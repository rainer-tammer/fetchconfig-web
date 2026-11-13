use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source);

# --------------------------------------------------------------------------
# Rename device-id (Setup devices -> Rename device-id), new in 2.14.0.
# Exercises the engine-version feature gate, the access/validation helpers,
# the web-owned device_notes migration fallback, and the source wiring
# (menu, dispatch, %STATE_CHANGING) plus the DB grant/migration pieces.
# --------------------------------------------------------------------------

my ($cfg, $dir, $fcp) = make_config();
my %kv; { open(my $r,'<',$cfg); while(<$r>){chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b;} close($r); }
open(my $w, '>', $kv{DEVICE_TABLE}) or die "write table: $!";
print $w <<'DT';
# DEFAULT OPTIONS SECTION
default: cisco-ios user=a,pass=b,repository=/r,keep=5
# DEVICES SECTION
cisco-ios sw-ber 10.0.0.1 user=x,pass=y,repository=/r,keep=5
generic   fw-ham 10.0.0.2 user=x,pass=y,repository=/r,keep=5
DT
close($w);

load_cgi($cfg); main::read_config();

# --- constants ------------------------------------------------------------
is(main::APP_VERSION(),          '2.18.1', 'APP_VERSION bumped to 2.18.1');
is(main::APP_VERSION_INTERNAL(), '2.18.1', 'APP_VERSION_INTERNAL bumped to 2.18.1');
is(main::MIN_FETCHCONFIG_VERSION(), '9.80', 'MIN_FETCHCONFIG_VERSION -> 9.80 (SNMP inventory / fw_version)');
is(main::RENAME_MIN_FETCHCONFIG_VERSION(), '9.78', 'rename needs engine 9.78');

# --- feature gate (engine version) ----------------------------------------
{
    no warnings 'redefine';
    local *main::fetchconfig_version_cached = sub { undef };
    is(main::rename_feature_available(), 0, 'gate closed when version undetermined');
    local *main::fetchconfig_version_cached = sub { '9.77' };
    is(main::rename_feature_available(), 0, 'gate closed on 9.77');
    local *main::fetchconfig_version_cached = sub { '9.78' };
    is(main::rename_feature_available(), 1, 'gate open on 9.78');
    local *main::fetchconfig_version_cached = sub { '9.80' };
    is(main::rename_feature_available(), 1, 'gate open on 9.80');
}

# --- id validation rules used by the handler ------------------------------
ok( main::valid_id('core-sw01'),  'normal id valid');
ok(!main::valid_id('-leading'),   'leading dash rejected (argv-safe)');
ok('...' =~ /^\.+\z/,             'all-dots id detected by the handler regex');
ok(!('a.b' =~ /^\.+\z/),          'dotted-but-not-all-dots id passes the all-dots test');

# --- device-id enumeration for the picker / pre-check ---------------------
my ($set, $sorted, $err) = main::rename_all_device_ids();
ok(!$err, 'rename_all_device_ids: no error');
ok($set->{'sw-ber'} && $set->{'fw-ham'}, 'both device ids present in the set');
is(scalar(@$sorted), 2, 'picker list has both ids');

# --- device_notes migration fallback (DB unavailable) ---------------------
{
    no warnings 'redefine', 'once';
    local *main::db_connect = sub { undef };
    is(main::rename_migrate_device_notes('old','new'),
       'notes not migrated (database unavailable)',
       'device_notes migration degrades gracefully without a DB');
}

# --- source wiring --------------------------------------------------------
my $src = do { local $/; open(my $f,'<',cgi_path()) or die $!; <$f> };
like($src, qr/\$su->\('Rename device-id', '\?action=rename_device_id'\)\s*\n\s*if \$unrestricted && rename_feature_available\(\)/,
     'menu item gated on unrestricted + engine version');
like($src, qr/action eq 'rename_device_id'/,  'dispatch: rename_device_id (GET form)');
like($src, qr/action eq 'rename_device_do'/,  'dispatch: rename_device_do (POST)');
like($src, qr/action eq 'replay_db_change'/,  'dispatch: replay_db_change (POST)');

