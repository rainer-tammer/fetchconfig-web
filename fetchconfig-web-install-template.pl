#!/usr/bin/perl
#
# fetchconfig-web-install-template.pl -- privileged helper that installs an
# edited fetchconfig template file, used by fetchconfig-web when the web-server
# user cannot write the template directories itself.
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

my $PROG = 'fetchconfig-web-install-template.pl';

sub fail { print STDERR "$PROG: error: $_[0]\n"; exit 2; }

sub check_target {
    my ($t) = @_;
    fail("target path is empty")                 if !defined $t || $t eq '';
    fail("target must be an absolute path: $t")  unless $t =~ m{^/};
    fail("target must not contain '..': $t")     if $t =~ m{(?:^|/)\.\.(?:/|$)};
    fail("target must end in .tmpl: $t")         unless $t =~ /\.tmpl$/;
    return $t;
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

my $cmd = shift @ARGV;
$cmd = '' unless defined $cmd;

if ($cmd eq 'install') {
    my ($src, $target) = @ARGV;
    fail("usage: $PROG install <srcfile> <target.tmpl>") unless defined $src && defined $target;
    fail("source file does not exist: $src")  unless -e $src;
    fail("source is not a plain file: $src")  unless -f $src;
    fail("source is not readable: $src")      unless -r $src;
    check_target($target);
    # Back up the existing target to <target>.bak (single, overwritten).
    if (-e $target) {
        atomic_copy($target, "$target.bak");
    }
    atomic_copy($src, $target);
    print "$PROG: installed $target (backup: $target.bak)\n";
    exit 0;
}
elsif ($cmd eq 'revert') {
    my ($target) = @ARGV;
    fail("usage: $PROG revert <target.tmpl>") unless defined $target;
    check_target($target);
    my $bak = "$target.bak";
    fail("no backup to revert from: $bak")   unless -e $bak;
    fail("backup is not readable: $bak")     unless -r $bak;
    atomic_copy($bak, $target);
    print "$PROG: reverted $target from $bak\n";
    exit 0;
}
else {
    print STDERR "$PROG: usage:\n"
        . "  $PROG install <srcfile> <target.tmpl>\n"
        . "  $PROG revert  <target.tmpl>\n";
    exit 2;
}
