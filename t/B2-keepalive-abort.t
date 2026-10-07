use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use File::Temp qw(tempdir);
use POSIX ();

my $tmpdir = tempdir(CLEANUP => 1);
my ($cfg) = make_config(BACKUP_TIMEOUT => 30, BACKUP_TMP_DIR => $tmpdir);
load_cgi($cfg); main::read_config();
no warnings 'once';

my $sh = -x '/bin/sh';

# Keepalive: called immediately (flushes the page start) and then every
# $KEEPALIVE_INTERVAL seconds while the command runs.
SKIP: {
    skip "no /bin/sh", 4 unless $sh;
    local $main::KEEPALIVE_INTERVAL = 1;
    my $n = 0;
    local $main::RUN_KEEPALIVE = sub { $n++; 1 };
    my ($out, $status, $err, $aborted) = main::run_command_capture('/bin/sh', '-c', 'sleep 3; echo done');
    like($out, qr/done/, 'keepalive: output captured');
    is($status, 0, 'keepalive: exit status 0');
    ok(!$err && !$aborted, 'keepalive: no error, not aborted');
    cmp_ok($n, '>=', 3, "keepalive: called immediately and periodically ($n calls in ~3s)");
}

# No keepalive set: never called (callers that have not printed a header).
SKIP: {
    skip "no /bin/sh", 1 unless $sh;
    local $main::RUN_KEEPALIVE;
    my ($out) = main::run_command_capture('/bin/sh', '-c', 'echo plain');
    like($out, qr/plain/, 'no keepalive: plain run works');
}

# A failing keepalive write (client gone) aborts: child killed, partial output
# kept, status undef, error names the client disconnect.
SKIP: {
    skip "no /bin/sh", 5 unless $sh;
    local $main::KEEPALIVE_INTERVAL = 1;
    my $n = 0;
    local $main::RUN_KEEPALIVE = sub { ++$n < 2 };   # 1st ok, 2nd fails
    my $t0 = time();
    my ($out, $status, $err, $aborted) = main::run_command_capture('/bin/sh', '-c', 'echo $$; echo partial; exec sleep 30');
    ok($aborted, 'client gone: aborted');
    like($err, qr/client disconnected/, 'client gone: error text');
    ok(!defined $status, 'client gone: status undef');
    like($out, qr/partial/, 'client gone: partial output kept');
    my ($cpid) = $out =~ /^(\d+)/;
    ok($cpid && !kill(0, $cpid), 'client gone: child process terminated');
    diag("abort took " . (time() - $t0) . "s") if time() - $t0 > 5;
}

# Real broken pipe: the selected output is a pipe whose reader has gone (as
# when Apache drops the CGI). html_keepalive's write fails with EPIPE instead
# of killing the process (SIGPIPE ignored during the run) and the run aborts.
SKIP: {
    skip "no /bin/sh", 3 unless $sh;
    local $main::KEEPALIVE_INTERVAL = 1;
    local $main::RUN_KEEPALIVE = main::html_keepalive();
    pipe(my $r, my $w) or die "pipe: $!";
    close($r);
    my $sv = select($w);
    # The very first keepalive already fails, so the child may be killed
    # before it runs at all; it records its pid in a file if it got that far.
    my $pidf = "$tmpdir/bp.pid";
    my ($out, $status, $err, $aborted) = main::run_command_capture('/bin/sh', '-c', "echo \$\$ > $pidf; exec sleep 30");
    select($sv); { local $SIG{PIPE} = 'IGNORE'; close($w); }
    ok($aborted, 'broken pipe: run aborted, process survived');
    like($err, qr/client disconnected/, 'broken pipe: reported as client disconnect');
    my $cpid; if (open(my $pf, '<', $pidf)) { $cpid = <$pf>; chomp $cpid if defined $cpid; }
    ok(!$cpid || !kill(0, $cpid), 'broken pipe: child process terminated');
}

# SIGTERM from the web server during the run: caught, child killed, aborted.
SKIP: {
    skip "no /bin/sh", 4 unless $sh;
    local $main::RUN_KEEPALIVE;
    my $parent = $$;
    my $killer = fork();
    die "fork: $!" unless defined $killer;
    if (!$killer) { sleep 1; kill('TERM', $parent); POSIX::_exit(0); }
    my $t0 = time();
    my ($out, $status, $err, $aborted) = main::run_command_capture('/bin/sh', '-c', 'echo $$; exec sleep 30');
    waitpid($killer, 0);
    ok($aborted, 'SIGTERM: aborted');
    like($err, qr/terminated by the web server/, 'SIGTERM: error text');
    cmp_ok(time() - $t0, '<', 10, 'SIGTERM: returned promptly');
    my ($cpid) = $out =~ /^(\d+)/;
    ok($cpid && !kill(0, $cpid), 'SIGTERM: child process terminated');
}

# Signal handlers are restored after the run (local), so a later SIGTERM is
# not swallowed by a stale handler.
is($SIG{TERM}, undef, 'SIGTERM handler restored after run');

