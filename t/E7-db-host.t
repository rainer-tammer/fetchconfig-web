use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config(); load_cgi($cfg);

# --- db_host_parse: IPv6-capable bracket rule (mirrors the engine) -----------
is_deeply([main::db_host_parse('localhost')],           ['localhost', undef],      'bare host -> default port');
is_deeply([main::db_host_parse('localhost:5432')],      ['localhost', '5432'],     'host:port');
is_deeply([main::db_host_parse('db.example.com')],      ['db.example.com', undef], 'fqdn');
is_deeply([main::db_host_parse('db.example.com:6543')], ['db.example.com','6543'], 'fqdn:port');
is_deeply([main::db_host_parse('192.0.2.10')],          ['192.0.2.10', undef],     'ipv4');
is_deeply([main::db_host_parse('192.0.2.10:5432')],     ['192.0.2.10','5432'],     'ipv4:port');
is_deeply([main::db_host_parse('2001:db8::1')],         ['2001:db8::1', undef],    'bare IPv6 (>=2 colons) -> host, default port');
is_deeply([main::db_host_parse('[2001:db8::1]:5432')],  ['2001:db8::1','5432'],    'bracketed IPv6 with port');
is_deeply([main::db_host_parse('[2001:db8::1]')],       ['2001:db8::1', undef],    'bracketed IPv6 no port');
is_deeply([main::db_host_parse('  host:6543  ')],       ['host','6543'],           'whitespace trimmed');
is_deeply([main::db_host_parse('')],                    [undef, undef],            'empty');

# --- db_host_format: round-trips; bracket IPv6 only when a port is attached ---
is(main::db_host_format('localhost', undef),     'localhost',          'fmt host');
is(main::db_host_format('localhost', '5432'),    'localhost:5432',     'fmt host:port');
is(main::db_host_format('2001:db8::1', undef),   '2001:db8::1',        'fmt bare IPv6');
is(main::db_host_format('2001:db8::1', '5432'),  '[2001:db8::1]:5432', 'fmt IPv6 bracketed with port');

# round-trip through parse->format is stable for the port-bearing IPv6 case
{
    my ($h,$p) = main::db_host_parse('[2001:db8::1]:5432');
    is(main::db_host_format($h,$p), '[2001:db8::1]:5432', 'IPv6 round-trip');
}

# --- db_host_valid -----------------------------------------------------------
ok( main::db_host_valid('localhost'),            'valid host');
ok( main::db_host_valid('[2001:db8::1]:5432'),   'valid bracketed IPv6');
ok( main::db_host_valid('2001:db8::1'),          'valid bare IPv6');
ok(!main::db_host_valid(''),                     'empty invalid');
ok(!main::db_host_valid('host:0'),               'port 0 invalid');
ok(!main::db_host_valid('host:99999'),           'port > 65535 invalid');
ok(!main::db_host_valid('host:abc'),             'non-numeric port invalid');

# --- ENABLE_DASHBOARD config key wired in (source check, E6 style) -----------
{
    my $src = do { open(my $fh,'<',"$FindBin::Bin/../fetchconfig-web.cgi") or die $!; local $/; <$fh> };
    like($src, qr/\[\s*'ENABLE_DASHBOARD',\s*'bool',\s*'0'/, 'ENABLE_DASHBOARD registered (bool, default 0)');
    like($src, qr/\$ENABLE_DASHBOARD\s*=\s*\(defined \$kv->\{ENABLE_DASHBOARD\}/, 'ENABLE_DASHBOARD read in read_config');
}

done_testing();
