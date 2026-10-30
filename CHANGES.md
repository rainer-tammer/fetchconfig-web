# fetchconfig-web -- Change Log

Release history for fetchconfig-web, newest version first.

## 2.09

Requires fetchconfig 9.72. Adds a state-machine diagram to the template viewer,
colour-codes the template **Used** column, and closes several credential-masking
gaps in the config and template views. No database change.

### Template state-machine diagram

* The **Template viewer** (`view_template`) now draws the template's
  login/collect state machine (Mermaid `stateDiagram-v2`) below the text -- the
  same diagram the shipped template HTML docs use. The source is built
  server-side from fetchconfig's own
  `fetchconfig::model::GenericTemplateParser` (loaded by absolute path from
  `FETCHCONFIG_PATH`, never copied); the browser renders it with the bundled,
  self-hosted `js/mermaid.min.js` -- fully offline, loaded only on this page.
  Edge labels sit on the panel background, not on white boxes.
* New config key **`JS_BASE_URL`** (default `/js`). The release now ships `js/`
  (`mermaid.min.js`) and `fonts/` (IBM Plex Sans, needed so labels fit); copy
  both directories into `WEB_DIR`. A short note replaces the diagram if the
  renderer, the font, or the parser is missing, or the template fails to parse --
  a stale diagram is never shown.

### Templates overview

* On Tools -> *Templates* (`view_templates`), the **Used** column is now
  colour-coded: **Yes** green, **No** red.

### Credential masking (config / template views)

* **Fixed:** encrypted password hashes in a viewed config could be shown
  unmasked. Two gaps: `mask_secrets` only redacted a numeric-type password
  (`password 7 <hash>`), missing the keyword-typed forms -- Zyxel
  `password encrypted <hash>`, HPE Comware `password cipher <hash>`, Huawei
  `password irreversible-cipher <hash>`, `password hash <hash>`; and the syntax
  highlighters isolate the encrypted blob into its own fragment and escape it
  alone, so the multi-token `password encrypted <hash>` context never reached the
  masker. `highlight_config` now masks the whole config up front, so the value is
  redacted regardless of how a highlighter splits the line.
* **Fixed:** Hirschmann password hashes were shown unmasked. The hash is a
  `:v<N>:<hash>:` blob on a `users passwd <user> :v1:<hash>:` line (hirschmann
  model, and generic devices driven by the hirschmann template); masking now
  keeps `users passwd <user>`, the `:vN:` tag and the closing `:`, and redacts
  only the hash.
* **Fixed:** SNMP community masking leaked on Hirschmann configs, where the
  community is a quoted string placed AFTER positional keywords
  (`snmp-server community ipaddr 0.0.0.0 "secret"`, `... ro "secret"`). The old
  rule masked the first token (the keyword) and left the quoted community
  exposed. Masking now redacts the quoted community wherever it sits on the line,
  and only falls back to masking a bare first-token community (Cisco/Comware)
  when the line has no quoted community -- no device-type detection needed.
* **Fixed:** Aruba CX (aruba-cx-ssh) secrets using the `ciphertext` encoding
  keyword were mishandled. `user ... password ciphertext <blob>` was not masked
  at all, and `radius-server host ... key ciphertext <blob>` masked the keyword
  `ciphertext` instead of the blob. Masking now recognises the encoding keywords
  (`ciphertext`/`plaintext`/`cipher`/`encrypted`) after `password` and after
  `key`, keeps the keyword, and redacts the value -- on server lines and on the
  indented `key` form alike.
* **Fixed:** Cisco Nexus (nexus-ssh) `tacacs-server`/`radius-server` lines use a
  numeric key TYPE before the secret (`key 7 "secret"`); masking redacted the
  type digit `7` instead of the secret. The `key` rule now treats a leading
  numeric type (as well as the Aruba CX encoding keywords) as the type, keeps it,
  and masks the value -- a lookahead prevents it from re-masking the visible type
  when the secret is the quoted token.

## 2.08

Requires fetchconfig 9.72. Adds a viewer for device debug logs and a
read-only schedule tool.

### Show schedule (Tools)

* New **Tools -> Show schedule** (admin only). Two panels:
  * **Current schedule** -- lists `CRON_USER`'s crontab (read-only) and shows
    the lines running `FETCHCONFIG_PATH/FETCHCONFIG_BIN`, parsed into schedule,
    a plain-language "when", the command and its log file. Commented-out
    fetchconfig lines are shown too, flagged *disabled*. Other jobs on the
    crontab (and any secrets on their command lines) are not shown.
  * **Build a crontab entry** -- pick minute / hour / day-of-month / month /
    weekday and copy the complete line (command from
    `FETCHCONFIG_PATH/FETCHCONFIG_BIN`, log from `FETCHCONFIG_LOG`). The tool
    never writes the crontab; you add the line yourself with `crontab -e`.
* New optional config key **`CRON_USER`** -- the user whose crontab holds the
  job. The page shows which settings are missing if any of `CRON_USER`,
  `FETCHCONFIG_PATH`, `FETCHCONFIG_BIN` or `FETCHCONFIG_LOG` is unset.
* Reading another user's crontab goes through the existing privileged helper
  (`TEMPLATE_HELPER` + sudo) -- a new read-only `list-cron` subcommand -- because
  the cron spool directory is root-owned. **No new sudoers rule is needed**; the
  helper is redeployed. The target user comes only from the config and must
  exist (`getpwnam`).
* Helper **v1.7**: `list-cron` forces `LC_ALL=C` and an absolute `crontab` path,
  so the viewer works on a non-English Linux host (RHEL/SLES/Debian) where cron's
  "no crontab for &lt;user&gt;" message would otherwise be localized and misread.

### Device debug logs

* **View** on the *Device backup status* page, in a new **Debug** column
  shown to admins and holders of the new `read_debug` right. Greyed out when
  the device has no `<device-id>.debug` file.
* The buttons key on the **file**, not on the `debug` option -- a device set
  back to `debug=off` keeps the log written while it was on.
* The viewer highlights the `Net::Telnet` hex dump, with **SEND** / **RECV**
  badges, a per-direction tint and a rule where the direction turns.
* **Sent only** / **Received only** filter in the browser; **Transcript** view
  reassembles the bytes into a readable session.
* **SSH log hidden / shown** -- the ssh client's own stderr, hidden by
  default. Classified by complement (not a hex line, not a `#` marker), so it
  can never hide device traffic; the `#` markers always stay visible.
* **Copy** returns the log as shown, with the original `<` / `>` markers:
  the badges are CSS generated content, not markup.
* New Tools entry **Device debug logs**: every device that has one, plus
  **Delete all debug logs**.
* Views and deletions are audited (`view_debug`, `delete_debug`,
  `delete_all_debug`).

### Debug log permissions

* New per-user right **`read_debug`** -- view device debug logs, for the
  user's own sites. **Not** implied by being site-unrestricted, unlike the
  other per-user rights: a debug log can contain the device password in clear
  text, so it must be granted explicitly.
* **Download** (raw file) and **Delete** stay **admin only**.
* Buttons: *Device backup status* has **View** only; Tools has
  **View | Download | Delete**; the viewer has **Download** and **Delete** for
  admins.
* The viewer returns to the page it was opened from.

### Other

* *Device backup status* gains **Site** and **Device-ID** filters, with the
  same behaviour as the device list (site exact, device-id a
  case-insensitive substring). Filters persist in the existing cookie.
* *Device backup status* and Tools -> *Device debug logs* are sorted by
  device-id, case-insensitively, instead of device-table order.
* **Fixed:** sorting a column on *Device backup status* reordered only the
  rows on the current page. It now sorts the whole table, as the device list
  already did.
