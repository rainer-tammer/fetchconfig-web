use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.17.15: deleting an option in the device-table editor restores it to that
# card's "+ add option" menu. Adding an option removes it from the menu (so it
# can't be added twice); the delete handler must put it back, otherwise
# add -> delete -> re-add is impossible for the rest of the session (the option
# vanishes from the dropdown).
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# The add path still removes the chosen option from the menu (no change there).
like($src, qr/if \(!repeatable\[key\]\) opt\.remove\(\);/, 'adding an option removes it from the menu');

# The restore helper exists and is wired into the delete handler.
like($src, qr/function readdAddOption\(card, key\)/,       'readdAddOption helper defined');
like($src, qr/okey = mm\[1\]/,                             'delete handler recovers the option key from the control name');
like($src, qr/readdAddOption\(card, okey\)/,              'delete handler restores the option to the menu');

# Restore details: skips non-restorable keys, dedupes, carries the catalog type,
# and inserts in sorted order (matching the server-rendered menu).
my ($body) = $src =~ /function readdAddOption\(card, key\) \{(.*?)\n  \}/s;
ok($body, 'located readdAddOption body');
like($body, qr/key === 'site' \|\| key === 'report_hide'/, 'skips the auto site field and the repeatable report_hide');
like($body, qr/if \(sel\.options\[i\]\.value === key\) return;/, 'does not add a duplicate option');
like($body, qr/OPT_TYPES\b.*\|\| 'text'/s,                'carries the catalog data-type (falls back to text)');
like($body, qr/key < opts\[j\]\.value.*insertBefore/s,    'inserts in sorted position');

# The key-recovery regex tolerates the repeatable __<n> suffix.
like($src, qr{/_opt_\(\.\+\?\)\(\?:__\\d\+\)\?\$/},       'key regex strips a repeatable __<n> suffix');

done_testing();
