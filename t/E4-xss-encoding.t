use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# A-02. The central output encoder esc() must neutralise HTML metacharacters in
# any stored/reflected value (device notes, template/report names, errors).
for my $p ('<script>alert(1)</script>', '"><img src=x onerror=alert(1)>', 'a & b < c > d', q{'"}) {
    my $e = main::esc($p);
    unlike($e, qr/<script|<img|<c>/,        "esc neutralises tags: $p");
    unlike($e, qr/(?<!&)(?<!&amp;)[<>]/,     'no raw angle brackets remain');
}
# Entity output is produced for the classic metacharacters.
is(main::esc('<'),  '&lt;',   'esc: <');
is(main::esc('>'),  '&gt;',   'esc: >');
is(main::esc('&'),  '&amp;',  'esc: &');
like(main::esc('"'), qr/&(quot|#34);/, 'esc: double-quote');

done_testing();
