use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(cgi_path);

# --------------------------------------------------------------------------
# Device Inventory DB (schema 2.15): the three tables the fetchconfig engine's
# SNMP inventory collector (engine 9.79+) writes via the backup-history outbox.
# This release is DB + setup-tool + docs only (no UI), so the checks are on the
# migration SQL, the dbsetup wiring/grants and the version bump -- plus, when a
# throwaway DSN is provided (FCW_TEST_DSN), a live apply + idempotency check.
# --------------------------------------------------------------------------

# --- version bump ---------------------------------------------------------
my $cgi = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };
like($cgi, qr/APP_VERSION\s*=>\s*'2\.17\.15'/,          'APP_VERSION 2.17.15');
like($cgi, qr/APP_VERSION_INTERNAL\s*=>\s*'2\.17\.15'/, 'APP_VERSION_INTERNAL 2.17.15');

# --- migration file -------------------------------------------------------
ok(-f 'fetchconfig-web-dbupdate-2.15.sql', 'the 2.15 migration file exists');
my $sql = do { local $/; open(my $f, '<', 'fetchconfig-web-dbupdate-2.15.sql') or die $!; <$f> };

# 8.2-safe shape (same conventions as 2.11): temp PL/pgSQL fn, catalog checks,
# no bigserial / IF NOT EXISTS / to_regclass / ON CONFLICT. Check the DDL only --
# the header comment deliberately names these constructs to say it avoids them.
my $code = $sql; $code =~ s/--[^\n]*//g;
like($sql,    qr/CREATE OR REPLACE FUNCTION fcweb_tmp_215_upgrade/, 'temp PL/pgSQL upgrade function');
like($sql,    qr/information_schema\.tables|pg_class/,              'catalog existence checks');
unlike($code, qr/\bIF NOT EXISTS\b/i,                              'no IF NOT EXISTS (8.2-unsafe)');
unlike($code, qr/\bbigserial\b/i,                                  'no bigserial shorthand (explicit sequences)');
unlike($code, qr/to_regclass/i,                                    'no to_regclass (9.4+)');
unlike($code, qr/ON CONFLICT/i,                                    'no ON CONFLICT (9.5+)');

