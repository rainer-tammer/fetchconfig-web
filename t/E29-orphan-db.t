use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.18: orphan-DB handling. An orphan is a device-id with history/inventory DB
# rows but no device-table entry. The dashboard flags it as "Orphan DB" (red,
# not "stale"), the backups page offers cleanup instead of Backup now, a
# non-existent id (no table, no DB) gets a plain error, and the dashboard
# cleanup deletes the inventory tables too. "Cleanup dashboard" is renamed
# "Orphan dashboard cleanup".
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# --- helpers --------------------------------------------------------------
ok(main->can('device_in_table'),   'device_in_table helper defined');
ok(main->can('device_has_db_rows'),'device_has_db_rows helper defined');

{
    no warnings 'redefine','once';
    local *main::slurp_device_table = sub {
        return ("cisco-ios dev-a 10.0.0.1 user admin pass x\ncisco-ios dev-b 10.0.0.2 user admin pass x\n", undef);
    };
    is(main::device_in_table('dev-a'), 1, 'device_in_table: present device');
    is(main::device_in_table('gone'),  0, 'device_in_table: absent device');
}

# --- pill -----------------------------------------------------------------
my $pill = main::dash_badge('orphan');
like($pill, qr/dash-badge-orphan/, 'orphan pill uses the dash-badge-orphan class');
like($pill, qr/Orphan DB/,         'orphan pill label is "Orphan DB"');

# --- dashboard rows: orphan classification (source) -----------------------
my ($rows) = $src =~ /sub dashboard_devices_rows \{(.*?)\n\}/s;
ok($rows, 'located dashboard_devices_rows');
like($rows, qr/if\s+\(\$s && !\$m\)\s*\{\s*\$st = 'orphan';/, 'row is orphan when it has a DB stat but no table meta');

# --- All devices page: filter option, count, orphan action (source) -------
my ($dd) = $src =~ /sub show_dashboard_devices \{(.*?)\n\}/s;
ok($dd, 'located show_dashboard_devices');
like($dd, qr/<option value="orphan">Orphan DB<\/option>/, 'status filter offers Orphan DB');
like($dd, qr/\$cnt\{orphan\}/,                            'counts line includes the orphan count');
like($dd, qr/\$r->\{status\} eq 'orphan'/,                'orphan rows get a distinct action cell');
like($dd, qr/action=dashboard_cleanup.*Orphan dashboard cleanup/s, 'orphan action links to Orphan dashboard cleanup');

# --- backups page: orphan vs non-existent (source) ------------------------
my ($bl) = $src =~ /sub show_backup_list \{(.*?)\n\}/s;
ok($bl, 'located show_backup_list');
like($bl, qr/my \$in_table\s*=\s*device_in_table\(\$dev\)/, 'classifies against the device table');
like($bl, qr/device_has_db_rows\(\$dev\)/,                  'distinguishes orphan from non-existent via DB rows');
like($bl, qr/No such device/,                              'non-existent id gets a plain "no such device" error');
like($bl, qr/if \(\$is_orphan\).*?Orphan dashboard cleanup/s, 'orphan hides Backup now, offers Orphan dashboard cleanup');
like($bl, qr/\?action=device_inventory/,                   'Inventory button kept (reachable for orphans too)');

# --- cleanup deletes the inventory tables too, and is renamed (source) ----
my ($del) = $src =~ /sub do_dashboard_cleanup_delete \{(.*?)\n\}/s;
ok($del, 'located do_dashboard_cleanup_delete');
like($del, qr/device_inventory_component device_inventory_history device_inventory/,
     'cleanup transaction includes the inventory tables (child-first)');
like($del, qr/db_table_exists\(\$wdbh, \$tbl\)/, 'inventory tables guarded by existence (older schema safe)');

like($src, qr/\$su->\('Orphan dashboard cleanup', '\?action=dashboard_cleanup'\)/,
     'Tools menu item renamed to "Orphan dashboard cleanup"');
unlike($src, qr/>Cleanup dashboard</, 'no "Cleanup dashboard" label remains');

# --- Overview "Backup health": orphans are out of the health counts ---------
my ($ov) = $src =~ /sub dashboard_overview_data \{(.*?)\n\}/s;
ok($ov, 'located dashboard_overview_data');
like($ov, qr/\$d\{orphan\}\+\+ if \$unrestricted;/, 'overview counts orphans separately (admin only)');
like($ov, qr/if \(!\$in\) \{.*?\$d\{orphan\}\+\+.*?next;/s, 'overview excludes orphan rows from fleet health');
like($ov, qr/orphan => 0/, 'overview %d initialises the orphan bucket');

my ($ovp) = $src =~ /sub show_dashboard_overview \{(.*?)\n\}/s;
ok($ovp, 'located show_dashboard_overview');
like($ovp, qr/if \(\$d->\{orphan\}\)/,                 'overview shows an orphan notice when any exist');
like($ovp, qr/dash-badge-orphan.*Orphan dashboard cleanup/s, 'orphan notice links to the cleanup tool');

done_testing();