* The user editor's permission boxes are wider, so no permission label wraps.
* The *Device backup status* filter row uses the same control sizes as the
  Devices page.
* **Fixed:** the stylesheet is now cache-busted by `APP_VERSION_INTERNAL` (the
  true shipped version), not by `APP_VERSION`. `APP_VERSION` is display-only and
  config-overridable, so it may be any string without affecting the CSS.
* *Per page* on *Device backup status* now offers All/10/20/40/80/160,
  defaulting to 40, as the device list does.

### Viewer size limits

* Under 2 MB in full; 2--16 MB as the first and last 1 MB with
  `----- content cut because of a 2 MB viewing size limit -----` between them;
  over 16 MB not displayed or downloaded (it can still be deleted).
* Chunks are cut on line boundaries, so no half hex-dump line is rendered.

### Reading root-owned debug logs

* fetchconfig creates `<device-id>.debug` as **root, mode 0600**, so the
  web-server user can neither read nor delete it (`unlink` needs write
  permission on the root-owned *repository directory*).
* With **`TEMPLATE_HELPER`** set, the viewer reads and deletes through that
  helper. It is the one the template editor already uses -- **no new sudoers
  rule**; redeploy the helper.
* Without it the buttons explain the permission problem instead of failing
  with a generic error.
* Helper **v1.5** adds `read-debug` and `delete-debug`, hardened like the
  template commands: absolute path, no `..`, must end `.debug`, plain file
  only. `read-debug` takes a byte window, so a large log is not pulled through
  the pipe in full.

**Upgrading:** run `fetchconfig-web-dbupdate-2.08.sql` once, and redeploy the
helper.

### Security

* A debug log is a full session transcript and **can contain device
  credentials**. Secret masking cannot help -- it matches `key=value`, while a
  password in a hex dump is split across 16-byte lines as hex *and* ASCII. The
  controls are the admin-only gate and fetchconfig's own `print_secret()`.
* The delete path takes a **device id only**. The file path is re-derived from
  the device table, symlinks are refused, and a missing file is not an error.
* Read errors show generic text; the reason goes to the audit log.

## 2.07

Requires fetchconfig 9.72. Template management on the Templates page, plus a
server-side input-validation audit and its fixes.

**Upgrading:** add the second sudoers rule -- *without it every template write
fails* -- and redeploy the helper (now v1.3):

```
<webuser> ALL=(root) NOPASSWD: /usr/local/fetchconfig/fetchconfig-web-install-template.pl
```

### Requires

* **fetchconfig 9.72** (was 9.71).
* `prompt_settle` removed from the `generic` model -- dropped in 9.72, it was a
  no-op. An existing `prompt_settle=` is preserved as an "(unrecognized)" chip,
  not discarded. Unrelated to `prompt_settle_ms`, which stays.
* Perl floors **lowered** to what the code uses: CGI 4.31, DBD::Pg 3.0.0,
  DBI 1.614. The old floors made `perl Makefile.PL` fail on stock RHEL 9 and
  SLES 15. Security guidance moved to INSTALL.md, where it belongs -- a floor
  rejects a patched vendor build and accepts an unpatched CPAN one.

### Template management

* **Upload, download, rename and delete templates.** Uploads are name-checked,
  capped at 100 KB, syntax-checked before install, and never overwrite
  (atomic). Rename and delete are refused for a template in use by a device,
  re-checked server-side.
* New **Used** column on the Templates page.
* **Generate a template from a HEX capture** via fetchconfig's
  `generate_template.pl`, stamping the chosen `syntax_style`. The result is a
  draft -- review it against the device.
* **Session-recorder downloads** (`record_session.exe`, `record_session.py`),
  each shown only when present, with size, date and a cached SHA-256. Not
  shipped; build the exe from fetchconfig's `contrib/windows`.
* Helper **v1.3**: adds `install-new`, `delete` and `rename` (v1.2), and
  refuses a symlinked `.bak` on `revert` (v1.3). The existing sudoers entry
  covers every subcommand. Helper errors in the UI are condensed to the single
  error line instead of its full `--help`.

### Security and validation

An audit asked whether all input is validated on the server or only in the
browser. It was not. Fixed:

* **Per-site scope on the device page.** The scope check keyed on the action
  name, and that page is reached with no action, so a site-limited user could
  read any device's backups by typing the URL. Unmasked downloads were gated
  separately and never exposed.
* **Unknown model no longer destroys the stored `enable` password.** The secret
  write-back keyed on the catalog type; for a model outside the catalog it
  wrote the mask string into the table as the password. No attacker needed --
  the editor keeps an unknown model, so a table from a newer fetchconfig lost
  the secret on any ordinary save. It now keys on the mask alone.
* **Report logo upload/delete, and report delete/prune, are admin-only.** All
  four handlers were reachable by any logged-in user; the admin-only menu was
  the only gate. Controls are hidden for non-admins *and* the handlers check.
* **`lock_dir` is checked against the directory allow-list** (opt-in: without a
  `lock` line it stays unrestricted, as documented).
* **Option values are checked against their catalog type** -- the same sets the
  widgets offer, case-insensitively -- and `report_logo` against
  `valid_logo_name()`. *Behaviour change:* a table hand-edited to carry a value
  outside the documented set (say `changes_only=yes`) is now refused on save,
  with an error naming the record, option and accepted values.
* Unknown models and option keys are still **accepted** and labelled
  "(unknown)" / "(unrecognized)", so a table written by a newer fetchconfig
  stays editable -- but checked for illegal content: an option name cannot
  carry `=` or `,`, and no value may contain a control character.
* **Bounded the editor's form indices.** A crafted `<key>__<n>` pre-extended a
  Perl array; the record loop also re-read every parameter per record.
* **Site codes reject `,` `=` `#`** -- they are written as `site=<code>` into
  the device table.
* Template rename without the helper is now atomic (`link()`, not
  check-then-act).
* Name and token validators anchor on `\z`, not `$`, which also matches before
  a trailing newline.
* An oversized POST now returns 413 instead of a misleading "No file was
  selected."
* Removed the legacy `set_download_full_report` / `set_download_full_config`
  handlers -- dead since 1.63; `do_user_save` covers the same rights and still
  emits the same audit actions.
* `run_check_empty()` removed (dead).
* Global `$CGI::POST_MAX` of 2 MB.
* New suites `t/C8-server-validation.t`, `t/C9-lock-dir-optin.t` and
  `t/D0-helper-revert.t`, each verified to fail against the previous code.

### Documentation

* **The device-table editor and bulk editor now POST url-encoded, not
  multipart.** CGI.pm's `start_form` defaults to `multipart/form-data`, which
  costs about 86 bytes of framing *per field* -- neither form has a file input,
  so that was pure overhead against `$CGI::POST_MAX`. The same table is now
  4-6x smaller (1000 collapsed devices: 196 KB -> 34 KB), raising the ceiling
  from roughly 10,600 to 55,000 collapsed devices. Upload forms stay multipart,
  as they must.
* **A device-table save that would exceed the request limit is now refused in
  the browser**, with the estimated and permitted sizes, instead of being
  discarded by CGI.pm and losing every edit in the form. The estimate carries a
  20% margin (the browser picks its own multipart boundary, and non-ASCII
  values encode to a variable number of bytes). Advisory only -- the server
  enforces `$CGI::POST_MAX` regardless.