# the three tables + explicit sequences (8.2 house style)
like($sql, qr/CREATE TABLE device_inventory \(/,                  'creates device_inventory');
like($sql, qr/CREATE TABLE device_inventory_component \(/,        'creates device_inventory_component');
like($sql, qr/CREATE TABLE device_inventory_history \(/,          'creates device_inventory_history');
like($sql, qr/CREATE SEQUENCE device_inventory_component_id_seq/, 'explicit component sequence');
like($sql, qr/CREATE SEQUENCE device_inventory_history_id_seq/,   'explicit history sequence');

# tri-state status + comp_class CHECKs (quotes doubled inside EXECUTE '...')
like($sql, qr/CHECK \(status IN \(''disabled'', ''successful'', ''failed''\)\)/, 'status tri-state CHECK');
like($sql, qr/CHECK \(comp_class IN \(''chassis'', ''module'', ''powerSupply'', ''transceiver''\)\)/, 'comp_class CHECK');

# reserved-word avoidance + key columns
like($sql,   qr/\bcomp_position\b/,     'locator column is comp_position (position is reserved)');
unlike($sql, qr/^\s*position\s+TEXT/mi, 'no unquoted reserved "position" column');
like($sql,   qr/\bhw_set\b/,            'hw_set change token present');

# history idempotency key + component indexes
like($sql, qr/CREATE UNIQUE INDEX device_inventory_history_dev_ts_uq\s+ON device_inventory_history \(dev_id, changed_at\)/, 'history UNIQUE(dev_id, changed_at)');
like($sql, qr/CREATE INDEX device_inventory_component_dev_idx/,    'component dev_id index');
like($sql, qr/CREATE INDEX device_inventory_component_serial_idx/, 'component serial index');

# records the ledger id; schema only (no executable GRANT in the .sql)
like($sql,   qr/INSERT INTO schema_migrations.*2\.15/s, 'migration records the 2.15 ledger id');
unlike($sql, qr/EXECUTE 'GRANT/i,                       'migration issues no GRANT (grants live in dbsetup)');

# --- dbsetup wiring + grants ---------------------------------------------
my $ds = do { local $/; open(my $f, '<', 'fetchconfig-web-dbsetup.pl') or die $!; <$f> };
like($ds, qr/'2\.15', 'fetchconfig-web-dbupdate-2\.15\.sql'/,  '@UPDATES registers the 2.15 migration');
like($ds, qr/tbl_exists\(\$_\[0\], 'device_inventory'\)/,      '2.15 signature probes device_inventory');
like($ds, qr/qw\(device_inventory device_inventory_component device_inventory_history\)/, 'ownership loop covers the three inventory tables');
# 8.2-safe: "ALTER SEQUENCE ... OWNER TO" is 8.3+, so a sequence's owner is set
# via "ALTER TABLE <seq> OWNER TO" (works on all versions incl. 8.2).
like($ds, qr/ALTER TABLE \$s OWNER TO \$qw/,                   'inventory sequences owned by the writer (ALTER TABLE, 8.2-safe)');
unlike($ds, qr/ALTER SEQUENCE \$s OWNER TO/,                   'no ALTER SEQUENCE OWNER TO (8.3+ only)');
like($ds, qr/seq_exists\(\$dbh, \$s\)/,                        'sequence ownership guarded by an existence check');
like($ds, qr/GRANT SELECT ON device_inventory, device_inventory_component, device_inventory_history TO \$qu/, 'web user SELECT on all three');
like($ds, qr/GRANT SELECT, INSERT, UPDATE, DELETE ON device_inventory, device_inventory_component TO \$qw/,  'writer full DML on inventory + component');
like($ds, qr/GRANT SELECT, INSERT, UPDATE ON device_inventory_history TO \$qw/, 'writer SELECT+INSERT+UPDATE (no DELETE) on history');
like($ds, qr/GRANT USAGE, UPDATE ON SEQUENCE device_inventory_component_id_seq, device_inventory_history_id_seq TO \$qw/, 'writer USAGE+UPDATE on both sequences');

# --- 2.17: device_inventory sysname/syslocation/syscontact ----------------
ok(-f 'fetchconfig-web-dbupdate-2.17.sql', 'the 2.17 migration file exists');
my $sql17 = do { local $/; open(my $f, '<', 'fetchconfig-web-dbupdate-2.17.sql') or die $!; <$f> };
(my $sql17_code = $sql17) =~ s/^\s*--.*$//mg;   # drop -- comment lines before the "avoids X" checks
like($sql17, qr/CREATE OR REPLACE FUNCTION fcweb_tmp_217_upgrade/, '2.17 uses the temp-function pattern (8.2-safe)');
unlike($sql17_code, qr/\bDO\b\s*\$|IF NOT EXISTS/,                  '2.17 avoids DO blocks / IF NOT EXISTS DDL (8.2)');
like($sql17, qr/information_schema\.columns/,                       '2.17 probes the catalog before ADD COLUMN');
like($sql17, qr/ALTER TABLE device_inventory ADD COLUMN sysname\s+TEXT/,     '2.17 adds sysname');
like($sql17, qr/ALTER TABLE device_inventory ADD COLUMN syslocation\s+TEXT/, '2.17 adds syslocation');
like($sql17, qr/ALTER TABLE device_inventory ADD COLUMN syscontact\s+TEXT/,  '2.17 adds syscontact');
like($sql17, qr/schema_migrations.*'2\.17'/s,                       '2.17 records its ledger id');
unlike($sql17_code, qr/\bGRANT\b/,                                  '2.17 issues no GRANT (columns inherit table privileges)');
like($ds, qr/'2\.17', 'fetchconfig-web-dbupdate-2\.17\.sql'/,       '@UPDATES registers the 2.17 migration');
like($ds, qr/col_exists\(\$_\[0\], 'device_inventory', 'sysname'\)/,'2.17 signature probes device_inventory.sysname');

# --- optional live-DB apply + idempotency (set FCW_TEST_DSN) --------------
SKIP: {
    my $dsn = $ENV{FCW_TEST_DSN};
    skip 'set FCW_TEST_DSN to run the live migration test', 3 unless $dsn;
    eval { require DBI; 1 } or skip 'DBI not available', 3;
    my $dbh = DBI->connect($dsn, $ENV{FCW_TEST_DBUSER}, $ENV{FCW_TEST_DBPASS},
                           { RaiseError => 0, PrintError => 0, AutoCommit => 1 });
    skip 'cannot connect to FCW_TEST_DSN', 3 unless $dbh;
    # Apply like the tool's run_sql_file_dbi: strip psql meta lines, run the
    # plpgsql guard separately (tolerate "already exists"), then the rest.
    my $s = $sql;
    $s =~ s/^[ \t]*\\[^\n]*\n?//mg;
    $s =~ s/^[ \t]*CREATE\s+LANGUAGE\s+plpgsql\s*;//im;
    $dbh->do('CREATE LANGUAGE plpgsql');
    ok($dbh->do($s), 'live: migration applies') or diag($dbh->errstr);
    my ($id) = $dbh->selectrow_array("SELECT id FROM schema_migrations WHERE id = '2.15'");
    is($id, '2.15', 'live: ledger records 2.15');
    ok($dbh->do($s), 'live: migration is idempotent on re-run') or diag($dbh->errstr);
    $dbh->disconnect;
}

done_testing();