# The child must not inherit SIGPIPE=IGNORE from the run. This reads the
# Linux-format /proc/<pid>/status "SigIgn:" bitmask, which only exists on
# Linux; AIX (and other non-Linux) /proc use a different, binary format, so
# skip there. The portable broken-pipe and SIGTERM tests above already prove
# the child gets default signal behaviour -- this is just a direct check of
# the mask where the OS exposes it as text.
SKIP: {
    skip "Linux-format /proc not available", 1
        unless $sh && -r "/proc/$$/status"
            && do { local (@ARGV, $/) = ("/proc/$$/status"); (<> // '') =~ /^SigIgn:/m };
    my ($out) = main::run_command_capture('/bin/sh', '-c', 'grep SigIgn /proc/$$/status');
    my ($mask) = $out =~ /SigIgn:\s*([0-9a-f]+)/i;
    ok(defined $mask && !(hex(substr($mask, -4)) & (1 << (13 - 1))), 'child: SIGPIPE not ignored');
}

# html_keepalive writes an HTML comment to the selected handle; true on success.
{
    my $o = ''; open(my $c, '>', \$o); my $sv = select($c);
    my $ok = main::html_keepalive()->();
    select($sv); close($c);
    ok($ok, 'html_keepalive: returns true on success');
    like($o, qr/^<!-- keepalive -->\n\z/, 'html_keepalive: writes an HTML comment');
}

# show_backup_now: an aborted run is audited ABORTED and renders nothing more.
{
    no warnings 'redefine';
    my @A;
    local *main::audit = sub { my %f = @_; push @A, $f{detail}; };
    local *main::page_head = sub { '' }; local *main::page_foot = sub { '' };
    local *main::valid_id = sub { 1 };
    local *main::copy_button_html = sub { '' }; local *main::copy_button_script = sub { '' };
    local *CGI::param = sub { my ($s, $k) = @_; return 'sw1' if $k eq 'dev'; return; };
    my $seen_ka;
    local *main::run_backup_now = sub { $seen_ka = ref $main::RUN_KEEPALIVE; ("info: partial\n", undef, "Run aborted", 1) };
    my $o = ''; open(my $c, '>', \$o); my $sv = select($c); main::show_backup_now('admin'); select($sv); close($c);
    is($seen_ka, 'CODE', 'show_backup_now: keepalive set during the run');
    ok(!defined $main::RUN_KEEPALIVE, 'show_backup_now: keepalive cleared afterwards');
    like($A[0], qr/^ABORTED:/, 'show_backup_now: aborted run audited ABORTED');
    unlike($o, qr/info: partial|finished successfully|FAILED/, 'show_backup_now: nothing rendered after abort');
}

# Empty Backup Cleanup data endpoint: header is printed BEFORE the scan runs
# (so the keepalive can flow), keepalive set during the run; abort audited.
{
    no warnings 'redefine';
    my @A;
    local *main::audit = sub { my %f = @_; push @A, $f{detail}; };
    local *main::page_head = sub { '' }; local *main::page_foot = sub { '' };
    local *main::top_bottom_nav = sub { '' }; local *main::user_may_use_tools = sub { 1 };
    local *main::copy_button_html = sub { '' }; local *main::copy_button_script = sub { '' };
    local *CGI::param = sub { return; };
    my ($o, $at_run, $seen_ka) = ('');
    local *main::run_empty_bk_delete = sub { $at_run = $o; $seen_ka = ref $main::RUN_KEEPALIVE; ("", undef, "Run aborted", 1) };
    open(my $c, '>', \$o); my $sv = select($c); main::do_empty_bk_delete_data('admin'); select($sv); close($c);
    like($at_run // '', qr/Content-Type/, 'empty_bk: header printed before the scan');
    is($seen_ka, 'CODE', 'empty_bk: keepalive set during the scan');
    like($A[0], qr/^ABORTED:/, 'empty_bk delete: aborted run audited ABORTED');
}

# Stale Backup Now temp tables (cleartext credentials) are swept; fresh ones,
# foreign names and non-files are kept.
{
    my $old   = "$tmpdir/fcweb-dev-AbCd1234.tbl";
    my $fresh = "$tmpdir/fcweb-dev-ZyXw9876.tbl";
    my $other = "$tmpdir/other-file.tbl";
    for ($old, $fresh, $other) { open(my $f, '>', $_) or die; print $f "x\n"; close $f; }
    my $past = time() - (30 + 300 + 60);
    utime($past, $past, $old, $other);
    mkdir("$tmpdir/fcweb-dev-DirDir12.tbl");
    utime($past, $past, "$tmpdir/fcweb-dev-DirDir12.tbl");
    main::sweep_stale_backup_tables();
    ok(!-e $old,   'sweep: stale temp table removed');
    ok(-e $fresh,  'sweep: fresh temp table kept');
    ok(-e $other,  'sweep: unrelated file kept');
    ok(-d "$tmpdir/fcweb-dev-DirDir12.tbl", 'sweep: directory with matching name kept');
}

done_testing();
