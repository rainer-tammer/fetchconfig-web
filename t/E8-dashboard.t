use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

my $NOW = 1_700_000_000;   # fixed naive epoch for deterministic tests

# --- db_pass masking (the generic pass\w*= rule misses db_pass) --------------
{
    my $line = 'db: db_inst=fc,db_user=fetchconfig_dashboard,db_pass=s3cr3t,db_host=localhost';
    my $m = main::mask_secrets($line);
    like($m,   qr/db_pass=\?\*\*\*\?/, 'db_pass value masked');
    unlike($m, qr/s3cr3t/,             'db_pass secret gone');
    like($m,   qr/db_user=fetchconfig_dashboard/, 'db_user NOT masked');
    like($m,   qr/db_inst=fc/,         'db_inst NOT masked');
    like($m,   qr/db_host=localhost/,  'db_host NOT masked');

    my $q = main::mask_secrets('db: db_pass="a,b=c",db_host=h');
    like($q,   qr/db_pass=\?\*\*\*\?/, 'quoted db_pass masked as a unit');
    unlike($q, qr/a,b=c/,              'quoted secret gone');
}

# --- dash_status classification ---------------------------------------------
is(main::dash_status('success', undef,        $NOW), 'never',  'no last_good -> never');
is(main::dash_status('failed',  $NOW - 100,   $NOW), 'failed', 'failed state -> failed');
is(main::dash_status('success', $NOW - 100,   $NOW), 'fresh',  'recent success -> fresh');
is(main::dash_status('success', $NOW - 90000, $NOW), 'stale',  '>24h -> stale');

# --- dash_fmt_ts: gmtime of a naive epoch (no tz conversion) -----------------
is(main::dash_fmt_ts(0),     '1970-01-01 00:00', 'epoch 0 renders as wall clock via gmtime');
is(main::dash_fmt_ts(86400), '1970-01-02 00:00', 'epoch +1d');
is(main::dash_fmt_ts(''),    '',                 'empty -> empty');

# --- dash_age buckets --------------------------------------------------------
is(main::dash_age(undef,         $NOW), 'never',     'undef -> never');
is(main::dash_age($NOW - 30,     $NOW), 'just now',  '<90s');
is(main::dash_age($NOW - 120,    $NOW), '2 min ago', 'minutes');
is(main::dash_age($NOW - 7200,   $NOW), '2 h ago',   'hours');
is(main::dash_age($NOW - 172800, $NOW), '2 d ago',   'days');

# --- dash_donut: background + four segment circles ---------------------------
{
    my $svg = main::dash_donut(90, 5, 3, 2, 100);
    like($svg, qr/<svg/,             'donut is an svg');
    like($svg, qr/class="dash-arc-fresh"/, 'fresh segment present');
    like($svg, qr/class="dash-arc-never"/, 'never segment present');
    my $n = () = ($svg =~ /<circle/g);
    is($n, 5, 'one background + four segment circles');
}

# --- schema state + guidance blocks (no DB handle needed) --------------------
is(main::dashboard_schema_state(undef), 'missing', 'no dbh -> missing');

{
    my $cmd = qr/fetchconfig-web-dbsetup\.pl --upgrade/;
    like(main::dashboard_state_block(undef, 'missing'), $cmd, 'missing block shows upgrade command');
    like(main::dashboard_state_block(undef, 'missing'), qr/not present/i, 'missing wording');
    like(main::dashboard_state_block(undef, 'nogrant'), qr/SELECT/,      'nogrant mentions SELECT');
    my $empty = main::dashboard_state_block(undef, 'empty');
    like($empty, qr/db_pass=\?\*\*\*\?/,          'empty panel password is masked (via esc/mask_secrets)');
    unlike($empty, qr/db_pass=\*{8}/,             'raw placeholder was itself masked (defense in depth)');
    like($empty, qr/fetchconfig_dashboard/,       'empty panel defaults writer name');
    like($empty, $cmd,                            'empty panel references --upgrade');
    like($empty, qr/db_inst=/,                    'empty panel prints db_inst');
    like($empty, qr/db_host=/,                    'empty panel prints db_host');
}

