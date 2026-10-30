use strict; use warnings;
use Test::More;
use FindBin;

# A-01. Authorization is enforced per handler (there is no single universal
# gate), so this is a structural regression guard: every privileged handler must
# keep an authorization check, via one of the three mechanisms the app uses --
# an in-body predicate, the dispatcher's central device-scope guard, or
# delegation to a handler that checks. It does not replace runtime tests, but it
# fails loudly if a guard is dropped or a new privileged action ships ungated.

my $src = do {
    open(my $fh, '<', "$FindBin::Bin/../fetchconfig-web.cgi") or die $!;
    local $/; <$fh>;
};

sub body {
    my ($name) = @_;
    my ($b) = $src =~ /\nsub \Q$name\E\b(.*?)(?=\nsub )/s;
    return defined $b ? $b : '';
}

# 1) Handlers that must carry an in-body authorization predicate.
my %guard = (
    show_tool_debug        => qr/user_may_use_tools/,
    show_debug_log         => qr/user_may_view_debug/,
    do_delete_debug        => qr/user_may_use_tools/,
    do_download_debug      => qr/user_may_use_tools/,
    do_delete_all_debug    => qr/user_may_use_tools/,
    show_tool_schedule     => qr/user_may_use_tools/,
    show_tool_audit        => qr/user_is_admin/,
    show_audit_data        => qr/user_is_admin/,
    do_audit_csv           => qr/user_is_admin/,
    show_view_templates    => qr/user_may_use_tools/,
    show_view_template     => qr/user_may_use_tools/,
    show_edit_template     => qr/user_may_use_tools/,
    do_check_template      => qr/user_may_use_tools/,
    do_save_template       => qr/user_may_use_tools/,
    do_revert_template     => qr/user_may_use_tools/,
    do_upload_template     => qr/user_may_use_tools/,
    do_delete_template     => qr/user_may_use_tools/,
    do_rename_template     => qr/user_may_use_tools/,
    do_download_template   => qr/user_may_use_tools/,
    do_restore_backup      => qr/user_may_use_tools/,
    do_delete_backup       => qr/user_may_use_tools/,
    do_delete_old_backups  => qr/user_may_use_tools/,
    show_user_sites_form   => qr/user_is_admin/,
    do_set_user_sites      => qr/user_is_admin/,
    do_user_save           => qr/user_is_admin/,
    do_add_user            => qr/user_is_admin/,
    do_delete_user         => qr/user_is_admin/,
    show_setup             => qr/user_may_edit_table/,
    show_user_page         => qr/user_is_admin/,   # backs show_user_add / show_user_edit
);
for my $sub (sort keys %guard) {
    my $b = body($sub);
    ok(length $b, "found sub $sub");
    like($b, $guard{$sub}, "$sub enforces authorization");
}

# 2) Device-scoped actions are gated centrally in the dispatcher by
#    device_accessible(), so a site-limited user cannot reach another site's
#    device by typing the URL.
{
    my ($set) = $src =~ /my %dev_scoped = map \{ \$_ => 1 \} qw\((.*?)\)/s;
    ok(defined $set, 'dispatcher defines %dev_scoped');
    for my $a (qw(compare sidebyside backup_now view_backup download_config
                  download_latest check_backups_one check_suffix_one)) {
        like($set, qr/\b\Q$a\E\b/, "device-scoped action '$a' is in %dev_scoped");
    }
    like($src, qr/\$dev_scoped\{\$action\}.*?!device_accessible\(\$user/s,
         'dispatcher denies out-of-site device access');
}

# 3) The backup read handlers also enforce device_accessible() in-body (they can
#    be reached with no action= param, which the dispatcher guard keys on).
like(body('show_backup_list'),    qr/device_accessible\(\$user/, 'show_backup_list checks device_accessible');
like(body('show_backup_content'), qr/device_accessible\(\$user/, 'show_backup_content checks device_accessible');

done_testing();