* **Over-sized uploads are now refused in the browser, before the request
  starts.** Once an upload is under way an over-sized one cannot be reported
  properly -- the server answers while the browser is still sending, the
  connection is reset, and the browser shows its own error page whatever
  `ErrorDocument` is configured (Apache bug 17722). The three upload forms now
  carry their cap as `data-max-upload` and a file over it is refused with a
  styled message and no upload. This is a convenience, **not** a control: the
  server re-checks every upload and remains the only thing that decides. The
  caps live in one place (`UPLOAD_MAX_LOGO` / `_TEMPLATE` / `_HEX`), used by
  both the forms and the handlers, so the hint cannot drift from the rule.
* **INSTALL's web-server setup consolidated into one Step 7.** The Apache
  configuration was spread over Steps 4, 7, 7a, 7b and 7c and shown six times
  over. It is now a single complete virtual host, given once in 2.4 syntax,
  with the three lines that differ on 2.2 listed beside it -- plus TLS, the
  FastCGI choice, the size limits, the plain-CGI variant and how to verify.
* INSTALL's Apache snippets now cover **both 2.2 and 2.4**: the Step 4 sample
  used `Require all granted`, which is 2.4-only and makes 2.2 fail to start
  with `Invalid command 'Require'`, and the mod_fcgid `<Directory>`
  block carried no access directive at all, so a copied vhost answered 403 on
  either branch.
* **mod_fcgid deployments must raise `FcgidMaxRequestLen`** (default 131072 =
  128 KB) to `2097152`, matching `$CGI::POST_MAX`. Below that, mod_fcgid
  rejects an upload *before the script runs* -- a bare 500, with
  `exceeds MaxRequestLen` in the error log -- so a 100 KB logo or template
  fails and a 1 MB HEX capture can never succeed. Documented in Step 7, in a
  callout beside the timeout requirements, and in the verification checklist.
  Plain CGI is unaffected.

* Audited against the source: the missing sudoers rule, per-distribution
  package names for RHEL 9 / SLES 15 / Ubuntu, bcrypt (not `$apr1$`) password
  storage, the DB-backed login throttle, a documented action that never
  existed, and assorted stale names and values.
* New *Installing newer modules from CPAN* section in INSTALL.md.
* The application is **not** a single self-contained file: the logo and login
  icon are inlined for load performance, while the stylesheet, fonts, favicon,
  help tree and `back.jpg` are deployed under `WEB_DIR`. Document headers now
  read *Perl FCGI/CGI*, and the prose no longer describes the app as
  plain-CGI-only.
* Help menus list up to 15 files (was 10).

## 2.04

Bug fix: Backup Now no longer reports a false failure on an initial backup.

* "Backup now" now takes its pass/fail verdict from the device's per-run
  `.status` file (`backup_state`) -- the same signal fetchconfig records and the
  summary email and backup overview already use -- instead of scraping the log
  for an `error:` line. An initial backup logs a benign
  `<model>: there is no latest config` (there is no prior config to diff
  against) while the fetch still succeeds; that no longer trips a
  "Backup run FAILED" message.
* A hard error (timeout / fork failure) is still a failure. When no `.status`
  file is available (an older fetchconfig, or a crash before it is written) the
  log is still scanned as a fallback, with that benign line ignored, and a
  genuine failure (bad enable password, unreachable device -> `backup_state =
  failed`) is still reported.

## 2.03

Help menu restructured.

* The Help menu is now served from a help tree, `<WEB_DIR><HELP_BASE_URL>`
  (new `HELP_BASE_URL` config key, default `/help`). `help.html` lives directly
  in it.
* Two "additional help" sections -- "fetchconfig-web - additional help" and
  "fetchconfig - additional help" -- are built by scanning the `fetchconfig-web/`
  and `fetchconfig/` sub-directories of the help tree for `*.html` documents.
  Each document's menu label is taken from its `<title>`; entries are sorted by
  label and open in a new tab. You curate each menu simply by placing the files
  you want exposed in the directory. The sub-directories are read-only to the
  application (no web-server write access needed).
* A sub-directory that is missing or holds no `*.html` shows a muted
  "No additional helpfiles available - see INSTALL.md"; one with more than ten
  `*.html` files shows a single "too many help documents in &lt;dir&gt;"
  placeholder.
* New **About** entry at the bottom of the Help menu, opening the same dialog as
  the title-bar program icon.
* The bundled help pages now carry a uniform `<title>` in the house style
  (`fetchconfig-web &mdash; <Subtitle>`, em dash), so the auto-derived menu
  labels are consistent.
* The previous flat Help-menu list of fixed document names in `WEB_DIR` was
  removed. See the Upgrading section of INSTALL for the migration steps.

## 2.02

Requires fetchconfig 9.71 or newer.

* The `debug=on|off` session-log toggle is now available on every model in the
  device-table editor (it became a universal option in fetchconfig 9.71). It
  was moved into the editor's common option set, so the previous per-model
  `debug` entries were removed.
* Minimum fetchconfig raised to 9.71 (was 9.69).
* Reworded the "device table modified outside fetchconfig-web" editor warning
  for clarity; the audit-log link text is now "audit log".
* The notice now also shows the on-disk file owner and the table's last-
  written date/time (yyyy-mm-dd / HH:MM:SS).

## 2.01

Maintenance release.

* Fixed report deep links from notification emails: opening a
  `?action=view_report&file=...` link while logged out now returns to that exact
  report after authenticating (the `file=` argument was previously dropped across
  the login). The carried argument is re-validated with the target action's own
  validator so only a safe report file / template path is kept;
  `valid_report_name` was tightened to a safe character set.

## 2.00
Major release consolidating 1.53-1.63. Requires fetchconfig 9.69 or newer.
Database: adds users.download_full_config and the device_notes table
(run fetchconfig-web-dbupdate-1.62.sql on an existing install).

### Highlights
* User management redesigned: slim user list -> per-user edit page (identity,
  permissions, site access, password); one save writes all fields and logs one
  audit line per changed permission. Permissions live in one place only.
* Device notes: a per-device free-text note (optionally "keep"), with a notes
  viewer and an orphaned-notes cleanup tool.
* Unmasked-config right: the config view is always masked; a per-user
  download_full_config right gates the unmasked copy/download, both audited.
* Device locking (fetchconfig 9.69): lock / lock_dir / lock_retry /
  lock_retry_time device options, lock_dir resolved against a "directory: lock"
  allow-list; a lock-skip shows as the "skipped" state.

### Security
* Host-header reset-link poisoning fixed: reset links use a configured SITE_URL
  only; no SITE_URL -> no reset mail.
* Session ids, reset tokens and password salts come from /dev/urandom with a
  loop on short reads and fail closed (no weak rand() fallback).
* Reset tokens hashed with SHA-256; login/reset throttling hardened (no timing
  oracle, no FastCGI-worker exhaustion); forgot-password audits every outcome.
* Password policy (length and character classes), config-file permission check,
  HSTS/Cache-Control headers, and a login-failures viewer.
* Config masking extended to switch-config secret forms (SNMP community,
  RADIUS/TACACS keys, WPA passphrases, Aruba CX controller/auth-server keys)
  and to Cisco IOS hashed secrets -- "secret <type> <hash>" and
  "password <type> <hash>" (enable secret, username secret/password), in both
  the plain and syntax-highlighted backup views.

### Other
* All notification emails (test, password reset, admin verify) share one modern
  HTML style (program icon via a CID image so Thunderbird/Outlook show it
  inline) plus a plain-text part; the reset mail has a "Set a new password"
  button.
* Consistent UI: every tool/editor/compare/result page uses the green
  tool-section box; the Devices list uses a blue box with the statistics box
  beside it; menu labels match the page titles.
