-- ===========================================================================
-- fetchconfig-web database update -- v2.14
--
-- Privilege change for the fetchconfig engine's device-id RENAME feature
-- (engine 9.78's --rename-device-id). The rename updates the key column dev_id
-- in place in all three history tables:
--
--   UPDATE backup_current  SET dev_id = :new WHERE dev_id = :old;
--   UPDATE backup_runs     SET dev_id = :new WHERE dev_id = :old;
--   UPDATE backup_versions SET dev_id = :new WHERE dev_id = :old;
--
-- The writer role needs UPDATE on dev_id for this:
--   * backup_current  already has table-wide UPDATE (dev_id covered) -> no change;
--   * backup_runs     had SELECT+INSERT only                         -> add it;
--   * backup_versions had column-scoped UPDATE                       -> add dev_id.
--
-- Column-level GRANT ("GRANT UPDATE (col) ...") is PostgreSQL 8.4+ syntax. On
-- 8.2 / 8.3 it is a syntax error, so below 8.4 we fall back to a whole-table
-- "GRANT UPDATE" (the writer owns these tables anyway, so this does not widen
-- effective access). The version is detected at run time, so the 8.4+ syntax is
-- only ever parsed on an 8.4+ server.
--
-- This grants to the OWNER of backup_current (the fetchconfig writer role, set by
-- fetchconfig-web-dbsetup.pl: "ALTER TABLE ... OWNER TO <writer>"), so the script
-- does not need to be told the role name. It also records the 2.14 schema level
-- so the About dialog reports "DB schema 2.14".
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.14.sql
--
-- Or, preferred, let the setup tool do it (and refresh the role/grants):
--
--   fetchconfig-web-dbsetup.pl --upgrade
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks, so the
-- conditional logic runs inside a temporary PL/pgSQL function. Idempotent.
-- The web login stays SELECT-only -- only the writer role is granted UPDATE.
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_214_upgrade() RETURNS void AS $upg$
DECLARE
    owner_role text;
    pgver      integer;
BEGIN
    -- The history tables must exist (created by the 2.11 update). If they do
    -- not, this install has never had the dashboard schema -- run the earlier
    -- updates first (fetchconfig-web-dbsetup.pl --upgrade applies all, oldest
    -- first).
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'backup_versions';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'backup_versions is missing -- apply the 2.11 update first';
    END IF;

    -- Grant to the OWNER of backup_current (the fetchconfig writer role), so we
    -- need not know the configured role name here.
    SELECT pg_get_userbyid(c.relowner) INTO owner_role
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'backup_current' AND n.nspname = 'public';

    pgver := current_setting('server_version_num')::int;

    IF owner_role IS NOT NULL THEN
        -- backup_current already has table-wide UPDATE for the writer, so dev_id
        -- is already covered there -- nothing to do for it.
        IF pgver >= 80400 THEN
            -- 8.4+: column-scoped grants (least privilege).
            EXECUTE 'GRANT UPDATE (dev_id) ON backup_runs     TO ' || quote_ident(owner_role);
            EXECUTE 'GRANT UPDATE (dev_id) ON backup_versions TO ' || quote_ident(owner_role);
        ELSE
            -- pre-8.4: no column privileges -> whole-table UPDATE fallback.
            EXECUTE 'GRANT UPDATE ON backup_runs     TO ' || quote_ident(owner_role);
            EXECUTE 'GRANT UPDATE ON backup_versions TO ' || quote_ident(owner_role);
        END IF;
    END IF;

    -- record this migration ------------------------------------------------
    PERFORM 1 FROM schema_migrations WHERE id = '2.14';
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO schema_migrations (id, applied_at)
                 VALUES (''2.14'', EXTRACT(EPOCH FROM now())::bigint)';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_214_upgrade();
DROP FUNCTION fcweb_tmp_214_upgrade();

COMMIT;

-- Done. The device-id rename (engine 9.78 + fetchconfig-web 2.14) can now update
-- dev_id across backup_current / backup_runs / backup_versions. Prefer
-- fetchconfig-web-dbsetup.pl --upgrade, which also refreshes the writer grants.
