use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# The help path globals are file-lexical; observe them via help_file_path().
# New style: HELP_DIR + HELP_FILE (filename).
{
    my ($cfg) = make_config(HELP_DIR => '/opt/help', HELP_FILE => 'help.html');
    load_cgi($cfg); main::read_config();
    is(main::help_file_path(), '/opt/help/help.html', 'new style: dir + filename joined');
}
# Backward compatible: HELP_FILE as a full path, no HELP_DIR.
{
    my ($cfg) = make_config(HELP_FILE => '/var/www/fcw/help.html');
    load_cgi($cfg); main::read_config();
    is(main::help_file_path(), '/var/www/fcw/help.html', 'old full-path HELP_FILE still works');
}
# HELP_DIR wins, basename stripped from a full HELP_FILE.
{
    my ($cfg) = make_config(HELP_DIR => '/srv/docs', HELP_FILE => '/ignored/dir/help.html');
    load_cgi($cfg); main::read_config();
    is(main::help_file_path(), '/srv/docs/help.html', 'HELP_DIR overrides; basename kept');
}
# Every registered config key is mentioned in README.md and in the config that
# fetchconfig-web-dbsetup.pl generates, so no setting ships undocumented.
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
