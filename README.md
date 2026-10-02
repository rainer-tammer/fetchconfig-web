# fetchconfig-web

A single-file Perl CGI front-end for `fetchconfig`, with a "fetchconfig-web"
title bar and logo shown on every page, and a Devices / Status / User / Help
menu (plus a Setup item for accounts with the edit or admin right) in the
title bar's nav row:

> **Requires fetchconfig 9.65 or newer.** fetchconfig-web reads the installed
> version from `<FETCHCONFIG_PATH>/fetchconfig/Constants.pm` and shows a
> warning banner (on every page, after login) if it is older than 9.65 or
> cannot be determined. The minimum is set by the `MIN_FETCHCONFIG_VERSION`
> constant in `fetchconfig-web.cgi`.

1. Login against the PostgreSQL user database (see "Configuration" and the
   `fetchconfig-web-dbsetup.pl` setup script below).
2. List all Device-IDs (parsed from the fetchconfig device table) with their
   Model, Hostname and Comment, plus a model dropdown and Device-ID /
   Hostname / Comment filter boxes (all remembered in a cookie across
   navigation), sortable columns, and a statistics panel (total device
   count, a live "devices filtered" count, and a per-model breakdown) in the
   upper-right corner. The Hostname column sorts IPv4 addresses in numeric IP
   order first (so `10.1.1.1` follows `2.5.7.8`, not lexically before it),
   then hostnames/FQDNs alphabetically (IPv6 literals sort with the names).
3. A **Status** page (menu, between Devices and Setup) tabulating every
   device's last-run status from its `.status` file: Device-ID (clickable),
   start/end date and time, duration, state (success/failed/skipped, colour
   coded) and changed (unchanged/changed/forced). State and Changed have
   drop-down filters (including N/A for devices with no status file), with the
   same sorting/paging as the device list and a load-time line below.
4. Click a Device-ID -> list its backups, each row showing its index, the
   backup's date (ISO `YYYY-MM-DD`) and time, size, and full path. The
   date and time are extracted from the backup file's own name. The list also
   offers per-device actions: Backup now, Check for empty backups, Check
   backup suffixes, and Download latest configuration.
5. Click a backup -> view its content in a monospaced `<pre>` block, with a
   copy-to-clipboard button and syntax highlighting for the recognised model
   families (see "Config syntax highlighting").
6. Tick two backups of a device and press Compare selected (unified diff)
   or Side by side selected (two-column view) -> see the differences, colored
   in both cases.
7. Press "Backup now" on a device's backup list -> runs a live backup for
   that device immediately, shows the full run transcript, and returns you
   to the (now refreshed) backup list.
8. **User** menu -> change your own password; admins can also add users,
   delete users, reset another user's password without the old one, and grant
   or revoke the edit-table and admin rights (see "User management" below).
9. **Setup** menu (admins and users with the edit right) -> view and edit the
   fetchconfig device table through a form-based editor, or view it raw.
10. **Tools** menu (admins) -> orphaned-backup cleanup, device-table backup
    restore/delete, the "devices without backups", "empty backups", and
    "consistent backup suffixes" scans, and the fetchconfig log viewer.
11. **Help** menu -> a description of the application, editable without
    touching the script (see "Help page" below).

It does not re-implement repository scanning. It shells out to your
already-extended `fetchconfig.pl` (`-l` and `-g` modes), via safe list-form
`exec()` (no shell interpolation), so results always match the CLI tool
exactly and command injection isn't possible via the web parameters.
User accounts (and the per-user device-table edit right) live in a
PostgreSQL database; no `htpasswd` binary or password file is used.

## Contents

