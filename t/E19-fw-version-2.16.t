use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.16 schema: device_inventory_component.fw_version (firmware/ROMMON version).
# Additive, 8.2-safe, nullable, no grant change. Surfaced in the Components view
# after SW, gated on the column being present so the viewer still works at 2.15.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# --- migration SQL ---------------------------------------------------------
my $sqlf = $FindBin::Bin . '/../fetchconfig-web-dbupdate-2.16.sql';
my $sql  = do { open(my $f, '<', $sqlf) or die "no 2.16 sql: $!"; local $/; <$f> };
my $sqlc = $sql; $sqlc =~ s/--[^\n]*//g;   # strip comments before 8.2-safety checks

like($sql,  qr/ADD COLUMN fw_version TEXT/,            '2.16 adds fw_version TEXT');
like($sql,  qr/information_schema\.columns/,           'idempotent: probes the catalog first');
like($sql,  qr/fcweb_tmp_216_upgrade/,                 'runs inside a temp PL/pgSQL function (8.2-safe)');
like($sql,  qr/schema_migrations.*2\.16|'2\.16'/s,     'records schema level 2.16');
unlike($sqlc, qr/ADD COLUMN IF NOT EXISTS/i,           'no ADD COLUMN IF NOT EXISTS (9.6+ only)');
unlike($sqlc, qr/\bGRANT\b/i,                          'no GRANT in the 2.16 migration (additive, inherits table grants)');
unlike($sqlc, qr/\bDO\b\s*\$/i,                        'no DO blocks (8.2-unsafe)');

# --- dbsetup registration --------------------------------------------------
my $dsf = $FindBin::Bin . '/../fetchconfig-web-dbsetup.pl';
my $ds  = do { open(my $f, '<', $dsf) or die $!; local $/; <$f> };
like($ds, qr/'2\.16',\s*'fetchconfig-web-dbupdate-2\.16\.sql'/, 'dbsetup \@UPDATES has the 2.16 entry');
like($ds, qr/col_exists\(\$_\[0\], 'device_inventory_component', 'fw_version'\)/,
     '2.16 signature probes the fw_version column');

# --- viewer surfaces the column, gated on presence -------------------------
like($src, qr/db_column_exists\(\$dbh, 'device_inventory_component', 'fw_version'\)/, 'viewer probes for the fw_version column');
like($src, qr/\$has_fw \? qq\{<th>FW version<\/th>\}/, 'FW version header shown only when present');
# header order: SW, then (FW version), then HW rev
like($src, qr/<th>SW<\/th>\}\s*\n\s*\.\s*\(\$has_fw \? qq\{<th>FW version<\/th>\} : qq\{\}\)\s*\n\s*\.\s*qq\{<th>HW rev<\/th>/,
     'FW version column sits between SW and HW rev');
# the SELECT only names fw_version when the column is present
like($src, qr/sw_version, \} \. \(\$has_fw \? qq\{fw_version, \}/,
     'fw_version is added to the SELECT list only when present');

# --- About dialog reads the DB schema level FRESH (not a process cache) -----
# A process-lifetime cache showed a stale level under FastCGI after --upgrade.
ok(defined &main::db_schema_version,          'db_schema_version() defined');
ok(!defined &main::db_schema_version_cached,  'old cached schema-version accessor removed');
unlike($src, qr/\$_db_schema_version_set/,    'no process-lifetime cache flag for the schema version');
like($src, qr/my \$schema = db_schema_version\(\)/, 'About reads the schema level fresh each view');

done_testing();
