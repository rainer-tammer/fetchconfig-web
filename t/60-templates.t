use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# Point the config's FETCHCONFIG_PATH/BIN at a stub that answers -t.
my ($cfg, $dir, $fcp) = make_config();
my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open(my $fh, '>', $stub) or die $!;
print $fh <<'STUB';
#!/usr/bin/perl
my $t=0; for (@ARGV){ $t=1 if $_ eq '-t'; }
if ($t) {
  print STDERR "info: list templates\n";
  print "2 cisco-ios\n1 cisco\n3 procurve\n";   # deliberately out of order
  print "# found 3 template(s)\n";
  exit 0;
}
exit 0;
STUB
close($fh); chmod 0755, $stub;

load_cgi($cfg); main::read_config();

my $tl = main::list_templates();
is_deeply($tl, ['cisco','cisco-ios','procurve'],
    'list_templates: id stripped, sorted, # line skipped');

# validate_records: generic model rule
sub dev  { my ($id,%o)=@_; return { kind=>'device', id=>$id, host=>'10.0.0.1', model=>'generic',
             opts=>[ map { [$_, $o{$_}] } keys %o ] }; }
sub defg { my (%o)=@_;      return { kind=>'default', model=>'generic',
             opts=>[ map { [$_, $o{$_}] } keys %o ] }; }

my $e1 = main::validate_records([ dev('sw1', user=>'x', pass=>'y') ]);
ok((grep /needs a model/, @$e1), 'generic device w/o model, no default -> error');

my $e2 = main::validate_records([ dev('sw1', user=>'x', pass=>'y', model=>'cisco-ios') ]);
ok(!(grep /needs a model/, @$e2), 'generic device WITH model -> ok');

my $e3 = main::validate_records([ defg(model=>'procurve'), dev('sw1', user=>'x', pass=>'y') ]);
ok(!(grep /needs a model/, @$e3), 'default: generic supplies model -> ok');

my $e4 = main::validate_records([ defg(user=>'x') ]);
ok(!(grep /needs a model/, @$e4), 'default: generic w/o model (no device) -> ok');

done_testing();

