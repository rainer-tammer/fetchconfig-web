use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source);

# --------------------------------------------------------------------------
# 2.19 / step 1: LDAP(S) authentication -- server management (admin only).
# Config flag ENABLE_LDAP (0|1|2), an admin "User -> LDAP" page to list/add/
# edit/delete servers, CA upload stored in the DB + decoded via
# Crypt::OpenSSL::X509, and a Test-connection bind. No user is wired to a server
# yet (next step); the schema change is inert for the current login path.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };
my $dbs = do { local $/; open(my $f, '<', "$FindBin::Bin/../fetchconfig-web-dbsetup.pl") or die $!; <$f> };
my $sql = do { local $/; open(my $f, '<', "$FindBin::Bin/../fetchconfig-web-dbupdate-2.19.sql") or die $!; <$f> };
my $css = css_source();

# --- config flag (the config vars are file-scoped lexicals, so assert on source) ---
like($src, qr/\[ 'ENABLE_LDAP',\s*'int',\s*'0',.*0, 2 \]/, 'config table: ENABLE_LDAP int 0..2, default 0');
like($src, qr/\$ENABLE_LDAP = \(defined \$kv->\{ENABLE_LDAP\} && \$kv->\{ENABLE_LDAP\} =~ \/\^\[012\]\$\/\)/,
     'read_config whitelists ENABLE_LDAP to 0|1|2 (else 0)');

# --- lazy probes + helpers defined ---------------------------------------
ok(main->can($_), "$_ defined") for qw(
    ldaps_available x509_available ldap_enc_ok ldap_default_port
    ldap_servers_all ldap_server_by_id ldap_ca_info ldap_ca_cache_file
    ldap_materialize_ca show_ldap_page show_ldap_edit do_ldap_save
    do_ldap_delete do_ldap_test run_ldap_test ldap_ca_trigger ldap_ca_modal_html);

# --- pure helpers behave --------------------------------------------------
is(main::ldap_default_port('ldaps'),    636, 'default port ldaps -> 636');
is(main::ldap_default_port('starttls'), 389, 'default port starttls -> 389');
is(main::ldap_default_port('ldap'),     389, 'default port ldap -> 389');
ok( main::ldap_enc_ok('ldaps'),  'ldaps is a valid encryption');
ok( main::ldap_enc_ok('starttls'),'starttls is a valid encryption');
ok(!main::ldap_enc_ok('tls'),    'bogus encryption rejected');
ok(!main::ldap_enc_ok(undef),    'undef encryption rejected');

# CA decode: no cert / junk never dies, always a hashref with an error
is(ref main::ldap_ca_info(undef),   'HASH', 'ca_info(undef) is a hashref');
ok(main::ldap_ca_info(undef)->{error},      'ca_info(undef) reports an error');
ok(main::ldap_ca_info('not a cert')->{error},'ca_info(junk) reports an error, does not die');

# materialized CA path lives under the session dir (cache file)
like(main::ldap_ca_cache_file(7), qr{/ldap-ca-7\.pem\z}, 'CA cache file is per-id under the session dir');

# --- wiring: menu, dispatcher, CSRF --------------------------------------
like($src, qr/\$su->\('LDAP',\s*'\?action=ldap'\)\s*if \$is_admin;/, 'User menu: LDAP item is admin-gated');
like($src, qr/\$action eq 'ldap'\)/,        'dispatcher: ldap (list)');
like($src, qr/\$action eq 'ldap_edit'/,     'dispatcher: ldap_edit');
like($src, qr/\$action eq 'ldap_save'/,     'dispatcher: ldap_save');
like($src, qr/\$action eq 'ldap_delete'/,   'dispatcher: ldap_delete');
like($src, qr/\$action eq 'ldap_test'/,     'dispatcher: ldap_test');

