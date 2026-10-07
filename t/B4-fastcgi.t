use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();
no warnings 'once';

# --- reset_request_state() clears every per-request global -------------------
{
    # Dirty every cache the reset is responsible for.
    $main::AUDIT_WARNING          = 'stale warning';
    $main::EXTERNAL_CHANGE_NOTICE = 'stale notice';
    $main::_fatal_error_cache     = 'stale fatal';
    $main::_sites_cache           = [ { id => 1 } ];
    %main::_user_sites_cache      = ( alice => ['A'] );
    $main::_allowed_dirs_cache    = { present => 1 };
    $main::_templates_t_cache     = { rc => 0 };

    my $err = main::reset_request_state();   # also re-reads config
    ok(!defined $err, 'reset_request_state: config still valid');

    is($main::AUDIT_WARNING,          undef, 'AUDIT_WARNING cleared');
    is($main::EXTERNAL_CHANGE_NOTICE, undef, 'EXTERNAL_CHANGE_NOTICE cleared');
    is($main::_fatal_error_cache,     undef, 'fatal_error_cache cleared');
    is($main::_sites_cache,           undef, 'sites_cache cleared');
    is(scalar keys %main::_user_sites_cache, 0, 'user_sites_cache cleared');
    is($main::_allowed_dirs_cache,    undef, 'allowed_dirs_cache cleared');
    is($main::_templates_t_cache,     undef, 'templates_t_cache cleared');
}

# --- the reset list is complete: every file-scoped request cache is reset -----
# Guard against a future cache being added without a matching reset line.
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> };
    close($fh);

    # The per-request cache globals, declared together near the top under the
    # "Per-request globals and in-memory caches" comment. Extract that block.
    my ($block) = $src =~ /Per-request globals and in-memory caches,.*?\n\n/s;
    ok($block, 'found the predeclaration block');
    my @declared = $block =~ /^our ([\%\$]\w+);/mg;
    # $cgi is reassigned (not cleared to undef) so it is declared separately and
    # excluded here; everything else must be reset.
    my %reset;
    my ($rs) = $src =~ /sub reset_request_state \{(.*?)^\}/ms;
    $reset{$1}++ while $rs =~ /^\s*([\%\$]\w+)\s*=/mg;
    for my $v (@declared) {
        ok($reset{$v}, "reset_request_state clears $v");
    }
}

# --- handle_request wires config-error path to the login page ----------------
{
    no warnings 'redefine';
    my @shown;
    local *main::show_login_form = sub { push @shown, $_[0]; };
    local *main::read_config     = sub { 'BACKUP_TIMEOUT: out of range' };
    local *main::main            = sub { fail('main() must not run on config error'); };
    my $o = ''; open(my $c, '>', \$o); my $sv = select($c);
    main::handle_request(CGI->new(''));
    select($sv); close($c);
    like($shown[0] // '', qr/^Server misconfiguration: BACKUP_TIMEOUT/,
         'handle_request: config error -> styled login page, main() skipped');
}

# --- handle_request sets $cgi and dispatches on a good config ----------------
{
    no warnings 'redefine';
    my $ran = 0; my $seen_cgi;
    local *main::read_config = sub { undef };
    local *main::main        = sub { $ran = 1; $seen_cgi = $main::cgi; };
    my $q = CGI->new('action=foo');
    main::handle_request($q);
    is($ran, 1, 'handle_request: main() dispatched on good config');
    is($seen_cgi, $q, 'handle_request: $cgi set to the request object');
}

# --- the shipped file has the dual-mode run block, not a bare main() ---------
{
    open(my $fh, '<', cgi_path()) or die $!;
    my $src = do { local $/; <$fh> };
    close($fh);
    like($src, qr/my \$USE_FCGI = eval \{ require FCGI; 1 \}/,
         'dual-mode: FCGI probed with fallback');
    like($src, qr/while \(\$req->Accept\(\) >= 0\)/, 'FastCGI accept loop present');
    like($src, qr/CGI::initialize_globals\(\) if defined &CGI::initialize_globals/,
         'per-request CGI reset present (clears cached params between FastCGI requests)');
    like($src, qr/\$req->Finish\(\);/,              'explicit Finish present');
    like($src, qr/POSIX::_exit\(0\) unless \$IN_REQUEST/, 'idle SIGTERM exits immediately');
    like($src, qr/\$RUN_MODE = \(eval \{ \$req->IsFastCGI\(\) \}\) \? 'FCGI' : 'CGI'/,
         'run mode set per request from IsFastCGI');
    like($src, qr/else \{(?:\s*#[^\n]*\n)*\s*handle_request\(CGI->new\);/,
         'plain-CGI fallback calls handle_request once');
    unlike($src, qr/^main\(\);\s*$/m, 'no bare top-level main() remains');
    unlike($src, qr{open\(my \$fh, '-\|'\)}, 'no fork-open against the tied FCGI STDOUT');
    like($src, qr{pipe\(my \$rd, my \$wr\)}, 'run_command_capture uses an explicit pipe');
    like($src, qr{untie \*STDOUT if tied \*STDOUT}, 'child unties STDOUT before redirect (FCGI tie)');
    like($src, qr{POSIX::dup2\(\$wfd, 1\)}, 'child dups real fd 1 via dup2, bypassing the tie');
    like($src, qr{waitpid\(\$pid, 0\) == \$pid}, 'explicit child reap');
    # run_command_capture must NOT use the fork-open open(FH,'-|') form: under
    # FastCGI STDOUT is a tied FCGI::Stream and the fork-open / dup against it
    # dies ("Operation 'OPEN' not supported on FCGI::Stream handle"). It uses an
    # explicit pipe + fork + fd-dup instead, and reaps the child with waitpid.
    # No stray exit inside request handlers that would kill a FastCGI worker:
    # the only top-level exits are the two in the run block.
    my @exits = $src =~ /^\s*exit\s+0;/mg;
    is(scalar @exits, 2, 'exactly two exit 0 (FastCGI branch end, plain-CGI branch end)');
}

# --- About dialog shows the run mode -----------------------------------------
{
    is($main::RUN_MODE, 'CGI', 'RUN_MODE defaults to CGI (plain-CGI / not yet in the loop)');
    my $html = main::about_modal_html();
    like($html, qr{<th>Run mode</th><td>CGI</td>}, 'About dialog shows Run mode: CGI by default');

    local $main::RUN_MODE = 'FCGI';
    like(main::about_modal_html(), qr{<th>Run mode</th><td>FCGI</td>},
         'About dialog shows Run mode: FCGI when set');
}

done_testing();
