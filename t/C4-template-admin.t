use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# Template admin (2.05): upload name validation, the "Used" determination, and
# the per-request cache invalidation after a device-table rewrite.

my ($cfg, $dir) = make_config();
load_cgi($cfg); main::read_config();
my $dt = File::Spec->catfile($dir, 'device_table');

sub write_table {
    my ($txt) = @_;
    open(my $fh, '>', $dt) or die "write $dt: $!";
    print $fh $txt; close($fh);
    main::_invalidate_table_caches();   # drop memo so the next read is fresh
}

# --- template_upload_name_ok ---
ok( main::template_upload_name_ok('cisco-foo.tmpl'),   'plain name accepted');
ok( main::template_upload_name_ok('my_switch-v2.tmpl'),'letters/digits/._- accepted');
ok(!main::template_upload_name_ok('cisco-foo.txt'),    '.txt rejected (must be .tmpl)');
ok(!main::template_upload_name_ok('cisco-foo'),        'no extension rejected');
ok(!main::template_upload_name_ok('../evil.tmpl'),     '".." rejected');
ok(!main::template_upload_name_ok('a/b.tmpl'),         'path separator rejected');
ok(!main::template_upload_name_ok('.hidden.tmpl'),     'leading dot rejected');
ok(!main::template_upload_name_ok(''),                 'empty rejected');
ok(!main::template_upload_name_ok('with space.tmpl'),  'space rejected');

# --- template_used_paths / template_is_used ---
# generic devices use templates via model= (+ optional template_dir=); the
# default section supplies template_dir when the device omits it. Non-generic
# devices contribute nothing. Literal dirs (no $alias) so no subprocess is hit.
write_table(<<'TBL');
default: generic template_dir=/tpl/dir
generic   dev1 host1.example model=usedmodel
generic   dev2 host2.example model=othermodel,template_dir=/other/dir
cisco-ios dev3 host3.example user=admin
TBL

my $used = main::template_used_paths();
is_deeply([ sort keys %$used ],
          ['/other/dir/othermodel.tmpl', '/tpl/dir/usedmodel.tmpl'],
          'used set = each generic device\'s resolved template (default inheritance + explicit dir)');
ok( main::template_is_used('/tpl/dir/usedmodel.tmpl'),    'device template is "used"');
ok( main::template_is_used('/other/dir/othermodel.tmpl'),'explicit-dir template is "used"');
ok(!main::template_is_used('/tpl/dir/unused.tmpl'),      'unreferenced template is "unused"');
ok(!main::template_is_used('/tpl/dir/cisco-ios.tmpl'),   'a non-generic device does not mark a template used');

# --- cache memoisation + invalidation ---
# Overwrite the table on disk WITHOUT invalidating: the memo must still hold.
open(my $fh, '>', $dt) or die; print $fh <<'TBL'; close($fh);
default: generic template_dir=/tpl/dir
generic dev1 host1.example model=usedmodel
generic dev9 host9.example model=newmodel
TBL
ok(!main::template_is_used('/tpl/dir/newmodel.tmpl'), 'memo holds until invalidated (new device not seen yet)');
main::_invalidate_table_caches();
ok( main::template_is_used('/tpl/dir/newmodel.tmpl'), 'after _invalidate_table_caches the new device is seen');
ok(!main::template_is_used('/other/dir/othermodel.tmpl'), 'removed device no longer marks its template used');

# --- download action: wired, with a Download button, and read-only (no CSRF) ---
{
    my $src = do { open(my $fh,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$fh> };
    like($src, qr/action eq 'download_template'/,       'download_template is dispatched');
    like($src, qr/sub do_download_template/,            'do_download_template is defined');
    like($src, qr/action=download_template&path=/,      'Templates page has a Download button');
    # It is a GET (read-only): must NOT be in the %STATE_CHANGING set.
    my ($body) = $src =~ /%STATE_CHANGING\s*=\s*map\s*\{[^}]*\}\s*qw\((.*?)\)/s;
    my %sc = map { $_ => 1 } grep { length } split /\s+/, ($body // '');
    ok(!$sc{download_template}, 'download_template is read-only (not state-changing)');
    ok( $sc{upload_template} && $sc{delete_template}, 'upload/delete remain state-changing');
}

done_testing();
