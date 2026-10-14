use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path css_source state_changing_actions);

my ($c) = make_config(); load_cgi($c); main::read_config();
no warnings 'once', 'redefine';

# --- DB helpers (mock dbh) ----------------------------------------------------
{
    our %T;
    my $dbh = bless {}, 'MND';
    local *main::db_connect = sub { $dbh };
    %T = ();
    ok(main::db_note_save($dbh, 'rtr1', 'hello', 0), 'save note');
    is(main::db_note_get($dbh, 'rtr1')->{note}, 'hello', 'get note');
    main::db_note_save($dbh, 'rtr1', '', 0);
    ok(!defined main::db_note_get($dbh, 'rtr1'), 'empty + no keep => deleted');
    main::db_note_save($dbh, 'rtr2', 'x', 1);
    main::db_note_save($dbh, 'rtr2', '', 1);
    ok(defined main::db_note_get($dbh, 'rtr2'), 'empty + keep => retained');
    main::db_note_save($dbh, 'rtr3', 'body', 0);
    my $p = main::db_notes_present($dbh);
    ok($p->{rtr3}, 'present-set includes a device with a note');
    ok(!$p->{rtr2}, 'present-set excludes an empty note');
    ok(main::db_note_delete($dbh, 'rtr3'), 'delete note');
    ok(!defined main::db_note_get($dbh, 'rtr3'), 'note gone after delete');
}

# --- endpoints: site scope enforced ------------------------------------------
{
    local *main::db_connect       = sub { bless {}, 'MND' };
    local *main::device_accessible = sub { my ($u,$d)=@_; return $d eq 'okdev' ? 1 : 0; };
    # note_get forbidden for a device the user can't see
    my $out=''; { open(my $fh,'>',\$out); my $sv=select($fh);
        local *CGI::param = sub { my($s,$k)=@_; return 'nope' if $k eq 'dev'; return; };
        main::show_note_get('joe'); select($sv); }
    like($out, qr/forbidden/, 'note_get: 403 for out-of-site device');
    # note_save forbidden likewise
    $out=''; { open(my $fh,'>',\$out); my $sv=select($fh);
        local *CGI::param = sub { my($s,$k)=@_; return 'nope' if $k eq 'dev'; return; };
        main::do_note_save('joe'); select($sv); }
    like($out, qr/forbidden/, 'note_save: 403 for out-of-site device');
}

