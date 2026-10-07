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

# A model with no built-in highlighter now falls through to the template-backed
# scheme resolution (GENERIC_SYNTAX, a config value). The three new scheme
# highlighters (json, xml, generic) must all obey the strip invariant, and a
# forced scheme is reachable through GENERIC_SYNTAX.

# With GENERIC_SYNTAX = none, an unknown model gets no highlighting (undef).
{
    my ($c) = make_config(GENERIC_SYNTAX => 'none');
    load_cgi($c); main::read_config();
    my $r = main::highlight_config('fortigate', "config system\nend\n");
    ok(!defined $r, 'GENERIC_SYNTAX=none: no highlighting for unknown model');
}

# With GENERIC_SYNTAX = auto (default), an unknown model is highlighted, and
# the strip invariant holds. Content-detection picks a scheme.
{
    my ($c) = make_config(GENERIC_SYNTAX => 'auto');
    load_cgi($c); main::read_config();
    my %sample = (
        'generic' => "# comment\nhostname r1\nvalue \"x\" 10\n",
        'json'    => "{\n  \"name\": \"r1\",\n  \"n\": 5,\n  \"on\": true\n}\n",
        'xml'     => "<config>\n  <host name=\"r1\"/>\n  <!-- c -->\n</config>\n",
    );
    for my $want (sort keys %sample) {
        my $content = $sample{$want};
        is(main::detect_syntax_scheme($content), $want, "detect_syntax_scheme -> $want");
        my $hl = main::highlight_config('fortigate', $content);
        ok(defined $hl, "auto: $want content is highlighted");
        my $plain = join("\n", map { main::esc($_) } split /\n/, $content, -1);
        is(strip($hl), $plain, "$want via auto: strip(spans) == esc(original)");
    }
}

# A forced scheme name via GENERIC_SYNTAX is honoured.
{
    my ($c) = make_config(GENERIC_SYNTAX => 'cisco-ios');
    load_cgi($c); main::read_config();
    my $hl = main::highlight_config('fortigate', "! c\nhostname r1\n");
    ok(defined $hl && $hl =~ /hl-comment/, 'GENERIC_SYNTAX=cisco-ios forces that scheme');
}

# Three-layer resolution: a template's syntax_style (layer 1) wins over the
# GENERIC_SYNTAX config and content detection.
{
    my ($c) = make_config(GENERIC_SYNTAX => 'auto');
    load_cgi($c); main::read_config();
    no warnings 'redefine', 'once';
    my $tmp = "/tmp/fcw-tmpl-$$.tmpl";
    open(my $f, '>', $tmp) or die; print $f "x\n"; close $f;
    local *main::device_template_path = sub { $tmp };
    local *main::run_fetchconfig = sub { ('cisco-ios', '', 0, undef) };
    # Content looks like JSON, but the template declares cisco-ios -> layer 1 wins.
    my $scheme = main::resolve_syntax_scheme('generic', '{"a":1}', 'dev1');
    is($scheme, 'cisco-ios', 'layer 1: template syntax_style overrides content');
    # fetchconfig says nothing -> fall through to content detection.
    local *main::run_fetchconfig = sub { ('', '', 1, undef) };
    main::_syntax_cache_reset();
    my $scheme2 = main::resolve_syntax_scheme('generic', '{"a":1}', 'dev1');
    is($scheme2, 'json', 'layer 3: content detection when no syntax_style');
    unlink $tmp;
}

# The generic highlighter must leave certificate hex dumps plain (no spans),
# like cisco-ios does -- the hex groups must never be tokenised.
{
    my $cert = "crypto pki certificate chain X\n certificate ca 01\n"
             . "  30820321 CBB4C798 212AA147\n  C7479096 B4CB2D62\n        quit\n!\n";
    my $hl = main::highlight_generic($cert);
    for my $line (split /\n/, $hl) {
        next unless $line =~ /30820321|CBB4C798|C7479096/;
        unlike($line, qr/<span/, 'generic: certificate hex line is not tokenised');
    }
    my $plain = join("\n", map { main::esc($_) } split /\n/, $cert, -1);
    is(strip($hl), $plain, 'generic with cert: strip(spans) == esc(original)');
}

# Auto-detect classifies an IOS config with crypto pki / certificate as
# cisco-ios (whose highlighter also leaves cert hex plain), not generic.
is(main::detect_syntax_scheme("!\ncrypto pki certificate chain X\n certificate ca 01\n"),
   'cisco-ios', 'detect: crypto pki / certificate -> cisco-ios');

# highlight_config reports the chosen scheme via the out-param.
{
    my ($c) = make_config(GENERIC_SYNTAX => 'auto');
    load_cgi($c); main::read_config();
    my $sch;
    main::highlight_config('cisco-ios', "hostname r1\n", undef, \$sch);
    is($sch, 'cisco-ios', 'out-param: direct model reports its scheme');
    my $sch2;
    main::highlight_config('fortigate', '{"a":1}', undef, \$sch2);
    is($sch2, 'json', 'out-param: auto-detect reports the resolved scheme');
}

# device_template_path expands a $alias template_dir (directory: allow-list).
{
    my ($c) = make_config(); load_cgi($c); main::read_config();
    no warnings 'redefine', 'once';
    local *main::resolve_dir_alias = sub { my ($k,$v)=@_; $v =~ s{^\$TPL}{/real/tpl}; $v };
    local *main::slurp_device_table = sub {
        ("default: generic template_dir=\$TPL\ngeneric d1 10.0.0.1 model=cisco\n", undef);
    };
    my $p2 = main::device_template_path('d1');
    is($p2, '/real/tpl/cisco.tmpl', 'device_template_path expands the $alias');
}

# Model 'generic' must NOT short-circuit to the generic highlighter; it goes
# through the resolution chain, so a template declaring cisco-ios wins.
{
    my ($c) = make_config(); load_cgi($c); main::read_config();
    no warnings 'redefine', 'once';
    my $f = "/tmp/fcw-hl-$$.tmpl"; open(my $t,'>',$f) or die; print $t "x"; close $t;
    local *main::resolve_dir_alias   = sub { $_[1] };
    local *main::device_template_path = sub { $f };
    local *main::run_fetchconfig     = sub { ('cisco-ios','',0,undef) };
    main::_syntax_cache_reset();
    my $sch;
    main::highlight_config('generic', "!\ncrypto pki\n", 'd1', \$sch);
    is($sch, 'cisco-ios', "model 'generic' routes through chain to the template's scheme");
    unlink $f;
}

done_testing();
