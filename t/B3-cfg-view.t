use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);
use File::Temp qw(tempdir);

my $tmp = tempdir(CLEANUP => 1);
my ($cfg) = make_config(BACKUP_TMP_DIR => $tmp);
load_cgi($cfg); main::read_config();
no warnings 'once';

# --- registry <-> read_config() stay in sync ---------------------------------
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> };
    close($fh);
    my ($rc) = $src =~ /^sub read_config \{(.*?)^\}/ms;
    my %read;
    $read{$1} = 1 while $rc =~ /\$kv->\{(\w+)\}/g;
    $read{$1} = 1 while $rc =~ /\$cfg_int->\('(\w+)'/g;
    my ($urls) = $rc =~ /for my \$k \(qw\(([^)]*)\)\)/;
    $read{$_} = 1 for split ' ', ($urls // '');
    # @CFG_KEYS is a file lexical; reach it through cfg_view_rows on an empty
    # file (every registry key then appears as nonexistent).
    my $empty = "$tmp/empty.cfg"; open(my $e, '>', $empty) or die; close($e);
    my ($rows) = main::cfg_view_rows($empty);
    my %reg = map { $_->{key} => 1 } grep { $_->{type} eq 'key' } @$rows;
    is_deeply([sort keys %reg], [sort keys %read], 'registry lists exactly the keys read_config() reads');
    ok(!$read{REPOSITORY}, 'REPOSITORY is no longer read');
}

# --- rows: groups, statuses, masking, duplicates, nonexistent -----------------
my $c = "$tmp/view.cfg";
open(my $w, '>', $c) or die;
print $w <<'CFG';
# fetchconfig-web configuration
# --- fetchconfig paths ---
# explanatory comment (not a group)
DEVICE_TABLE            = /usr/local/fetchconfig/device_table
REPOSITORY              = /usr/local/fetchconfig/config
BACKUP_TIMEOUT          = 300

# --- empty group ---

# --- PostgreSQL user database ---
DBinst                  = fetchconfig
DBpass                  = "s3cr3t"
DBpasswd                = typo-secret
HTTPS_ENABLED           = yes
SESSION_TTL             = 100
SESSION_TTL             = 200
BACKUP_TMP_DIR          = relative/dir
DBpass changeme-no-equals
LOG_MAX_DEVICES         =
CFG
close($w);

my ($rows, $err) = main::cfg_view_rows($c);
ok(!$err, 'rows built');
my @groups = map { $_->{title} } grep { $_->{type} eq 'group' } @$rows;
is_deeply(\@groups, ['fetchconfig paths', 'PostgreSQL user database', 'Not in config file'],
          'groups from "# --- x ---" headings; empty group skipped; trailing nonexistent group');
my %k; for (grep { $_->{type} eq 'key' } @$rows) { push @{ $k{$_->{key}} }, $_ }
is($k{DEVICE_TABLE}[0]{status}, 'valid', 'valid key');
is($k{BACKUP_TIMEOUT}[0]{status}, 'valid', 'valid int');
is($k{BACKUP_TIMEOUT}[0]{default}, '120', 'default shown');
like($k{BACKUP_TIMEOUT}[0]{range}, qr/>= 0/, 'range shown');
is($k{REPOSITORY}[0]{status}, 'invalid', 'REPOSITORY invalid');
like($k{REPOSITORY}[0]{note}, qr/obsolete/, 'REPOSITORY marked obsolete');
is($k{DBpasswd}[0]{status}, 'invalid', 'unknown key invalid');
like($k{DBpasswd}[0]{note}, qr/unknown key/, 'unknown key note');
ok($k{DBpasswd}[0]{secret}, 'unknown password-like key is secret');
ok($k{DBpass}[0]{secret}, 'DBpass is secret');
is($k{DBpass}[0]{value}, 's3cr3t', 'quotes stripped like parse_config_file');
is($k{HTTPS_ENABLED}[0]{status}, 'invalid', 'bad 0|1 value invalid');
is($k{SESSION_TTL}[0]{status}, 'invalid', 'earlier duplicate invalid');
like($k{SESSION_TTL}[0]{note}, qr/overridden by line \d+/, 'duplicate note');
is($k{SESSION_TTL}[1]{status}, 'valid', 'last duplicate valid');
is($k{BACKUP_TMP_DIR}[0]{status}, 'invalid', 'relative path invalid');
is($k{LOG_MAX_DEVICES}[0]{status}, 'valid', 'empty int = default, valid');
my ($bad) = grep { $_->{type} eq 'key' && $_->{note} =~ /not "KEY = value"/ } @$rows;
ok($bad, 'malformed line listed');
unlike($bad->{key}, qr/changeme/, 'malformed line with "pass" hidden');
is($k{FETCHCONFIG_PATH}[0]{status}, 'nonexistent', 'missing key nonexistent');
like($k{FETCHCONFIG_PATH}[0]{note}, qr/required/, 'missing required key noted');
is($k{SUDO_BIN}[0]{default}, '/usr/bin/sudo', 'nonexistent shows default');

