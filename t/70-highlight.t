use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# The safety invariant: stripping the <span> tags a highlighter adds must
# yield exactly esc() of the original -- i.e. highlighting only ADDS markup.
sub strip { my ($h)=@_; $h =~ s/<span class="hl-[a-z]+">//g; $h =~ s{</span>}{}g; return $h; }

my %sample = (
  'cisco-ios'   => "hostname r1\ninterface Gi0/1\n ip address 10.0.0.1 255.255.255.0\n!\nend\n",
  'procurve'    => "hostname SW\nvlan 1\n name DEFAULT\nexit\n",
  'comware-ssh' => "#\n sysname SW\n interface Vlan1\n#\nreturn\n",
  'zyxel'       => "! config\nhostname zx\nexit\n",
  'aruba-cx-ssh'=> "!\nhostname aru\ninterface 1/1/1\n ip address 10.0.0.1/24\n",
  'nexus-ssh'   => "hostname nx\nfeature lacp\nbanner motd ^\n  Hi ^\ninterface Ethernet1/1\n",
  'mediant-sbc' => "## Data\nconfigure data\n interface GigabitEthernet 0/0\n  ip address 10.0.0.1 255.255.255.0\n  activate\n exit\n",
);

for my $model (sort keys %sample) {
    my $content = $sample{$model};
    my $hl = main::highlight_config($model, $content);
    my $plain = join("\n", map { main::esc($_) } split /\n/, $content, -1);
    is(strip($hl), $plain, "highlight_config($model): strip(spans) == esc(original)");
}

# The template highlighter (Tools -> Template viewer) obeys the same invariant.
{
    my $tpl = "# a template\ntransport ssh telnet\nprompt_tail '#'\n"
            . "capture_from /^!/\nstate getconfig\n"
            . "  send \"show running-config\"\n"
            . "  expect prompt -> capture_stop -> done\n";
    my $hl = main::highlight_template($tpl);
    my $plain = join("\n", map { main::esc($_) } split /\n/, $tpl, -1);
    is(strip($hl), $plain, "highlight_template: strip(spans) == esc(original)");
}

# a model with no highlighter falls back to escaped text (no spans added)
my $none = main::highlight_config('fortigate', "config system\nend\n");
unlike($none, qr/<span class="hl-/, 'model without highlighter: no spans');

done_testing();
