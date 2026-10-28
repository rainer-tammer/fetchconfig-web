use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# Tools -> Show schedule (2.08): the read-only cron viewer and the crontab-entry
# builder. Covers the pure parsing/formatting helpers, the fetchconfig-only
# match, the CRON_USER config type, and the structural invariants (read-only
# helper, match on FETCHCONFIG_PATH/FETCHCONFIG_BIN, wiring).

my ($cfg, $dir, $fcp) = make_config(CRON_USER => 'root');   # root exists everywhere
load_cgi($cfg); main::read_config();

# FETCHCONFIG_BIN_FULL is a file-scoped lexical inside the cgi, not a package
# global, so reconstruct it from the config the way read_config does.
my $BIN = "$fcp/fetchconfig.pl";
ok($BIN ne '', "fetchconfig binary path is ($BIN)");

# ---------------------------------------------------------------------------
# cron_describe: the common cases, and "custom" for anything else.
# ---------------------------------------------------------------------------
is(main::cron_describe('0','0','*','*','*'),  'daily at 00:00',          'daily');
is(main::cron_describe('30','1','*','*','*'), 'daily at 01:30',          'daily, other time');
is(main::cron_describe('0','0','*','*','0'),  'weekly on Sunday at 00:00','weekly (dow 0 = Sunday)');
is(main::cron_describe('0','0','*','*','7'),  'weekly on Sunday at 00:00','weekly (dow 7 = Sunday too)');
is(main::cron_describe('5','2','*','*','1'),  'weekly on Monday at 02:05','weekly, Monday');
is(main::cron_describe('0','3','1','*','*'),  'monthly on day 1 at 03:00','monthly');
is(main::cron_describe('0','0','*','6','*'),  'custom schedule',          'a month restriction is custom');
is(main::cron_describe('*/15','*','*','*','*'),'custom schedule',         'a step field is custom');

# ---------------------------------------------------------------------------
# cron_parse_schedule: five time fields + command, or undef.
# ---------------------------------------------------------------------------
my $p = main::cron_parse_schedule("0 0 * * * $BIN -devices=device_table -P 1");
ok($p, 'a five-field line parses');
is($p->{min}, '0',  'minute'); is($p->{dow}, '*', 'dow');
like($p->{cmd}, qr/\Q$BIN\E/, 'command captured');
ok(!main::cron_parse_schedule('MAILTO=root'),            'env line does not parse');
ok(!main::cron_parse_schedule('@daily /usr/bin/thing'),  '@shortcut does not parse');
ok(!main::cron_parse_schedule('0 0 * *'),                'too few fields does not parse');
ok(!main::cron_parse_schedule('x 0 * * * cmd'),          'non-cron field does not parse');

# ---------------------------------------------------------------------------
# cron_split_redirect: stdout redirect (1> / >) is the log, not 2>.
# ---------------------------------------------------------------------------
{
    my ($disp, $log) = main::cron_split_redirect(
        "$BIN -devices=device_table -P 1 1>/var/log/getconfig.log 2>&1");
    is($disp, "$BIN -devices=device_table -P 1", 'command without the redirect tail');
    is($log,  '/var/log/getconfig.log',          'log target from 1>');
    my (undef, $log2) = main::cron_split_redirect("$BIN >/tmp/x.log");
    is($log2, '/tmp/x.log', 'bare > is also a log target');
}

# ---------------------------------------------------------------------------
# cron_match_entries: keep only fetchconfig lines (matched on the full
# FETCHCONFIG_PATH/FETCHCONFIG_BIN), keep commented ones (flagged), and never
# leak an unrelated job.
# ---------------------------------------------------------------------------
{
    my $crontab = join "\n",
        '# a header comment',
        'MAILTO=root',
        "0 0 * * * $BIN -devices=device_table -P 1 1>/var/log/gc.log 2>&1",
        "#30 2 * * 0 $BIN -devices=device_table -P 1 1>/var/log/gc.log 2>&1",
        '15 3 * * * /usr/bin/other-job --password=SECRET',
        '';
    my $rows = main::cron_match_entries($crontab);
    is(scalar @$rows, 2, 'two fetchconfig rows (active + commented), unrelated job excluded');
    is($rows->[0]{commented}, 0, 'first row active');
    is($rows->[0]{when}, 'daily at 00:00', 'active row described');
    is($rows->[0]{log}, '/var/log/gc.log', 'active row log target');
    is($rows->[1]{commented}, 1, 'second row flagged disabled');
    ok(!(grep { $_->{cmd} =~ /other-job|SECRET/ } @$rows),
       "an unrelated job's command (and its secret) never appears");
}