# --- CA shown in an About-style modal, not a new tab ----------------------
like($src, qr/id="fc-ldapca"/,          'CA-details modal present (About-style box)');
like($src, qr/fc-about-box/,            'CA modal reuses the About dialog box styling');
like($src, qr/class="fc-ldapca-open"/,  'the "view" link is a modal trigger');
like($src, qr/data-sha="/,              'the trigger carries the decoded fields (sha256 etc.)');
unlike($src, qr/action=ldap_ca/,        'the old new-tab CA page is gone');

# --- form field widths (CSS) ----------------------------------------------
like($css, qr/\.ldap-field input\[type="text"\]\s*\{\s*width:\s*64ch/,     'name/host fields are 64ch wide');
like($css, qr/\.ldap-field select\s*\{\s*width:\s*32ch/,                   'encryption select is 32ch wide');
like($css, qr/\.ldap-field input\[type="password"\]\s*\{\s*width:\s*32ch/, 'test password field is 32ch wide');
like($src, qr/^\s*ldap_save\s*$/m,   'STATE_CHANGING: ldap_save (CSRF-guarded)');
like($src, qr/^\s*ldap_delete\s*$/m, 'STATE_CHANGING: ldap_delete (CSRF-guarded)');
like($src, qr/^\s*ldap_test\s*$/m,   'STATE_CHANGING: ldap_test (CSRF-guarded)');

# --- security invariants (source) ----------------------------------------
my ($test) = $src =~ /sub do_ldap_test \{(.*?)\n\}/s;
ok($test, 'located do_ldap_test');
like($test, qr/\$tpass !~ \/\\S\//, 'empty/whitespace password refused before binding');
like($test, qr/unauthenticated bind/, 'the empty-password refusal explains the unauthenticated-bind trap');
like($test, qr/ENABLE_LDAP != 2/, 'plain LDAP refused unless ENABLE_LDAP=2');
like($test, qr/detail=>'tested LDAP bind for user ' \. \$tuser/, 'audit records the user, never the password');

my ($runt) = $src =~ /sub run_ldap_test \{(.*?)\n\}/s;
ok($runt, 'located run_ldap_test');
like($runt, qr/verify => 'require'/, 'TLS is always CA-verified (verify => require)');
unlike($src, qr/verify\s*=>\s*'none'/, 'there is never a verify => none path');
like($runt, qr/sslversion => 'tlsv1_2'/, 'minimum TLS 1.2');

like($src, qr/required for LDAPS and STARTTLS/, 'a CA is required for the encrypted schemes');
like($src, qr/-----BEGIN CERTIFICATE-----/, 'uploaded CA must look like a PEM certificate');

# --- schema: dbsetup + migration -----------------------------------------
like($dbs, qr/\[ '2\.19', 'fetchconfig-web-dbupdate-2\.19\.sql', sub \{ tbl_exists\(\$_\[0\], 'ldap_servers'\) \} \]/,
     'dbsetup @UPDATES includes the 2.19 migration');
like($dbs, qr/ldap_auth\s+BOOLEAN\s+NOT NULL\s+DEFAULT FALSE/, 'fresh users table gains ldap_auth');
like($dbs, qr/ldap_server\s+INTEGER/, 'fresh users table gains ldap_server (nullable)');
like($dbs, qr/GRANT SELECT, INSERT, UPDATE, DELETE ON ldap_servers TO \$qu/, 'do_grants gives the web role DML on ldap_servers');
like($dbs, qr/ON SEQUENCE ldap_servers_id_seq TO \$qu/, 'do_grants gives the web role the sequence');

like($sql, qr/CREATE TABLE ldap_servers/, '2.19 SQL creates ldap_servers');
like($sql, qr/ALTER TABLE users ADD COLUMN ldap_auth/,   '2.19 SQL adds users.ldap_auth');
like($sql, qr/ALTER TABLE users ADD COLUMN ldap_server/, '2.19 SQL adds users.ldap_server');
like($sql, qr/VALUES \(''2\.19''/, '2.19 SQL records the migration id');
like($sql, qr/probe the catalog|information_schema/, '2.19 SQL is 8.2-safe (catalog-probed, no ADD COLUMN IF NOT EXISTS)');

# --- Add-only default-port-follows-encryption + coloured bind result ------
like($src, qr/e\.value==='ldaps' \? 636 : 389/, 'Add form fills the default port from the encryption');
like($src, qr/unless \(\$editing\) \{\s*\n\s*print <<'JS';/, 'the port-autofill script is emitted on Add only (not Edit)');
my ($dt) = $src =~ /sub do_ldap_test \{(.*?)\n\}/s;
like($dt, qr/\$ln =~ \/\^Bind\\s\*:\//, 'the Bind line is singled out in the test result');
like($dt, qr/#3fb950/, 'Bind OK is coloured green');
like($dt, qr/#ff7b72/, 'Bind failure is coloured red');

# --- Enabled is the first field (above Name), relabelled; in-use not deletable -
like($src, qr/Enable LDAP server<\/label>.*?<label>Name<br/s,
     'the enable checkbox is the first field, labelled "Enable LDAP server"');
like($src, qr/SELECT COUNT\(\*\) FROM users WHERE ldap_server = \?/, 'the list counts users per server');
like($src, qr/>\(in use\)</, 'a server in use shows "(in use)" instead of a Delete button');
like($src, qr/SELECT 1 FROM users WHERE ldap_server = \?/, 'do_ldap_delete still refuses a referenced server server-side');

done_testing();
