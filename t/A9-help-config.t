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
done_testing();
