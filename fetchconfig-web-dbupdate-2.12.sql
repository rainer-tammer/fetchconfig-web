-- ===========================================================================
-- fetchconfig-web database update -- v2.12
--
-- Adds per-version line-change counts to the Backup Dashboard history, for the
-- Changes view's "recently changed" feed (magnitude, not just frequency):
--
--   backup_versions.lines_added    INTEGER  -- meaningful lines added vs the
--                                               previous stored version
--   backup_versions.lines_removed  INTEGER  -- meaningful lines removed
--
-- "Meaningful" = the engine's normalized, ignore-aware diff (volatile lines such
-- as an embedded timestamp do not count). Both columns are NULLABLE: NULL is a
-- baseline version (no predecessor) OR a row written before this change; 0 is a
-- real version whose only differences were ignored lines. The fetchconfig engine
-- (9.77+) writes them on the live save path and backfills them in --db-backfill;
-- fetchconfig-web only reads them.
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.12.sql
--
-- Or, preferred, let the setup tool do the schema AND the role/grants:
--
--   fetchconfig-web-dbsetup.pl --upgrade
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no "ADD COLUMN IF NOT EXISTS"
-- and no DO blocks, so the conditional, re-runnable logic runs inside a temporary
-- PL/pgSQL function. ADD COLUMN with no default does not rewrite the table and
-- does not block readers. The script is idempotent.
--
-- Privileges: schema objects only -- no GRANT, no CREATE ROLE here. The writer
-- role needs UPDATE on the two new columns to backfill existing rows:
--   GRANT UPDATE (lines_added, lines_removed) ON backup_versions TO <writer>;
-- fetchconfig-web-dbsetup.pl --upgrade issues it (the INSERT grant already covers
-- new rows). The web login stays SELECT-only.
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_212_upgrade() RETURNS void AS $upg$
BEGIN
    -- backup_versions must exist (created by the 2.11 update). If it does not,
    -- this install has never had the dashboard schema -- run the 2.11 update
    -- first (fetchconfig-web-dbsetup.pl --upgrade applies both, oldest first).
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'backup_versions';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'backup_versions is missing -- apply fetchconfig-web-dbupdate-2.11.sql first';
    END IF;

    -- lines_added ----------------------------------------------------------
    PERFORM 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'backup_versions'
          AND column_name = 'lines_added';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE backup_versions ADD COLUMN lines_added INTEGER';
    END IF;

    -- lines_removed --------------------------------------------------------
    PERFORM 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'backup_versions'
          AND column_name = 'lines_removed';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE backup_versions ADD COLUMN lines_removed INTEGER';
    END IF;

    -- record this migration ------------------------------------------------
    PERFORM 1 FROM schema_migrations WHERE id = '2.12';
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO schema_migrations (id, applied_at)
                 VALUES (''2.12'', EXTRACT(EPOCH FROM now())::bigint)';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_212_upgrade();
DROP FUNCTION fcweb_tmp_212_upgrade();

COMMIT;

-- Done. Grant the writer UPDATE on the new columns (see the header) or run
-- fetchconfig-web-dbsetup.pl --upgrade. The counts appear once the fetchconfig
-- engine (9.77+) writes/backfills them.
