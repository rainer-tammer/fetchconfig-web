use strict; use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source state_changing_actions);

# read_debug, the viewer size bands, and the per-page permission matrix (2.08).

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();

# ---------------------------------------------------------------------------
# 1. read_debug is admin OR the explicit flag -- NEVER implied by being
#    site-unrestricted.
#
# Its three siblings all start with "return 1 if user_is_unrestricted(...)",
# and user_is_unrestricted() means "not limited to any site", not "admin". If
# this right picked up that line, every non-admin account without a site
# restriction would silently gain access to device credentials.
# ---------------------------------------------------------------------------
{
    my %ROW;
    no warnings qw(redefine once);
    local *main::db_get_user          = sub { $ROW{$_[1]} };
    local *main::user_is_admin        = sub { $ROW{$_[1]} && $ROW{$_[1]}{admin_function} ? 1 : 0 };
    local *main::user_is_unrestricted = sub { 1 };   # the trap: no site limits

    %ROW = (
        boss  => { username=>'boss',  admin_function=>1, read_debug=>0 },
        opr   => { username=>'opr',   admin_function=>0, read_debug=>1 },
        plain => { username=>'plain', admin_function=>0, read_debug=>0 },
    );
    my $dbh = bless {}, 'FakeDbh';
    is(main::user_may_read_debug($dbh, 'boss'),  1, 'an administrator may read debug logs');
    is(main::user_may_read_debug($dbh, 'opr'),   1, 'an explicit read_debug holder may');
    is(main::user_may_read_debug($dbh, 'plain'), 0,
       'a site-unrestricted user WITHOUT the flag may NOT -- not implied by unrestricted');
}

# The deviation has to stay deliberate, so the source must not acquire the
# sibling shortcut.
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    my ($body) = $src =~ /\nsub user_may_read_debug \{(.*?)\n\}\n/s;
    ok(defined $body, 'user_may_read_debug exists');
    unlike($body, qr/user_is_unrestricted/,
           'user_may_read_debug does NOT grant via site-unrestriction');
    like($body, qr/user_is_admin/, '... it grants via admin');
    like($body, qr/\{read_debug\}/, '... or the explicit flag');

    # The column must reach every place that reads or writes a user row.
    like($src, qr/download_full_config, read_debug, email FROM users WHERE username/,
         'db_get_user selects read_debug');
    like($src, qr/download_full_config, read_debug, email FROM users ORDER BY/,
         'db_all_users selects read_debug');
    like($src, qr/qw\(edit_device_table admin_function download_full_report download_full_config\s+read_debug\)/,
         'db_set_user_flag allows read_debug');
    like($src, qr/read_debug = \?/,           'user_save updates the column');
    like($src, qr/'set_read_debug'/,          'user_save audits the change');
    like($src, qr/name="read_debug" value="1" class="ue-sub"/,
         'the user editor renders the checkbox, greyed by the existing admin JS');

    # The schema has to carry it in BOTH places, or a fresh install and an
    # upgraded one disagree.
    for my $f ('fetchconfig-web-dbsetup.pl', 'fetchconfig-web-dbupdate-2.08.sql') {
        my $path = "$FindBin::Bin/../$f";
        open(my $g, '<', $path) or die "$f: $!";
        my $t = do { local $/; <$g> }; close($g);
        like($t, qr/read_debug\s+BOOLEAN\s+NOT NULL DEFAULT FALSE/i,
             "$f declares read_debug NOT NULL DEFAULT FALSE (nobody gains it on upgrade)");
    }
}

