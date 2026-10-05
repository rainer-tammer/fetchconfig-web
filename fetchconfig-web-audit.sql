-- ===========================================================================
-- fetchconfig-web database update -- audit log (v1.51)
--
-- Adds the append-only audit_log table (with its sequence and indexes) and the
-- small mutable app_state key/value table to an existing fetchconfig-web
-- database. Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-audit.sql
--
-- (Use the DBuser / DBinst values from /etc/fetchconfig-web.cfg.)
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks, no
-- "IF NOT EXISTS" and no "ON CONFLICT", so the conditional, re-runnable logic
-- runs inside a temporary PL/pgSQL function. The script is idempotent: running
-- it more than once is harmless.
--
-- IMMUTABILITY: the web DB user is granted INSERT + SELECT on audit_log only
-- (no UPDATE/DELETE). It can write and read the log but cannot alter or erase
-- it; only a DBA/superuser can. Retention/pruning, if any, is therefore a DBA
-- task by design -- the application can never delete audit rows.
--
-- If you run this script as a different role than the web user (e.g. as
-- "postgres"), the new objects end up owned by that role. This script already
-- grants the web user the privileges it needs. If you created the objects some
-- other way and the audit tool cannot write, grant them manually (replace
-- "fetchconfig" with your DBuser):
--
--   GRANT SELECT, INSERT ON audit_log            TO fetchconfig;
--   GRANT USAGE, SELECT  ON SEQUENCE audit_log_id_seq TO fetchconfig;
--   GRANT SELECT, INSERT, UPDATE ON app_state    TO fetchconfig;
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

-- All schema changes, made idempotent by catalog checks, inside one PL/pgSQL
-- function that is created, run once and dropped.
CREATE OR REPLACE FUNCTION fcweb_tmp_audit_upgrade() RETURNS void AS $upg$
DECLARE
    webuser TEXT;
BEGIN
    -- 1. Sequence feeding audit_log.id (8.2: no bigserial shorthand).
    PERFORM 1 FROM pg_class WHERE relkind = 'S' AND relname = 'audit_log_id_seq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE SEQUENCE audit_log_id_seq START WITH 1 MINVALUE 1';
    END IF;

    -- 2. The append-only audit log.
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'audit_log';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE audit_log (
                    id           BIGINT      NOT NULL PRIMARY KEY
                                             DEFAULT nextval(''audit_log_id_seq''),
                    ts           TIMESTAMPTZ NOT NULL DEFAULT now(),
                    username     TEXT,
                    ip           TEXT,
                    action       TEXT        NOT NULL,
                    object_type  TEXT,
                    object_id    TEXT,
                    field        TEXT,
                    old_value    TEXT,
                    new_value    TEXT,
                    detail       TEXT
                 )';
    END IF;

    -- 3. Indexes for the viewer's filters (by time, user, action, object).
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_ts_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_ts_idx     ON audit_log (ts)';       END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_user_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_user_idx   ON audit_log (username)'; END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_action_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_action_idx ON audit_log (action)';   END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_object_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_object_idx ON audit_log (object_id)';END IF;

    -- 4. Small mutable key/value table (device-table change tripwire token, ...).
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'app_state';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE app_state (
                    key       TEXT        PRIMARY KEY,
                    value     TEXT,
                    username  TEXT,
                    ts        TIMESTAMPTZ
                 )';
    END IF;

    -- 5. Grant the web user (owner of the existing "users" table, i.e. the
    --    account fetchconfig-web connects as) exactly the privileges it needs.
    --    Level B: audit_log is INSERT + SELECT only (NO update/delete).
    SELECT tableowner INTO webuser FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'users';
    IF webuser IS NOT NULL THEN
        EXECUTE 'GRANT SELECT, INSERT ON audit_log TO ' || quote_ident(webuser);
        EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO ' || quote_ident(webuser);
        EXECUTE 'GRANT SELECT, INSERT, UPDATE ON app_state TO ' || quote_ident(webuser);
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_audit_upgrade();
DROP FUNCTION fcweb_tmp_audit_upgrade();

COMMIT;

-- Done. The Tools -> Audit log page (admin only) shows the log.
