use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# A device table (file-based) with five devices across two sites. One device
# (idledev) is long-stable; one (newdev) has no stored version yet.
require File::Spec; require File::Basename;
my $dt = File::Spec->catfile(File::Basename::dirname($cfg), 'device_table');
open(my $w, '>', $dt) or die $!;
print $w "default: cisco-ios\n";
print $w "cisco-ios rtrcore01 10.0.0.1 site=gop\n";
print $w "cisco-ios swigmg01  10.0.0.2 site=gop\n";
print $w "cisco-ios swisit02  10.0.0.3 site=can\n";
print $w "cisco-ios idledev   10.0.0.4 site=gop\n";
print $w "cisco-ios newdev    10.0.0.5 site=can\n";
close $w;

my $now    = main::dash_naive_now();
my $cur_wk = int($now / 604800);
my $D = 86400;

# A mock DBI handle: returns a chosen "DB truth" per query, matched by SQL token.
{
    package ChgDbh;
    our ($NOW, $CUR_WK);
    sub new { bless {}, shift }
    sub disconnect { }
    sub selectall_arrayref {
        my ($self, $sql) = @_;
        my $D = 86400;
        if ($sql =~ /FROM sites/) {
            return [ { id => 0, code => '*',   description => 'any' },
                     { id => 1, code => 'gop', description => 'Goeppingen' },
                     { id => 2, code => 'can', description => 'Canton, MI' } ];
        }
        if ($sql =~ /FROM backup_runs/) {          # cut-over to live recording
            return [ { c => $NOW - 6 * 604800 } ]; # ~6 weeks ago
        }
        if ($sql =~ m{/ 604800}) {                 # weekly churn buckets
            return [ { wk => $CUR_WK - 5, n => 2 },
                     { wk => $CUR_WK - 4, n => 12 },   # the spike
                     { wk => $CUR_WK - 2, n => 3 },
                     { wk => $CUR_WK,     n => 5 } ];
        }
        if ($sql =~ /ORDER BY n DESC/) {           # windowed per-device (30d)
            return [ { dev_id => 'swigmg01',  n => 3 },
                     { dev_id => 'rtrcore01', n => 3 },
                     { dev_id => 'swisit02',  n => 1 } ];
        }
        if ($sql =~ /ORDER BY file_timestamp DESC/) {   # recently-changed feed
            return [ { dev_id => 'rtrcore01', ts => $NOW - 6 * 3600,  la => 4,     lr => 1     },
                     { dev_id => 'swisit02',  ts => $NOW - 20 * 3600, la => 0,     lr => 0     },
                     { dev_id => 'swigmg01',  ts => $NOW - 2 * $D,    la => undef, lr => undef } ];
        }
        if ($sql =~ /GROUP BY dev_id/) {           # lifetime per-device
            return [ { dev_id => 'rtrcore01', n => 3, last_ts => $NOW - 6 * 3600 },
                     { dev_id => 'swigmg01',  n => 4, last_ts => $NOW - 2 * $D },
                     { dev_id => 'swisit02',  n => 1, last_ts => $NOW - 20 * 3600 },
                     { dev_id => 'idledev',   n => 1, last_ts => $NOW - 800 * $D } ];
        }
        if ($sql =~ /count\(\*\) AS n FROM backup_versions/) {   # changes_7d
            return [ { n => 5 } ];
        }
        return [];
    }
}
$ChgDbh::NOW    = $now;
$ChgDbh::CUR_WK = $cur_wk;
my $dbh = ChgDbh->new;

my $c = main::dashboard_changes_data($dbh, undef);

# --- KPIs --------------------------------------------------------------------
is($c->{total_devices}, 5, 'total_devices = device-table count');
is($c->{changes_7d},    5, 'changes_7d from count query');
is($c->{changes_30d},   7, 'changes_30d = sum of per-device 30d counts');
is($c->{changed_24h},   2, 'changed_24h = devices changed < 24h (rtrcore01 6h, swisit02 20h)');
is($c->{stable_1y},     1, 'stable_1y = devices unchanged >= 365d (idledev)');
is($c->{most_changed}{dev}, 'swigmg01', 'most_changed = top of 30d leaderboard');
is($c->{most_changed}{site_code}, 'gop', 'most_changed carries its site code');

