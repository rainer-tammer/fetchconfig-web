use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# Regression: the compare/diff view must mask secrets that the normal config
# view masks. render_unified_diff() masks the config CONTENT, not the
# diff-marker-prefixed line, so ^-anchored rules (indented "key", SNMP
# community, radius/tacacs key) are not defeated by a leading -/+/</> marker.

my $hex = '5a4792db4ae0d40c55a13e0b17d6c4a4b7e6c4ba7d415ec8f755424ff30be799';

# Normal diff (fetchconfig.pl -m / `diff`): "<marker><space><content>".
{
    my $text = "148c148\n<  key $hex\n---\n>  key ${hex}aa\n";
    my $h = main::render_unified_diff($text);
    like($h,   qr/\*\*\*/,       'normal diff: indented key is masked');
    unlike($h, qr/\Q$hex\E/,     'normal diff: the hex key value is gone');
    like($h,   qr/&lt; /,        'normal diff: the < marker is preserved (escaped)');
    like($h,   qr/class="d-del"/,'normal diff: del colouring kept');
    like($h,   qr/class="d-add"/,'normal diff: add colouring kept');
}

# Unified style (build_unified_diff): "<marker><content>", no separator space.
{
    my $text = "- key $hex\n+ key ${hex}aa\n";
    my $h = main::render_unified_diff($text);
    unlike($h, qr/\Q$hex\E/, 'unified diff: the hex key value is gone');
}

# Other ^-anchored rules are also masked in the diff view.
{
    my $text = "< snmp-server community s3cr3tcomm RW\n"
             . "> radius-server host 1.2.3.4 key supersecretkey\n";
    my $h = main::render_unified_diff($text);
    unlike($h, qr/s3cr3tcomm/,    'diff: bare SNMP community masked');
    unlike($h, qr/supersecretkey/,'diff: radius-server key masked');
}

# The admin "compare configs" unmask=1 path still shows the real value.
{
    my $h = main::render_unified_diff("<  key $hex\n", 1);
    like($h, qr/\Q$hex\E/, 'unmask=1 shows the real value (admin compare)');
}

done_testing();
