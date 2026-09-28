use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# mask_secrets: pass/enable/community values are hidden
like(main::mask_secrets('user=admin,pass=secret,x=1'), qr/pass=\?\*\*\*\?/, 'pass masked');
unlike(main::mask_secrets('user=admin,pass=secret'), qr/secret/, 'password value gone');
like(main::mask_secrets('enable=ena123'), qr/enable=\?\*\*\*\?/, 'enable masked');
like(main::mask_secrets('community=public'), qr/community=\?\*\*\*\?/, 'community masked');
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