# --- viewer page + modal + wiring --------------------------------------------
{
    local *main::db_connect   = sub { bless {}, 'MND' };
    local *main::page_head    = sub { '' };
    local *main::page_foot    = sub { '' };
    local *main::top_bottom_nav = sub { '' };
    local *main::csrf_field   = sub { '' };
    my $out=''; { open(my $fh,'>',\$out); my $sv=select($fh); main::show_notes('joe'); select($sv); }
    like($out, qr/tool-section-title">Device notes/, 'notes viewer: title');
    like($out, qr/id="nt-dev".*id="nt-keep".*id="nt-from".*id="nt-to"/s, 'notes viewer: filters');
    like($out, qr/ap-first.*ap-last/s, 'notes viewer: pager');
    like($out, qr/action=notes_data/, 'notes viewer: data endpoint');
}
{
    my $src = do { open(my $fh,'<',cgi_path()) or die $!; local $/; <$fh> };
    my $css = css_source();
    like($src, qr/action eq 'note_get'/,            'note_get dispatched');
    like($src, qr/action eq 'note_save'/,           'note_save dispatched');
    like($src, qr/action eq 'note_delete'/,         'note_delete dispatched');
    like($src, qr/action eq 'notes_data'/,          'notes_data dispatched');
    like($src, qr/action eq 'tool_notes'/,          'tool_notes dispatched');
    like($src, qr/action eq 'tool_notes_orphans'/,  'orphan page dispatched');
    like($src, qr/action eq 'notes_orphan_delete'/, 'orphan delete dispatched');
    { my $sc = state_changing_actions($src);
      ok($sc->{note_save} && $sc->{note_delete} && $sc->{notes_orphan_delete},
         'note POST actions are state-changing'); }
    like($src, qr/\$su->\('Device notes',\s*'\?action=tool_notes'\)/, 'Device -> Device notes menu entry');
    like($src, qr/\$su->\('Orphaned notes cleanup',/, 'Tools -> Orphaned notes cleanup entry');
    like($src, qr/&#x1F4DD;/, 'paper-note icon (U+1F4DD, HTML entity) used');
    like($src, qr/sub note_modal_html/, 'note modal present');
    like($css, qr/\.fc-note-text \{[^}]*resize: vertical/s, 'note textarea resizes vertically only (not wider than the dialog)');
    like($src, qr/'action=note_save&csrf='/, 'note save posts the csrf param (not csrf_token)');
    unlike($src, qr/csrf_token='\+encodeURIComponent/, 'no stale csrf_token param name');
    like($src, qr/function isDirty\(\)/, 'modal has an unsaved-changes check');
    like($src, qr/Discard unsaved changes to this note/, 'Cancel warns on unsaved text');
    # modal included globally in page_foot
    like($src, qr/my \$note_html    = note_modal_html\(\);/, 'note modal wired into page_foot');
    # The viewer's delete form must embed CSRF inline; csrf_field()'s trailing
    # newline inside a single-quoted JS string had broken the whole script.
    unlike($src, qr/\+'\@\{\[ csrf_field\(\) \]\}/, 'no csrf_field() (newline) in the JS row template');
    like($src, qr/name="csrf" value="\@\{\[ csrf_token\(\) \]\}">/, 'delete form uses inline csrf_token');
    # note_get lets an admin view any note (orphaned-device notes), site scope otherwise.
    like($src, qr/admin may view any note/, 'note_get: admin bypass commented');
    like($src, qr/user_is_admin\(.dbh, .user\) \|\| device_accessible/, 'note_get: admin-or-accessible check');
    like($src, qr/note_icon_button\(\$o->\{device_id\}, 1\)/, 'orphan table icon is bright (has-note)');
    like($src, qr/class="note-icon has-note" data-note-dev="'\+esc\(r\.dev\)/, 'notes viewer icon is bright (every row has a note)');
}

# Orphan view: admin can note_get a device not in the table; non-admin cannot.
{
    local *main::db_connect        = sub { bless {}, 'MND' };
    local *main::device_accessible = sub { 0 };
    local *main::db_note_get       = sub { { note => 'o', keep => 0, updated => 'x' } };
    local *CGI::param = sub { my ($s,$k)=@_; return 'gone' if $k eq 'dev'; return; };
    {
        local *main::user_is_admin = sub { 1 };
        my $o=''; { open(my $fh,'>',\$o); my $sv=select($fh); main::show_note_get('admin'); select($sv); }
        like($o, qr/"note":"o"/, 'admin can view an orphan note');
    }
    {
        local *main::user_is_admin = sub { 0 };
        my $o=''; { open(my $fh,'>',\$o); my $sv=select($fh); main::show_note_get('joe'); select($sv); }
        like($o, qr/forbidden/, 'non-admin cannot view an out-of-site note');
    }
}

# --- notes_data returns rows the user may see (site access resolved once) ---
# Unrestricted user: all notes are returned.
{
    local *main::db_connect       = sub { bless {}, 'MNDQ' };
    local *main::user_site_access  = sub { { unrestricted => 1 } };
    local *CGI::param = sub { my($s,$k)=@_; return 0 if $k eq 'offset'; return; };
    my $out=''; { open(my $fh,'>',\$out); my $sv=select($fh); main::show_notes_data('admin'); select($sv); }
    like($out, qr/"total":1/,                 'notes_data: visible note counted');
    like($out, qr/rtrtst01loop\.schuler\.de/, 'notes_data: returns the device row');
}
# Restricted user whose device table does NOT contain the noted device -> hidden.
{
    local *main::db_connect        = sub { bless {}, 'MNDQ' };
    local *main::user_site_access   = sub { { unrestricted => 0, codes => {} } };
    local *main::slurp_device_table = sub { ("", undef) };          # no devices
    local *main::parse_device_table = sub { [] };
    local *CGI::param = sub { my($s,$k)=@_; return 0 if $k eq 'offset'; return; };
    my $out=''; { open(my $fh,'>',\$out); my $sv=select($fh); main::show_notes_data('joe'); select($sv); }
    like($out, qr/"total":0/, 'notes_data: out-of-site note is filtered out');
}

done_testing();

package MNDQ;
sub selectall_arrayref { return [ {device_id=>'rtrtst01loop.schuler.de', note=>'n', keep=>1, updated=>'2026-10-11 14:37:34'} ]; }
sub disconnect {}

package MND;
sub new { bless {}, shift }
sub do {
    my ($s,$sql,undef,@b)=@_;
    if ($sql=~/DELETE FROM device_notes WHERE device_id/) { delete $main::T{$b[0]}; return 1; }
    if ($sql=~/UPDATE device_notes SET note/) { my($n,$k,$d)=@b; return 0 unless $main::T{$d}; $main::T{$d}={note=>$n,keep=>$k}; return 1; }
    if ($sql=~/INSERT INTO device_notes/) { my($d,$n,$k)=@b; $main::T{$d}={note=>$n,keep=>$k}; return 1; }
    return 1;
}
sub selectrow_hashref { my ($s,$sql,undef,$d)=@_; my $r=$main::T{$d}; return undef unless $r;
    return {note=>$r->{note}, keep=>$r->{keep}, updated=>'2026-01-01 00:00:00'}; }
sub selectcol_arrayref { return [ grep { ($main::T{$_}{note}//'') ne '' } keys %main::T ]; }
sub selectall_arrayref { return []; }
sub errstr { return 'mock error'; }
sub disconnect {}