* The stylesheet moved out of the CGI into an external, cacheable file,
  fetchconfig-web.css, linked with a ?v=<version> cache-buster and served from
  WEB_DIR via CSS_BASE_URL. Config reworked into web paths: WEB_DIR (filesystem
  root, presence checks), BASE_URL (URL root), and CSS_BASE_URL/FONT_BASE_URL/
  IMAGE_BASE_URL sub-paths (defaults /css, /fonts, /images). HELP_DIR,
  HELP_FILE and HELP_BASE_URL are removed (help.html is a fixed name under
  WEB_DIR); a missing stylesheet shows a red "directories not configured"
  banner. The login backdrop image loads from BASE_URL + IMAGE_BASE_URL +
  /back.jpg. Ship fetchconfig-web.css into WEB_DIR/css (see INSTALL).
* Fixed report deep links from notification emails: opening a
  ?action=view_report&file=... link while logged out now returns to that exact
  report after authenticating (the file= argument was previously dropped across
  the login). The argument is re-validated with the action's own validator so
  only a safe report file / template path is carried; valid_report_name was
  tightened to a safe character set.
* Removed the DEVICE_ID_FIELD config key: the Device-ID is always the second
  column of a device-table line, so the knob only confused (and the main parser
  ignored it anyway).
* The log viewer is renamed "View last fetchconfig schedule log" (menu, page
  and box title); the box title now shows the log's date and time.
* Tool-output pages (Backup Now, orphaned/empty backup and directory
  check/delete) now use the full window width; the dark result box fills it and
  scrolls long lines internally instead of forcing the whole page to scroll.
* The "Backups for <device>" page drops the "Check for empty backups" button
  (and its now-unused checkempty action); a 0-byte (empty) backup row is
  highlighted red instead. The site-wide Tools -> Empty backup cleanup is
  unaffected.
* Ships favicon.ico.
* FastCGI deployment (FCGI optional).
* Every function now carries a uniform header block.

## 1.52
* Requires fetchconfig 9.67 or newer (MIN_FETCHCONFIG_VERSION bumped from 9.65);
  the version warning banner and the required-version notes updated accordingly.
* Version bumped to 1.52.

## 1.51
* Fixed: user add/change/delete, permission changes (edit/admin rights, site
  assignment, report-download right) and site add/edit/delete were not recorded
  in the audit log -- the database handle was disconnected before the audit
  call, so the write was silently lost. audit() now detects a dead handle (via
  ping) and opens its own connection, and those callers no longer pass the
  closed handle. The set_user_sites entry now records which site codes were
  added/removed (and old->new), and the add_user entry spells out the rights.
  The report-download right change
  now logs grant vs revoke (like the edit/admin right changes) instead of a flat
  "updated" message.
* The device-table external-change tripwire no longer fails silently: if its
  app_state record cannot be read/written (e.g. the table is missing or not
  granted to the web user), a footer warning is shown instead of the check
  quietly doing nothing. A real content change is logged as external_change on
  login and editor open; an mtime-only touch is intentionally ignored. The
  detection now also shows
  the user a visible amber banner (on editor open, and once on the first page
  after login via a one-shot app_state notice), not just an audit-log row. The
  banner links to the audit log only for admins
  (a user with just the edit-device-table right sees the notice without the
  link, since they cannot open the audit log). On the device-table editor the
  banner
  also notes that the editor has loaded the changed table, so the user is
  editing the current on-disk content (not a stale copy). The bulk editor does
  the same: it now runs the tripwire on a fresh open and carries the same
  "editing the current content" note. (Fixed a regression where a
  stale DBI errstr on the shared handle made app_state reads look like failures,
  silently disabling the tripwire even though the token was stored.)
* Audit log. New append-only audit_log table (and a small app_state table)
  recording state-changing actions: device-table saves (one row per changed
  option, old -> new), restores, backup runs, deletes/cleanups, user add/
  change/delete, password changes/resets (never the password), site changes,
  logo upload/delete, template save/revert, plus logins / failed logins /
  logout and denied attempts (CSRF, out-of-site). Secret option values
  (pass/enable/SNMP community) are stored as ***.
* Immutability (Level B): the web DB user gets INSERT + SELECT on audit_log
  only -- no UPDATE/DELETE -- so the log cannot be altered or erased from the
  app; only a DBA can. Audit writes are fail-open: on failure the action still
  completes and a yellow warning is shown in the footer.
* External-change tripwire: the app records the device table's content token
  after its own writes and, on login and when the editor opens, logs an
  external_change entry if the table was modified outside the application.
* Tools -> Audit log viewer (admin only): 100 rows/page, newest first, fetched
  by AJAX (the table is never sent whole), First/Prev/Next/Last navigation,
  filters (user/action/object/text/date range) and CSV export.
* New standalone PostgreSQL 8.2-compatible script fetchconfig-web-audit.sql to
  add the audit tables to an existing database (also folded into
  fetchconfig-web-dbupdate.sql); fresh installs get them via
  fetchconfig-web-dbsetup.pl.
* Fixed: audit entries for actions that did not pass an explicit user (e.g.
  empty/orphan cleanup, backup_now) logged the session id instead of the
  username -- current_user() returned the session id (current_session's first
  element) rather than the username. The Audit log page now uses the wide layout
  and its table sits in a scroll wrapper inside the green box (the box fills the
  width and contains the table instead of overflowing).
* Audit log page: added a Reload button (Filter | Clear | Reload | Export CSV)
  that re-fetches the current page.
* New documents: LICENSE-ADDITIONS.md/.html (GPLv3 Section 7 additional terms --
  EU/German liability and warranty adaptation, severability, German/EU governing
  law) and PRIVACY.md/.html (GDPR notes; the software runs on the operator's own
  system and the operator is the data controller; the provider stores no data).
* New fetchconfig-web-clean-audit.pl: prune old audit-log rows with a privileged
  DB role (-t days to keep, -l preview, -s print the create-role SQL, -l
  requires -t, -u/-p or
  prompt for credentials, -v/-h). The prune is itself recorded in the audit log
  (action audit_prune, including the -t value), so the create-role SQL grants
  SELECT + INSERT + DELETE on audit_log (and the id sequence). The prune never
  deletes the audit_prune records themselves, so the pruning history is kept,
  and it writes a prune record only when rows were actually deleted (a run that
  removed nothing logs nothing). A failure to WRITE that prune record (e.g. the
  role was granted INSERT on audit_log but not USAGE on audit_log_id_seq) is now
  reported instead of being silent: the delete still succeeds and a warning
  names
  the missing grant. Version/copyright follow the config overrides.
* Added cpanfile (mirrors Makefile.PL prerequisites) to document the Perl module
  dependencies and support `cpanm --installdeps .`. (GitHub's dependency graph
  and Dependabot do not support CPAN, so no dependabot.yml is shipped.)
* Audit log viewer: the Old -> New column wraps long values -- after the arrow
  when present (>60 chars), otherwise at the nearest whitespace near 50 chars
  (40-60), or a hard break at 60 if there is no whitespace there.
* render-doc.py now also renders the GPLv3 LICENSE verbatim to LICENSE.md and
  LICENSE.html (preformatted, not reflowed).
* The Help menu is now a dropdown: Help (help.html or internal), Documentation
  fetchconfig-web, Documentation fetchconfig, GNU GPL v3, Additional terms,
  and Privacy policy -- each static doc shown only if present in the help
  directory and opened in a new browser tab (the Help page itself opens in the
  same tab).
* Help config split: HELP_DIR (filesystem dir, for the existence check) +
  HELP_FILE (filename) + HELP_BASE_URL (URL base, for the menu links), with
  the old full-path HELP_FILE still accepted.
* Removed the obsolete "Fetchconfig manual" topic from help.html.
* The internal help fallback is now a short notice that help.html is missing
  from the web help directory and should be copied from the source package,
  rather than a duplicate feature description.
