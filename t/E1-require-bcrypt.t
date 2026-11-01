use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# F-01. These must pass whether or not Crypt::Bcrypt is installed, so the
# "bcrypt unavailable" behaviour is exercised by mocking bcrypt_available()
# rather than depending on the environment.

# REQUIRE_BCRYPT=0 + no bcrypt -> legacy Apache MD5 ($apr1$) fallback, which verifies.
{
    my ($cfg) = make_config(REQUIRE_BCRYPT => 0);
    load_cgi($cfg); main::read_config();
    no warnings 'redefine';
    local *main::bcrypt_available = sub { 0 };
    my $h = main::password_hash('secret');
    like($h, qr/^\$apr1\$/,                 'REQUIRE_BCRYPT=0, no bcrypt -> $apr1$ fallback');
    ok(main::verify_password('secret', $h), 'the fallback hash verifies');
}

# REQUIRE_BCRYPT=1 + no bcrypt -> password_hash dies rather than write a weak hash.
{
    my ($cfg) = make_config(REQUIRE_BCRYPT => 1);
    load_cgi($cfg); main::read_config();
    no warnings 'redefine';
    local *main::bcrypt_available = sub { 0 };
    my $h = eval { main::password_hash('secret') };
    ok($@ && !defined $h,          'REQUIRE_BCRYPT=1, no bcrypt -> password_hash dies');
    like($@, qr/REQUIRE_BCRYPT/,   'die message names REQUIRE_BCRYPT');
}

# When bcrypt IS available, password_hash writes a $2b$ hash (regardless of
# REQUIRE_BCRYPT). Skipped on a stack without Crypt::Bcrypt.
{
    my ($cfg) = make_config(REQUIRE_BCRYPT => 1);
    load_cgi($cfg); main::read_config();
    SKIP: {
        skip 'Crypt::Bcrypt not installed', 2 unless main::bcrypt_available();
        my $h = main::password_hash('secret');
        like($h, qr/^\$2b\$/,                   'bcrypt present -> $2b$ hash');
        ok(main::verify_password('secret', $h), 'the bcrypt hash verifies');
    }
}

# Source wiring (environment-independent).
{
    my $src = do { open(my $fh,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$fh> };
    like($src, qr/\$REQUIRE_BCRYPT && !bcrypt_available\(\)/, 'do_login gate present');
    like($src, qr/Login disabled:.*Crypt::Bcrypt/s,          'login screen shows the disabled banner');
    like($src, qr/die "REQUIRE_BCRYPT is set but Crypt::Bcrypt/, 'password_hash backstop die present');
}

done_testing();
