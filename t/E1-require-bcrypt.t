use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# F-01. Crypt::Bcrypt is absent in this environment, so these exercise the
# require/fallback logic directly.

# REQUIRE_BCRYPT=0 -> legacy Apache MD5 ($apr1$) fallback, which still verifies.
{
    my ($cfg) = make_config(REQUIRE_BCRYPT => 0);
    load_cgi($cfg); main::read_config();
    ok(!main::bcrypt_available(), 'precondition: Crypt::Bcrypt not installed here');
    my $h = main::password_hash('secret');
    like($h, qr/^\$apr1\$/,                 'REQUIRE_BCRYPT=0 falls back to $apr1$');
    ok(main::verify_password('secret', $h), 'the fallback hash verifies');
}

# REQUIRE_BCRYPT=1 with no bcrypt -> password_hash dies rather than write a weak hash.
{
    my ($cfg) = make_config(REQUIRE_BCRYPT => 1);
    load_cgi($cfg); main::read_config();
    my $h = eval { main::password_hash('secret') };
    ok($@ && !defined $h,          'REQUIRE_BCRYPT=1 without bcrypt: password_hash dies');
    like($@, qr/REQUIRE_BCRYPT/,   'die message names REQUIRE_BCRYPT');
}

# Source wiring: login is refused up front, and the login screen shows it.
{
    my $src = do { open(my $fh,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$fh> };
    like($src, qr/\$REQUIRE_BCRYPT && !bcrypt_available\(\)/, 'do_login gate present');
    like($src, qr/Login disabled:.*Crypt::Bcrypt/s,          'login screen shows the disabled banner');
    like($src, qr/die "REQUIRE_BCRYPT is set but Crypt::Bcrypt/, 'password_hash backstop die present');
}

done_testing();