* Audit log viewer: added a second First/Prev/Next/Last pager at the bottom
  (left-aligned, like the other pages); both pagers stay in sync.
* Audit log viewer: added the floating Top / Bottom scroll buttons that the
  other pages have.
* Email config: a gray hint after the "to" field notes that multiple recipients
  may be separated by ";".
* Backup Now now has a wall-clock timeout (BACKUP_TIMEOUT, default 120s, 0
  disables): a device that never responds no longer blocks the request. On a
  timeout the run is terminated and the partial tool output is still shown.
  The Backup Now page now shows the tool output whenever there is any -- even
  on an error/timeout (previously output was hidden on any error). Success is
  judged from the output (fetchconfig always exits 0): an "error:" line, or a
  "backup_state=failed" line in the stats block, means FAILED. The audit log
  records OK/FAILED accordingly; the meaningless exit
  status is no longer logged.
* Replaced the per-device "Check devices for empty backups" tool with an
  "Empty Backup Cleanup" tool (modelled on Empty Directory Cleanup): a Check
  (fetchconfig.pl -Z) and a Delete (-Z -D) that scan all devices at once for
  zero-byte backups, with a spinner and the tools output layout. The spinner now
  stays on the
  result page until the (slow) -Z scan finishes: the page renders the spinner
  immediately and fetches the result fragment by AJAX (with a no-JS fallback).
  The delete does
  the same -- its AJAX POST carries the CSRF token (and the action in the body,
  so the
  multipart POST reaches the right handler instead of falling through to the
  Devices page), and its no-JS fallback is a POST form. Success is
  taken from the summary line (rc 1 = "found some", not an error). The delete
  is audited. The per-device -z check remains on each device's backup page. (The
  old
  all-device scan code -- check_empty_one / device_empty_status -- was removed.)
  Help and README updated accordingly (empty backups is a cleanup, not a scan;
  dropped from the MAX_PARALLEL_SCAN tool list). The Tools menu entry is now
  "Empty Backup Cleanup" (the old "Check devices for empty backups" label was
  removed).
* Version bumped to 1.51.