# ---------------------------------------------------------------------------
# 2. Size bands.
# ---------------------------------------------------------------------------
{
    is(main::DEBUG_VIEW_FULL_MAX(),  2 * 1024 * 1024, 'full-view limit is 2 MB');
    is(main::DEBUG_VIEW_CHUNK(),     1 * 1024 * 1024, 'each chunk is 1 MB');
    is(main::DEBUG_MAX_BYTES(),     16 * 1024 * 1024, 'hard ceiling is 16 MB');

    # The viewer never renders more than 2 MB of source, in any band.
    cmp_ok(2 * main::DEBUG_VIEW_CHUNK(), '<=', main::DEBUG_VIEW_FULL_MAX(),
           'head + tail never exceed the full-view limit');

    my $td = tempdir(CLEANUP => 1);

    # (a) under the limit -> whole file, not cut
    my $small = "$td/small.debug";
    open(my $f, '>', $small) or die $!; binmode($f);
    print $f "line$_\n" for 1 .. 50;
    close($f);
    my ($raw, $cut, $err) = main::debug_log_read($small, (stat($small))[7]);
    is($err, undef, 'small file reads');
    is($cut, 0,     '... and is not cut');
    is(ref $raw, '', '... returning a plain string');
    like($raw, qr/^line1\n/,   '... from the very beginning');
    like($raw, qr/line50\n\z/, '... to the very end');

    # (b) over the limit -> [head, tail], each cut on a LINE boundary
    my $big = "$td/big.debug";
    open($f, '>', $big) or die $!; binmode($f);
    # 35-byte numbered lines (34 digits + newline), comfortably past 2 MB.
    my $LINE = 35;
    my $n = int(main::DEBUG_VIEW_FULL_MAX() / $LINE) + 20000;
    print $f sprintf("%034d\n", $_) for 1 .. $n;
    close($f);
    my $size = (stat($big))[7];
    cmp_ok($size, '>', main::DEBUG_VIEW_FULL_MAX(), 'test file is over the full-view limit');
    cmp_ok($size, '<', main::DEBUG_MAX_BYTES(),     '... and under the ceiling');

    ($raw, $cut, $err) = main::debug_log_read($big, $size);
    is($err, undef,      'large file reads');
    is($cut, 1,          '... and reports itself cut');
    is(ref $raw, 'ARRAY', '... returning [head, tail]');
    my ($head, $tail) = @$raw;

    cmp_ok(length($head), '<=', main::DEBUG_VIEW_CHUNK(), 'head is at most one chunk');
    cmp_ok(length($tail), '<=', main::DEBUG_VIEW_CHUNK(), 'tail is at most one chunk');
    cmp_ok(length($head), '>',  main::DEBUG_VIEW_CHUNK() - 100, 'head is very nearly a full chunk');

    # THE property: no partial line survives at either seam. A half dump line
    # would be sliced at the wrong column by the positional hex parser.
    is(substr($head, -1), "\n", 'head ends exactly on a line boundary');
    like($head, qr/^0{33}1\n/,  'head starts at the beginning of the file');
    my @hl = split /\n/, $head, -1;
    is(length($hl[-2]), 34, 'head: last kept line is a whole line');
    my @tl = split /\n/, $tail, -1;
    is(length($tl[0]), 34, 'tail: first kept line is a whole line');
    like($tail, qr/\n\z/,  'tail ends on a line boundary');
    like($tail, qr/0{29}$n\n\z/, 'tail runs to the end of the file');

    # (c) a chunk with no newline at all is kept whole, not discarded.
    my $nonl = "$td/nonl.debug";
    open($f, '>', $nonl) or die $!; binmode($f);
    print $f ('x' x (main::DEBUG_VIEW_FULL_MAX() + 4096));
    close($f);
    ($raw, $cut, $err) = main::debug_log_read($nonl, (stat($nonl))[7]);
    is($err, undef, 'a file with no newline at all still reads');
    is($cut, 1, '... is cut');
    cmp_ok(length($raw->[0]), '>', 0, '... and the head is kept, not discarded');
}

