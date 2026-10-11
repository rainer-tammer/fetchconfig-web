-- ===========================================================================
-- fetchconfig-web database update -- v1.62
--
-- Adds, to an existing fetchconfig-web database:
--   * users.download_full_config -- per-user right: download a device config
--                                   and copy it unmasked (like download_full_report)
--   * device_notes               -- one free-text note per device-id, with a
--                                   "keep" flag that protects it from the
--                                   orphaned-notes cleanup
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-1.62.sql
--
-- (Use the DBuser / DBinst values from /etc/fetchconfig-web.cfg.)
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks, no
-- "ADD COLUMN IF NOT EXISTS", no "CREATE TABLE IF NOT EXISTS" and no
-- "ON CONFLICT", so the conditional, re-runnable logic runs inside a temporary
-- PL/pgSQL function. The script is idempotent: running it more than once is
-- harmless.
--
-- PRIVILEGES: the web DB user (owner of the existing "users" table, i.e. the
-- account fetchconfig-web connects as) is granted exactly what the application
-- needs:
--   * users.download_full_config -- already covered by its existing rights on users
--   * device_notes               -- SELECT, INSERT, UPDATE, DELETE (notes are
--                                   created, edited and deleted at run time);
--                                   plus USAGE,SELECT on its id sequence
--
-- If you run this script as a different role than the web user (e.g. as
-- "postgres"), the new objects end up owned by that role; this script grants
-- the web user the privileges it needs. To grant them manually (replace
-- "fetchconfig" with your DBuser):
--
--   GRANT SELECT, INSERT, UPDATE, DELETE ON device_notes          TO fetchconfig;
--   GRANT USAGE, SELECT               ON SEQUENCE device_notes_id_seq TO fetchconfig;
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_162_upgrade() RETURNS void AS $upg$
DECLARE
    webuser TEXT;
BEGIN
    -- 1. users.download_full_config (nullable-safe: NOT NULL DEFAULT FALSE).
    --    8.2 has no ADD COLUMN IF NOT EXISTS, so check the catalog first.
    PERFORM 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'download_full_config';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE users ADD COLUMN download_full_config BOOLEAN NOT NULL DEFAULT FALSE';
    END IF;

    -- 2. device_notes -- one row per device-id (UNIQUE), free-text note, a
    --    "keep" flag that protects it from the orphaned-notes cleanup, and
    --    created/updated timestamps.
    PERFORM 1 FROM information_schema.sequences WHERE sequence_name = 'device_notes_id_seq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE SEQUENCE device_notes_id_seq START WITH 1 MINVALUE 1';
    END IF;
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'device_notes';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE device_notes (
                    note_id    INTEGER     NOT NULL PRIMARY KEY
                               DEFAULT nextval(''device_notes_id_seq''),
                    device_id  TEXT        NOT NULL,
                    note       TEXT        NOT NULL DEFAULT '''',
                    keep       BOOLEAN     NOT NULL DEFAULT FALSE,
                    created    TIMESTAMPTZ NOT NULL DEFAULT now(),
                    updated    TIMESTAMPTZ NOT NULL DEFAULT now()
                 )';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'device_notes_devid_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE UNIQUE INDEX device_notes_devid_idx ON device_notes (device_id)';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'device_notes_updated_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX device_notes_updated_idx ON device_notes (updated)';
    END IF;

    -- 3. Grant the web user what it needs on the new objects.
    SELECT tableowner INTO webuser FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'users';
    IF webuser IS NOT NULL THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON device_notes TO ' || quote_ident(webuser);
        EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE device_notes_id_seq TO ' || quote_ident(webuser);
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_162_upgrade();
DROP FUNCTION fcweb_tmp_162_upgrade();

COMMIT;

-- Done. Grant the new per-user right in User -> Users (Full config download),
-- and manage device notes via the paper-note icon, Device -> Notes, and
-- Tools -> Orphaned notes cleanup.
