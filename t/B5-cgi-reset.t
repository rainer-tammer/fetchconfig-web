use strict; use warnings;
use Test::More;
use CGI;

# Reproduces the FastCGI cross-request leak: CGI->new caches parsed params in
# $CGI::Q, so after a POST, a later GET with no query string would otherwise
# still report the POST's params. The accept loop calls CGI::initialize_globals
# before each CGI->new to prevent this. Verify that reset actually clears them.
sub mk {
    my ($method, $qs, $body) = @_;
    local $ENV{REQUEST_METHOD} = $method;
    local $ENV{QUERY_STRING}   = $qs // '';
    local $ENV{CONTENT_TYPE}   = 'application/x-www-form-urlencoded';
    $body = '' unless defined $body;
    local $ENV{CONTENT_LENGTH} = length $body;
    open(my $in, '<', \$body); local *STDIN = $in;
    return CGI->new;
}

my $q1 = mk('POST', '', 'action=login&username=admin');
is($q1->param('action'), 'login', 'POST request parses action=login');

# Without a reset the cached params leak into the next (bodyless) GET.
my $q2 = mk('GET', '');
is($q2->param('action'), 'login', 'cached params leak into next GET without reset (documents the bug)');

# With the reset the loop performs, the GET is clean. Check method and params
# inside the request scope (mk() localizes %ENV, so read before it returns).
{
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = '';
    local $ENV{CONTENT_LENGTH} = 0;
    my $empty = ''; open(my $in, '<', \$empty); local *STDIN = $in;
    CGI::initialize_globals();
    my $q3 = CGI->new;
    is($q3->param('action'),  undef, 'after initialize_globals the GET has no stale action');
    is($q3->request_method,   'GET', 'method reflects the new request');
}

# A GET that carries its own action still works after reset.
CGI::initialize_globals();
my $q4 = mk('GET', 'action=report');
is($q4->param('action'), 'report', 'fresh GET params parse correctly after reset');

done_testing();
