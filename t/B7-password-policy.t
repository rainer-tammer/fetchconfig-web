use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# Default policy: only MIN/MAX length + differ-from-default/username.
{
    my ($c) = make_config(MIN_PASSWORD_LENGTH => 8, MAX_PASSWORD_LENGTH => 64,
                          DEFAULT_PASSWORD => 'fetchconfig');
    load_cgi($c); main::read_config();
    no warnings 'once';
    ok(!defined main::password_policy_error('abcd1234', 'bob'), 'default: 8-char ok');
    like(main::password_policy_error('abc', 'bob'), qr/at least 8/, 'default: too short');
    like(main::password_policy_error('x' x 65, 'bob'), qr/at most 64/, 'default: too long');
    like(main::password_policy_error('fetchconfig', 'bob'), qr/default password/,
         'default: equals DEFAULT_PASSWORD rejected');
    like(main::password_policy_error('Operator', 'operator'), qr/username/,
         'default: equals username (case-insensitive) rejected');
}

# Composition rules.
{
    my ($c) = make_config(MIN_PASSWORD_LENGTH => 6,
                          PASSWORD_MIN_UPPER => 1, PASSWORD_MIN_LOWER => 1,
                          PASSWORD_MIN_DIGIT => 1, PASSWORD_MIN_SPECIAL => 1);
    load_cgi($c); main::read_config();
    no warnings 'once';
    like(main::password_policy_error('abcdefg', 'u'), qr/uppercase/,  'needs uppercase');
    like(main::password_policy_error('ABCDEFG', 'u'), qr/lowercase/,  'needs lowercase');
    like(main::password_policy_error('Abcdefg', 'u'), qr/digit/,      'needs digit');
    like(main::password_policy_error('Abcdef1', 'u'), qr/special/,    'needs special');
    ok(!defined main::password_policy_error('Abcde1!', 'u'),          'all classes present ok');
}

# Class-count rule (N of 4).
{
    my ($c) = make_config(MIN_PASSWORD_LENGTH => 6, PASSWORD_MIN_CLASSES => 3);
    load_cgi($c); main::read_config();
    no warnings 'once';
    like(main::password_policy_error('abcdef12', 'u'), qr/at least 3 of/, '2 classes < 3 rejected');
    ok(!defined main::password_policy_error('Abcdef12', 'u'), '3 classes ok');
}

# Hint text and config-viewer registration.
{
    my ($c) = make_config(MIN_PASSWORD_LENGTH => 10, PASSWORD_MIN_DIGIT => 2);
    load_cgi($c); main::read_config();
    no warnings 'once';
    my $h = main::password_policy_hint();
    like($h, qr/10-/,                 'hint shows min length');
    like($h, qr/at least 2 digit/,    'hint shows digit rule');
    like($h, qr/differ from your username/, 'hint mentions username/default rule');

    # Registry has the new keys (and read_config reads them -- B3 enforces sync).
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    like($src, qr/\[ 'MAX_PASSWORD_LENGTH',/,  'MAX_PASSWORD_LENGTH registered');
    like($src, qr/\[ 'PASSWORD_MIN_CLASSES',/, 'PASSWORD_MIN_CLASSES registered');
    # All four password-set points use the policy helper.
    my @calls = $src =~ /password_policy_error\(/g;
    cmp_ok(scalar @calls, '>=', 4, 'policy enforced at all password-set points');
}

done_testing();
