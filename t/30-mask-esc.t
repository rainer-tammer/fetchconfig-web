use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# mask_secrets: pass/enable/community values are hidden
like(main::mask_secrets('user=admin,pass=secret,x=1'), qr/pass=\?\*\*\*\?/, 'pass masked');
unlike(main::mask_secrets('user=admin,pass=secret'), qr/secret/, 'password value gone');
like(main::mask_secrets('enable=ena123'), qr/enable=\?\*\*\*\?/, 'enable masked');
like(main::mask_secrets('community=public'), qr/community=\?\*\*\*\?/, 'community option masked');
# SNMP community in a switch config (space form), masked but access level kept.
like(main::mask_secrets('snmp-server community "public" operator'),
     qr/community "\*\*\*" operator/, 'ProCurve quoted community masked, level kept');
unlike(main::mask_secrets('snmp-server community "private" unrestricted'),
       qr/private/, 'quoted community value gone');
like(main::mask_secrets('snmp-server community private RW'),
     qr/community \?\*\*\*\? RW/, 'bare community masked, RW kept');
# Hirschmann: the community is the QUOTED token, which comes AFTER positional
# keywords (ipaddr/ipmask/ro/rw [+ address]). Mask the quoted string, keep the
# keywords/address; never mask the keyword as if it were the community.
for my $pair (
    ['snmp-server community "__c1__"',                   'community "\*\*\*"'],
    ['snmp-server community ipaddr 0.0.0.0 "__c1__"',    'community ipaddr 0\.0\.0\.0 "\*\*\*"'],
    ['snmp-server community ipmask 0.0.0.0 "__c1__"',    'community ipmask 0\.0\.0\.0 "\*\*\*"'],
    ['snmp-server community ro "__c1__"',                'community ro "\*\*\*"'],
    ['snmp-server community rw "__c2__"',                'community rw "\*\*\*"'],
) {
    like(main::mask_secrets($pair->[0]), qr/$pair->[1]/, "Hirschmann snmp: $pair->[0]");
    unlike(main::mask_secrets($pair->[0]), qr/__c\d__/, "Hirschmann snmp community value gone: $pair->[0]");
}
# RADIUS/TACACS shared key on a server line (ProCurve etc.), scoped so other
# "key" keywords are not touched.
like(main::mask_secrets('radius-server host 1.2.3.4 key "secret"'),
     qr/key "\*\*\*"/, 'radius key masked (quoted)');
unlike(main::mask_secrets('radius-server host 1.2.3.4 key "secret"'), qr/secret/, 'radius key value gone');
like(main::mask_secrets('tacacs-server host 1.2.3.4 key plainkey'),
     qr/key \?\*\*\*\?/, 'tacacs key masked (bare)');
is(main::mask_secrets('crypto key generate rsa'), 'crypto key generate rsa', 'crypto key generate not masked');
is(main::mask_secrets('ip ssh host-key'), 'ip ssh host-key', 'host-key not masked');
# Aruba CX: an encoding keyword (ciphertext/plaintext) sits between "key" and the
# value -- keep the keyword, mask the value (not the keyword).
like(main::mask_secrets('radius-server host 172.31.1.126 key ciphertext AQxZZqiBI14l91PE=='),
     qr/key ciphertext \?\*\*\*\?/, 'Aruba CX radius "key ciphertext <blob>" masks the blob');
unlike(main::mask_secrets('radius-server host 172.31.1.126 key ciphertext AQxZZqiBI14l91PE=='),
       qr/AQxZZ/, 'Aruba CX radius ciphertext blob value gone');
like(main::mask_secrets(' key ciphertext AQBxyzIndentedBlob=='),
     qr/^ key ciphertext \?\*\*\*\?/m, 'indented "key ciphertext <blob>" masks the blob');
# Cisco Nexus: a numeric key TYPE sits before the quoted secret -- keep the
# type, mask the secret (not the type digit).
like(main::mask_secrets('tacacs-server host 172.24.180.101 key 7 "secret" timeout 2'),
     qr/key 7 "\*\*\*" timeout 2/, 'Nexus "key 7 <quoted>" keeps type 7, masks secret');
