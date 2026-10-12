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
    # The sites editor no longer carries the full-report / full-config
    # permission checkboxes (they live only on the user edit page now).
    my ($sites_sub) = $src =~ /sub show_user_sites_form \{(.*?)\nsub /s;
    unlike($sites_sub // '', qr/May download the full/,  'sites form: no full-report checkbox');
    unlike($sites_sub // '', qr/May download a device config/, 'sites form: no full-config checkbox');
    my ($sites_save) = $src =~ /sub do_set_user_sites \{(.*?)\nsub /s;
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
