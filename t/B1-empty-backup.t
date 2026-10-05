use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();

no warnings 'redefine', 'once';
my @A;
local *main::audit = sub { my %f=@_; push @A, $f{detail}; };
local *main::page_head = sub { '' }; local *main::page_foot = sub { '' };
local *main::top_bottom_nav = sub { '' }; local *main::user_may_use_tools = sub { 1 };
local *main::copy_button_html = sub { '' }; local *main::copy_button_script = sub { '' };
local *CGI::param = sub { return; };

my $found2 = "info: checked 256 device(s)/1498 backup(s), found 2 zero-byte backup(s)\n"
           . "rtr1 11 0 /path/a\nrtr2 15 0 /path/b\n";
my $found0 = "info: checked 256 device(s)/1498 backup(s), found 0 zero-byte backup(s)\n";

# CHECK: 2 found (rc 1 must NOT be an error); listing shown; nothing audited
{
    local *main::run_empty_bk_check = sub { ($found2, 1, undef) };
    my $o=''; open(my $c,'>',\$o); my $s=select($c); main::show_empty_bk_check_data('admin'); select($s); close($c);
    like($o, qr/Found 2 empty/, 'check: reports 2 found');
    like($o, qr/rtr1/, 'check: shows the listing');
}
# CHECK: 0 found (rc 0)
{
    local *main::run_empty_bk_check = sub { ($found0, 0, undef) };
    my $o=''; open(my $c,'>',\$o); my $s=select($c); main::show_empty_bk_check_data('admin'); select($s); close($c);
    like($o, qr/No empty .*backups found/, 'check: reports none');
}
# DELETE: 2 found -> audited with the count
{
    @A=();
    local *main::run_empty_bk_delete = sub { ($found2, 1, undef) };
    my $o=''; open(my $c,'>',\$o); my $s=select($c); main::do_empty_bk_delete_data('admin'); select($s); close($c);
    like($A[0], qr/deleted 2 empty .*backup/, 'delete: audits the count');
    like($o, qr/Deleted 2 empty/, 'delete: reports the count');
}
# run helpers build the right fetchconfig args
{
    no warnings 'redefine';
    my @cap; local *main::run_command_capture = sub { @cap = @_; ('', 0, undef) };
    main::run_empty_bk_check();
    ok((grep { $_ eq '-Z' } @cap) && !(grep { $_ eq '-D' } @cap), 'check runs -Z (no -D)');
    main::run_empty_bk_delete();
    ok((grep { $_ eq '-Z' } @cap) && (grep { $_ eq '-D' } @cap), 'delete runs -Z -D');
}
# The spinner shell: delete POSTs with the correct CSRF param ("csrf", not
# "csrf_token", which csrf_ok() reads); check is a GET.
{
    no warnings 'redefine', 'once';
    local *main::csrf_token = sub { 'TOKxyz' };
    my $del = main::empty_bk_result_shell('empty_bk_delete_data');
    like($del,   qr/opt\.method = 'POST'/, 'delete shell: POST path present');
    like($del,   qr/fd\.append\('csrf', "TOKxyz"\)/, 'delete shell sends csrf param (name "csrf")');
    like($del,   qr/fd\.append\('action', "empty_bk_delete_data"\)/, 'delete shell POSTs action in the body');
    unlike($del, qr/csrf_token/, 'delete shell does not use the wrong csrf_token name');
    like($del,   qr/<noscript><form method="POST"/, 'delete no-JS fallback is a POST form');
    my $chk = main::empty_bk_result_shell('empty_bk_check_data');
    like($chk,   qr/if \("GET" === 'POST'\)/, 'check shell uses GET');
}

done_testing();
