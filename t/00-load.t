use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path stub_libdir);

# The three Perl programs must at least compile. fetchconfig-web.cgi pulls in
# CGI/DBI/DBD::Pg/Algorithm::Diff, which may not be installed on the test box,
# so run its compile check with the stub library dir on @INC. The two helper
# scripts only use core modules.
my $stub = stub_libdir();
my %incs = (
    'fetchconfig-web.cgi'        => qq{-I"$stub" },
    'fetchconfig-web-dbsetup.pl' => qq{-I"$stub" },
    'imageconvert.pl'            => '',
);
for my $prog (sort keys %incs) {
    my $root = $FindBin::Bin . '/..';
    my $path = "$root/$prog";
  SKIP: {
        skip "$prog not present", 1 unless -f $path;
        my $out = `perl $incs{$prog}-c "$path" 2>&1`;
        like($out, qr/syntax OK/, "$prog compiles") or diag($out);
    }
}

# The CGI's functions load into the test harness.
my ($cfg) = make_config();
eval { load_cgi($cfg); 1 } or BAIL_OUT("load_cgi failed: $@");
ok(defined &main::read_config,   'read_config defined');
ok(defined &main::version_cmp,   'version_cmp defined');
ok(defined &main::mask_secrets,  'mask_secrets defined');
ok(defined &main::valid_id,      'valid_id defined');
is(main::read_config(), undef,   'read_config accepts a valid config');

done_testing();
