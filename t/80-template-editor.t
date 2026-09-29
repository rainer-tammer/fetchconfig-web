use strict; use warnings;
use Test::More;
use File::Spec; use File::Temp qw(tempdir);
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# Config with a stub fetchconfig that answers -t and --check-template, a
# template dir, and no sudo (direct write path).
my ($cfg, $dir, $fcp) = make_config(USE_SUDO_FOR_BACKUP_NOW => 0);
my $tdir = tempdir(CLEANUP => 1);
my $tmpl = File::Spec->catfile($tdir, 'cisco-ios.tmpl');
open(my $w, '>', $tmpl) or die $!; print $w "transport ssh\nstate s\n  expect prompt -> done\n"; close($w);

my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open($w, '>', $stub) or die $!;
print $w <<"STUB";
#!/usr/bin/perl
my \$ct; for (my \$i=0;\$i<\@ARGV;\$i++){ \$ct=\$ARGV[\$i+1] if \$ARGV[\$i] eq '--check-template'; }
if (defined \$ct) {
  local \$/; open(my \$f,'<',\$ct); my \$c=<\$f>||''; close(\$f);
  if (\$c =~ /transport_/) {
    print STDERR "fetchconfig.pl: error: \$ct: NOT ok - 1 error(s):\\n";
    print STDERR "fetchconfig.pl: error:   line 1: unrecognised directive\\n";
    exit 1;
  }
  print STDERR "fetchconfig.pl: info: \$ct: ok (structural check only)\\n";
  exit 0;
}
my \$t=0; for (\@ARGV){ \$t=1 if \$_ eq '-t'; }
if (\$t) { print STDERR "debug: 1. template dir: $tdir\\n"; print "1 cisco-ios\\n"; exit 0; }
exit 0;
STUB
close($w); chmod 0755, $stub;

load_cgi($cfg); main::read_config();

# path whitelist
ok( main::template_path_ok($tmpl),                 'known template path allowed');
ok(!main::template_path_ok("$tdir/../etc/x.tmpl"), 'path with .. rejected');
ok(!main::template_path_ok("$tdir/nope.tmpl"),     'unknown path rejected');

# check good vs bad buffer
my ($ok1) = main::run_check_template($tmpl);
is($ok1, 1, 'check of a good template returns ok');

# save (direct write) + backup + revert
my ($sok, $smsg) = main::save_template($tmpl, "# edited\ntransport ssh\nstate s\n  expect prompt -> done\n");
ok($sok, 'save succeeds (direct write)');
ok(-f "$tmpl.bak", 'single .bak created on save');
ok(defined main::template_backup_path($tmpl), 'backup path detected (Revert button would show)');

my ($rok) = main::revert_template($tmpl);
ok($rok, 'revert succeeds');
my $now = do { local $/; open(my $f,'<',$tmpl); <$f> };
unlike($now, qr/edited/, 'revert restored the pre-save content');

done_testing();
