use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config(BACKUP_TIMEOUT => 2);
load_cgi($cfg); main::read_config();

# A command that emits output then hangs past the timeout: the child is killed,
# but the partial output is preserved and returned with a timeout error.
SKIP: {
    skip "no /bin/sh", 3 unless -x '/bin/sh';
    my ($out, $status, $err) = main::run_command_capture('/bin/sh','-c','echo line1; echo line2; sleep 20');
    like($out, qr/line1/, 'partial output captured before timeout');
    like($err, qr/timed out after 2s/, 'timeout reported as an error');
    ok(!defined $status, 'exit status undef after a kill');
}

# A normal, quick command: full output, status 0, no error.
SKIP: {
    skip "no /bin/sh", 3 unless -x '/bin/sh';
    my ($out, $status, $err) = main::run_command_capture('/bin/sh','-c','echo ok; exit 0');
    like($out, qr/ok/, 'output captured');
    is($status, 0, 'exit status 0');
    ok(!defined $err, 'no error on success');
}

# Backup success is judged from the OUTPUT (fetchconfig always exits 0): an
# "error:" line means FAILED; the meaningless rc is not logged.
{
    no warnings 'redefine', 'once';
    my @A;
    local *main::audit = sub { my %f=@_; push @A, $f{detail}; };
    local *main::page_head = sub { '' };
    local *main::page_foot = sub { '' };
    local *main::top_bottom_nav = sub { '' };
    local *main::valid_id = sub { 1 };
    local *main::copy_button_html = sub { '' };
    local *main::copy_button_script = sub { '' };
    local *CGI::param = sub { my ($s,$k)=@_; return 'sw1' if $k eq 'dev'; return; };

    local *main::run_backup_now = sub { ("info: retrieving\nerror: enable failed\ninfo: done\n", 0, undef) };
    @A=(); my $o=''; open(my $c,'>',\$o); my $sv=select($c); main::show_backup_now('admin'); select($sv); close($c);
    like($A[0], qr/^FAILED:/, 'output with error: -> audit FAILED');
    like($o, qr/Backup run FAILED/, 'page shows FAILED');

    local *main::run_backup_now = sub { ("info: retrieving\ninfo: saved\n", 0, undef) };
    @A=(); $o=''; open($c,'>',\$o); $sv=select($c); main::show_backup_now('admin'); select($sv); close($c);
    like($A[0], qr/^OK:/, 'clean output -> audit OK');
    like($o, qr/finished successfully/, 'page shows success');

    local *main::run_backup_now = sub { ("info: partial\n", undef, "Backup timed out after 2s and was terminated.") };
    @A=(); $o=''; open($c,'>',\$o); $sv=select($c); main::show_backup_now('admin'); select($sv); close($c);
    like($A[0], qr/^FAILED:/, 'timeout -> audit FAILED');
    like($o, qr/info: partial/, 'timeout still shows partial output');
}

# backup_state=failed in the output is also a failure; other states are OK.
{
    no warnings 'redefine', 'once';
    my @A;
    local *main::audit = sub { my %f=@_; push @A, $f{detail}; };
    local *main::page_head = sub { '' }; local *main::page_foot = sub { '' };
    local *main::top_bottom_nav = sub { '' }; local *main::valid_id = sub { 1 };
    local *main::copy_button_html = sub { '' }; local *main::copy_button_script = sub { '' };
    local *CGI::param = sub { my ($s,$k)=@_; return 'sw1' if $k eq 'dev'; return; };

    local *main::run_backup_now = sub { ("info: retrieving\nbackup_state=failed\nbackup_changed=unknown\n", 0, undef) };
    @A=(); my $o=''; open(my $c,'>',\$o); my $sv=select($c); main::show_backup_now('admin'); select($sv); close($c);
    like($A[0], qr/^FAILED:/, 'backup_state=failed -> audit FAILED');

    local *main::run_backup_now = sub { ("info: retrieving\nbackup_state=success\n", 0, undef) };
    @A=(); $o=''; open($c,'>',\$o); $sv=select($c); main::show_backup_now('admin'); select($sv); close($c);
    like($A[0], qr/^OK:/, 'backup_state=success -> audit OK');

    local *main::run_backup_now = sub { ("info: retrieving\nbackup_state=unchanged\n", 0, undef) };
    @A=(); $o=''; open($c,'>',\$o); $sv=select($c); main::show_backup_now('admin'); select($sv); close($c);
    like($A[0], qr/^OK:/, 'backup_state=unchanged -> audit OK');
}

done_testing();
