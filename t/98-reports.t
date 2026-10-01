use strict; use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my $rdir = tempdir(CLEANUP => 1);
# two reports + a non-report file
for my $n ('report-20261001-112208.html', 'report-20260930-090000.html') {
    open(my $w,'>',File::Spec->catfile($rdir,$n)) or die $!;
    print $w qq{<div class="device-diff" data-device="sw1" data-state="Changed" id="d1">\n};
    print $w qq{<pre class="diff"><span class="d-hunk">1c1</span>\n};
    print $w qq{<span class="d-old">&lt; old &amp; line</span>\n};
    print $w qq{<span class="d-hunk">---</span>\n};
    print $w qq{<span class="d-new">&gt; new line</span>\n</pre>\n</div>\n};
    print $w qq{<div class="device-diff" data-device="sw2" data-state="Unchanged" id="d2"></div>\n};
    close($w);
}
open(my $w,'>',File::Spec->catfile($rdir,'logo.png')); print $w "x"; close($w);

my ($cfg, $dir, $fcp) = make_config();
open(my $r,'<',$cfg); my %kv; while(<$r>){ chomp; my($k,$v)=split/\s*=\s*/,$_,2; $kv{$k}=$v if defined $v; } close($r);
# device table: email report_dir = literal path (no allow-list -> literal accepted)
open($w,'>',$kv{DEVICE_TABLE}); print $w "email: from=a,to=b,smtp=s,report_dir=$rdir\n"; close($w);
# stub --list-allowed-dirs: no report allow-list -> literal path accepted
my $stub = File::Spec->catfile($fcp,'fetchconfig.pl');
open($w,'>',$stub); print $w "#!/usr/bin/perl\nexit 0;\n"; close($w); chmod 0755,$stub;

load_cgi($cfg); main::read_config();

is(main::report_directory(), $rdir, 'report_directory from email report_dir (literal)');

ok( main::valid_report_name('report-20261001-112208.html'), 'valid report name');
ok(!main::valid_report_name('../etc/passwd'),  'reject traversal');
ok(!main::valid_report_name('report.txt'),     'reject non-html');
ok(!main::valid_report_name('logo.png'),       'reject non-report');
ok(!main::valid_report_name('a/report-x.html'),'reject path separator');

my $list = main::list_reports($rdir);
is(scalar(@$list), 2, 'two reports listed (logo.png excluded)');
is($list->[0]{name}, 'report-20261001-112208.html', 'newest first');

my $html = do { local $/; open(my $f,'<',File::Spec->catfile($rdir,'report-20261001-112208.html')); <$f> };
my @b = main::parse_report_blocks($html);
is(scalar(@b), 2, 'two device blocks parsed');
is($b[0]{device}, 'sw1', 'device name parsed');
is($b[0]{state}, 'Changed', 'state parsed');
like($b[0]{diff_html}, qr/class="d-old"/, 'd-old re-emitted');
like($b[0]{diff_html}, qr/&lt; old &amp; line/, 'diff text re-escaped (entities preserved)');
is($b[1]{diff_html}, '', 'unchanged block has no diff');

# a report with no device blocks
my $none = "<html><body>nothing here</body></html>";
is(scalar(main::parse_report_blocks($none)), 0, 'no blocks in a non-report html');

# stamp -> epoch + name stamp
is(main::report_name_stamp('report-20261001-112208.html'), '20261001112208', 'stamp parsed');
ok(main::stamp_to_epoch('20261001112208') > 0, 'stamp_to_epoch');

done_testing();