# --- weekly churn ------------------------------------------------------------
is(scalar @{ $c->{weeks} }, 16, 'weekly chart zero-filled to CHG_WEEKS');
is($c->{weeks}[-1]{rel}, 0,  'last week is rel 0 (now)');
is($c->{weeks}[0]{rel}, -15, 'first week is rel -15');
is($c->{weeks}[-1]{n}, 5, 'current week count');
my ($spk) = grep { $_->{spike} } @{ $c->{weeks} };
ok($spk && $spk->{n} == 12, 'spike week flagged (12 >> median)');
ok($c->{weeks}[0]{bf}, 'oldest shown week is in the back-filled (pre-cut-over) region');
ok(!$c->{weeks}[-1]{bf}, 'current week is measured (post cut-over)');
is($c->{cutover}, $now - 6 * 604800, 'cut-over = first live backup_runs row');

# --- leaderboard -------------------------------------------------------------
is(scalar @{ $c->{top} }, 3, 'leaderboard rows');
is($c->{top}[0]{dev}, 'swigmg01', 'leaderboard ordered by 30d count');
is($c->{top}[0]{n}, 3, 'leaderboard count');
like($c->{top}[0]{age}, qr/ago|now/, 'leaderboard last-change age rendered');

# --- age buckets -------------------------------------------------------------
my $b = $c->{buckets};
is($b->{le7},   3, 'buckets: 3 changed within 7 days');
is($b->{gt2},   1, 'buckets: idledev in >2y');
is($b->{none},  1, 'buckets: newdev has no recorded change');
is($b->{with_versions}, 4, 'buckets: 4 device-table devices have versions');
is($b->{le7}+$b->{d8_30}+$b->{d31_90}+$b->{d91_365}+$b->{y1_2}+$b->{gt2}+$b->{none},
   $c->{total_devices}, 'buckets + none sum to the fleet');

# --- feed (DB line counts: defined, 0/0, and NULL-baseline) ------------------
is(scalar @{ $c->{feed} }, 3, 'feed rows');
is($c->{feed}[0]{dev}, 'rtrcore01', 'feed newest first');
is($c->{feed}[0]{site_code}, 'gop', 'feed carries site code');
is($c->{feed}[0]{la}, 4, 'feed carries lines_added');
is($c->{feed}[0]{lr}, 1, 'feed carries lines_removed');
is($c->{feed}[1]{la}, 0, 'feed: a 0/0 row (only ignored lines changed)');
ok(!defined $c->{feed}[2]{la}, 'feed: oldest-retained row has NULL line counts (renders as --, never "new")');

# --- feed window/cap options -------------------------------------------------
{
    my $c2 = main::dashboard_changes_data($dbh, undef, feed_n => 2, feed_days => 3);
    is(scalar @{ $c2->{feed} }, 2, 'feed_n caps the feed length');
}

# --- scope pill (global/restricted) -----------------------------------------
is($c->{unrestricted}, 1, 'changes data exposes unrestricted (for the scope pill)');
like(main::dash_tile('X', 1, '', '', 'global'),     qr/dash-scope-global"[^>]*>global</,         'dash_tile renders a global pill');
like(main::dash_tile('X', 1, '', '', 'restricted'), qr/dash-scope-restricted"[^>]*>restricted</, 'dash_tile renders a restricted pill');
unlike(main::dash_tile('X', 1, '', ''),             qr/dash-scope/,                          'dash_tile has no pill without a scope');

# --- recent-changed card (Overview) -----------------------------------------
my $rc = main::dashboard_recent_changed($dbh, undef, 86400, 4);
ok($rc->{count} >= 1, 'dashboard_recent_changed returns changed devices');

# --- wiring (source checks) --------------------------------------------------
{
    my $src = do { open(my $fh,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$fh> };
    like($src, qr/\$action eq 'dashboard_changes'/,       'dispatcher: dashboard_changes route');
    like($src, qr/'Changes',\s*'\?action=dashboard_changes'/, 'menu: Changes item');
    like($src, qr/sub show_dashboard_changes/,            'renderer defined');
    like($src, qr/sub dashboard_changes_allowed/,         'access check defined');
    like($src, qr/\$action eq 'changes_diff'/,            'dispatcher: changes_diff route');
    like($src, qr/sub show_changes_diff/,                 'direct-diff renderer defined');
    like($src, qr/action=changes_diff&dev=/,              'feed View diff links to changes_diff');
    like($src, qr/device_accessible\(\$user, \$dev\)/,    'changes_diff guards device visibility');
}

done_testing();
