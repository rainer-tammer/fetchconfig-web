use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();

# safe landing actions redirect back; devices/undef -> bare url
my $base = main::script_url();
like(main::login_next_url('report'),      qr/\Qaction=report\E$/,      'report -> report page');
like(main::login_next_url('status'),      qr/\Qaction=status\E$/,      'status -> status page');
like(main::login_next_url('view_report'), qr/\Qaction=view_report\E$/, 'view_report allowed');
is(main::login_next_url('devices'), $base, 'devices -> bare url');
is(main::login_next_url(undef),     $base, 'undef -> bare url');

# unsafe values fall back to the default (no open redirect, no action injection)
is(main::login_next_url('delete_report'),   $base, 'state-changing action rejected');
is(main::login_next_url('save_table'),      $base, 'save action rejected');
is(main::login_next_url('logout'),          $base, 'logout rejected');
is(main::login_next_url('http://evil.com'), $base, 'off-site url rejected');
is(main::login_next_url('../x'),            $base, 'traversal rejected');
is(main::login_next_url('report&file=x'),   $base, 'param injection rejected');

done_testing();
