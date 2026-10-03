use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config();
load_cgi($cfg);

no warnings 'redefine', 'once';
# Allow-list with two repos, two script dirs, two template dirs.
*main::read_allowed_dirs = sub { +{
    present => 1,
    repository => [{alias=>'$REPO1',path=>'/u/config'}, {alias=>'$REPO2',path=>'/u/config2'}],
    template   => [{alias=>'$TEMPLATE1',path=>'/u/tpl'}, {alias=>'$TEMPLATE2',path=>'/u/tpl2'}],
    report     => [],
    fetch_run  => [{alias=>'$SCRIPTS1',path=>'/u/s'}, {alias=>'$SCRIPTS2',path=>'/u/s2'}],
    fetch_run_configured => 1, fetch_run_disabled => 0,
}; };
my %P = ('$REPO1','/u/config','$REPO2','/u/config2','$SCRIPTS1','/u/s','$SCRIPTS2','/u/s2','$TEMPLATE1','/u/tpl','$TEMPLATE2','/u/tpl2');
*main::resolve_allowed_path = sub { $P{$_[1]} };
*main::alias_for_value = sub { $_[1] };
*main::expanded_path_for = sub { '/x' };
*main::template_default_dir = sub { '$TEMPLATE1' };

main::model_defaults_init([
    { kind=>'default', model=>'procurve-ssh', opts=>[['repository','$REPO1']] },
    { kind=>'default', model=>'generic',      opts=>[['on_fetch_run','$SCRIPTS1/run']] },
]);

my $shown = sub { $_[0] =~ /tag-default"(?! style="display:none)/ ? 1 : 0 };
my $colored = sub { my ($h,$a)=@_; $h =~ /<option value="\Q$a\E"[^>]*class="opt-default"/ ? 1 : 0 };

# repository matching the model default
my $h = main::render_option_field('r1','procurve-ssh','repository','$REPO1',0,'device','',1);
ok($shown->($h), 'repository == default: blue tag shown');
ok($colored->($h,'$REPO1'), 'repository default option coloured');

# repository not matching
$h = main::render_option_field('r1','procurve-ssh','repository','$REPO2',0,'device','',1);
ok(!$shown->($h), 'repository != default: tag hidden');

# on_fetch_run directory matching the model default (command part ignored)
$h = main::render_option_field('r1','generic','on_fetch_run','$SCRIPTS1/other',0,'device','',1);
ok($shown->($h), 'on_fetch_run dir == default: tag shown (command ignored)');

# template_dir generic matching
$h = main::render_option_field('r1','generic','template_dir','$TEMPLATE1',0,'device','',1);
ok($shown->($h), 'template_dir generic == default: tag shown');

# template_dir on a non-generic model: no default comparison
$h = main::render_option_field('r1','cisco-ios','template_dir','$TEMPLATE1',0,'device','',1);
ok(!$shown->($h), 'template_dir non-generic: no default tag');

# Defaults tab (section=default): never a default tag
$h = main::render_option_field('r1','procurve-ssh','repository','$REPO1',0,'default','',1);
ok(!$shown->($h), 'defaults tab: no default tag');

done_testing();
