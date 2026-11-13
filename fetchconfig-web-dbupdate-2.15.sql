-- ===========================================================================
-- fetchconfig-web database update -- v2.15
--
-- Adds the Device Inventory schema (written by the fetchconfig engine's optional
-- SNMP inventory collector -- engine >= 9.79 -- read by a future dashboard page):
--
--   * device_inventory            -- one row per device: headline + tri-state status
--   * device_inventory_component  -- serial-bearing parts (snapshot-replaced)
--   * device_inventory_history    -- change-triggered audit (one row per change)
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.15.sql
--
-- (Use the DBuser / DBinst values from /etc/fetchconfig-web.cfg.)
--
-- Or, preferred, let the setup tool do the schema AND the role/grants:
--
--   fetchconfig-web-dbsetup.pl --upgrade
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks and no
-- "CREATE TABLE/INDEX/SEQUENCE IF NOT EXISTS", so the conditional, re-runnable
-- logic runs inside a temporary PL/pgSQL function. The script is idempotent.
--
-- Privileges: this script creates SCHEMA OBJECTS ONLY. It issues no GRANT and no
-- CREATE ROLE -- the writer role name is not known at authoring time. Grant with
-- fetchconfig-web-dbsetup.pl --upgrade (which owns the tables to the writer and
-- grants the web user SELECT), or by hand:
--   GRANT SELECT                       ON device_inventory, device_inventory_component,
--                                         device_inventory_history            TO <webuser>;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON device_inventory,
--                                         device_inventory_component          TO <writer>;
--   GRANT SELECT, INSERT, UPDATE        ON device_inventory_history           TO <writer>;
--   GRANT USAGE, UPDATE ON SEQUENCE device_inventory_component_id_seq,
--                                   device_inventory_history_id_seq           TO <writer>;
-- The writer's SELECT is REQUIRED: the engine's pre-9.5 DML reads the tables
-- (UPDATE ... WHERE, update-then-insert, INSERT ... WHERE NOT EXISTS).
--
-- Notes:
--  * All timestamps are naive local wall-clock epoch BIGINT (timegm on write,
--    gmtime on read -- never tz-convert), matching the backup-history schema.
--  * No FKs to backup_current / device_table: the tables share dev_id and are
--    maintained explicitly (the engine's op=rename updates all three in step).
--  * No bigserial shorthand (8.2 house style): explicit sequences feed the
--    component / history surrogate ids.
--  * The history idempotency key is a UNIQUE INDEX on (dev_id, changed_at).
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_215_upgrade() RETURNS void AS $upg$
BEGIN
    -- schema-version ledger (create if a standalone run on a legacy DB) --------
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'schema_migrations';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE schema_migrations (
                   id          TEXT   PRIMARY KEY,
                   applied_at  BIGINT)';
    END IF;

    -- device_inventory ---------------------------------------------------------
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'device_inventory';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE device_inventory (
                   dev_id          TEXT PRIMARY KEY,
                   status          TEXT NOT NULL,
                   source          TEXT,
                   vendor          TEXT,
                   vendor_raw      TEXT,
                   model           TEXT,
                   serial          TEXT,
                   os_version      TEXT,
                   member_count    SMALLINT,
                   hw_set          TEXT,
                   last_attempt_at BIGINT,
                   last_success_at BIGINT,
                   changed_at      BIGINT,
                   CONSTRAINT device_inventory_status_chk
                       CHECK (status IN (''disabled'', ''successful'', ''failed'')))';
    END IF;

    -- device_inventory_component (explicit sequence; no bigserial on 8.2) -------
    PERFORM 1 FROM pg_class WHERE relkind = 'S'
        AND relname = 'device_inventory_component_id_seq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE SEQUENCE device_inventory_component_id_seq START WITH 1 MINVALUE 1';
    END IF;
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'device_inventory_component';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE device_inventory_component (
                   id            BIGINT   NOT NULL PRIMARY KEY
                                          DEFAULT nextval(''device_inventory_component_id_seq''),
                   dev_id        TEXT     NOT NULL,
                   member_index  SMALLINT,
                   comp_class    TEXT     NOT NULL,
                   comp_position TEXT,
                   model         TEXT,
                   serial        TEXT     NOT NULL,
                   sw_version    TEXT,
                   hw_rev        TEXT,
                   is_primary    BOOLEAN  NOT NULL DEFAULT FALSE,
                   CONSTRAINT device_inventory_component_class_chk
                       CHECK (comp_class IN (''chassis'', ''module'', ''powerSupply'', ''transceiver'')))';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i'
        AND relname = 'device_inventory_component_dev_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX device_inventory_component_dev_idx
                   ON device_inventory_component (dev_id)';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i'
        AND relname = 'device_inventory_component_serial_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX device_inventory_component_serial_idx
                   ON device_inventory_component (serial)';
    END IF;

    -- device_inventory_history -------------------------------------------------
    PERFORM 1 FROM pg_class WHERE relkind = 'S'
        AND relname = 'device_inventory_history_id_seq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE SEQUENCE device_inventory_history_id_seq START WITH 1 MINVALUE 1';
    END IF;
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'device_inventory_history';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE device_inventory_history (
                   id             BIGINT NOT NULL PRIMARY KEY
                                         DEFAULT nextval(''device_inventory_history_id_seq''),
                   dev_id         TEXT   NOT NULL,
                   changed_at     BIGINT,
                   hw_set         TEXT,
                   member_serials TEXT,
                   os_version     TEXT,
                   note           TEXT)';
    END IF;
    -- Replay-idempotency key for op=inv history (one row per device per run).
    PERFORM 1 FROM pg_class WHERE relkind = 'i'
        AND relname = 'device_inventory_history_dev_ts_uq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE UNIQUE INDEX device_inventory_history_dev_ts_uq
                   ON device_inventory_history (dev_id, changed_at)';
    END IF;

    -- record this migration ----------------------------------------------------
    PERFORM 1 FROM schema_migrations WHERE id = '2.15';
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO schema_migrations (id, applied_at)
                 VALUES (''2.15'', EXTRACT(EPOCH FROM now())::bigint)';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_215_upgrade();
DROP FUNCTION fcweb_tmp_215_upgrade();

COMMIT;

-- Done. Grant privileges (see the header) or run
-- fetchconfig-web-dbsetup.pl --upgrade, which owns the tables to the writer role
-- and grants the web user SELECT. The inventory UI is a later release.
