#!/usr/bin/perl
#
# fetchconfig-web-install-template.pl -- privileged helper for fetchconfig-web,
# used when the web-server user cannot reach a file itself: installing an edited
# template, and reading or deleting a device debug log (fetchconfig writes those
# as root, mode 0600).
#
# It is meant to be run through sudo, e.g. from /etc/sudoers:
#
#   www ALL=(root) NOPASSWD: /usr/local/fetchconfig/bin/fetchconfig-web-install-template.pl
#
# and is called as:
#
#   sudo -n fetchconfig-web-install-template.pl install <srcfile> <target.tmpl>
#   sudo -n fetchconfig-web-install-template.pl revert  <target.tmpl>
#
#   install: back up <target.tmpl> to <target.tmpl.bak> (overwriting any
#            previous .bak), then copy <srcfile> over <target.tmpl>.
#   revert : copy <target.tmpl.bak> back over <target.tmpl>.
#
# The helper hardens the operation independently of the caller: the target must
# be an ABSOLUTE path, must NOT contain "..", and must end in ".tmpl". The
# source (for install) must be an existing readable file. Nothing else is
# touched. Copies are atomic (write a temp file in the target directory, then
# rename).
#
# Copyright (C) 2026 Rainer Tammer. GNU GPL v3 or later.

use strict;
use warnings;
use File::Copy ();
use File::Basename ();
use File::Temp qw(tempfile);

my $PROG    = 'fetchconfig-web-install-template.pl';
my $VERSION = '1.7';
my $COPYRIGHT = 'Copyright (C) 2026 Rainer Tammer. GNU GPL v3 or later.';

sub fail { print STDERR "$PROG: error: $_[0]\n"; exit 2; }

sub print_version { print "$PROG $VERSION\n"; }

sub print_help {
    my ($fh) = @_;
    $fh ||= \*STDOUT;
    print $fh <<"HELP";
$PROG $VERSION -- privileged helper that installs an edited fetchconfig
template file for fetchconfig-web, run via sudo.

USAGE:
    $PROG install     <srcfile> <target.tmpl>
    $PROG install-new <srcfile> <target.tmpl>
    $PROG revert      <target.tmpl>
    $PROG delete      <target.tmpl>
    $PROG rename      <old.tmpl> <new.tmpl>
    $PROG read-debug   <file.debug> [offset] [length]
    $PROG delete-debug <file.debug>
    $PROG list-cron    <user>

COMMANDS:
    install      Back up <target.tmpl> to <target.tmpl.bak> (overwriting any
                 previous .bak), then copy <srcfile> over <target.tmpl>.
    install-new  Create <target.tmpl> from <srcfile> ONLY if it does not already
                 exist (atomic; fails if the target is present). No backup is
                 made. Used for uploading a brand-new template.
    revert       Copy <target.tmpl.bak> back over <target.tmpl>.
    delete       Remove <target.tmpl> (and its <target.tmpl.bak>, if present).
    rename       Rename <old.tmpl> to <new.tmpl> (atomic; fails if <new.tmpl>
                 already exists). Its <old.tmpl.bak> is moved too, if present.
    read-debug   Copy a device debug log to stdout (binary). fetchconfig
                 writes <repository>/<dev-id>.debug as root, mode 0600. An
                 optional byte window (offset, length) lets the caller take
                 just the head or the tail of a large log.
    delete-debug Remove a device debug log. Unlinking it needs write
                 permission on the root-owned repository directory.
    list-cron    Print <user>'s crontab to stdout (read-only). Another user's
                 crontab is not readable by the web-server user -- the spool
                 directory is root-owned -- so "crontab -l" is run here. <user>
                 must exist (checked with getpwnam). Nothing is ever written.

The target must be an ABSOLUTE path, must NOT contain "..", must end in
".tmpl" (".debug" for the two debug commands), and must be a plain regular
file (not a symbolic or hard link).
Copies are atomic (temp file in the target directory, then rename).

OPTIONS:
    -h, --help, -?    Show this help and exit.
    -v, --version     Show the version and exit.

It is meant to be run through sudo, e.g. from /etc/sudoers:

    www ALL=(root) NOPASSWD: /usr/local/fetchconfig/fetchconfig-web-install-template.pl

$COPYRIGHT
HELP
    return;
}