# Privileged (sudo) execution: rename + replay go through run_fetchconfig_priv.
like($src, qr/run_fetchconfig_priv\(\@args\)/,                'rename runs via the sudo helper');
like($src, qr/audit_record_device_table_token\(undef, \$user\)/, 'rename refreshes the external-change token (no false "modified outside" warning)');
like($src, qr/run_fetchconfig_priv\('-devices=' \. \$DEVICE_TABLE, '--replay-db-change'\)/, 'replay runs via the sudo helper');
like($src, qr/sub run_fetchconfig_priv/,                      'run_fetchconfig_priv exists');
like($src, qr/\$USE_SUDO_FOR_BACKUP_NOW\s*\n?\s*\?\s*\(\$SUDO_BIN, '-n', \$FETCHCONFIG_BIN_FULL/, 'priv runner prepends sudo -n when enabled');

# Behaviour: with sudo enabled (the default), the command is
# "<sudo> -n <fetchconfig.pl> <args...>" and carries -devices= and the rename flag.
{
    no warnings 'redefine', 'once';
    my @seen;
    local *main::run_capture_cmd = sub { @seen = @_; return ('', '', 0, undef); };
    main::run_fetchconfig_priv('-devices=/x', '--rename-device-id', '--old=a', '--new=b');
    like($seen[0], qr{sudo$},            'priv command starts with the sudo binary');
    is($seen[1], '-n',                   'sudo -n (non-interactive)');
    ok((grep { $_ eq '-devices=/x' } @seen),        'priv command keeps -devices=');
    ok((grep { $_ eq '--rename-device-id' } @seen), 'priv command keeps --rename-device-id');
}

# Device-table editor: existing device's Device-ID is read-only; a new (JS) one is not.
my $card = main::render_record_card('d0', { kind=>'device', model=>'generic', id=>'sw-ber', host=>'h', opts=>[] }, 'device');
like($card, qr/name="d0_id"[^>]*\breadonly\b/,            'existing device Device-ID is readonly');
like($card, qr/name="d0_id"[^>]*Rename device-id/,        'read-only id carries the rename tooltip');
like($src,  qr/name="' \+ rk \+ '_id" value="" size="32">/, 'new (Add device) card Device-ID stays editable (no readonly)');
# The GET form action must NOT be POST/CSRF-guarded; the two "do" actions must be.
like($src, qr/rename_device_do\n\s*replay_db_change\n\);/, 'both do-actions are state-changing');
unlike($src, qr/^\s*rename_device_id\s*$/m, 'the GET form action is not in %STATE_CHANGING');

# --- DB side: dbsetup grants + migration ----------------------------------
my $ds = do { local $/; open(my $f,'<','fetchconfig-web-dbsetup.pl') or die $!; <$f> };
like($ds, qr/'2\.14', 'fetchconfig-web-dbupdate-2\.14\.sql'/, '@UPDATES registers the 2.14 migration');
# Version-aware grants: column-scoped on 8.4+, whole-table below 8.4.
like($ds, qr/pg_server_version/,                             'do_grants detects the server version');
like($ds, qr/>= 80400/,                                      'do_grants branches on 8.4');
like($ds, qr/GRANT UPDATE \(dev_id\) ON backup_runs TO \$qw/,'do_grants: 8.4+ column grant on backup_runs');
like($ds, qr/expired, expired_at, dev_id, lines_added, lines_removed/, 'do_grants: 8.4+ dev_id in backup_versions column grant');
like($ds, qr/GRANT UPDATE ON backup_runs TO \$qw/,           'do_grants: <8.4 whole-table UPDATE on backup_runs');
like($ds, qr/GRANT UPDATE ON backup_versions TO \$qw/,       'do_grants: <8.4 whole-table UPDATE on backup_versions');

ok(-f 'fetchconfig-web-dbupdate-2.14.sql', 'the 2.14 migration file exists');
my $sql = do { local $/; open(my $f,'<','fetchconfig-web-dbupdate-2.14.sql') or die $!; <$f> };
like($sql, qr/server_version_num/,                         'migration detects the server version');
like($sql, qr/pgver >= 80400/,                             'migration branches on 8.4');
like($sql, qr/GRANT UPDATE \(dev_id\) ON backup_runs/,     'migration: 8.4+ column grant on backup_runs');
like($sql, qr/GRANT UPDATE \(dev_id\) ON backup_versions/, 'migration: 8.4+ column grant on backup_versions');
like($sql, qr/'GRANT UPDATE ON backup_runs     TO '/,      'migration: <8.4 whole-table fallback on backup_runs');
like($sql, qr/'GRANT UPDATE ON backup_versions TO '/,      'migration: <8.4 whole-table fallback on backup_versions');
like($sql, qr/INSERT INTO schema_migrations.*2\.14/s,      'migration records the 2.14 ledger id');

# Transcript collapses the "registering model:" preamble like the other views.
{
    my $err = "fetchconfig.pl: info: version 9.78\n"
            . join('', map { "fetchconfig.pl: debug: registering model: m$_\n" } 1..26)
            . "fetchconfig.pl: info: would rename dir: a -> b\n";
    my $th = main::rename_transcript_html('', $err);
    like($th,   qr/\d+ models registered/,            'transcript collapses registering-model lines');
    unlike($th, qr/registering model: m5\b/,          'individual registering-model lines are dropped');
    like($th,   qr/would rename dir/,                 'meaningful transcript lines are kept');
}

done_testing();
