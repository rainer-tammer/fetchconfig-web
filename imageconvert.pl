#!/usr/bin/perl
#
# imageconvert.pl -- encode an image file as a base64 blob for embedding in
# fetchconfig-web.cgi (or any Perl source).
#
# Copyright (C) 2026 Rainer Tammer
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;
use MIME::Base64 qw(encode_base64);

my $PROG = 'imageconvert.pl';
my $VERSION = '1.0';
my $LINE_WIDTH = 80;      # width of the base64 block

# ---------------------------------------------------------------------------
sub usage {
    my ($fh) = @_;
    $fh ||= \*STDOUT;
    print $fh <<"USAGE";
$PROG $VERSION -- encode an image as a base64 blob for embedding in Perl.

USAGE:
    $PROG <input-image> <output-file> <var-name>

ARGUMENTS:
    input-image   Path to the image (or any binary file) to encode.
    output-file   File to write the generated Perl snippet to. Use '-' to
                  write to standard output instead.
    var-name      The Perl scalar variable name for the blob, e.g. LOGO_BASE64
                  (a leading '\$' is accepted and ignored). Must be a valid
                  Perl identifier.

OUTPUT:
    A ready-to-paste Perl snippet of the form:

        my \$VAR_NAME = do {
            local \$/;
            my \$raw = <<'B64';
        <base64, wrapped at $LINE_WIDTH characters>
        B64
            \$raw =~ s/\\s+//g;
            \$raw;
        };

    Paste it into your Perl source; \$VAR_NAME then holds the image bytes
    as a single base64 string (whitespace stripped).

OPTIONS:
    -h, --help       Show this help and exit.
    -V, --version    Show version and exit.

EXAMPLES:
    $PROG logo.png logo-b64.pl LOGO_BASE64
    $PROG back.jpg - IMAGE_BASE64 > back-b64.pl

Copyright (C) 2026 Rainer Tammer. GNU GPL v3 or later.
USAGE
    return;
}

sub fail {
    my ($msg) = @_;
    print STDERR "$PROG: error: $msg\n";
    print STDERR "$PROG: try '$PROG --help' for usage.\n";
    exit 2;
}

# ---------------------------------------------------------------------------
# Option handling (help / version) before positional-argument checking.
for my $a (@ARGV) {
    if ($a eq '-h' || $a eq '--help')    { usage(\*STDOUT); exit 0; }
    if ($a eq '-V' || $a eq '--version') { print "$PROG $VERSION\n"; exit 0; }
}

if (@ARGV == 0) {
    usage(\*STDERR);
    exit 1;
}
if (@ARGV != 3) {
    fail('exactly three arguments are required: '
       . '<input-image> <output-file> <var-name> (got ' . scalar(@ARGV) . ').');
}

my ($infile, $outfile, $varname) = @ARGV;

# --- validate the variable name --------------------------------------------
(my $clean_var = $varname) =~ s/^\$//;        # tolerate a leading '$'
if ($clean_var eq '') {
    fail("the variable name is empty.");
}
if ($clean_var !~ /^[A-Za-z_]\w*$/) {
    fail("'$varname' is not a valid Perl variable name "
       . "(use letters, digits and underscore; must not start with a digit).");
}

# --- validate the input file -----------------------------------------------
if (!-e $infile) {
    fail("input file '$infile' does not exist.");
}
if (-d $infile) {
    fail("input file '$infile' is a directory, not a file.");
}
if (!-r $infile) {
    fail("input file '$infile' is not readable (check permissions).");
}
if (-z $infile) {
    fail("input file '$infile' is empty (0 bytes).");
}

# --- read the input in binary ----------------------------------------------
my $data;
{
    open(my $in, '<', $infile)
        or fail("cannot open input file '$infile': $!");
    binmode($in)
        or fail("cannot set binary mode on '$infile': $!");
    local $/;
    $data = <$in>;
    close($in);
}
if (!defined $data || length($data) == 0) {
    fail("read no data from '$infile'.");
}
my $bytes = length($data);

# --- encode ----------------------------------------------------------------
# encode_base64($data, "") -> one long line, no line breaks; we wrap it
# ourselves to exactly $LINE_WIDTH characters.
my $b64 = encode_base64($data, "");
$b64 =~ s/\s+//g;                              # be safe: no stray whitespace
my $wrapped = '';
for (my $i = 0; $i < length($b64); $i += $LINE_WIDTH) {
    $wrapped .= substr($b64, $i, $LINE_WIDTH) . "\n";
}

# --- build the Perl snippet ------------------------------------------------
my $snippet = "my \$$clean_var = do {\n"
            . "    local \$/;\n"
            . "    my \$raw = <<'B64';\n"
            . $wrapped
            . "B64\n"
            . "    \$raw =~ s/\\s+//g;\n"
            . "    \$raw;\n"
            . "};\n";

# --- write the output ------------------------------------------------------
if ($outfile eq '-') {
    print $snippet
        or fail("cannot write to standard output: $!");
} else {
    if (-d $outfile) {
        fail("output path '$outfile' is a directory, not a file.");
    }
    open(my $out, '>', $outfile)
        or fail("cannot open output file '$outfile' for writing: $!");
    print $out $snippet
        or fail("cannot write to output file '$outfile': $!");
    close($out)
        or fail("cannot close output file '$outfile': $!");
    my $lines = ($wrapped =~ tr/\n//);
    print STDERR "$PROG: wrote \$$clean_var to '$outfile' "
               . "($bytes bytes -> " . length($b64) . " base64 chars, "
               . "$lines lines of $LINE_WIDTH).\n";
}

exit 0;