unlike(main::mask_secrets('tacacs-server host 172.24.180.101 key 7 "secret" timeout 2'),
       qr/"secret"/, 'Nexus tacacs secret value gone');
like(main::mask_secrets('radius-server host 1.2.3.4 key 0 "cleartext"'),
     qr/key 0 "\*\*\*"/, 'Nexus "key 0 <quoted>" keeps type 0, masks secret');
# Aruba CX user password: "password ciphertext <blob>".
like(main::mask_secrets('user admin group administrators password ciphertext AQBapSFxQZ123MA'),
     qr/password ciphertext \?\*\*\*\?/, 'Aruba CX "password ciphertext <blob>" masked');
unlike(main::mask_secrets('user admin group administrators password ciphertext AQBapSFxQZ123MA'),
       qr/AQBapSFx/, 'Aruba CX password ciphertext blob value gone');
like(main::mask_secrets('user admin group administrators password ciphertext AQBapSFxQZ123MA'),
     qr/^user admin group administrators /, 'Aruba CX user/group kept, only blob masked');
# WPA pre-shared key (Aruba CX etc.).
like(main::mask_secrets('wpa-passphrase 0861d33aXXXX303f'),
     qr/wpa-passphrase \?\*\*\*\?/, 'wpa-passphrase masked');
unlike(main::mask_secrets('wpa-passphrase 0861d33aXXXX303f'), qr/0861d33a/, 'wpa passphrase value gone');

# Cisco IOS hashed secrets: "secret <type> <hash>" / "password <type> <hash>".
like(main::mask_secrets('enable secret 9 $14$Y4y4$in9MZd4jxxxxAsC4g'),
     qr/secret 9 \?\*\*\*\?/, 'enable secret 9 hash masked');
unlike(main::mask_secrets('enable secret 9 $14$Y4y4$in9MZd4jxxxxAsC4g'),
       qr/\$14\$/, 'enable secret 9 hash value gone');
like(main::mask_secrets('username x privilege 15 secret 9 $14$abcXYZ'),
     qr/secret 9 \?\*\*\*\?/, 'username secret 9 hash masked');
like(main::mask_secrets('username logicvein privilege 15 password 7 0000000000614B5B495742'),
     qr/password 7 \?\*\*\*\?/, 'username password 7 hash masked');
unlike(main::mask_secrets('username logicvein privilege 15 password 7 0000000000614B5B495742'),
       qr/614B5B/, 'password 7 hash value gone');
like(main::mask_secrets('enable password 7 070C285F4D06'),
     qr/password 7 \?\*\*\*\?/, 'enable password 7 hash masked');
like(main::mask_secrets('username admin secret 5 $1$abc$def'),
     qr/secret 5 \?\*\*\*\?/, 'secret 5 (MD5) hash masked');
# Keyword-typed encrypted passwords (no numeric type): Zyxel / HPE Comware /
# Huawei. The keyword stays; the hash is masked; the username stays visible.
like(main::mask_secrets('username admin privilege 15 password encrypted 9f8c7b6a5e4d3c2b'),
     qr/password encrypted \?\*\*\*\?/, 'Zyxel "password encrypted <hash>" masked');
like(main::mask_secrets('username admin privilege 15 password encrypted 9f8c7b6a5e4d3c2b'),
     qr/^username admin privilege 15 /, 'the username line is kept, only the hash masked');
unlike(main::mask_secrets('username admin privilege 15 password encrypted 9f8c7b6a5e4d3c2b'),
       qr/9f8c7b6a/, 'Zyxel password hash value gone');
like(main::mask_secrets('local-user admin password cipher $c$3$Hq8Zabc'),
     qr/password cipher \?\*\*\*\?/, 'HPE Comware "password cipher <hash>" masked');
like(main::mask_secrets('password irreversible-cipher $1a$Abc123'),
     qr/password irreversible-cipher \?\*\*\*\?/, 'Huawei "password irreversible-cipher <hash>" masked');
like(main::mask_secrets('password hash 1A2B3C4D5E'),
     qr/password hash \?\*\*\*\?/, '"password hash <hash>" masked');
