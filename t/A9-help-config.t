use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# help.html now lives at WEB_DIR/help.html (fixed filename); help_file_path()
# builds that on-disk path for the presence check and the fallback reader.
{
    my ($cfg) = make_config(WEB_DIR => '/opt/help');
    load_cgi($cfg); main::read_config();
    is(main::help_file_path(), '/opt/help/help.html', 'WEB_DIR + help.html joined');
}
# A trailing slash on WEB_DIR is trimmed.
{
    my ($cfg) = make_config(WEB_DIR => '/srv/docs/');
    load_cgi($cfg); main::read_config();
    is(main::help_file_path(), '/srv/docs/help.html', 'trailing slash on WEB_DIR trimmed');
}
# help_doc_dir() is WEB_DIR (the directory the Help-menu docs are checked in).
{
    my ($cfg) = make_config(WEB_DIR => '/srv/docs');
    load_cgi($cfg); main::read_config();
    is(main::help_doc_dir(), '/srv/docs', 'help_doc_dir() is WEB_DIR');
}
# Every registered config key is mentioned in README.md, so no setting ships
# undocumented.
{
    my $root = "$FindBin::Bin/..";
    my $cgi  = do { open(my $f,'<',"$root/fetchconfig-web.cgi") or die $!; local $/; <$f> };
    my %reg; $reg{$1}=1 while $cgi =~ /^\s*\[ '([A-Z_]+)',/mg;
    my $readme = do { open(my $f,'<',"$root/README.md") or die $!; local $/; <$f> };
    my @undoc = grep { $readme !~ /\b\Q$_\E\b/ } sort keys %reg;
    is_deeply(\@undoc, [], 'every config key is documented in README.md')
        or diag("undocumented in README: @undoc");
}

done_testing();
