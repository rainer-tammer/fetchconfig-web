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


# --- deep-link argument carried across login (view_report file=, 2.00) ---
is(main::login_next_url('view_report','report-20261015-002557.html'),
   main::script_url().'?action=view_report&file=report-20261015-002557.html',
   'view_report deep link keeps a valid file= across login');
like(main::login_next_url('view_template','x.tmpl'), qr/action=view_template/,
   'view_template landing is accepted');
# malicious / invalid args are dropped (not appended)
for my $bad ('../../etc/passwd','report-<script>.html','report-x".html','notreport.html') {
    unlike(main::login_next_url('view_report',$bad), qr/file=/,
           "view_report drops unsafe file arg: $bad");
}
# an arg for an action that does not take one is ignored
unlike(main::login_next_url('view_log','anything'), qr/[&?](file|path|next_arg)=/,
       'view_log carries no deep-link arg');

done_testing();
