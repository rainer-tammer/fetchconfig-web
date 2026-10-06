use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);
my $repoB = "$dir/repoB"; mkdir $repoB;
my $rep   = "$dir/rep";   mkdir $rep;
my ($cfg) = make_config();
mkdir "$dir/repoA";
load_cgi($cfg); main::read_config();
my %kv; { open(my $r,'<',$cfg); while(<$r>){chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b;} close($r); }
my $tbl = $kv{DEVICE_TABLE};
open(my $w,'>',$tbl) or die $!;
print $w "email: to=a\@b,report_dir=$rep\n";
print $w "default: cisco-ios repository=$dir/repoA\n";
print $w "cisco-ios sw1 10.0.0.1 user=x,pass=p,repository=$repoB\n";
print $w "cisco-ios sw2 10.0.0.2 user=x,pass=p\n";
close($w);

no warnings 'redefine', 'once';
local *main::read_allowed_dirs = sub { +{ present => 0, rc => 0 } };

my $rows = main::collect_repo_dirs();
my %byp; push @{$byp{$_->{purpose}}}, $_->{dir} for @$rows;
ok( (grep { $_ eq "$dir/repoA" } @{$byp{Repository}}), 'model default: repository= included');
ok( (grep { $_ eq $repoB }       @{$byp{Repository}}), 'per-device repository= included');
is_deeply($byp{'Report dir'}, [$rep], 'report_dir included once');

# dedup: a second device with the SAME repository collapses to one row
open($w,'>',$tbl) or die $!;
print $w "email: to=a\@b,report_dir=$rep\n";
print $w "cisco-ios sw1 10.0.0.1 user=x,pass=p,repository=$repoB\n";
print $w "cisco-ios sw3 10.0.0.3 user=x,pass=p,repository=$repoB\n";
close($w);
$rows = main::collect_repo_dirs();
my @rb = grep { $_->{dir} eq $repoB } @$rows;
is(scalar(@rb), 1, 'duplicate repository paths collapse to one row');

# FS grouping: two dirs on the same filesystem share an st_dev
my $d1 = (stat("$dir/repoA"))[0];
my $d2 = (stat($repoB))[0];
is($d1, $d2, 'tempdirs under the same mount share st_dev (same-FS detection basis)');

# Grouped render: directories on the same filesystem share one "Filesystem N"
# table; figures appear once (black) then gray on the rest. Uses a stub
# Filesys::Df so the test does not depend on the module being installed.
{
    # Put a stub Filesys::Df on @INC.
    my $stubdir = tempdir(CLEANUP => 1);
    mkdir "$stubdir/Filesys";
    open(my $sf,'>',"$stubdir/Filesys/Df.pm") or die $!;
    print $sf "package Filesys::Df;\nsub df { return { blocks=>1000000, bfree=>400000, bavail=>380000, per=>62 }; }\n1;\n";
    close($sf);
    unshift @INC, $stubdir;

    # Two dirs under the same tempdir mount => same st_dev => one group.
    open($w,'>',$tbl) or die $!;
    print $w "email: to=a\@b,report_dir=$rep\n";
    print $w "cisco-ios sw1 10.0.0.1 user=x,pass=p,repository=$repoB\n";
    close($w);

    no warnings 'redefine', 'once';
    local *main::user_may_use_tools = sub { 1 };
    local *main::page_head = sub { '' };
    local *main::page_foot = sub { '' };
    my $out = '';
    open(my $c,'>',\$out); my $save = select($c);
    main::show_tool_diskspace('admin');
    select($save); close($c);

    like($out, qr/Filesystem 1/, 'renders a Filesystem 1 group');
    my ($g1) = $out =~ m{Filesystem 1</h3>\s*<table[^>]*>(.*?)</table>}s;
    $g1 //= '';
    my $nrows = () = $g1 =~ /<td>(?:Repository|Report dir)</g;
    ok($nrows >= 2, 'same-filesystem directories grouped into one table');
    like($g1, qr/<td class="muted">[\d.]+ [KMGT]?B</, 'repeat rows show figures in gray');
}

# Source tags: allow-list repository/report dirs are included; a dir that is both
# used and allow-listed is "allowed and configured"; allow-list-only is "allowed".
{
    no warnings 'redefine', 'once';
    local *main::read_allowed_dirs = sub { +{ present=>1,
        repository=>[{alias=>'$R1',path=>$repoB},{alias=>'$R2',path=>"$dir/spare"}],
        report=>[{alias=>'$RP',path=>$rep}],
        template=>[], fetch_run=>[] } };
    local *main::resolve_allowed_path = sub {
        my ($k,$v)=@_;
        my %m=('$R1'=>$repoB,'$R2'=>"$dir/spare",'$RP'=>$rep);
        return $m{$v};
    };
    open($w,'>',$tbl) or die $!;
    print $w "email: to=a\@b,report_dir=\$RP\n";
    print $w "cisco-ios sw1 10.0.0.1 user=x,pass=p,repository=\$R1\n";
    close($w);
    my $rows = main::collect_repo_dirs();
    my %src; $src{$_->{dir}} = $_->{source} for @$rows;
    is($src{$repoB}, 'allowed and configured', 'used + allow-listed repo => allowed and configured');
    is($src{$rep},   'allowed and configured', 'used + allow-listed report dir => allowed and configured');
    is($src{"$dir/spare"}, 'allowed', 'allow-list-only repo => allowed');
}

done_testing();
