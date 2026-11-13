-- ===========================================================================
-- fetchconfig-web database update -- v2.16
--
-- Adds one nullable column to the device inventory component table:
--
--   * device_inventory_component.fw_version  TEXT  -- firmware / ROMMON version
--
-- Written by the fetchconfig engine's SNMP inventory collector alongside the
-- existing sw_version / hw_rev. Purely additive: no data change, no grant change
-- (the column inherits the table's existing whole-table privileges).
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.16.sql
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
-- new column), so this file touches schema objects only. Requires 2.15 first.
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_216_upgrade() RETURNS void AS $upg$
BEGIN
    -- schema-version ledger (defensive: create if a standalone run on a legacy DB)
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'schema_migrations';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE schema_migrations (
                   id          TEXT   PRIMARY KEY,
                   applied_at  BIGINT)';
    END IF;

    -- device_inventory_component.fw_version (nullable; no ADD COLUMN IF NOT EXISTS
    -- on 8.2, so probe the catalog first) ------------------------------------
    PERFORM 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'device_inventory_component'
          AND column_name = 'fw_version';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE device_inventory_component ADD COLUMN fw_version TEXT';
    END IF;

    -- record this migration ----------------------------------------------------
    PERFORM 1 FROM schema_migrations WHERE id = '2.16';
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO schema_migrations (id, applied_at)
                 VALUES (''2.16'', EXTRACT(EPOCH FROM now())::bigint)';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_216_upgrade();
DROP FUNCTION fcweb_tmp_216_upgrade();

COMMIT;

-- Done. No grants to issue (the new column inherits the table's whole-table
-- privileges). fetchconfig-web-dbsetup.pl --upgrade records this level too.