# ---------------------------------------------------------------------------
# 3. The size note and the cut marker.
# ---------------------------------------------------------------------------
{
    my $note = main::debug_size_note();
    for my $want ('2 MB', '16 MB', '1 MB') {
        like($note, qr/\Q$want\E/, "the note states $want");
    }
    unlike($note, qr/2\.0 MB/, 'whole-megabyte limits read as "2 MB", not "2.0 MB"');
    like($note, qr/cannot be processed or downloaded/,
         'the note says an oversized log cannot be downloaded either');

    my $m = main::debug_cut_marker('hex');
    like($m, qr/content cut because of a 2 MB viewing size limit/, 'marker text');
    like($m, qr/class="dbg-l dbg-cut"/, 'marker carries dbg-cut');
    # It must survive EVERY filter: a reader can never hide the fact that
    # content is missing.
    unlike($m, qr/dbg-tx|dbg-rx|dbg-ssh/, 'marker carries no filterable class');
    like($m, qr/\n<\/span>/, 'marker keeps the newline-inside-span contract');
    my $p = main::debug_cut_marker('plain');
    unlike($p, qr/<span/, 'the plain view gets the marker as text');
    like(css_source(), qr/\.dbg-cut \{ color: #ff7b72; font-weight: 700; \}/,
         'the marker is bold red');
}

# ---------------------------------------------------------------------------
# 4. The permission matrix, per handler.
# ---------------------------------------------------------------------------
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    my %body;
    for my $sub (qw(show_debug_log do_download_debug do_delete_debug
                    do_delete_all_debug show_tool_debug show_status_page
                    status_debug_cell)) {
        ($body{$sub}) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        ok(defined $body{$sub}, "$sub is present");
    }

    # Viewing: the read_debug right.
    like($body{show_debug_log},  qr/user_may_view_debug\(\$user\)/,
         'the viewer gates on read_debug, not on admin');
    like($body{show_status_page}, qr/user_may_view_debug\(\$user\)/,
         'the Debug column follows the same right');

    # Download and delete: administrator only.
    for my $sub (qw(do_download_debug do_delete_debug do_delete_all_debug show_tool_debug)) {
        like($body{$sub}, qr/user_may_use_tools\(\$user\)/, "$sub requires admin");
        unlike($body{$sub}, qr/user_may_view_debug/,        "$sub is not satisfied by read_debug");
    }

    # Device scope on both per-device entry points.
    for my $sub (qw(show_debug_log do_download_debug do_delete_debug)) {
        like($body{$sub}, qr/valid_id\(\$dev\)/,              "$sub validates the id");
        like($body{$sub}, qr/device_accessible\(\$user, \$dev\)/, "$sub re-checks site scope");
    }

    # The status cell offers View and nothing else.
    like($body{status_debug_cell},   qr/>View</,       'the status cell offers View');
    unlike($body{status_debug_cell}, qr/delete_debug|download_debug/,
           '... and neither Delete nor Download');
    like($body{show_status_page}, qr/view debug/, 'the column header carries the "view debug" tag');

    # Download is a GET; the two deletes are POST + CSRF.
    my $sc = state_changing_actions();
    ok(!$sc->{download_debug}, 'download_debug is a read-only GET');
    ok(!$sc->{view_debug},     'view_debug is a read-only GET');
    ok($sc->{delete_debug},     'delete_debug is POST + CSRF');
    ok($sc->{delete_all_debug}, 'delete_all_debug is POST + CSRF');

    # The ceiling is enforced in the handler, not merely on the button.
    like($body{do_download_debug}, qr/\$size > DEBUG_MAX_BYTES/,
         'download re-checks the size ceiling server-side');
    like($body{show_debug_log},    qr/\$size > DEBUG_MAX_BYTES/,
         'the viewer refuses an oversized log');
    # Download must stream the WHOLE file -- never the head/tail split, which
    # exists only to bound what is rendered.
    like($body{do_download_debug}, qr/debug_log_window\(\$path, 0, undef\)/,
         'download reads the whole file');
    unlike($body{do_download_debug}, qr/debug_log_read/,
           '... not the split the viewer uses');

    # Navigation: "from" is request input, so it may only pick from a fixed set.
    like($body{show_debug_log}, qr/\$from eq 'tool'\s*\)\s*\?\s*\('tool_debug'/s,
         'the breadcrumb chooses from a fixed set, never building a URL from input');
}

# ---------------------------------------------------------------------------
# 5. Device-id ordering.
#
# The device table is stored in whatever order it was edited in. Sorting in
# read_all_status() rather than in the page means the status table, Tools ->
# Device debug logs and the purge all agree, and the order survives with
# JavaScript off.
# ---------------------------------------------------------------------------
{
    no warnings qw(redefine once);
    my @ids = qw(zulu Alpha swisit08 SWIGMG01 rtrsic01 Bravo alpha);
    local *main::slurp_device_table = sub { ('', undef) };
    local *main::parse_device_table = sub {
        [ map { { kind => 'device', id => $_, model => 'generic',
                  opts => [[ 'repository', '/nonexistent' ]] } } @ids ] };
    local *main::resolve_dir_alias  = sub { $_[1] };
    local *main::read_status_file   = sub { undef };
    local *main::device_site_code   = sub { '' };
    local *main::db_connect         = sub { undef };

    my ($rows, $err) = main::read_all_status(undef);
    is($err, undef, 'read_all_status returns rows');
    my @got = map { $_->{id} } @$rows;
    is_deeply(\@got, [qw(Alpha alpha Bravo rtrsic01 SWIGMG01 swisit08 zulu)],
              'devices come back in case-insensitive device-id order');
    isnt("@got", "@ids", '... not in device-table order');

    # Case must not segregate the list: an upper-case id belongs beside its
    # lower-case neighbours, not before all of them (plain cmp would do that).
    my @plain = sort @ids;
    isnt("@got", "@plain", 'ordering is case-INsensitive, not a plain cmp');
}

