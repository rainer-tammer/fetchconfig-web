use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# HTTPS_ENABLED is optional and validated like the other 0|1 flags: any value
# (valid or not) must load cleanly -- an invalid one falls back to off rather
# than producing a config error. (The lexical's value isn't reachable from
# outside, so this asserts the parse contract, not the stored value.)
for my $v ('1', '0', 'yes', '2', '') {
    my ($cfg) = make_config(HTTPS_ENABLED => $v);
    my $out = `perl -I "$FindBin::Bin/lib" -e 'use FCWebTest qw(load_cgi); load_cgi(q{$cfg}); my \$e=main::read_config(); print defined \$e ? "ERR:\$e" : "OK";' 2>/dev/null`;
    is($out, 'OK', "HTTPS_ENABLED='$v' loads without a config error");
}
done_testing();