# --- rendered page ------------------------------------------------------------
{
    no warnings 'redefine';
    local *main::user_may_use_tools = sub { 1 };
    local *main::page_head = sub { '' }; local *main::page_foot = sub { '' };
    local *main::cfg_view_rows = sub { ($rows, undef) };
    my $o = ''; open(my $fh, '>', \$o); my $sv = select($fh);
    main::show_tool_show_cfg('admin');
    select($sv); close($fh);
    like($o, qr{<th>Status</th><th>Option</th><th>Value</th><th>Default</th><th>Range</th>}, 'column order');
    like($o, qr{<tr class="cfg-group"><td colspan="5">fetchconfig paths</td></tr>}, 'group row');
    like($o, qr{<tr class="cfg-invalid"><td class="cfg-st">invalid}, 'invalid row class');
    like($o, qr{<tr class="cfg-nonexistent">}, 'nonexistent row class');
    like($o, qr{<td class="cfg-key"[^>]*>DBpass</td><td class="cfg-val">\*\*\*\*</td>}, 'DBpass masked');
    unlike($o, qr/s3cr3t|typo-secret|changeme/, 'no secret leaks into the page');
    like($o, qr/invalid<\/span>/, 'invalid count highlighted');
}

# --- FATAL ERROR banner ---------------------------------------------------------
{
    my %kv; open(my $r, '<', $cfg) or die; while (<$r>) { chomp; my ($a, $b) = split /\s*=\s*/, $_, 2; $kv{$a} = $b if defined $b } close($r);
    my $tbl = $kv{DEVICE_TABLE};
    my $set = sub { open(my $t, '>', $tbl) or die; print $t @_; close($t); $main::_fatal_error_cache = undef; };

    $set->("cisco-ios sw1 10.0.0.1 user=x,pass=p\n");
    like(main::fatal_error_text(), qr/^No repository found in \Q$tbl\E/, 'no repository -> fatal');
    like(main::fatal_error_banner(), qr{<div class="fatal-error"><strong>FATAL ERROR:</strong> No repository found}, 'banner HTML');

    $set->("default: cisco-ios repository=/r\ncisco-ios sw1 10.0.0.1 user=x,pass=p\n");
    is(main::fatal_error_text(), '', 'default: repository= -> no fatal');
    is(main::fatal_error_banner(), '', 'no banner');

    $set->("cisco-ios sw1 10.0.0.1 user=x,pass=p,repository=/r\n");
    is(main::fatal_error_text(), '', 'device repository= -> no fatal');

    $set->("# repository=/r only in a comment\ncisco-ios sw1 10.0.0.1 user=x\n");
    like(main::fatal_error_text(), qr/No repository found/, 'comment does not count');

    unlink $tbl; $main::_fatal_error_cache = undef;
    like(main::fatal_error_text(), qr/^Device table not found: \Q$tbl\E \(/, 'missing table -> fatal with reason');

    # device_repository: no global fallback any more
    $set->("cisco-ios sw1 10.0.0.1 user=x\ndefault: hp sw repository=/r\n");
    ok(!defined main::device_repository('sw1'), 'device without repository -> undef (no fallback)');
    $set->("cisco-ios sw1 10.0.0.1 user=x\ndefault: cisco-ios repository=/a\ndefault: cisco-ios repository=/b\n");
    is(main::device_repository('sw1'), '/b', 'last model default: wins (fetchconfig semantics)');

    # Backup Now temp table: directives + device line, no injected repository.
    $set->("default: cisco-ios user=u,repository=/modelrepo\ncisco-ios sw1 10.0.0.1 pass=p\n");
    no warnings 'redefine';
    my $seen;
    local *main::run_command_capture = sub {
        my ($tf) = grep { /^-devices=/ } @_; $tf =~ s/^-devices=//;
        open(my $t, '<', $tf) or die; local $/; $seen = <$t>; close($t);
        return ('', 0, undef, 0);
    };
    main::run_backup_now('sw1');
    is($seen, "default: cisco-ios user=u,repository=/modelrepo\ncisco-ios sw1 10.0.0.1 pass=p\n",
       'Backup Now table = directives + device line (no repository override)');
}

done_testing();