# The Device-ID column must advertise itself as the active sort, or the arrow
# contradicts the rows and the first click re-applies ascending.
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    my ($tbl) = $src =~ /(\Qprint qq{<table class="list" id="status-table">\E.{0,900})/s;
    ok(defined $tbl, 'found the status table header');
    like($tbl, qr/data-key="dev" data-dir="asc"/,
         'Device-ID is marked as the active ascending sort');
    like($tbl, qr/sort-ind">&nbsp;&#9650;/, '... and shows the ascending arrow');
}

# Sorting a column must reorder ALL rows, not just the ones currently on
# screen. render() pages by slicing the `rows` array, so sortBy() has to write
# the sorted order back into it -- reordering only the DOM leaves the page
# contents chosen from the original order, and the user sees just the visible
# lines change places. The device list already did this; the status table did
# not.
{
    my $js = main::status_page_script();
    my ($sortby) = $js =~ /function sortBy\(key, dir\)\{(.*?)\n  \}/s;
    ok(defined $sortby, 'status page has a sortBy()');
    like($sortby, qr/sorted\.forEach\(function\(r\)\{ tb\.appendChild\(r\); \}\)/,
         'sortBy reorders the DOM');
    like($sortby, qr/^\s*rows = sorted;/m,
         'sortBy also writes the order back to the rows array (paging reads it)');

    # render() must page over that same array, or the two drift apart again.
    like($js, qr/var matched = rows\.filter\(matches\);/,
         'render() pages over the rows array');
}

# ---------------------------------------------------------------------------
# 6. Site / Device-ID filters on the status page.
#
# Same controls and the same matching rules as the device list, so the two
# pages behave alike: site is an exact match from a drop-down of the codes
# actually present, device-id is a case-insensitive substring.
# ---------------------------------------------------------------------------
{
    my $js = main::status_page_script();
    like($js, qr/getElementById\('status-site-filter'\)/, 'the script binds the site filter');
    like($js, qr/getElementById\('status-dev-filter'\)/,  'the script binds the device filter');

    my ($m) = $js =~ /function matches\(row\)\{(.*?)\n  \}/s;
    ok(defined $m, 'matches() found');
    like($m, qr/siq===''\s*\|\|\s*si===siq/, 'site is an exact match');
    like($m, qr/dq===''\s*\|\|\s*dv\.indexOf\(dq\)!==-1/, 'device-id is a substring match');
    like($m, qr/devBox\.value\.trim\(\)\.toLowerCase\(\)/, '... case-insensitively');

    # Clearing must clear ALL four, not just the two it started with.
    my ($clear) = $js =~ /clearBtn\.addEventListener\('click', function\(\)\{(.*?)\}\);/s;
    ok(defined $clear, 'Clear filter handler found');
    for my $c (qw(stateSel chgSel siteSel devBox)) {
        like($clear, qr/\Q$c\E\s*\.?value=''/, "Clear resets $c");
    }

    # Typing must filter as you type, not only on blur.
    like($js, qr/devBox\.addEventListener\('input',\s*onFilter\)/,
         'the device box filters on input');

    # The cookie gains two fields; they must be APPENDED, or a cookie written
    # by an older version would restore its values into the wrong controls.
    my ($save) = $js =~ /function save\(\)\{(.*?)\n  \}/s;
    # Assert the POSITION, not the fallback literal: the default page size is
    # free to change, the field order is not.
    like($save, qr/sizeSel\?sizeSel\.value:'\d+',/, 'size keeps cookie field 3');
    like($save, qr/siteSel\?siteSel\.value:'',\s*devBox\?devBox\.value:''/s,
         'site/device are appended after the original three');
    like($js, qr/setSel\(siteSel,\s*p\[3\]/, 'restore reads site from field 4');
    like($js, qr/devBox\.value = p\[4\]/,     'restore reads device from field 5');
}

# Untagged devices must report the sentinel in data-site, or the "(no site)"
# option matches nothing. (The browser rewrites the NUL to U+FFFD in BOTH the
# option value and the attribute, so they still compare equal.)
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    # Scoped to show_status_page: the device LIST emits the same expression,
    # so an unscoped match would pass even with the status page broken.
    my ($sp) = $src =~ /\nsub show_status_page \{(.*?)\n\}\n/s;
    ok(defined $sp, 'show_status_page found');
    like($sp, qr/data-site="\}\s*\.\s*esc\(\$site ne '' \? lc \$site : "\\0none"\)/,
         'status rows carry the \0none sentinel for untagged devices');
    like($sp, qr/<option value="\\0none">\(no site\)<\/option>\} if \$have_untagged/,
         'the (no site) option is offered only when some device is untagged');
    like($sp, qr/id="status-site-filter"/, 'the status page renders the site select');
    like($sp, qr/id="status-dev-filter"/,  'the status page renders the device box');
}

