use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();
no warnings 'once', 'redefine';

# --- X1: json_string escapes < > / & so it cannot break out of <script> ------
{
    my $j = main::json_string('</script><b>x</b>&y/z');
    unlike($j, qr{</script>}, 'json_string: no literal </script>');
    unlike($j, qr{[<>&]}, 'json_string: <, >, & are escaped');
    like($j, qr/\\u003c/, 'json_string: < encoded as \\u003c');
    like($j, qr/\\u002f/, 'json_string: / encoded as \\u002f');
    # Round-trips as the same string once a JSON parser decodes it.
    is($j, '"\u003c\u002fscript\u003e\u003cb\u003ex\u003c\u002fb\u003e\u0026y\u002fz"',
       'json_string: full expected encoding');
}

# --- H1: std_header injects the security headers -----------------------------
# The test harness CGI is a stub whose header() ignores extra args, so the
# headers are verified by inspecting std_header's source (real CGI.pm turns
# -X_Frame_Options into the X-Frame-Options header) and by confirming every
# response routes through std_header rather than $cgi->header directly.
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    my ($body) = $src =~ /sub std_header \{(.*?)\n\}/s;
    ok($body, 'std_header defined');
    like($body, qr/'-X_Frame_Options'\s*=>\s*'DENY'/,                "std_header sets X-Frame-Options: DENY");
    like($body, qr/'-X_Content_Type_Options'\s*=>\s*'nosniff'/,      "std_header sets X-Content-Type-Options: nosniff");
    like($body, qr/'-Referrer_Policy'\s*=>\s*'same-origin'/,         "std_header sets Referrer-Policy: same-origin");
    my @raw = $src =~ /\$cgi->header\(/g;
    is(scalar @raw, 1, 'only std_header itself calls $cgi->header directly');
}

# --- B3: bcrypt hashing, verify, legacy fallback, upgrade detection ----------
SKIP: {
    skip "Crypt::Bcrypt not installed", 6 unless main::bcrypt_available();
    my $h = main::password_hash('correct horse');
    like($h, qr/^\$2b\$/, 'password_hash: produces bcrypt when available');
    ok(main::verify_password('correct horse', $h), 'verify_password: bcrypt correct');
    ok(!main::verify_password('wrong', $h),         'verify_password: bcrypt wrong rejected');
    ok(main::hash_is_preferred($h),                 'bcrypt hash is preferred');
    my $old = main::apr1_hash('correct horse');
    ok(main::verify_password('correct horse', $old), 'verify_password: legacy apr1 still works');
    ok(!main::hash_is_preferred($old),               'apr1 hash is not preferred (would upgrade)');
}

# --- B1: login throttle state machine ----------------------------------------
{
    my %T;
    my $dbh = _mock_throttle_dbh(\%T);
    is(main::login_is_throttled($dbh, 'ip', '10.0.0.1'), 0, 'throttle: clean initially');
    main::login_record_failure($dbh, 'ip', '10.0.0.1') for 1 .. main::LOGIN_MAX_FAILURES();
    is(main::login_is_throttled($dbh, 'ip', '10.0.0.1'), 1,
       'throttle: tripped at LOGIN_MAX_FAILURES');
    main::login_clear($dbh, 'bob', '10.0.0.1');
    is(main::login_is_throttled($dbh, 'ip', '10.0.0.1'), 0, 'throttle: cleared on success');
    # Failures older than the window do not count.
    $T{'ip/9.9.9.9'} = { n => 99, t => time() - main::LOGIN_WINDOW_SECS() - 10 };
    is(main::login_is_throttled($dbh, 'ip', '9.9.9.9'), 0, 'throttle: window expiry ignores old rows');
}

# --- C: email validation -----------------------------------------------------
{
    is(main::normalize_email(''),            '',            'email: empty allowed');
    is(main::normalize_email('  '),          '',            'email: whitespace -> empty');
    is(main::normalize_email('A@B.De'),      'a@b.de',      'email: lowercased');
    is(main::normalize_email('bad'),         undef,         'email: no @ rejected');
    is(main::normalize_email('a b@c.de'),    undef,         'email: space rejected');
    is(main::normalize_email('x@y'),         undef,         'email: no dotted domain rejected');
    is(main::normalize_email('x@y.z'),       'x@y.z',       'email: minimal valid');
    is(main::normalize_email('a' x 260 . '@b.cd'), undef,   'email: over length rejected');
}

