use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# --------------------------------------------------------------------------
# snmp_inventory (and the other enum_onoff booleans) are PERMISSIVE booleans in
# fetchconfig: on/off, 1/0, yes/no. The editor writes the canonical on/off, but
# a table written by the engine (snmp_inventory=1) or by hand may carry any of
# them. The save-time validator must accept them all -- otherwise an untouched
# device line (e.g. #64 snmp_inventory=1) blocks the whole table save.
# --------------------------------------------------------------------------

sub dev { my ($id,%o)=@_; return { kind=>'device', id=>$id, host=>'10.0.0.1',
          model=>'cisco-ios', opts=>[ map { [$_, $o{$_}] } sort keys %o ] }; }

# the enum error we must NOT see for a valid boolean
sub enum_err {
    my $recs = shift;
    return grep { /snmp_inventory=.*is not one of/ } @{ main::validate_records($recs) };
}

for my $v (qw(on off 1 0 yes no On OFF Yes No)) {
    ok(!enum_err([ dev('sw1', snmp_inventory=>$v) ]),
       "snmp_inventory=$v is accepted (permissive boolean)");
}

# empty is allowed (inherits the default: value)
ok(!enum_err([ dev('sw1', snmp_inventory=>'') ]), 'snmp_inventory= (empty) is accepted');

# a genuinely invalid value is still rejected
ok(enum_err([ dev('sw1', snmp_inventory=>'maybe') ]),
   'snmp_inventory=maybe is still rejected');

# the other enum_onoff booleans accept the same permissive set
ok(!enum_err([ dev('sw1', snmp_inventory_history=>'1') ]) &&
   !grep({ /snmp_inventory_history=.*is not one of/ }
         @{ main::validate_records([ dev('sw1', snmp_inventory_history=>'1') ]) }),
   'snmp_inventory_history=1 is accepted too');
ok(!grep({ /snmp_fatal=.*is not one of/ }
         @{ main::validate_records([ dev('sw1', snmp_fatal=>'yes') ]) }),
   'snmp_fatal=yes is accepted too');

# render: an incoming "1"/"yes"/"0"/"no" maps to the canonical on/off the
# dropdown offers (so an existing value is not shown as "(unset)" and dropped).
{
    my $h1 = main::render_option_field('r0','cisco-ios','snmp_inventory','1',0,'device','',0);
    like($h1, qr/<option value="on"\s+selected>/, 'snmp_inventory=1 renders with "on" selected');
    my $h0 = main::render_option_field('r0','cisco-ios','snmp_inventory','0',0,'device','',0);
    like($h0, qr/<option value="off"\s+selected>/, 'snmp_inventory=0 renders with "off" selected');
    my $hy = main::render_option_field('r0','cisco-ios','snmp_inventory','yes',0,'device','',0);
    like($hy, qr/<option value="on"\s+selected>/, 'snmp_inventory=yes renders with "on" selected');
}

done_testing();
