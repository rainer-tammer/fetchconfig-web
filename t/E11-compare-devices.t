use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source);

# --------------------------------------------------------------------------
# Compare devices (Devices -> Compare devices): the two-device side-by-side
# view added in 2.12.28. Exercises the selection-form renderer, the pure URL
# builder, the version resolver's error path, and the source wiring (menu,
# dispatch, CSS).
# --------------------------------------------------------------------------

my ($cfg, $dir, $fcp) = make_config();
my %kv; { open(my $r,'<',$cfg); while(<$r>){chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b;} close($r); }
open(my $w, '>', $kv{DEVICE_TABLE}) or die "write table: $!";
print $w <<'DT';
# DEFAULT OPTIONS SECTION
default: cisco-ios user=a,pass=b,repository=/r,keep=5
# DEVICES SECTION
cisco-ios sw-ber 10.0.0.1 user=x,pass=y,repository=/r,keep=5,site=BER01
generic   fw-ham 10.0.0.2 user=x,pass=y,repository=/r,keep=5,site=HAM01
DT
close($w);

load_cgi($cfg); main::read_config();

# --- selection form renders the essential controls ------------------------
my $devices = [
    { id => 'sw-ber', model => 'cisco-ios', site => 'BER01' },
    { id => 'fw-ham', model => 'generic',   site => 'HAM01' },
];
my $form = main::compare_devices_form_html(undef, $devices, '', 'latest', '', 'latest', 0);

like($form, qr/name="action" value="compare_devices"/, 'form posts the compare_devices action');
like($form, qr/name="devA"/,                 'device A input present');
like($form, qr/name="devB"/,                 'device B input present');
like($form, qr/id="a-ver"[^>]*name="verA"/,  'version A selector present');
like($form, qr/id="b-ver"[^>]*name="verB"/,  'version B selector present');
like($form, qr/id="cmp-swap"/,               'swap button present');
like($form, qr/id="a-site"/,                 'site filter A present');
like($form, qr/name="ignore_ws"/,            'ignore-whitespace toggle present');
like($form, qr/name="only_diff"/,            'only-differences checkbox present on the form');
unlike($form, qr/name="only_diff" value="1" checked/, 'only-differences is unchecked by default');
# Foldable selection box: open on the first visit (no result yet)...
like($form, qr/<details class="tool-section" id="cmp-devices-section" open>/, 'selection form is an open <details> with no result');
like($form, qr/<summary class="tool-section-title">Compare devices<\/summary>/, 'title is the fold summary');
# ...and folded away once a result is shown.
my $folded = main::compare_devices_form_html(undef, $devices, 'sw-ber', 'latest', 'fw-ham', 'latest', 0, 0, 1);
like($folded,   qr/id="cmp-devices-section">/, 'selection form collapses (no open attr) when a result is shown');
unlike($folded, qr/id="cmp-devices-section" open>/, 'collapsed form really has no open attribute');
like($form, qr/action=compare_device_versions/, 'JS wires the AJAX version endpoint');
like($form, qr/"id":"sw-ber"/,               'device data embedded for the client');
like($form, qr/BER01/,                       'site option rendered');
unlike($form, qr/\bpass=y\b/,                'raw device secrets never reach the picker');

# data-sel carries a selected version back into the form
my $form2 = main::compare_devices_form_html(undef, $devices, 'sw-ber', '3', 'fw-ham', 'latest', 1);
like($form2, qr/data-sel="3"/,               'chosen backup index round-trips via data-sel');
like($form2, qr/value="sw-ber"/,             'chosen device A round-trips');
like($form2, qr/name="ignore_ws" value="1" checked/, 'ignore-whitespace stays checked');

# --- compare_devices_url: 'latest' and defaults are omitted ---------------
my $u1 = main::compare_devices_url(devA=>'r1', devB=>'r2');
like($u1,   qr/action=compare_devices/,      'url has the action');
like($u1,   qr/devA=r1/,                     'url has devA');
like($u1,   qr/devB=r2/,                     'url has devB');
unlike($u1, qr/verA=/,                       'url omits verA when latest/unset');
unlike($u1, qr/ignore_ws/,                   'url omits ignore_ws when off');
my $u2 = main::compare_devices_url(devA=>'r1', verA=>'5', devB=>'r2', verB=>'latest', ignore_ws=>1, format=>'txt');
like($u2,   qr/verA=5/,                       'explicit verA kept');
unlike($u2, qr/verB=/,                        'verB=latest omitted');
like($u2,   qr/ignore_ws=1/,                  'ignore_ws kept when on');
like($u2,   qr/format=txt/,                   'download format kept');
like(main::compare_devices_url(devA=>'r1', devB=>'r2', only_diff=>1), qr/only_diff=1/, 'only_diff kept when on');
unlike($u1, qr/only_diff/,                    'url omits only_diff when off');

# --- result toolbar: segmented toggles (debug-viewer style) + spinner -------
my $tb = main::compare_devices_toolbar_html('a','latest','b','latest',0,3,1);
like($tb, qr/class="dbg-bar"/,                'toolbar reuses the viewer-toolbar (.dbg-bar) chrome');
like($tb, qr/seg-btn[^>]*>All lines</,        'differences toggle: All lines');
like($tb, qr/seg-btn[^>]*>Only differences</, 'differences toggle: Only differences');
like($tb, qr/seg-btn[^>]*>Keep whitespace</,  'whitespace toggle: Keep whitespace');
like($tb, qr/seg-btn[^>]*>Ignore whitespace</,'whitespace toggle: Ignore whitespace');
like($tb, qr/seg-btn cmp-reload on"[^>]*only_diff=1/, 'active toggle carries the "on" class');
like($tb, qr/backup-spinner/,                 'spinner overlay present');
like($tb, qr/cmp-reload/,                     'reload links trigger the spinner');
unlike($tb, qr/type="checkbox"/,              'toggles are buttons, not checkboxes');

# --- resolve_compare_version degrades gracefully (no real fetchconfig) -----
my ($idx, $ts, $err) = main::resolve_compare_version('sw-ber', 'latest');
ok(defined $err,                             'resolve returns an error rather than dying when no backups');

# --- source wiring --------------------------------------------------------
my $src = do { local $/; open(my $f,'<',cgi_path()) or die $!; <$f> };
like($src, qr/\$su->\('Compare devices', '\?action=compare_devices'\)/, 'menu item added under Devices');
like($src, qr/action eq 'compare_devices'/,         'dispatch: compare_devices');
like($src, qr/action eq 'compare_device_versions'/, 'dispatch: compare_device_versions (AJAX)');

my $css = css_source();
like($css, qr/\.cmp-grid/,       'CSS: compare grid present');
like($css, qr/\.cmp-swap/,       'CSS: swap control present');
like($css, qr/\.dbg-bar \.seg-btn/, 'CSS: shared seg-button toolbar styling present');

done_testing();
