use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# The fetchconfig engine locks "<devices>.lock" next to any device table it is
# handed and does not remove its own lock. The web app creates those temp tables
# (fcweb-dev-*.tbl for Backup Now, fcweb-save-*.tbl for save validation), so the
# lock sidecars leaked into the session dir. The handlers now unlink their own
# "<tmp>.lock" immediately, and the stale-table sweep also clears older strays
# of both prefixes (and the pre-fix accumulation).
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# Immediate cleanup at both temp-table sites.
my $n = () = ($src =~ /unlink\("\$tmp\.lock"\)/g);
ok($n >= 2, "both temp-table paths unlink their <tmp>.lock sidecar (found $n)");

# The sweep now matches both prefixes and the .lock sidecar.
my ($sweep) = $src =~ /sub sweep_stale_backup_tables \{(.*?)\n\}/s;
ok($sweep, 'located sweep_stale_backup_tables');
like($sweep, qr/\\Afcweb-\(\?:dev\|save\)-\[A-Za-z0-9_\]\{8\}\\\.tbl\(\?:\\\.lock\)\?\\z/,
     'sweep regex matches fcweb-{dev,save}-*.tbl and the .tbl.lock sidecars');
like($sweep, qr/\$now - \$st\[9\] < \$max_age/, 'sweep still only removes files older than any possible run');

# The persistent single-file device-table lock is untouched by the sweep regex.
unlike('device_table.lock', qr/\Afcweb-(?:dev|save)-[A-Za-z0-9_]{8}\.tbl(?:\.lock)?\z/,
       'the reused device_table.lock is not matched by the sweep');

done_testing();
