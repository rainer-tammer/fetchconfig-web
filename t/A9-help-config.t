use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use File::Temp qw(tempdir);
use File::Path qw(make_path);

# --- help_doc_dir() / help_file_path() now resolve against WEB_DIR + HELP_BASE_URL ---

# The help tree is WEB_DIR + HELP_BASE_URL; help.html lives directly in it.
{
    my ($cfg) = make_config(WEB_DIR => '/opt/web', HELP_BASE_URL => '/help');
    load_cgi($cfg); main::read_config();
    is(main::help_doc_dir(),   '/opt/web/help',            'help_doc_dir() = WEB_DIR + HELP_BASE_URL');
    is(main::help_file_path(), '/opt/web/help/help.html',  'help.html sits in the help tree');
}
# HELP_BASE_URL defaults to /help when the config omits it.
{
    my ($cfg) = make_config(WEB_DIR => '/srv/docs', HELP_BASE_URL => undef);
    load_cgi($cfg); main::read_config();
    is(main::help_doc_dir(), '/srv/docs/help', 'HELP_BASE_URL defaults to /help');
}
# Trailing slashes on WEB_DIR and HELP_BASE_URL are trimmed.
{
    my ($cfg) = make_config(WEB_DIR => '/srv/docs/', HELP_BASE_URL => '/help/');
    load_cgi($cfg); main::read_config();
    is(main::help_file_path(), '/srv/docs/help/help.html', 'trailing slashes trimmed');
}
# A non-default HELP_BASE_URL is honoured.
{
    my ($cfg) = make_config(WEB_DIR => '/srv/docs', HELP_BASE_URL => '/documentation');
    load_cgi($cfg); main::read_config();
    is(main::help_doc_dir(), '/srv/docs/documentation', 'custom HELP_BASE_URL honoured');
}

# --- help_extract_title(): <title> -> menu label ---
{
    my ($cfg) = make_config(); load_cgi($cfg); main::read_config();
    my $dir = tempdir(CLEANUP => 1);
    _put("$dir/a.html",   "<html><head><title>  Hello   World  </title></head>");
    is(main::help_extract_title("$dir/a.html"), 'Hello World',
       'title read and whitespace collapsed');
    _put("$dir/ent.html", "<head><title>Backup &amp; Restore &lt;x&gt;</title>");
    is(main::help_extract_title("$dir/ent.html"), 'Backup & Restore <x>',
       'XML entities decoded to literal text (esc() re-encodes)');
    # Typographic named entity -> its UTF-8 bytes (en dash U+2013 = E2 80 93).
    _put("$dir/dash.html", "<head><title>fetchconfig-web &ndash; Install</title>");
    is(main::help_extract_title("$dir/dash.html"), "fetchconfig-web \xE2\x80\x93 Install",
       'typographic entity decoded to UTF-8 bytes');
    # Raw UTF-8 in the title passes through unchanged (the real-world case).
    _put("$dir/utf8.html", "<head><title>Modell hinzuf\xC3\xBCgen</title>");  # ü
    is(main::help_extract_title("$dir/utf8.html"), "Modell hinzuf\xC3\xBCgen",
       'raw UTF-8 passes through unchanged');
    _put("$dir/none.html", "<html><body>no title here</body></html>");
    is(main::help_extract_title("$dir/none.html"), undef, 'missing <title> => undef');
    is(main::help_extract_title("$dir/nope.html"), undef, 'unreadable file => undef');
}

# --- help_scan_dir(): ok / empty / toomany ---
{
    my ($cfg) = make_config(); load_cgi($cfg); main::read_config();
    my $root = main::help_doc_dir();   # WEB_DIR + HELP_BASE_URL (from make_config)

    make_path("$root/fetchconfig-web");
    _put("$root/fetchconfig-web/z.html", "<title>Zebra guide</title>");
    _put("$root/fetchconfig-web/a.html", "<title>Apple guide</title>");
    _put("$root/fetchconfig-web/readme.txt", "not html, ignored");
    my $s = main::help_scan_dir('fetchconfig-web');
    is($s->{state}, 'ok', 'populated dir => ok');
    is(scalar @{$s->{items}}, 2, 'only *.html counted');
    is_deeply([ map { $_->{label} } @{$s->{items}} ], ['Apple guide', 'Zebra guide'],
              'items sorted by label (case-insensitive)');

    make_path("$root/empty-sub");
    is(main::help_scan_dir('empty-sub')->{state}, 'empty', 'empty dir => empty');
    is(main::help_scan_dir('nope')->{state},      'empty', 'missing dir => empty');

    make_path("$root/big");
    _put("$root/big/f$_.html", "<title>doc $_</title>") for 1 .. (main::HELP_MAX_FILES() + 1);
    is(main::help_scan_dir('big')->{state}, 'toomany', '> HELP_MAX_FILES => toomany');
}

# --- Help menu markup: two scanned sections, About item, scan wiring ---
{
    my $src = do { open(my $f,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$f> };
    like($src, qr/\Qfetchconfig-web - additional help\E/, 'Help menu has the fetchconfig-web section');
    like($src, qr/\Qfetchconfig - additional help\E/,     'Help menu has the fetchconfig section');
    like($src, qr/class="fc-about-open"/,                 'Help menu About item wired to the dialog');
    like($src, qr/help_scan_dir\(/,                       'Help menu built by scanning the subdirs');
}

# --- every registered config key is documented in README.md ---
{
    my $root = "$FindBin::Bin/..";
    my $cgi  = do { open(my $f,'<',"$root/fetchconfig-web.cgi") or die $!; local $/; <$f> };
    my %reg; $reg{$1}=1 while $cgi =~ /^\s*\[ '([A-Z_]+)',/mg;
    my $readme = do { open(my $f,'<',"$root/README.md") or die $!; local $/; <$f> };
    my @undoc = grep { $readme !~ /\b\Q$_\E\b/ } sort keys %reg;
    is_deeply(\@undoc, [], 'every config key is documented in README.md')
        or diag("undocumented in README: @undoc");
}

sub _put { my ($p, $c) = @_; open(my $fh, '>', $p) or die "$p: $!"; binmode($fh); print $fh $c; close($fh); }

done_testing();