sub check_target {
    my ($t, $suffix) = @_;
    $suffix = '.tmpl' unless defined $suffix;
    fail("target path is empty")                 if !defined $t || $t eq '';
    fail("target must be an absolute path: $t")  unless $t =~ m{^/};
    # Scope of this check, so it is not mistaken for more than it is: it
    # lstat()s the FINAL component only. An intermediate symlinked directory is
    # not resolved, and the helper enforces no directory allow-list of its own
    # -- with the documented sudoers grant it will write any absolute *.tmpl
    # anywhere as root. That is by design: the CGI pins every call site to an
    # allow-listed template directory, and this guards traversal, suffix and
    # file type, not WHICH directory. Audits re-raise this; it is intentional.
    fail("target must not contain '..': $t")     if $t =~ m{(?:^|/)\.\.(?:/|$)};
    # \z, not $: Perl's $ also matches just before a trailing newline, so
    # "evil.tmpl\n" would satisfy /\.tmpl$/ and slip past this check. The '..'
    # test above deliberately keeps $ -- there it widens what is REJECTED.
    fail("target must end in $suffix: $t")       unless $t =~ /\Q$suffix\E\z/;
    # If it already exists it must be a plain regular file: never a symlink
    # (could point outside the template dirs) and never hard-linked (the same
    # inode would be reachable under another name).
    if (-l $t) { fail("target is a symbolic link, refusing: $t"); }
    if (-e $t) {
        fail("target is not a regular file, refusing: $t") unless -f $t;
        my @st = stat($t);
        fail("target is hard-linked (link count $st[3]), refusing: $t") if @st && $st[3] > 1;
    }
    return $t;
}

# The source (the edited content written by the web app) must likewise be a
# plain regular file, not a link.
sub check_source {
    my ($s) = @_;
    fail("source file does not exist: $s")        unless -e $s;
    fail("source is a symbolic link, refusing: $s") if -l $s;
    fail("source is not a plain file: $s")        unless -f $s;
    fail("source is not readable: $s")            unless -r $s;
    return $s;
}

# Atomic copy $src -> $dst (temp in $dst's dir, then rename). Dies via fail().
sub atomic_copy {
    my ($src, $dst) = @_;
    my $dir = File::Basename::dirname($dst);
    fail("target directory does not exist: $dir") unless -d $dir;
    my ($fh, $tmp) = eval { tempfile('.fcweb-tmpl-XXXXXX', DIR => $dir) };
    fail("cannot create temp file in $dir: $@")   unless $fh;
    close($fh);
    unless (File::Copy::copy($src, $tmp)) {
        my $e = $!; unlink($tmp); fail("copy to temp failed: $e");
    }
    chmod(0644, $tmp);
    unless (rename($tmp, $dst)) {
        my $e = $!; unlink($tmp); fail("rename into place failed: $e");
    }
    return 1;
}

# Atomic create-if-absent: write a temp file in $dst's directory, then link() it
# into place. link() is atomic and fails if $dst already exists, so this never
# overwrites an existing template (no TOCTOU window between a check and the
# write). Dies via fail().
sub atomic_create_new {
    my ($src, $dst) = @_;
    my $dir = File::Basename::dirname($dst);
    fail("target directory does not exist: $dir") unless -d $dir;
    my ($fh, $tmp) = eval { tempfile('.fcweb-tmpl-XXXXXX', DIR => $dir) };
    fail("cannot create temp file in $dir: $@")   unless $fh;
    close($fh);
    unless (File::Copy::copy($src, $tmp)) {
        my $e = $!; unlink($tmp); fail("copy to temp failed: $e");
    }
    chmod(0644, $tmp);
    unless (link($tmp, $dst)) {
        my $e = $!; unlink($tmp);
        fail("target already exists: $dst") if -e $dst;
        fail("link into place failed: $e");
    }
    unlink($tmp);
    return 1;
}

# Help / version (accepted as the first argument, before the command).
for my $a (@ARGV) {
    if ($a eq '-h' || $a eq '--help' || $a eq '-?') { print_help(\*STDOUT); exit 0; }
    if ($a eq '-v' || $a eq '--version')            { print_version();       exit 0; }
}

my $cmd = shift @ARGV;
$cmd = '' unless defined $cmd;

