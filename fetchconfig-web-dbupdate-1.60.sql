-- ===========================================================================
-- fetchconfig-web database update -- v1.60
--
-- Adds, to an existing fetchconfig-web database:
--   * users.email           -- optional per-user email address (password reset)
--   * login_attempts        -- online login throttle counters (B1)
--   * password_resets        -- one-time password-reset tokens (hashed)
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-1.60.sql
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
--   * users.email          -- already covered by its existing rights on users
--   * login_attempts        -- SELECT, INSERT, UPDATE, DELETE (counters are
--                             created, incremented and cleared at run time)
--   * password_resets        -- SELECT, INSERT, UPDATE (create a token, look it
--                             up, mark it used; rows are pruned by a DBA tool,
--                             not the web user -- no DELETE here)
--
-- If you run this script as a different role than the web user (e.g. as
-- "postgres"), the new objects end up owned by that role; this script grants
-- the web user the privileges it needs. To grant them manually (replace
-- "fetchconfig" with your DBuser):
--
--   GRANT SELECT, INSERT, UPDATE, DELETE ON login_attempts  TO fetchconfig;
--   GRANT SELECT, INSERT, UPDATE         ON password_resets TO fetchconfig;
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_160_upgrade() RETURNS void AS $upg$
DECLARE
    webuser TEXT;
BEGIN
    -- 1. users.email (nullable). 8.2 has no ADD COLUMN IF NOT EXISTS, so check
    --    the catalog first.
    PERFORM 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'email';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE users ADD COLUMN email TEXT';
    END IF;

    -- 2. login_attempts -- one row per (kind, keyval), kind in ('ip','user').
    --    failures is the count within the rolling window; last_fail is the
    --    most recent failure time. The application reads/updates/clears these.
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'login_attempts';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE login_attempts (
                    kind       TEXT        NOT NULL,
                    keyval     TEXT        NOT NULL,
                    failures   INTEGER     NOT NULL DEFAULT 0,
                    last_fail  TIMESTAMPTZ NOT NULL DEFAULT now(),
                    PRIMARY KEY (kind, keyval)
                 )';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'login_attempts_last_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX login_attempts_last_idx ON login_attempts (last_fail)';
    END IF;

    -- 3. password_resets -- one row per issued reset token. Only the token HASH
    --    is stored (the usable token is emailed, never kept). Single-use via
    --    the "used" flag; expires at "expires".
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'password_resets';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE password_resets (
                    token_hash TEXT        NOT NULL PRIMARY KEY,
                    username   TEXT        NOT NULL,
                    created    TIMESTAMPTZ NOT NULL DEFAULT now(),
                    expires    TIMESTAMPTZ NOT NULL,
                    used       BOOLEAN     NOT NULL DEFAULT FALSE
                 )';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'password_resets_user_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX password_resets_user_idx ON password_resets (username)';
    END IF;
    PERFORM 1 FROM pg_class WHERE relkind = 'i' AND relname = 'password_resets_exp_idx';
    IF NOT FOUND THEN
        EXECUTE 'CREATE INDEX password_resets_exp_idx ON password_resets (expires)';
    END IF;

    -- 4. Grant the web user exactly the privileges it needs on the new tables.
    SELECT tableowner INTO webuser FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'users';
    IF webuser IS NOT NULL THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON login_attempts  TO ' || quote_ident(webuser);
        EXECUTE 'GRANT SELECT, INSERT, UPDATE         ON password_resets TO ' || quote_ident(webuser);
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_160_upgrade();
DROP FUNCTION fcweb_tmp_160_upgrade();

COMMIT;

-- Done. Set per-user email addresses in Tools/User -> Users, enable password
-- reset email in /etc/fetchconfig-web.cfg (EMAIL = 1 plus the SMTP_* settings),
-- and prune old reset/throttle rows periodically with
-- fetchconfig-web-clean-resets.pl.
