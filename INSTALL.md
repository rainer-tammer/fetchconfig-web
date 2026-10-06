# fetchconfig-web -- Installation

This guide takes you from an empty web server to a running **fetchconfig-web**
instance, and covers upgrading an existing installation. It is the
operator's checklist; the full feature reference lives in `README.md`
(rendered as `fetchconfig-web-documentation.html`).

fetchconfig-web is a single Perl CGI script (`fetchconfig-web.cgi`) that sits
in front of an existing [fetchconfig](https://github.com/rainer-tammer/fetchconfig)
installation. It needs Perl with a handful of modules, a PostgreSQL database
for its user accounts, a web server that can run CGI, and read access to
fetchconfig's device table and repository.

## Contents

- [Part 1 -- Before you start](#part-1----before-you-start)
  - [What is in the package](#what-is-in-the-package)
  - [Requirements](#requirements)
  - [Perl modules](#perl-modules)
  - [Planning the layout](#planning-the-layout)
- [Part 2 -- Fresh installation](#part-2----fresh-installation)
  - [Step 1 -- Install the Perl modules](#step-1----install-the-perl-modules)
  - [Step 2 -- Create the user database](#step-2----create-the-user-database)
  - [Step 3 -- Write the configuration file](#step-3----write-the-configuration-file)
  - [Step 4 -- Install the CGI and static files](#step-4----install-the-cgi-and-static-files)
  - [Step 5 -- Directories and permissions](#step-5----directories-and-permissions)
  - [Step 6 -- Backup Now and sudo](#step-6----backup-now-and-sudo)
  - [Step 7 -- Serve over HTTPS](#step-7----serve-over-https)
  - [Step 8 -- First login](#step-8----first-login)
- [Part 3 -- Upgrading](#part-3----upgrading)
  - [Upgrading the script](#upgrading-the-script)
  - [Upgrading to 1.53](#upgrading-to-153)
  - [Upgrading the database to 1.51 (audit log)](#upgrading-the-database-to-151-audit-log)
  - [Upgrading the database to 1.50](#upgrading-the-database-to-150)
  - [New configuration keys in 1.50](#new-configuration-keys-in-150)
- [Part 4 -- Verification and troubleshooting](#part-4----verification-and-troubleshooting)
  - [Checklist](#checklist)
  - [Common problems](#common-problems)
- [Running the test suite](#running-the-test-suite)

## Part 1 -- Before you start

### What is in the package

The release archive `fetchconfig-web-1.50.tar` unpacks to a directory
`fetchconfig-web-1.50/` containing:

| File | Purpose |
|------|---------|
| `fetchconfig-web.cgi` | The application: one self-contained Perl CGI script. |
| `fetchconfig-web-dbsetup.pl` | Creates the PostgreSQL role, database and tables; bootstraps the `admin` account; can write the config file. |
| `fetchconfig-web-audit.sql` | Standalone idempotent SQL to add the 1.51 audit-log tables to an existing database (PostgreSQL 8.2+). |
| `fetchconfig-web-clean-audit.pl` | Standalone script to prune old audit-log rows (needs a privileged DB role; `-h` for help, `-s` to print the role SQL). |
| `LICENSE-ADDITIONS.md`, `LICENSE-ADDITIONS.html` | Additional terms under GPLv3 Section 7 (EU/German liability adaptation). |
| `PRIVACY.md`, `PRIVACY.html` | GDPR data-privacy notes for the operator (data controller). |
| `fetchconfig-web-dbupdate.sql` | Idempotent SQL that upgrades an existing database to the 1.50 schema (per-site access). |
| `fetchconfig-web-install-template.pl` | Root-side helper, run via `sudo`, that installs an edited template file. |
| `imageconvert.pl`, `README.imageconvert` | Optional helper for preparing the login backdrop image. |
| `images/back.jpg` | Login-page backdrop image. |
| `help.html` | The in-application Help page (served by the web server, path set by `HELP_FILE` / `HELP_BASE_URL`). |
| `README.md`, `fetchconfig-web-documentation.html` | Full reference documentation (Markdown and rendered HTML). |
| `INSTALL.md`, `INSTALL.html` | This guide (Markdown and rendered HTML). |
| `render-doc.py`, `render-doc.md` | Renders the Markdown documents to HTML. |
| `CHANGES`, `LICENSE`, `Makefile.PL` | Change log, GPL-3.0-or-later licence, and a `prove`-based test harness. |
| `t/` | The regression test suite. |

### Requirements

- **fetchconfig 9.67 or newer** already installed and working. fetchconfig-web
  calls `fetchconfig.pl` and reads its device table, repository and template
  directories; it does not replace fetchconfig.
- **Perl 5.10 or newer.** Tested on Linux and AIX.
- **PostgreSQL 9.2 or newer** reachable from the web server. (The database
  upgrade script is written to be PostgreSQL 8.2-compatible, but 9.2+ is the
  supported baseline.)
- A **web server that runs CGI scripts** -- Apache with `mod_cgi` /
  `ScriptAlias`, or an equivalent.
- **Read access** for the web-server user to the fetchconfig device table and
  repository, and **execute access** to `fetchconfig.pl`.
- Optionally **sudo**, if you want the *Backup Now* button to run live backups
  (see Step 6).

> [!CAUTION]
> **Long backups and web server timeouts.** While *Backup Now* or the *Empty
> Backup Cleanup* scan runs, fetchconfig-web sends a keepalive (an HTML
> comment) every 10 s, so the web server's inactivity timeout (Apache
> `Timeout`, default 300 s) only needs to be longer than 10 s, and
> `BACKUP_TIMEOUT` may exceed it. `BACKUP_TIMEOUT` (default 120 s) must be
> higher than the longest backup run of any device in the device table
> (bounded by its `timeout`, `fetch_timeout` and `banner_timeout` options).
> A reverse proxy or load balancer in front of the web server must not buffer
> the response, otherwise its own timeout applies. Closing the browser tab
> during a run terminates it (audited as `ABORTED`).

### Perl modules

Most of what the two scripts need ships with Perl itself. The table lists
**every** module used, so you can check an unfamiliar system in one pass.

**Core modules** (present on a standard Perl install on Linux and AIX):
`CGI::Cookie`, `Digest::MD5`, `Time::HiRes`, `MIME::Base64`, `Fcntl`, `File::Path`,
`File::Temp`, `File::Copy`, `IPC::Open3`, `IO::Select`, `Symbol`, `Errno`,
`Text::ParseWords`.

**Modules that may need installing:**

| Module | Minimum version | Why | Debian / Ubuntu | RHEL / Rocky | SLES | CPAN |
|--------|-----------------|-----|-----------------|--------------|------|------|
| `CGI` | any | Request/response handling. Removed from Perl core in 5.22, so modern distributions no longer include it. | `libcgi-pm-perl` | `perl-CGI` | `perl-CGI` | `cpan CGI` |
| `DBI` | 1.641 | Database access layer. | `libdbi-perl` | `perl-DBI` | `perl-DBI` | `cpan DBI` |
| `DBD::Pg` | 3.15.0 | PostgreSQL driver for DBI (loaded at runtime via the `dbi:Pg:` DSN). | `libdbd-pg-perl` | `perl-DBD-Pg` | `perl-DBD-Pg` | `cpan DBD::Pg` |
| `Algorithm::Diff` | 1.19 | Side-by-side and unified config diffs. | `libalgorithm-diff-perl` | `perl-Algorithm-Diff` | `perl-Algorithm-Diff` | `cpan Algorithm::Diff` |
| `Filesys::Df` | 0.92 | **Optional** -- only for the *Tools -> Disk space* page (free-space figures). Loaded lazily; without it the app runs normally and that one tool shows an install hint. | `libfilesys-df-perl` | `perl-Filesys-Df` | (CPAN) | `cpan Filesys::Df` |

**`Digest::SHA` is not required.** This is deliberate, and worth knowing if
you audit dependencies: password hashes are pure-Perl Apache MD5 (`$apr1$`)
computed with `Digest::MD5`, SHA-256/512 (`$5$`/`$6$`) hashes are verified
through the system `crypt()`, and the device-table change-detection digest
also uses `Digest::MD5` (as a change detector, not a security primitive).
Avoiding `Digest::SHA` keeps the script running on older Perls such as the
one shipped with AIX. If you later add code that needs it, add it to this
table.

Check what is already present in one command:

```sh
perl -MCGI -MDBI -MDBD::Pg -MAlgorithm::Diff -MDigest::MD5 -MTime::HiRes -e 'print "all modules found\n"'
```

Any module that is missing is named in the error.

### Planning the layout

Decide these paths before you start; they go into `/etc/fetchconfig-web.cfg`
in Step 3. The defaults match a typical fetchconfig install.

| Setting | Default | What it is |
|---------|---------|------------|
| `FETCHCONFIG_PATH` | `/usr/local/fetchconfig` | Where `fetchconfig.pl` lives. |
| `DEVICE_TABLE` | `/usr/local/fetchconfig/device_table` | fetchconfig's device table (read, and written by the editor). |
| `BACKUP_DEVICE_TABLE` | `/usr/local/fetchconfig/backup` | Where the editor keeps timestamped `.bak` copies of the device table. Must be writable by the web user. |
| `SESSION_DIR` | `/var/lib/fetchconfig-web/sessions` | Login sessions (mode 0700, files 0600). Must be writable by the web user. |
| `BACKUP_TMP_DIR` | same as `SESSION_DIR` | Scratch space for *Backup Now* and the device-table writer lock. Must be writable by the web user. |
| `HELP_FILE` | `/www/pub/fetchconfig-web/help.html` | Filesystem path of the Help page. |
| `IMAGE_BASE_URL`, `FONT_BASE_URL`, `HELP_BASE_URL` | `/fetchconfig-web/...` | **URL paths** (not filesystem paths) under which the web server serves the images, fonts and help. |

You also need the identity of the **web-server user** (Apache's `User`
directive, or `ps -ef` while a request is running). On the reference
deployment it is `nobody`; on Debian/Ubuntu it is usually `www-data`, on RHEL
`apache`. It is referred to as `<webuser>` below.

## Part 2 -- Fresh installation

### Step 1 -- Install the Perl modules

Install the four non-core modules for your platform (see the table above),
then re-run the one-line check:

```sh
# Debian / Ubuntu
apt install libcgi-pm-perl libdbi-perl libdbd-pg-perl libalgorithm-diff-perl

# RHEL / Rocky / Alma
dnf install perl-CGI perl-DBI perl-DBD-Pg perl-Algorithm-Diff

# SLES
zypper install perl-CGI perl-DBI perl-DBD-Pg perl-Algorithm-Diff

# Any platform, from CPAN
cpan CGI DBI DBD::Pg Algorithm::Diff

perl -MCGI -MDBI -MDBD::Pg -MAlgorithm::Diff -e 'print "ok\n"'
```

On AIX, prefer the IBM AIX Toolbox RPMs (`perl-DBI`, `perl-DBD-Pg`,
`perl-Algorithm-Diff`) where available; otherwise build from CPAN against
the system Perl.

### Step 2 -- Create the user database

fetchconfig-web keeps its own accounts in PostgreSQL. The setup script
creates everything. Run it on a host that can reach the database server, as
a user allowed to connect as the PostgreSQL superuser (typically run it as
`postgres`, or pass connection details interactively):

```sh
perl fetchconfig-web-dbsetup.pl
```

It walks through these steps, asking before each:

1. **Create the role** -- the database user the CGI connects as (default
   `fetchconfig`) and its password.
2. **Create the database** (default `fetchconfig`) owned by that role.
3. **Create the tables** -- `users`, plus the 1.50 `sites` and `user_sites`
   tables for per-site device access, with the needed grants.
4. **Import an existing `htpasswd` file** (optional) -- hashes are copied
   verbatim, so existing passwords keep working. Imported users start with
   no edit or admin rights.
5. **Bootstrap `admin`** -- if no `admin` account exists it is created with
   the password `fetchconfig`. **Change this immediately after first login**
   (Step 8).
6. **Write `/etc/fetchconfig-web.cfg`** (optional) -- writes a complete
   configuration file with the database credentials filled in. Say yes
   unless you prefer to write it by hand in Step 3.

The database connection parameters you choose here (`DBhost`, `DBinst`,
`DBuser`, `DBpass`) must match the configuration file.

### Step 3 -- Write the configuration file

The CGI reads `/etc/fetchconfig-web.cfg` once per request (the path is fixed
in the script). If the setup script wrote it for you, review it; otherwise
create it. The format is one `KEY = value` per line, `#` comments allowed.

A complete example with the defaults:

```
# --- fetchconfig ---
FETCHCONFIG_PATH        = /usr/local/fetchconfig
FETCHCONFIG_BIN         = fetchconfig.pl
DEVICE_TABLE            = /usr/local/fetchconfig/device_table
BACKUP_DEVICE_TABLE     = /usr/local/fetchconfig/backup
FETCHCONFIG_LOG         = /usr/local/fetchconfig/fetchconfig.log

# --- database ---
DBhost                  = localhost
DBinst                  = fetchconfig
DBuser                  = fetchconfig
DBpass                  = <the role password from Step 2>

# --- sessions and scratch ---
SESSION_DIR             = /var/lib/fetchconfig-web/sessions
SESSION_TTL             = 28800
SESSION_MAX_LIFETIME    = 86400
BACKUP_TMP_DIR          = /var/lib/fetchconfig-web/sessions

# --- Backup Now via sudo (see Step 6) ---
USE_SUDO_FOR_BACKUP_NOW = 1
SUDO_BIN                = /usr/bin/sudo
# BACKUP_TIMEOUT must exceed the longest backup run of any device
BACKUP_TIMEOUT          = 120
TEMPLATE_HELPER         = /usr/local/fetchconfig/fetchconfig-web-install-template.pl

# --- accounts ---
PROTECTED_USER          = admin
MIN_PASSWORD_LENGTH     = 8
DEFAULT_PASSWORD        = fetchconfig

# --- misc ---
HTTPS_ENABLED           = 0
SHOW_RENDER_TIME        = 0
HELP_FILE               = /www/pub/fetchconfig-web/help.html
HELP_BASE_URL           = /pub/fetchconfig-web
IMAGE_BASE_URL          = /pub/fetchconfig-web/images
FONT_BASE_URL           = /pub/fetchconfig-web/fonts
COPYRIGHT               = 2026 (c) Your Organisation
```

Protect it: it contains the database password.

```sh
chown root:<webgroup> /etc/fetchconfig-web.cfg
chmod 640 /etc/fetchconfig-web.cfg
```

The web-server user must be able to read it (hence the group), nobody else.
Every key is documented in the Configuration section of `README.md`.

### Step 4 -- Install the CGI and static files

Copy the script into your CGI directory and make it executable:

```sh
cp fetchconfig-web.cgi /www/cgi-bin/
chmod 755 /www/cgi-bin/fetchconfig-web.cgi
```

Install the static files where the web server serves the URL paths you set
for `IMAGE_BASE_URL`, `HELP_BASE_URL` and `FONT_BASE_URL` (the example uses
`/www/pub/fetchconfig-web` served as `/pub/fetchconfig-web`):

```sh
mkdir -p /www/pub/fetchconfig-web/images
cp images/back.jpg /www/pub/fetchconfig-web/images/
cp help.html       /www/pub/fetchconfig-web/
```

The backdrop image is optional (the login page shows a plain background
without it). The Help page is read from `HELP_FILE` on the filesystem and
also linked at `HELP_BASE_URL`; both must point at the same file.

Install the root-side template helper next to fetchconfig so the template
editor can save files it cannot write directly (only needed if you use the
template editor):

```sh
cp fetchconfig-web-install-template.pl /usr/local/fetchconfig/
chmod 755 /usr/local/fetchconfig/fetchconfig-web-install-template.pl
```

Make sure your web server executes `.cgi` files in that directory, e.g. for
Apache:

```
ScriptAlias /cgi-bin/ "/www/cgi-bin/"
<Directory "/www/cgi-bin">
    Options +ExecCGI
    AddHandler cgi-script .cgi
    Require all granted
</Directory>
```

### Step 5 -- Directories and permissions

The web-server user needs to **write** to three places and **read** two
more. Create the writable directories by hand rather than letting the
application do it -- the application can only create a directory if its
parent is web-writable, which the `fetchconfig` tree should **not** be.

```sh
# sessions + scratch (lock file, Backup Now temp tables)
mkdir -p /var/lib/fetchconfig-web/sessions
chown <webuser> /var/lib/fetchconfig-web/sessions
chmod 700 /var/lib/fetchconfig-web/sessions

# device-table backups written by the editor
mkdir -p /usr/local/fetchconfig/backup
chown <webuser> /usr/local/fetchconfig/backup
chmod 700 /usr/local/fetchconfig/backup

# the editor overwrites the device table IN PLACE, so the file itself must be
# web-writable (the directory need not be)
chown <fetchconfig_owner>:<webgroup> /usr/local/fetchconfig/device_table
chmod 664 /usr/local/fetchconfig/device_table
```

Read access is needed to the repositories (every `repository=` in the device
table), the template
directories and `fetchconfig.pl` itself; those keep their normal ownership.

Why in place: the editor cannot use the usual atomic write-temp-then-rename,
because that would require creating files in the `fetchconfig` directory. It
therefore takes a timestamped `.bak` copy into `BACKUP_DEVICE_TABLE` **before**
every write, so a failed write is always recoverable from the backup.

Writes are serialised: every save, bulk edit, restore and site-code rename
takes an exclusive lock on `device_table.lock` in `BACKUP_TMP_DIR` and
re-checks that the table has not changed (sub-second modification time, size
and a content digest) before writing. Two users saving at once can therefore
not overwrite each other; the second is told the table changed and nothing is
written.

> **A single empty `device_table.lock` file** appears in `BACKUP_TMP_DIR` (or
> `SESSION_DIR` if that is unset). This is expected: it is a 0-byte `flock`
> target, created once and reused, mode `0600`. **Do not delete it while the
> application is running** -- unlinking a lock file in use breaks the mutual
> exclusion. It is harmless to leave in place.

> **Device-table backups are not pruned automatically.** Every save, bulk edit,
> restore and site-code rename writes one timestamped `.bak` into
> `BACKUP_DEVICE_TABLE`, so that directory grows over time. Prune it
> periodically -- either from the web UI (*Tools -> Restore device table* has a
> "delete old backups" control) or on the server with a cron job, e.g.
> `find /usr/local/fetchconfig/backup -name '*.bak' -mtime +90 -delete`.
> (These are the editor's own table backups, separate from fetchconfig's
> per-device config repository.)

> **The report directory must be web-writable for logo upload.** *Tools ->
> Upload report logo* writes image files into the `report_dir` configured on the
> `email:` line. Reports are already written there, so it is normally writable
> by the web-server user; if it is not, uploads/deletes fail with a clear
> message (no sudo is added for this).

> **Session files are cleaned up automatically.** Files in `SESSION_DIR` are
> expired on access, and a login runs a throttled sweep (at most once per
> `SESSION_TTL`) that removes any session past its idle timeout
> (`SESSION_TTL`) or its absolute cap (`SESSION_MAX_LIFETIME` after login), so
> they do not accumulate. No cron is needed for these.

### Step 6 -- Backup Now and sudo

The *Backup Now* button runs `fetchconfig.pl` for one device and writes the
result into the repository. Because the repository is normally owned by a
privileged account and not writable by the web user, the recommended setup
is a **narrow sudo rule** that lets only the web-server user run only
`fetchconfig.pl`, as root, without a password:

```
# /etc/sudoers.d/fetchconfig-web   (install with visudo -f)
<webuser> ALL=(root) NOPASSWD: /usr/local/fetchconfig/fetchconfig.pl
```

and keep `USE_SUDO_FOR_BACKUP_NOW = 1` (the default). Backup Now then runs
`sudo -n /usr/local/fetchconfig/fetchconfig.pl -devices=<tempfile>`; `-n`
means it fails fast with sudo's own message rather than hanging if the rule
does not match. New backups are created with root ownership, consistent with
cron-made ones.

Two things to weigh before granting this:

- It is passwordless root execution of that one binary for whatever runs as
  `<webuser>` -- in practice only this script, but it deserves your normal
  privilege-grant sign-off.
- `nobody` (and sometimes `www-data`) is a shared low-privilege account used
  by other daemons too. The rule applies to every process running as that
  user, not just this CGI. If that is broader than you like, run the web
  server under a dedicated user.

If you do not want sudo at all, set `USE_SUDO_FOR_BACKUP_NOW = 0`; Backup Now
then runs as the web user and needs the repository to be web-writable (see
"Backup Now and repository write permissions" in `README.md` for that
option).

### Step 7 -- Serve over HTTPS

Login sends a password and the session cookie is a bearer token; both should
travel encrypted. Terminate TLS in the web server (Apache/nginx) in front of
the CGI -- the script does not do TLS itself -- and redirect HTTP to HTTPS
so the login form is never served in clear.

Then set in the configuration:

```
HTTPS_ENABLED = 1
```

This adds the `Secure` flag to the session cookie so the browser never sends
it over plain HTTP. Leave it `0` on an HTTP-only deployment -- with `Secure`
set, the browser would withhold the cookie and login would appear to fail.
Consider also enabling HSTS in the web server once HTTPS is stable.

### Step 8 -- First login

Browse to `https://yourhost/cgi-bin/fetchconfig-web.cgi` and log in as
`admin` with the password `fetchconfig` (or the one you set in Step 2).

Immediately:

1. **Change the admin password** -- *User -> Change your password*. Until you
   do, a warning banner is shown on every page.
2. **Create your sites** -- *User -> Sites*. Every device must carry a
   `site=` tag before the device table can be saved, so define the site codes
   first.
3. **Create users** and assign their sites and rights -- *User -> Add user*,
   then *Users list -> Edit sites*. A user needs the *Edit device* right to use
   the editor and *Admin functions* for Tools, sites and user management.
4. **Tag your devices** -- *Setup devices -> Edit device table*. Untagged
   devices are shown with a red site placeholder; *Tools -> Check site
   assignment* lists any that remain untagged.

## Part 3 -- Upgrading

### Upgrading the script

Upgrading the application itself is a file copy; no data migration is
involved for the script:

```sh
cp /www/cgi-bin/fetchconfig-web.cgi /www/cgi-bin/fetchconfig-web.cgi.old
cp fetchconfig-web.cgi /www/cgi-bin/
chmod 755 /www/cgi-bin/fetchconfig-web.cgi
cp help.html /www/pub/fetchconfig-web/
```

Then hard-reload the browser (Ctrl-F5) so cached JavaScript and CSS are
refreshed -- several 1.50 changes are client-side, and a stale cache is the
usual reason a fix "does not appear".

### Upgrading to 1.53

- **Remove `REPOSITORY`** from `/etc/fetchconfig-web.cfg`. The repository now
  always comes from the device table (device `repository=` or the model's
  `default:` line), exactly as for `fetchconfig.pl` itself. A leftover
  `REPOSITORY` line is ignored and shown as `invalid` in *Tools -> Show
  fetchconfig-web.cfg*.
- If the device table sets no `repository=` at all, every page shows
  `FATAL ERROR: No repository found ...` -- add a `default:` line with
  `repository=` for each model.
- Before 1.53, *Backup Now* stored backups of devices whose repository comes
  from a model `default:` line in `REPOSITORY` instead, if the two differed.
  Check `REPOSITORY` for such device directories and move them into the
  device's real repository.

### Upgrading the database to 1.51 (audit log)

Version 1.51 adds an append-only `audit_log` table (plus a small
`app_state` table). Run the idempotent, PostgreSQL 8.2-compatible
script once:

```sh
psql -U fetchconfig -d fetchconfig -f fetchconfig-web-audit.sql
```

It is safe to re-run, and the same changes are also included in
`fetchconfig-web-dbupdate.sql`. The web user is granted INSERT + SELECT
on `audit_log` only (it can never alter or erase the log); a DBA
handles any retention/pruning.

### Upgrading the database to 1.50

Version 1.50 adds per-site device access, which needs two new tables
(`sites`, `user_sites`) and one new column (`users.download_full_report`).
Run the idempotent upgrade script **once** against the fetchconfig-web
database:

```sh
psql -U fetchconfig -d fetchconfig -f fetchconfig-web-dbupdate.sql
```

It is safe to re-run. It:

- creates `sites` and `user_sites` and the `download_full_report` column if
  missing;
- seeds the reserved `*` "All sites" entry (id 0);
- gives every existing user site 0, so **everyone starts unrestricted** and
  nothing changes for them until you narrow their sites;
- grants the web database user the privileges it needs on the new tables
  (this matters if you run the script as `postgres` rather than as the web
  user).

Upgrading from a version **before 1.15** also needs the `admin_function`
column; see "The user database" in `README.md`.

### New configuration keys in 1.50

Both are optional and default off; add them if you want the behaviour:

| Key | Default | Effect |
|-----|---------|--------|
| `HTTPS_ENABLED` | `0` | `1` adds the `Secure` flag to the session cookie. Set it once you serve over HTTPS (Step 7). |
| `SHOW_RENDER_TIME` | `0` | `1` shows the page load/render-time lines (device list, status, log, template list, editor render and per-card AJAX times). A diagnostic aid. |

## Part 4 -- Verification and troubleshooting

### Checklist

Work through this after a fresh install or an upgrade:

- [ ] `perl -c /www/cgi-bin/fetchconfig-web.cgi` reports *syntax OK* (proves
      the Perl modules are present).
- [ ] The login page loads over HTTPS and shows the backdrop image.
- [ ] You can log in as `admin` and the default-password warning disappears
      after you change it.
- [ ] *Devices* lists your devices with the correct **Site** column.
- [ ] *Devices -> Backup status* and *Backup reports* open.
- [ ] *Setup devices -> Edit device table* opens, a device expands on *Edit*,
      and *Save changes* writes a `.bak` into `BACKUP_DEVICE_TABLE`.
- [ ] *Tools -> Check site assignment* reports no untagged devices (or lists
      the ones to fix).
- [ ] *Backup Now* on one device completes and the new backup appears in the
      repository.
- [ ] The footer shows the expected version: *fetchconfig-web v1.50 using
      fetchconfig v9.6x*.

### Common problems

**"Internal Server Error" on first request.** Almost always a missing Perl
module or a non-executable script. Run `perl -c fetchconfig-web.cgi` as the
web user, check `chmod 755`, and read the web server's error log.

**Login succeeds but immediately returns to the login page.** The session
cookie is not being accepted. Either `SESSION_DIR` is not writable by the web
user, or `HTTPS_ENABLED = 1` is set on an HTTP-only site (the browser then
discards the `Secure` cookie). Check `SESSION_DIR` permissions and the
`HTTPS_ENABLED` value.

**"Configuration error" on the login page.** One of the URL-path keys
(`IMAGE_BASE_URL`, `FONT_BASE_URL`, `HELP_BASE_URL`) is not an absolute URL
path, or a required key is missing. The message names the key.

**The editor opens but Save fails with "could not open ... for writing".**
The device table file is not writable by the web user (Step 5). Only the
file needs to be writable, not its directory.

**Save fails with "The device table changed on disk since you opened the
editor".** Someone else saved, or a cron job rewrote the table, between your
open and your save. Nothing was written. Reload the editor and redo the
change -- this guard is what stops two people overwriting each other.

**Backup Now ends with a blank or truncated page; the Apache error log shows
`(70007)The timeout specified has expired: ap_content_length_filter:
apr_bucket_read() failed`.** The web server saw no output for its `Timeout`.
Since 1.53 the keepalive (every 10 s) prevents this; on older releases raise
`Timeout` above `BACKUP_TIMEOUT`. If it still occurs, a reverse proxy or load
balancer in front is buffering the response (see the warning under
Requirements).

**Backup Now shows "a password is required" or similar sudo text.** The
sudoers rule from Step 6 is not matching: check the exact web-server user
and the exact path to `fetchconfig.pl`, and that the file in
`/etc/sudoers.d/` has mode 0440.

**Everything looks right but a recent fix is "not there".** Hard-reload the
browser (Ctrl-F5); the editor's JavaScript is cached.

## Running the test suite

The package ships its regression tests. They run without a database or web
server (the test harness stubs both) and take under a minute:

```sh
cd fetchconfig-web-<version>
prove -I t/lib t/
```

or, via the included `Makefile.PL`:

```sh
perl Makefile.PL && make test
```

All tests should pass. Failures almost always mean a missing Perl module
on the build host.
