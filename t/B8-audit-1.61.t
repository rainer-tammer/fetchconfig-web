use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);
use Time::HiRes ();

my $src = do { open(my $fh, '<', cgi_path()) or die $!; local $/; <$fh> };

# --- V7 / V6: std_header defaults, HSTS only with TLS, caller override -------
{
    my ($b) = $src =~ /sub std_header \{(.*?)\n\}/s;
    like($b, qr/'-Cache_Control'\s*=>\s*'no-store, no-cache, must-revalidate'/, 'V7: Cache-Control no-store');
    like($b, qr/'-Pragma'\s*=>\s*'no-cache'/,                                   'V7: Pragma no-cache');
    like($b, qr/\$HTTPS_ENABLED \? \('-Strict_Transport_Security'/,           'V6: HSTS gated on HTTPS_ENABLED');
    like($b, qr/\@args,\s*# caller's args win/,                                 'std_header: caller can override a default');
}

# --- V4: no multi-second sleep on the login failure paths ---------------------
{
    my ($login) = $src =~ /sub do_login \{(.*?)\n\}/s;
    unlike($login, qr/\bsleep\s*\(?\s*[25]\b/, 'V4: no sleep 2/5 in do_login');
    like($login, qr/login_jitter\(\)/,          'V4: jitter used instead');
    my ($j) = $src =~ /sub login_jitter \{(.*?)\}/s;
    like($j, qr/0\.05 \+ rand\(0\.05\)/, 'V4: jitter is 50-100 ms');
}

# --- V3: a nonexistent user still costs one verify ----------------------------
{
    my ($login) = $src =~ /sub do_login \{(.*?)\n\}/s;
    like($login, qr/verify_password\(\$password, dummy_password_hash\(\)\)/, 'V3: dummy verify when user missing');
    my ($c) = make_config(); load_cgi($c); main::read_config();
    no warnings 'once';
    my $d1 = main::dummy_password_hash(); my $d2 = main::dummy_password_hash();
    is($d1, $d2, 'V3: dummy hash is stable within the process');
    like($d1, qr/^\$(2b|apr1)\$/, 'V3: dummy hash uses the live algorithm');
}

# --- V1: reset link only from SITE_URL --------------------------------------
{
    my ($c) = make_config(EMAIL => 1, SMTP_HOST => 'localhost', EMAIL_FROM => 'x@y.de',
                          SITE_URL => 'https://fc.example.com/');
    load_cgi($c); main::read_config();
    no warnings 'once', 'redefine';
    local *main::script_url = sub { '/cgi-bin/fetchconfig-web.cgi' };
    local $ENV{HTTP_HOST} = 'attacker.example';     # must be ignored
    my $link = main::_reset_link('a' x 32);
    is($link, 'https://fc.example.com/cgi-bin/fetchconfig-web.cgi?action=reset_token&tok=' . ('a' x 32),
       'V1: link built from SITE_URL (trailing slash stripped), Host ignored');
    unlike($link, qr/attacker/, 'V1: attacker Host never appears in the link');

    my ($c2) = make_config(EMAIL => 1, SMTP_HOST => 'localhost', EMAIL_FROM => 'x@y.de');
    load_cgi($c2); main::read_config();
    ok(!defined main::_reset_link('a' x 32), 'V1: no SITE_URL -> no link is built at all');
    like($src, qr/reset link NOT emailed: SITE_URL is not configured/, 'V1: refusal is audited');
    # Every forgot-password outcome is audited, so "I got no email" is diagnosable.
    like($src, qr/reset NOT sent: requests from .* are throttled/, 'throttled reset is audited');
    like($src, qr/reset NOT sent: no account matches/,            'unknown-user reset is audited');
    like($src, qr/reset NOT sent: no email address on file/,      'no-email reset is audited');
    like($src, qr/reset NOT sent: could not create a reset token/, 'token-fail reset is audited');
}

# --- V2: every forgot-password request counts; fixed time floor ----------------
{
    my ($fp) = $src =~ /sub do_forgot_password \{(.*?)\n\}/s;
    # the record call must precede the username lookup (i.e. be unconditional)
    my $rec = index($fp, "login_record_failure(\$dbh, 'ip', \$ip)");
    my $lk  = index($fp, 'db_user_exists');
    ok($rec > -1 && $lk > -1 && $rec < $lk, 'V2: throttle counted before/independent of account lookup');
    like($fp, qr/Time::HiRes::sleep\(RESET_FLOOR_SECS - \$elapsed\)/, 'V2: padded to the floor');
    like($src, qr/use constant RESET_FLOOR_SECS => 0\.5;/,            'V2: floor is 0.5 s');
}

# --- V5: SHA-256 token hash; no-referrer on reset pages ------------------------
{
    my ($c) = make_config(); load_cgi($c); main::read_config();
    no warnings 'once';
    my $h = main::_reset_token_hash('abc');
    like($h, qr/^[0-9a-f]{64}$/, 'V5: token hash is SHA-256 hex');
    is($h, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'V5: matches the known SHA-256 of "abc"');
    my @nr = $src =~ /'-Referrer_Policy' => 'no-referrer'/g;
    cmp_ok(scalar @nr, '>=', 3, 'V5: no-referrer on the reset pages');
}

# --- V10: config file mode warning -------------------------------------------
{
    my ($c) = make_config();
    chmod 0644, $c;                       # loosen it on purpose
    load_cgi($c); main::read_config();
    no warnings 'once';
    like($main::SECURITY_WARNING // '', qr/is mode 0644; it contains passwords and must be 0600/,
         'V10: 0644 config file raises the SECURITY warning');
    # It is rendered red, on its own line, above the copyright line.
    my $foot = main::page_foot();
    like($foot, qr{<div class="footer-warn security-warn">.*?0644.*?</div>\s*<div class="footer-line">}s,
         'V10: security warning is a red block above the copyright line');
    chmod 0600, $c;
    $main::SECURITY_WARNING = undef; main::read_config();
    ok(!defined $main::SECURITY_WARNING, 'V10: 0600 config file is quiet');
    # Operational warnings stay amber, also above the copyright line.
    local $main::AUDIT_WARNING = 'audit log write failed: x';
    like(main::page_foot(), qr{<div class="footer-warn audit-warn">.*?</div>\s*<div class="footer-line">}s,
         'operational warning is amber, above the copyright line');
}

# --- V11: DEFAULT_PASSWORD masked; login_record_failure is transactional ------
{
    my ($c) = make_config(); load_cgi($c); main::read_config();
    no warnings 'once';
    ok(main::cfg_key_is_secret('DEFAULT_PASSWORD', 1), 'V11: DEFAULT_PASSWORD masked');
    my ($lrf) = $src =~ /sub login_record_failure \{(.*?)\n\}/s;
    like($lrf, qr/begin_work/, 'V11: throttle upsert runs in a transaction');
    like($lrf, qr/Lost the race.*increment it/s, 'V11: PK-collision retry present');
}

# --- version ----------------------------------------------------------------
like($src, qr/use constant APP_VERSION => '2\.00';/, 'version bumped to 2.00');


# --- fetchconfig-web-dbsetup.pl's generated config covers every registered key -------------------
# (keys only used with EMAIL_AUTH=1 are commented out in the sample, by design)
{
    my $ds = do { open(my $fh, '<', "$FindBin::Bin/../fetchconfig-web-dbsetup.pl") or die $!; local $/; <$fh> };
    my ($sub) = $ds =~ /(sub cfg_body \{.*?\nCFG\n\})/s;
    ok($sub, 'fetchconfig-web-dbsetup.pl: cfg_body found');
    our $CFG_PATH = '/etc/fetchconfig-web.cfg';
    eval $sub; die $@ if $@;
    my $out = cfg_body('fc', 'fcu', 'pw', 'localhost');
    my %gen; $gen{$1} = 1 while $out =~ /^([A-Z_]+)\s*=/mg;
    my %reg; $reg{$1} = 1 while $src =~ /^\s*\[ '([A-Z_]+)',/mg;
    my %optional = map { $_ => 1 } qw(SMTP_USER SMTP_PASS);
    my @missing = grep { !$gen{$_} && !$optional{$_} } sort keys %reg;
    is_deeply(\@missing, [], 'fetchconfig-web-dbsetup.pl: every registered config key is in the generated config')
        or diag("missing: @missing");
    my @unknown = grep { !$reg{$_} } sort keys %gen;
    is_deeply(\@unknown, [], 'fetchconfig-web-dbsetup.pl: generated config has no unregistered keys')
        or diag("unknown: @unknown");
    for (qw(MAX_PASSWORD_LENGTH PASSWORD_MIN_UPPER PASSWORD_MIN_LOWER PASSWORD_MIN_DIGIT
            PASSWORD_MIN_SPECIAL PASSWORD_MIN_CLASSES SITE_URL GENERIC_SYNTAX EMAIL)) {
        ok($gen{$_}, "fetchconfig-web-dbsetup.pl: writes $_");
    }
}

done_testing();
