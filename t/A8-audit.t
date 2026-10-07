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

# A disconnected (ping-false) dbh passed to audit() must NOT lose the record:
# audit() detects the dead handle and opens its own connection.
{
    my $dead = bless {}, 'FCW_DeadDBH';
    { package FCW_DeadDBH; sub ping { 0 } sub prepare { die "dead handle used" } sub disconnect {} sub errstr { '' } }
    @ROWS = ();
    main::audit(dbh => $dead, action => 'set_edit_right', object_type => 'user',
                object_id => 'bob', field => 'edit_device_table', new_value => 'yes');
    is(scalar(@ROWS), 1, 'audit() opens a fresh connection when the passed dbh is dead');
    is($ROWS[0][2], 'set_edit_right', 'the permission-change row was written');
}

# set_user_sites logs which site codes were added/removed, plus old->new.
{
    no warnings 'redefine', 'once';
    local *main::user_is_admin    = sub { 1 };
    local *main::db_get_user      = sub { +{ username => 'bob' } };
    local *main::db_user_site_ids = sub { [1, 2] };   # before: GPN, WHF
    local *main::db_all_sites     = sub { [ {id=>0,code=>'*'}, {id=>1,code=>'GPN'},
                                            {id=>2,code=>'WHF'}, {id=>3,code=>'CTN'} ] };
    local *main::db_set_user_sites = sub { };
    local *main::redirect_to_user_page = sub { };
    local *CGI::multi_param = sub { my ($s,$k)=@_; return (1,3) if $k eq 'site_id'; return (); };  # after: GPN, CTN
    local *CGI::param = sub { my ($s,$k)=@_; return 'bob' if $k eq 'username'; return 0 if $k eq 'download_full_report'; return; };
    @ROWS = ();
    main::do_set_user_sites('admin');
    my ($r) = grep { $_->[2] eq 'set_user_sites' } @ROWS;
    ok($r, 'set_user_sites writes an audit row');
    like($r->[8], qr/added CTN/,   'logs the added site code');
    like($r->[8], qr/removed WHF/, 'logs the removed site code');
    is($r->[6], 'GPN, WHF', 'old_value lists the previous sites');
    is($r->[7], 'GPN, CTN', 'new_value lists the resulting sites');
}

# Right changes log grant vs revoke distinctly (download-report right).
{
    no warnings 'redefine', 'once';
    local *main::user_is_admin = sub { 1 };
    local *main::redirect_to_user_page = sub { };
    for my $case ([1,'granted','yes'], [0,'revoked','no']) {
        my ($val,$verb,$yn) = @$case;
        local *CGI::param = sub { my ($s,$k)=@_; return 'bob' if $k eq 'username'; return $val if $k eq 'value'; return; };
        @ROWS = ();
        main::do_set_download_full_report('admin');
        my ($r) = grep { $_->[2] eq 'set_download_full_report' } @ROWS;
        ok($r, "download-right change logged (value=$val)");
        like($r->[8], qr/\b$verb report-download right/, "detail says $verb");
        is($r->[7], $yn, "new_value is $yn");
    }
}

# Device-table external-change tripwire: records on first check, detects a
# later content change, and surfaces a warning (not a silent no-op) if app_state
# cannot be read.
{
    no warnings 'redefine', 'once';
    my %STATE; my @rows;
    my $good = do {
        package FCW_StateDBH;
        sub new { bless {}, shift }
        sub ping { 1 } sub disconnect {} sub errstr { '' }
        sub selectrow_array { my ($s,$sql,$a,@b)=@_; return ($STATE{$b[0]}) if $sql=~/app_state/; return (0); }
        sub do {
            my ($s,$sql,$a,@b)=@_;
            if ($sql=~/UPDATE app_state/) { my($v,$u,$k)=@b; return 0 unless exists $STATE{$k}; $STATE{$k}=$v; return 1; }
            if ($sql=~/INSERT INTO app_state/) { my($k,$v)=@b; $STATE{$k}=$v; return 1; }
            return 1;
        }
        sub prepare { my ($s,$sql)=@_; bless { sql=>$sql }, 'FCW_StateSTH' }
        package FCW_StateSTH;
        sub execute {
            my ($s,@b)=@_;
            push @rows, [@b] if $s->{sql}=~/INSERT INTO audit_log/;
            $s->{key} = $b[0] if $s->{sql}=~/app_state/;
            1;
        }
        sub fetchrow_array { my $s=shift; return $s->{sql}=~/app_state/ ? ($STATE{$s->{key}}) : (); }
        sub finish {}
        package main;
        FCW_StateDBH->new;
    };
    local *main::db_connect = sub { $good };
    local *main::device_table_mtime = sub { our $TOK; $TOK };

    our $TOK = '100.0:10:' . ('a' x 32);
    @rows=(); main::audit_check_device_table_change('admin');
    is(scalar(grep { $_->[2] eq 'external_change' } @rows), 0, 'first check records token, logs nothing');

    $TOK = '200.0:20:' . ('b' x 32);   # content (md5) changed
    @rows=(); main::audit_check_device_table_change('admin');
    is(scalar(grep { $_->[2] eq 'external_change' } @rows), 1, 'content change is detected and logged');

    $TOK = '300.0:20:' . ('b' x 32);   # mtime-only touch, same md5
    @rows=(); main::audit_check_device_table_change('admin');
    is(scalar(grep { $_->[2] eq 'external_change' } @rows), 0, 'mtime-only touch is not logged');

    # An in-app write (restore, site rename) changes the content but records the
    # new token via audit_record_device_table_token(), so the next check must
    # NOT flag it as an external change. Without that call the restore tripped a
    # false "changed outside this application" banner.
    $TOK = '400.0:40:' . ('c' x 32);   # new content, as a restore would produce
    main::audit_record_device_table_token($good, 'admin');   # the app records it
    @rows=(); main::audit_check_device_table_change('admin');
    is(scalar(grep { $_->[2] eq 'external_change' } @rows), 0,
       'in-app write that records the token is not flagged as external');

    # Error path: app_state read dies -> warning set, no false log.
    my $bad = do { package FCW_BadDBH; sub new { bless {}, shift }
        sub ping {1} sub disconnect {} sub errstr { 'permission denied' }
        sub selectrow_array { die 'permission denied' } sub do {1} sub prepare { bless {}, 'FCW_BadSTH' }
        package FCW_BadSTH; sub execute { return 0 } sub fetchrow_array { () } sub finish {}
        package main; FCW_BadDBH->new; };
    local *main::db_connect = sub { $bad };
    $main::AUDIT_WARNING = undef;
    @rows=(); main::audit_check_device_table_change('admin');
    like($main::AUDIT_WARNING, qr/app_state read failed/, 'app_state read failure surfaces a warning');
}

