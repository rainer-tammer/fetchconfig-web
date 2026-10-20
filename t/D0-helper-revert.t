use strict; use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;

# The privileged helper's "revert" subcommand (v1.3).
#
# revert copies "<target>.tmpl.bak" back over "<target>.tmpl". The backup path
# is DERIVED from the target, never passed in, so there is no source directory
# for a caller to redirect -- but the .bak itself was only tested with -e/-r.
# The helper runs as root, so following a symlinked .bak would copy whatever it
# points at into a template that the web UI then renders and serves.
# 'delete' and 'rename' already refused a symlinked .bak; 'revert' did not.

my $helper = "$FindBin::Bin/../fetchconfig-web-install-template.pl";
plan skip_all => "helper not found" unless -f $helper;

my $td = tempdir(CLEANUP => 1);

sub run_helper {
    my (@args) = @_;
    my $out = `$^X \Q$helper\E @{[ map { "\Q$_\E" } @args ]} 2>&1`;
    return ($? >> 8, $out);
}

# --- the normal case still works -------------------------------------------
{
    open(my $f, '>', "$td/good.tmpl")     or die $!; print $f "CURRENT\n"; close $f;
    open($f,    '>', "$td/good.tmpl.bak") or die $!; print $f "BACKUP\n";  close $f;

    my ($rc, $out) = run_helper('revert', "$td/good.tmpl");
    is($rc, 0, 'revert from a real .bak exits 0') or diag $out;
    my $got = do { local $/; open(my $r,'<',"$td/good.tmpl") or die $!; <$r> };
    is($got, "BACKUP\n", 'revert restored the backup content');
}

# --- a symlinked .bak is refused -------------------------------------------
{
    open(my $f, '>', "$td/evil.tmpl") or die $!; print $f "ORIGINAL\n"; close $f;
    # Point the backup at a file outside the template directory.
    open($f, '>', "$td/secret.txt") or die $!; print $f "SECRET\n"; close $f;
    symlink("$td/secret.txt", "$td/evil.tmpl.bak")
        or plan skip_all => "cannot create symlink on this filesystem";

    my ($rc, $out) = run_helper('revert', "$td/evil.tmpl");
    isnt($rc, 0, 'revert from a symlinked .bak fails');
    like($out, qr/symbolic link/, '... and says why');

    my $got = do { local $/; open(my $r,'<',"$td/evil.tmpl") or die $!; <$r> };
    is($got, "ORIGINAL\n", '... and the template is left untouched');
    unlike($got, qr/SECRET/, '... the symlink target was not copied in');
}

# --- a missing .bak is still refused ---------------------------------------
{
    open(my $f, '>', "$td/nobak.tmpl") or die $!; print $f "X\n"; close $f;
    my ($rc, $out) = run_helper('revert', "$td/nobak.tmpl");
    isnt($rc, 0, 'revert with no .bak fails');
    like($out, qr/no backup to revert from/, '... with the expected message');
}

# --- version carries the hardening -----------------------------------------
{
    my ($rc, $out) = run_helper('--version');
    is($rc, 0, 'helper --version exits 0');
    like($out, qr/\b1\.5\b/, 'helper reports v1.5');
}

# --- 1.4: read-debug / delete-debug ----------------------------------------
# fetchconfig writes <repository>/<dev-id>.debug as root, mode 0600, so the
# web-server user can neither open it nor unlink it (unlink needs write
# permission on the root-owned repository DIRECTORY). These two subcommands
# close that gap through the SAME sudoers rule the template editor already
# uses, so an upgrade needs no sudoers change.
{
    # read-debug copies the file to stdout verbatim, including high bytes.
    my $bin = "line1\nline2\n\xff\xfc\n";
    open(my $f, '>', "$td/d1.debug") or die $!; binmode($f); print $f $bin; close $f;

    my $out = `$^X \Q$helper\E read-debug \Q$td/d1.debug\E 2>/dev/null`;
    is($out, $bin, 'read-debug round-trips the bytes exactly');

    # stdout must carry NOTHING but the file: errors go to stderr, so the
    # caller can treat stdout as the content.
    my ($rc2, $both) = run_helper('read-debug', "$td/d1.debug");
    is($rc2, 0, 'read-debug exits 0');
    is($both, $bin, '... and writes no banner or warning onto stdout');

    # The offset argument exists so a huge log is not pulled through the pipe
    # in full just to show its tail.
    my $tail = `$^X \Q$helper\E read-debug \Q$td/d1.debug\E 6 2>/dev/null`;
    is($tail, substr($bin, 6), 'read-debug honours a byte offset');

    # v1.5: the LENGTH argument. Load-bearing, not an optimisation -- the
    # viewer shows a large log as head+tail, and without a length the head
    # read would pull a multi-gigabyte file through the pipe in full.
    my $head = `$^X \Q$helper\E read-debug \Q$td/d1.debug\E 0 5 2>/dev/null`;
    is($head, substr($bin, 0, 5), 'read-debug honours a byte window');
    my $past = `$^X \Q$helper\E read-debug \Q$td/d1.debug\E 3 99999 2>/dev/null`;
    is($past, substr($bin, 3), 'a length past EOF just stops at EOF');
    my ($rcz) = run_helper('read-debug', "$td/d1.debug", '0', '0');
    isnt($rcz, 0, 'a zero length is refused');
    my ($rcn) = run_helper('read-debug', "$td/d1.debug", '0', '-5');
    isnt($rcn, 0, 'a negative length is refused');
    my ($rc3, $o3) = run_helper('read-debug', "$td/d1.debug", '-1');
    isnt($rc3, 0, 'a negative offset is refused');

    # Same path hardening as the .tmpl commands, with the suffix swapped.
    open($f, '>', "$td/notdebug.txt") or die $!; print $f "x\n"; close $f;
    my ($rc4, $o4) = run_helper('read-debug', "$td/notdebug.txt");
    isnt($rc4, 0, 'read-debug refuses a non-.debug suffix');
    like($o4, qr/must end in \.debug/, '... and says why');

    my ($rc5, $o5) = run_helper('read-debug', '/tmp/../etc/passwd.debug');
    isnt($rc5, 0, 'read-debug refuses ".." traversal');
    my ($rc6, $o6) = run_helper('read-debug', 'relative.debug');
    isnt($rc6, 0, 'read-debug refuses a relative path');

    symlink("$td/d1.debug", "$td/link.debug")
        and do {
            my ($rc7, $o7) = run_helper('read-debug', "$td/link.debug");
            isnt($rc7, 0, 'read-debug refuses a symlink');
            like($o7, qr/symbolic link/, '... and says why');
        };

    # delete-debug removes it, and then has nothing left to remove.
    my ($rc8) = run_helper('delete-debug', "$td/d1.debug");
    is($rc8, 0, 'delete-debug removes the log');
    ok(!-e "$td/d1.debug", '... the file is gone');
    my ($rc9, $o9) = run_helper('delete-debug', "$td/d1.debug");
    isnt($rc9, 0, 'delete-debug on a missing file fails');

    # The .tmpl commands must still enforce .tmpl after the suffix was made a
    # parameter.
    my ($rc10, $o10) = run_helper('delete', "$td/x.debug");
    isnt($rc10, 0, 'the .tmpl commands still reject a .debug target');
    like($o10, qr/must end in \.tmpl/, '... with the .tmpl message');
}

done_testing();
