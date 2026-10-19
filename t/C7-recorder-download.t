use strict; use warnings;
use Test::More;
use File::Spec;
use Digest::SHA qw(sha256_hex);
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

# Session-recorder download row (2.05): recorder_download_html() is presence-gated
# on WEB_DIR/record_session.{exe,py}; each present file gets a meta line with
# size/date and a SHA-256 that is computed by the CGI and cached in SESSION_DIR
# (keyed by mtime+size). Both downloads use the blue .btn.

my ($cfg, $dir) = make_config();
load_cgi($cfg); main::read_config();
my $web = File::Spec->catdir($dir, 'htdocs');            # == WEB_DIR
my $exe = File::Spec->catfile($web, 'record_session.exe');
my $py  = File::Spec->catfile($web, 'record_session.py');
sub put { my ($p,$c) = @_; open(my $f,'>',$p) or die "$p: $!"; print $f $c; close($f); }
sub rm  { unlink $_[0] if -e $_[0]; }

# 1. neither present -> row omitted
rm($exe); rm($py);
is(main::recorder_download_html(), '', 'no files -> empty string (row omitted)');

# 2. only the .py present -> blue button, meta line with Python note + SHA-256
my $pydata = "#!/usr/bin/env python3\nprint('x')\n";
put($py, $pydata);
my $h = main::recorder_download_html();
like($h,   qr/record_session\.py/,          'py link shown');
unlike($h, qr/record_session\.exe/,         'no exe button when exe absent');
unlike($h, qr/btn-gray/,                    'py button is blue (no btn-gray)');
like($h,   qr/class="btn"[^>]*href="\/record_session\.py"/, 'py uses blue .btn + BASE_URL');
like($h,   qr/runs on Python/,              'python note on the py meta line');
like($h,   qr/SHA-256 <code>\Q${\ sha256_hex($pydata)}\E<\/code>/, 'py SHA-256 computed correctly');
unlike($h, qr/unsigned build/,              'no signing note without the exe');

# 3. exe + py -> two meta lines, both with SHA-256, signing note present
my $exedata = "MZ fake exe payload\n";
put($exe, $exedata);
$h = main::recorder_download_html();
like($h, qr/Download record_session\.exe \(Windows\)/,          'exe button shown');
like($h, qr/class="btn"[^>]*href="\/record_session\.exe"/,      'exe uses blue .btn + BASE_URL');
like($h, qr/SHA-256 <code>\Q${\ sha256_hex($exedata)}\E<\/code>/,'exe SHA-256 correct');
like($h, qr/SHA-256 <code>\Q${\ sha256_hex($pydata)}\E<\/code>/, 'py SHA-256 still present');
like($h, qr/<br>/,                                              'two meta lines (<br> separator)');
like($h, qr/unsigned build/,                                    'signing note shown with the exe');

# 4. the cache file is created in SESSION_DIR
my $cachef = File::Spec->catfile($dir, 'sessions', '.recorder-sha256');
ok(-f $cachef, 'SHA cache written to SESSION_DIR');

# 5. changing the file content + mtime invalidates the cached hash
my $newdata = "MZ different payload now\n";
put($exe, $newdata);
utime(time + 5, time + 5, $exe);          # bump mtime so the cache key changes
$h = main::recorder_download_html();
like($h,   qr/SHA-256 <code>\Q${\ sha256_hex($newdata)}\E<\/code>/, 'hash recomputed after change');
unlike($h, qr/\Q${\ sha256_hex($exedata)}\E/,                      'stale hash no longer shown');

done_testing();
