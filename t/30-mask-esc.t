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
# RADIUS/TACACS shared key on a server line (ProCurve etc.), scoped so other
# "key" keywords are not touched.
like(main::mask_secrets('radius-server host 1.2.3.4 key "secret"'),
     qr/key "\*\*\*"/, 'radius key masked (quoted)');
unlike(main::mask_secrets('radius-server host 1.2.3.4 key "secret"'), qr/secret/, 'radius key value gone');
like(main::mask_secrets('tacacs-server host 1.2.3.4 key plainkey'),
     qr/key \?\*\*\*\?/, 'tacacs key masked (bare)');
is(main::mask_secrets('crypto key generate rsa'), 'crypto key generate rsa', 'crypto key generate not masked');
is(main::mask_secrets('ip ssh host-key'), 'ip ssh host-key', 'host-key not masked');
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