# ---------------------------------------------------------------------------
# CRON_USER config type (cronuser): optional, format-validated.
# ---------------------------------------------------------------------------
{
    my $ent = [ 'CRON_USER', 'cronuser', '(empty: tool not configured)', 'system user name' ];
    is(main::cfg_value_problem($ent, ''),        undef, 'empty CRON_USER is allowed (optional)');
    is(main::cfg_value_problem($ent, 'fetchconfig'), undef, 'a normal user name is accepted');
    is(main::cfg_value_problem($ent, 'svc_bk$'), undef, 'a trailing $ (machine account) is accepted');
    ok(main::cfg_value_problem($ent, 'bad;user'), 'a shell metacharacter is rejected');
    ok(main::cfg_value_problem($ent, '1abc'),     'a leading digit is rejected');
    ok(main::cfg_value_problem($ent, 'x' x 40),   'an over-long name is rejected');
}

# ---------------------------------------------------------------------------
# Structural invariants.
# ---------------------------------------------------------------------------
my $src = do { open(my $fh, '<', cgi_path()) or die $!; local $/; <$fh> };

like($src, qr/\[\s*'CRON_USER',\s*'cronuser'/, 'CRON_USER is a registered config key');
like($src, qr/action eq 'tool_schedule'\s*\)\s*\{\s*\n\s*show_tool_schedule/,
     'tool_schedule is dispatched');
like($src, qr/\QShow schedule\E.*\?action=tool_schedule/, 'Show schedule is in the Tools menu');

# Q2: the viewer matches on the full FETCHCONFIG_PATH/FETCHCONFIG_BIN path, not
# just the directory -- so a line must actually run fetchconfig.pl to show.
like($src, qr/index\(\$body,\s*\$FETCHCONFIG_BIN_FULL\)/,
     'fetchconfig lines are matched on FETCHCONFIG_BIN_FULL');

# The tool is read-only: it reaches the crontab only through the helper's
# list-cron subcommand, and never writes one.
like($src, qr/'list-cron',\s*\$CRON_USER/, 'viewer calls the helper list-cron with CRON_USER');
# The cgi reaches cron ONLY through the helper's list-cron; it never invokes
# the privileged helper with any other cron-related subcommand. (The literal
# "crontab -e" DOES appear in the cgi -- but only as on-screen guidance text
# telling the admin how to add the line themselves, never run.)
unlike($src, qr/run_privileged\([^)]*'list-cron'[^)]*\n[^)]*'(?:install|revert|delete)-cron'/,
       'the cgi never runs a privileged cron write');

# The privileged helper's list-cron is read-only and checks the user exists.
my $helper = do {
    open(my $fh, '<', "$FindBin::Bin/../fetchconfig-web-install-template.pl") or die $!;
    local $/; <$fh>;
};
like($helper, qr/\$cmd eq 'list-cron'/,          'helper has a list-cron subcommand');
like($helper, qr/getpwnam\(\$cuser\)/,           'helper verifies the user exists');
like($helper, qr/\$crontab,\s*'-l'/,             'helper runs crontab -l (read-only)');
unlike($helper, qr/\$crontab,\s*'-[er]'/,        'helper never runs crontab -e / -r');
# Linux robustness: list-cron forces a C locale so the "no crontab" message is
# recognised on a non-English host, and resolves crontab by absolute path.
like($helper, qr/\$ENV\{LC_ALL\}\s*=\s*'C'/,     'helper forces LC_ALL=C for crontab');
like($helper, qr{/usr/bin/crontab},              'helper resolves crontab by absolute path');

done_testing();
