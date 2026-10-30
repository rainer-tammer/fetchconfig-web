use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec;

# The Template viewer's state-machine diagram. The server builds the Mermaid
# "stateDiagram-v2" source from fetchconfig's own GenericTemplateParser (loaded
# by absolute path from FETCHCONFIG_PATH, never copied); the browser renders it
# with the self-hosted js/mermaid.min.js. These tests cover the ported gloss/
# diagram subs (tdiag_*) and the template_mermaid_source() branch logic, using a
# stub parser so the real module (shipped by fetchconfig) is not required.

# A stub GenericTemplateParser whose parse() varies by a marker in the text, so
# one module file drives every branch.
my $STUB = <<'PM';
package fetchconfig::model::GenericTemplateParser;
use strict; use warnings;
sub parse {
    my ($class, $text) = @_;
    return { errors => ['line 1: boom'], transports=>[], states=>[], state_by=>{} }
        if $text =~ /PARSEERR/;
    return { errors => [], transports=>[], states=>[], state_by=>{} }   # parses, nothing to draw
        if $text =~ /EMPTY/;
    return {
        errors => [], transports => ['ssh','telnet'],
        state_by => { state_login_ssh=>1, state_login_telnet=>1 },
        states => [
          { name=>'state_login_ssh', steps=>[
              { op=>'expect', pattern=>{kind=>'prompt'},
                action=>{op=>'send',kind=>'option',name=>'enable'},
                next_kind=>'goto', next=>'enable' } ]},
          { name=>'enable', steps=>[
              { op=>'capture_start' },
              { op=>'send_now', action=>{op=>'send',kind=>'literal',text=>'show run'},
                next_kind=>'stay' },
              { op=>'expect', pattern=>{kind=>'prompt'},
                action=>{op=>'capture_stop'}, next_kind=>'done' } ]},
        ],
    };
}
1;
PM

sub write_parser {
    my ($root) = @_;
    my $dir = File::Spec->catdir($root, 'fetchconfig', 'model');
    make_path($dir);
    my $f = File::Spec->catfile($dir, 'GenericTemplateParser.pm');
    open(my $fh, '>', $f) or die "write stub: $!";
    print $fh $STUB; close $fh;
}

# ---- tdiag_mermaid(): the ported port, on a hand-built structure ----------
{
    my ($cfg) = make_config(); load_cgi($cfg); main::read_config();
    my $t = { transports=>['ssh'], state_by=>{state_login_ssh=>1},
        states=>[ { name=>'state_login_ssh', steps=>[
            { op=>'expect', pattern=>{kind=>'regex', regex=>'login:'},
              action=>{op=>'send',kind=>'option',name=>'user'},
              next_kind=>'goto', next=>'pw' } ]},
        ] };
    my $m = join "\n", @{ main::tdiag_mermaid($t) };
    like($m, qr/^stateDiagram-v2/,                              'header line');
    like($m, qr/\[\*\] --> state_login_ssh: transport ssh/,    'entry edge for transport');
    like($m, qr/state_login_ssh --> pw: login, send user/,     'trigger + action edge label');

    # mm_label strips Mermaid metacharacters from labels.
    is(main::tdiag_mm_label('a "b" #c; {d}|e : f'), 'a b c de - f', 'mm_label sanitises');
}

# ---- template_mermaid_source(): success / parse_error / empty via stub -----
{
    my $root = tempdir(CLEANUP=>1);
    write_parser($root);
    my ($cfg) = make_config(FETCHCONFIG_PATH => $root);
    load_cgi($cfg); main::read_config();

    my ($src, $why) = main::template_mermaid_source("a real template");
    ok(defined $src && !defined $why,                  'success: source, no reason');
    like($src, qr/^stateDiagram-v2/,                   'success: stateDiagram-v2 header');
    like($src, qr/state_login_ssh --> enable: at prompt, send enable/, 'prompt+option edge');
    like($src, qr/enable --> enable: send show run/,   'send_now self (stay) edge');
    like($src, qr/enable --> \[\*\]: at prompt, capture_stop/, 'done edge -> [*]');

    my ($s2, $w2) = main::template_mermaid_source("has PARSEERR marker");
    ok(!defined $s2 && $w2 eq 'parse_error',           'parse_error when errors present');

    my ($s3, $w3) = main::template_mermaid_source("has EMPTY marker");
    ok(!defined $s3 && $w3 eq 'empty',                 'empty when no transitions');
}

# ---- no_parser when the module is absent ----------------------------------
{
    my $root = tempdir(CLEANUP=>1);   # deliberately no fetchconfig/model/... file
    my ($cfg) = make_config(FETCHCONFIG_PATH => $root);
    load_cgi($cfg); main::read_config();
    my ($src, $why) = main::template_mermaid_source("x");
    ok(!defined $src && $why eq 'no_parser',           'no_parser when module absent');
}

# ---- no_parser when FETCHCONFIG_PATH is empty -----------------------------
{
    my ($cfg) = make_config(FETCHCONFIG_PATH => '');
    # read_config may reject an empty required path; load directly and test the
    # guard regardless by pointing the module resolver at nothing.
    load_cgi($cfg); eval { main::read_config() };
    my $mod = main::template_diagram_module();
    ok(!defined $mod || !-f $mod, 'template_diagram_module undef/none without a real path');
}

# ---- source wiring: show_view_template emits the diagram section correctly --
{
    my $cgi = do {
        open(my $fh, '<', "$FindBin::Bin/../fetchconfig-web.cgi") or die $!;
        local $/; <$fh>;
    };
    like($cgi, qr/<pre class="mermaid">/,                        'emits a mermaid <pre>');
    like($cgi, qr{\$BASE_URL\$JS_BASE_URL/mermaid\.min\.js},     'loads mermaid.min.js from JS_BASE_URL');
    like($cgi, qr/IBMPlexSans-Regular\.woff2/,                   'references IBM Plex Sans webfont');
    like($cgi, qr/\@font-face/,                                  'scoped \@font-face present');
    like($cgi, qr/CGI::escapeHTML\(\$mm_src\)/,                  'diagram source is HTML-escaped');
    like($cgi, qr/diagram renderer is not /,                     'note branch: renderer missing');
    like($cgi, qr/IBM Plex Sans font is not installed/,          'note branch: font missing');
    like($cgi, qr/GenericTemplateParser.*was not found/s,        'note branch: parser missing');
    # The diagram must reuse the already-validated path (no re-derivation) and
    # only render when both the source and the on-disk renderer are present.
    like($cgi, qr/my \$can_render = \(defined \$mm_src && \$js_ok\)/, 'render gated on source AND js present');
}

done_testing();
