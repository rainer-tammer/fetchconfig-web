-- ===========================================================================
-- fetchconfig-web database update -- v2.11
--
-- Adds, to an existing fetchconfig-web database, the Backup Dashboard history
-- schema (written by the fetchconfig engine's optional DB writer, read by the
-- dashboard) plus a schema-version ledger:
--
--   * schema_migrations  -- records which dbupdate scripts have been applied
--   * backup_current     -- one row per device: latest run (dashboard Overview)
--   * backup_runs        -- one row per run: dense health history (trend)
--   * backup_versions    -- one row per saved backup: change history
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.11.sql
--
-- (Use the DBuser / DBinst values from /etc/fetchconfig-web.cfg.)
--
-- Or, preferred, let the setup tool do the schema AND the role/grants:
--
--   fetchconfig-web-dbsetup.pl --upgrade
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks and no
-- "CREATE TABLE/INDEX IF NOT EXISTS", so the conditional, re-runnable logic
-- runs inside a temporary PL/pgSQL function. The script is idempotent.
--
-- Privileges: this script creates SCHEMA OBJECTS ONLY. It issues no GRANT and
-- no CREATE ROLE -- the writer role name is not known at authoring time. Grant
-- with fetchconfig-web-dbsetup.pl --upgrade (which prompts for the writer name),
-- or by hand:
--   GRANT SELECT               ON backup_current, backup_runs, backup_versions TO <webuser>;
--   GRANT SELECT, INSERT       ON backup_current, backup_runs, backup_versions TO <writer>;
--   GRANT UPDATE               ON backup_current                                TO <writer>;
--   GRANT UPDATE (expired, expired_at) ON backup_versions                       TO <writer>;
-- The writer's SELECT is REQUIRED: the engine's pre-9.5 DML reads the tables
-- (INSERT ... WHERE NOT EXISTS, and the UPDATE WHERE/CASE expressions).
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_211_upgrade() RETURNS void AS $upg$
BEGIN
    -- schema-version ledger ------------------------------------------------
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'schema_migrations';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE schema_migrations (
                   id          TEXT   PRIMARY KEY,
                   applied_at  BIGINT)';
    END IF;

    -- backup_current -------------------------------------------------------
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'backup_current';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE backup_current (
                   dev_id         TEXT PRIMARY KEY,
                   repository     TEXT,
                   run_end        BIGINT,
                   state          TEXT,
                   changed        TEXT,
                   duration_sec   INTEGER,
                   size_bytes     BIGINT,
                   fail_reason    TEXT,
                   last_good_at   BIGINT,
                   last_good_size BIGINT)';
    END IF;

    -- backup_runs ----------------------------------------------------------
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'backup_runs';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE backup_runs (
                   dev_id        TEXT   NOT NULL,
                   run_end       BIGINT NOT NULL,
                   state         TEXT,
                   changed       TEXT,
                   duration_sec  INTEGER,
                   size_bytes    BIGINT,
                   fail_reason   TEXT,
                   repository    TEXT)';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'backup_runs_dev_run_uq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE UNIQUE INDEX backup_runs_dev_run_uq ON backup_runs (dev_id, run_end)';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'backup_runs_run_end_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX backup_runs_run_end_idx ON backup_runs (run_end)';
    END IF;

    -- backup_versions ------------------------------------------------------
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'backup_versions';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE backup_versions (
                   dev_id         TEXT   NOT NULL,
                   file_timestamp BIGINT NOT NULL,
                   path           TEXT,
                   size_bytes     BIGINT,
                   sha1           TEXT   NOT NULL,
                   expired        BOOLEAN NOT NULL DEFAULT FALSE,
                   expired_at     BIGINT)';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'backup_versions_dev_ts_uq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE UNIQUE INDEX backup_versions_dev_ts_uq ON backup_versions (dev_id, file_timestamp)';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'backup_versions_active_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX backup_versions_active_idx ON backup_versions (dev_id) WHERE expired = FALSE';
    END IF;

    -- record this migration ------------------------------------------------
    PERFORM 1 FROM schema_migrations WHERE id = '2.11';
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO schema_migrations (id, applied_at)
                 VALUES (''2.11'', EXTRACT(EPOCH FROM now())::bigint)';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_211_upgrade();
DROP FUNCTION fcweb_tmp_211_upgrade();

COMMIT;

-- Done. Grant privileges (see the header) or run
-- fetchconfig-web-dbsetup.pl --upgrade, then set ENABLE_DASHBOARD = 1 in
-- /etc/fetchconfig-web.cfg.