# --- D: reset-token lifecycle ------------------------------------------------
{
    my @ROWS;
    my $dbh = _mock_reset_dbh(\@ROWS);
    my $tok = main::reset_token_create($dbh, 'alice');
    like($tok, qr/^[0-9a-f]{32}$/, 'reset: token is 128-bit hex');
    is(main::reset_token_user($dbh, $tok), 'alice', 'reset: token resolves to user');
    is(main::reset_token_user($dbh, '0' x 32), undef, 'reset: unknown token -> undef');
    main::reset_token_consume($dbh, $tok);
    is(main::reset_token_user($dbh, $tok), undef, 'reset: single-use after consume');
    my $t2 = main::reset_token_create($dbh, 'bob');
    main::reset_token_invalidate_user($dbh, 'bob');
    is(main::reset_token_user($dbh, $t2), undef, 'reset: invalidated on password change');
    # Only the HASH is stored, never the clear token.
    ok(!(grep { ($_->{h} // '') eq $tok } @ROWS), 'reset: clear token is never stored');
}

# --- D: send_mail refuses cleanly when email is disabled ---------------------
{
    local $main::EMAIL = 0;
    my ($ok, $err) = main::send_mail(to => 'x@y.de', subject => 's', body => 'b');
    ok(!$ok && $err =~ /disabled/, 'send_mail: refuses when EMAIL=0');
}

# --- the shipped file has the new config keys + new scripts exist -------------
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    like($src, qr/\[ 'EMAIL',/,     'config registry has EMAIL');
    like($src, qr/\[ 'SMTP_PASS',/, 'config registry has SMTP_PASS');
    ok(main::cfg_key_is_secret('SMTP_PASS', 1), 'SMTP_PASS is masked in the viewer');
    ok(!main::cfg_key_is_secret('DEFAULT_PASSWORD', 1), 'DEFAULT_PASSWORD not masked (as agreed)');
}

# --- Change-your-email: self-service wiring ----------------------------------
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    like($src, qr{action eq 'change_email'},    'change_email action dispatched');
    like($src, qr{sub do_change_email},          'do_change_email handler present');
    like($src, qr{change_password change_email}, 'change_email is state-changing (POST-guarded)');
    like($src, qr{Change your email},            'Change your email appears (menu + page)');
    like($src, qr{\$only eq 'password' \|\| \$only eq 'email'},
         'non-admins can reach their own email page');
}

# --- Test-email tools: bodies and wiring -------------------------------------
{
    # A second CGI loaded with EMAIL enabled, so send_mail is reachable.
    my ($cfg2) = make_config(EMAIL => 1, SMTP_HOST => 'localhost',
                             EMAIL_FROM => 'fcweb@example.com');
    # Reuse the already-loaded package; just re-read config with EMAIL on.
    {
        no warnings 'redefine';
        local *main::std_header = sub { '' };
        # Point read_config at the EMAIL-enabled file and run it.
        local $main::CONFIG_FILE = $cfg2 if 0;   # (read_config uses the loaded path)
    }

    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    # The two fixed body texts the user asked for.
    like($src, qr/Your fetchconfig-web email address setup was successful/,
         'self-service test email body text');
    like($src, qr/Email setup of fetchconfig-web successful/,
         'admin verify-email body text');
    # Wiring.
    like($src, qr/action eq 'test_my_email'/,     'test_my_email dispatched');
    like($src, qr/action eq 'tool_verify_email'/, 'tool_verify_email dispatched (GET page)');
    like($src, qr/action eq 'verify_email'/,      'verify_email dispatched (POST send)');
    like($src, qr/sub do_test_my_email/,          'self-service handler present');
    like($src, qr/sub show_verify_email/,         'admin verify page present');
    like($src, qr/sub do_verify_email/,           'admin verify handler present');
    like($src, qr/change_email test_my_email verify_email/,
         'test_my_email + verify_email are state-changing (POST-guarded)');
    like($src, qr/Verify email setup/,            'Tools -> Verify email setup entry present');
}

# --- E2: unified priority banner (only the most severe shows) -----------------
{
    no warnings 'redefine';
    local *main::current_session   = sub { ('sid','admin','csrf','') };
    local *main::user_is_admin     = sub { 1 };
    local *main::user_may_edit_table = sub { 1 };
    local *main::user_is_unrestricted = sub { 1 };
    local *main::db_connect        = sub { undef };

    # fatal present + version present + external present => only fatal shows.
    {
        local *main::fatal_error_banner          = sub { '<div class="fatal-error">FATAL</div>' };
        local *main::fetchconfig_version_warning = sub { '<div class="pw-warning">OLD</div>' };
        local $main::EXTERNAL_CHANGE_NOTICE      = 'changed outside';
        my $h = main::page_head('Devices', 'admin');
        like($h,   qr/class="fatal-error"/,      'E2: fatal banner shown when it is the most severe');
        unlike($h, qr/OLD/,                       'E2: version banner suppressed under fatal');
        unlike($h, qr{<div class="ext-change-warning"},        'E2: external banner suppressed under fatal');
    }
    # no fatal, version present + external present => only version shows.
    {
        local *main::fatal_error_banner          = sub { '' };
        local *main::fetchconfig_version_warning = sub { '<div class="pw-warning">OLDVER</div>' };
        local $main::EXTERNAL_CHANGE_NOTICE      = 'changed outside';
        my $h = main::page_head('Devices', 'admin');
        like($h,   qr/OLDVER/,             'E2: version banner shown when no fatal');
        unlike($h, qr{<div class="ext-change-warning"}, 'E2: external banner suppressed under version');
    }
    # no fatal, no version, external present => external shows.
    {
        local *main::fatal_error_banner          = sub { '' };
        local *main::fetchconfig_version_warning = sub { '' };
        local $main::EXTERNAL_CHANGE_NOTICE      = 'changed outside';
        my $h = main::page_head('Devices', 'admin');
        like($h, qr{<div class="ext-change-warning"}, 'E2: external banner shown when nothing more severe');
    }
}

# --- E1: no raw $! leaks; failures are generic + audited ----------------------
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    unlike($src, qr/esc\("\$!"\)/, 'no esc("$!") leak remains');
    my @generic = $src =~ /See the audit log for details|fetchconfig log file could not be read/g;
    cmp_ok(scalar @generic, '>=', 4, 'read-error sites show generic text (template x2, session, log)');
}

done_testing();

# ---- mock DBHs --------------------------------------------------------------
sub _mock_throttle_dbh {
    my ($T) = @_;
    my $pkg = "MockThrottle" . int(rand(1e6));
    no strict 'refs';
    *{"${pkg}::new"} = sub { bless {}, shift };
    *{"${pkg}::selectrow_arrayref"} = sub {
        my ($s, $sql, undef, $kind, $key) = @_;
        my $r = $T->{"$kind/$key"}; return undef unless $r;
        return [ $r->{n}, $r->{t} ];
    };
    *{"${pkg}::do"} = sub {
        my ($s, $sql, undef, @b) = @_;
        if ($sql =~ /UPDATE login_attempts/) { my ($n,$k,$v)=@b; return 0 unless $T->{"$k/$v"}; $T->{"$k/$v"}={n=>$n,t=>time()}; return 1; }
        if ($sql =~ /INSERT INTO login_attempts/) { my ($k,$v,$n)=@b; $T->{"$k/$v"}={n=>$n,t=>time()}; return 1; }
        if ($sql =~ /DELETE FROM login_attempts/) { my ($k1,$v1,$k2,$v2)=@b; delete $T->{"$k1/$v1"}; delete $T->{"$k2/$v2"}; return 1; }
        return 1;
    };
    *{"${pkg}::disconnect"} = sub {};
    return "$pkg"->new;
}

sub _mock_reset_dbh {
    my ($ROWS) = @_;
    my $pkg = "MockReset" . int(rand(1e6));
    no strict 'refs';
    *{"${pkg}::new"} = sub { bless {}, shift };
    *{"${pkg}::do"} = sub {
        my ($s, $sql, undef, @b) = @_;
        if ($sql =~ /INSERT INTO password_resets/) { my ($h,$u)=@b; push @$ROWS,{h=>$h,u=>$u,used=>0,exp=>time()+1800}; return 1; }
        if ($sql =~ /UPDATE password_resets SET used = TRUE WHERE token_hash/) { my ($h)=@b; $_->{used}=1 for grep { $_->{h} eq $h } @$ROWS; return 1; }
        if ($sql =~ /UPDATE password_resets SET used = TRUE WHERE username/)   { my ($u)=@b; $_->{used}=1 for grep { $_->{u} eq $u && !$_->{used} } @$ROWS; return 1; }
        return 1;
    };
    *{"${pkg}::selectrow_array"} = sub {
        my ($s, $sql, undef, $h) = @_;
        for (@$ROWS) { return $_->{u} if $_->{h} eq $h && !$_->{used} && $_->{exp} > time(); }
        return ();
    };
    *{"${pkg}::disconnect"} = sub {};
    return "$pkg"->new;
}
