use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# Step 2b: the LDAP login bind. do_login authenticates an ldap_auth account by
# binding to its configured directory (verbatim UPN bind, CA-verified TLS, blank
# password refused), instead of the local pass_hash. The protected admin always
# stays local. (Net::LDAP is not installed in the test image, so the positive
# bind path is exercised live, not here; these cover the guards + wiring.)
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# --- ldap_bind_ok: the pre-bind guards (all return before any network use) ---
# Tri-state: 'ok' | 'reject' (bad credentials) | 'unavailable' (directory/config).
ok(main->can('ldap_bind_ok'), 'ldap_bind_ok defined');
is(main::ldap_bind_ok(undef, 'u@d.tld', 'pw'), 'unavailable', 'no server -> unavailable');
is(main::ldap_bind_ok({ enabled => 0, encryption => 'ldaps', host1 => 'h' }, 'u@d.tld', 'pw'),
   'unavailable', 'disabled server -> unavailable');
is(main::ldap_bind_ok({ enabled => 1, encryption => 'ldaps', host1 => 'h' }, 'u@d.tld', '   '),
   'reject', 'blank/whitespace password -> reject (anonymous-bind trap)');
is(main::ldap_bind_ok({ enabled => 1, encryption => 'ldaps', host1 => 'h' }, '', 'pw'),
   'reject', 'empty username -> reject');

# --- ldap_bind_ok: security invariants (source) --------------------------
my ($bo) = $src =~ /sub ldap_bind_ok \{(.*?)\n\}/s;
ok($bo, 'located ldap_bind_ok');
like($bo, qr/\$pass =~ \/\\S\//,              'blank password refused before binding');
like($bo, qr/verify => 'require'/,            'TLS is CA-verified (verify => require)');
like($bo, qr/sslversion => 'tlsv1_2'/,        'minimum TLS 1.2');
like($bo, qr/\$enc eq 'ldap' && \$ENABLE_LDAP != 2/, 'plain LDAP refused unless ENABLE_LDAP=2');
like($bo, qr/\$res = \$try->\(\$r->\{host2\}, \$r->\{port2\}\) if \$res < 0/,
     'secondary is tried only on a connection/TLS failure, never on a rejected bind');
like($bo, qr/\$ldap->bind\(\$user, password => \$pass\)/,
     'bind is verbatim (username sent exactly as stored)');
like($bo, qr/\? 'ok' : \$res == 0 \? 'reject' : 'unavailable'/,
     'result distinguishes accept / reject / unreachable');
unlike($src, qr/verify\s*=>\s*'none'/, 'there is still never a verify => none path');

# --- do_login wiring (source) --------------------------------------------
my ($dl) = $src =~ /sub do_login \{(.*?)\n\}/s;
ok($dl, 'located do_login');
like($dl, qr/\$u->\{ldap_auth\} && \$username ne \$PROTECTED_USER/,
     'an LDAP account authenticates by bind; the protected admin stays local');
like($dl, qr/my \$st  = ldap_bind_ok\(\$srv, \$username, \$password\)/,
     'login binds the entered credentials against the account\'s server');
# a directory outage is distinct from a wrong password, and must not be counted
like($dl, qr/\$ldap_unavailable = 1/, 'an unreachable directory is flagged, not treated as a bad password');
like($dl, qr/if \(\$ldap_unavailable\) \{/, 'the outage is handled before the failure counters run');
like($dl, qr/Login is currently not possible/, 'the user is told login is temporarily impossible');
like($dl, qr/no configured LDAP server could be reached/, 'the outage is audited distinctly');
like($dl, qr/ldap_server_by_id\(\$dbh, \$u->\{ldap_server\}\)/,
     'the bind uses the server linked on the user record');
like($dl, qr/if \(\$ok && !\$u->\{ldap_auth\} && bcrypt_available/,
     'the transparent hash upgrade never runs for an LDAP account');
like($dl, qr/if \(!\$u->\{ldap_auth\} && \$password eq \$DEFAULT_PASSWORD\)/,
     'the default-password banner never applies to an LDAP account');
like($dl, qr/login succeeded' \. \(\$u->\{ldap_auth\} \? ' \(LDAP bind\)' : ''\)/,
     'a successful LDAP login is audited as an LDAP bind (never the password)');

done_testing();
