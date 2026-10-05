use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config(SESSION_TTL => 28800, SESSION_MAX_LIFETIME => 86400);
load_cgi($cfg); main::read_config();
my %kv; { open(my $r,'<',$cfg); while(<$r>){chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b;} close($r); }
my $sdir = $kv{SESSION_DIR};
mkdir $sdir unless -d $sdir;

# create_session writes a 5-line file incl login_time; load returns the user
my $sid = main::create_session('admin','');
my ($u) = main::load_session($sid);
is($u, 'admin', 'fresh session loads');
{
    open(my $f,'<',"$sdir/$sid"); my @L=<$f>; close($f);
    is(scalar(@L), 5, 'session file has 5 lines (incl login_time)');
    like($L[4], qr/^\d+\n?$/, 'line 5 is a login epoch');
}

# absolute cap: login_time two days ago -> load must expire and unlink
{
    open(my $w,'>',"$sdir/$sid") or die $!;
    print $w "admin\n", (time()+28800), "\n", ("a"x48), "\n\n", (time()-2*86400), "\n";
    close($w);
    my ($u2) = main::load_session($sid);
    ok(!defined $u2, 'session past the absolute cap is rejected');
    ok(!-e "$sdir/$sid", 'capped session file is unlinked on load');
}

# legacy 4-line file (no login_time) loads and is upgraded to 5 lines
{
    my $sid3 = 'b' x 48;
    open(my $w,'>',"$sdir/$sid3") or die $!;
    print $w "admin\n", (time()+28800), "\n", ("c"x48), "\n\n";   # 4 lines
    close($w);
    my ($u3) = main::load_session($sid3);
    is($u3, 'admin', 'legacy 4-line session still loads');
    open(my $f,'<',"$sdir/$sid3"); my @L=<$f>; close($f);
    is(scalar(@L), 5, 'legacy session upgraded to 5 lines on load');
    unlink "$sdir/$sid3";
}

# sweep removes an expired file, keeps a valid one
{
    unlink "$sdir/.last_sweep";
    my $dead = 'd' x 48; my $live = 'f' x 48;
    open(my $w,'>',"$sdir/$dead"); print $w "admin\n", (time()-100), "\n", ("e"x48), "\n\n", (time()-100), "\n"; close($w);
    open($w,'>',"$sdir/$live"); print $w "admin\n", (time()+28800), "\n", ("g"x48), "\n\n", time(), "\n"; close($w);
    main::sweep_sessions();
    ok(!-e "$sdir/$dead", 'sweep removes an expired session file');
    ok( -e "$sdir/$live", 'sweep keeps a valid session file');
}

# throttle: a second sweep within SESSION_TTL does not run
{
    my $dead2 = '0' x 48;
    open(my $w,'>',"$sdir/$dead2"); print $w "admin\n", (time()-100), "\n", ("h"x48), "\n\n", (time()-100), "\n"; close($w);
    main::sweep_sessions();   # stamp is fresh from the previous sweep
    ok( -e "$sdir/$dead2", 'second sweep within SESSION_TTL is throttled (skipped)');
}

# --- invalidate_user_sessions: keeps $keep_sid and other users (B/C) ---
{
    my $a1 = main::create_session('alice','');
    my $a2 = main::create_session('alice','');
    my $b1 = main::create_session('bob','');
    main::invalidate_user_sessions('alice', $a1);
    ok( -e "$sdir/$a1", 'kept session (self-change current id) survives');
    ok(!-e "$sdir/$a2", "user's other session is invalidated");
    ok( -e "$sdir/$b1", 'another user is untouched');
    main::invalidate_user_sessions('bob', undef);   # admin reset: kill all of bob
    ok(!-e "$sdir/$b1", 'admin reset invalidates all of the target user');
    unlink "$sdir/$a1";
}

done_testing();
