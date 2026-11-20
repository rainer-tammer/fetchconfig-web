use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# --------------------------------------------------------------------------
# Devices-tab read-only columns (2.15.2): Vendor + HW Model, sourced from the
# 2.15 device_inventory table. The DB load is exercised against PostgreSQL
# separately; here we drive the render helpers with the state they populate.
# --------------------------------------------------------------------------

ok(defined &main::device_inventory_summary_init, 'device_inventory_summary_init defined');
ok(defined &main::render_inventory_cells,        'render_inventory_cells defined');

my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# wiring: panel class, header cells, row cells, and SELECT-only load
like($src, qr/dev-has-inv/,                       'panel gets the dev-has-inv grid class');
like($src, qr/<span class="dev-row-vendor">Vendor<\/span>/,   'header has a Vendor column');
like($src, qr/<span class="dev-row-hwmodel">HW Model<\/span>/,'header has a HW Model column');
like($src, qr/render_inventory_cells\(\$id\)/,    'summary/expanded rows emit the inventory cells');
like($src, qr/SELECT dev_id, vendor, vendor_raw, model\}/,
     'summary loader reads device_inventory (SELECT only)');
like($src, qr/\$has_sysloc \? q\{, syslocation\} : q\{, NULL\}/,
     'loader pulls syslocation only when the 2.17 column is present');
unlike($src, qr/(?:INSERT|UPDATE|DELETE)\s+(?:INTO\s+)?device_inventory\b/i,
     'the editor columns never write the inventory tables');
like($src, qr/return unless \$ENABLE_DASHBOARD/,  'loader is gated on the DB feature flag');

# --- Devices LIST page (Setup -> Devices) wiring ---------------------------
# the list page (show_device_list) is where the columns were primarily asked for
like($src, qr/sub show_device_list/,              'device list renderer present');
like($src, qr/data-key="vendor">Vendor/,          'list page: sortable Vendor header');
like($src, qr/data-key="hwmodel">HW Model/,       'list page: sortable HW Model header');
like($src, qr/data-vendor="/,                     'list rows carry data-vendor (for sort/filter)');
like($src, qr/data-hwmodel="/,                    'list rows carry data-hwmodel');
like($src, qr/data-key="syslocation">sysLocation/,'list page: sortable sysLocation header (between Site and Comment)');
like($src, qr/data-syslocation="/,                'list rows carry data-syslocation (for sort)');
unlike($src, qr/<th>Comment<\/th>/,               'list page: the Comment column is removed');
# the list page loads the same inventory summary, gated the same way
like($src, qr/device_inventory_summary_init\(\);\s*\n\s*my \$inv_cols/,
     'list page loads the inventory summary once');

# --- render helper behaviour ----------------------------------------------
# Not available -> no cells at all (editor unchanged on a non-inventory install).
{
    local $main::DEVICE_INVENTORY_AVAILABLE = 0;
    is(main::render_inventory_cells('sw1'), '', 'no cells when inventory unavailable');
    my $row = main::render_device_summary_row(0, { kind=>'device', id=>'sw1', model=>'procurve-snmp' });
    unlike($row, qr/dev-row-vendor/, 'summary row has no vendor cell when unavailable');
}

# Available -> vendor + hw model for a known device; muted dash for an unknown.
{
    local $main::DEVICE_INVENTORY_AVAILABLE = 1;
    local %main::DEVICE_INVENTORY = (
        'sw1' => { vendor => 'HPE', model => 'J9728A' },
    );
    my $cells = main::render_inventory_cells('sw1');
    like($cells, qr/<span class="dev-row-vendor" title="HPE">HPE<\/span>/,        'vendor cell shows the value + title tooltip');
    like($cells, qr/<span class="dev-row-hwmodel" title="J9728A">J9728A<\/span>/, 'hw model cell shows the value + title tooltip');

    my $none = main::render_inventory_cells('nope');
    like($none, qr/dev-row-vendor"><span class="dev-inv-none">&mdash;<\/span>/,
         'unknown device shows a muted dash for vendor');

    my $row = main::render_device_summary_row(0, { kind=>'device', id=>'sw1', model=>'procurve-snmp' });
    like($row, qr/dev-row-model.*dev-row-vendor.*dev-row-hwmodel.*dev-row-site/s,
         'columns sit between Model and Site in the row');

    # HTML is escaped
    local %main::DEVICE_INVENTORY = ( 'sw1' => { vendor => 'A&B<x>', model => 'm"q' } );
    my $esc = main::render_inventory_cells('sw1');
    like($esc, qr/A&amp;B&lt;x&gt;/, 'vendor is HTML-escaped');
    unlike($esc, qr/<x>/,            'no raw markup leaks through');
}

# --- Foldable Statistics panel -> vertical pill tab ------------------------
ok(defined &main::stats_fold_script, 'stats_fold_script defined');
like($src, qr/id="stats-fold"/,  'Statistics header has a fold button');
like($src, qr/id="stats-pill"/,  'collapsed state renders the pill tab');
like($src, qr/class="dev-stats-pill"/, 'pill uses the dev-stats-pill class');
like($src, qr/<span class="sp-n">\} \. esc\(\$total\)/, 'pill shows the total device count');
like($src, qr/print stats_fold_script\(\);/, 'the fold script is emitted on the devices page');
my ($sf) = $src =~ /sub stats_fold_script \{(.*?)\n\}/s;
ok($sf, 'located stats_fold_script');
like($sf, qr/stats-folded/,       'toggles the stats-folded class on .dev-layout');
like($sf, qr/fcweb_statsfold/,    'remembers the choice in the fcweb_statsfold cookie');
like($sf, qr/getCookie\(\) === '0'/, 'only an explicit "0" cookie expands it');
# default state is folded: the class is applied server-side on the layout div
like($src, qr/class="dev-layout stats-folded"/, 'the panel starts folded by default');
# CSS: the folded class hides the panel and pins the vertical tab to the viewport edge
my $css = css_source();
like($css, qr/\.dev-layout\.stats-folded \.dev-stats \{ display: none/, 'CSS: folded hides the panel');
like($css, qr/\.dev-layout\.stats-folded \.dev-stats-pill \{/,          'CSS: folded shows the pill');
like($css, qr/writing-mode: vertical-rl/,                               'CSS: the pill is a vertical (rotated) tab');
like($css, qr/position: fixed; right: 0;/,                              'CSS: the pill is pinned to the right browser edge');
# Devices page trims its side padding so the open stats box nears the right edge
like($src, qr/page_head\('Devices', \$user, 'full dev-wide'\)/, 'Devices page opts into the wide (thin-stripe) layout');
like($css, qr/main\.full\.dev-wide \{ padding: 0 1em; \}/,      'CSS: Devices page uses a ~1em side stripe');

done_testing();
