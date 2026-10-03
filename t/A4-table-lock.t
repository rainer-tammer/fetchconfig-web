use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use Fcntl qw(:flock);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();
my %kv; { open(my $r,'<',$cfg); while(<$r>){chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b;} close($r); }
my $tbl = $kv{DEVICE_TABLE};

# --- Gap A: the staleness token detects a same-size rewrite (not just mtime) ---
open(my $w,'>',$tbl) or die $!; print $w "cisco-ios sw1 10.0.0.1 user=x,pass=p,site=GPN\n"; close($w);
my $t1 = main::device_table_mtime();
like($t1, qr/^\d+(?:\.\d+)?:\d+:[0-9a-f]{32}$/, 'token is mtime:size:md5');
open($w,'>',$tbl) or die $!; print $w "cisco-ios sw1 10.0.0.1 user=x,pass=q,site=GPN\n"; close($w);  # same length
my $t2 = main::device_table_mtime();
isnt($t1, $t2, 'same-size rewrite changes the token (content digest)');

# --- Gap B: lock_device_table serialises writers and releases on scope exit ---
{
    my ($lk, $err) = main::lock_device_table();
    ok($lk, 'writer lock acquired') or diag($err);
    my $pid = fork();
    if ($pid == 0) {
        my $dir = $kv{BACKUP_TMP_DIR} || $kv{SESSION_DIR};
        open(my $f2,'>>',"$dir/device_table.lock") or exit 2;
        exit( flock($f2, LOCK_EX|LOCK_NB) ? 0 : 1 );
    }
    waitpid($pid,0);
    is($? >> 8, 1, 'a second writer is blocked while the lock is held');
}   # $lk out of scope -> released
{
    my $pid = fork();
    if ($pid == 0) {
        my $dir = $kv{BACKUP_TMP_DIR} || $kv{SESSION_DIR};
        open(my $f2,'>>',"$dir/device_table.lock") or exit 2;
        exit( flock($f2, LOCK_EX|LOCK_NB) ? 0 : 1 );
    }
    waitpid($pid,0);
    is($? >> 8, 0, 'lock is released when the handle goes out of scope');
}


# --- Restore honours the staleness token (Gap C, Layer 1) ---
{
    my ($cfg2, $dir2) = make_config(
        BACKUP_DEVICE_TABLE => undef,   # placeholder; set below
    );
    # Build a config whose backup + tmp dirs are writable test locations.
    my %kv2; { open(my $r,'<',$cfg2); while(<$r>){chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv2{$a}=$b if defined $b;} close($r); }
    my $sess = $kv2{SESSION_DIR}; mkdir $sess unless -d $sess;
    my $bakdir = "$sess/bak"; mkdir $bakdir unless -d $bakdir;
    open(my $cw,'>>',$cfg2) or die $!;
    print $cw "BACKUP_DEVICE_TABLE = $bakdir\n";
    print $cw "BACKUP_TMP_DIR = $sess\n";
    close($cw);
    load_cgi($cfg2); main::read_config();

    my $tbl2 = $kv2{DEVICE_TABLE};
    my $base = $tbl2; $base =~ s{.*/}{};
    my $bak = "$bakdir/$base.2026-10-01_120000.bak";
    open(my $bw,'>',$bak) or die $!; print $bw "cisco-ios sw1 10.0.0.1 user=x,pass=OLDBAK,site=GPN\n"; close($bw);
    open(my $lw,'>',$tbl2) or die $!; print $lw "cisco-ios sw1 10.0.0.1 user=x,pass=LIVE,site=GPN\n"; close($lw);

    no warnings 'redefine', 'once';
    local *main::user_may_use_tools = sub { 1 };
    my @redir;
    local *main::redirect_to_tools = sub { my %o=@_; push @redir, ($o{err} ? "ERR" : "OK"); };

    # stale token -> refused, table unchanged
    my %F = (name => "$base.2026-10-01_120000.bak", table_mtime => '1.0:1:deadbeef');
    local *CGI::param = sub { my($s,$k)=@_; return $F{$k}; };
    @redir=(); main::do_restore_backup('admin');
    is($redir[0], 'ERR', 'restore with a stale token is refused');
    my $live = do { open(my $f,'<',$tbl2); local $/; <$f> };
    like($live, qr/pass=LIVE/, 'live table is unchanged after a refused restore');

    # matching token -> restored
    my $tok = main::device_table_mtime();
    %F = (name => "$base.2026-10-01_120000.bak", table_mtime => $tok);
    @redir=(); main::do_restore_backup('admin');
    is($redir[0], 'OK', 'restore with a matching token succeeds');
    $live = do { open(my $f,'<',$tbl2); local $/; <$f> };
    like($live, qr/pass=OLDBAK/, 'live table now matches the restored backup');
}

done_testing();