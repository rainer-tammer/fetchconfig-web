use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path state_changing_actions);

# --------------------------------------------------------------------------
# "Dismiss" button on the external device-table change warning banner. It clears
# the per-user one-shot notice server-side (so the banner does not reappear) via
# an audited, CSRF-protected POST, and removes the banner without reloading the
# page (which on the open editor would lose edits).
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
ok(defined &main::do_external_change_ack, 'do_external_change_ack handler defined');

my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# state-changing => POST + CSRF enforced by the dispatcher
my $sc = state_changing_actions($src);
ok($sc->{external_change_ack}, 'external_change_ack is a state-changing (CSRF-gated) action');

# dispatch wiring
like($src, qr/action eq 'external_change_ack'/,         'dispatcher routes external_change_ack');
like($src, qr/do_external_change_ack\(\$user\)/,        'dispatch calls the handler');

# handler behaviour: clears the per-user notice (empty, since web has no DELETE) + audits
like($src, qr/app_state_set\(\$dbh, "external_notice:\$user", '', \$user\)/,
     'handler clears the per-user external_notice');
like($src, qr/action => 'external_change_ack'/,         'handler audits the acknowledgement');

# banner: Dismiss button with the CSRF token + a fetch that removes the banner
like($src, qr/id="ext-change-warning"/,                 'banner carries a stable id');
like($src, qr/id="ext-change-dismiss"[^>]*data-csrf="/s,'Dismiss button carries the CSRF token');
like($src, qr/action=external_change_ack&csrf=/,        'dismiss POSTs the ack action with csrf');
like($src, qr/removeChild\(w\)/,                        'banner is removed client-side on success (no reload)');

# The inline dismiss script must be VALID JS. It is built with a ~ delimiter
# (not qq{}) because the JS body has unbalanced "{" that brace-delimited qq{}
# miscounts -- which once produced a "missing )" syntax error in the browser.
like($src, qr/qq~\(function\(\)\{/, 'dismiss script uses a brace-safe ~ delimiter, not qq{}');
my ($js) = $src =~ /qq~([^~]*)~/;
ok(defined $js && $js =~ /addEventListener\('click'/, 'inline dismiss script extracted');
is((($js =~ tr/(//) - ($js =~ tr/)//)), 0, 'dismiss script: parentheses balanced');
is((($js =~ tr/{//) - ($js =~ tr/}//)), 0, 'dismiss script: braces balanced');

done_testing();
