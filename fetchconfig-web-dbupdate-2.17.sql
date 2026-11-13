-- ===========================================================================
-- fetchconfig-web database update -- v2.17
--
-- Adds three nullable columns to the device inventory headline table:
--
--   * device_inventory.sysname      TEXT  -- SNMPv2-MIB sysName.0     (1.3.6.1.2.1.1.5.0)
--   * device_inventory.syslocation  TEXT  -- SNMPv2-MIB sysLocation.0 (1.3.6.1.2.1.1.6.0)
--   * device_inventory.syscontact   TEXT  -- SNMPv2-MIB sysContact.0  (1.3.6.1.2.1.1.4.0)
--
-- Written by the fetchconfig engine's SNMP inventory collector in the same
-- system-group GET it already does for sysObjectID / sysDescr -- no extra round
-- trip, available for every device that answers SNMP. These are device-level
-- current-state facts (the device's own configured name/location/contact), so
-- they live on the one-per-device headline row, NOT on the component or history
-- tables, and they do NOT participate in change detection. Purely additive: no
-- data change, no grant change (the columns inherit the table's whole-table
-- privileges).
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.17.sql
--
-- Or, preferred, let the setup tool do it:
--
--   fetchconfig-web-dbsetup.pl --upgrade
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks and no
-- "ADD COLUMN IF NOT EXISTS" (9.6+), so the conditional, re-runnable logic runs
-- inside a temporary PL/pgSQL function that probes information_schema.columns.
-- The script is idempotent.
--
-- Privileges: NONE issued here. "ALTER TABLE ... ADD COLUMN" needs no new GRANT
-- (SELECT / INSERT / UPDATE / DELETE already granted on the whole table cover the
-- new columns), so this file touches schema objects only. Requires 2.15 first.
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_217_upgrade() RETURNS void AS $upg$
BEGIN
    -- schema-version ledger (defensive: create if a standalone run on a legacy DB)
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'schema_migrations';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE schema_migrations (
                   id          TEXT   PRIMARY KEY,
                   applied_at  BIGINT)';
    END IF;

    -- device_inventory system-group columns (nullable; no ADD COLUMN IF NOT EXISTS
    -- on 8.2, so probe the catalog first). The three are added together; one guard
    -- keyed on sysname is enough. --------------------------------------------
    PERFORM 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'device_inventory'
          AND column_name = 'sysname';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE device_inventory ADD COLUMN sysname     TEXT';
        EXECUTE 'ALTER TABLE device_inventory ADD COLUMN syslocation TEXT';
        EXECUTE 'ALTER TABLE device_inventory ADD COLUMN syscontact  TEXT';
    END IF;

    -- record this migration ----------------------------------------------------
    PERFORM 1 FROM schema_migrations WHERE id = '2.17';
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO schema_migrations (id, applied_at)
                 VALUES (''2.17'', EXTRACT(EPOCH FROM now())::bigint)';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_217_upgrade();
DROP FUNCTION fcweb_tmp_217_upgrade();

COMMIT;

-- Done. No grants to issue (the new columns inherit the table's whole-table
-- privileges). fetchconfig-web-dbsetup.pl --upgrade records this level too.
