use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# helpers over the (lexical) catalog, via the CGI's accessors
sub keys_of { return { map { $_ => 1 } main::model_option_keys($_[0]) } }
sub is_mand { my ($m,$o)=@_; my $s=main::option_spec($m,$o); return $s && $s->{mandatory}; }
sub has_opt { my ($m,$o)=@_; return exists keys_of($m)->{$o}; }

my @models = main::known_models();
ok(scalar(@models) >= 35, 'catalog has >= 35 models (' . scalar(@models) . ')');
ok((grep { $_ eq 'generic' } @models), 'generic model present');

# generic: model= is a mandatory template dropdown
my $sp = main::option_spec('generic','model');
is($sp->{type}, 'enum_template', 'generic model = enum_template');
ok($sp->{mandatory}, 'generic model mandatory (catalog level)');

# timeout is optional on EVERY model (fetchconfig defaults to 30s)
my @bad = grep { is_mand($_, 'timeout') } @models;
is("@bad", '', 'no model has mandatory timeout');

# audit fixes
ok(!has_opt('mikrotik','enable'),   'mikrotik has no enable');
ok( has_opt('cisco-sg300','enable'),   'cisco-sg300 has enable');
ok( has_opt('cisco-sg300','show_cmd'), 'cisco-sg300 has show_cmd');
ok( has_opt('procurve','enable'),      'procurve has enable');
ok( has_opt('procurve-ssh','enable'),  'procurve-ssh has enable');
ok( has_opt('dell','show_cmd'),        'dell has show_cmd');
ok( has_opt('comware-ssh','debug'),    'comware-ssh has debug');
ok( has_opt('mediant-sbc','pager_cmd'),'mediant-sbc has pager_cmd');

# mandatory core set on a normal model
ok(is_mand('cisco-ios','user') && is_mand('cisco-ios','pass')
   && is_mand('cisco-ios','enable') && is_mand('cisco-ios','repository')
   && is_mand('cisco-ios','keep'), 'cisco-ios mandatory core set');

# procurve-snmp: community mandatory, no user/pass
ok(is_mand('procurve-snmp','community'), 'procurve-snmp community mandatory');
ok(!has_opt('procurve-snmp','user'),     'procurve-snmp has no user');

done_testing();
