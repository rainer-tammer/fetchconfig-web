use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# --- parse: a db: line becomes kind 'db' with parsed opts ---------------------
my $tbl = <<'TBL';
# a comment
default: cisco-ios user=admin
db: db_inst=fetchconfig,db_user=fetchconfig_dashboard,db_pass=secret,db_host=localhost,db_connect_timeout=5
cisco-ios r1 10.0.0.1 pass=x
TBL

my $recs = main::parse_device_table($tbl);
my ($db) = grep { $_->{kind} eq 'db' } @$recs;
ok($db, 'db: line parsed as kind db');
my %o = map { $_->[0] => $_->[1] } @{ $db->{opts} };
is($o{db_inst}, 'fetchconfig',            'db_inst parsed');
is($o{db_user}, 'fetchconfig_dashboard',  'db_user parsed');
is($o{db_pass}, 'secret',                 'db_pass parsed');
is($o{db_host}, 'localhost',              'db_host parsed');
is($o{db_connect_timeout}, '5',           'db_connect_timeout parsed');

# --- serialize: db: line emitted; comma/equals value quoted ------------------
my $out = main::serialize_records($recs);
like($out, qr/^db: .*db_inst=fetchconfig/m, 'db: line serialized');
like($out, qr/db_host=localhost/,           'db_host serialized');

my $recs2 = [ { kind => 'db', opts => [ ['db_inst','fc'], ['db_pass','a,b=c'], ['db_host','h'] ] } ];
my $out2  = main::serialize_records($recs2);
like($out2, qr/db_pass="a,b=c"/, 'value with comma/equals is double-quoted');

# an all-empty db record emits no line
my $out3 = main::serialize_records([ { kind => 'db', opts => [] } ]);
unlike($out3, qr/^db:/m, 'empty db record drops the line');

# --- round-trip stable -------------------------------------------------------
my $rt = main::parse_device_table($out);
my ($db3) = grep { $_->{kind} eq 'db' } @$rt;
my %o3 = map { $_->[0] => $_->[1] } @{ $db3->{opts} };
is($o3{db_pass}, 'secret',    'round-trip keeps db_pass');
is($o3{db_host}, 'localhost', 'round-trip keeps db_host');

# round-trip a quoted comma value
my $rt2 = main::parse_device_table($out2);
my ($db4) = grep { $_->{kind} eq 'db' } @$rt2;
my %o4 = map { $_->[0] => $_->[1] } @{ $db4->{opts} };
is($o4{db_pass}, 'a,b=c', 'round-trip keeps a comma/equals password');

# --- editor render: prefilled fields, password masked ------------------------
my $html = main::edit_table_db_fields_html($recs);
like($html,   qr/name="db_inst" value="fetchconfig"/, 'prefill db_inst');
like($html,   qr/name="db_host" value="localhost"/,   'prefill db_host');
like($html,   qr/name="db_pass"/,                      'db_pass field present');
unlike($html, qr/secret/,                              'real password NOT shown in the editor');
like($html,   qr/name="db_section" value="1"/,         'db_section marker present');
# db_sslmode is a dropdown; numeric fields are number inputs
like($html,   qr/<select name="db_sslmode"/,           'db_sslmode is a dropdown');
like($html,   qr/<option value="verify-full"/,         'sslmode options present');
like($html,   qr/<input type="number"[^>]*name="db_connect_timeout"/, 'db_connect_timeout is a number input');
like($html,   qr/<input type="number"[^>]*name="db_max_outbox_days"/, 'db_max_outbox_days is a number input');

# --- mask_secrets masks db_pass in the raw-table view (Setup) -----------------
like(main::mask_secrets($out), qr/db_pass=\?\*\*\*\?/, 'db_pass masked in raw device-table display');

done_testing();
