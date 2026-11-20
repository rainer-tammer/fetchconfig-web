use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# Full-width list/detail pages carry the floating Top/Bottom navigation in the
# lower-right corner (top_bottom_nav). These three were missing it; each now
# emits it just before its final page_foot (anchored on a string unique to the
# page, since the handlers are large).
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

like($src, qr/Delete all debug logs.*?print top_bottom_nav\(\);/s,
     'tool_debug: Top/Bottom navigation added');
like($src, qr{</script>\nJS\n\n    print top_bottom_nav\(\);},
     'inventory_dashboard: Top/Bottom navigation added');
like($src, qr/Template list load time:.*?print top_bottom_nav\(\);/s,
     'view_templates: Top/Bottom navigation added');

done_testing();
