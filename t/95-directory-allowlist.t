use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg, $dir, $fcp) = make_config();
open(my $r,'<',$cfg) or die $!; my %kv; while(<$r>){ chomp; my($k,$v)=split/\s*=\s*/,$_,2; $kv{$k}=$v if defined $v; } close($r);
my $table = $kv{DEVICE_TABLE};

# device table with an armored directory: block (repository, 2 template, fetch_run)
open(my $w,'>',$table) or die $!;
print $w <<'DT';
# DEFAULT OPTIONS SECTION

# directory allow list - must be directly edited on the server
directory: repository $REPO1     /usr/local/fetchconfig/config
directory: template   $TEMPLATE1 /usr/local/fetchconfig/templates
directory: template   $TEMPLATE2 /usr/local/fetchconfig/templates_alt
directory: fetch_run  $CMD1      /usr/local/fetchconfig/fetch_run
# directory allow list - must be directly edited on the server

cisco-ios sw1 10.0.0.1 user=x,pass=y
DT
close($w);

# stub fetchconfig --list-allowed-dirs (tab-separated), rc 0
my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open($w,'>',$stub) or die $!;
print $w <<'STUB';
#!/usr/bin/perl
my $lad=0; for(@ARGV){$lad=1 if $_ eq '--list-allowed-dirs';}
exit 0 unless $lad;
print "1\trepository\t\$REPO1\t/usr/local/fetchconfig/config\n";
print "2\ttemplate\t\$TEMPLATE1\t/usr/local/fetchconfig/templates\n";
print "3\ttemplate\t\$TEMPLATE2\t/usr/local/fetchconfig/templates_alt\n";
print "4\tfetch_run\t\$CMD1\t/usr/local/fetchconfig/fetch_run\n";
print "# found 4 allowed director(y/ies): 1 repository, 2 template, 1 fetch_run\n";
exit 0;
STUB
close($w); chmod 0755, $stub;

load_cgi($cfg); main::read_config();

my $al = main::read_allowed_dirs();
is($al->{present}, 1, 'allow-list present (--list-allowed-dirs)');
is($al->{rc}, 0, 'rc 0');
is(scalar(@{$al->{repository}}), 1, 'one repository');
is(scalar(@{$al->{template}}), 2, 'two templates');
is(scalar(@{$al->{fetch_run}}), 1, 'one fetch_run');
is($al->{fetch_run_configured}, 1, 'fetch_run configured');
is($al->{fetch_run_disabled}, 0, 'fetch_run not disabled');

is(main::resolve_allowed_path('template','$TEMPLATE2'), '/usr/local/fetchconfig/templates_alt', 'template alias resolves');
is(main::resolve_allowed_path('fetch_run','$CMD1'), '/usr/local/fetchconfig/fetch_run', 'fetch_run alias resolves');
is(main::resolve_allowed_path('repository','$TEMPLATE1'), undef, 'wrong kind rejected');
is(main::alias_for_value('template','/usr/local/fetchconfig/templates_alt'), '$TEMPLATE2', 'path->alias');

# fetch_run split / join / reduce
my ($fd,$fc) = main::split_fetch_run('$CMD1/backup.sh --full');
is("$fd|$fc", '$CMD1|backup.sh --full', 'split alias fetch_run');
is(main::alias_for_fetch_run('/usr/local/fetchconfig/fetch_run/x.sh -o'), '$CMD1/x.sh -o', 'reduce fetch_run literal to alias');

sub dev { my (%o)=@_; return { kind=>'device', id=>'d', host=>'1.1.1.1', model=>'generic', opts=>[ map {[$_,$o{$_}]} keys %o ] }; }

ok(!grep(/allowed/, @{ main::validate_records([ dev(template_dir=>'$TEMPLATE1', repository=>'$REPO1', on_fetch_run=>'$CMD1/x.sh', pass=>'p', user=>'u', model=>'cisco', keep=>'5') ]) }),
   'all allowed aliases pass');
ok( grep(/allowed directory/, @{ main::validate_records([ dev(template_dir=>'/bad') ]) }), 'bad template_dir rejected');
ok( grep(/allowed fetch_run/, @{ main::validate_records([ dev(on_fetch_run=>'/bad/x.sh') ]) }), 'bad fetch_run dir rejected');

# serialize: armored block + alias normalisation (incl. fetch_run)
my $recs = main::parse_device_table(do { local $/; open(my $f,'<',$table); <$f> });
my $out = main::serialize_records($recs);
like($out, qr/# directory allow list - must be directly edited on the server\ndirectory: repository \$REPO1/, 'armored block re-emitted');
like($out, qr/^# directory$/m, 'directory header present');
my $o2 = main::serialize_records([ dev(model=>'generic', on_fetch_run=>'/usr/local/fetchconfig/fetch_run/run.sh') ]);
like($o2, qr/on_fetch_run=\$CMD1\/run\.sh/, 'fetch_run reduced to alias on serialize');

done_testing();
