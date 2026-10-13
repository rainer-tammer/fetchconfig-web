use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

my ($c) = make_config(); load_cgi($c); main::read_config();
no warnings 'once', 'redefine';

# --- edit page renders grouped sections, site summary, dirty guard -----------
{
    local *main::user_is_admin   = sub { 1 };
    local *main::db_connect      = sub { bless {}, 'MUE' };
    local *main::db_get_user     = sub { { username=>'op', email=>'ops@x.de', admin_function=>0,
        edit_device_table=>1, download_full_report=>0, download_full_config=>1 } };
    local *main::db_user_site_ids = sub { [3,5,7] };
    local *main::db_all_sites    = sub { [ map { {id=>$_, code=>"S$_"} } (3,5,7) ] };
    local *main::page_head       = sub { '' };
    local *main::page_foot       = sub { '' };
    local *CGI::param = sub { my($s,$k)=@_; return 'op' if $k eq 'username'; return; };
    my $o=''; { open(my $fh,'>',\$o); my $sv=select($fh); main::show_user_edit('admin'); select($sv); }
    like($o, qr/Edit user: op/,                       'edit page title');
    like($o, qr/<legend>Identity<\/legend>/,          'Identity group');
    like($o, qr/<legend>Permissions<\/legend>/,       'Permissions group');
    like($o, qr/<legend>Site access<\/legend>/,       'Site access group');
    like($o, qr/id="ue-admin"/,                       'Administrator checkbox');
    like($o, qr/class="ue-sub"/,                      'sub-right checkboxes');
    like($o, qr/ue-sites-cell/,                       'wrapped site summary cell');
    like($o, qr/Edit site access/,                    'link to sites editor');
    like($o, qr/action" value="user_save"/,           'posts to user_save');
    like($o, qr/Save changes/,                        'Save button');
    like($o, qr/id="ue-cancel"/,                      'Cancel button');
    like($o, qr/Discard unsaved changes/,             'unsaved-changes guard');
    like($o, qr/id="ue-edit-sites"/,                  'sites link has an id for the save-first guard');
    like($o, qr/Save your changes before editing site access/, 'save-first alert on the sites link');
    # (email size is asserted at source level below, since the test CGI stub
    #  does not render textfield attributes.)
}

# --- protected admin: permissions locked -------------------------------------
{
    local *main::user_is_admin   = sub { 1 };
    local *main::db_connect      = sub { bless {}, 'MUE' };
    local *main::db_get_user     = sub { { username=>'admin', email=>'', admin_function=>1,
        edit_device_table=>1, download_full_report=>1, download_full_config=>1 } };
    local *main::db_user_site_ids = sub { [0] };
    local *main::db_all_sites    = sub { [] };
    local *main::page_head = sub { '' }; local *main::page_foot = sub { '' };
    local *CGI::param = sub { my($s,$k)=@_; return 'admin' if $k eq 'username'; return; };
    my $o=''; { open(my $fh,'>',\$o); my $sv=select($fh); main::show_user_edit('admin'); select($sv); }
    like($o, qr/always a full administrator/, 'protected admin: permissions locked note');
    unlike($o, qr/id="ue-admin"/,            'protected admin: no editable admin checkbox');
}

# --- save emits ONE audit line per CHANGED field -----------------------------
{
    local *main::user_is_admin = sub { 1 };
    local *main::db_get_user   = sub { { username=>'op', email=>'old@x.de', admin_function=>0,
        edit_device_table=>0, download_full_report=>0, download_full_config=>0 } };
    local *main::normalize_email = sub { $_[0] };
    local *main::db_connect    = sub { bless {}, 'MUE' };
    my @A;
    local *main::audit = sub { my %a=@_; push @A, "$a{action}=$a{new_value}"; };
    local *main::redirect_to_user_page = sub { my %o=@_; $main::LAST_MSG = $o{msg}; };
    my %P = (username=>'op', email=>'new@x.de', edit=>1, full_config=>1);  # 3 changes
    local *CGI::param = sub { my($s,$k)=@_; return $P{$k}; };
    main::do_user_save('admin');
    is_deeply([sort @A], [sort('set_email=new@x.de','set_edit_right=yes','set_download_full_config=yes')],
              'one audit line per changed field, historical action names');
    like($main::LAST_MSG, qr/Saved: /, 'summary lists changes');
}
# --- save with NO changes: no audit lines ------------------------------------
{
    local *main::user_is_admin = sub { 1 };
    local *main::db_get_user   = sub { { username=>'op', email=>'same@x.de', admin_function=>0,
        edit_device_table=>1, download_full_report=>0, download_full_config=>0 } };
    local *main::normalize_email = sub { $_[0] };
    local *main::db_connect    = sub { bless {}, 'MUE' };
    my @A; local *main::audit = sub { push @A, 1; };
    local *main::redirect_to_user_page = sub { my %o=@_; $main::LAST_MSG = $o{msg}; };
    # Every field sent equal to the stored row: email same, edit on, others off.
    my %P = (username=>'op', email=>'same@x.de', edit=>1);  # identical to old
    local *CGI::param = sub { my($s,$k)=@_; return $P{$k}; };
    main::do_user_save('admin');
    is(scalar @A, 0, 'no changes -> no audit lines');
    like($main::LAST_MSG, qr/No changes/, 'summary says no changes');
}

# --- list page: slim columns, username links to edit -------------------------
{
    my $src = do { open(my $fh,'<',cgi_path()) or die $!; local $/; <$fh> };
    like($src, qr/action=user_edit&username=/, 'username links to the edit page');
    like($src, qr/-name => 'email'.*-size => 64/, 'email field widened to size 64');
    like($src, qr/<th>Username<\/th><th>Email<\/th><th>Admin<\/th>.*<th>Password<\/th>/s,
         'list has slim columns (no per-right toggles)');
    unlike($src, qr/_right_toggle_form\('set_admin_right'/, 'no inline admin toggle in the list');
    like($src, qr/action eq 'user_edit'/, 'user_edit dispatched');
    like($src, qr/action eq 'user_save'/, 'user_save dispatched');
    like($src, qr/set_download_full_report set_download_full_config set_email user_save/,
         'user_save is state-changing');
    # Save/Cancel order is consistent (Cancel left, Save right) on the sites page.
    like($src, qr/">Cancel<\/a> .*?<button type="submit" class="btn btn-green">Save<\/button>/s,
         'sites page: Cancel before Save');
    # Compare configurations page uses the green tool-section box.
    like($src, qr/id="compare-section"/, 'compare page wrapped in tool-section');
    like($src, qr/table\.sbs td \{[^}]*background: #fff/s, 'side-by-side diff cells have a white base (not the green box)');
    # The per-device compare views also use the green tool-section box.
    like($src, qr/id="compare-backups-section"/, 'unified compare page wrapped in tool-section');
    like($src, qr/id="side-by-side-section"/,    'side-by-side page wrapped in tool-section');
    like($src, qr/id="backup-list-section"/,     'backups-for page wrapped in tool-section');
    # Compare backups + backups-for pages have the Top/Bottom nav.
    like($src, qr/compare-backups-section.*?top_bottom_nav\(\)/s, 'compare page has Top/Bottom nav');
    like($src, qr/backup-list-section.*?top_bottom_nav\(\)/s,     'backups-for page has Top/Bottom nav');
    like($src, qr/id="backup-now-section"/,   'Backup Now result page wrapped in tool-section');
    like($src, qr/id="check-empty-section"/,  'Check-empty result page wrapped in tool-section');
    like($src, qr/id="orphan-check-section"/,  'Check-orphaned-backups page wrapped in tool-section');
    like($src, qr/id="orphan-delete-section"/, 'Delete-orphaned-backups page wrapped in tool-section');
    # Orphaned notes cleanup has the Top/Bottom nav.
    like($src, qr/notes-orphans-section.*?top_bottom_nav\(\)/s, 'orphaned-notes cleanup has Top/Bottom nav');
    # Empty-cleanup result pages use the green tool-section box.
    like($src, qr/id="empty-dir-check-section"/,  'check empty dirs page wrapped in tool-section');
    like($src, qr/id="empty-dir-delete-section"/, 'delete empty dirs page wrapped in tool-section');
    like($src, qr/id="empty-bk-check-section"/,   'check empty backups page wrapped in tool-section');
    like($src, qr/id="empty-bk-delete-section"/,  'delete empty backups page wrapped in tool-section');
    like($src, qr/id="ebk-result" style="min-height:\d+em;width:\d+px;/, 'empty-backup result reserves a fixed size so the box keeps natural proportions');
    # View backup now has the green box.
    like($src, qr/id="view-backup-section"/, 'view backup page wrapped in tool-section');
    # Single title: no redundant <h1> above the box on these pages.
    unlike($src, qr/print qq\{<h1>Status<\/h1>/,      'no redundant <h1>Status above the box');
    unlike($src, qr/print qq\{<h1>Sites<\/h1>/,       'no redundant <h1>Sites above the box');
    unlike($src, qr/<h2>Site codes<\/h2>/,            'Sites box title is "Sites", not "Site codes"');
    like($src,   qr/tool-section-title">Sites<\/h2>/,  'Sites page box title is "Sites"');
    like($src,   qr/tool-section-title">Sites for /,    'user-sites box title names the user');
    unlike($src, qr/print qq\{<h1>\} . esc\(\$title\)/, 'show_tools has no redundant <h1> above its box title');
    # Devices page: blue box around the list, green statistics box, no h1.
    like($src,   qr/tool-section-blue" id="devices-section"/, 'devices list in a blue tool-section box');
    like($src,   qr/\.tool-section-blue \{/,                 'blue tool-section variant defined');
    like($src,   qr/\.dev-stats \{[^}]*#e8faf1/s,            'statistics box stays green');
    unlike($src, qr/print qq\{<h1>Devices<\/h1>/,            'no redundant <h1>Devices');
    like($src, qr/\.dev-layout \{[^}]*align-items: flex-start/s, 'boxes top-aligned; green hugs content');
    like($src, qr/id="dev-table-scroll"/,                       'device table is in a horizontal-scroll container');
    like($src, qr/main\.full \{ max-width: none/,              'Devices page uses full window width');
    like($src, qr/\.dev-stats \{[^}]*width: max-content/s,     'stats box hugs its content, not stretched');
    like($src, qr/#site-filter \{ max-width/,                  'site filter is narrower');
    like($src, qr/<option value="40" selected>40<\/option>/,   'per-page default 40');
    like($src, qr/<option value="160">160<\/option>/,          'per-page option 160');
    my ($devsel) = $src =~ /id="dev-page-size".*?<\/select>/s;
    unlike($devsel // '', qr/value="100"/, 'devices per-page no longer offers 100');
    # The sites editor (reached from Edit user) returns to the Edit user page,
    # not the user list.
    my ($sites_form) = $src =~ /sub show_user_sites_form \{(.*?)\n#{80}/s;
    like($sites_form // '', qr/action=user_edit&username='/, 'sites form Cancel/breadcrumb -> user_edit');
    my ($sites_save) = $src =~ /sub do_set_user_sites \{(.*?)\n#{80}/s;
    like($sites_save // '', qr/action=>"user_edit", username=>\$target, msg=>"Updated sites/, 'sites save -> user_edit');
    # The reset-password page (reached from Edit user) also returns there.
    my ($rpf) = $src =~ /sub show_reset_password_form \{(.*?)\n#{80}/s;
    like($rpf // '', qr/action=user_edit&username='.*&larr; Edit user/s, 'reset form breadcrumb -> Edit user');
    my ($rp) = $src =~ /sub do_reset_password \{(.*?)\n# Add a new user/s;
    like($rp // '', qr/action=>"user_edit", username=>\$target,\s*\n\s*msg => "Password for \$target was reset/s, 'self-reset success -> user_edit');
    like($rp // '', qr/action=>"user_edit", username=>\$target,\s*\n\s*msg => "Password for '\$target' reset/s, 'other-reset success -> user_edit');
    # The sites editor no longer carries the full-report / full-config
    # permission checkboxes (they live only on the user edit page now).
    my ($sites_sub) = $src =~ /sub show_user_sites_form \{(.*?)\n#{80}/s;
    unlike($sites_sub // '', qr/May download the full/,  'sites form: no full-report checkbox');
    unlike($sites_sub // '', qr/May download a device config/, 'sites form: no full-config checkbox');
    ($sites_save) = $src =~ /sub do_set_user_sites \{(.*?)\n#{80}/s;
    unlike($sites_save // '', qr/download_full_report/, 'sites save: does not write full-report');
    unlike($sites_save // '', qr/download_full_config/, 'sites save: does not write full-config');
    # Add user: no permission checkboxes; creation redirects to the edit page.
    my ($add_sub) = $src =~ /if \(\$only eq 'add'/s ? ($src =~ /(if \(\$only eq 'add'.*?# \.user-section \(Add user\))/s) : ('');
    unlike($add_sub // '', qr/Grant admin functions/,   'add form: no admin checkbox');
    unlike($add_sub // '', qr/Allow this user to view and edit/, 'add form: no edit checkbox');
    like($src, qr/redirect_to_user_page\(action=>"user_edit", username=>\$new_user/,
         'add user redirects to the edit page');
    like($src, qr/db_add_user\(\$dbh, \$new_user, password_hash\(\$password\), 0, 0\)/,
         'new user created with no special rights');
}

done_testing();

package MUE;
sub do { 1 }
sub errstr { '' }
sub disconnect {}