# The external-change detection shows the USER a banner (not just a log row):
# in-request via the global (editor-open), and once after login via the
# one-shot app_state notice that page_head reads and clears.
{
    no warnings 'redefine', 'once';
    my %STATE; 
    my $dbh = do {
        package FCW_BanDBH; sub new { bless {}, shift }
        sub ping {1} sub disconnect {} sub errstr {''}
        sub do { my ($s,$sql,$a,@b)=@_;
            if ($sql=~/UPDATE app_state/)      { my($v,$u,$k)=@b; return 0 unless exists $STATE{$k}; $STATE{$k}=$v; return 1; }
            if ($sql=~/INSERT INTO app_state/) { my($k,$v)=@b; $STATE{$k}=$v; return 1; }
            return 1; }
        sub prepare { my ($s,$sql)=@_; bless { sql=>$sql }, 'FCW_BanSTH' }
        package FCW_BanSTH;
        sub execute { my ($s,@b)=@_; $s->{key}=$b[0] if $s->{sql}=~/app_state/; 1 }
        sub fetchrow_array { my $s=shift; return $s->{sql}=~/app_state/ ? ($STATE{$s->{key}}) : (); }
        sub finish {}
        package main; FCW_BanDBH->new;
    };
    local *main::db_connect = sub { $dbh };
    local *main::current_session = sub { ('sid','admin','csrf','') };
    local *main::user_is_admin = sub { 0 };
    local *main::user_may_edit_table = sub { 0 };
    local *main::user_is_unrestricted = sub { 1 };
    local *main::fetchconfig_version_warning = sub { '' };
    # Under the unified priority banner (E2), a more severe banner suppresses
    # the external-change one. Stub the two higher-priority sources off so this
    # test exercises the external-change banner specifically.
    local *main::fatal_error_banner = sub { '' };

    # (a) in-request global (editor-open case)
    local $main::EXTERNAL_CHANGE_NOTICE = 'The device table was changed outside this application.';
    my $h = main::page_head('Edit', 'admin');
    like($h, qr/<div class="ext-change-warning"/, 'editor-open shows the external-change banner');

    # (b) one-shot after login: persisted notice, no global
    local $main::EXTERNAL_CHANGE_NOTICE = undef;
    $STATE{'external_notice:admin'} = 'The device table was changed outside this application.';
    my $h1 = main::page_head('Devices', 'admin');
    like($h1, qr/<div class="ext-change-warning"/, 'first page after login shows the banner');
    my $h2 = main::page_head('Devices', 'admin');
    unlike($h2, qr/<div class="ext-change-warning"/, 'banner is one-shot (gone on the next page)');

    # The audit-log link is admin-only (others cannot open the audit log).
    local $main::EXTERNAL_CHANGE_NOTICE = 'The device table was changed outside this application.';
    {
        local *main::user_is_admin = sub { 1 };
        my $ha = main::page_head('Edit', 'admin');
        like($ha, qr/action=tool_audit/, 'admin banner includes the audit-log link');
    }
    {
        local *main::user_is_admin = sub { 0 };
        my $hn = main::page_head('Edit', 'editor');
        like($hn,   qr/<div class="ext-change-warning"/, 'non-admin still sees the banner');
        unlike($hn, qr/action=tool_audit/, 'non-admin banner omits the audit-log link');
    }
}

done_testing();
