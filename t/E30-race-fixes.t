use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.18.1: concurrency hardening.
#   Fix 1  device-table torn read -- readers take a SHARED lock on the writer
#          sidecar; writers that already hold LOCK_EX read via the unlocked
#          variant so they can't self-deadlock on a second handle.
#   Fix 2  login throttle lost-update -- the failure counter is incremented
#          atomically in SQL ("failures = failures + 1"), no SELECT-then-UPDATE.
#   Fix 3  dashboard-cleanup TOCTOU -- the orphan id list is re-verified against
#          the (now shared-locked) device table inside the delete handler, so a
#          device re-added in the meantime is not wiped.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# === Fix 1: helpers present, single-sourced lock path, split reader =========
ok(main->can('_device_table_lock_file'),   'lock-path helper defined');
ok(main->can('_shared_lock_device_table'), 'shared-lock helper defined');
ok(main->can('slurp_device_table_unlocked'),'unlocked reader defined');
ok(main->can('slurp_device_table'),         'public (locked) reader defined');

# lock_device_table and the shared helper must derive the path from the same
# single source, or the exclusive and shared locks would be on different files.
like($src, qr/sub lock_device_table \{\s*\n\s*my \$lock = _device_table_lock_file\(\);/,
     'lock_device_table uses the single-source lock path');
like($src, qr/sub _shared_lock_device_table \{.*?_device_table_lock_file\(\).*?LOCK_SH/s,
     'shared helper locks the same sidecar with LOCK_SH');

# public slurp wraps the unlocked body behind a shared lock
like($src, qr/sub slurp_device_table \{.*?_shared_lock_device_table\(\).*?slurp_device_table_unlocked\(\)/s,
     'public slurp takes a shared lock then delegates to the unlocked read');

# the hot parsed reader is shared-locked too
my ($rdi) = $src =~ /sub read_device_ids \{(.*?)\n\}/s;
ok($rdi, 'located read_device_ids');
like($rdi, qr/_shared_lock_device_table\(\)/, 'read_device_ids takes a shared lock for the read');

# every writer that holds LOCK_EX reads via the UNLOCKED variant (no deadlock).
# There are exactly four such re-reads; none may use the public locking slurp.
for my $spec (['do_restore_backup'], ['do_edit_site'], ['do_save_table'], ['do_bulk_save']) {
    my ($name) = @$spec;
    my ($body) = $src =~ /sub \Q$name\E \{(.*?)\n\}/s;
    ok($body, "located $name");
    # the re-read inside the locked section is the unlocked variant ...
    like($body, qr/slurp_device_table_unlocked\(\)/, "$name re-reads with the unlocked variant");
    # ... and does NOT call the public locking slurp while holding LOCK_EX
    unlike($body, qr/[^_]slurp_device_table\(\)/, "$name never calls the locking slurp under LOCK_EX");
}

# functional: the locked public read still returns the file's bytes (the shared
# lock path must not break ordinary reads). The cgi's $DEVICE_TABLE is a
# file-scoped lexical set by read_config() to <config dir>/device_table.
{
    require File::Spec; require File::Basename;
    my $dt = File::Spec->catfile(File::Basename::dirname($cfg), 'device_table');
    open(my $w, '>', $dt) or die $!;
    print $w "cisco-ios r1 10.0.0.1 user admin pass x\n";
    close $w;
    my ($content, $err) = main::slurp_device_table();
    is($err, undef, 'locked slurp: no error');
    like($content, qr/cisco-ios r1 10\.0\.0\.1/, 'locked slurp returns the table bytes');
    my ($uc, $uerr) = main::slurp_device_table_unlocked();
    is($uerr, undef, 'unlocked slurp: no error');
    is($uc, $content, 'unlocked and locked reads agree');
}

# === Fix 2: atomic increment, no SELECT-then-UPDATE ========================
my ($lrf) = $src =~ /sub login_record_failure \{(.*?)\n\}/s;
ok($lrf, 'located login_record_failure');
like($lrf, qr/SET failures = failures \+ 1/, 'increment is atomic (failures = failures + 1)');
unlike($lrf, qr/SET failures = \?/,          'no "SET failures = ?" (old read-then-write)');
unlike($lrf, qr/_login_fail_state/,          'no SELECT of the current count inside the incrementer');

# behavioural: UPDATE-miss -> INSERT -> second failure -> UPDATE-hit increments.
{
    package E30Dbh;
    sub new { bless { ac => 1, rows => {}, upd_sql => '' }, shift }
    sub begin_work { 0 }     # AutoCommit stays on in this fake; begin/commit are no-ops
    sub commit     { 1 }
    sub rollback   { 1 }
    sub do {
        my ($self, $sql, $attr, @args) = @_;
        if ($sql =~ /^\s*UPDATE login_attempts SET failures = failures \+ 1/) {
            $self->{upd_sql} = $sql;
            my $k = "$args[0]\0$args[1]";     # kind \0 keyval
            return '0E0' unless exists $self->{rows}{$k};   # 0 rows, no such row yet
            $self->{rows}{$k}++;              # server-side increment
            return 1;
        }
        if ($sql =~ /^\s*INSERT INTO login_attempts/) {
            my $k = "$args[0]\0$args[1]";
            $self->{rows}{$k} = 1;            # VALUES (?, ?, 1, now())
            return 1;
        }
        return 1;
    }
}
{
    my $dbh = E30Dbh->new;
    $dbh->{AutoCommit} = 1;
    main::login_record_failure($dbh, 'user', 'alice');
    is($dbh->{rows}{"user\0alice"}, 1, 'first failure inserts with failures = 1');
    main::login_record_failure($dbh, 'user', 'alice');
    is($dbh->{rows}{"user\0alice"}, 2, 'second failure increments to 2 (no lost update)');
    like($dbh->{upd_sql}, qr/failures = failures \+ 1/, 'the UPDATE used the atomic form');
}

# === Fix 3: cleanup re-verifies table membership before deleting ===========
my ($del) = $src =~ /sub do_dashboard_cleanup_delete \{(.*?)\n\}/s;
ok($del, 'located do_dashboard_cleanup_delete');
like($del, qr/slurp_device_table\(\)/,          'cleanup re-reads the device table (shared-locked)');
like($del, qr/\@ids = grep \{ !\$in_table\{\$_\} \} \@ids;/,
     'cleanup drops ids that were re-added to the table');
like($del, qr/re-added in the meantime/,        'cleanup reports when every orphan was re-added');
# the re-read must happen before the id placeholders are built for the DELETE
like($del, qr/\@ids = grep.*?my \$ph = join\(','/s,
     're-verify runs before the DELETE placeholder list is built');

done_testing();
