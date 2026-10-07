-- ===========================================================================
-- fetchconfig-web database update -- per-site device access + audit log (v1.50, v1.51)
--
-- Adds the site-based access-control tables and columns to an existing
-- fetchconfig-web database. Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-1.50.sql
--
-- (Use the DBuser / DBinst values from /etc/fetchconfig-web.cfg.)
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks, no
-- "IF NOT EXISTS" and no "ON CONFLICT", so the conditional, re-runnable logic
-- runs inside a temporary PL/pgSQL function. The script is idempotent: running
-- it more than once is harmless.
--
-- PL/pgSQL must be available. On PostgreSQL 9.0+ it is installed by default. On
-- 8.2 it may not be; the first statement below installs it and TOLERATES the
-- "already exists" error via the psql meta-commands around it (so a fresh 8.2
-- database and a database that already has plpgsql both work). These
-- backslash commands are psql features and must be run through psql.
--
-- If you run this script as a different role than the web user (e.g. as
-- "postgres"), the new tables end up owned by that role. This script already
-- grants the web user the privileges it needs. If you created the tables some
-- other way and the web UI cannot add/edit sites, grant them manually (replace
-- "fetchconfig" with your DBuser):
--
--   GRANT SELECT, INSERT, UPDATE, DELETE ON sites      TO fetchconfig;
--   GRANT SELECT, INSERT, UPDATE, DELETE ON user_sites TO fetchconfig;
--   GRANT USAGE, SELECT, UPDATE ON SEQUENCE sites_id_seq TO fetchconfig;
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

-- All schema changes, made idempotent by catalog checks, inside one PL/pgSQL
-- function that is created, run once and dropped.
CREATE OR REPLACE FUNCTION fcweb_tmp_upgrade() RETURNS void AS $upg$
DECLARE
    webuser TEXT;
BEGIN
    -- 1. Per-user "download full report" right (default off).
    PERFORM 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'download_full_report';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE users
                 ADD COLUMN download_full_report BOOLEAN NOT NULL DEFAULT FALSE';
    END IF;

    -- 2. Site code table. ID 0 is the reserved "All sites" sentinel: a user who
    --    holds site 0 is unrestricted, and a device with no site (shown as
    --    "any site") belongs to site 0.
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'sites';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE sites (
                    id           INTEGER  PRIMARY KEY,
                    code         TEXT     NOT NULL UNIQUE,
                    description  TEXT     NOT NULL DEFAULT ''''
                 )';
    END IF;

    -- Seed the reserved "All sites" sentinel (id 0, code ''*'').
    PERFORM 1 FROM sites WHERE id = 0;
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO sites (id, code, description)
                 VALUES (0, ''*'', ''All sites'')';
    END IF;

    -- A sequence for new site ids (id 0 is reserved, so start at 1).
    PERFORM 1 FROM pg_class WHERE relkind = 'S' AND relname = 'sites_id_seq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE SEQUENCE sites_id_seq START WITH 1 MINVALUE 1';
    END IF;
    -- Keep the sequence ahead of any existing rows.
    PERFORM setval('sites_id_seq',
                   GREATEST((SELECT COALESCE(MAX(id), 0) FROM sites), 1));

    -- 3. User <-> site assignment. Deleting a user removes their rows; a site
    --    that is still assigned cannot be deleted (RESTRICT).
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'user_sites';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE user_sites (
                    username  TEXT     NOT NULL REFERENCES users(username) ON DELETE CASCADE,
                    site_id   INTEGER  NOT NULL REFERENCES sites(id)       ON DELETE RESTRICT,
                    PRIMARY KEY (username, site_id)
                 )';
    END IF;

    -- 4. Start every EXISTING user as unrestricted (site 0), so nobody is
    --    locked out by the upgrade. Administrators then tighten assignments on
    --    the User page. (Only inserts the rows that are missing.)
    EXECUTE 'INSERT INTO user_sites (username, site_id)
             SELECT u.username, 0 FROM users u
             WHERE NOT EXISTS (SELECT 1 FROM user_sites s
                               WHERE s.username = u.username AND s.site_id = 0)';

    -- 5. Grant the web user (the owner of the existing "users" table, i.e. the
    --    account fetchconfig-web connects as) the privileges it needs on the
    --    new objects. This matters when this script is run by a different role
    --    (e.g. postgres), which would otherwise own the new tables and leave
    --    the web user unable to write to them.
    SELECT tableowner INTO webuser FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'users';
    IF webuser IS NOT NULL THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON sites TO ' || quote_ident(webuser);
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON user_sites TO ' || quote_ident(webuser);
        EXECUTE 'GRANT USAGE, SELECT, UPDATE ON SEQUENCE sites_id_seq TO ' || quote_ident(webuser);
    END IF;

    -- 6. Audit log (v1.51): append-only audit_log + its sequence/indexes, plus
    --    the mutable app_state key/value table. audit_log is granted INSERT +
    --    SELECT only (Level B immutability: the web user cannot alter/erase it).
    PERFORM 1 FROM pg_class WHERE relkind = 'S' AND relname = 'audit_log_id_seq';
    IF NOT FOUND THEN
        EXECUTE 'CREATE SEQUENCE audit_log_id_seq START WITH 1 MINVALUE 1';
    END IF;
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
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_ts_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_ts_idx     ON audit_log (ts)';       END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_user_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_user_idx   ON audit_log (username)'; END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_action_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_action_idx ON audit_log (action)';   END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'audit_log_object_idx';
    IF NOT FOUND THEN EXECUTE 'CREATE INDEX audit_log_object_idx ON audit_log (object_id)';END IF;
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'app_state';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE app_state (
                    key       TEXT        PRIMARY KEY,
                    value     TEXT,
                    username  TEXT,
                    ts        TIMESTAMPTZ
                 )';
    END IF;
    IF webuser IS NOT NULL THEN
        EXECUTE 'GRANT SELECT, INSERT ON audit_log TO ' || quote_ident(webuser);
        EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO ' || quote_ident(webuser);
        EXECUTE 'GRANT SELECT, INSERT, UPDATE ON app_state TO ' || quote_ident(webuser);
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_upgrade();
DROP FUNCTION fcweb_tmp_upgrade();

COMMIT;

-- Done. Review per-user site assignments on the User page and tighten as needed.