# The Delete button sits in a <form>; Download next to it does not. In the
# flex toolbar a "display:inline" form is blockified to a block and gains a
# line box taller than its button, which leaves Delete a pixel below
# Download. inline-flex keeps the form exactly as tall as its button, in the
# toolbar and in the Tools table cell alike.
{
    my $css = css_source();
    my ($rule) = $css =~ /\.dbg-del-form \{([^}]*)\}/s;
    ok(defined $rule, '.dbg-del-form has a rule');
    like($rule, qr/display:\s*inline-flex/, 'the delete form is inline-flex');
    unlike($rule, qr/display:\s*inline\s*;/, '... not plain inline (it blockifies in the toolbar)');
    like($rule, qr/align-items:\s*center/, '... and centres its button');
}

# The filter row's labels are flex containers, so their text is an anonymous
# flex item: without nowrap, "Device-ID" breaks across two lines as soon as
# the control beside it claims the width. And .filter-box defaults to
# width:100% with a vertical margin (it doubles as a standalone box); the
# reset for that existed only under .filter-row, so inside .dev-filter-row the
# input stretched to fill its label and made the row three times taller.
{
    my $css = css_source();
    my ($lab) = $css =~ /\.filter-label \{([^}]*)\}/s;
    ok(defined $lab, '.filter-label has a rule');
    like($lab, qr/white-space:\s*nowrap/, 'filter labels do not wrap');

    # One rule governs the text box AND the drop-downs, so they cannot drift
    # apart again: same height, padding, border and rendered font size.
    my ($ctl) = $css =~ /\.dev-filter-row \.filter-box,\s*\n\s*\.dev-filter-row \.filter-select \{([^}]*)\}/s;
    ok(defined $ctl, 'one rule styles both the box and the selects in this row');
    like($ctl, qr/margin:\s*0/,        '... no stray vertical margin');
    like($ctl, qr/width:\s*[\d.]+em/,  '... an explicit width, not 100%');
    like($ctl, qr/height:\s*[\d.]+em/, '... an explicit height, so a select and an input match');
    like($ctl, qr/padding:\s*0\.5em 0\.7em/, '... the same padding the Devices row uses');
    # The controls sit inside a 0.9em label; without cancelling that they
    # render smaller than their counterparts on the Devices page.
    like($ctl, qr/font-size:\s*1\.0556em/, '... and a font size that cancels the label');
}

# Per page offers the same ladder and default as the device list. A cookie
# holding one of the old sizes (25/50/100) finds no matching option, and
# restore() only assigns on an exact match, so the select keeps its default.
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    my ($sp) = $src =~ /\nsub show_status_page \{(.*?)\n\}\n/s;
    my ($sel) = $sp =~ /id="status-page-size"(.*?)<\/select>/s;
    ok(defined $sel, 'the status page has a per-page select');
    my @vals = $sel =~ /<option value="(\d+)"/g;
    is_deeply(\@vals, [qw(0 10 20 40 80 160)], 'per-page ladder matches the device list');
    like($sel, qr/<option value="40" selected>/, 'it defaults to 40');

    # The script's fallbacks must not contradict the markup.
    my $js = main::status_page_script();
    unlike($js, qr/sizeSel\?sizeSel\.value:'100'/, 'no stale 100 in the cookie fallback');
    unlike($js, qr/parseInt\(sizeSel\.value,10\) : 100/, 'no stale 100 in the page-size fallback');
}

# Filter row order: State | Changed | Site | Device-ID | Clear filter.
# The COOKIE keeps its own field order; the two are independent, and swapping
# the cookie order would make a cookie written by an earlier version restore
# into the wrong controls.
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> }; close($fh);
    my ($sp) = $src =~ /\nsub show_status_page \{(.*?)\n\}\n/s;

    my @order;
    while ($sp =~ /(?:filter-label">([A-Za-z\- ]+?)\s*\}|id="status-clear"[^>]*>(Clear filter))/g) {
        push @order, defined $1 ? $1 : $2;
    }
    is_deeply(\@order, ['State', 'Changed', 'Site', 'Device-ID', 'Clear filter'],
              'filter controls render in the requested order');

    # Cookie field order must NOT have followed the visual order.
    my $js = main::status_page_script();
    my ($save) = $js =~ /function save\(\)\{(.*?)\n  \}/s;
    like($save, qr/stateSel.*?chgSel.*?sizeSel.*?siteSel.*?devBox/s,
         'the cookie keeps state|changed|size|site|dev regardless of layout');
}

done_testing();
