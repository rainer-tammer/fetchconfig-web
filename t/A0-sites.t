use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg, $dir, $fcp) = make_config();
# A device table with tagged + untagged devices.
my %kv; { open(my $r,'<',$cfg); while(<$r>){chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b;} close($r); }
open(my $w, '>', $kv{DEVICE_TABLE}) or die "write table: $!";
print $w <<'DT';
# DEFAULT OPTIONS SECTION
default: cisco-ios user=a,pass=b,repository=/r,keep=5
# eMail
email: from=a,to=b,smtp=s
# DEVICES SECTION
cisco-ios sw-ber 10.0.0.1 user=x,pass=y,repository=/r,keep=5,site=BER01
cisco-ios sw-ham 10.0.0.2 user=x,pass=y,repository=/r,keep=5,site=HAM01
cisco-ios sw-none 10.0.0.3 user=x,pass=y,repository=/r,keep=5
DT
close($w);

load_cgi($cfg); main::read_config();

# --- access decisions (pre-fetched acc hashref) ---
my $unrestricted = { unrestricted => 1, codes => {} };
my $ber          = { unrestricted => 0, codes => { BER01 => 1 } };

sub dev { my ($id,$site)=@_; return { kind=>'device', id=>$id,
    opts=>[ ($site ? ['site',$site] : ()) ] }; }

is(main::device_site_code(dev('x')), '*', 'untagged device -> * sentinel');
is(main::device_site_code(dev('x','BER01')), 'BER01', 'tagged device -> its code');

ok( main::device_visible_to_acc($unrestricted, dev('x','HAM01')), 'unrestricted sees any tagged device');
ok( main::device_visible_to_acc($unrestricted, dev('x')),         'unrestricted sees untagged device');
ok( main::device_visible_to_acc($ber, dev('x','BER01')),  'BER01 user sees BER01 device');
ok(!main::device_visible_to_acc($ber, dev('x','HAM01')),  'BER01 user does NOT see HAM01 device');
ok(!main::device_visible_to_acc($ber, dev('x')),          'BER01 user does NOT see untagged device');

# --- read_device_ids filter (no user = all) ---
my ($all) = main::read_device_ids();
is(scalar(@$all), 3, 'unfiltered device list has all 3');

# --- the merge logic (limited user edits only their device) ---
my $orig = main::parse_device_table(do { local $/; open(my $f,"<",$kv{DEVICE_TABLE}); <$f> });
# submitted: only sw-ber, with a comment added
my @submitted = ( { kind=>'device', model=>'cisco-ios', id=>'sw-ber', host=>'10.0.0.1',
    opts=>[['user','x'],['pass','y'],['repository','/r'],['keep','5'],['site','BER01'],['comment','edited']] } );
my @merged; my $ins=0;
for my $r (@$orig) {
    if ($r->{kind} eq 'device' && main::device_visible_to_acc($ber,$r)) {
        if (!$ins) { push @merged, @submitted; $ins=1; } next;
    }
    push @merged, $r;
}
my $out = main::serialize_records(\@merged);
like($out, qr/sw-ber.*comment=edited/, 'merge: the edited device is updated');
like($out, qr/sw-ham/,  'merge: other-site device preserved');
like($out, qr/sw-none/, 'merge: untagged device preserved');
like($out, qr/email: from=a/, 'merge: email section preserved');

# --- site_table_errors needs a dbh with known codes; use a fake ---
{
    package FakeDbh;
    sub selectall_arrayref { my($s,$q)=@_;
        return [ {id=>0,code=>'*',description=>'All sites'},
                 {id=>1,code=>'BER01',description=>''},
                 {id=>2,code=>'HAM01',description=>''} ] if $q=~/FROM sites/;
        return []; }
    sub disconnect {}
}
my $fdbh = bless {}, 'FakeDbh';
# reset the per-request sites cache so the fake dbh is used
{ no warnings; $main::_sites_cache = undef; }
my @e1 = main::site_table_errors($fdbh, [ dev('a','BER01'), dev('b','ZZZ') ]);
ok( (grep /not a known site code/, @e1), 'unknown site code reported');
{ no warnings; $main::_sites_cache = undef; }
my @e2 = main::site_table_errors($fdbh, [ dev('dup','BER01'), dev('dup','HAM01') ]);
ok( (grep /Duplicate device-id/, @e2), 'duplicate device-id reported');
{ no warnings; $main::_sites_cache = undef; }
my @e3 = main::site_table_errors($fdbh, [ dev('a','BER01'), dev('b','HAM01'), dev('c') ]);
ok( !(grep /not a known|Duplicate/, @e3), 'all-valid set has no errors (untagged ok)');


