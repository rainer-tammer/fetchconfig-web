-- ===========================================================================
-- fetchconfig-web database update -- v2.19
--
-- Adds LDAP(S) authentication *configuration* (step 1: server management only;
-- wiring a user to a connection follows later):
--
--   * NEW TABLE ldap_servers  -- one row per configured directory (primary +
--     optional secondary host, encryption, timeout, and the uploaded root CA in
--     PEM). Web-owned auth config; contains NO secret (there is no bind/service
--     account -- authentication is a verbatim user bind -- and a root CA is a
--     public certificate).
--   * users.ldap_auth    BOOLEAN NOT NULL DEFAULT FALSE  -- this user logs in via LDAP
--   * users.ldap_server  INTEGER (nullable)              -- which ldap_servers row
--
-- The two users columns are additive with safe defaults, and NOTHING reads them
-- until the user-login step, so this migration is inert: existing users and the
-- current login path behave exactly as before. ldap_server is a plain INTEGER
-- (referential integrity is enforced in the application -- a server cannot be
-- deleted while a user references it) to avoid cross-table create ordering on a
-- fresh install and FK-owner issues on 8.2.
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.19.sql
--
-- Or, preferred, let the setup tool do it (it also issues the grants):
--
--   fetchconfig-web-dbsetup.pl --upgrade
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks and no
-- "ADD COLUMN IF NOT EXISTS" (9.6+), so the conditional, re-runnable logic runs
-- inside a temporary PL/pgSQL function that probes the catalog. Idempotent.
--
-- Privileges: the web role needs SELECT/INSERT/UPDATE/DELETE on ldap_servers and
-- USAGE/SELECT/UPDATE on its sequence. Those GRANTs are issued by
-- fetchconfig-web-dbsetup.pl --upgrade (do_grants), which knows the web user
-- name; this file touches schema objects only. Requires the base schema first.
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_219_upgrade() RETURNS void AS $upg$
BEGIN
    -- schema-version ledger (defensive: create if a standalone run on a legacy DB)
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'schema_migrations';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE schema_migrations (
                   id          TEXT   PRIMARY KEY,
                   applied_at  BIGINT)';
    END IF;

    -- ldap_servers: the connection config table ------------------------------
    PERFORM 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'ldap_servers';
    IF NOT FOUND THEN
        EXECUTE 'CREATE TABLE ldap_servers (
                   id           SERIAL   PRIMARY KEY,
                   name         TEXT     NOT NULL UNIQUE,
                   enabled      BOOLEAN  NOT NULL DEFAULT TRUE,
                   host1        TEXT     NOT NULL,
                   port1        INTEGER  NOT NULL DEFAULT 636,
                   host2        TEXT,
                   port2        INTEGER,
                   encryption   TEXT     NOT NULL DEFAULT ''ldaps'',
                   timeout_sec  INTEGER  NOT NULL DEFAULT 8,
                   ca_cert_pem  TEXT,
                   created_at   BIGINT,
                   created_by   TEXT,
                   updated_at   BIGINT,
                   updated_by   TEXT)';
    END IF;

    -- users.ldap_auth (nullable BOOLEAN defaulted FALSE; 8.2 has no
    -- ADD COLUMN IF NOT EXISTS, so probe the catalog first) ------------------
    PERFORM 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'ldap_auth';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE users ADD COLUMN ldap_auth BOOLEAN NOT NULL DEFAULT FALSE';
    END IF;

    -- users.ldap_server (nullable INTEGER; no DB-level FK by design) ---------
    PERFORM 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'ldap_server';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE users ADD COLUMN ldap_server INTEGER';
    END IF;

    -- record this migration ----------------------------------------------------
    PERFORM 1 FROM schema_migrations WHERE id = '2.19';
    IF NOT FOUND THEN
        EXECUTE 'INSERT INTO schema_migrations (id, applied_at)
                 VALUES (''2.19'', EXTRACT(EPOCH FROM now())::bigint)';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_219_upgrade();
DROP FUNCTION fcweb_tmp_219_upgrade();

COMMIT;

-- Done. Grants for the web role on ldap_servers (+ its sequence) are issued by
-- fetchconfig-web-dbsetup.pl --upgrade (do_grants). This migration is inert for
-- the current login path until the user-login step is added.
