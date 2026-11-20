use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# Step 2 (partial): the per-user LDAP option, the admin/@ guards, and the user
# rename (short name -> full UPN). The login path itself is still a later step.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# --- valid_username allows '@' (UPN) but not a leading dash ---------------
ok(main->can('valid_username'), 'valid_username defined');
ok( main::valid_username('tammer'),                 'plain short name ok');
ok( main::valid_username('tammer@net.schuler.de'),  'UPN with @ ok');
ok( main::valid_username('a.b-c_d@e.f'),            'dots/dashes/underscore/@ ok');
ok(!main::valid_username('-bad'),                   'leading dash rejected');
ok(!main::valid_username('has space'),              'space rejected');
ok(!main::valid_username(''),                       'empty rejected');
# db_get_user keeps allowing '@' (valid_id was too strict for usernames)
like($src, qr/\[\\w\.\@\]\[\\w\.\@\\-\]\*/, 'valid_username charset includes @');

# --- db_get_user now carries the LDAP columns ----------------------------
like($src, qr/read_debug, email, ldap_auth, ldap_server FROM users WHERE username/,
     'db_get_user selects ldap_auth + ldap_server');

# --- per-user Authentication fieldset (source) ---------------------------
my ($ue) = $src =~ /sub show_user_edit \{(.*?)\n\}/s;
ok($ue, 'located show_user_edit');
like($ue, qr/if \(\$ENABLE_LDAP\)/,                 'Authentication fieldset gated on ENABLE_LDAP');
like($ue, qr/always uses a local password and cannot use LDAP/, 'protected admin pinned to local');
like($ue, qr/name="auth_method" value="ldap"/,      'LDAP radio present');
like($ue, qr/renaming the user to a full UPN/,      'hint to rename short names to a UPN');

# --- do_user_save guards (source) ----------------------------------------
my ($us) = $src =~ /sub do_user_save \{(.*?)\n\}/s;
ok($us, 'located do_user_save');
like($us, qr/!\$is_protected && \$ENABLE_LDAP/,     'admin never switched to LDAP');
like($us, qr/\$target !~ \/\\@\//,                  'LDAP requires an @ in the username');
like($us, qr/\$srv && \$srv->\{enabled\}/,          'LDAP requires an enabled server');
like($us, qr/ldap_auth = \?, ldap_server = \?/,     'save writes the two LDAP columns');
# switching an existing LOCAL account to LDAP scrubs its local password, so a
# previously-known password cannot resurface under the LDAP flag
like($us, qr/\$want_ldap && !\$old->\{ldap_auth\}/,          'scrub fires only on the local->LDAP transition');
like($us, qr/UPDATE users SET pass_hash = \? WHERE username/, 'the switch overwrites pass_hash with a random value');
like($us, qr/action=>'reset_password'.*switched to LDAP/s,    'the password scrub is audited');
like($src, qr/Switching an account to LDAP replaces its local/, 'the edit page notes the random-password behaviour');

# --- user list: Rename button before Delete ------------------------------
like($src, qr/action=user_rename_form.*?value="delete_user"/s, 'Rename action precedes Delete in the user row');

# --- rename handler: moves the row + repoints every table ----------------
my ($ur) = $src =~ /sub do_user_rename \{(.*?)\n\}/s;
ok($ur, 'located do_user_rename');
like($ur, qr/INSERT INTO users .*SELECT \?, pass_hash/s,       'copies the row under the new name');
like($ur, qr/UPDATE user_sites\s+SET username = \? WHERE username = \?/,      'repoints user_sites');
like($ur, qr/UPDATE password_resets SET username = \? WHERE username = \?/,   'repoints password_resets');
like($ur, qr/UPDATE audit_log\s+SET username = \? WHERE username = \?/,       'repoints audit_log (history follows the new name)');
like($ur, qr/UPDATE login_attempts\s+SET keyval = \? WHERE kind = \?/,        'repoints the login throttle key');
like($ur, qr/DELETE FROM users WHERE username = \?/,           'removes the old row last');
like($ur, qr/\$old eq \$PROTECTED_USER/,                       'the protected admin cannot be renamed');
like($ur, qr/db_user_exists\(\$dbh, \$new\)/,                  'refuses a name that already exists');
like($ur, qr/begin_work.*commit/s,                            'the rename runs in one transaction');

# --- wiring ---------------------------------------------------------------
like($src, qr/\$action eq 'user_rename_form'/, 'dispatcher: user_rename_form');
like($src, qr/\$action eq 'user_rename'\)/,    'dispatcher: user_rename');
like($src, qr/^\s*user_rename\s*$/m,           'STATE_CHANGING: user_rename (CSRF-guarded)');

