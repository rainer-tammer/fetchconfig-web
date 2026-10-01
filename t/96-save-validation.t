use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# C1: integer config keys reject an invalid value with a config error.
for my $case (['SESSION_TTL','abc','REJECT'], ['MAX_PARALLEL_SCAN','9','REJECT'],
              ['LOG_MAX_DEVICES','-1','REJECT'], ['MIN_PASSWORD_LENGTH','0','REJECT'],
              ['SESSION_TTL','3600','OK'], ['DEVICE_ID_FIELD','2','OK']) {
    my ($k,$v,$exp) = @$case;
    my ($cfg) = make_config($k => $v);
    my $out = `perl -I "$FindBin::Bin/lib" -e '
        use FCWebTest qw(load_cgi); load_cgi(q{$cfg}); my \$e=main::read_config();
        print defined \$e ? "REJECT" : "OK";' 2>/dev/null`;
    is($out, $exp, "config $k=$v -> $exp");
}

done_testing();
