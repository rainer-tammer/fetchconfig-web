use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

is(main::version_cmp('9.60','9.60'),  0, '9.60 == 9.60');
is(main::version_cmp('9.59','9.60'), -1, '9.59 < 9.60');
is(main::version_cmp('9.60','9.59'),  1, '9.60 > 9.59');
is(main::version_cmp('9.64','9.60'),  1, '9.64 > 9.60');
is(main::version_cmp('10.0','9.64'),  1, '10.0 > 9.64');
is(main::version_cmp('9.9','9.60'),  -1, '9.9 < 9.60 (per-component numeric)');
# tagged components (e.g. 9.44-ACME) compare on the numeric parts
is(main::version_cmp('9.60-ACME','9.60'), 0, 'tag ignored on trailing component');

# The gate: installed < MIN (9.65) triggers a warning; >= does not.
for my $c ([qw(9.59 WARN)],[qw(9.60 WARN)],[qw(9.64 WARN)],[qw(9.65 OK)],[qw(10.0 OK)]) {
    my ($ver,$exp) = @$c;
    my $too_old = main::version_cmp($ver, main::MIN_FETCHCONFIG_VERSION()) < 0;
    is($too_old ? 'WARN' : 'OK', $exp, "gate: installed $ver vs min "
        . main::MIN_FETCHCONFIG_VERSION());
}
is(main::MIN_FETCHCONFIG_VERSION(), '9.65', 'MIN_FETCHCONFIG_VERSION is 9.65');

done_testing();