# --- Users list: Auth column, Tools heading, Edit button ------------------
like($src, qr/read_debug, email, ldap_auth FROM users ORDER BY/, 'db_all_users selects ldap_auth for the list');
like($src, qr/<th>Auth<\/th><th>Password<\/th><th>Tools<\/th>/,   'user list has Auth + Tools columns');
like($src, qr/\$row->\{ldap_auth\} \? 'LDAP' : 'local'/,          'Auth cell shows LDAP|local');
like($src, qr/">Edit<\/a>\};\s*\n\s*if \(\$u eq \$PROTECTED_USER\)/, 'Edit button precedes Rename/Delete in the row');

# --- Forgot-password: LDAP account gets a help-desk notice, no reset link --
ok(main->can('reset_email_ldap_bodies'), 'LDAP reset-email body helper defined');
my ($fp) = $src =~ /sub do_forgot_password \{(.*?)\n\}/s;
ok($fp, 'located do_forgot_password');
like($fp, qr/\$u && \$u->\{ldap_auth\}/,   'forgot-password branches on ldap_auth');
like($fp, qr/reset_email_ldap_bodies/,     'LDAP account is emailed the help-desk notice');
my ($lb) = $src =~ /sub reset_email_ldap_bodies \{(.*?)\n\}/s;
ok($lb, 'located reset_email_ldap_bodies');
like($lb, qr/contact the user help desk/i, 'LDAP reset email says contact the help desk');
unlike($lb, qr/\$link|reset_token|Set a new password/, 'LDAP reset email carries no reset link/token');

# --- Forgot-password: two type-explicit fields (username OR email) ---------
# The form offers a separate Username field and Email field; the user supplies
# whichever they know. Because each field's type is known, there is no guessing
# (a UPN login name like tammer@net.schuler.de is matched as a NAME, not misread
# as an address) -- which is what makes the record selection fail-safe.
like($src, qr/name="who"/,   'forgot-password form has a username field');
like($src, qr/name="email"/, 'forgot-password form has an email field');
like($fp, qr/valid_username\(\$who\) && db_user_exists\(\$dbh, \$who\)/,
     'username field is resolved by account name');
like($fp, qr/db_user_by_email\(\$dbh, \$who_email\)/,
     'email field is resolved by stored address');
like($fp, qr/\$on_file eq \$who_email/,
     'when both fields are filled the email must match the stored address for that account');
# an email-only request (username field blank) must NOT be skipped -- the old
# single-field guard gated the whole block on $who alone, dropping it silently.
like($fp, qr/\$who ne '' \|\| \(defined \$who_email && \$who_email ne ''\)/,
     'resolution proceeds when either the username or the email field is filled');
unlike($fp, qr/if \(\$dbh && \$who ne ''\)/,
     'the block is no longer gated on the username field alone');
# the two fields echo their submitted value HTML-encoded (esc()), like every
# other input in the app -- not via CGI.pm textfield (which did not echo at all)
like($src, qr/name="who"\s+autocomplete="off"\s+value="\}\s*\.\s*esc\(\$pre_who\)/s,
     'reset username field HTML-encodes its echoed value');
like($src, qr/name="email"\s+autocomplete="off"\s+value="\}\s*\.\s*esc\(\$pre_email\)/s,
     'reset email field HTML-encodes its echoed value');

# --- Email addresses are unique across accounts --------------------------
ok(main->can('db_email_conflict'), 'db_email_conflict helper defined');
like($src, qr/SELECT username FROM users WHERE lower\(email\) = lower/,
     'uniqueness is checked case-insensitively');
# every write path that sets an email rejects a collision with another account
like($src, qr/sub do_set_email \{.*?db_email_conflict\(\$dbh, \$email, \$target\).*?\n\}/s,
     'admin set-email rejects a duplicate address');
like($src, qr/sub do_user_save \{.*?db_email_conflict\(\$dbh, \$email, \$target\).*?\n\}/s,
     'user-save rejects a duplicate address');
like($src, qr/sub do_add_user \{.*?db_email_conflict\(\$dbh, \$email, undef\).*?\n\}/s,
     'add-user rejects a duplicate address');
like($src, qr/sub do_change_email \{.*?db_email_conflict\(\$dbh, \$email, \$user\).*?\n\}/s,
     'self-service change-email rejects a duplicate address');
# the self-service path must not disclose which account owns the address
my ($ce) = $src =~ /sub do_change_email \{(.*?)\n\}/s;
like($ce, qr/already in use by another account/, 'self-service duplicate message is non-disclosing');

# --- LDAP user cannot change a local password -----------------------------
my ($cp) = $src =~ /sub do_change_password \{(.*?)\n\}/s;
ok($cp, 'located do_change_password');
like($cp, qr/\$u->\{ldap_auth\}/,                  'change-password refuses an LDAP account');
like($cp, qr/change your password on the AD\/LDAP server/, 'LDAP change-password message points to AD');
like($src, qr/\$me->\{ldap_auth\}/,                'the change-password form shows a notice for LDAP users');

# --- Reset-password greyed for admin + LDAP users -------------------------
like($src, qr/if \(\$u eq \$PROTECTED_USER \|\| \$row->\{ldap_auth\}\) \{\s*\n\s*my \$why/,
     'Reset password is disabled for the admin and for LDAP users');
like($src, qr/pointer-events:none/, 'the disabled Reset button is non-clickable');
like($ue, qr/if \(\$row->\{ldap_auth\}\) \{.*?Reset password &rarr;<\/span>/s,
     'the user edit page greys Reset password for an LDAP user too');

# --- Add user with LDAP -> random local password --------------------------
my ($au) = $src =~ /sub do_add_user \{(.*?)\n\}/s;
ok($au, 'located do_add_user');
like($au, qr/\$want_ldap = \(\$ENABLE_LDAP/,       'add-user honours an LDAP choice');
like($au, qr/\$new_user !~ \/\\@\//,               'LDAP add requires a UPN username');
like($au, qr/secure_random_bytes\(16\)/,           'a random 16-byte secret seeds the throwaway password');
like($au, qr/password_hash\(substr\(unpack/,       'the random password is hashed, not stored in clear');
like($au, qr/UPDATE users SET ldap_auth = 1, ldap_server = \?/, 'the new LDAP user is flagged + linked to its server');

# --- "Tools" column heading on the reports and templates lists ------------
like($src, qr/<th>Report<\/th><th>Date \/ time<\/th><th>Size<\/th><th>Tools<\/th>/, 'Backup reports list has a Tools heading');
like($src, qr/<th>Used<\/th><th>Orig<\/th><th>Tools<\/th>/,                         'Templates list has a Tools heading');

done_testing();
