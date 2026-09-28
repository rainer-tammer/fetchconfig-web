use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

my $p = '/repo/202609/20260917/sw1.acme.com/sw1.acme.com.run.20260917.001947CEST';

# parse_backup_timestamp -> (date, time)
my ($d,$t) = main::parse_backup_timestamp($p);
is($d, '2026-09-17', 'date parsed');
is($t, '00:19:47 CEST', 'time+tz parsed') for 1;   # tz appended
like($t, qr/^00:19:47/, 'time parsed');

# compact stamp for download filenames
is(main::backup_compact_stamp($p), '260917-001947', 'compact stamp');

# suffix: none here
is(main::backup_name_suffix($p), '', 'no suffix when plain');

# with a dotted filename_append_suffix after the TZ
my $ps = $p . '.txt';
is(main::backup_name_suffix($ps), '.txt', 'dotted suffix recognised');
is(main::backup_compact_stamp($ps), '260917-001947', 'compact stamp tolerates suffix');
my ($d2) = main::parse_backup_timestamp($ps);
is($d2, '2026-09-17', 'date parsed with suffix present');

# CET (winter) tz + no-suffix legacy
my $pw = '/r/x.run.20250125.001751CET';
my ($dw,$tw) = main::parse_backup_timestamp($pw);
is($dw, '2025-01-25', 'winter date');
like($tw, qr/CET$/, 'winter tz');

# a dot-less trailing token is NOT treated as a suffix
is(main::backup_name_suffix('/r/x.run.20260917.001947CESTx'), '', 'dot-less token = no suffix');

done_testing();