if ($cmd eq 'install') {
    my ($src, $target) = @ARGV;
    fail("usage: $PROG install <srcfile> <target.tmpl>") unless defined $src && defined $target;
    check_source($src);
    check_target($target);
    # Back up the existing target to <target>.bak (single, overwritten).
    if (-e $target) {
        atomic_copy($target, "$target.bak");
    }
    atomic_copy($src, $target);
    print "$PROG: installed $target (backup: $target.bak)\n";
    exit 0;
}
elsif ($cmd eq 'install-new') {
    my ($src, $target) = @ARGV;
    fail("usage: $PROG install-new <srcfile> <target.tmpl>") unless defined $src && defined $target;
    check_source($src);
    check_target($target);
    fail("target already exists: $target") if -e $target;   # fast path; link() is the real guard
    atomic_create_new($src, $target);
    print "$PROG: created $target\n";
    exit 0;
}
elsif ($cmd eq 'revert') {
    my ($target) = @ARGV;
    fail("usage: $PROG revert <target.tmpl>") unless defined $target;
    check_target($target);
    my $bak = "$target.bak";
    fail("no backup to revert from: $bak")   unless -e $bak;
    # Refuse a symlinked backup, exactly as 'delete' and 'rename' do for the
    # same file, and as check_source() does for an install's source. We run as
    # root: following a symlink here would copy whatever it points at into the
    # template, which the web UI then renders and serves. The backup is always
    # the sibling "<target>.bak" -- it is derived from the target, never passed
    # in -- so a real one is never a symlink, and refusing costs nothing.
    fail("backup is a symbolic link, refusing: $bak") if -l $bak;
    fail("backup is not a plain file: $bak") unless -f $bak;
    fail("backup is not readable: $bak")     unless -r $bak;
    atomic_copy($bak, $target);
    print "$PROG: reverted $target from $bak\n";
    exit 0;
}
elsif ($cmd eq 'delete') {
    my ($target) = @ARGV;
    fail("usage: $PROG delete <target.tmpl>") unless defined $target;
    check_target($target);
    fail("target does not exist: $target") unless -e $target;
    unless (unlink($target)) { fail("cannot delete $target: $!"); }
    my $bak = "$target.bak";
    unlink($bak) if -e $bak && !-l $bak;        # best-effort: drop the backup too
    print "$PROG: deleted $target\n";
    exit 0;
}
elsif ($cmd eq 'rename') {
    my ($old, $new) = @ARGV;
    fail("usage: $PROG rename <old.tmpl> <new.tmpl>") unless defined $old && defined $new;
    check_target($old);                              # absolute, no "..", .tmpl, plain file
    check_target($new);
    fail("source does not exist: $old")  unless -e $old;
    fail("target already exists: $new")  if -e $new; # never overwrite
    unless (rename($old, $new)) { fail("cannot rename $old -> $new: $!"); }
    # Move the single backup alongside, if present (and a plain file, not a link).
    my ($obak, $nbak) = ("$old.bak", "$new.bak");
    if (-e $obak && !-l $obak) {
        rename($obak, $nbak)
            or print STDERR "$PROG: warning: renamed template but could not move $obak: $!\n";
    }
    print "$PROG: renamed $old -> $new\n";
    exit 0;
}
elsif ($cmd eq 'read-debug') {
    # fetchconfig writes <repository>/<dev-id>.debug as root, mode 0600, so the
    # web-server user cannot open it. Read it here and copy it to stdout.
    #
    # Output is BINARY: a debug log is raw device traffic, and a hex dump's
    # ASCII gutter carries bytes 0x80-0xFF. Nothing is written to stdout but
    # the file itself -- errors go to stderr -- so the caller can treat stdout
    # as the file content verbatim.
    my ($target, $offset, $length) = @ARGV;
    fail("usage: $PROG read-debug <file.debug> [offset] [length]") unless defined $target;
    check_target($target, '.debug');
    fail("target does not exist: $target") unless -e $target;
    # Optional byte window. The viewer shows a large log as its first chunk
    # plus its last chunk, so it asks for two windows rather than the whole
    # file -- without the length, reading the HEAD of a multi-gigabyte log
    # would pull all of it through the pipe just to discard the rest.
    if (defined $offset) {
        fail("offset must be a non-negative integer: $offset") unless $offset =~ /^\d+\z/;
    }
    if (defined $length) {
        fail("length must be a positive integer: $length")
            unless $length =~ /^\d+\z/ && $length > 0;
    }
    open(my $fh, '<', $target) or fail("cannot read $target: $!");
    binmode($fh);
    binmode(STDOUT);
    if ($offset) { seek($fh, $offset, 0) or fail("cannot seek $target: $!"); }
    my $left = $length;                       # undef => to end of file
    my $buf;
    while (!defined $left || $left > 0) {
        my $want = 65536;
        $want = $left if defined $left && $left < $want;
        my $n = sysread($fh, $buf, $want);
        last if !defined $n || $n == 0;
        print STDOUT $buf;
        $left -= $n if defined $left;
    }
    close($fh);
    exit 0;
}
elsif ($cmd eq 'delete-debug') {
    # Same ownership problem as read-debug: unlink needs write permission on
    # the REPOSITORY DIRECTORY, which is root-owned when fetchconfig runs from
    # cron. No .bak handling -- a debug log has none.
    my ($target) = @ARGV;
    fail("usage: $PROG delete-debug <file.debug>") unless defined $target;
    check_target($target, '.debug');
    fail("target does not exist: $target") unless -e $target;
    unless (unlink($target)) { fail("cannot delete $target: $!"); }
    print "$PROG: deleted $target\n";
    exit 0;
}
elsif ($cmd eq 'list-cron') {
    # Print a user's crontab. The web-server user cannot read another user's
    # crontab directly -- the spool directory (/var/spool/cron[/crontabs]) is
    # root-owned and not world-traversable -- so "crontab -l" is run here as
    # root. READ-ONLY: this command never installs, edits or removes a crontab.
    #
    # The user name is validated here independently of the caller and must
    # resolve to a real account (getpwnam). crontab itself is invoked with an
    # ARGUMENT VECTOR (no shell), so the user name is never interpreted.
    my ($cuser) = @ARGV;
    fail("usage: $PROG list-cron <user>") unless defined $cuser && $cuser ne '';
    fail("invalid user name: $cuser")
        unless $cuser =~ /^[A-Za-z_][A-Za-z0-9_.-]{0,31}\$?$/;
    fail("no such user: $cuser") unless defined getpwnam($cuser);

    # Force a predictable locale and PATH for the crontab call:
    #  - LC_ALL/LANG = C so the "no crontab for <user>" message is ENGLISH. The
    #    caller keys on that text to tell "empty crontab" from a real error; on a
    #    non-English system (e.g. LANG=de_DE) cronie/cron would otherwise print a
    #    translated message and an empty crontab would be misread as a failure.
    #  - a sane PATH so crontab is found even under a restrictive sudo secure_path.
    local $ENV{LC_ALL} = 'C';
    local $ENV{LANG}   = 'C';
    local $ENV{PATH}   = '/usr/bin:/bin:/usr/sbin:/sbin';

    # Resolve crontab to an absolute path where we can, so a minimal inherited
    # environment cannot hide it; fall back to a bare name (found via PATH above).
    my $crontab = 'crontab';
    for my $c (qw(/usr/bin/crontab /bin/crontab /usr/sbin/crontab)) {
        if (-x $c) { $crontab = $c; last; }
    }

    # Platform difference: AIX lists another user's crontab with
    # "crontab -l <user>"; Vixie/cronie (Linux: RHEL, SLES, Debian) and the BSDs
    # use "crontab -u <user> -l".
    my @cmd = ($^O eq 'aix')
        ? ($crontab, '-l', $cuser)
        : ($crontab, '-u', $cuser, '-l');

    # List-form open: fork/exec with no shell. The child's STDERR is inherited
    # (so "no crontab for <user>" and real errors reach the caller's stderr),
    # and we read its STDOUT. Output is capped so a pathological crontab cannot
    # stream without bound through the pipe.
    my $CAP = 262144;                                # 256 KiB is far more than any crontab
    my $pid = open(my $fh, '-|', @cmd);
    fail("cannot run crontab: $!") unless defined $pid;
    binmode($fh);
    binmode(STDOUT);
    my ($buf, $total) = ('', 0);
    while (sysread($fh, $buf, 65536)) {
        $total += length $buf;
        if ($total > $CAP) {
            # Emit up to the cap, then stop; the viewer only needs the
            # fetchconfig lines, which are near the top of any sane crontab.
            print STDOUT substr($buf, 0, length($buf) - ($total - $CAP));
            last;
        }
        print STDOUT $buf;
    }
    close($fh);                                      # sets $? from crontab's exit
    exit($? >> 8);                                   # forward crontab's status
}
else {
    print STDERR "$PROG: error: unknown or missing command"
        . ($cmd ne '' ? " '$cmd'" : '') . ".\n";
    print_help(\*STDERR);
    exit 2;
}
