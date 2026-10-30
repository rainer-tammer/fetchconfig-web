use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# F-04. CAPTURE_MAX_BYTES bounds subprocess output capture.

# run_privileged: over the cap -> no output, controlled error.
{
    my ($cfg) = make_config(CAPTURE_MAX_BYTES => 1000);
    load_cgi($cfg); main::read_config();

    my ($out, $errout, $status, $err) =
        main::run_privileged($^X, '-e', 'print "x" x 50000');
    ok(!defined $out,                       'run_privileged discards output on overflow');
    like($err, qr/exceeded CAPTURE_MAX_BYTES/, 'run_privileged returns a controlled overflow error');

    my ($o2, $e2, $s2, $er2) = main::run_privileged($^X, '-e', 'print "hello"');
    is($o2, 'hello',  'run_privileged: under-limit output intact');
    ok(!defined $er2, 'run_privileged: no error under the limit');
}

# run_command_capture: over the cap -> partial transcript kept + error (like timeout).
{
    my ($cfg) = make_config(CAPTURE_MAX_BYTES => 1000);
    load_cgi($cfg); main::read_config();
    my ($out, $status, $err, $aborted) =
        main::run_command_capture($^X, '-e', 'print "y" x 50000');
    like($err, qr/exceeded CAPTURE_MAX_BYTES/,     'run_command_capture overflow error');
    ok(defined $out && length($out) >= 1000,       'run_command_capture keeps the partial transcript');
}

# 0 disables the cap.
{
    my ($cfg) = make_config(CAPTURE_MAX_BYTES => 0);
    load_cgi($cfg); main::read_config();
    my ($out) = main::run_privileged($^X, '-e', 'print "z" x 20000');
    is(length($out // ''), 20000, 'CAPTURE_MAX_BYTES=0 disables the cap');
}

done_testing();
