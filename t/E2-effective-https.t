use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# F-02. effective_https() = config force OR server-set scheme env OR (opt-in)
# a trusted reverse proxy's X-Forwarded-Proto.
sub eff {
    my (%o) = @_;
    my %env = %{ delete $o{env} || {} };
    my ($cfg) = make_config(%o);
    load_cgi($cfg); main::read_config();
    # Deterministic base: drop any scheme hints the sandbox might carry.
    local %ENV = %ENV;
    delete @ENV{qw(HTTPS REQUEST_SCHEME HTTP_X_FORWARDED_PROTO)};
    $ENV{$_} = $env{$_} for keys %env;
    return main::effective_https();
}

is(eff(HTTPS_ENABLED=>1),                                        1, 'HTTPS_ENABLED=1 forces on');
is(eff(HTTPS_ENABLED=>0),                                        0, 'off with no hints');
is(eff(HTTPS_ENABLED=>0, env=>{HTTPS=>'on'}),                    1, 'env HTTPS=on detected');
is(eff(HTTPS_ENABLED=>0, env=>{REQUEST_SCHEME=>'https'}),        1, 'REQUEST_SCHEME=https detected');
is(eff(HTTPS_ENABLED=>0, TRUST_FORWARDED_PROTO=>0, env=>{HTTP_X_FORWARDED_PROTO=>'https'}),
   0, 'X-Forwarded-Proto ignored when not trusted');
is(eff(HTTPS_ENABLED=>0, TRUST_FORWARDED_PROTO=>1, env=>{HTTP_X_FORWARDED_PROTO=>'https'}),
   1, 'X-Forwarded-Proto honoured when trusted');
is(eff(HTTPS_ENABLED=>0, TRUST_FORWARDED_PROTO=>1, env=>{HTTP_X_FORWARDED_PROTO=>'https, http'}),
   1, 'X-Forwarded-Proto first token used');
is(eff(HTTPS_ENABLED=>0, TRUST_FORWARDED_PROTO=>1, env=>{HTTP_X_FORWARDED_PROTO=>'http'}),
   0, 'X-Forwarded-Proto http stays off');

done_testing();
