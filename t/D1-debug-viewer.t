use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source state_changing_actions);

# Device debug log viewer (2.08).
#
# Covers the three things that can silently go wrong:
#   1. the positional hex parse (the only fragile part of the parser),
#   2. the newline-inside-the-span contract the direction filter depends on,
#   3. the authorization/path guards on the delete path.

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# ---------------------------------------------------------------------------
# A real Net::Telnet dump_log fragment. Built from BYTES, not from a literal:
# the ASCII gutter is Latin-1, and a UTF-8 source file would silently change
# what is under test.
# ---------------------------------------------------------------------------
sub dumpline {
    my ($dir, @bytes) = @_;
    my $hex = '';
    for my $i (0 .. 15) {
        $hex .= $i < @bytes ? sprintf('%02x ', $bytes[$i]) : '   ';
        $hex .= ' ' if $i % 4 == 3;
    }
    my $gut = join '', map { ($_ >= 0x20) ? chr($_) : '.' } @bytes;
    return sprintf('%s 0x%05x: %s%s', $dir, 0, $hex, $gut);
}

my @lines = (
    'debug1: multiplexing control connection',
    '# switch session (Net::Telnet dump_log)',
    dumpline('<', 0xff, 0xfd, 0x18, 0xff, 0xfd, 0x20),
    dumpline('>', 0xff, 0xfc, 0x18),
    dumpline('<', 0x0d, 0x0a, 0x00, map { ord } split //, 'Username: '),
    dumpline('>', ord('a')),
    dumpline('>', ord('d')),
    '# [secret sent - not logged]',
    dumpline('<', (0x2a) x 5, 0x0d, 0x0a, 0x00),
);
my $log = join("\n", @lines) . "\n";

my $h = main::highlight_debug_log($log);

# --- 1. the positional parse ------------------------------------------------
like($h, qr{<span class="dbg-off">&lt; 0x00000:</span>},
     'direction glyph and offset kept verbatim in the text');
like($h, qr{<span class="dbg-gut">\.\.\.Username: </span>},
     'ASCII gutter sliced at exactly 16*3+4 chars past the offset');
like($h, qr{<span class="dbg-gut">a</span>},
     'single-byte line slices correctly despite the space padding');

# A six-digit offset (a log past 1 MB) must not shift the field boundaries:
# the hex field is taken relative to the offset match, never from column 11.
{
    my $wide = '< 0x100000: ' . ('41 ' x 4) . ' ' . (' ' x 39) . 'AAAA';
    my $wh   = main::highlight_debug_log($wide);
    like($wh, qr{<span class="dbg-gut">AAAA</span>},
         'a six-digit offset does not break the gutter boundary');
}

# Anything that is not a dump line must not be parsed as one.
for my $not ('hostname GS-4210', '<not a dump line>', '> 0xZZ: 41', '') {
    is(main::_dbg_hex_line($not), undef, "not a dump line: '$not'");
}

# --- 2. direction, turns and the filter contract ----------------------------
like($h, qr{class="dbg-l dbg-rx"},  '"<" is classed as received');
like($h, qr{class="dbg-l dbg-tx},   '">" is classed as sent');
like($h, qr{dbg-turn},              'a direction change is marked');
unlike($h, qr{class="dbg-l dbg-rx dbg-turn">\s*<span class="dbg-off">&lt; 0x00000:</span>[^\n]*\n<span class="dbg-l dbg-rx dbg-turn"},
       'consecutive same-direction lines are not both marked as turns');

# THE contract: every newline is inside a line span, so the CSS filter can
# hide whole lines with display:none without leaving blank rows behind.
unlike($h, qr{\n(?!</span>)}, 'every newline sits inside a line span');
is(scalar(() = $h =~ /\n/g), scalar(@lines), 'one newline per input line, no more');

# The <,> glyphs stay in the DOM text: SEND/RECV are ::before content, which
# is not part of textContent, so the Copy button still returns the file.
unlike($h, qr{>SEND<|>RECV<}, 'SEND/RECV are not written into the markup');
like(css_source(), qr{\.dbg-tx::before\s*\{\s*content:\s*"SEND "},
     'SEND badge is CSS generated content');
like(css_source(), qr{\.dbg-rx::before\s*\{\s*content:\s*"RECV "},
     'RECV badge is CSS generated content');
like(css_source(), qr{pre\.config\.only-tx \.dbg-rx, pre\.config\.only-rx \.dbg-tx \{ display: none},
     'the direction filter rule exists');

# --- 3. markers and protocol bytes -----------------------------------------
like($h, qr{class="dbg-l dbg-sec"}, 'the secret marker gets its own class');
like($h, qr{class="dbg-l dbg-hdr"}, 'the session header is a header');
like($h, qr{class="dbg-l dbg-ssh"}, 'ssh stderr is de-emphasised');
like($h, qr{<span class="dbg-tag">debug1:</span>}, 'the ssh level tag is picked out');
like($h, qr{<span class="dbg-iac">ff</span>},      'telnet IAC bytes are picked out');
like($h, qr{<span class="dbg-ctl">0d</span>},      'CR/LF/NUL padding is dimmed');
# The IAC/control pass must not corrupt the fixed-width hex field.
{
    my ($hexfield) = $h =~ m{<span class="dbg-hex">(.*?)</span><span class="dbg-gut">a</span>};
    my $plain = $hexfield; $plain =~ s/<[^>]*>//g;
    is(length($plain), 16 * 3 + 4, 'hex field keeps its 52-char width after tokenising');
}

# --- 3b. CRLF line endings ---------------------------------------------------
# A real .debug file is CRLF: fetchconfig's ssh client writes its stderr
# through a pty and ONLCR rewrites every \n. Left in place, the \r lands inside
# the gutter span, where it sits before a TAG rather than before our \n -- so
# the HTML parser treats it as a line break of its own and every hex line
# renders as two, the second empty. That is what made the direction filter look
# like it was only "hiding" lines.
{
    my $crlf = $log; $crlf =~ s/\n/\r\n/g;
    my $hc = main::highlight_debug_log($crlf);
    is($hc, $h, 'a CRLF log renders byte-identically to the same log with LF');
    unlike($hc, qr/\r/, 'no carriage return reaches the markup');

    my $tc = main::debug_log_transcript($crlf);
    is($tc, main::debug_log_transcript($log), 'transcript is CRLF-insensitive too');
    unlike($tc, qr/\r/, 'no carriage return in the transcript');
}

# --- 3c. the blank line Net::Telnet writes after each dump block -------------
# It has no direction of its own. Untagged it survives the filter, leaving one
# blank row per hidden block -- on a device that trickles its output that is
# most of the page.
{
    my $blocks = join("\n", dumpline('>', ord('a')), '',
                            dumpline('<', ord('b')), '',
                            dumpline('<', ord('c')), '') . "\n";
    my $hb = main::highlight_debug_log($blocks);

    my @blank = $hb =~ /<span class="dbg-l ([^"]*dbg-blank[^"]*)">/g;
    is(scalar @blank, 3, 'every block separator is tagged');
    is(scalar(grep { /dbg-tx/ } @blank), 1, '... the one after the SEND block as sent');
    is(scalar(grep { /dbg-rx/ } @blank), 2, '... the ones after RECV blocks as received');
    unlike($hb, qr{<span class="dbg-l">\s*\n</span>},
           'no untagged blank line is left to survive the filter');

    # ... and it must stay transparent to turn detection, or no turn is ever
    # seen: in a real log every hex line is preceded by one of these.
    like($hb, qr/dbg-turn/, 'a turn is still detected across a block separator');

    # The separator must not get the SEND/RECV badge or the tint: it is an
    # empty line, and a labelled, tinted empty band looks like a bug.
    like(css_source(), qr{\.dbg-blank::before \{ content: none; \}},
         'the separator carries no badge');
    like(css_source(), qr{\.dbg-blank \{ background: none; \}},
         'the separator carries no tint');
}

# --- 3d. ssh client chatter is classified by COMPLEMENT ---------------------
# A .debug file can hold exactly three things (fetchconfig Abstract.pm):
#   * five "# ..." markers,
#   * Net::Telnet dump_log hex lines -- the ONLY carrier of device bytes,
#     since input_log is never attached, and
#   * the ssh client's stderr (master_stderr_fh => $debug_fh).
# So "ssh output" is defined as the complement of the first two, never by
# matching ssh's own wording -- which changes with the OpenSSH version, the
# log level and the locale. The invariant worth protecting: hiding .dbg-ssh
# can never hide a byte of the session.
{
    my @ssh = (
        'debug1: Entering interactive session.',
        'debug3: receive packet: type 80',
        'Warning: Permanently added \'swisit01\' (RSA) to the list of known hosts.',
        'Authenticated to swisit01.net.schuler.de ([10.195.0.101]:22).',
        'Transferred: sent 2376, received 137384 bytes, in 6.4 seconds',
        'Bytes per second: sent 371.7, received 21491.2',
        'OpenSSH_9.6p1, OpenSSL 3.0.13',
        'Verbindung zu swisit01 geschlossen.',      # a localised line
        'something nobody predicted',
    );
    my @markers = (
        '# ssh master connection to swisit01 (LogLevel=DEBUG, i.e. ssh -v)',
        '# telnet session to swisit01 (dump_log; passwords masked)',
        '# switch session (Net::Telnet dump_log)',
        '# could not connect: timeout',
        '# [secret sent - not logged]',
    );

    for my $l (@ssh) {
        my $o = main::highlight_debug_log($l);
        like($o, qr/class="dbg-l dbg-ssh"/, "ssh output classified: $l");
    }
    for my $l (@markers) {
        my $o = main::highlight_debug_log($l);
        unlike($o, qr/dbg-ssh/, "marker is NOT ssh output: $l");
    }
    # The one that must never be hidden by a display toggle.
    like(main::highlight_debug_log($markers[4]), qr/dbg-sec/,
         'the secret marker keeps its own class, outside dbg-ssh');

    # THE invariant: no hex line is ever classed as ssh output.
    my $mixed = join("\n", @ssh, @markers,
                     dumpline('<', 0x41), dumpline('>', 0x42)) . "\n";
    my $hm = main::highlight_debug_log($mixed);
    for my $line (split /\n/, $hm) {
        next unless $line =~ /dbg-ssh/;
        unlike($line, qr/dbg-tx|dbg-rx/,
               'a line is never both ssh output and device traffic');
        unlike($line, qr/dbg-off|dbg-gut/, '... and carries no hex-dump parts');
    }

    like(css_source(), qr{pre\.config\.no-ssh \.dbg-ssh \{ display: none},
         'the ssh filter rule exists');
}

# --- 4. Latin-1 gutter is widened to UTF-8 ---------------------------------
{
    my $l1 = main::highlight_debug_log(dumpline('<', 0xff, 0xfc));
    like($l1, qr/\xc3\xbf\xc3\xbc/,
         '0xff 0xfc in the gutter are emitted as UTF-8, not raw Latin-1');
    unlike($l1, qr/<span class="dbg-gut">\xff/,
           'raw high bytes do not reach the page');
}

# --- 5. transcript view -----------------------------------------------------
{
    my $t = main::debug_log_transcript($log);
    like($t,   qr/Username: /,  'transcript carries the prompt text');
    like($t,   qr{>ad</span>},  'per-character sends are reassembled into one line');
    # ssh chatter is CARRIED with the dbg-ssh class, not dropped, so the one
    # Show/Hide control governs the hex and transcript views alike. It is
    # hidden by default, so the view looks the same as when it was dropped.
    like($t,   qr/class="dbg-l dbg-ssh"/, 'ssh chatter is classed, not dropped');
    unlike($t, qr/0x00000/,     'offsets are dropped');
    unlike($t, qr/\xff/,        'telnet IAC negotiation is dropped');
    like($t,   qr/secret sent - not logged/, 'the secret marker survives');
    unlike($t, qr{\n(?!</span>)}, 'transcript keeps the newline-inside-span contract');
}

# --- 6. the delete path is POST + CSRF -------------------------------------
{
    my $sc = state_changing_actions();
    ok($sc->{delete_debug},     'delete_debug is state-changing (POST + CSRF)');
    ok($sc->{delete_all_debug}, 'delete_all_debug is state-changing (POST + CSRF)');
    ok(!$sc->{view_debug},      'view_debug is a read-only GET');
}

# --- 7. source-level guards -------------------------------------------------
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);

    # Every handler carries its own authorization: main() has no central gate.
    for my $sub (qw(show_debug_log do_delete_debug do_delete_all_debug show_tool_debug)) {
        my ($body) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        ok(defined $body, "$sub is present");
        like($body, qr/user_may_use_tools\(\$user\)/, "$sub checks the admin right itself");
    }
    # The two single-device handlers additionally re-check device scope.
    for my $sub (qw(show_debug_log do_delete_debug)) {
        my ($body) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        like($body, qr/valid_id\(\$dev\)/,                "$sub validates the device id");
        like($body, qr/device_accessible\(\$user, \$dev\)/, "$sub re-checks device scope");
    }

    # The path is derived from the device table, never taken from the request.
    my ($del) = $src =~ /\nsub do_delete_debug \{(.*?)\n\}\n/s;
    like($del,   qr/device_debug_file\(\$dev\)/, 'delete derives the path from the device id');
    unlike($del, qr/param\(\s*['"](?:path|file|repo|repository|dir)['"]/,
           'delete accepts no path-like parameter');
    like($del,   qr/lstat\(\$path\)/,  'delete lstats (does not follow a symlink)');
    like($del,   qr/-f _/,             'delete requires a plain file');

    # do_delete_debug redirects to 'status' or 'tool_debug'; BOTH must render
    # the flash message, or a delete from the status page is silent.
    like($del, qr/\$back = .*'status'.*:\s*'tool_debug'/s,
         'delete returns to the page it was invoked from');
    for my $page (qw(show_status_page show_tool_debug)) {
        my ($body) = $src =~ /\nsub \Q$page\E \{(.*?)\n\}\n/s;
        like($body, qr/param\('msg'\)/, "$page renders a flash message");
        like($body, qr/param\('err'\)/, "$page renders a flash error");
    }

    # The ssh log is hidden by DEFAULT, and the JS default state must agree
    # with which button is rendered as pressed -- otherwise the first click
    # does nothing visible.
    my ($vw) = $src =~ /\nsub show_debug_log \{(.*?)\n\}\n/s;
    like($vw, qr/\$cls \.= ' no-ssh'/, 'the viewer starts with the ssh log hidden');
    like($vw, qr/data-ssh="hide">SSH log hidden<\/button>/, 'the Hidden button is rendered');
    like($vw, qr/class="seg-btn on" data-ssh="hide"/, '... and is the pressed one');
    my ($js) = $src =~ /\nsub debug_filter_script \{(.*?)\n\}\n/s;
    like($js, qr/state = \{ dir: 'both', ssh: 'hide' \}/,
         'the script default matches the pressed buttons');

    # No raw errno in a rendered page (t/B6 enforces this globally; keep the
    # new code honest about it too).
    my ($view) = $src =~ /\nsub show_debug_log \{(.*?)\n\}\n/s;
    unlike($view, qr/esc\("\$!"\)/, 'viewer does not render errno');
    like($view,   qr/audit\(action => 'view_debug'/, 'viewing a debug log is audited');
    like($del,    qr/audit\(action => 'delete_debug'/, 'deleting a debug log is audited');

    # device_debug_file refuses anything not in the device table.
    my ($ddf) = $src =~ /\nsub device_debug_file \{(.*?)\n\}\n/s;
    like($ddf, qr/return undef unless valid_id\(\$dev\)/, 'device_debug_file validates the id');
    like($ddf, qr/resolve_dir_alias\('repository'/,       'device_debug_file resolves $aliases');
    like($ddf, qr/return undef;\s*#\s*device id is not in the device table/,
         'device_debug_file refuses an unknown device');
}

# --- 8. registered like every other highlighter -----------------------------
# %SYNTAX_HIGHLIGHTERS is a file-scoped lexical, so the registration is tested
# through its real entry point rather than by poking at the hash.
{
    my $scheme;
    my $via = main::highlight_config('__debug__', $log, undef, \$scheme);
    ok(defined $via, 'highlight_config dispatches the __debug__ pseudo-model');
    is($scheme, '__debug__', '... and reports it as the scheme');
    is($via, $h, '... to highlight_debug_log itself');
    ok(!grep({ $_ eq '__debug__' } main::template_syntax_schemes()),
       '... but it is not offered as a user-selectable template scheme');
}

done_testing();