# --- wiring (source checks, E6 style) ----------------------------------------
{
    my $src = do { open(my $fh,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$fh> };
    like($src, qr/\$action eq 'dashboard_overview'/, 'dispatcher: dashboard_overview');
    like($src, qr/\$action eq 'dashboard_devices'/,  'dispatcher: dashboard_devices');
    like($src, qr/if \(\$ENABLE_DASHBOARD\) \{\s*\n\s*my \@dash_items/, 'dashboard menu gated on ENABLE_DASHBOARD (overview for all)');
    like($src, qr/push \@dash_items.*'All devices'.*\n\s*if \$is_admin;/, 'All devices menu entry is admin-only');
    like($src, qr/sub dashboard_overview_allowed/, 'overview has its own (non-admin) access check');
    like($src, qr/\$action eq 'dashboard_devices_csv'/, 'dispatcher: CSV export route');
    like($src, qr/data-tab="email">General parameters</, 'editor tab renamed to General parameters');
    like($src, qr/\\b\(db_pass=\)/, 'db_pass mask rule present');
}

# --- All-devices join + By-site aggregation (fake dbh + device table) ---------
{
    require File::Spec; require File::Basename;
    my $dt = File::Spec->catfile(File::Basename::dirname($cfg), 'device_table');
    open(my $w, '>', $dt) or die $!;
    print $w "default: cisco-ios\n";
    print $w "cisco-ios rtrcore01 10.0.0.1 site=gop\n";
    print $w "generic   fw01      10.0.0.9 site=can,template=asa-5525.tmpl\n";
    print $w "cisco-ios orphan    10.0.0.5 site=gop\n";
    close $w;

    my $now = main::dash_naive_now();
    {
        package E8Dbh;
        our $NOWREF;
        sub new { bless {}, shift }
        sub selectall_arrayref {
            my ($self, $sql) = @_;
            if ($sql =~ /FROM sites/) {
                return [ { id => 0, code => '*',   description => 'any' },
                         { id => 1, code => 'gop', description => 'Goeppingen' },
                         { id => 2, code => 'can', description => 'Canton, MI' } ];
            }
            if ($sql =~ /FROM backup_current/) {
                return [ { dev_id => 'rtrcore01', state => 'success', last_good_at => $NOWREF - 60,     last_good_size => 420000 },
                         { dev_id => 'fw01',      state => 'failed',  last_good_at => $NOWREF - 300,    last_good_size => 170000 },
                         { dev_id => 'ghost',     state => 'success', last_good_at => $NOWREF - 500000, last_good_size => 1000 } ];
            }
            return [];   # backup_runs (trend) etc.
        }
    }
    $E8Dbh::NOWREF = $now;
    my $dbh = E8Dbh->new;

    my $rows = main::dashboard_devices_rows($dbh, undef);
    my %by = map { $_->{dev_id} => $_ } @$rows;
    is($by{rtrcore01}{site_code}, 'gop',        'devices: site code');
    is($by{rtrcore01}{site_desc}, 'Goeppingen', 'devices: site code resolved to description');
    is($by{rtrcore01}{model},  'cisco-ios',  'devices: plain model shown');
    is($by{rtrcore01}{status}, 'fresh',      'devices: fresh status');
    is($by{fw01}{model}, "generic \xc2\xb7 asa-5525", 'devices: generic shows "generic <dot> <template>"');
    is($by{fw01}{site_code}, 'can',        'devices: site code (can)');
    is($by{fw01}{site_desc}, 'Canton, MI', 'devices: description with comma preserved');
    is($by{fw01}{status}, 'failed',     'devices: failed status');
    is($by{orphan}{status}, 'nodata',   'devices: configured but no DB row => No data');
    ok(exists $by{ghost},  'devices: history-only device still listed');
    is($by{ghost}{site_code}, '', 'devices: history-only device has no site');
    is($by{ghost}{model},     '', 'devices: history-only device has no model');

    # Orphan detection: present in history, absent from the device table.
    my $orph = main::dashboard_orphans($dbh);
    my @oids = map { $_->{dev_id} } @$orph;
    is_deeply(\@oids, ['ghost'], 'orphans: only the history-only device (configured ones excluded)');

    my $d = main::dashboard_overview_data($dbh, undef);
    is($d->{total}, 3, 'overview total counts current-status rows');
    my %site = map { $_->{site} => $_ } @{ $d->{by_site} };
    is($site{'gop / Goeppingen'}{total},   1, 'by_site: label is "code / description"');
    is($site{'gop / Goeppingen'}{fresh},   1, 'by_site: Goeppingen 1 fresh');
    is($site{'can / Canton, MI'}{failed},  1, 'by_site: Canton 1 failed');
    ok(exists $site{'(no site)'},             'by_site: history-only device bucketed as (no site)');
    is($site{'(no site)'}{stale},          1, 'by_site: (no site) 1 stale');
}

# --- backup_sha1_map: path -> sha1 from backup_versions ----------------------
{
    no warnings 'redefine', 'once';
    local *main::db_connect = sub { bless {}, 'E8ShaDbh' };
    *E8ShaDbh::selectall_arrayref = sub {
        my ($self, $sql) = @_;
        return undef unless $sql =~ /FROM backup_versions/;
        return [ { path => '/repo/r1.cfg',    sha1 => 'abc123' },
                 { path => '/repo/r2.cfg',    sha1 => 'def456' },
                 { path => '/repo/empty.cfg', sha1 => '' } ];
    };
    *E8ShaDbh::disconnect = sub { };
    my $m = main::backup_sha1_map('r1');
    is($m->{'/repo/r1.cfg'}, 'abc123', 'sha1 map: path -> hash (1)');
    is($m->{'/repo/r2.cfg'}, 'def456', 'sha1 map: path -> hash (2)');
    ok(!exists $m->{'/repo/empty.cfg'}, 'sha1 map: blank hash skipped');
}

done_testing();
