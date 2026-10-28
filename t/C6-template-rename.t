use strict; use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# Template rename (2.05): the direct-fallback rename_template_file() (the test
# config sets no TEMPLATE_HELPER, so the direct rename() path is exercised), and
# the privileged helper's "rename" subcommand.

my ($cfg, $dir) = make_config();
load_cgi($cfg); main::read_config();

my $td = tempdir(CLEANUP => 1);
sub put { my ($p,$c) = @_; open(my $f,'>',$p) or die "$p: $!"; print $f $c; close($f); }

# --- rename_template_file: happy path, .bak moved ---
put("$td/alpha.tmpl",     "body\n");
put("$td/alpha.tmpl.bak", "old backup\n");
my ($ok, $msg) = main::rename_template_file("$td/alpha.tmpl", "$td/beta.tmpl");
ok($ok, 'rename succeeds') or diag($msg);
ok(!-e "$td/alpha.tmpl",      'old template gone');
ok( -e "$td/beta.tmpl",       'new template present');
ok(!-e "$td/alpha.tmpl.bak",  'old .bak gone');
ok( -e "$td/beta.tmpl.bak",   'new .bak present (backup carried over)');

# --- refuse to overwrite an existing target ---
put("$td/gamma.tmpl", "g\n");
my ($ok2, $msg2) = main::rename_template_file("$td/beta.tmpl", "$td/gamma.tmpl");
ok(!$ok2, 'refuses to overwrite an existing target');
ok( -e "$td/beta.tmpl",  'source kept when target exists');
like($msg2, qr/already exists/i, 'message explains the clash');

# --- no .bak to move is fine ---
put("$td/solo.tmpl", "s\n");
my ($ok3) = main::rename_template_file("$td/solo.tmpl", "$td/solo2.tmpl");
ok($ok3, 'rename without a .bak works');
ok(-e "$td/solo2.tmpl" && !-e "$td/solo.tmpl", 'moved, no .bak needed');

# --- the privileged helper's "rename" subcommand ---
my $helper = "$FindBin::Bin/../fetchconfig-web-install-template.pl";

# Run the helper with its STDERR discarded. The refuse-* cases below deliberately
# trigger the helper's own error messages (fail() -> STDERR) and we assert only on
# the exit status; without this those messages leak into the test-harness output
# and look like warnings. /dev/null is the null device on Linux and AIX alike.
sub sys_quiet {
    open(my $save, '>&', \*STDERR) or return system(@_);
    unless (open(STDERR, '>', '/dev/null')) { return system(@_); }
    my $rc = system(@_);
    open(STDERR, '>&', $save);
    return $rc;
}

SKIP: {
    skip "helper not found", 4 unless -f $helper;
    put("$td/h1.tmpl",     "hb\n");
    put("$td/h1.tmpl.bak", "hbak\n");
    my $rc = sys_quiet($^X, $helper, 'rename', "$td/h1.tmpl", "$td/h2.tmpl");
    is($rc, 0, 'helper rename exits 0');
    ok(-e "$td/h2.tmpl" && -e "$td/h2.tmpl.bak", 'helper moved template and .bak');
    # refuse existing target (helper prints an error to STDERR -- discarded)
    put("$td/h3.tmpl", "x\n");
    my $rc2 = sys_quiet($^X, $helper, 'rename', "$td/h2.tmpl", "$td/h3.tmpl");
    isnt($rc2, 0, 'helper refuses existing target');
    # refuse non-.tmpl target (ditto)
    my $rc3 = sys_quiet($^X, $helper, 'rename', "$td/h2.tmpl", "$td/h2.txt");
    isnt($rc3, 0, 'helper refuses non-.tmpl target');
}

# --- helper failure messages: trim the dump, add a version hint for old helpers ---
my $dump = "fetchconfig-web-install-template.pl: error: unknown or missing command 'rename'.\n"
         . "fetchconfig-web-install-template.pl 1.1 -- privileged helper that installs ...\n"
         . "USAGE:\n    install <srcfile> <target.tmpl>\n    ... lots more help ...\n";
is(main::helper_error_summary($dump),
   "fetchconfig-web-install-template.pl: error: unknown or missing command 'rename'.",
   'summary = the first error line only');
my $m = main::helper_fail_msg(2, $dump);
like($m,   qr/^Helper failed \(exit 2\): /,              'wrapped with the exit code');
like($m,   qr/unknown or missing command 'rename'/,     'keeps the real error');
like($m,   qr/v1\.2 or newer/,                          'adds the redeploy/version hint');
unlike($m, qr/USAGE|privileged helper/,                 'drops the full help dump');

my $m2 = main::helper_fail_msg(2, "prog: error: target already exists: /x.tmpl\n");
like($m2,   qr/target already exists/, 'ordinary helper error is wrapped');
unlike($m2, qr/v1\.2/,                 'no version hint for ordinary errors');

is(main::helper_fail_msg(2, ''), 'Helper failed (exit 2).', 'empty output -> bare message');

done_testing();
