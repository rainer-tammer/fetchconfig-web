use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path state_changing_actions);

# --------------------------------------------------------------------------
# Per-device Inventory viewer (2.15.1): a read-only page that reads the 2.15
# device_inventory* tables for one device, reached from the backups page. The
# full render needs a live PostgreSQL (DBD::Pg) so these are source-wiring +
# load checks; the SQL itself is validated against PostgreSQL separately.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);   # compiles the whole .cgi (syntax)
ok(defined &main::show_device_inventory,     'show_device_inventory handler is defined');

my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# dispatch + wide green box
like($src, qr/action eq 'device_inventory'/,                       'dispatch routes device_inventory');
like($src, qr/show_device_inventory\(\$user\)/,                    'dispatch calls the handler');
like($src, qr/page_head\('Inventory data', \$user, 'full'\)/,      'wide green box titled "Inventory data"');

# the Inventory button on the backups page, between "Side by side selected" and "Download"
like($src, qr/\?action=device_inventory&dev=/,                     'Inventory button links to the viewer');
like($src, qr/Side by side selected.*?\?action=device_inventory.*?Download/s,
     'Inventory button sits between "Side by side selected" and "Download"');

# reads all three inventory tables, SELECT-only (no writes from the viewer)
like($src,   qr/FROM device_inventory\b/,             'reads device_inventory');
like($src,   qr/FROM device_inventory_component\b/,   'reads device_inventory_component');
like($src,   qr/FROM device_inventory_history\b/,     'reads device_inventory_history');
unlike($src, qr/(?:INSERT|UPDATE|DELETE)\s+(?:INTO\s+)?device_inventory/i,
       'the viewer never writes the inventory tables');

# 8.2-safe ordering (NULLS FIRST/LAST is 8.3+), per-site guard, graceful states
unlike($src, qr/NULLS\s+(?:FIRST|LAST)/i,             'no NULLS FIRST/LAST (8.2-unsafe) in the viewer SQL');
like($src,   qr/device_accessible\(\$user, \$dev\)/,  'viewer enforces per-site device access');
like($src,   qr/inventory schema is not installed/i,  'handles a missing schema');
like($src,   qr/No inventory data for this device/i,  'no-data screen present');
like($src,   qr/snmp_community=/,                      'no-data screen tells the user to enable SNMP');

# 2.17 system-group fields (sysName/sysLocation/sysContact): guarded SELECT +
# Summary rows, shown only when the 2.17 columns exist (one build runs on 2.16+2.17).
like($src, qr/db_column_exists\(\$dbh, 'device_inventory', 'sysname'\)/, 'viewer probes for the 2.17 sysname column');
like($src, qr/\$has_sys \? q\{, sysname, syslocation, syscontact\}/, 'selects the three columns only when present');
like($src, qr/\['sysName',\s*\$cur->\{sysname\}\]/,         'Summary row: sysName');
like($src, qr/\['sysLocation',\s*\$cur->\{syslocation\}\]/, 'Summary row: sysLocation');
like($src, qr/\['sysContact',\s*\$cur->\{syscontact\}\]/,   'Summary row: sysContact');

# read-only: not a state-changing action (no CSRF / POST gate)
my $sc = state_changing_actions($src);
ok(!$sc->{device_inventory}, 'device_inventory is a read-only (non state-changing) action');

done_testing();
