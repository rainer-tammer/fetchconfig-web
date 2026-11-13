use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.17.8: Inventory dashboard -- a read-only fleet roll-up of the SNMP
# inventory (device_inventory). Gated on $ENABLE_DASHBOARD + a present,
# SELECT-readable schema; scoped to the viewer's visible devices via
# read_device_ids; reuses the existing dash-* CSS vocabulary.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# --- handler + dispatch ----------------------------------------------------
ok(main->can('show_inventory_dashboard'), 'show_inventory_dashboard is defined');
like($src, qr/\$action eq 'inventory_dashboard'/,        'action inventory_dashboard is dispatched');
like($src, qr/show_inventory_dashboard\(\$user\)/,       'dispatch calls the handler');

# --- the handler body ------------------------------------------------------
my ($body) = $src =~ /sub show_inventory_dashboard \{(.*?)\n\}/s;
ok($body, 'located the handler body');

like($body, qr/unless \$ENABLE_DASHBOARD/,               'gated on the DB dashboard feature');
like($body, qr/db_table_exists\(\$dbh, 'device_inventory'\)/, 'defensive: probes for the device_inventory table (fast pg_catalog)');
like($body, qr/read_device_ids\(\$user, \$acc\)/,        'denominator is the viewer-visible device set (site-scoped)');
like($body, qr/user_site_access/,                        'computes the viewer scope (global vs restricted)');
like($body, qr/dash_tile\(/,                             'reuses the KPI tile helper');
like($body, qr/dash_scope_pill\(\$scope\)/,              'shows the scope pill');
like($body, qr/last_success_at/,                         'uses last_success_at for freshness');
like($body, qr/Needs attention/,                         'renders the needs-attention list');
like($body, qr/action=device_inventory&dev=/,            'attention rows link to the per-device inventory page');

# status uses the real schema values, not a guessed 'ok'
like($body, qr/\$st eq 'successful'/,                     "counts status 'successful' as OK");
like($body, qr/\$st eq 'failed'/,                        "counts status 'failed'");
like($body, qr/\$st eq 'disabled'/,                      "counts status 'disabled'");
unlike($body, qr/\$status\{ok\}|\$st eq 'ok'/,           "does not use a non-existent 'ok' status");

# no-row devices split into pending (configured) vs not configured, from the device table
like($body, qr/parse_device_table\(\$content\)/,         'parses the device table for SNMP config');
like($body, qr/\$inv_configured->\(\$d->\{id\}\)/,       'classifies no-row devices by configured-ness');
like($body, qr/\$pending\+\+/,                           'counts pending (configured, not yet collected)');
like($body, qr/\$notcfg\+\+/,                            'counts not-configured');
like($body, qr/snmp_community.*snmp_write_community/s,   'enable rule checks v1/v2c credentials');
like($body, qr/snmp_user/,                               'enable rule checks the v3 credential');
like($body, qr/\(0\|off\|no\|false\)/,                   'snmp_inventory=0/off disables');

# firmware is read from the COMPONENT table, not the summary
like($body, qr/device_inventory_component.*fw_version/s, 'firmware coverage comes from device_inventory_component.fw_version');
like($body, qr/\$fw_dev\{/,                              'firmware is a per-device set');

# needs-attention only lists failed/disabled (not successful, not never-collected)
like($body, qr/\$st eq 'failed' \|\| \$st eq 'disabled'/, 'needs-attention = failed or disabled only');
# empty-state message is truthful: no false "all collected successfully" while devices are pending
like($body, qr/No failed or disabled collections\./,     'empty state: states no failed/disabled');
like($body, qr/pending (its|their)/,                     'empty state: flags pending first collections');
unlike($body, qr/Every configured device was collected successfully/, 'empty state no longer over-claims success');

# model / OS bars carry the vendor in front; long labels wrap
like($body, qr/\$model\{\s*"\$vp\$row->\{model\}"/,      'model bars grouped with the vendor in front');
like($body, qr/\$os\{\s*"\$vp\$row->\{os\}"/,            'OS bars grouped with the vendor in front');
ok(main->can('dash_wrap_label'),                         'dash_wrap_label helper exists');
like($body, qr/dash_wrap_label\(\$k, 50\)/,              'ranked labels wrap past 50 chars');
is(main::dash_wrap_label('short', 50), 'short',          'short label: no break');
like(main::dash_wrap_label('x' x 30 . ' ' . 'y' x 30, 50), qr/<br>/, 'long label gets one <br>');

# per-panel "Show N" selects, persisted in a cookie
ok(main->can('dash_show_select'),                        'dash_show_select helper exists');
like(main::dash_show_select('vendor', 10), qr/class="dash-show-sel" data-key="vendor"/, 'select carries its panel key');
like(main::dash_show_select('vendor', 10), qr/<option value="10" selected>/, 'current value is preselected');
like(main::dash_show_select('vendor', 0),  qr{<option value="0" selected>All</option>}, '0 = All');
like($body, qr/\%show = \(vendor => 10, models => 10, os => 10, attention => 25\)/, 'defaults: 10 ranked, 25 attention');
like($body, qr/CGI::Cookie->fetch/,                      'reads the fcweb_invshow cookie server-side (no flash)');
like($body, qr/fcweb_invshow/,                           'uses the fcweb_invshow cookie');
like($body, qr/data-show-key=/,                          'panels tagged for the show/hide script');
like($body, qr/data-show-row/,                           'rows tagged for the show/hide script');
like($body, qr/dash-row-hidden/,                         'rows beyond N hidden server-side');

# status panel label wording
like($body, qr/>Successful <strong>/,                    'status tally says "Successful", not "OK"');

# --- navigation entry: in the Dashboard menu, named "Inventory" -------------
like($src, qr/\$su->\('Inventory', '\?action=inventory_dashboard'\)/,
     'Dashboard menu offers "Inventory"');
# and it sits inside the $ENABLE_DASHBOARD-gated Dashboard group, not the Devices menu
my ($dash_block) = $src =~ /my \$dashboard_menu = '';(.*?)\$dashboard_menu = \$group->\('Dashboard'/s;
ok($dash_block && $dash_block =~ /inventory_dashboard/, 'Inventory entry lives in the Dashboard group');
unlike($src, qr/Inventory dashboard', '\?action=inventory_dashboard/,
     'no longer offered from the Devices menu');

# --- CSS: categorical ranked-bar fill --------------------------------------
my $cssf = $FindBin::Bin . '/../fetchconfig-web.css';
my $css  = do { open(my $f, '<', $cssf) or die $!; local $/; <$f> };
like($css, qr/\.dash-age-fill\.dash-cat \{ background: var\(--color-accent\)/,
     'categorical bar fill uses the app accent');
like($css, qr/\.dash-cat-dim \{ background: var\(--color-faint\)/,
     '"Other" bar is dimmed');

# --- version ---------------------------------------------------------------
is(main::APP_VERSION(),          '2.17.15', 'APP_VERSION 2.17.15');
is(main::APP_VERSION_INTERNAL(), '2.17.15', 'APP_VERSION_INTERNAL 2.17.15 (stays equal to APP_VERSION)');

done_testing();