#
## 1.50
* New Tools -> Disk space page: free/total space and use% for every repository
  directory (global REPOSITORY + per-device/default repository=) and the
  report_dir, grouped by filesystem (one table per filesystem, "Filesystem
  1/2/..."); the
  size figures are read once per filesystem and shown black on the first
  directory and gray on the rest (the device id is no longer shown -- it is not
  useful across AIX/Linux). "unknown" when a filesystem can't be read; missing
  directories listed under "Unavailable". The tool now also lists the
  directory: allow-list repository/report directories (not just the ones in
  use), with a Source column: configured / allowed / allowed and configured
  ($aliases expanded to real paths for matching). Uses the optional Filesys::Df
  module (loaded lazily;
  the tool shows an install hint if it is absent, the app is unaffected).
* The title-bar program icon now opens an About dialog (program name, internal
  version APP_VERSION_INTERNAL, configured/effective version, copyright [config
  COPYRIGHT or the built-in default], installed fetchconfig.pl version, GPLv3
  note; OK/Esc/backdrop to close). The page footer also
  falls back to the built-in copyright when none is configured, instead of
  ending in a bare dash.
* Report logo handling: the report_logo editor option is now a drop-down of
  the image files (.png/.jpg/.gif, up to 25, case-sensitive) in the
  report_dir, with a red warning if the directory holds more than 25. The
  stored value is the bare filename.
* New Tools -> Upload report logo page uploads a logo into the report_dir
  (<=100KB, PNG/JPEG/GIF verified by magic bytes, safe case-preserved
  filename) and lists existing logos with a Delete button and an inline base64
  preview (the report directory is not web-served, so previews are embedded as
  data: URIs).
* Fixed two edited-card round-trip bugs: a collapsed edited device no longer
  auto-expands after Preview -> Back to editor, and its red dot (and its edits)
  are no longer lost on the first or a repeated round-trip. The "Back to editor"
  render now embeds the full card in a collapsed row (fields still submit),
  carries r{n}_edited, and only re-opens rows that were actually open.
* Device editor: a device whose fields have been changed (not merely expanded)
  now shows a red dot after its Device-ID. The marker tracks real edits (field
  input/change, option add/remove, new device) and survives a Preview -> Back
  to editor round-trip.
* Password changes now rotate/invalidate sessions. A self password change mints
  a fresh session (seamless) and invalidates the user's other sessions; an admin
  reset of another user signs that user out everywhere (admin resetting their
  own non-protected account is rotated like a self-change). A request with a
  stale session cookie now lands on the login page with a "Your session has
  ended" notice instead of a blank form. Session cookie construction is shared
  via session_cookie(); clear_pw_warning_if_changed preserves the login_time.
* New config key SESSION_MAX_LIFETIME (seconds, default 86400, 0 disables): an
  absolute cap that force-expires a session that long after login regardless of
  activity, so a captured cookie cannot be kept alive indefinitely. Session
  files now carry a 5th line (login time); legacy 4-line files load and are
  upgraded in place.
* Fixed: expired session files were only removed when their own cookie was
  presented again, so files from abandoned cookies accumulated in SESSION_DIR.
  A login now runs a throttled sweep (at most once per SESSION_TTL) that reaps
  any session past its idle timeout or absolute cap.
* backup_and_write_table: on a partial write failure the message now states
  plainly that the table may be incomplete, names the pre-write backup, and
  tells the admin to restore it via Tools -> Restore device table (or copy it
  back on the server), noting a full disk / FS error as the likely cause.
* The device_table.lock flock target is created mode 0600.
* Documented (README + INSTALL): device-table .bak files are not pruned
  automatically (how to prune), and the empty device_table.lock is expected and
  must not be deleted while running.
* make test now runs cleanly: the test harness (t/lib/FCWebTest.pm) silences
  the "Subroutine/Constant subroutine ... redefined" and "used only once" noise
  that a deliberate second load of the CGI produced, and make_config skips
  undef overrides. No change to the shipped application.
* The test harness no longer prints "Subroutine ... redefined" / "used only
  once" / uninitialized-value warnings when a test loads the CGI more than once
  (e.g. to switch config). FCWebTest::load_cgi now filters that reload noise and
  make_config skips undef overrides; the affected tests set no warnings "once".
  Cosmetic only - no test outcome changed (271 tests pass).
* Restore device table now participates in the concurrency guard: its confirm
  shows the live table's last-modified time/age, and the restore takes the
  writer lock and re-checks the staleness token under it, so a restore started
  against a table that has since changed is refused instead of silently
  discarding the newer change (Gap C, Layers 1-2).
* New INSTALL.md (rendered to INSTALL.html by render-doc.py): a step-by-step
  installation and upgrade guide.
* render-doc.py: clearer usage errors (reversed args / missing input now print
  a usage message and exit cleanly instead of a traceback).
* render-doc.py now derives the page title/lede from the input document so it
  renders both README.md and INSTALL.md.
* Corrected the Perl requirements: Digest::MD5 and Time::HiRes listed; the
  phantom Digest::SHA / MIME::Base64 requirements removed (neither is used --
  MD5 is used deliberately to avoid a Digest::SHA dependency on older Perls
  such as AIX).
* Concurrency hardening of device-table writes. The staleness token is now
  <hires-mtime>:<size>:<md5> (Time::HiRes::stat for sub-second mtimes on AIX
  JFS2 / Linux XFS, plus a content digest), so a same-second rewrite is
  detected. Save, Bulk edit and the site-code rename now take an exclusive
  flock on a sidecar lock file, re-check the token under the lock and write
  while holding it, closing the check-then-write race in which two
  near-simultaneous saves could silently overwrite each other.
* Documentation brought up to date (README.md and help.html): collapsed device
  editor and on-demand card loading, Site/comment filters and top+bottom pager,
  Save changes / view-only Preview / Reject all changes, directory drop-downs
  showing $ALIAS + path, and the blue "default" flag.
* Device editor: an expanded card had two Collapse buttons; removed the
  redundant bottom one, leaving the single Collapse button on the summary line.
* The editor Defaults tab now shows "No per-model defaults are defined" when the
  device table has no default: lines, instead of appearing completely empty
  (notably for a site-limited read-only user).
* CRITICAL FIX: Preview -> Back to editor could wipe default-definition
  passwords
  and drop devices. The rebuilt records could be compacted, so field indices no
  longer matched the on-disk table: the masked-secret write-back read the wrong
  record (wiping passwords, defaults included) and a too-small rec_count dropped
  high-index devices. Records now carry their original disk index and rec_count
  covers the highest index, so everything round-trips correctly.
* Device editor: when SHOW_RENDER_TIME=1, expanding a device now shows the
  per-card AJAX timing below the table ("Last card: N ms (server M ms) - K cards
  loaded"); edit_card returns its server render time in an X-Render-Time header.
* Fixed: a freshly-added template_dir / repository / on_fetch_run option now
  gets
  the blue "default" flag and option colouring (previously only options present
  when the card was opened were tagged, and an added generic template_dir did
  not highlight the default directory because its default is reported as a
  $alias rather than a path).
* Editor: the green "Save changes without preview" button is now just "Save
  changes"; the Preview raw table page is view-only (its Save button removed
  -- use "Back to editor" to save).
* The Bulk edit editor keeps its own Save.
* Fixed a severe editor bug: Preview raw table -> Back to editor could change a
  device's model (e.g. generic -> nexus-ssh) because the reconstructed record
  order no longer matched the on-disk table that the collapsed rows re-fetch
  from. "Back to editor" re-renders only the devices that were expanded as cards
  (carrying the submitted values); the rest stay collapsed. Nothing is lost or
  mis-indexed.
* The generic model= option is labelled "model template" (vs the device Model).
* New config key SHOW_RENDER_TIME (0|1, default 0): when 1, it shows the
  load/render-time lines
  across the UI (device list, status, log, template list, and the device-table
  editor render time). Off by default, so these are now hidden unless enabled.
* Device editor: when a device's repository=, on_fetch_run= (directory part),
  or (for generic) template_dir= equals its model's default: value, a blue
  "default" flag is shown beside the dropdown and the matching option is
  coloured blue, so it is clear the device is using the model default.
* Directory drop-downs (template_dir, repository, report_dir, on_fetch_run) now
  show both the $alias and the directory it expands to in each option, instead
  of just the $alias.
* Device editor: the device-list First/Prev/Next/Last pager is shown both above
  and below the list.
* Fixed template_dir inheritance for generic devices: a device with no
  template_dir= now inherits the default: line's template_dir and lists that
  directory's templates (which fetchconfig -t tags as "default"); a device with
  its own template_dir= still lists only that directory. Fixed in the editor
  model drop-down, its live JS refresh, and the save-time validation.
* Editor collapsed rows now show a Comment column after Site, and the device
  filter gains a searchable Site drop-down (alongside Device-ID and comment).
* Fixed: collapsing a previously-expanded device left the row blank -- the
  summary line (ID/Model/Site/Comment) now stays and the card is hidden below
  it.
* New config key HTTPS_ENABLED (0|1, default 0, in the misc section of
  /etc/fetchconfig-web.cfg and the fetchconfig-web-dbsetup.pl template): set to
  1 to add the Secure
  flag to the session cookie when served over HTTPS, instead of editing the
  source. Documented in README.
* The HTML documentation sidebar is now built from the actual document
  structure (Part 1-4 and their subsections) instead of a stale hardcoded list,
  and ###/#### headings get id anchors so the nav links resolve.
* Device-table editor rewritten for large tables: devices now show as collapsed
  summary rows (Device-ID / Model / Site) and the full editable card is fetched
  on demand (?action=edit_card) when a row is expanded. Un-expanded devices
  round-trip verbatim on save. For ~2500 devices this cuts the page from ~9.5 MB
  to ~1 MB and the DOM from ~198k to ~18k elements (editor loads ~5-20x faster).
* Code cleanup: removed three unused section-renderer subs left over from the
  combined Tools page and corrected a stale comment on show_tools.
* Normalised .btn so <button> and <a> buttons render at the same height (e.g.
  Save vs Cancel on the Assign-sites page were slightly mismatched).
* Fixed back links that led to the empty User landing instead of the users
  table: the Edit-sites breadcrumb/Cancel, the reset-password breadcrumb, and
  the change-password warning link now go to the right page.
* Fixed the login box size/centering that the sticky-footer layout change had
  disturbed (box is now flex-centered with a fixed width).
* CRITICAL FIX: saving the device table as a site-limited editor could wipe the
  pass= of the edited devices (the masked-password write-back resolved the
  original by a sequential field index that did not match the table position).
  Editor field indices now use the record's real table position, so masked
  passwords are always restored to their correct value on save.
* Users table: the Grant/Revoke and Edit sites buttons now come first in their
  cell, before the current-state text / site list, and the yes/no tag matches
  the button height.
* Fixed narrow-window layout: the 900px minimum is now enforced on the body (so
  the whole page scrolls horizontally below 900px instead of clipping); green
  section boxes now grow (fit-content) to fully contain a wide table instead of
  the table spilling past the box edge, and no longer clip content that is wider
  (the box grows and the whole page scrolls horizontally),
  and a red banner appears below the menu when the window is under 900px.
* Fixed: the "Users list" menu item (and the redirects after user-management
  actions) now show the users table again instead of the "pick from the menu"
  landing message.
* The orphaned-backup / empty-directory delete tools now report the number of
  items deleted (parsed from fetchconfig's summary) instead of a vague "nothing
  needed deleting, or ... removed successfully" message.
* Fixed stale messages that referred to the removed "Tools page": the orphan /
  empty-directory check results now name the specific cleanup tool.
* Renamed "Orphaned Configuration Cleanup" to "Orphaned Backup Cleanup".
* Fixed: comparing/viewing device-table backups in the Restore tool no longer
  fails with "device not available" (the per-device guard applied only when a
  device is actually referenced). Dropdown menus now float above page content;
  the orphan/empty-cleanup result
  pages use a green "<- <tool>" breadcrumb at the top instead of a bottom button
  and
  the restore compare/view pages label their back button "Restore device table".
  The copyright footer sticks to the bottom of short pages and follows the
  content on long pages.
* Editor: "Cancel" is now "Reject all changes" (red) and reloads the table
  from disk after a confirm.
* Preview shows only "Back to editor".
* Tools/User landing pages prompt to pick from the menu; every tool sub-screen
  returns to its own tool.
* Add-user / change-password errors return to that page with the message above
  the form.
* Removed leftover back buttons (Sites, Check site assignment, log/template
  viewers).
* The title bar now uses application-style drop-down menus (Devices, Setup
  devices, Tools, User); Status/Reports moved under Devices; the Setup page is
  the read-only highlighted view (edit/bulk are menu entries).
* Each Tools and User menu item is now its own single-function page (one page
  per tool / per user action, no overview page, no back buttons).
* New Tools entry "Check site assignment" lists devices with no site=.
* Edit device table and Bulk edit lost their back button; the device list no
  longer nests a second scrollbar.
* site= is now a mandatory, non-deletable, auto-added device option rendered as
  a drop-down; saving a device with no site is blocked. For a site-limited user
  the requirement applies only to their own devices (others are preserved). The
  read-only Defaults view shows one merged box per model (last value wins). The
  Users Sites column wraps long lists; the layout keeps a 900px minimum with a
  horizontal scrollbar on narrower windows.
* A site code can no longer be deleted while it is used by a device (previously
  only a user assignment blocked deletion); enforced in the UI and server-side.
* Green section boxes now inset their content equally on the left and right
  (padding on the box, tables at full content width), so wide tables are no
  longer flush/clipped on the right.
* The User page also uses the full-width layout.
* The User page Users table has a "Full Report" column (the download-full-
  report right, with a grant/revoke toggle for site-limited users) between
  "Edit device" and "Sites"; the edit-right heading is shortened to "Edit
  device".
* Fixed the "Full Report" column so the granted state is actually shown.
* The Status page shows the site code as its first column; the Devices page
  shows it as the second column and adds a site filter drop-down (like the
  model filter), with a "(no site)" choice.
* Device editor: site= is a drop-down (code + description). Devices without a
  site show a red "no site assigned" and get the option added automatically on
  load; an unassigned site is not written back. The "no site assigned" entry is
  a red placeholder shown only until a real site is picked, after which it is no
  longer selectable; dropdown colours are consistent. The "+ add option" site
  entry
  is a drop-down too.
* Fixed: saving a user's site assignment crashed (undefined redirect helper);
  site_id now uses multi_param and the login "next" is read in scalar context,
  clearing the CGI "param called in list context" warnings.
+ Per-site device access: a device may carry a site=<code> tag, site codes are
  defined in the database (new sites / user_sites tables) and users are assigned
  one or more codes. A site-limited user sees and edits only their devices --
  the Devices/Status/Reports pages are filtered, direct device URLs are guarded,
  Setup opens the device editor only (Devices tab; Defaults view-only; no
  Email/Reporting, Bulk edit or raw view), Tools stays admin-only, and saves are
  merged into the full table server-side (other devices/sections preserved).
  Site 0 ("any site"/All sites) means unrestricted; admin always has it. Reports
  show only the user's device sections, and downloading the full report needs a
  per-user right. Admins manage site codes (add/edit/delete, with atomic code
  rename that updates site= in the device table) and per-user assignments from
  the User page. The site-management and assign-sites pages use the same green
  section box as the rest of the User page. Run the PostgreSQL 8.2-compatible
  fetchconfig-web-dbupdate.sql to enable it on
  an existing install (all users start unrestricted). fetchconfig.pl ignores
  site=. The update script grants the web user privileges
  on the new tables, and site add/edit/delete now report database errors (and
  recreate a missing sites_id_seq) instead of failing silently. The initial
  setup
  script also grants the web user access to the new site tables.

## 1.15
* After logging in, an unauthenticated user who opened a specific page URL
  (e.g. ?action=report) is returned to that page instead of always landing on
  Devices. Only a whitelist of read-only landing actions is honoured (no
  open redirect, no state-changing action).
* The Status page table is wrapped in the same green "tool-section" box as the
  Tools pages, for a consistent look.
+ The template viewer (Tools) and the new Reports page use the backup-table
  style: the green "tool-section" box with a bordered list and View/Edit/
  Download/Delete as buttons.
+ New "Reports" page (top menu, between Status and Setup): lists the HTML
  change-reports fetchconfig writes into the email: report_dir, newest first,
  with styled table and button actions; View (collapsible per-device diffs,
  parsed and escaped, Expand/Collapse
  all), Download (streamed as an attachment through the CGI), Delete, and a
  "delete reports older than N days" prune. All file access goes through the
  login since the web server cannot read the report directory directly.
* Removed the per-device "Check backup suffixes" button from the backups page;
  the Tools page "Check devices for consistent backup suffixes" covers this.
+ New template-driven "generic" model: a device selects model=generic and a
  model=<template> option, with model= rendered as a drop-down of the templates
  fetchconfig reports. Adopts fetchconfig's tab-separated --list-allowed-dirs /
  -t output and its exit codes (a missing directory blocks the editor and
  viewer with the fetchconfig output; "stay" is highlighted as a transition).
+ Tools: "Template viewer" lists the generic-model templates read-only with
  syntax highlighting, and "Template editor" edits them in a split view with a
  syntax check, single .tmpl.bak backup, revert, and unsaved-changes guard.
  Template writes go through a new privileged helper
  (fetchconfig-web-install-template.pl, run via sudo, configured by
  TEMPLATE_HELPER); non-regular files (symlinks, hard links) are refused.
+ Directory allow-list: the device table may carry "directory:" lines
  (repository / template / fetch_run / report, each $ALIAS + path), read
  server-side from
  the table so they cannot be forged and written back verbatim, armored with
  "must be edited on the server" comments (shown red in the Setup view). When
  present, the editor's repository=, template_dir= and on_fetch_run fields
  become drop-downs of the allowed aliases (expanded path shown in gray;
  on_fetch_run splits into a directory + a command field), saved lines store the
  $ALIAS, and a table using a directory not on the list cannot be saved.
+ New config keys FONT_BASE_URL, IMAGE_BASE_URL, HELP_BASE_URL (URL-path bases,
  validated at startup) and TEMPLATE_HELPER; integer config keys now report a
  clear configuration error on an invalid value instead of silently defaulting.
+ A device-table save is now validated by fetchconfig (-t and
  --list-allowed-dirs against the exact bytes) before being written, so an
  invalid table never reaches disk; the Bulk edit page runs the same checks.
+ Added a Makefile.PL and a t/ unit-test suite (Test::More), plus
  imageconvert.pl
  (encodes an image as a base64 Perl snippet, with README.imageconvert).
* Model-option audit against the fetchconfig README (timeout optional
  everywhere, plus per-model option corrections).
* Custom confirmation dialogs replace the browser's confirm(); wider,
  full-width layout for the config/compare/log/backup views; editor, preview
  and bulk-edit action buttons moved to the top of the page.
* Documentation restructured into parts with a table of contents and quick
  start.
* Minimum required fetchconfig version is now 9.65; fetchconfig-web is 1.15.

## 1.12
+ New models: "mediant-sbc" (AudioCodes Mediant SBC, Cisco-style CLI;
  user/pass/enable, optional transport=ssh|telnet|auto, adds an enum_transport
  editor field and an AudioCodes-syntax highlighter) and "nexus-ssh" (Cisco
  Nexus / NX-OS over SSH, with a dedicated NX-OS highlighter).
+ Tools: run the device scans (without-backups / empty / suffix) in parallel,
  controlled by MAX_PARALLEL_SCAN (1..5, default 1); the progress line shows
  how many scan processes are active.
+ Fixed intermittent scan failures by rewriting session files atomically (temp
  file + rename) and hardening child-process I/O (EINTR retry, checked
  waitpid, ASCII-safe JSON); each failed device now shows why.
+ Tools: new "Empty Directory Cleanup" (fetchconfig.pl -e / -e -D) and "Check
  devices for consistent backup suffixes" (fetchconfig.pl -s), plus a per-device
  "Check backup suffixes" button; and, under Restore device table, "Delete
  backups older than N days" (always keeps the newest).
+ Login page shows a full-page backdrop image (IMAGE_BASE_URL/back.jpg) behind
  the title bar, login box and bottom-centred footer.
+ New config keys FONT_BASE_URL and IMAGE_BASE_URL (URL-path bases for fonts
  and images).
* Config: the fetchconfig executable is now two keys -- FETCHCONFIG_PATH
  (install dir, also used to find Constants.pm) and FETCHCONFIG_BIN
  (executable name); the old single full-path form is no longer accepted.
* The page footer shows the installed fetchconfig version, and a warning
  banner appears if it is older than the required minimum or cannot be
  determined.
+ Device-table editor: numeric time fields show their unit (s / ms); the Email
  tab gained optional "port" and "tls" (off|starttls|ssl) options; the aruba-
  cx-ssh model gained optional prompt_settle_ms.
+ Fixed: coriant-8600 no longer wrongly requires an "enable" password.
+ Backup-filename parsing tolerates fetchconfig's filename_append_suffix (the
  backup list dates/times stay correct and "Download latest configuration"
  keeps a dotted suffix, else .cfg).
+ Empty-backup check also recognises fetchconfig's newer "N zero-byte
  backup(s)" message.
* Security hardening: device ids/usernames reject a leading "-" (central
  valid_id, so an id can't be read as a CLI option); unsalted {SHA} password
  hashes removed ($apr1$/$1$/$5$/$6$/DES kept); session cookie SameSite=Lax;
  uniform 2s delay on failed logins; Backup-Now cleartext temp file auto-removed
  on exit; SESSION_TTL is now an idle timeout; numeric/boolean config keys
  validated with fallback to defaults.
+ Licensed under the GNU GPL v3+ (headers in both programs, LICENSE file,
  README section).
+ render-doc.py runs on Python 3 and 2.7.
+ Documentation reworked (added a "How fetchconfig.pl is invoked" reference
  and a security overview; wider HTML manual).
+ APP_VERSION is a built-in constant, overridable by the config.

## 1.11
+ Config file default path is now /etc/fetchconfig-web.cfg (was
  /etc/fetchconfig.cfg); rename on upgrade.
+ Backup list: new "Download latest configuration" button (newest backup as
  "<Device-ID>-YYMMDD-HHMMSS.cfg", web-binary models as their decoded file).
+ New "Status" page (nav, between Devices and Setup): a table of every device's
  last-run status from the per-device .status files -- Device-ID, start/end
  date+time, duration, state and changed, colour-coded, with dropdown filters,
  sorting, paging and a load-time line (N/A when no status file).
+ Tools: new "View fetchconfig log" -- opens the scheduled (cron) run's output
  (FETCHCONFIG_LOG) on its own page, split into collapsible per-device sections
  (green ok / red failed, failed expanded), with Expand/Collapse all and a
  LOG_MAX_DEVICES cap (default 1000).
+ Backup Now overlay: shows the elapsed runtime (with a "this can take a while"
  note after 10s) and, when a per-device .status file exists (fetchconfig
  >= 9.52), the last run's runtime/state/changed.
+ Devices page: statistics panel shows a "Device table load time".
+ Device-table editor, Email tab: added the optional "footer" option.
* Fixed: with multiple email: lines the editor wrongly reported from/to/smtp
  missing (the mandatory check now merges all email: lines); and email: values
  are no longer needlessly quoted for spaces (only commas force quoting).
* Button labels made sentence case app-wide (Backup now, Compare selected, ...).

## 1.10
+ New device models: "procurve-snmp" (HP ProCurve ProVision incl. 4000M/8000M,
  backed up over SNMP+TFTP -- no user/pass, mandatory "community" secret,
  masked; text backup, no highlighter); "aruba-cx-ssh" (Aruba CX / AOS-CX over
  SSH, no enable, with a dedicated AOS-CX highlighter); "planet-ssh" (PLANET
  managed switches, Cisco-IOS-like, reuses the IOS highlighter);
  "tplink-web-sg105e" and "procurve-web-1700" (web-managed, no CLI: opaque
  uuencoded backups, so Compare/checkboxes are hidden and the view offers a
  Download of the transparently uudecoded binary; procurve-web-1700 makes user
  optional).
+ Devices page: added a Hostname column with its own filter (IPv4 sorts numeric,
  then names); the pager gained First/Last buttons (editor Devices tab too); the
  "+ Add model defaults" button adds at the top.
* Fixed UTF-8 handling: backups with non-ASCII characters (e.g. umlauts) are now
  decoded before display (no mojibake), and the Copy button's legacy fallback
  puts UTF-8 text on the clipboard correctly over plain HTTP.

## 1.9
+ New device model "zyxel" (user/pass/repository/keep/timeout mandatory; enable,
  show_cmd, debug optional), with a dedicated IOS-like highlighter.

## 1.8
+ Device-table editor (Setup -> Edit device table): a structured three-tab
  editor (Devices / Defaults / Email) driven by a per-model option catalog,
  replacing raw-table editing. Masked-secret fields with keep-on-save, per-model
  "+ add option" menus, host validation (IPv4/IPv6/FQDN), duplicate-ID checks, a
  "Preview raw table" step, an mtime concurrency guard, and a timestamped backup
  to $BACKUP_DEVICE_TABLE before each save (table overwritten in place; option
  parsing/serialisation matches fetchconfig exactly). Devices tab paginates at
  100 and has Device-ID/comment filters (cookie-persisted).
+ Bulk Edit (Setup, admin only): plain-text editor for the device lines only;
  saving replaces the DEVICES SECTION with all-or-nothing validation, the mtime
  guard and a backup (default:/email: untouched).
+ Tools (admins only): "Check for orphaned backups" / "Delete orphaned backups"
  (fetchconfig -o / -o -D); "Devices without backups" and "Check devices for
  empty backups" scans (fetchconfig -l / -z) with a live progress bar and
  Start/Cancel; and "Restore device table" -- list the timestamped backups with
  View / Restore / Delete (Restore backs up first; strict name validation) and
  compare any two configs (unified or side-by-side, newer green / older red,
  quote-aware; passwords masked with a reveal checkbox).
+ "admin_function" per-user right (a full admin, like the built-in admin),
  managed from the User page; new users-table column (see README for the upgrade
  SQL).
+ Config syntax highlighting on the backup view for cisco-ios / cisco-ios-ssh
  (extensible per-model registry; cosmetic only, same masking/escaping).
+ New device model "hirschmann" (user/pass/repository/keep/timeout mandatory;
  enable, show_cmd optional).
+ UI: model filter is a dropdown of models in use (cookie-persisted); a live
  "devices filtered" count; floating Top/Bottom nav on long pages; editor action
  buttons moved to the top; User page areas separated into boxes.
* Fixed: "Check devices for empty backups" misparsed the single-device -z output
  and treated -z exit 1 ("empties found") as an error; and the read-only Compare
  form used the wrong enctype.

## 1.7
+ Intermediate development version introducing the first structured
  device-table editor; superseded by the consolidated 1.8 above.

## 1.6
+ User accounts moved from the htpasswd file to a PostgreSQL database
  (DBI/DBD::Pg). Standalone setup script fetchconfig-web-dbsetup.pl creates
  the database/table, can import existing htpasswd accounts, and can write
  /etc/fetchconfig.cfg. New-password hashing is pure-Perl Apache MD5
  ($apr1$), so the htpasswd binary and its sudo rule are no longer needed.
+ Per-user "edit_device_table" right (grantable from the User page) that
  also grants read access to the Setup page.
+ Default-password login warning until an account changes away from the
  default password.
+ All configuration moved to an external file, /etc/fetchconfig.cfg
  (key = value); only the config-file path, app title, and cookie name stay
  hard-coded.

## 1.5 and earlier
+ Login, device list with live filter and sortable Model/Device-ID columns,
  per-device backup list with Date/Time columns, backup content view with
  copy-to-clipboard, unified "Compare" and "Side by Side" diff views,
  "Backup Now" and "Check Empty Backups", the read-only Setup page, in-UI
  user management, and the Help page. CSRF protection and server-side
  session store throughout.

