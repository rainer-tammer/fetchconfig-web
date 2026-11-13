# fetchconfig-web -- Quick install

The essential steps to get a fresh instance running, in order. For anything
non-obvious -- exact module names, the complete configuration-key list,
web-server variants, SELinux, sudo, troubleshooting -- see the full **INSTALL**
guide; each step below names the INSTALL step that covers it in depth.

> This is the fast path for an experienced operator doing a clean install on a
> single host. Upgrading an existing instance instead? See INSTALL,
> "Part 3 -- Upgrading" (no fuss there either: for a point release you usually
> just copy the new `fetchconfig-web.cgi` and `graceful` the server).

## 1. Prerequisites (INSTALL Step 1)

- Perl with `DBI`, `DBD::Pg`, `CGI`, `Algorithm::Diff`
- PostgreSQL, local or reachable over the network
- fetchconfig 9.80+ installed and working
- A web server with CGI or FastCGI (mod_fcgid recommended)

## 2. Create the database (INSTALL Step 2)

Run the setup script as a user that can connect as the PostgreSQL superuser
(typically `postgres`). It creates the role, the database, and the tables, can
import an existing `htpasswd`, bootstraps the `admin` account (initial password
`fetchconfig` -- change it at first login), and can write the config file for
you.

```sh
perl fetchconfig-web-dbsetup.pl
```

## 3. Configuration (INSTALL Step 3)

The CGI reads `/etc/fetchconfig-web.cfg` (the path is fixed in the script), one
`KEY = value` per line. If step 2 wrote it, just review it. The keys you must
get right:

```
FETCHCONFIG_PATH    = /usr/local/fetchconfig            # where fetchconfig.pl lives
DEVICE_TABLE        = /usr/local/fetchconfig/device_table
BACKUP_DEVICE_TABLE = /usr/local/fetchconfig/backup
DBhost              = localhost
DBinst              = fetchconfig
DBuser              = fetchconfig
DBpass              = <the role password from step 2>
SESSION_DIR         = /var/lib/fetchconfig-web/sessions
```

The four `DB*` values must match what you chose in step 2. INSTALL Step 3 has
the complete, annotated key list (sessions, Backup Now / sudo, timeouts, the
cron viewer, and more).

## 4. Deploy the files (INSTALL Step 4)

```sh
cp fetchconfig-web.cgi /www/cgi-bin/ && chmod 755 /www/cgi-bin/fetchconfig-web.cgi

WEB=/www/virtual/fetchconfig/htdocs       # the directory served at BASE_URL
mkdir -p $WEB/css $WEB/images $WEB/js $WEB/fonts
cp fetchconfig-web.css $WEB/css/          # REQUIRED -- no CSS means unstyled pages + error banner
cp images/back.jpg     $WEB/images/       # optional login backdrop
cp js/mermaid.min.js   $WEB/js/           # optional template-viewer diagram
cp fonts/*.woff2       $WEB/fonts/        # optional IBM Plex webfonts
```

Only the stylesheet is mandatory; the rest are optional and the UI degrades
gracefully without them.

## 5. Directories and permissions (INSTALL Steps 5-6)

Create `SESSION_DIR` (and `BACKUP_TMP_DIR` if separate) and make them writable
by the web-server user. If you will use **Backup Now**, set up the sudo rule as
in INSTALL Step 6.

## 6. Web server (INSTALL Step 7)

Point the web server at the CGI and serve `WEB_DIR` at `BASE_URL`. The exact
configuration differs between mod_fcgid and mod_cgi -- copy the matching vhost
block from INSTALL Step 7, which also covers the socket directory,
`FcgidMaxRequestLen`, and the inactivity timeout. After any later script update,
run `apachectl graceful` under FastCGI.

## 7. First login (INSTALL Step 8)

Browse to the app, log in as `admin` / `fetchconfig`, and **change the password
immediately**. Confirm the footer shows the expected fetchconfig-web and
fetchconfig versions and that no red configuration banner appears.

---

That is the whole path. If pages are unstyled or show a red "directories not
configured" banner, the stylesheet or the `WEB_DIR` / `BASE_URL` pairing is
wrong -- recheck steps 3-4. For everything else, the full **INSTALL** guide is
the reference.