**Part 1 -- Overview**
- [What fetchconfig-web is](#what-fetchconfig-web-is)
- [How it works](#how-it-works)
- [Files](#files)

**Part 2 -- Installation and configuration**
- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [The user database](#the-user-database)
- [Deploying](#deploying)
- [Backup Now and repository write permissions](#backup-now-and-repository-write-permissions)

**Part 3 -- Using fetchconfig-web**
- [Devices and backups](#devices-and-backups)
- [Viewing and comparing backups](#viewing-and-comparing-backups)
- [Setup devices and the device-table editor](#setup-devices-and-the-device-table-editor)
- [Tools](#tools-admins-only)
- [User management](#user-management-via-the-web-ui)
- [The Help page](#help-page)
- [User-interface conveniences](#user-interface-conveniences)

**Part 4 -- Reference**
- [How fetchconfig.pl is invoked](#how-fetchconfigpl-is-invoked)
- [Supported password hash formats](#supported-hash-formats)

**Part 5 -- [Security model](#security-model)**

**Part 6 -- [Development](#development)**

[License](#license)

## Part 1 -- Overview

### What fetchconfig-web is

fetchconfig-web is a web front-end for
[fetchconfig](https://github.com/udhos/fetchconfig), the network-device
configuration-backup tool. It lets operators browse devices, view and compare
saved configurations, trigger an on-demand backup, edit the device table, and
run housekeeping tools -- all from a browser, without shell access to the
backup host.

### How it works

fetchconfig-web is a **single stateless Perl CGI script**
(`fetchconfig-web.cgi`). It holds no long-running state of its own: every
operation either shells out to `fetchconfig.pl` (to list templates, list or
fetch backups, run a backup, check directories) or reads the repository and
device table directly on disk. User accounts and login sessions are stored in a
small **PostgreSQL** database. Because it is a plain CGI, it runs under any
standard web server (Apache `mod_cgi` and comparable setups) with no
application server or daemon to manage.

A running instance is made up of: the CGI script, a configuration file
(`/etc/fetchconfig-web.cfg`), the PostgreSQL `users` table (created by the
bundled setup script), an installed copy of fetchconfig, and -- optionally -- a
sudo helper for privileged template writes. The rest of this document covers
each of these in turn.

### Files

- `fetchconfig-web.cgi` -- the entire application (one file, easy to deploy).
  Its images (the title-bar logo and the login-box icon) are embedded as
  base64 inside the script itself, so there are no separate image files to
  deploy.
- `help.html` -- optional HTML *fragment* (no `<html>`/`<body>` tags) shown
  on the Help page; see "Help page" below. The app works fine without it
  (a built-in description is shown instead), so this file is only needed
  if you want to customise that text.
- `fetchconfig-web-dbsetup.pl` -- one-off setup helper for the PostgreSQL
  user database (see "User database" below).
- `fetchconfig-web-documentation.html` -- this README rendered as a styled,
  self-contained HTML manual (linked from the Help page).
- `CHANGES` -- the changelog.
- `LICENSE` -- the GNU General Public License, version 3 (see "License"
  below).
- `render-doc.py` + `render-doc.md` -- a build helper (Python 3, standard
  library only) that regenerates `fetchconfig-web-documentation.html` from
  this README, and its short description. Not needed at runtime.

## Part 2 -- Installation and configuration

### Quick start

For an experienced operator, the shortest path to a running instance:

1. **Install the prerequisites** -- Perl with DBI/DBD::Pg, CGI and
   Algorithm::Diff; PostgreSQL; and fetchconfig 9.65+ (see
   [Requirements](#requirements)).
2. **Create the user database** -- run `perl fetchconfig-web-dbsetup.pl`
   (see [The user database](#the-user-database)).
3. **Write the configuration** -- copy the sample in
   [Configuration](#configuration) to `/etc/fetchconfig-web.cfg` and adjust the
   paths for your fetchconfig install.
4. **Install the CGI** -- copy `fetchconfig-web.cgi` into your web server's
   `cgi-bin` and make it executable (see [Deploying](#deploying)).
5. **Log in** -- browse to the script and sign in as the default admin, then
   change the password immediately.

Each step is detailed below.

### Requirements

- Perl 5 with core modules: `CGI`, `CGI::Cookie`, `Digest::MD5`,
  `Digest::SHA`, `MIME::Base64`, `Fcntl`, `File::Path`, `File::Temp`,
  `IPC::Open3`, `IO::Select`, `Symbol`, `Text::ParseWords`. `CGI.pm` was
  removed from Perl core in 5.22+, so on newer systems install it
  separately, e.g. `apt install libcgi-pm-perl` (Debian/Ubuntu),
  `dnf install perl-CGI` (RHEL), `zypper install perl-CGI` (SLES) or
  `cpan CGI`. The rest are
  standard core modules on every Perl install (Linux and AIX).
- `Algorithm::Diff`, `DBI`, and `DBD::Pg` (non-core) -- see "Non-core Perl
  modules" below.
- A **PostgreSQL** server (9.2 or newer) reachable from the web server, and
  the user database created by `fetchconfig-web-dbsetup.pl` (see "User
  database setup" below).
- A web server configured to run `.cgi` scripts (Apache `mod_cgi`/`ScriptAlias`,
  or equivalent).
- Read access to your fetchconfig device table and execute access to
  `fetchconfig.pl`.

#### Non-core Perl modules

Every module the two scripts use *except* the following ships with Perl 5
(core) on both Linux and AIX. These are the only ones that may need
installing; if any is missing the app won't start, so install them before
deploying:

| Module            | Minimum version | Used by                          | Purpose                                              | Install (Debian/Ubuntu)   | Install (RHEL)          | Install (SLES)          | Install (CPAN)          |
|-------------------|-----------------|----------------------------------|------------------------------------------------------|---------------------------|-------------------------|-------------------------|-------------------------|
| `DBI`             | **1.641**       | `fetchconfig-web.cgi`, setup script | Database access layer for the PostgreSQL user store | `libdbi-perl`             | `perl-DBI`              | `perl-DBI`              | `cpan DBI`              |
| `DBD::Pg`         | **3.15.0**      | `fetchconfig-web.cgi`, setup script | PostgreSQL driver for `DBI` (used via the `dbi:Pg:` DSN -- no explicit `use`, but required at runtime) | `libdbd-pg-perl` | `perl-DBD-Pg` | `perl-DBD-Pg` | `cpan DBD::Pg` |
| `Algorithm::Diff` | any (1.201 ok)  | `fetchconfig-web.cgi`            | Side-by-side and Tools config diffs (`sdiff`); 1.201 is known-good | `libalgorithm-diff-perl` | `perl-Algorithm-Diff` | `perl-Algorithm-Diff` | `cpan Algorithm::Diff` |
| `CGI` (`CGI.pm`)  | **4.53**        | `fetchconfig-web.cgi`            | CGI request/response handling. Core until Perl 5.22, then removed -- treat as non-core on modern Perl | `libcgi-pm-perl` | `perl-CGI` | `perl-CGI` | `cpan CGI` |

`perl Makefile.PL` checks these versions and refuses to continue (with a clear
message) if a module is missing or older than the minimum above.

One-line install of all four:

```sh
# Debian / Ubuntu
apt install libdbi-perl libdbd-pg-perl libalgorithm-diff-perl libcgi-pm-perl

# RHEL / Rocky / AlmaLinux (dnf or yum)
dnf install perl-DBI perl-DBD-Pg perl-Algorithm-Diff perl-CGI

# SUSE / SLES / openSUSE
zypper install perl-DBI perl-DBD-Pg perl-Algorithm-Diff perl-CGI
```

The standalone `fetchconfig-web-dbsetup.pl` needs only `DBI` + `DBD::Pg`
(plus core `Digest::MD5`).

#### CGI 4.53 patch for `start_html()` (AIX, and possibly Linux)

On AIX with CGI 4.53, `CGI::Util::_rearrange_params` warns

```
Odd number of elements in hash assignment at .../CGI/Util.pm line 119
```

when `start_html()` is called with a BODY-format parameter (as fetchconfig-web
does). The warning is harmless but noisy in the web-server error log. Suppress
it by wrapping the parameter handling in `no warnings;` -- apply this small
patch to the installed `CGI/Util.pm`:

```diff
--- Util.pm.orig        2021-07-26 16:33:34.716539697 +0200
+++ Util.pm     2021-07-26 16:33:19.941302316 +0200
@@ -95,6 +95,13 @@ sub rearrange_header {
 }

 sub _rearrange_params {
+    # needed because of start_html() BODY format parameter
+    # Odd number of elements in hash assignment at
+    # /usr/opt/perl5/lib/site_perl/5.28.1/CGI/Util.pm line 119 (#1)
+    # (W misc) You specified an odd number of elements to initialize a hash,
+    # which is odd, because hashes come in key/value pairs.
+    no warnings;
+    # needed because of start_html() BODY format parameter
     my($order,@param) = @_;
     return [] unless @param;
```

Find the file with `perl -MCGI::Util -e 'print $INC{"CGI/Util.pm"}, "\n"'`,
back it up, and apply the patch (e.g. with the AIX `patch` or the freeware
`diff`/`patch` tools). This was first seen on AIX, but the warning comes from
CGI 4.53 itself, not from AIX -- so **the same patch may be needed on Linux**
(or any platform) running CGI 4.53 if `start_html()`'s BODY-format parameter
triggers the same "odd number of elements" message in the web-server error
log. The file location differs by platform (use the `perl -MCGI::Util` command
above to find it), but the change is identical. If your CGI is a newer version
that has already fixed this, the patch is not needed.

### Configuration

All site-specific settings live in an external config file,
**`/etc/fetchconfig-web.cfg`** (`key = value`), so credentials and paths are not
baked into the script. Only two things stay hardcoded in
`fetchconfig-web.cgi`: `$APP_TITLE`, `$COOKIE_NAME` -- and the path to the
config file itself, `$CONFIG_FILE = '/etc/fetchconfig-web.cfg'`.

`fetchconfig-web-dbsetup.pl` offers to write this file for you at the end of
its run (mode 0600, with the database values filled in and the rest at
defaults). You can also create it by hand:

```
# /etc/fetchconfig-web.cfg -- fetchconfig-web configuration (key = value)
DEVICE_TABLE            = /usr/local/fetchconfig/device_table
REPOSITORY              = /usr/local/fetchconfig/config
FETCHCONFIG_LOG         = /usr/local/fetchconfig/fetchconfig.log
LOG_MAX_DEVICES         = 1000
MAX_PARALLEL_SCAN       = 1
FONT_BASE_URL           = /fetchconfig-web/fonts
IMAGE_BASE_URL          = /fetchconfig-web/images
HELP_BASE_URL           = /fetchconfig-web
FETCHCONFIG_PATH        = /usr/local/fetchconfig
FETCHCONFIG_BIN         = fetchconfig.pl
BACKUP_DEVICE_TABLE     = /usr/local/fetchconfig/backup
USE_SUDO_FOR_BACKUP_NOW = 1
SUDO_BIN                = /usr/bin/sudo
SESSION_DIR             = /www/fetchconfig-web/sessions
BACKUP_TMP_DIR          = /www/fetchconfig-web/sessions
SESSION_TTL             = 28800
DEVICE_ID_FIELD         = 1
DBinst                  = fetchconfig
DBuser                  = fcweb
DBpass                  = changeme
DBhost                  = localhost
PROTECTED_USER          = admin
MIN_PASSWORD_LENGTH     = 8
DEFAULT_PASSWORD        = fetchconfig
HELP_FILE               = /www/pub/fetchconfig-web/help.html
TEMPLATE_HELPER         = /usr/local/fetchconfig/fetchconfig-web-install-template.pl
APP_VERSION             = 1.50
COPYRIGHT               = 2026 (c) Rainer Tammer
```

Format and loading:

- One `key = value` per line; the first `=` splits key from value, and both
  sides are trimmed. A matching pair of surrounding quotes on the value is
  stripped, so `COPYRIGHT = "2026 (c) ..."` and the bare form are equivalent.
- Whole-line `#` comments and blank lines are ignored. A `#` *inside* a value
  is kept (e.g. `COPYRIGHT = 2026 #1 vendor` works).
- `DEVICE_TABLE`, `REPOSITORY`, `FETCHCONFIG_PATH`, `FETCHCONFIG_BIN`, `SESSION_DIR`, `DBinst`,
  `DBuser`, and `DBhost` are **required**; the rest fall back to built-in
  defaults if absent (`BACKUP_TMP_DIR` defaults to `SESSION_DIR`;
  `BACKUP_DEVICE_TABLE`, where the device-table editor writes its
  timestamped `.bak` copies, defaults to `/usr/local/fetchconfig/backup`
  and is created automatically on first save). If the
  file is missing or a required key is absent, the app serves a clear
  configuration-error page instead of failing obscurely.
- The config is read once per request, before anything else runs.
- **`FETCHCONFIG_PATH` and `FETCHCONFIG_BIN`** together locate the
  fetchconfig executable: it is run as `<FETCHCONFIG_PATH>/<FETCHCONFIG_BIN>`
  (e.g. `/usr/local/fetchconfig/fetchconfig.pl`). `FETCHCONFIG_PATH` is also
  where the version check looks for `fetchconfig/Constants.pm`. (Earlier
  releases used a single `FETCHCONFIG_BIN` holding the full path -- update
  old config files to the two-key form; the old single-key form is no longer
  accepted.)
- **`MAX_PARALLEL_SCAN`** (default `1`) sets how many device checks the Tools
  scan tools ("devices without backups", "empty backups", "consistent backup
  suffixes") run concurrently in the browser. `1` is fully serial (the
  original behaviour). It must be an integer **1..5**; a value outside that
  range is a configuration error and the app refuses to start. Each concurrent
  check spawns its own `fetchconfig.pl`, so raise this only as far as the
  server hosting fetchconfig can comfortably handle -- and note that browsers
  also cap connections per host (about 6), which bounds the effective
  parallelism.

**Permissions:** the file holds the database password in clear text, so it
must be readable by the web-server user but no one else. With the web server
running as `nobody`, `chown nobody /etc/fetchconfig-web.cfg` + `chmod 600` is the
intended setup (which is what the setup script writes).

The four `DB*` values must match the application login the setup script
used. A fresh database connection is opened per request and closed at the
end.

Every page's footer prints `$APP_TITLE v$APP_VERSION using fetchconfig
v<version> -- $COPYRIGHT` (the "using fetchconfig v..." part is added only
when the installed fetchconfig version can be read from `Constants.pm`, using
the same cached lookup as the version-check banner; it is omitted otherwise).
`APP_VERSION` is built in: the script carries the version it ships as in the
`APP_VERSION` constant near the top of `fetchconfig-web.cgi`, and that is
what the footer shows unless the config file's `APP_VERSION` key **overrides**
it. So the key is optional -- leave it out to use the built-in version, or set
it to display something else. `COPYRIGHT` is read from the config file.

- `$SESSION_DIR` must be writable by the web server user; the script creates
  it automatically (mode 0700) on first run if it doesn't exist.
- `$DEVICE_TABLE` **assumption**: whitespace-separated columns, e.g.
  `model  device_id  host`. `#` comments, blank lines, and directive lines
  are skipped. A directive line is any whose first token is a keyword
  ending in a colon (e.g. `default:`, `email:`) -- those configure
  fetchconfig rather than declaring a device, so they never appear in the
  device list. `$DEVICE_ID_FIELD` picks which column (0-based) is the
  Device-ID -- `1` (the second column) is confirmed correct for the observed
  `model  device_id  host` layout. If your table uses a different delimiter
  entirely, adjust `read_device_ids()` -- it's a small, self-contained
  function.
- Backup listing/index numbering is taken verbatim from whatever
  `fetchconfig.pl -l dev_id` prints (tab-separated: index, size, path), and
  that same index is passed straight through to `fetchconfig.pl -g dev_id -n
  idx` -- so it stays correct even if the indexing scheme changes later.
- Every `fetchconfig.pl` call passes a `-devices=` table -- the read-only
  calls (`-l`/`-g`/`-m`) use `-devices=$DEVICE_TABLE`, while Backup Now uses
  `-devices=<tempfile>` (its own single-device table, see below). The CLI
  requires either `-devices=` or `-line=` on every invocation and has no
  implicit default table path.
- All `fetchconfig.pl` calls go through a shared `run_fetchconfig()` helper
  that captures stdout and stderr **separately** (via `IPC::Open3`, read
  concurrently with `IO::Select` to avoid the classic open3 pipe-buffer
  deadlock). This matters because `fetchconfig.pl` writes its own
  `info:`/`debug:` startup diagnostics to stderr -- only stdout is parsed as
  data (backup listings, config content, diff output); stderr is used
  solely to build an error message when the exit code is non-zero.
- **Compare Selected** (unified diff) calls `fetchconfig.pl`'s own native
  compare mode (`-g dev_id -n N -m M`) directly and renders its output --
  it does not fetch two configs and diff them itself, and it never writes
  anything to disk on the web server. `N` is always the newer
  (lower-numbered) of the two selected backups and `M` the older, since
  the CLI requires `M > N`. Exit code `0` means identical, `1` means the
  output is a diff, anything else is treated as an error and shown as one.
  The diff text is now colored per line by its leading marker (`+`/`>`
  green, `-`/`<` red, `@@`/`***`/`---` blue), keying only on the first
  character(s) so it works for both unified and traditional `diff` output;
  the lines themselves are still individually HTML-escaped. Its legend reads
  **red = old, green = new** (the unified view only distinguishes old vs.
  new lines -- there is no separate "changed" colour, unlike Side by Side).
- **Side by Side Selected** is an additional view (not a replacement) that
  *does* diff in the app, using `Algorithm::Diff::sdiff()` on the two
  fetched configs (retrieved with the same `-g dev_id -n idx` the
  single-backup view uses). It renders a two-column table -- older on the
  left, newer on the right -- with per-side line-number gutters and rows
  tinted green (added), red (removed), or amber (changed). Because it uses
  a different diff engine than `fetchconfig.pl -m`, the two views always
  agree on *what* changed but may occasionally group hunks slightly
  differently; the unified view remains the CLI-exact one. Requires the
  `Algorithm::Diff` CPAN module (1.201 is known-good); it is the only
  non-core Perl dependency the app adds, and only the Side by Side view
  needs it.
- "Backup Now" runs a live backup immediately. It builds a **temporary,
  single-device device table** and hands it to `fetchconfig.pl` via
  `-devices=<tempfile>` -- exactly the way the tool is run from the command
  line -- rather than reconstructing the config from `-line=` arguments. The
  temp table contains, in this order: every **global directive line** from
  `$DEVICE_TABLE` (`find_directive_lines()` -- any line whose first token
  ends in a colon: the model `default:` lines, the `email:` notification
  line, and any other such directive), then a `default: <model>
  repository=$REPOSITORY` line, then the **verbatim** target device line
  (`find_device_table_line()`). Two things matter here, both learned the
  hard way against fetchconfig 9.28-ACME:
    - The device line is written **verbatim** -- `repository=` is *not*
      appended to it. fetchconfig treats everything after the host column
      as the device's comma-separated option list, so a space-appended
      `repository=...` was being folded into the preceding `pass=` value,
      corrupting the password. That broke authentication for exactly the
      devices that set their own `user=`/`pass=` on the device line, while
      default-credential devices were unaffected. Repository is instead set
      the normal way, as a model `default:` line.
    - **All** directive lines are carried through, not just `default:`s. In
      particular the `email:` line must be present or fetchconfig has no
      recipient and sends no backup-summary notification. (An earlier
      version passed only `default:` lines, which silently suppressed the
      e-mail on WEB-UI backups.)
  `find_directive_lines()` does no per-model filtering or deduplication --
  it passes every directive through in file order and lets `fetchconfig.pl`'s
  own matching apply the right ones, exactly as loading the full table on
  the CLI does. Only the one target device line is included, so just that
  device is backed up. The temp file holds cleartext credentials, so it is
  created mode 0600 in `$BACKUP_TMP_DIR` (a web-writable, non-web-served
  directory, defaulting to `$SESSION_DIR`) and unlinked the moment the run
  finishes, success or failure. Unlike every other call in this app, stdout
  and stderr are **merged** here on purpose -- for a live run,
  `fetchconfig.pl`'s `info:`/`debug:` transcript (connecting, retrieving,
  saved-to, or any error) is exactly what you want to see. The button is a
  POST form with a JS `confirm()` prompt (real side effect: it opens a live
  connection to the device and writes a new file), and the follow-up
  "Return to backups" link is a plain GET back to the device's backup list,
  which shows the new backup once `fetchconfig.pl` has written it.
- On the backup list page, "Backup Now", "Compare Selected", and "Side by
  Side Selected" sit together at the top, above the table. Backup Now is
  its own POST form; the two compare buttons drive a single GET form
  (`id="compare-form"`) that wraps the table and its checkboxes. The two
  buttons live outside that form's markup, up in the top row, tied to it
  via the HTML5 `form="compare-form"` attribute, so the browser submits
  them as if nested inside (checked checkboxes included). Each button
  carries the action as its own `name="action"` value (`compare` vs
  `sidebyside`) rather than the form holding a hidden `action` field --
  that way exactly one `action` is submitted, whichever button was
  clicked, with no ambiguity from two `action` params in the query string.
  The form keeps only the hidden `dev` field.
- The copy-to-clipboard button on the backup content page uses
  `navigator.clipboard.writeText()`, which most browsers restrict to
  secure contexts (HTTPS or localhost). It falls back automatically to the
  older `document.execCommand('copy')` trick when the Clipboard API isn't
  available, so it should still work over plain HTTP -- but this is one
  more reason to move to HTTPS when you can (see the note near the top of
  this file). It copies the DOM's decoded text content, not the
  HTML-escaped markup, so the exact original config bytes end up on the
  clipboard. The same button/script is reused on the Backup Now result
  page to copy the run transcript.
- Two images are embedded as base64 constants near the top of the file: the
  title-bar logo (`$LOGO_BASE64`, between the `<<'B64'` / `B64` heredoc
  markers) and the login-box icon (`$LOGIN_ICON_BASE64`, between
  `<<'ICONB64'` / `ICONB64`). To swap either one: `base64 -w100 new.png` and
  replace the contents between the corresponding markers. Any line wrapping and
  whitespace inside is stripped before use, so the 100-column wrapping is
  cosmetic.

### The user database

The bundled `fetchconfig-web-dbsetup.pl` script creates the PostgreSQL role, database and `users` table.

To enable per-site access on an **existing** installation, run the bundled
`fetchconfig-web-dbupdate.sql` once against the fetchconfig-web database:

```
psql -U <DBuser> -d <DBinst> -f fetchconfig-web-dbupdate.sql
```

It is idempotent, PostgreSQL 8.2-compatible, and starts every existing user unrestricted (site 0). It also grants the web user the privileges it needs on the new tables (important if you run it as `postgres` rather than the web DB user).

A standalone helper that creates the database and table and (optionally)
imports existing accounts. Every step is a Y/N prompt, so it's safe to
re-run. Run it once before first use:

```sh
perl fetchconfig-web-dbsetup.pl
```

It will, in order:

1. Ask for the application **database name** (default `fetchconfig`) and
   **host**.
2. Offer to **create the database**: it connects to the `postgres`
   maintenance database with a maintenance login (typically the `postgres`
   superuser, which needs `CREATEDB`/`CREATEROLE` rights), creates the
   application role if missing, and `CREATE DATABASE ... OWNER <app-user>`.
   Skip this if the database already exists.
3. Reconnect as the **application login** and create the `users` table
   (PostgreSQL 9.2-compatible DDL).
4. Offer to **import** accounts from `/www/passwd/fetchconfig` if that old
   htpasswd file is present -- hashes are copied verbatim, so everyone's
   current password keeps working, all with `edit_device_table = false` and
   `admin_function = false` (except `admin`, which gets both true).
5. **Bootstrap admin**: if no `admin` account exists after import (or you
   skipped import), create `admin` with the password `fetchconfig`. If
   `admin` was imported, it is left untouched (and imported `admin` is given
   both the edit and admin-function rights, since `admin` always has them
   anyway).
6. **Write `/etc/fetchconfig-web.cfg`** (optional): writes the config file the
   CGI reads, mode 0600, with the database values filled in from the answers
   above and the other settings at their defaults for you to review. Skip
   this to create the file by hand (see "Configuration").

Migrating from an earlier (htpasswd) version means everyone re-logs in once,
since sessions are new.

**Upgrading an existing database** (adding `admin_function` to a `users`
table created by an earlier version) is a one-time manual step:

```sql
ALTER TABLE users ADD COLUMN admin_function BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE users SET admin_function = TRUE WHERE username = 'admin';
```

Set it `TRUE` for any other accounts that should have full admin rights (or
do that from the User page afterward).

### Deploying

```sh
cp fetchconfig-web.cgi /www/cgi-bin/
chmod 755 /www/cgi-bin/fetchconfig-web.cgi
```

Point your browser at `https://yourhost/cgi-bin/fetchconfig-web.cgi`.

**Login backdrop and static assets.** `FONT_BASE_URL` (default
`/fetchconfig-web/fonts`) and `IMAGE_BASE_URL` (default `/fetchconfig-web/images`)
are the **URL paths** (not filesystem paths) under which the web server serves
the optional fonts and images. These (and `HELP_BASE_URL`) are validated at
startup: they must be absolute URL paths made only of letters, digits and
`. _ ~ - /` -- no scheme, quotes, spaces or parentheses -- because they are
emitted into links and CSS; an invalid value is reported as a configuration
error on the login page. The login page shows a full-page backdrop
image loaded from `<IMAGE_BASE_URL>/back.jpg`; the title bar, login box and
the (bottom-centred) copyright footer stay legible on top of it. Copy the
`back.jpg` shipped in the `images/` directory of this package to wherever the
server serves `IMAGE_BASE_URL`, e.g.:

```sh
mkdir -p /www/pub/fetchconfig-web/images
cp images/back.jpg /www/pub/fetchconfig-web/images/
```

and set `IMAGE_BASE_URL` to the matching URL path (e.g. `/pub/fetchconfig-web/images`).
If the file is absent the login page simply shows a plain background. Only the
login page uses the backdrop; the logged-in pages do not.

**Create the device-table backup directory at install time.** If you use the
device-table editor, the app needs `$BACKUP_DEVICE_TABLE` (default
`/usr/local/fetchconfig/backup`) to exist and be writable by the web-server
user. The app can create it automatically, but only if the base directory it
sits in is web-writable -- which it usually should **not** be. Create it by
hand instead, leaving the base `fetchconfig` directory at `755
fetchconfig_user:fetchconfig_group` and making just the backup directory
writable by the web user (see "Setup devices and the device-table editor" for the
exact commands).

**Serve over HTTPS.** Login posts a plaintext password and the session
cookie is a bearer token; both should travel encrypted. Once HTTPS is in
place, uncomment `-secure => 1` on the cookie in `do_login()`.

### Backup Now and repository write permissions

Your existing backups are written by a privileged process (typically a
root cron job) and end up owned `root:system`, mode `0744` on files and
`2755` on directories. Viewing, listing, and comparing backups all only
*read* those files -- and `0744`/`2755` are world-readable, so the CGI
script can do all of that as whatever unprivileged user your web server
runs as. But Backup Now *writes* a new file into that same root-owned
tree, which an unprivileged user has no permission to do on its own,
producing:

```
fetchconfig.pl: error: ...: unable to write to repository=...
```

**This deployment's script is already configured for this**: Apache runs
as `nobody`, a matching sudoers rule is in place (below), and
`$USE_SUDO_FOR_BACKUP_NOW = 1` is set accordingly. If you ever redeploy to
a host where the web server runs as a different user, or move the
sudoers rule, this is the section to revisit.

Two ways to solve the underlying permission gap (the first is what's
configured):

**Option A -- narrow `sudo` rule (recommended, smallest blast radius).**
Add a sudoers rule allowing only the web server's user to run only this
one binary as root, no password prompt (find your web server's user via
e.g. the `User` directive in Apache's config, or `ps -ef` while a request
is in flight -- on this deployment it's Apache's default `nobody`):

```
# /etc/sudoers.d/fetchconfig-web
nobody ALL=(root) NOPASSWD: /usr/local/fetchconfig/fetchconfig.pl
```

`$USE_SUDO_FOR_BACKUP_NOW` is already set to `1` in the delivered script
to match. Backup Now runs
`sudo -n /usr/local/fetchconfig/fetchconfig.pl -devices=<tempfile>`; `-n`
means it never blocks waiting for a password it can't answer -- if the
sudoers rule isn't matching yet, you'll see sudo's own error ("a password
is required" or similar) right there in the output box instead of a hang.
The `<tempfile>` is the short-lived, mode-0600 single-device table written
under `$BACKUP_TMP_DIR`; root reads it via this rule and it's removed as
soon as the run finishes. This keeps newly-created backups owned
`root:system`, consistent with your existing files, and doesn't touch the
repository's permissions or your other tools
at all. Two things worth knowing about this specific setup:
- It grants passwordless root execution of that one binary to whatever
  runs as `nobody`, with whatever arguments the caller passes -- in
  practice only this script calls it that way, but it's still a privilege
  grant worth your usual security sign-off.
- `nobody` is often a shared, generic low-privilege account used by more
  than just Apache (other daemons or cron jobs may also run as `nobody`)
  -- this sudo rule applies to *any* process running as that user, not
  just this CGI script. If that's broader than you'd like, consider
  running this CGI under a dedicated user instead (e.g. via Apache's
  `SuexecUserGroup`/`mod_ruid2`/a separate vhost) and scoping the sudoers
  rule to that user instead of `nobody`.

**Option B -- group-writable repository (no code change, but a bigger
permission change).** Add the web server's user to the `system` group (or
create a dedicated group, e.g. `fetchconfig`, and put both root's cron
user and the web server's user in it), then change the repository
directories from `2755` to `2775` (adds group-write; the setgid bit
already there means new files/dirs keep inheriting the right group). This
needs no code change and no sudoers entry, but it does mean *any* process
running as a member of that group can write into the repository, not just
this one narrowly-scoped script -- a larger, more permanent change to your
existing permission model.

Either way, no change is needed for viewing, listing, or comparing
backups -- those already work under the web server's own unprivileged
user, since the existing files are world-readable.

## Part 3 -- Using fetchconfig-web

### Devices and backups

#### Web-UI (binary) backups

Some switches have no CLI at all -- TP-Link Easy Smart (`tplink-web-sg105e`,
e.g. TL-SG105E) and the HP ProCurve 1700 series (`procurve-web-1700`).
fetchconfig retrieves their config by scraping the switch's web GUI over
plain HTTP. The downloaded config is an **opaque binary file**, which
fetchconfig stores **uuencoded** (`begin 644 <name>.cfg` ... `end`) so it
fits the text repository. `procurve-web-1700` has only a manager password,
so its `user` option is optional (ignored). The web UI treats both models
the same way:

- On a device's backup list, the **Compare Selected** / **Side by Side
  Selected** actions and the per-row checkboxes are **hidden** -- a
  line-by-line diff of a binary blob isn't meaningful (only that it changed,
  not what changed).
- Selecting a backup does **not** show the raw text. Instead the config view
  offers a **Download** button that serves the backup transparently
  **uudecoded** to the real binary file. The name is per-model, matching what
  each switch's restore page expects: `<Device-ID>-switch.cfg` for
  `procurve-web-1700` (e.g. `PCW_1700_1-switch.cfg`) and
  `<Device-ID>-config.cfg` for `tplink-web-sg105e` (e.g.
  `TPL_Montage_1-config.cfg`). Decoding is done in-app (`uudecode_content`,
  via Perl `unpack "u"`) by the read-only
  `?action=download_config&dev=<id>&idx=<n>` endpoint; the file is sent as
  `application/octet-stream`. Models are recognised by
  `is_web_binary_model()`, and the filename by `web_config_filename()`.

#### Backup list: date & time columns

Each row of a device's backup list shows, in order: a compare checkbox,
the backup **index** (`#`), the **date**, the **time**, the **size**, and
the full **path**. The date and time are parsed out of the backup file's
own name rather than from its filesystem mtime, so they reflect when
`fetchconfig.pl` actually captured that backup.

fetchconfig names each saved config in the repository as
`<dev_id>.<tag>.YYYYMMDD.HHMMSS<TZ>`, e.g.

```
/usr/local/fetchconfig/config/202608/20260825/V1-SW1/V1-SW1.run.20260825.143556CEST
```

`parse_backup_timestamp()` takes only the basename and anchors to the
trailing `.YYYYMMDD.HHMMSS` plus an optional alphabetic timezone suffix.
That means:

- The `202608/20260825/` year-month / date directories earlier in the path
  are ignored -- only the filename's own timestamp is used.
- A `dev_id` that contains dots or digits (e.g. an FQDN like
  `switch01.acme.com`) doesn't throw the match off, because the
  pattern is anchored to the end of the name.
- The date is shown ISO-formatted as `YYYY-MM-DD`; the time as `HH:MM:SS`
  with the timezone appended when present (e.g. `14:35:56 CEST`), so CET
  and CEST backups are distinguishable.
- The timezone suffix is assumed to be a short **alphabetic** abbreviation
  (`CEST`, `CET`, `MET`, `GMT`, `UTC`, ...). This holds for fetchconfig running
  on **AIX, Linux and Solaris**, whose C library returns such abbreviations
  from `strftime`'s `%Z`. On **Windows**, `%Z` instead returns a long
  descriptive name (e.g. `W. Europe Daylight Time`), so only its leading
  letters would be shown as the timezone label -- the **date and time
  themselves are still parsed correctly** (they precede the timezone), and
  `timezone=hide` avoids the label entirely. Running fetchconfig on
  AIX/Linux/Solaris needs no special handling.
- If a filename ever doesn't match this pattern, that row simply shows
  blank date/time cells rather than a wrong or misleading value.

If your fetchconfig build names backup files differently, that one
`parse_backup_timestamp()` sub is the only thing to adjust -- the regex is
isolated there. Table cells use `white-space: nowrap`, so the date, time,
and path columns stay on a single line each instead of wrapping.

### Viewing and comparing backups

#### Config syntax highlighting (backup content view)

When you view a single backup, the config is syntax-highlighted if a
highlighter is registered for the device's model. This is **extensible**:
`%SYNTAX_HIGHLIGHTERS` maps a model name to a highlighter coderef, and
`highlight_config()` uses it if present, otherwise falls back to the plain
escaped `<pre>`. To add another model, write a `highlight_<model>()` sub and
add one line to the registry.

A Cisco IOS highlighter is registered for `cisco-ios` and `cisco-ios-ssh`.
It's a lightweight, line-oriented colouriser (not a full grammar): comment/
`!` lines, a leading command keyword, interface identifiers
(`GigabitEthernet0/1`), IPv4 addresses/masks, numbers, and quoted strings.
Free-form blocks whose bodies shouldn't be tokenised are detected and left
uncoloured: **certificate/key hex dumps** (`certificate ...` up to `quit`)
and **banners** (`banner <type> ^C` up to the closing `^C`).

Separate, independently-tunable highlighters are registered for other model
families, each tailored to that platform's syntax: `procurve`/`procurve-ssh`
(ProCurve/Aruba -- `;` comments, quoted names, `1/A2`/`Trk10` ports),
`comware-ssh` (Comware/H3C -- `#` comments, `undo` negation,
`GigabitEthernet1/0/1` interfaces, `cipher`/`hash` credential lines left
plain), and `zyxel` (Zyxel -- IOS-like, but with a space before the unit as
in `GigabitEthernet 1/1`, and `username ... password encrypted <blob>` lines
whose blob is left un-tokenised). `planet-ssh` (PLANET switches) reuses the
Cisco IOS highlighter, since its running-config is plain IOS-like.
`aruba-cx-ssh` (Aruba AOS-CX) has its own highlighter: `!` comments, a
banner whose delimiter is `!`, `password/key ciphertext <blob>` lines left
plain, `1/1/1`/`lag`/`vlan` interfaces, IPv4 with an optional `/CIDR`
suffix, and single-quoted descriptions. `nexus-ssh` (Cisco Nexus / NX-OS)
reuses the IOS per-token rules -- NX-OS running-config is IOS-family syntax
(`!` comments, `interface Ethernet1/1`, `feature`, `vlan`, `no ...`) -- but
adds NX-OS-specific handling: banners use an **operator-chosen delimiter**
(e.g. `banner motd ^` ... `^`, `banner exec #` ... `#`) rather than IOS's
`^C`, so the banner body (often ASCII art) is detected by that delimiter and
left un-tokenised; and inline secret material (`password 5 <hash>`,
`key 7 "<hex>"`) is emitted as a plain string rather than mis-coloured.
`mediant-sbc` (AudioCodes Mediant SBC) has its own highlighter because its
"show running-config" is **not** IOS syntax but AudioCodes' own
`parameter-value` style: `#`/`##` comments (including `##` section banners),
object blocks that open with a header line and close with `activate`/`exit`,
hyphenated parameter names, `"quoted strings"`, IPv4 addresses and integers,
`no <param>` negation, and `enabled`/`disabled` values. The obscured
`password <blob> obscured` lines are highlighted but not masked (like the
other space-separated secrets, `mask_secrets` only covers `key=value` syntax).

Highlighting is applied **only** to the single-backup content view -- the
compare and side-by-side views keep their add/remove/change colouring.
Safety invariant: highlighters escape every character they emit through the
same `esc()` (which HTML-escapes and masks `pass=`/`enable=` secrets), so
stripping the `<span>`s from the output yields byte-for-byte the plain view
-- highlighting is purely cosmetic and can't leak a secret or inject markup.
The copy button copies the DOM's text content, so it copies the plain
config, not the highlight markup.

### Navigation menus

The title bar uses drop-down menus: **Devices** (Device list, Backup status,
Backup reports), **Setup devices** (Show device table, Edit device table, Bulk
edit -- shown only to users who may edit the table; a site-limited user sees
only Edit device table), **Tools** (admin only, each tool on its own page), **User** (Change your password
for everyone; Users list, Add user and Sites for admins), and **Help**. The
post-login page is the device list.

### Reports

The **Reports** page (Devices menu -> Backup reports; all logged-in users)
lists the HTML change-reports fetchconfig writes into the report directory --
the `report_dir` set on the `email:` line, resolved through the `directory:`
allow-list. The reports are listed newest first, with **View**, **Download**
and **Delete** per report, and a **"Delete reports older than N days"** control
(always keeps the newest), mirroring the device-table backup cleanup.

Because the web server has no direct access to the report directory, every
operation is handled by the CGI behind the fetchconfig-web login:

* **View** opens a page (like *View fetchconfig log*) that parses the report's
  `device-diff` blocks and shows each device as a collapsible section
  (collapsed initially, with *Expand all* / *Collapse all*), re-rendering the
  diff with escaped text -- the report's own markup/styles are never injected.
  A report with no device sections shows a short note instead.
* **Download** streams the original self-contained `.html` file as an
  attachment (it is not rendered in the fetchconfig-web origin).
* **Delete** / prune remove `report-*.html` files from the report directory
  (strict `report-*.html` basename validation, no traversal).

Only files named `report-*.html` are listed or touched; the directory is
expected to be group-writable with the set-group-id bit so fetchconfig and the
web user share it.

### Setup devices and the device-table editor

The **Setup** menu item -- shown in the title bar for the `admin` account
(`$PROTECTED_USER`) or any user granted the device-table edit right --
displays the raw contents of `$DEVICE_TABLE` exactly as `fetchconfig.pl`
reads it (no parsing or filtering), using the same monospaced block and
copy-to-clipboard button as the backup content view. It has an **Edit
device table** button that opens the structured editor, and (for admins
only) a **Bulk Edit** button -- see "Bulk edit" below.

Because the device table can carry device login credentials on its
`default:` lines (the same class of secret the credential-masking on
Backup Now exists to protect), both the view and the editor are treated as
sensitive: the menu link and the actions are available only to `admin` or a
user with the edit right, re-checked server-side (`user_may_edit_table()`),
since `?action=setup`/`?action=edit_table` are reachable directly by URL.

#### The structured editor

The editor (`action=edit_table`, gated as above, POST + CSRF on save) works
on the table as three tabs -- **Devices**, **Defaults (per model)**, and
**Email notification** -- rather than as raw text:

- Each device / default / email line is a card; its options are typed
  fields driven by a per-model **option catalog** (transcribed from the
  fetchconfig README): masked secret fields (`pass`/`enable`/`password`)
  with a show toggle, on/off toggles (`changes_only`, `on_fetch_cat`,
  and ProCurve's `debug`), numeric fields, a `;`-separated recipients field
  for email `to`, a `timezone` selector, and text/path fields. Mandatory
  options are marked; an option not recognized for the model is kept and
  flagged "(unrecognized)" rather than dropped.
- **+ add option** on each card lists only the options valid for that
  model (or the email keys) that aren't already present; **+ Add device** /
  **+ Add model defaults** add new rows; each option and each row can be
  removed. A newly-added device is placed at the **top** of the Devices
  list (as the first entry), not the bottom.
- The **Email notification** tab edits the `email:` line: `from`, `to`
  (`;`-separated recipients) and `smtp` are mandatory; `port`, `user`,
  `password` (SMTP AUTH), `footer` and `tls` are optional. The SMTP server's
  port can be given three ways -- `smtp=host`, `smtp=host:port`, or
  `smtp=host` plus a separate `port=<n>` -- and an explicit `port=` wins over
  a port in the host, which wins over the default (25 for `tls=off`/`starttls`,
  465 for `tls=ssl`). `footer` is the copyright /
  attribution text shown in the summary e-mail's footer (the trailing
  " - Version <n>" is appended automatically; the value must not contain a
  comma, since commas separate options). `tls` is a drop-down selecting the
  SMTP transport security: `off` (default, plain SMTP), `starttls` (upgrade an
  initially-clear connection, typically port 25/587) or `ssl` (TLS from the
  start, typically port 465).
- The **Devices** tab has **Device-ID** and **comment** filter boxes (with a
  Clear button); they narrow the visible device cards by substring, combined
  with AND, matching against each card's *live* field values (so filtering
  keeps working as you edit). The filter choices persist in a cookie
  (`fcweb_editfilter`, separate from the device-list filter). Filtering only
  hides cards -- every device is still submitted on save -- and adding a
  device clears the filter so the new (empty) card is visible.
- The **Devices** tab paginates at 100 devices per page, with Prev/Next
  navigation, over the *filtered* set (all devices are still submitted on
  save regardless of the visible page). Adding a device jumps to page 1 so
  the new entry is visible at the top.
- **Device-ID** and **Host** get wider fields; on save the host is
  validated as an IPv4/IPv6 address or a hostname/FQDN, and Device-IDs must
  be present, valid, and unique.
- **Preview raw table** shows the exact text that Save would write, with
  passwords masked, without touching the file. From the preview you can
  **Save changes** directly (your edits are carried forward) or go **Back to
  editor** to keep editing. The editor's own **Save changes without preview**
  button skips the preview step.

**Masked-secret write-back:** secret fields show a fixed placeholder
(`\__unchanged__/`) for an existing value, never the real password. On save,
a field still holding that placeholder keeps the stored value (recovered by
re-reading the current table); any other value -- including empty --
replaces it. New devices/defaults must have their password typed in.

**Concurrency guard:** the editor records the device table's modification
time when it opens and sends it back on save. If the file changed on disk in
the meantime (another admin, or an OS-side edit), the save is refused with a
message and nothing is written -- so two overlapping edits can't silently
clobber each other.

**On save**, the editor writes the table in a fixed layout, regrouping the
records by kind (original relative order preserved within each group) and
discarding the original free-form comments in favour of fixed section
headers:

```
# DEFAULT OPTIONS SECTION

# eMail

email: ...

#              model           options

default: ...

# Unknown

<unknown directive lines, if any>

# DEVICES SECTION

# model        dev-unique-id  hostname  device-specific-options

<device lines>
```

The `# eMail` and `# Unknown` blocks appear only when there's content for
them; any directive line the editor doesn't model (not `email:`/`default:`/
a device line) is preserved under `# Unknown` at the end of the defaults
section. A timestamped backup of the previous table is saved **first** to
`$BACKUP_DEVICE_TABLE` (default `/usr/local/fetchconfig/backup`, created
automatically if its base directory is writable by the web-server user --
otherwise create it by hand at install time, see the note below) as
`<device_table_name>.<YYYY-MM-DD_HHMMSS>.bak`, and then
`$DEVICE_TABLE` is overwritten **in place**.

The in-place write (rather than the usual atomic temp-file-plus-rename) is
deliberate: it matches a common permission setup where the web-server user
can write the existing `device_table` file and the `backup` directory, but
**not** create new files in `/usr/local/fetchconfig/` itself. So the two
things the save needs write access to are the `device_table` file and
`$BACKUP_DEVICE_TABLE`; the containing directory does not need to be
writable. The trade-off is that a crash midway through the write could leave
a truncated table -- the just-written timestamped backup is the recovery
point, and the save reports its path in that case.

> **`$BACKUP_DEVICE_TABLE` directory creation.** The app will try to create
> `$BACKUP_DEVICE_TABLE` on first use, but that only succeeds if the base
> directory it lives in (e.g. `/usr/local/fetchconfig/`) is itself writable
> by the web-server user -- which, in the recommended setup, it is **not**.
> It is therefore better to create the backup directory **manually during
> installation** and give it (only) to the web-server user. If you create it
> by hand, the base `fetchconfig` directory can keep its normal ownership and
> permissions -- `755 fetchconfig_user:fetchconfig_group` -- while just the
> backup directory is made writable by the web server. For example:
>
> ```sh
> # base fetchconfig dir stays owned by the fetchconfig user, mode 755
> chown fetchconfig_user:fetchconfig_group /usr/local/fetchconfig
> chmod 755 /usr/local/fetchconfig
>
> # create the device-table backup dir and make it writable by the web user
> mkdir -p /usr/local/fetchconfig/backup
> chown www-data:www-data /usr/local/fetchconfig/backup   # web-server user/group
> chmod 755 /usr/local/fetchconfig/backup
> ```

The editor's option catalog is easy to extend: each model maps to a set of
`{option => {type, mandatory}}` entries in `%MODEL_CATALOG`, built from a
shared common set (`timeout` is optional everywhere -- fetchconfig defaults it
to 30 seconds). `procurve` and `procurve-ssh` use the common set plus an
optional `enable` (manager/enable password) and `debug=on|off`; `comware-ssh`
uses the common set plus `debug`; `cisco-sg300` adds optional `enable` and
`show_cmd`; `dell` adds optional `show_cmd`; `mikrotik` is user/pass only (no
`enable`). The catalog covers all
registered models, including `hirschmann` and `zyxel`
(user/pass/repository/keep mandatory; `enable` and `show_cmd`
optional), with `zyxel` also accepting `debug=on|off`, `planet-ssh` (PLANET
managed switches, Cisco-IOS-like over SSH -- user/pass mandatory; `enable`,
`show_cmd`, `debug`, `banner_timeout` and `type_delay` optional), `aruba-cx-ssh` (Aruba CX / AOS-CX over SSH -- user/pass mandatory,
no `enable`; `show_cmd`, `debug`, `banner_timeout` and `prompt_settle_ms`
optional), `nexus-ssh` (Cisco Nexus / NX-OS over SSH -- same option set as
`aruba-cx-ssh`: user/pass mandatory, no `enable`; `show_cmd`, `debug`,
`banner_timeout` and `prompt_settle_ms` optional), `mediant-sbc` (AudioCodes
Mediant SBC / gateway, current Cisco-style CLI -- user/pass/`enable`
mandatory; optional `transport`=`ssh`|`telnet`|`auto` (default `ssh`;
`auto` falls back to telnet only when no SSH service answers), plus
`pager_cmd`, `show_cmd`, `debug`, `banner_timeout` and `prompt_settle_ms`), the
template-driven `generic` model (see "The generic (template-driven) model"
above), and the
web-managed binary-backup models `tplink-web-sg105e` and `procurve-web-1700`
(common set + `debug=on|off`, no `enable`/`show_cmd` since they have no CLI;
`procurve-web-1700` also makes `user` optional, as the switch has only a
manager password -- see "Web-UI (binary) backups" below).

`procurve-snmp` (HP ProCurve ProVision, incl. 4000M/8000M, backed up over
SNMP+TFTP) is the odd one out: it has **no** `user`/`pass`. Instead its
mandatory option is `community` (the SNMP read-write community, a masked
secret), alongside `repository`/`keep` mandatory and `timeout`,
`snmp_version`, `oid`, `remote_file`, `changes_only`, `on_fetch_run`,
`on_fetch_cat`, `timezone`, `filename_append_suffix` and `debug` optional.
Its backup is an ordinary text config, so it uses the normal content view
and the Compare / Side by Side diffs (no syntax highlighter). The
`community=` option value is masked (as `?***?`) wherever config text is
shown, like `pass=`/`enable=`.

#### The generic (template-driven) model

`generic` is fetchconfig's template-driven model: its device interaction is
described by a template file rather than built into the module. In the device
table it is selected with the model name `generic` and a `model=<template>`
option that names the template (e.g. `model=cisco-ios` loads
`templates/cisco-ios.tmpl`). Mandatory options are `user`, `pass`,
`repository`, `keep` and `model`; optional ones include `transport`
(`ssh`/`telnet`), `enable`, `changes_only`, `timeout`, `fetch_timeout`,
`banner_timeout`, `fetch_delay`, `prompt_settle`, `max_visits`, `strip_ansi`,
`prompt_head`, `prompt_tail`, `ssh_extra_opts`, `template_dir`, `debug`,
`show_cmd`, `on_fetch_run`, `on_fetch_cat`, `timezone` and
`filename_append_suffix` (most of the timing/prompt options may also be set in
the template file).

In the editor the `model=` option is rendered as a **drop-down of the
available templates** rather than a free-text field, scoped to the directory in
effect for that row. The list comes from `fetchconfig.pl -devices=<table> -t`,
whose tab-separated output gives, for every template, its section
(`default`/`device`), full path, model and directory:

* on the **Defaults (per model)** tab the dropdown offers the models in the
  `default` section (that single default directory);
* on the **Devices** tab it offers the models in the `device` section for the
  device's own `template_dir`, or -- when the device sets none -- for the
  directory the `default: generic` line uses.

When you set or change a row's `template_dir` and leave the field, the model
list is re-evaluated. For a directory fetchconfig already lists it comes from
the snapshot taken at page load; for a directory you just typed that `-t` does
not yet list -- the common case, since `-t` only reports *configured*
directories -- the editor asks the server to scan that directory for `*.tmpl`
files (the read-only `?action=template_models` endpoint), so its templates are
immediately selectable without having to save a device that uses the directory
first. A red warning appears when no templates match the directory, and a
stored model that is not present in the current directory is shown disabled
(not selectable) so you notice it. An information icon notes that templates
*added on disk* to an already-listed directory appear after a page reload.

If `-t` cannot run, reports a missing template directory (exit 2) or finds no
templates at all (exit 1), the whole device-table editor shows the fetchconfig
output instead (the same error as the template viewer).

`model=` may be set on a `default: generic` line so all generic devices
sharing one template need not repeat it; a device line can still override it.
Accordingly the editor requires `model=` on a generic **device** line only
when no `default: generic` line supplies it -- otherwise the device inherits
the default. The dropdown appears on both the `default:` and device forms.

#### Directory allow-list (`directory:`)

The device table may carry an optional **allow-list** that restricts which
repository and template directories a device or `default:` line may use. It is
a set of `directory:` lines in the DEFAULT OPTIONS SECTION:

```
# DEFAULT OPTIONS SECTION

# directory

# directory allow list - must be directly edited on the server
directory: repository $REPO1     /usr/local/fetchconfig/config
directory: template   $TEMPLATE1 /usr/local/fetchconfig/templates
directory: template   $TEMPLATE2 /usr/local/fetchconfig/templates_alt
# directory allow list - must be directly edited on the server

# eMail
...
```

Each line is `directory: <kind> <$ALIAS> <path>`, where `kind` is
`repository`, `template`, `fetch_run` or `report`. fetchconfig expands the `$ALIAS` at run
time, so a device or default line may write either the full path or the alias
(`repository=$REPO1`, `template_dir=$TEMPLATE2`).

The allow-list is read via **`fetchconfig.pl --list-allowed-dirs`**, which also
verifies the directories exist on disk: exit 0 = all present, exit 2 = one is
missing (named in an error line). On exit 2 the template viewer and the
device-table editor show the fetchconfig output and refuse to proceed, exactly
like a missing template directory.

`fetch_run` controls the `on_fetch_run` device option (a command line run after
a fetch). `directory: fetch_run none` **disables** `on_fetch_run` entirely
(it cannot be added, and an existing one blocks saving); otherwise
`directory: fetch_run $CMD1 /path` allows commands under that directory. Because
`on_fetch_run` is `<directory>/<command with options>`, the editor shows it as
**two fields** -- a directory drop-down (the `$ALIAS`, with the expanded path in
gray) and a command-plus-options text field -- combined into
`$CMD1/command -options` on save. A full path in the command is reduced to its
alias on save, like the other directories. If no `fetch_run` line exists at all,
`on_fetch_run` is unrestricted (free text).

`report` controls the HTML-report feature (fetchconfig writes a report into an
allow-listed report directory). `directory: report none` disables reporting
(the `report_dir` email option cannot be used); otherwise
`directory: report $REP /path` allows a report directory. The Email-notification
tab exposes the report options: `report_dir` (a drop-down of the allowed report
aliases), `write_report` (on/off), `email_max_diff` (device-count threshold for
including diffs in the e-mail; 0 = none), `web_report_url` (the URL of the
fetchconfig-web Report page, e.g. `http(s)://host/.../fetchconfig-web.cgi?action=report`),
`report_logo` (a logo file name inside the report directory, embedded at
250x50 px), and `report_days` (prune reports older than N days; 0/unset = no
prune). `report_dir` stores its `$ALIAS` and is enforced against the allow-list
exactly like `repository`/`template_dir`. A further option, `report_hide`, is a
regex applied to mask matching text in the report; it may be given more than
once (one per `email:` line), is edited as repeatable ~40-character fields, and
is parsed rest-of-line verbatim (no quoting; e.g.
`report_hide=(?<=wpa-passphrase )\S+`). Each pattern is checked on save for valid regex
syntax and balanced brackets; two `report_hide=` on one line is a parse error and that line is
ignored.

**Security.** fetchconfig-web reads the `directory:` block **directly from the
device table on the server** -- never from the browser -- so it cannot be
forged. The block is intentionally **not editable in the web UI**: it is
wrapped in the `# directory allow list - must be directly edited on the server`
armor comments (shown in **red** in the Setup config view), and on save it is
written back verbatim from disk. When the allow-list is present:

* On the device-table editor, `repository=` and `template_dir=` become
  **drop-downs of the allowed entries** (labelled by their `$ALIAS`), with the
  expanded path shown in gray beside the field. A stored value that is not on
  the list is shown as a disabled *"(current, not allowed)"* option.
* Saved lines always store the **`$ALIAS`** (a literal path that matches an
  allowed path is rewritten to its alias), so changing a directory only means
  editing the `directory:` section -- every device follows automatically.
* A table that references a directory not on the list can still be opened in
  the editor (so it can be fixed), with a red banner naming each violation, but
  **the save is blocked** until the violations are resolved.
* Generic-model template lookups use the alias's **expanded path**.

When no `directory:` lines exist, the allow-list is inactive and the path
fields stay free-text, exactly as before.

User accounts live in a PostgreSQL table, `users`:

| Column              | Type    | Notes |
|---------------------|---------|-------|
| `username`          | TEXT    | primary key |
| `pass_hash`         | TEXT    | Apache MD5 (`$apr1$`) or any format `verify_password()` accepts |
| `edit_device_table` | BOOLEAN | per-user right to view and edit the device table |
| `admin_function`    | BOOLEAN | per-user "full admin" right (behaves like the built-in `admin`) |

Point `fetchconfig-web.cgi` at it with the four `$DB*` config values, which
must match the application login created during setup. A fresh connection
is opened per request. Password hashes are generated in **pure Perl**
(`apr1_hash()`, byte-for-byte identical to `openssl passwd -apr1`), so no
`htpasswd` binary -- and no sudo rule for one -- is needed anymore.

#### Bulk edit

The **Bulk edit** item in the Setup devices menu (`?action=bulk_edit`, **admin
only** -- stricter than the edit-device-table right) opens a plain-text
editor for the device lines only. The textarea is preloaded with the
**complete device list**, one device per line as
`model` `device-id` `host` `[options]` (tab-separated), with **passwords in
plain text** -- so they can be edited and are saved verbatim rather than
masked.

Saving **replaces the entire `DEVICES SECTION`**: whatever is in the
textarea becomes the new complete device list. Removing a line deletes that
device; an empty box removes every device. The `default:`, `email:`, and
any unknown-directive lines are left untouched. A confirm dialog summarises
the resulting device count (and warns when it would remove all devices).

Validation is **all-or-nothing** and uses the same checks as the structured
editor (known model; Device-ID present, valid, and unique; valid
IPv4/IPv6/FQDN host; no control characters). If any line fails, nothing is
saved and the page is redrawn with your text intact and the error list.
Saving goes through the same safe path as the editor -- mtime concurrency
guard, timestamped backup to `$BACKUP_DEVICE_TABLE`, in-place overwrite,
POST + CSRF.

### Tools (admins only)

The **Tools** menu item -- shown in the title bar between Setup and User to
any **admin** (the built-in `admin` account or a user with `admin_function`)
-- groups admin utilities, each in its own titled box. All actions re-check
the admin requirement server-side (not just menu hiding), since they're
reachable directly by URL.

#### Orphaned Configuration Cleanup

Orphaned backups are backed-up configurations on disk whose device is no
longer in the device table (a decommissioned or renamed device leaving its
old backups behind).

- **Check for orphaned backups** runs `fetchconfig.pl -devices=<table> -o`
  (read-only) and shows the transcript in the same layout as Backup Now: the
  scan log followed by the tab-separated listing
  (`dev_id`, file count, total bytes, path) of each orphaned backup
  directory found. `-o` exits 0 when nothing is orphaned and 1 when
  something is -- so a "1" here is reported as *found*, not an error.
- **Delete orphaned backups** runs `fetchconfig.pl -devices=<table> -o -D`,
  which deletes the orphaned directories fetchconfig finds (it uses its own
  `unlink`/`rmdir` per file -- no shell, no wildcards -- and logs each
  `rm`/`rmdir`). A JavaScript confirm dialog guards it, and the transcript is
  shown the same way; here exit 1 means at least one deletion failed.

The check is a read-only GET; the delete is a POST + CSRF state-changing
action and, like Backup Now, runs `fetchconfig.pl` through `sudo` when
`USE_SUDO_FOR_BACKUP_NOW` is set (it writes into the repository).

#### Empty Directory Cleanup

Empty directories are the date (`YYYYMM`/`YYYYMMDD`) or per-device directories
left in the repository with no files in them. A normal aged-config delete run
or the orphaned-configuration cleanup should remove these on their own; this
tool is for the occasional directory left behind by something else, such as
manual file operations. It mirrors the orphaned-configuration cleanup in both
design and behaviour.

- **Check for empty directories** runs `fetchconfig.pl -devices=<table> -e`
  (read-only) and shows the transcript: the scan log followed by a
  tab-separated listing (`device`/`day`/`month`, path) of each empty directory
  found. `-e` exits 0 when nothing is empty and 1 when something is -- a "1"
  here is reported as *found*, not an error.
- **Delete empty directories** runs `fetchconfig.pl -devices=<table> -e -D`,
  which removes the empty directories fetchconfig finds (appending `deleted`
  to each listed line) and reports a `removed N of M empty directories
  (X device, Y day, Z month)` summary. `-e -D` exits 0 on success. A
  JavaScript confirm dialog guards it, and the transcript is shown the same
  way.

The check is a read-only GET; the delete is a POST + CSRF state-changing
action and, like the orphaned-configuration delete, runs through `sudo` when
`USE_SUDO_FOR_BACKUP_NOW` is set.

#### Restore device table

Lists the timestamped device-table backups kept in `$BACKUP_DEVICE_TABLE`
(the `.bak` files written before every editor/bulk-edit save), newest first.
A synthetic **current** row (the live `$DEVICE_TABLE`) appears at the top --
selectable for comparison, but with no View/Restore/Delete actions. Each
backup row has a checkbox and **View / Restore / Delete**:

- **View** (read-only GET) shows the backup's contents in a `pre.config`
  block with a copy button. Passwords are **masked by default**; unticking
  the **Mask passwords** checkbox (see below) shows them in plain text so a
  backup can be inspected fully before restoring.
- **Restore** (POST + CSRF, confirm dialog) writes the chosen backup over
  `$DEVICE_TABLE`. The **current** table is backed up first (into the same
  `$BACKUP_DEVICE_TABLE`, so a restore is itself undoable), then the backup
  is written in place via the shared safe-writer. No mtime guard here -- a
  restore is an intentional "make it this" action.
- **Delete** (POST + CSRF, confirm dialog) permanently removes the `.bak`
  file.

Two compare buttons -- **Compare Selected** (unified diff) and **Side by
Side Selected** (two-column view) -- let you compare exactly two ticked rows
(any mix of `current` and backups). The **older** configuration is always the
red/left side and the **newer** the green/right side: `current` (the live
table) is always treated as newest, otherwise the backup with the later
timestamp is newer -- independent of the order you ticked them. Both views
are **whitespace-normalized, quote-aware**: each line's runs of spaces/tabs
are collapsed and trimmed *outside* double quotes, so two tables that differ
only in tab-vs-space alignment compare as identical, while a real change
inside a quoted value (e.g. a comment) still shows. The unified view lists
**only the changed lines** (removed in red, added in green; unchanged lines
are omitted); the side-by-side view shows the full configs with rows tinted
green/red/amber for added/removed/changed. The diff is computed in-app
(`Algorithm::Diff`), not via `fetchconfig.pl`.

A **Mask passwords** checkbox (checked by default) controls whether View and
Compare mask `pass=`/`enable=` values. It's honoured server-side -- masked
unless the checkbox is unticked -- so passwords are never shown in plain
text unless an admin explicitly asks for it.

Only the backup **basename** is ever accepted from the browser, and it must
match the exact backup pattern
(`<device_table_name>.YYYY-MM-DD_HHMMSS.bak`) -- no slashes, no `..` -- so
these actions can only ever touch a real backup inside `$BACKUP_DEVICE_TABLE`
(no path traversal).

**Delete backups older than N days.** Below the backup table, a small form
lets you bulk-remove old backups: enter a number of days (default 30, must be
a whole number >= 1) and press **Delete backups older than days** (POST +
CSRF, confirm dialog). Every backup whose timestamp is older than that many
days is deleted -- **except the single newest backup, which is never deleted
by this function**, even if it is itself older than the threshold, so you
always keep at least one restore point. A backup's age is taken from the
timestamp in its **filename**, not the file's mtime, so a restore or copy that
touches the file doesn't change how old it counts as. The form is only shown
when there are at least two backups (with one or none there is nothing this
could remove). The result -- how many were deleted and which backup was kept
-- is reported as a flash message on the tool page.

#### Devices without backups

Scans every Device-ID in the device table and lists those that have no
stored backups yet (never backed up). Press **Start scan** (which becomes
**Cancel scan** while running); a progress bar advances as each device is
checked, and the devices without backups are listed at the end (or "all
devices have at least one backup").

Because a CGI produces a single response, the live progress bar is driven
**client-side**: JavaScript walks the device list one at a time, calling a
small read-only JSON endpoint (`?action=check_backups_one&dev=<id>`,
admin-only) per device. Each call runs `fetchconfig.pl -l <dev>` and returns
just a status word -- `has` (at least one backup), `none` ("no backed up
config files found"), or `error`. The device IDs to scan are emitted into
the page from `read_device_ids()`, and the endpoint validates `dev` against
`^[\w.\-]+$`.

#### Check devices for empty backups

Works the same way, but flags devices that have one or more **empty**
(zero-byte) backup files -- a fetch that connected but saved nothing. Each
device is checked with `fetchconfig.pl -z <dev>` via the
`?action=check_empty_one&dev=<id>` endpoint. `-z` exits **1** when at least
one 0-byte backup is found (0 when all are non-empty), printing a
tab-separated size-0 line; the endpoint maps that to `empty`, an exit of 0
(or the "no backed up config files found" case) to `clean`, and any other
non-zero exit to `error`. Same Start/Cancel button and progress bar. Both
scan tools share one implementation (`render_scan_tool`), with each box's
element IDs namespaced so they can share markup, and both list any
devices that could not be checked by name.

#### Check devices for consistent backup suffixes

Flags devices whose stored backups have a filename-suffix problem. Each device
is checked with `fetchconfig.pl -s <dev>` via the
`?action=check_suffix_one&dev=<id>` endpoint. `-s` returns three codes:

- **0** -- the backups' suffixes are consistent *and* match the configured
  `filename_append_suffix`.
- **1** -- the backups have **inconsistent** suffixes (they differ from each
  other), e.g. one plain backup (`...CEST`) and one ending in `.bak`
  (`...CEST.bak`).
- **2** -- the backups are consistent with each other but their suffix does
  **not** match the currently configured `filename_append_suffix`.

The endpoint maps exit 0 to `consistent` and both exit 1 and exit 2 to a
single `issue` status (any other failure to `error`), so the Tools box lists
every Device-ID with a suffix problem under one list, with a note to check the
specific device page for details. That per-device detail is the **Check
backup suffixes** button on a device's backup list
(`?action=checksuffix&dev=<id>`), which shows the full `fetchconfig.pl -s`
output -- including the per-file suffix breakdown -- in a copyable block and
spells out which of the three cases applies, the same way the empty-backup
check does.

#### View fetchconfig log

The Tools menu has a **View fetchconfig log** tool with a **Display log**
button that opens the log on its own page (`?action=view_log`, admin only).
It shows the output written by the scheduled (cron) `fetchconfig.pl` run. The
log file is set with the optional `FETCHCONFIG_LOG` key in
`/etc/fetchconfig-web.cfg` (full path); if it's unset the section says so, and if
the file can't be read an error is shown on the log page.

The log is split into collapsible sections at each
`fetchconfig.pl: info: -----[NAME]-----` header. Each section shows a `+`/`-`
toggle and its `[NAME]` in bold -- **green** for a successful section, **red**
for a failed one (its body contains `error:` or `failed`). Failed sections
start **expanded**; successful ones start collapsed. **Expand all** /
**Collapse all** buttons toggle every section at once, and a **Log table load
time** line is shown below the output. At most `LOG_MAX_DEVICES` sections are
rendered (default **1000**); if the log has more, a warning is shown above the
output and only the first `LOG_MAX_DEVICES` are displayed.

#### Template viewer

The Tools menu has a **Template viewer** tool with a **Show templates**
button that opens a list of the generic-model templates on its own page
(`?action=view_templates`, admin only). The list comes from
`fetchconfig.pl -devices=<table> -t`, whose tab-separated output gives the full
path, model and directory of every template (in both the `default` and `device`
sections). If `-t` reports a missing directory (exit 2) or finds no templates
(exit 1) the page shows the fetchconfig output instead of a list. Every template
is listed once, de-duplicated by full path only:
the same template name may legitimately exist in more than one directory (in
the device table a generic model is the combination of `template_dir` and the
template name), so same-named files in different directories appear as separate
rows, each with its full template name (path including the file), size and modification time. The list is sorted
by template name.

Clicking **View** opens a template read-only (`?action=view_template`) in the
same output window as a configuration view, with **template syntax
highlighting** (directives, state keywords, `/regex/` patterns, quoted strings,
and the `->` arrow; `expect` is green, `send`/`done` red, `goto` purple). The `path` parameter is validated against the discovered
template list -- it must contain no `..` and must exactly match a scanned
template path -- so the viewer can never read files outside the template
directories.

#### Template editor

Each row in the template list also has an **Edit** link
(`?action=edit_template`, admin only). The editor is a vertical split: the left
**Editor** pane is a plain textarea; the right **Checked version** pane shows
the template with syntax highlighting, refreshed whenever you press **Check
syntax** (so the right pane always reflects the last checked buffer). The
buttons are:

- **Check syntax** -- writes the current buffer to a temporary file and runs
  `fetchconfig.pl --check-template <tmpfile>` (a structural check; no device
  table, no device contact). The result (`ok`, or `NOT ok` with the per-line
  errors) is shown and the right pane is re-highlighted.
- **Save** -- runs the same check first and **refuses to save if it fails**
  (a broken template would break the next scheduled backup). On success the
  file is written and the previous version is kept as `<template>.tmpl.bak`
  (a single backup, overwritten on each save).
- **Revert to last version** -- shown only when a `<template>.tmpl.bak` exists;
  restores that backup over the template. Not itself undoable.
- **Cancel** -- returns to the template list.

**Writing the files.** Template directories are usually owned by the account
fetchconfig runs as and not writable by the web-server user, so saving goes
through a small privileged helper, **`fetchconfig-web-install-template.pl`**
(shipped with this package), run via `sudo -n`. Point the config at it:

```
TEMPLATE_HELPER = /usr/local/fetchconfig/fetchconfig-web-install-template.pl
```

> **Note on write access.** If `TEMPLATE_HELPER` is set, saves and reverts
> go through that sudo helper; if it is empty, the web user must be able to
> write the template directories directly. The helper path is independent of
> `USE_SUDO_FOR_BACKUP_NOW` (which only governs Backup Now), so a template
> write can use sudo even when Backup Now does not, and vice-versa.


and grant the web-server user permission to run just that helper, e.g. via
`visudo`:

```
www ALL=(root) NOPASSWD: /usr/local/fetchconfig/fetchconfig-web-install-template.pl
```

(replace `www` with your web-server user). The helper is invoked as
`install <tmpfile> <target.tmpl>` (back up, then write) or
`revert <target.tmpl>`, and independently enforces that the target is an
**absolute** path, contains **no `..`**, and ends in **`.tmpl`** -- so even a
compromised caller cannot make it touch anything else. Saving through the helper
requires `USE_SUDO_FOR_BACKUP_NOW = 1`.

If `TEMPLATE_HELPER` is empty (or sudo is disabled), the editor writes the file
**directly**, which only works if the template directory is writable by the
web-server user; otherwise Save reports a clear error. In all cases the web
application also validates the target against the live template list (from `-t`)
and rejects any path containing `..` before doing anything. Only **plain
regular files** are accepted: a `.tmpl` entry that is a symbolic link or a
hard link (link count > 1) is still listed, with a warning, but cannot be
viewed or edited -- a symlink could point outside the template directories,
and a hard link would make a write reach a second name. The helper enforces
the same rule independently.

The check is **structural only** -- fetchconfig verifies the template's grammar,
not that it actually drives your device; always test a changed template against
the real hardware.

The editor toolbar also has a **Help templates** button that opens
`<HELP_BASE_URL>/README.template_engine.html` (the template-engine manual) in a
new browser tab. **`HELP_BASE_URL`** (default `/fetchconfig-web`) is the URL
base under which that documentation is served; put `README.template_engine.html`
there (e.g. alongside the other served assets). If the file is not installed the
button simply leads to a 404.

### Per-site device access

Users can be limited to **see and edit only the devices for their site(s)**.

**How it works.** A device carries an optional `site=<code>` option in the
device table. Each site code is defined in the database (`sites` table: id,
code, description) and users are assigned one or more codes (`user_sites`). A
device is visible to a user only if its `site=` is one of their codes.

* **Site 0** (code `*`, shown as **"any site" / All sites"**) is the reserved
  sentinel: a user who holds site 0 is **unrestricted** (sees and edits
  everything, the default). The built-in **admin** always has site 0 and cannot
  be limited. A user with `admin_function` is likewise unrestricted.
* A device with **no `site=`** belongs to "any site" (site 0), so it is visible
  **only to unrestricted users**. In the editor an untagged device shows a red
  **"any site"** marker.

**What a site-limited user sees.**

* The **Devices** and **Status** pages list only their devices; **direct URLs**
  to another site's device (view/compare/download a backup, Backup Now) are
  refused.
* **Setup** opens the graphical device editor directly, showing only their
  devices. The **Defaults** tab is **view-only**; there is **no Email/Reporting
  tab**, **no Bulk edit** and **no raw-config view**. **Tools** is
  administrator-only.
* On a device, `site=` is a drop-down of **only the codes the user may assign**;
  a new or copied device must be given one of their codes, and the device-id is
  read-only.
* **Reports**: the report is parsed and only the sections for the user's devices
  are shown. Downloading the full (unfiltered) HTML file requires the per-user
  **"download full report"** right.

**Saving (merge).** When a site-limited user saves, their edits are **merged
into the full device table on the server**: every device and section they
cannot see is preserved verbatim; only their own device lines are replaced. The
save is refused if it would touch a device outside their sites, assign a site
they do not hold, or create a duplicate device-id.

**Validation.** On load and save, a `site=` value that is not a known code is
reported as a clearly visible error, and device-ids must be unique table-wide.
`fetchconfig.pl` ignores `site=`, so the CLI tool is unaffected.

**Managing sites (admin).** The **User** page has a **Manage sites** link to a
page that adds, edits and deletes site codes. A code can be deleted only if it
is **not assigned to any user**. Editing a code is **atomic**: the `sites` row
is updated and every `site=<old>` in the device table is rewritten to the new
code, so no device is orphaned. Per user, the **Edit sites** button opens a
searchable checklist (scales to ~1000 sites) to assign codes and toggle the
"download full report" right; the User listing shows each user's first 10 codes
with a tooltip listing all.

**Enabling it on an existing install.** Run the bundled
`fetchconfig-web-dbupdate.sql` once (see
[The user database](#the-user-database)); it creates the `sites` and
`user_sites` tables, adds the `download_full_report` column, seeds site 0, and
**starts every existing user as unrestricted** so nobody is locked out. Then
assign sites per user and tag devices with `site=` as needed.

### User management via the web UI

The **User** menu item (every page's title bar) lets any logged-in user
change their own password, and lets any **admin** (the built-in `admin`
account or any user with `admin_function`) manage other accounts -- all
against the database, no shell access required.

- **Change your password** -- available to everyone. Requires your current
  password (re-checked via `verify_password()` against the stored hash)
  plus a new password typed twice; the new hash is written with `UPDATE`.
- **Add user** / **Delete user** -- shown only to admins, and enforced in
  the request handler itself, not just hidden in the page. Add user has an
  "Allow this user to view and edit the device table" checkbox
  (`edit_device_table`) and a "Grant admin functions" checkbox
  (`admin_function`).
- **Reset another user's password** -- shown only to admins, via the
  "Change password" button next to each non-`admin` user. Sets a new
  password *without* the current one; refuses to target `admin` itself
  (admin's own password only changes through "Change your password").
- **Grant / Revoke admin functions** -- the "Admin functions" column has a
  per-user toggle (`do_set_admin_right`). A user with `admin_function`
  becomes a **full admin**, identical in capability to the built-in
  `admin`: user management, Tools, and Setup/device-table editing. Any admin
  can grant or revoke it (including revoking their own), and it can target
  any account except the built-in `admin`.
- **Grant / Revoke edit right** -- the "Can edit device table" column has a
  per-user toggle (`do_set_edit_right`). A user with the right gains access
  to the **Setup** page and the device-table editor.
- The built-in **`admin`** account is special in only two ways: it can never
  be deleted, and its `admin_function` and `edit_device_table` are locked on
  (shown as "always (admin)", not toggleable). A user who merely *has*
  `admin_function` is a full admin but is otherwise a normal account -- it
  can be deleted, and its flags toggled, by any admin (including itself).
  Because `admin` is always an admin, you can never lock every admin out.
- New/changed passwords must be at least `$MIN_PASSWORD_LENGTH` (8)
  characters -- a web-UI-side check.
- All of these actions redirect back to the User page with a short flash
  message (`?msg=`/`?err=`), so refreshing never resubmits the form.

#### Default-password warning

An account still using the literal password `$DEFAULT_PASSWORD`
(`fetchconfig`) gets a persistent banner after login until it changes to
something else: **"Change the default admin password."** for `admin`, and
**"Do NOT use the application name as password."** for anyone else. The
flag is set at login (recorded as a 4th line in the session file, never in
the cookie) and cleared automatically when the password is changed away
from the default.

### Help page

The **Help** menu item shows a short description of the application. It
reads `$HELP_FILE` as an HTML *fragment* -- no `<html>`/`<head>`/`<body>`
tags, just the content -- and drops it straight into the page's own title
bar/nav/footer chrome. A ready-to-use `help.html` is included; deploy it
with:

```sh
mkdir -p /www/pub/fetchconfig-web
cp help.html /www/pub/fetchconfig-web/help.html
```

`$HELP_FILE` is a **filesystem path**, read directly with Perl's `open()`
-- it is not the same as this file's HTTP-visible location. The web
server's existing mapping of the URL path `/fetchconfig-web/` to the
filesystem directory `/www/pub/fetchconfig-web/` means the same file is
also reachable in a browser at `/fetchconfig-web/help.html` -- a
server-relative path with no hostname, since that mapping applies on
whichever host this is deployed to. `fetchconfig-web.cgi` itself never
needs that URL (it reads the file from disk, not over HTTP), but it's
worth knowing if you ever want to link to the raw file directly.

If the file is missing (e.g. before you've deployed it), Help still works:
`fetchconfig-web.cgi` falls back to a built-in description covering the
same features, and names the expected filesystem path so it's obvious
where to put it. Since this content is operator-authored, not user input,
it is included verbatim (not run through `esc()`) -- treat it the same as
any other file you place on the server, i.e. don't let untrusted parties
write to it.

### User-interface conveniences

#### Floating Top / Bottom navigation

Long-scrolling pages -- the device list, Setup, the device-table editor, the
backup content view, and the side-by-side diff -- carry a small pair of
floating **&#9650; Top** / **&#9660; Bottom** buttons (`top_bottom_nav()`),
`position: fixed` in the **bottom-right** corner so they never overlap the
title bar's Log out link. They smooth-scroll to either end of the page (with
a plain-jump fallback for older browsers) and are hidden when printing.

## Part 4 -- Reference

### How `fetchconfig.pl` is invoked

Every interaction with fetchconfig goes through its command-line interface;
the application never reads the repository or the device table's backups
directly. The executable is `<FETCHCONFIG_PATH>/<FETCHCONFIG_BIN>` and is
always invoked in **list form** (`open3()` or, for the two privileged writes,
`exec()` after `fork`) -- never through a shell -- so no argument is subject to
shell interpretation.

Two execution paths exist:

- **Read paths** run as the web-server user through `run_fetchconfig()`, which
  captures stdout and stderr separately via `IO::Select` (no deadlock on large
  output) and returns `(stdout, stderr, exit_status, fork_error)`.
- **Write paths** (Backup now, orphaned-backup delete) run through
  `sudo -n` when `USE_SUDO_FOR_BACKUP_NOW` is set, because the web-server user
  typically cannot write the repository. These use `run_command_capture()`,
  which merges stdout and stderr into one transcript.

`T` below is the configured device table (`-devices=$DEVICE_TABLE`), `DEV` a
validated Device-ID, and `N`/`M` validated backup indices.

| Caller | Command | stdout consumed | Exit codes |
|--------|---------|-----------------|------------|
| `list_backups` | `-devices=T -l DEV` | `index<TAB>size<TAB>path` per backup | `0` = listed; `1` with `no backed up config files found` = treated as "no backups yet" (empty list, not an error); other non-zero = error |
| `get_backup_content` | `-devices=T -g DEV -n N` | raw config bytes of backup `N` (served through unchanged) | `0` = ok; non-zero = error |
| `compare_backups` | `-devices=T -g DEV -n N -m M` | unified diff of backup `N` against older backup `M` (`M > N`) | `0` = identical; `1` = differs; `>1` = error (the underlying diff's code) |
| `device_empty_status`, `run_check_empty` | `-devices=T -z DEV` | `index<TAB>0<TAB>path` for each zero-byte backup | `0` = clean (all non-empty, or none exist); `1` = at least one zero-byte backup found (an expected result, not an error); other = error |
| `device_suffix_status`, `run_check_suffix` | `-devices=T -s DEV` | per-file suffix breakdown when inconsistent | `0` = suffixes consistent and match the configured `filename_append_suffix`; `1` = suffixes inconsistent between backups; `2` = consistent but do not match the configured suffix; other = error |
| `run_orphan_check` | `-devices=T -o` | listing of orphaned repository entries | passed through to the transcript |
| `run_orphan_delete` | `[sudo -n] BIN -devices=T -o -D` | listing; stderr logs `rm`/`rmdir` per removed item | passed through to the transcript |
| `run_empty_check` | `-devices=T -e` | `device`/`day`/`month`<TAB>path per empty directory | `0` = none found; `1` = empty directories found (an expected result, not an error); other = error |
| `run_empty_delete` | `[sudo -n] BIN -devices=T -e -D` | each listed directory with `deleted` appended, plus a `removed N of M` summary | `0` = success; non-zero = at least one removal failed |
| `run_backup_now` | `[sudo -n] BIN -devices=<tmp>` | full run transcript (stdout+stderr merged) | reported to the user as-is; result state is read from the device's `.status` file |

Notes on specific paths:

- **`-z` and `-s` return `1` for a found condition, not an error.** The
  wrappers classify on the exit code first and cross-check the log text, so a
  found-empties (`-z` = 1) or inconsistent-suffix (`-s` = 1/2) result is
  reported as a normal outcome, while any other non-zero exit becomes an error.
- **Backup now does not use `-devices=T`.** It writes a temporary,
  single-device table (mode 0600) containing that device's own line verbatim
  plus a `default: <model> repository=$REPOSITORY` line, and runs
  `-devices=<tmp>`. The device line is copied verbatim -- `repository=` is
  never appended to it -- because appending onto a line whose last field is
  `pass=...` folded the repository path into the password. The temp table is
  created with `File::Temp` and `UNLINK => 1` so it is removed even if the
  process dies.
- **Compare uses fetchconfig's own diff.** `-g DEV -n N -m M` retrieves and
  diffs entirely inside fetchconfig; the application creates no temp files and
  never touches the repository for a compare.
- **Version detection** does not invoke the CLI. It reads
  `<FETCHCONFIG_PATH>/fetchconfig/Constants.pm` and calls
  `fetchconfig::Constants::version()`, caching the result against that file's
  mtime (see the version banner and footer).

### Supported hash formats

New passwords are always written as `$apr1$` (Apache MD5). Imported hashes
are read back by `verify_password()`, which accepts:

| Format               | Example prefix | Supported |
|-----------------------|-----------------|-----------|
| `{SHA}` (SHA1)         | `{SHA}...`       | **No** -- unsalted, trivially brute-forced; removed in 1.12. Reset such users' passwords via the User page. |
| Apache MD5 (apr1)     | `$apr1$...`      | Yes (pure-Perl, verified against `openssl passwd -apr1`) -- what the app now writes |
| glibc MD5 crypt       | `$1$...`         | Yes (pure-Perl, same algorithm as apr1) |
| glibc SHA-256/512     | `$5$...` / `$6$...` | Only if the *web server's* system `crypt()` supports it (true on most Linux; not guaranteed on AIX) |
| Traditional DES crypt | 2-char salt      | Yes, via system `crypt()` |
| bcrypt                | `$2a$`/`$2b$`/`$2y$` | **Not supported** -- add `Crypt::Eksblowfish::Bcrypt` and extend `verify_password()` if you need it |

## Security model

The application is a single Perl CGI behind a web server; it holds no
privileges of its own beyond the web-server user's, plus an optional narrow
`sudo` grant for two write operations (see Deployment hardening). The controls
below are grouped by concern.

### Authentication and sessions

- Passwords are verified with a constant-time `secure_compare()` in
  `verify_password()` (not Perl's `eq`), so response timing does not leak how
  many leading hash characters matched. Supported hash formats are the salted
  `$apr1$`, `$1$`, `$5$`/`$6$`, and traditional DES `crypt`; the unsalted
  `{SHA}` format is rejected.
- Sessions are opaque 192-bit tokens from `/dev/urandom`, stored server-side
  in `$SESSION_DIR` (files mode 0600 in a 0700 directory). The session id is
  validated against `^[0-9a-f]{48}$` before use as a filename, so a crafted
  cookie cannot traverse out of `$SESSION_DIR`.
- The session cookie is `HttpOnly` and `SameSite=Lax`. `-secure` is
  commented out pending HTTPS; enable it once TLS is in place.
- `SESSION_TTL` (default 28800 s) is an **idle timeout**: the stored expiry is
  slid forward on every authenticated request, so a session ends `SESSION_TTL`
  after the last activity, not a fixed time after login.
- A failed login sleeps **2 seconds** before responding, applied identically
  to an unknown user and a wrong password, to slow online brute forcing. The
  form returns a single generic "Invalid username or password" message for
  both cases to avoid username enumeration. No lockout is implemented; front
  it with `fail2ban` on the web server's access log if exposed beyond a
  trusted network.

### Authorization

- Every privileged handler re-checks rights from the database on each request;
  hiding a menu link or form is never the only gate, because the underlying
  `?action=` URLs are directly reachable.
- Admin gates use `user_is_admin()` (the built-in `admin` account, or any user
  whose `admin_function` flag is set). `add_user`, `delete_user`,
  `reset_password`, `set_admin_right`, and `set_edit_right` are admin-only in
  the handler itself. The built-in `admin` account cannot be deleted, cannot
  have its rights toggled, and cannot be targeted by `reset_password`.
- `change_password` only ever targets the current session's own username (never
  a form field), so it cannot be used to change another user's password.
- The "Show device table" view and the device-table editor are gated on
  `user_may_edit_table()` (any admin, or a user with the edit-table right).
  Setup exposes the raw device table, which may contain credentials on
  `default:` lines, so it is restricted by design.
- The Tools functions and all their endpoints are gated on `user_may_use_tools()`
  (admins). A valid CSRF token does not bypass any authorization check: the two
  are independent layers.

### Request integrity (CSRF)

- Every state-changing action requires **POST** and a valid per-session CSRF
  token; a GET is refused with `405 Method Not Allowed`, and a missing or
  wrong token with `403 Forbidden`. Read-only actions (device list, backup
  view, compare, Status, User, Help) remain GET-friendly.
- The CSRF token is a second 192-bit random value generated at login and held
  **server-side** as a line in the session file, never in the cookie. It is
  emitted as a hidden `csrf` field in every state-changing form and checked
  with the constant-time `secure_compare()`. Because it lives only in the
  session file and is only ever written into this app's own pages, a
  cross-site attacker can neither read nor guess it.
- "Log out" is a POST form with a token, not a GET link, so it cannot be
  force-triggered cross-site.

### Input validation and injection

- Device ids and usernames are validated with `valid_id()`
  (`^[\w.][\w.\-]*$`: word characters, dots, and dashes, with **no leading
  dash**). Ids are passed to `fetchconfig.pl` as positional arguments, so a
  leading `-` could otherwise be read as an option (e.g. `-D`). Backup
  indices are validated `^\d+$`.
- All external commands are invoked in **list form** via `open3()`/`exec()` --
  never through a shell -- so shell metacharacters in any argument are inert.
  See "How `fetchconfig.pl` is invoked" for the exact argument vectors.
- All database access uses placeholders (`?`), never string interpolation.
- Device-table backup filenames accepted from the browser must match the exact
  `<device_table_name>.YYYY-MM-DD_HHMMSS.bak` pattern (no slashes, no `..`), so
  restore/delete can only ever touch a real backup inside
  `$BACKUP_DEVICE_TABLE`.

### Output and data exposure

- All dynamic output passes through a single `esc()` helper
  (`CGI::escapeHTML` after secret masking), including backup file content, so a
  config containing `<`, `>`, `&`, or `"` cannot break out of the page.
- `esc()` masks credentials before escaping (`mask_secrets()`): any
  `pass...=`, `enable...=`, or `community=` token (case-insensitive key prefix)
  has its value replaced with `?***?` throughout the app's output. The value is
  read up to the next whitespace, **comma, or semicolon**, because
  device-table fields pack several `key=value` pairs into one comma-separated
  field (e.g. `user=admin,pass=X,enable=Y`).
- Masking matters most for **Backup Now**: `fetchconfig.pl`'s debug log echoes
  the device table it loads, including `default:` lines, which would otherwise
  place plaintext passwords on the page. Because masking runs on all output,
  it also covers backup content and diffs. Real device configurations rarely
  use `key=value` credential syntax (Cisco's `enable secret 5 ...` is
  untouched), but a config that legitimately contained a `pass=`/`enable=`
  token would have that value masked there too, and two different masked values
  would look identical in a diff. Restricting masking to the Backup Now
  transcript is a small follow-up change if that ever matters.
- The config file holds the database password in clear text; it must be
  readable only by the web-server user (see Configuration).

### Deployment hardening

- Serve over HTTPS and enable the cookie `-secure` flag; login posts a
  plaintext password and the session cookie authenticates every request.
- `chown` the config file to the web-server user and `chmod 600` it.
- Two operations write into the repository, which the web-server user
  typically cannot: **Backup Now** and **orphaned-backup delete**. Both run
  through `sudo -n` when `USE_SUDO_FOR_BACKUP_NOW` is set. Scope the sudoers
  entry to exactly the `fetchconfig.pl` command, and keep the repository owned
  by the account fetchconfig runs as.

## Development

The project ships a `Makefile.PL` and a `t/` unit-test suite (using the core
`Test::More`). Generate the Makefile and run the tests the usual way:

```sh
perl Makefile.PL
make test
```

or run the suite directly without generating a Makefile:

```sh
prove -I t/lib t/
```

To regenerate the HTML manual (`fetchconfig-web-documentation.html`) from this
README, run:

```sh
make doc
```

`make doc` runs `render-doc.py` with the first available Python interpreter
(`python3`, else `python`) and fails with a clear error if neither is
installed.

The suite loads the pure functions out of `fetchconfig-web.cgi` (via the
`t/lib/FCWebTest.pm` helper, which stubs CGI/DBI/DBD::Pg/Algorithm::Diff so the
tests run even where those modules aren't installed) and checks: the scripts
compile; `version_cmp` and the minimum-fetchconfig-version gate; the backup
filename parsers (`parse_backup_timestamp`, `backup_compact_stamp`,
`backup_name_suffix`); secret masking and HTML/JSON escaping (`mask_secrets`,
`esc`, `json_string`); `valid_id`; the whole model-option catalog (mandatory
vs. optional per model, the generic template model, the audited options); the
template listing and the generic-model validation rule; and the
syntax-highlighter safety invariant (highlighting only adds markup).

**`make install` intentionally does nothing** -- fetchconfig-web is not a
CPAN-style module; it is deployed by copying files into your web server as
described under "Deploying" above (and the fonts/images and database-setup
steps in the surrounding sections). Running `make install` just prints a
reminder to that effect.

## License

fetchconfig-web -- Web interface for the fetchconfig network configuration tool.
Copyright (C) 2026 Rainer Tammer.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

The full license text is in the `LICENSE` file shipped with this project, and
at <https://www.gnu.org/licenses/gpl-3.0.html>.
