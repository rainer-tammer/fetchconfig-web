use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();

# --- capture audit() INSERTs via a mock DBI --------------------------------
our @ROWS;
{ package FDB;
  sub prepare { my($s,$sql)=@_; bless { sql=>$sql }, 'FSTH'; }
  sub do { 1 } sub selectrow_array { (0) } sub selectrow_hashref { undef }
  sub disconnect {} sub errstr { '' }
}
{ package FSTH;
  sub execute { my $s=shift; push @main::ROWS, [@_] if $s->{sql}=~/INSERT INTO audit_log/; 1; }
  sub fetchall_arrayref { [] }
}
no warnings 'redefine', 'once';
local *main::db_connect   = sub { bless {}, 'FDB' };
local *main::current_user = sub { 'tester' };
$ENV{REMOTE_ADDR} = '10.9.8.7';

# 1. secret redaction
@ROWS=(); main::audit(action=>'save_table', object_type=>'device', object_id=>'sw1',
                      field=>'pass', old_value=>'OLD', new_value=>'NEW');
is($ROWS[0][6], '***', 'secret old value redacted');
is($ROWS[0][7], '***', 'secret new value redacted');
is($ROWS[0][0], 'tester', 'username captured');
is($ROWS[0][1], '10.9.8.7', 'ip captured');

# 2. non-secret verbatim
@ROWS=(); main::audit(action=>'save_table', field=>'user', old_value=>'a', new_value=>'b');
is($ROWS[0][6], 'a', 'non-secret old kept'); is($ROWS[0][7], 'b', 'non-secret new kept');

# 3. device-table diff -> add / change / remove rows (secret masked)
@ROWS=();
my $old=[ {kind=>'device',id=>'sw1',model=>'m',opts=>[['user','a'],['pass','P1'],['keep','5']]},
          {kind=>'device',id=>'sw2',model=>'m',opts=>[['user','a']]} ];
my $new=[ {kind=>'device',id=>'sw1',model=>'m',opts=>[['user','b'],['pass','P2'],['keep','5']]},
          {kind=>'device',id=>'sw3',model=>'m',opts=>[['user','c']]} ];
main::audit_device_table_changes('save_table',$old,$new,'tester');
my %by; for my $r (@ROWS){ push @{$by{$r->[8]//''}}, $r; }
ok((grep { ($_->[5]//'') eq 'pass' && $_->[6] eq '***' && $_->[7] eq '***' } @{$by{'changed option pass'}||[]}), 'changed secret masked in diff');
ok((grep { ($_->[5]//'') eq 'user' && $_->[6] eq 'a' && $_->[7] eq 'b' } @{$by{'changed option user'}||[]}), 'changed user a->b');
ok($by{'removed device'} && $by{'removed device'}[0][4] eq 'sw2', 'sw2 removed');
ok($by{'added device'}   && $by{'added device'}[0][4]   eq 'sw3', 'sw3 added');
ok(!(grep { ($_->[5]//'') eq 'keep' } @ROWS), 'unchanged option not logged');

# 4. filter SQL builder (parameterized)
{
    my %P=(f_user=>'bob',f_action=>'login_failed',f_text=>'x',f_from=>'2026-10-01',f_to=>'2026-10-03');
    local *CGI::param=sub{ my($s,$k)=@_; return $P{$k}; };
    my ($w,$b)=main::audit_filter_sql();
    like($w, qr/username = \?/, 'user filter');
    like($w, qr/ts >= \?/,      'from filter');
    like($w, qr/ts <  \(\?::date \+ 1\)/, 'to filter end-of-day');
    is(scalar(@$b), 8, 'bind count: user + action + 4x text + from + to');
}

# 5. fail-open: INSERT failure sets the warning, does not die
{
    local *main::db_connect = sub { bless {}, 'FAILDB' };
    { package FAILDB; sub prepare{undef} sub errstr{'disk full'} sub disconnect{} }
    $main::AUDIT_WARNING = undef;
    my $r = eval { main::audit(action=>'login', username=>'x'); 1 };
    ok($r, 'audit() does not die on INSERT failure');
    like($main::AUDIT_WARNING, qr/audit log write failed: disk full/, 'fail-open warning set');
}

# 6. external-change tripwire: md5 change logs, mtime-only touch does not
{
    is(main::_token_md5('1700000000.000000:46:0bac5e64d9f19c7c589c8583ef807855'),
       '0bac5e64d9f19c7c589c8583ef807855', 'token md5 extracted');
    isnt(main::_token_md5('1.0:46:'.('a'x32)), main::_token_md5('1.0:46:'.('b'x32)), 'different md5 distinguished');
}

done_testing();
