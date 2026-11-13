use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.17.12: per-phase render timing in the device-table editor. With
# SHOW_RENDER_TIME=1, show_edit_table appends an HTML comment attributing the
# server render time to phases (auth/DB, parse, templates -t, inventory DB, row
# build), so a slow load is diagnosed rather than guessed. A no-op when off.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

my ($body) = $src =~ /sub show_edit_table \{(.*?)\n\}/s;
ok($body, 'located show_edit_table');

# The marker closure is a no-op unless SHOW_RENDER_TIME is on (zero cost in prod).
like($body, qr/my \$_mark = \$SHOW_RENDER_TIME/, 'phase marker is gated on SHOW_RENDER_TIME');
like($body, qr/\? sub \{ push \@_phase/,          'marker records a phase when enabled');
like($body, qr/: sub \{ \};/,                     'marker is a no-op when disabled');

# Each phase boundary is marked.
like($body, qr/\$_mark->\('auth\+site DB'\)/,          'marks the auth/site DB phase');
like($body, qr/\$_mark->\('slurp\+parse table'\)/,     'marks the parse phase');
like($body, qr/\$_mark->\('templates -t'\)/,           'marks the templates -t phase');
like($body, qr/\$_mark->\('model\+inventory init DB'\)/,'marks the model/inventory DB phase');
like($body, qr/\$_mark->\('build device rows'\)/,      'marks the row-build phase');

# The breakdown is printed as an HTML comment, only under SHOW_RENDER_TIME,
# with each entry showing the delta since the previous mark.
like($body, qr/if \(\$SHOW_RENDER_TIME\) \{/,          'breakdown is gated on SHOW_RENDER_TIME');
like($body, qr/render phases \(ms since previous mark\)/, 'emits the phase-breakdown comment');
like($body, qr/\(\$at - \$prev\) \* 1000/,            'reports per-phase deltas in ms');

done_testing();
