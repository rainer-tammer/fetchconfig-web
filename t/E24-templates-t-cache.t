use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# --------------------------------------------------------------------------
# 2.17.11: cross-request cache for `fetchconfig.pl -t`.
#
# The device-table editor forked the engine (-t) on every load just to detect a
# broken-template install. Under FastCGI the result is now kept across requests
# and reused while the device table is unchanged AND the result is younger than
# TEMPLATES_T_TTL, so a healthy install forks at most once per TTL. Plain CGI is
# unaffected (fresh process per request => the persist var is always undef).
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
{ no warnings 'once'; main::read_config(); }
no warnings 'redefine','once';

ok(main->can('run_templates_t'),     'run_templates_t defined');
ok(defined &main::_templates_t_sig,  '_templates_t_sig helper defined');
is(main::TEMPLATES_T_TTL(), 60,      'TTL is 60s');

# Count engine forks; make the signature controllable.
my $FORKS = 0;
*main::run_fetchconfig = sub { $FORKS++; return ("i\tdefault\t/t/x.tmpl\tcisco-ios\t/t", "", 0, 0); };
*main::collapse_model_registration = sub { $_[0] };
our $SIG = "100:200";
*main::_templates_t_sig = sub { $SIG };

# reset_request_state clears only the per-request memo, never the persist cache.
sub newreq { no strict 'refs'; ${'main::_templates_t_cache'} = undef; }

# Three back-to-back requests, table unchanged, within TTL -> one fork.
newreq(); my $r1 = main::run_templates_t();
newreq(); my $r2 = main::run_templates_t();
newreq(); main::run_templates_t();
is($FORKS, 1, 'unchanged table, 3 requests -> engine forked once');
is($r2->{rc}, 0, 'cached result carries the real rc');
is_deeply($r2->{rows}, $r1->{rows}, 'cached rows are the same structure');

# Device-table change (signature changes) -> re-fork immediately.
$SIG = "101:205";
newreq(); main::run_templates_t();
is($FORKS, 2, 'device-table change re-forks at once');

# A save invalidates explicitly.
main::_invalidate_table_caches();
newreq(); main::run_templates_t();
is($FORKS, 3, '_invalidate_table_caches drops the cross-request cache');

# TTL expiry re-forks even when the table is unchanged.
{ no strict 'refs'; ${'main::_templates_t_persist'}->{checked_at} -= (main::TEMPLATES_T_TTL() + 1); }
newreq(); main::run_templates_t();
is($FORKS, 4, 'result older than the TTL re-forks');

# A fork failure is NOT persisted (usually transient): the next call re-forks.
main::_invalidate_table_caches();
*main::run_fetchconfig = sub { $FORKS++; return (undef, "boom", undef, 1); };
newreq(); my $fe = main::run_templates_t();
is($fe->{rc}, undef, 'fork failure yields rc undef');
newreq(); main::run_templates_t();
is($FORKS, 6, 'fork failure is not cached -> next request re-forks');

# The persist var is intentionally absent from reset_request_state (clearing it
# per request would defeat the cross-request cache).
my $src = do { local $/; open(my $f, '<', FCWebTest::cgi_path()) or die $!; <$f> };
my ($reset) = $src =~ /sub reset_request_state \{(.*?)\n\}/s;
ok($reset, 'found reset_request_state body');
unlike($reset, qr/\$_templates_t_persist/, 'persist cache is NOT cleared per request');
my ($inval) = $src =~ /sub _invalidate_table_caches \{(.*?)\n\}/s;
ok($inval, 'found _invalidate_table_caches body');
like($inval, qr/\$_templates_t_persist\s*=\s*undef;/, 'persist cache IS cleared on save/invalidate');

# --------------------------------------------------------------------------
# read_allowed_dirs shares the same cross-request-cache pattern: --list-allowed-dirs
# is a second ~340ms engine fork that used to run on every editor load.
# --------------------------------------------------------------------------
{
    no warnings 'redefine','once';
    my $FORKS = 0;
    local *main::run_fetchconfig = sub { $FORKS++; return ("d1\trepository\tmain\t/var/fc", "", 0, 0); };
    local *main::collapse_model_registration = sub { $_[0] };
    our $SIG2 = '100:200';
    local *main::_templates_t_sig = sub { $SIG2 };
    my $newreq = sub { no strict 'refs'; ${'main::_allowed_dirs_cache'} = undef; };

    $newreq->(); my $a = main::read_allowed_dirs();
    $newreq->(); main::read_allowed_dirs();
    $newreq->(); main::read_allowed_dirs();
    is($FORKS, 1, 'read_allowed_dirs: unchanged table, 3 requests -> forked once');
    is($a->{present}, 1, 'parsed the allowed-dirs result');

    $SIG2 = '101:205';
    $newreq->(); main::read_allowed_dirs();
    is($FORKS, 2, 'read_allowed_dirs: device-table change re-forks');

    main::_invalidate_table_caches();
    $newreq->(); main::read_allowed_dirs();
    is($FORKS, 3, 'read_allowed_dirs: _invalidate_table_caches drops the cache');

    { no strict 'refs'; ${'main::_allowed_dirs_persist'}->{checked_at} -= (main::TEMPLATES_T_TTL() + 1); }
    $newreq->(); main::read_allowed_dirs();
    is($FORKS, 4, 'read_allowed_dirs: result older than the TTL re-forks');

    main::_invalidate_table_caches();
    local *main::run_fetchconfig = sub { $FORKS++; return (undef, "boom", undef, 1); };
    $newreq->(); main::read_allowed_dirs();
    $newreq->(); main::read_allowed_dirs();
    is($FORKS, 6, 'read_allowed_dirs: a fork failure is not cached');
}
unlike($reset, qr/\$_allowed_dirs_persist/, 'allowed-dirs persist cache NOT cleared per request');
like($inval, qr/\$_allowed_dirs_persist\s*=\s*undef;/, 'allowed-dirs persist cache cleared on save/invalidate');

done_testing();
