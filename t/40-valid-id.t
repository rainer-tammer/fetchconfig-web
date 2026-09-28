use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

ok( main::valid_id('sw1'),              'plain id');
ok( main::valid_id('sw1.acme.com'),     'dotted id');
ok( main::valid_id('IS-Nr_337591'),     'dash+underscore');
ok( main::valid_id('a.b-c_d'),          'mixed');
ok(!main::valid_id('-lead'),            'leading dash rejected (option injection)');
ok(!main::valid_id('a b'),              'space rejected');
ok(!main::valid_id('a/b'),              'slash rejected');
ok(!main::valid_id('a;b'),              'semicolon rejected');
ok(!main::valid_id(''),                 'empty rejected');
ok(!main::valid_id(undef),              'undef rejected');

done_testing();