# Must NOT over-mask: "password encryption/complexity ..." are commands, not secrets.
is(main::mask_secrets('password encryption aes'),
   'password encryption aes', '"password encryption aes" (command) not masked');
is(main::mask_secrets('password complexity enable'),
   'password complexity enable', '"password complexity" (command) not masked');
# Hirschmann ":v<N>:<hash>:" password blob (hirschmann model + generic/hirschmann
# template). Keep "users passwd <user>", the ":vN:" tag and the closing ":".
like(main::mask_secrets('users passwd admin :v1:a2bbccddeecf7c563746c5037b1dad:'),
     qr/users passwd admin :v1:\?\*\*\*\?:/, 'Hirschmann :v1: hash masked, tag and colons kept');
unlike(main::mask_secrets('users passwd admin :v1:a2bbccddeecf7c563746c5037b1dad:'),
       qr/a2bbccddee/, 'Hirschmann hash value gone');
like(main::mask_secrets('users passwd operator :v2:deadbeefcafebabe:'),
     qr/:v2:\?\*\*\*\?:/, 'Hirschmann :v2: variant masked');
is(main::mask_secrets('users access admin readwrite'),
   'users access admin readwrite', '"users access ..." (not a passwd line) not masked');
# Must NOT over-mask: hyphenated keywords and prose without a type digit.
is(main::mask_secrets('password-policy minimum-length 8'),
   'password-policy minimum-length 8', 'password-policy not masked');
is(main::mask_secrets('service password-encryption'),
   'service password-encryption', 'password-encryption not masked');
is(main::mask_secrets('description secret project 7'),
   'description secret project 7', 'prose "secret <word>" (no type digit) not masked');
# Aruba CX virtual-controller key and the indented auth-server "key" line.
like(main::mask_secrets('virtual-controller-key 10abcDEF737'),
     qr/virtual-controller-key \?\*\*\*\?/, 'virtual-controller-key masked');
unlike(main::mask_secrets('virtual-controller-key 10abcDEF737'), qr/10abcDEF737/, 'vc key value gone');
like(main::mask_secrets("wlan auth-server x\n key 046f0017abcd\n port 1812\n"),
     qr/^ key \?\*\*\*\?/m, 'indented auth-server key masked');
unlike(main::mask_secrets("wlan auth-server x\n key 046f0017abcd\n"), qr/046f0017abcd/, 'auth-server key value gone');
# Indented "key-*" commands must NOT be masked (hyphen, not a bare "key").
is(main::mask_secrets(' key-management wpa2'), ' key-management wpa2', 'key-management not masked');
is(main::mask_secrets(' ssh key-exchange group14'), ' ssh key-exchange group14', 'key-exchange not masked');
# community must be masked only as an snmp-server COMMAND, not as prose.
is(main::mask_secrets('description community center switch'),
   'description community center switch', 'prose "community" not masked');
is(main::mask_secrets('hostname community-sw01'), 'hostname community-sw01', 'hostname with community- not masked');
like(main::mask_secrets('set snmp community public'), qr/community \?\*\*\*\?/, 'set snmp community masked');
# value ends at comma/semicolon/space, not swallowing the next field
like(main::mask_secrets('pass=x,user=bob'), qr/user=bob/, 'next field survives');
# quoted value masked as a unit
like(main::mask_secrets('pass="a b c"'), qr/pass=\?\*\*\*\?/, 'quoted pass masked');

# esc: HTML-escapes AFTER masking
my $e = main::esc('<b>pass=secret</b>');
like($e, qr/&lt;b&gt;/, 'html escaped');
unlike($e, qr/secret/, 'secret masked inside esc');

# json_string: quotes/backslash/newline + non-ASCII -> \uXXXX (pure ASCII out)
my $j = main::json_string("a\"b\\c\n");
like($j, qr/\\"/, 'quote escaped'); like($j, qr/\\\\/, 'backslash escaped');
like($j, qr/\\n/, 'newline escaped');
my $hi = main::json_string("caf\xe9");           # latin-1 e-acute byte
unlike($hi, qr/[^\x00-\x7f]/, 'json_string output is pure ASCII');
like($hi, qr/\\u00e9/, 'high byte -> \\u00e9');

done_testing();
