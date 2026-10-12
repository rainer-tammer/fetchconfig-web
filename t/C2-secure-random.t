use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

my ($c) = make_config(); load_cgi($c); main::read_config();
no warnings 'once', 'redefine';

# secure_random_bytes: exact length, non-constant, fail-closed on bad input.
is(length(main::secure_random_bytes(16)), 16, 'returns requested length (16)');
is(length(main::secure_random_bytes(1)),   1, 'returns requested length (1)');
isnt(main::secure_random_bytes(24), main::secure_random_bytes(24), 'two calls differ');
for my $bad (0, -1, undef, 'x', '1.5') {
    my $died = !eval { main::secure_random_bytes($bad); 1 };
    ok($died, "dies on bad length (" . (defined $bad ? "'$bad'" : 'undef') . ")");
}

# Session id: 24 bytes -> 48 hex chars, hex only.
my $sid = main::new_session_id();
like($sid, qr/^[0-9a-f]{48}$/, 'session id is 48 hex chars');

# No weak PRNG fallback remains in the security-sensitive generators.
{
    my $src = do { open(my $fh,'<',cgi_path()) or die $!; local $/; <$fh> };
    unlike($src, qr/chr\(int\(rand\(256\)\)\)/, 'no rand(256) fallback for secrets');
    # All four sites use the helper.
    my @calls = $src =~ /secure_random_bytes\(/g;
    cmp_ok(scalar @calls, '>=', 4, 'helper used at session/token/salt sites');
}

# Reset-token creation fails CLOSED: if the RNG dies, it returns undef (no weak
# token, no exception leaking to the caller) -- preserving "no link sent".
{
    local *main::secure_random_bytes = sub { die "rng unavailable" };
    my $r = main::reset_token_create(bless({}, 'MRNGDB'), 'someuser');
    ok(!defined $r, 'reset_token_create returns undef when the RNG fails');
}

done_testing();

package MRNGDB;
sub do { 1 }
sub disconnect {}
