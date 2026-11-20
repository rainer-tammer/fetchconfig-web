use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source);

# --------------------------------------------------------------------------
# 2.18.2: per-device UI text-size control (A/A/A) in the titlebar.
#   - page_head sets html{font-size:<px>} from the fcweb_fontsize cookie, so the
#     first server paint is already at the chosen size (14/16/18).
#   - the cookie value is whitelisted: only small/normal/large map to a size,
#     anything else falls back to 16 -- the raw value never reaches the CSS.
#   - a titlebar control switches the level live and rewrites the cookie.
#   - the dashboard donut is sized in em so it scales with the level.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };
my $css = css_source();

# --- fontsize_px: cookie -> px, whitelisted ------------------------------
ok(main->can('fontsize_px'), 'fontsize_px helper defined');
is(main::fontsize_px(), 16, 'no cookie -> 16 (large = no-change default)');

{
    no warnings 'redefine','once';
    package E31Cookie; sub new { bless { v => $_[1] }, $_[0] } sub value { $_[0]{v} }
    package main;

    { local *CGI::Cookie::fetch = sub { ('fcweb_fontsize' => E31Cookie->new('small')) };
      is(main::fontsize_px(), 12, 'cookie small -> 12'); }
    { local *CGI::Cookie::fetch = sub { ('fcweb_fontsize' => E31Cookie->new('normal')) };
      is(main::fontsize_px(), 14, 'cookie normal -> 14'); }
    { local *CGI::Cookie::fetch = sub { ('fcweb_fontsize' => E31Cookie->new('large')) };
      is(main::fontsize_px(), 16, 'cookie large -> 16'); }
    { local *CGI::Cookie::fetch = sub { ('fcweb_fontsize' => E31Cookie->new('SMALL')) };
      is(main::fontsize_px(), 12, 'cookie value is case-insensitive'); }
    { local *CGI::Cookie::fetch = sub { ('fcweb_fontsize' => E31Cookie->new('32px;}body{x')) };
      is(main::fontsize_px(), 16, 'junk cookie -> 16 (whitelist; CSS-injection-safe)'); }
    { local *CGI::Cookie::fetch = sub { ('fcweb_fontsize' => E31Cookie->new('')) };
      is(main::fontsize_px(), 16, 'empty cookie -> 16'); }
}

# --- page_head wiring (source) -------------------------------------------
like($src, qr/my \$fs_px = fontsize_px\(\);/, 'page_head computes the base size');
like($src, qr/<style>html\{font-size:\$\{fs_px\}px\}/,
     'page_head emits html{font-size:<px>} for the first paint');
like($src, qr/\. fontsize_control_html\(\)\s*\n\s*\. qq\{<div class="user-info">/s,
     'the control is placed immediately left of the user name');

# --- control markup + live JS (source) ----------------------------------
ok(main->can('fontsize_control_html'), 'fontsize_control_html defined');
my $ctl = main::fontsize_control_html();
like($ctl, qr/class="fontsize-control"/,            'control container present');
like($ctl, qr/data-fs="small".*data-fs="normal".*data-fs="large"/s, 'three levels, in order');
like($ctl, qr/role="group"/,                        'control is an aria group');
like($ctl, qr/document\.documentElement\.style\.fontSize/, 'JS sets the root font-size live');
like($ctl, qr/document\.cookie='fcweb_fontsize='/,  'JS writes the fcweb_fontsize cookie');
like($ctl, qr/Max-Age=31536000/,                    'cookie persists ~1 year');
like($ctl, qr/SameSite=Lax/,                        'cookie is SameSite=Lax');
like($ctl, qr/location\.protocol==='https:'\)\?';Secure'/, 'cookie Secure only on HTTPS');
like($ctl, qr/aria-pressed/,                        'active level exposed to assistive tech');

# --- CSS: control styling + em-scaled donut ------------------------------
like($css, qr/\.fontsize-control\s*\{[^}]*margin-left:\s*auto/s,
     'control is right-aligned (carries the margin-left:auto)');
like($css, qr/\.user-info\s*\{[^}]*margin-left:\s*0/s,
     'user-info no longer carries the auto (control does)');
like($css, qr/\.dash-donut\s*\{[^}]*width:\s*7\.5em;[^}]*height:\s*7\.5em/s,
     'donut sized in em so it scales with the text level');

# --- donut markup uses the class, not fixed px ---------------------------
my ($donut) = $src =~ /sub dash_donut \{(.*?)\n\}/s;
ok($donut, 'located dash_donut');
like($donut, qr/<svg class="dash-donut" viewBox="0 0 128 128"/, 'donut svg uses the em-sized class');
unlike($donut, qr/<svg width="120" height="120"/, 'donut no longer hardcodes 120x120 px');

done_testing();
