use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# Stub that answers -t in the new tab-separated format:
#   ID <tab> section <tab> full_path <tab> model <tab> dir
# default section = one dir (/tpl); device section = /tpl (all three) + /alt (cisco).
my ($cfg, $dir, $fcp) = make_config();
my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open(my $fh, '>', $stub) or die $!;
print $fh <<'STUB';
#!/usr/bin/perl
my $t=0; for (@ARGV){ $t=1 if $_ eq '-t'; }
exit 0 unless $t;
print STDERR "fetchconfig.pl: debug: list templates\n";
print "1\tdefault\t/tpl/cisco.tmpl\tcisco\t/tpl\n";
print "2\tdefault\t/tpl/cisco-ios.tmpl\tcisco-ios\t/tpl\n";
print "3\tdefault\t/tpl/procurve.tmpl\tprocurve\t/tpl\n";
print "4\tdevice\t/tpl/cisco.tmpl\tcisco\t/tpl\n";
print "5\tdevice\t/tpl/cisco-ios.tmpl\tcisco-ios\t/tpl\n";
print "6\tdevice\t/tpl/procurve.tmpl\tprocurve\t/tpl\n";
print "7\tdevice\t/alt/cisco.tmpl\tcisco\t/alt\n";
print "# found 7 template(s): 3 default, 4 device\n";
exit 0;
STUB
close($fh); chmod 0755, $stub;

load_cgi($cfg); main::read_config();

my $t = main::run_templates_t();
is($t->{rc}, 0, 'run_templates_t: rc 0');
is(scalar(@{ $t->{rows} }), 7, 'run_templates_t: 7 rows parsed');
is(main::template_default_dir(), '/tpl', 'template_default_dir is the single default dir');
is_deeply(main::template_models_for('default', ''), ['cisco','cisco-ios','procurve'],
    'default-section models');
is_deeply(main::template_models_for('device', '/tpl'), ['cisco','cisco-ios','procurve'],
    'device models in /tpl');
is_deeply(main::template_models_for('device', '/alt'), ['cisco'],
    'device models in /alt (cisco only)');

sub dev  { my ($id,%o)=@_; return { kind=>'device', id=>$id, host=>'10.0.0.1', model=>'generic',
             opts=>[ map { [$_, $o{$_}] } keys %o ] }; }
sub defg { my (%o)=@_;      return { kind=>'default', model=>'generic',
             opts=>[ map { [$_, $o{$_}] } keys %o ] }; }

my $e1 = main::validate_records([ dev('sw1', user=>'x', pass=>'y') ]);
ok((grep /needs a model/, @$e1), 'generic device w/o model, no default -> error');

my $e2 = main::validate_records([ dev('sw1', user=>'x', pass=>'y', model=>'cisco-ios') ]);
ok(!(grep /needs a model|not found/, @$e2), 'generic device with a valid model -> ok');

my $e3 = main::validate_records([ defg(model=>'procurve'), dev('sw1', user=>'x', pass=>'y') ]);
ok(!(grep /needs a model|not found/, @$e3), 'default: generic supplies a valid model -> ok');

my $e4 = main::validate_records([ defg(user=>'x') ]);
ok(!(grep /needs a model|not found/, @$e4), 'default: generic w/o model (no device) -> ok');

my $e5 = main::validate_records([ dev('sw1', user=>'x', model=>'procurve', template_dir=>'/alt') ]);
ok((grep /not found/, @$e5), 'device model not in its template_dir -> rejected');

my $e6 = main::validate_records([ dev('sw1', user=>'x', model=>'cisco', template_dir=>'/alt') ]);
ok(!(grep /not found/, @$e6), 'device model present in its template_dir -> ok');

my $e7 = main::validate_records([ defg(model=>'nosuch') ]);
ok((grep /not found/, @$e7), 'default: generic model not in the default dir -> rejected');


# rc 1 (no templates) and rc 2 (missing dir): run_templates_t reports them, and
# generic_model_dir_error blocks the save. Each needs a fresh interpreter
# because run_templates_t caches per process.
for my $case ([1, qr/no templates are available/], [2, qr/directory is missing/]) {
    my ($rc, $re) = @$case;
    open(my $w, '>', $stub) or die $!;
    print $w "#!/usr/bin/perl\nmy \$t=0; for(\@ARGV){\$t=1 if \$_ eq '-t';}\n";
    print $w "if(\$t){ print STDERR \"error: x\\n\"; exit $rc; }\nexit 0;\n";
    close($w); chmod 0755, $stub;
    my $out = `perl -I "$FindBin::Bin/lib" -e '
        use FCWebTest qw(load_cgi); load_cgi(q{$cfg}); main::read_config();
        my \$t=main::run_templates_t();
        my \$e=main::generic_model_dir_error("x","device","cisco","/tpl");
        print "rc=\$t->{rc};err=\$e";
    ' 2>/dev/null`;
    like($out, qr/rc=$rc/, "run_templates_t reports rc $rc");
    like($out, $re, "generic_model_dir_error blocks on rc $rc");
}


# scan_dir_models: discover *.tmpl in a directory -t does not know (A1).
{
    use File::Temp qw(tempdir); use File::Spec;
    my $d = tempdir(CLEANUP => 1);
    for my $n (qw(cisco.tmpl cisco-ios.tmpl readme.txt)) {
        open(my $w,'>',File::Spec->catfile($d,$n)) or die $!; print $w "x\n"; close($w);
    }
    is_deeply(main::scan_dir_models($d), ['cisco','cisco-ios'],
        'scan_dir_models lists *.tmpl models, skips non-tmpl');
    is_deeply(main::scan_dir_models("$d/../".(File::Spec->splitpath($d))[2]), [],
        'scan_dir_models rejects a path containing ".."');
    is_deeply(main::scan_dir_models('relative/path'), [], 'scan_dir_models rejects non-absolute');
    is_deeply(main::scan_dir_models('/no/such/dir'), [], 'scan_dir_models on missing dir -> empty');
  SKIP: {
        my $link = File::Spec->catfile($d,'lnk.tmpl');
        skip 'symlinks unsupported', 1 unless eval { symlink(File::Spec->catfile($d,'cisco.tmpl'),$link) };
        is_deeply(main::scan_dir_models($d), ['cisco','cisco-ios'],
            'scan_dir_models skips a symlinked .tmpl');
        unlink($link);
    }

    # Q-D accepts a model present in a typed dir that -t does not list.
    my $err = main::generic_model_dir_error("dev x","device","cisco",$d);
    is($err, '', 'save validation accepts a model found by scanning a typed dir');
    my $err2 = main::generic_model_dir_error("dev x","device","procurve",$d);
    like($err2, qr/not found/, 'save validation rejects a model absent from the typed dir');
}

done_testing();
