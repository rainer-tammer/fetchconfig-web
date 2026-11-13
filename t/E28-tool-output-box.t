use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.17.16: tool_output_box() renders captured engine output in the standard
# dark box (<pre class="config">) with the per-model "registering model:"
# preamble collapsed -- the same treatment every tool-output window uses. The
# device-backups View error path (an orphan device => fetchconfig "unknown
# device") used a bare <p class="error"> that dumped the whole 26-line
# registration list; it now uses the box.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

ok(main->can('tool_output_box'), 'tool_output_box helper defined');

# empty / undef -> no markup
is(main::tool_output_box(''),    '', 'empty text -> empty string');
is(main::tool_output_box(undef), '', 'undef text -> empty string');

# a representative engine error with the registering-model preamble
my $raw = join("\n",
    'fetchconfig.pl -l failed (exit 1): fetchconfig.pl: info: -----[fetchconfig]-----',
    'fetchconfig.pl: info: version 9.80',
    'fetchconfig.pl: debug: registering model: generic',
    'fetchconfig.pl: debug: registering model: cisco-ios',
    'fetchconfig.pl: debug: registering model: cisco-ios-ssh',
    'fetchconfig.pl: debug: loading device list: /usr/local/fetchconfig/device_table',
    'fetchconfig.pl: error: dev=rtr01-template-cisco: unknown device (not found in -devices device list)',
);
my $box = main::tool_output_box($raw);

like($box,   qr/<pre class="config">/,          'wraps output in the dark tool-output box');
like($box,   qr/models registered/,             'collapses the registering-model preamble to a summary');
unlike($box, qr/registering model: cisco-ios\b/, 'individual "registering model:" lines are collapsed away');
like($box,   qr/unknown device/,                'keeps the real error line');
# output is HTML-escaped (the engine prints no angle brackets here, but verify
# the escape path is used by feeding one)
like(main::tool_output_box('a <b> c'), qr/a &lt;b&gt; c/, 'escapes HTML');

# --- the backups View error path now uses the box, not a bare <p class="error"> ---
my ($body) = $src =~ /sub show_backup_list \{(.*?)\n\}/s;
ok($body, 'located show_backup_list');
like($body, qr/if \(\$err\) \{.*?tool_output_box\(\$err\)/s, 'error path renders the engine output via tool_output_box');
unlike($body, qr/if \(\$err\) \{\s*print qq\{<p class="error">\} \. esc\(\$err\)/s,
     'error path no longer dumps the raw stderr in a bare <p class="error">');

done_testing();
