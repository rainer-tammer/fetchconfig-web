use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg, $dir, $fcp) = make_config();
open(my $r,'<',$cfg) or die $!; my %kv; while(<$r>){ chomp; my($k,$v)=split/\s*=\s*/,$_,2; $kv{$k}=$v if defined $v; } close($r);
my $table = $kv{DEVICE_TABLE};
open(my $w,'>',$table) or die $!;
print $w "directory: repository \$REPO1 /usr/local/fetchconfig/config\n";
print $w "directory: report \$REP /var/www/fetchconfig/reports\n";
print $w "cisco-ios sw1 10.0.0.1 user=x,pass=y\n";
close($w);
my $stub = File::Spec->catfile($fcp,'fetchconfig.pl');
open($w,'>',$stub) or die $!;
print $w "#!/usr/bin/perl\n";
print $w 'my $lad=0; for(@ARGV){$lad=1 if $_ eq q{--list-allowed-dirs};}'."\n";
print $w 'exit 0 unless $lad;'."\n";
print $w 'print "1\ttemplate\t", q{$T}, "\t/t\n";'."\n";
print $w 'print "2\treport\t", q{$REP}, "\t/var/www/fetchconfig/reports\n";'."\n";
print $w 'exit 0;'."\n";
close($w); chmod 0755,$stub;

load_cgi($cfg); main::read_config();

my $al = main::read_allowed_dirs();
is($al->{report_configured}, 1, 'report kind configured');
is($al->{report_disabled}, 0, 'report not disabled');
is(scalar(@{$al->{report}}), 1, 'one report entry');
is(main::resolve_allowed_path('report','$REP'), '/var/www/fetchconfig/reports', 'report alias resolves');
is(main::resolve_allowed_path('report','$NOPE'), undef, 'unknown report alias -> undef');
is(main::alias_for_value('report','/var/www/fetchconfig/reports'), '$REP', 'report path -> alias');

# enforcement on an email record
sub em { my (%o)=@_; return { kind=>'email', opts=>[ map {[$_,$o{$_}]} keys %o ] }; }
ok(!grep(/allowed report/, main::directory_allowlist_violations([ em(report_dir=>'$REP') ])),
   'allowed report_dir passes');
ok( grep(/allowed report/, main::directory_allowlist_violations([ em(report_dir=>'$NOPE') ])),
   'disallowed report_dir rejected');

# serialize normalises a literal report_dir to its alias
my $out = main::serialize_records([ em(from=>'a',to=>'b',smtp=>'s',report_dir=>'/var/www/fetchconfig/reports') ]);
like($out, qr/report_dir=\$REP/, 'report_dir literal normalised to alias on save');

# the six options render on the Email tab (proves they are in the catalog)
my %want = (report_dir=>qr/dir-alias-select/, write_report=>qr/<select/,
            email_max_diff=>qr/input/, web_report_url=>qr/opt-hint/,
            report_logo=>qr/input/, report_days=>qr/input/);
for my $k (sort keys %want) {
    my $val = $k eq 'report_dir' ? '$REP' : ($k eq 'write_report' ? 'on' : '5');
    my $h = main::render_option_field('rk','email',$k,$val,1);
    like($h, $want{$k}, "email option $k renders");
}

done_testing();