# --- require-site is scoped to the user's own devices in the merge ---
# site_table_errors with require_site=0 (limited save) must NOT fault an
# untagged device; with require_site=1 (admin save) it must.
{
    package FakeDbh2;
    sub selectall_arrayref { [ {id=>0,code=>'*',description=>'All'},{id=>1,code=>'BER01',description=>''} ] }
    sub disconnect {}
}
my $fd = bless {}, 'FakeDbh2';
{ no warnings; $main::_sites_cache = undef; }
my @untagged = ( { kind=>'device', id=>'x', opts=>[] } );   # no site=
ok( !(grep /must select a site/, main::site_table_errors($fd, \@untagged, 0)),
    'require_site=0: untagged device is NOT faulted (limited-user merge path)');
{ no warnings; $main::_sites_cache = undef; }
ok(  (grep /must select a site/, main::site_table_errors($fd, \@untagged, 1)),
    'require_site=1: untagged device IS faulted (admin save)');


# --- Check site assignment tool: finds untagged devices ---
{
    my $tbl = $kv{DEVICE_TABLE};
    open(my $w,'>',$tbl) or die $!;
    print $w "cisco-ios sw-a 10.0.0.1 user=x,pass=y,repository=/r,keep=5,site=BER01\n";
    print $w "cisco-ios sw-b 10.0.0.2 user=x,pass=y,repository=/r,keep=5\n";   # untagged
    close($w);
    my $recs = main::parse_device_table(do { local $/; open(my $f,'<',$tbl); <$f> });
    my @untagged = grep { $_->{kind} eq 'device'
                          && main::device_site_code($_) eq main::SITE_ALL_CODE() } @$recs;
    is(scalar(@untagged), 1, 'one untagged device found');
    is($untagged[0]{id}, 'sw-b', 'the untagged device is sw-b');
}


# --- regression: secret (pass=) is preserved on save (not wiped) ---
# The password write-back must resolve the ORIGINAL by table position, so a
# site-limited user submitting only their own device (sparse field index)
# still recovers the real password.
{
    my $SK = '\\__unchanged__/';   # the mask placeholder shown for secrets
    my $orig = [
        { kind=>'comment', raw=>'#c' },
        { kind=>'default', model=>'cisco-ios', opts=>[['user','a'],['pass','defpass']] },
        { kind=>'device', id=>'other', host=>'h', model=>'cisco-ios',
          opts=>[['user','m'],['pass','OTHERPASS'],['site','HAM']] },
        { kind=>'device', id=>'mine', host=>'h', model=>'cisco-ios',
          opts=>[['user','m'],['pass','MYSECRET'],['site','BER01']] },
    ];
    # The form carries ONLY r3 (the user's device at table position 3), masked.
    local %main::_FORM = (
        rec_count => 4,
        r3_kind => 'device', r3_model => 'cisco-ios', r3_id => 'mine', r3_host => 'h',
        r3_opt_user => 'm', r3_opt_pass => $SK, r3_opt_site => 'BER01',
    );
    no warnings 'redefine';
    my $old_param = \&CGI::param;
    local *CGI::param = sub {
        my ($s,$k) = @_;
        return (sort keys %main::_FORM) if @_ < 2 || !defined $k;
        return $main::_FORM{$k};
    };
    local *CGI::multi_param = sub { () };
    my ($recs) = main::reconstruct_records_from_form($orig);
    my ($dev) = grep { $_->{kind} eq 'device' } @$recs;
    my ($pass) = map { $_->[1] } grep { $_->[0] eq 'pass' } @{ $dev->{opts} };
    is($pass, 'MYSECRET', 'masked password restored from the correct original record');
}

done_testing();