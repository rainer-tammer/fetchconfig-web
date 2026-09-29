use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# *_BASE_URL keys must be safe absolute URL paths; anything that could break
# out of an href or a CSS url('...') is a configuration error.
my @bad  = ('javascript:alert(1)', "/x'y", '/x)y', '/x y', 'http://evil', 'relative', '/x"y');
my @good = ('/fetchconfig-web', '/a/b_c.d~e-f/', '/');

for my $v (@bad) {
    my ($cfg) = make_config(HELP_BASE_URL => $v);
    my $out = `perl -I "$FindBin::Bin/lib" -e 'use FCWebTest qw(load_cgi); load_cgi(q{$cfg}); my \$e=main::read_config(); print defined \$e ? "REJ" : "OK";' 2>/dev/null`;
    is($out, 'REJ', "HELP_BASE_URL '$v' rejected");
}
for my $v (@good) {
    my ($cfg) = make_config(HELP_BASE_URL => $v);
    my $out = `perl -I "$FindBin::Bin/lib" -e 'use FCWebTest qw(load_cgi); load_cgi(q{$cfg}); my \$e=main::read_config(); print defined \$e ? "REJ" : "OK";' 2>/dev/null`;
    is($out, 'OK', "HELP_BASE_URL '$v' accepted");
}
done_testing();
