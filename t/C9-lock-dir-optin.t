use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# F4, second half. The lock_dir allow-list restriction is OPT-IN, exactly like
# fetch_run and report. README: "without a lock line, lock_dir= is
# unrestricted (apart from fetchconfig's system-directory rule)."
#
# This matters because the fix for the missing lock_dir check could easily have
# been written to gate on the allow-list block as a whole (that is how
# repository and template behave, and how the editor decides to render the
# dropdown). That would silently start rejecting lock_dir= on every install
# that armors repository/template but never declared lock directories.
#
# The enforced case lives in t/C8-server-validation.t. It needs a table WITH a
# lock line, and the config globals are file-scoped lexicals that a test cannot
# re-point, so the no-lock case gets its own process here.

my ($cfg, $dir, $fcp) = make_config();
my %kv; { open(my $r,'<',$cfg) or die $!;
          while(<$r>){ chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b; }
          close($r); }

# Allow-list block present, repository + template declared, NO lock line.
open(my $w, '>', $kv{DEVICE_TABLE}) or die "write table: $!";
print $w <<'DT';
# DEFAULT OPTIONS SECTION

# directory allow list - must be directly edited on the server
directory: repository $REPO1     /usr/local/fetchconfig/config
directory: template   $TEMPLATE1 /usr/local/fetchconfig/templates
# directory allow list - must be directly edited on the server

cisco-ios sw1 10.0.0.1 user=x,pass=y,repository=$REPO1,keep=5
DT
close($w);

my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open($w, '>', $stub) or die $!;
print $w <<'STUB';
#!/usr/bin/perl
my $lad=0; for(@ARGV){$lad=1 if $_ eq '--list-allowed-dirs';}
exit 0 unless $lad;
print "1\trepository\t\$REPO1\t/usr/local/fetchconfig/config\n";
print "2\ttemplate\t\$TEMPLATE1\t/usr/local/fetchconfig/templates\n";
exit 0;
STUB
close($w); chmod 0755, $stub;

load_cgi($cfg); main::read_config();
no warnings 'once';

my $al = main::read_allowed_dirs();
ok($al->{present},             'allow-list block is present');
is(scalar @{ $al->{lock} }, 0, 'no lock directories are declared');

my $viol = sub {
    my (@opts) = @_;
    my @e = main::directory_allowlist_violations(
                [{ kind=>'device', model=>'cisco-ios', id=>'sw1', host=>'10.0.0.1',
                   opts=>[['user','u'],['pass','p'],['keep','5'], @opts] }]);
    return scalar @e;
};

ok(!$viol->(['repository','$REPO1'], ['lock_dir','/any/where']),
   'lock_dir is unrestricted when no lock line is declared (per README)');
ok(!$viol->(['repository','$REPO1'], ['lock_dir','$WHATEVER']),
   'an undeclared lock alias is likewise not rejected');

# The declared kinds must still be enforced in the very same table, so this is
# a targeted opt-out and not a hole.
ok($viol->(['repository','/etc']),
   'repository is still enforced in the same table');
ok($viol->(['repository','$REPO1'], ['template_dir','/etc']),
   'template_dir is still enforced in the same table');

done_testing();
