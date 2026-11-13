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

# procurve-snmp: snmp_community (renamed from community in 2.15.1, now OPTIONAL --
# it may be inherited from the default: line), no user/pass. snmp_write_community is
# procurve-snmp-only. The SNMP inventory options are common to every model.
ok(has_opt('procurve-snmp','snmp_community'),       'procurve-snmp has snmp_community');
ok(!is_mand('procurve-snmp','snmp_community'),       'procurve-snmp snmp_community is optional');
ok(!has_opt('procurve-snmp','community'),            'procurve-snmp no longer uses the old community option');
ok(has_opt('procurve-snmp','snmp_write_community'),  'procurve-snmp has snmp_write_community (RW)');
ok(!has_opt('cisco-ios','snmp_write_community'),     'snmp_write_community is procurve-snmp-only');
ok(has_opt('cisco-ios','snmp_community'),            'snmp_* inventory options are common (cisco-ios has snmp_community)');
ok(has_opt('cisco-ios','snmp_profile_file'),         'snmp_profile_file is a known (default-only) option');
ok(has_opt('cisco-ios','snmp_max_repetitions'),      'snmp_max_repetitions is a known snmp option');
is(main::option_spec('cisco-ios','snmp_max_repetitions')->{type}, 'int',
   'snmp_max_repetitions is an int option');
ok(!is_mand('cisco-ios','snmp_max_repetitions'),     'snmp_max_repetitions is optional');
ok(has_opt('cisco-ios','snmp_inventory_interval'),   'snmp_inventory_interval is a known snmp option');
is(main::option_spec('cisco-ios','snmp_inventory_interval')->{type}, 'int',
   'snmp_inventory_interval is an int option');
ok(!is_mand('cisco-ios','snmp_inventory_interval'),  'snmp_inventory_interval is optional');
is(main::option_spec('cisco-ios','snmp_inventory_level')->{type}, 'enum_snmp_inv_level',
   'snmp_inventory_level is a labeled 1|2 dropdown');
{
    my $h = main::render_option_field('r0','cisco-ios','snmp_inventory_level','2',0,'device','',0);
    like($h, qr/<select/,                         'snmp_inventory_level renders a <select>');
    like($h, qr/value="1"[^>]*>1 = chassis\+modules\+PSUs</, 'level 1 option + label');
    like($h, qr/value="2"[^>]*>2 = chassis\+modules\+PSUs\+optics</, 'level 2 option + label');
    unlike($h, qr/value=""/, 'no "(unset)"/empty option -- remove the option to inherit default:');
}
ok(!has_opt('procurve-snmp','user'),     'procurve-snmp has no user');


# site is a universal enum_site dropdown on EVERY model, including hand-built ones
# like procurve-snmp: show_edit_table auto-adds site= to every device row, and the
# catalog type is what makes it render as a dropdown rather than a text field.
for my $m (main::known_models()) {
    my $sp = main::option_spec($m, 'site');
    ok($sp && $sp->{type} eq 'enum_site', "$m exposes site as an enum_site dropdown");
}

# debug=on|off is a universal option (fetchconfig 9.71) -- every model exposes it.
for my $m (main::known_models()) {
    ok(scalar(grep { $_ eq 'debug' } main::model_option_keys($m)),
       "model $m exposes debug");
}

done_testing();
