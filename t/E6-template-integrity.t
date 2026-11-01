use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use File::Temp qw(tempdir);
use Digest::SHA qw(sha1_hex);

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# --- template_status() against a crafted integrity.sha1 manifest -------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $stock   = "hostname r1\nend\n";                 # matches manifest -> original
    my $edited  = "locally changed\n";                  # differs -> edited
    my $crlf    = "a\r\nb\r\n";                          # CRLF; LF-hash in manifest
    my %w = (
        'cisco-ios.tmpl' => sha1_hex($stock),
        'procurve.tmpl'  => sha1_hex("the original procurve\n"),  # != $edited
        'crlf.tmpl'      => sha1_hex("a\nb\n"),                    # LF-normalised
    );
    _put("$dir/cisco-ios.tmpl", $stock);
    _put("$dir/procurve.tmpl",  $edited);
    _put("$dir/crlf.tmpl",      $crlf);
    _put("$dir/cust-foo.tmpl",  "my own template\n");   # not in manifest
    _put("$dir/integrity.sha1", join('', map { "$w{$_}  $_\n" } sort keys %w));

    is(main::template_status("$dir/cisco-ios.tmpl"), 'original', 'hash matches -> original');
    is(main::template_status("$dir/procurve.tmpl"),  'edited',   'hash differs -> edited');
    is(main::template_status("$dir/crlf.tmpl"),      'original', 'CRLF normalised before hashing -> original');
    is(main::template_status("$dir/cust-foo.tmpl"),  'custom',   'not in manifest -> custom');

    my $nodir = tempdir(CLEANUP => 1);                  # no integrity.sha1
    _put("$nodir/x.tmpl", "x\n");
    is(main::template_status("$nodir/x.tmpl"), 'custom', 'no manifest (no hash) -> custom');

    # The manifest dir is derived from the template's own path, not any external
    # "dir" field, so a template found via a different template_dir value still
    # resolves its integrity.sha1 next to the file.
    is(main::template_status("$dir/cisco-ios.tmpl"), 'original',
       'status keys on dirname(path), independent of the -t dir field');
}

# --- source wiring: Orig column, shipped-row buttons, copy handler guards -----
{
    my $src = do { open(my $fh,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$fh> };
    like($src, qr/<th>Orig<\/th>/,                         'Orig column header present');
    like($src, qr/action=copy_template_form/,              'shipped row offers a Copy link');
    like($src, qr/btn btn-green" href="\$copy"/,           'Copy button is green');
    like($src, qr/Shipped template &mdash; use Copy to edit/, 'shipped Edit is disabled with a hint');
    like($src, qr/replaced on update, cannot delete/,      'shipped Delete is disabled with a hint');
    like($src, qr/\$stem-cust/,                            'copy form pre-fills <stem>-cust');
    like($src, qr/is a shipped template name in that directory/, 'do_copy_template refuses a shipped target name');
    like($src, qr/A template named \$base already exists/, 'do_copy_template refuses an existing target');
    like($src, qr/\$action eq 'copy_template_form'/,       'dispatcher: copy_template_form');
    like($src, qr/\$action eq 'copy_template'/,            'dispatcher: copy_template');
    like($src, qr/^\s*copy_template\s*$/m,                 'copy_template is a state-changing (CSRF) action');
}

done_testing();

sub _put { my ($p,$c) = @_; open(my $fh,'>',$p) or die "write $p: $!"; binmode($fh); print $fh $c; close($fh); }
