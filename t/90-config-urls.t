use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use File::Spec;

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

# Regression for the vhost "//file" bug: with HELP_BASE_URL=/, the old code
# normalized "/" back to "/" and joined "$BASE/$file" -> "//file", a
# protocol-relative URL the browser read as a hostname (//license.html ->
# https://license.html/). The fix normalizes a bare "/" (and any trailing
# slash) to "" so the join is "/file".
#
# The config globals are file-lexical, so assert the normalization logic and
# that the special-case line was removed from the source.
{
    my $cgi = do {
        my $path = File::Spec->catfile("$FindBin::Bin/..", 'fetchconfig-web.cgi');
        open(my $fh, '<', $path) or die $!; local $/; <$fh>;
    };
    # The join uses "$HELP_BASE_URL/$file"; the old "$v = '/' if $v eq ''" that
    # reintroduced the leading slash must be gone.
    unlike($cgi, qr/\$v = '\/' if \$v eq ''/, 'bare-/ no longer re-added before the join');
    like($cgi, qr/\$v =~ s\{\/\+\$\}\{\};/, 'trailing slashes are stripped from URL bases');

    # The normalization+join, run exactly as the code does it.
    my $norm = sub { my $v = shift; $v =~ s{/+$}{}; $v };
    is($norm->('/')               . '/LICENSE.html', '/LICENSE.html',               'base / -> /LICENSE.html');
    is($norm->('/fetchconfig-web') . '/LICENSE.html', '/fetchconfig-web/LICENSE.html', 'base /path kept');
    is($norm->('/a/b/')           . '/LICENSE.html', '/a/b/LICENSE.html',           'trailing slash stripped');
    unlike($norm->('/') . '/LICENSE.html', qr{^//}, 'base / never yields //file');
}

done_testing();
