use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# Backup-Now success/failure detection (backup_run_failed).
#
# Regression: an INITIAL backup of an aruba-cx-ssh device logs a benign
#   fetchconfig.pl: error: aruba-cx-ssh: there is no latest config
# line while the fetch still succeeds (status = initial, email = "initial").
# The old substring heuristic flagged that as FAILED. The .status backup_state
# is now authoritative.

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();

# The exact benign log from the field report (initial backup, succeeded).
my $initial_log = <<'LOG';
fetchconfig.pl: info: version 9.71
fetchconfig.pl: debug: loading device list
fetchconfig.pl: error: aruba-cx-ssh: there is no latest config
fetchconfig.pl: info: -----[sphe352879.net.schuler.de]-----
fetchconfig.pl: dev=sphe352879.net.schuler.de: debug: aruba-cx-ssh: fetched: 558 lines
fetchconfig.pl: info: done
LOG

# A genuine failure transcript (bad enable, no fetch).
my $fail_log = <<'LOG';
fetchconfig.pl: info: version 9.71
fetchconfig.pl: info: -----[rtr01]-----
fetchconfig.pl: dev=rtr01: error: cisco-ios: could not enter enable mode
fetchconfig.pl: info: done
LOG

# --- .status backup_state is authoritative (any non-undef state) ---
is(main::backup_run_failed(undef, $initial_log, 'initial'),   0, 'state=initial => success despite benign error: line');
is(main::backup_run_failed(undef, $initial_log, 'success'),   0, 'state=success => success');
is(main::backup_run_failed(undef, '',           'unchanged'), 0, 'state=unchanged => success');
is(main::backup_run_failed(undef, $initial_log, 'Initial'),   0, 'state is case-insensitive');
is(main::backup_run_failed(undef, $fail_log,    'failed'),    1, 'state=failed => failure');
# Status wins even if the log looks clean/dirty the other way.
is(main::backup_run_failed(undef, $fail_log,    'success'),   0, 'status trusted over a dirty log');

# --- hard error always fails, regardless of state ---
is(main::backup_run_failed('backup timed out after 120s', $initial_log, 'initial'), 1, 'hard error => failure');

# --- no status file: fall back to the log, benign line ignored ---
is(main::backup_run_failed(undef, $initial_log, undef), 0, 'no status + only benign error: line => success');
is(main::backup_run_failed(undef, $fail_log,    undef), 1, 'no status + real error: line => failure');
is(main::backup_run_failed(undef, "all good\nbackup_state = failed\n", undef), 1, 'no status + backup_state=failed in log => failure');
is(main::backup_run_failed(undef, "info: -----[x]-----\ninfo: done\n",  undef), 0, 'no status + clean log => success');
is(main::backup_run_failed(undef, '',    undef), 0, 'no status + empty output => success');
is(main::backup_run_failed(undef, undef, undef), 0, 'no status + undef output => success');

done_testing();
