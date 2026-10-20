-- ===========================================================================
-- fetchconfig-web database update -- v2.08
--
-- Adds, to an existing fetchconfig-web database:
--   * users.read_debug -- per-user right: view device debug logs
--                         (<repository>/<device-id>.debug) for the devices
--                         the user can already see.
--
-- Run it once with psql:
--
--   psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate-2.08.sql
--
-- (Use the DBuser / DBinst values from /etc/fetchconfig-web.cfg.)
--
-- Compatibility: PostgreSQL 8.2 and newer. 8.2 has no DO blocks and no
-- "ADD COLUMN IF NOT EXISTS", so the conditional, re-runnable logic runs
-- inside a temporary PL/pgSQL function. The script is idempotent: running it
-- more than once is harmless.
--
-- Privileges: the new column lives in the existing "users" table, which the
-- web user already owns, so no additional GRANT is required.
--
-- WHAT THIS RIGHT MEANS -- read before granting it.
--
-- A device debug log is a complete session transcript. fetchconfig keeps the
-- password out of it by suspending its session log around password sends, but
-- a model that does not do that writes the password in CLEAR TEXT, and
-- fetchconfig-web cannot mask it: masking matches key=value shapes, while a
-- password inside a hex dump exists both as hex bytes and in the ASCII gutter,
-- split across 16-byte boundaries.
--
-- So granting read_debug is, in practice, granting the device credentials for
-- the sites that user can see. It is a heavier right than "download full
-- config", not a lighter one. The right is deliberately NOT implied by being
-- site-unrestricted (unlike download_full_report / download_full_config):
-- it must be granted explicitly, or the user must be an administrator.
--
-- Downloading and deleting debug logs remain ADMINISTRATOR-ONLY and are not
-- affected by this column.
-- ===========================================================================

-- Install PL/pgSQL if missing. Ignore the error if it already exists; this is
-- the one step we let fail, outside the main transaction.
\set ON_ERROR_STOP off
CREATE LANGUAGE plpgsql;
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION fcweb_tmp_208_upgrade() RETURNS void AS $upg$
BEGIN
    -- users.read_debug (nullable-safe: NOT NULL DEFAULT FALSE, so every
    -- existing account starts WITHOUT the right). 8.2 has no
    -- ADD COLUMN IF NOT EXISTS, so check the catalog first.
    PERFORM 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'read_debug';
    IF NOT FOUND THEN
        EXECUTE 'ALTER TABLE users ADD COLUMN read_debug BOOLEAN NOT NULL DEFAULT FALSE';
    END IF;
END;
$upg$ LANGUAGE plpgsql;

SELECT fcweb_tmp_208_upgrade();
DROP FUNCTION fcweb_tmp_208_upgrade();

COMMIT;

-- Done. Grant the new per-user right in User -> Users -> (edit a user) ->
-- Permissions -> "View device debug logs". Administrators have it implicitly.
