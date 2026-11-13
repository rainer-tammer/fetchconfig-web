# fetchconfig-web -- Change Log

Release history for fetchconfig-web, newest version first.

## 2.17.15

* Device-table editor: deleting an option now restores it to that card's "+ add option" menu.
  Previously, adding an option then deleting it removed it from the dropdown for the rest of the
  session, so it could not be added back (e.g. snmp_inventory_level). The option is re-inserted in
  sorted order with its correct type; applies to device, model-defaults and Email cards.

## 2.17.14

* Performance: the device-table editor's `--list-allowed-dirs` engine fork (~340 ms, the largest
  remaining cost) is now cached across FastCGI requests, like the `-t` cache -- reused while the
  device table is unchanged and younger than the TTL, invalidated at once by any save/table change.
  Plain CGI is unaffected.
* dbsetup (PostgreSQL 8.2): inventory sequence ownership now uses `ALTER TABLE <seq> OWNER TO`
  instead of `ALTER SEQUENCE ... OWNER TO` (the latter is 8.3+ and errored on 8.2), guarded by an
  existence check; `CREATE LANGUAGE plpgsql` is skipped when the language already exists (no more
  spurious error in the server log). Existing installs can set the ownership directly -- see the
  2.17.14 upgrade note.

## 2.17.13

* Performance: schema/column existence probes now use `pg_catalog` (pg_class / pg_attribute)
  instead of the `information_schema` views, which are very slow on PostgreSQL 8.2. A single
  `information_schema.tables` probe was ~340 ms and dominated the device-table editor render; it is
  now sub-millisecond. Same fix applied to the inventory viewer, the inventory dashboard, the
  backup-health check and the schema-version lookup. One-time migration `.sql` files are unchanged.

## 2.17.12

* Diagnostics: with `SHOW_RENDER_TIME=1`, the device-table editor now appends an HTML comment
  breaking the server render time into phases (auth/DB, parse, templates `-t`, inventory DB, row
  build), and the "Rendered in" line shows the device count. View source to read it. No cost when
  the flag is off.

## 2.17.11

* Performance (FastCGI): the device-table editor forked `fetchconfig.pl -t` on every load just to
  check for broken templates. That result is now cached across requests and reused while the device
  table is unchanged and the result is younger than 60s, so a healthy install forks the engine at
  most once per minute. A save, or any device-table change, invalidates it immediately. Plain CGI is
  unaffected.

## 2.17.10

* Performance: the device-table editor renders much faster on large fleets. `mask_secrets()`
  (run on every escaped value) now short-circuits strings that cannot contain a credential, so
  the device list is built with a fraction of the work. Output is byte-for-byte identical. In
  testing, server-side render of 2600 devices dropped from ~1.4s to ~0.1s.

## 2.17.9

* Device-table editor: the "Save changes" button stays greyed out until the editor is dirty, and a
  save only writes a device table when there are actual changes. It enables on the first edit in any
  tab (devices, defaults, email, general) and after a Preview round-trip.

## 2.17.8

* Inventory dashboard: the Needs-attention empty state no longer claims every device was collected
  while some are still pending their first collection. It now reads "No failed or disabled
  collections" and points at the Pending tile. (Needs attention still lists failed/disabled only.)

## 2.17.7

Inventory dashboard: distinguish "pending" from "not configured".

* A device with no inventory row is now split into **Pending** (SNMP inventory is configured -- on its
  own line or via a `default:` line -- but not collected yet) and **Not configured** (no SNMP
  credentials). Determined from the device table using the engine enable rule (`snmp_inventory != 0`
  and a community / v3 user present). Separate KPI tiles, and a three-way Collection-coverage bar.

## 2.17.6

Inventory dashboard: per-panel "Show N" selector.

* By vendor / Top models / OS versions and Needs attention each get a **Show N** select in the
  upper-right (5 / 10 / 25 / 50 / 100 / All). Defaults: 10 for the ranked panels, 25 for Needs
  attention. The choice is saved per panel in the `fcweb_invshow` cookie and read server-side, so the
  first render already matches it.

## 2.17.5

Inventory dashboard fixes.

* **Collection status** now uses the real status values (`successful` / `failed` / `disabled`);
  shows OK / Failed / (Disabled) / Not collected.
* **Firmware** tile now counts devices that actually have firmware (read from
  `device_inventory_component.fw_version`), instead of always showing `n/a`.
* **Needs attention** now lists only devices that failed or are disabled — not successful or
  never-collected ones.
* **Top models / OS versions** now show the vendor in front; long labels wrap. Status label "OK" →
  "Successful". Added vertical spacing between the dashboard's panel rows. Header now reads
  "Last (partial) collection attempt seen".

## 2.17.4

Inventory dashboard. Code + CSS, no database change (reads the existing inventory tables).

* New **Dashboard -> Inventory**: a read-only, fleet-wide roll-up of the SNMP inventory
  (`device_inventory`) -- KPI tiles (devices, with/without inventory, failed, stacked, firmware set),
  collection coverage and status bars, ranked **By vendor / Top models / OS versions** breakdowns,
  a data-freshness view (age of the last success), and a **Needs attention** list (failed / partial /
  stale devices, each linking to its Inventory data page). Shown only when `ENABLE_DASHBOARD = 1`;
  scoped to the viewer's visible devices (global vs restricted scope pill), and degrades to a short
  notice if the inventory schema is absent or unreadable. Reuses the existing dashboard styling.
* **Docs:** README documents the new dashboard, and the Tools-menu entry list is reordered to match
  the actual menu order.

## 2.17.3

Devices list: column reorder, plus a documentation note. Code + docs, no DB change, no CSS change.

* **Devices -> Devices** column order is now **Model | Device-ID | Hostname | Vendor | HW Model |
  Site | Comment | Note** (Device-ID and Hostname moved up next to Model). The filter row follows
  the same order (Model, device, hostname, Site, comment). Purely cosmetic: sorting still keys off
  each header's `data-key` and filtering off the row `data-*` attributes, so neither is affected.
* **Docs:** README gains a "Secret masking" section describing the two placeholder forms the
  config/compare/device-table views use -- a quoted value keeps its quotes and masks the contents
  (`"***"`), a bare value becomes the sentinel `?***?` -- and which credential patterns
  `mask_secrets` covers. No behaviour change.
* **Docs:** new `QUICK-INSTALL` -- a one-page, command-only install checklist that points back to the
  matching INSTALL step for each item, for operators who want the fast path.
* **Docs:** the rendered HTML now prints in a smaller, print-native type size (body 10pt, code blocks
  8.5pt) on top of the existing print rules (nav hidden, full-width, wrapped code). Render-only.
* **Docs:** documentation consistency pass. Corrected the stated minimum engine version to 9.80
  (README/INSTALL had 9.77; `MIN_FETCHCONFIG_VERSION` is 9.80); added the 2.17 sysName/sysLocation/
  sysContact fields to the README inventory summary; added INSTALL upgrade notes and TOC entries for
  2.17.0-2.17.3; and refreshed stale version examples. Doc-only.

## 2.17.2

Two fixes. Code + docs, no DB change.

* **Secret masking:** a PLANET switch config uses the bare `snmp community <value>` command (no
  `-server`), e.g. `snmp community "public" ro` or `no snmp community public`. The config/diff
  viewer now masks the community in that form too (quoted or bare, with an optional `no` prefix);
  the `ro`/`rw` access level stays visible. Previously only `snmp-server community` / `set snmp
  community` were masked, so planet-ssh communities showed in cleartext.
* **LICENSE page:** `LICENSE.html` is regenerated from the plain `LICENSE` master (as INSTALL
  documents) instead of `LICENSE.md`; the full licence text now renders inside a `<pre>` block
  rather than collapsing into the page lede with a literal ``` ``` ```.

## 2.17.1

Devices list: the HW Model column now **wraps** instead of truncating. Code + CSS, no DB change.

* The capped HW Model column (so it can't dominate the row) lets a long value **wrap onto further
  lines** rather than being clipped with a fade (2.16.6) -- nothing is hidden. The title tooltip
  stays.
* Docs: the rendered reference manual is now **`README.html`** (was
  `fetchconfig-web-documentation.html`) so every `X.md` renders to `X.html` consistently; the page
  title is unchanged ("fetchconfig-web -- Documentation"). Update any deploy script or bookmark that
  referenced the old name.

## 2.17.0

Inventory: device SNMP system-group fields (sysName / sysLocation / sysContact). Schema
**2.16 -> 2.17**; run `fetchconfig-web-dbsetup.pl --upgrade`.

* Three new nullable `text` columns on `device_inventory` -- `sysname`, `syslocation`,
  `syscontact` (SNMPv2-MIB system-group scalars). Additive only: no change to any existing
  table, column, grant or index.
* The per-device Inventory viewer shows them in the Summary table (next to Vendor/Model/Serial);
  a NULL shows as an em-dash.
* Current-state only: these are **not** change-detection triggers and are not written to the
  inventory history (a rename/relocation is administrative, not a hardware event).
* `fetchconfig-web-dbupdate-2.17.sql` (8.2-safe, idempotent, no grant change); `@UPDATES` gains
  the 2.17 row with a `col_exists` signature probe. The columns stay NULL until an engine build
  that collects them is deployed; one web build runs against both a 2.16 and a 2.17 database.

## 2.16.6

Devices list: tame the HW Model column. Code + CSS, no DB change.

* The HW Model cell is capped at ~25 characters on one line, with the overflow **faded out**
  (CSS mask) instead of widening the column; the full value is in the cell's native **title
  tooltip**. No extra DOM -- just a `title` attribute and a CSS mask (browsers without
  mask-image support fall back to a plain clip).

## 2.16.5

Backup Now page tidy-up. Code only, no DB or CSS change.

* Removed the redundant blue "Return to backups for ..." button at the bottom; the green
  breadcrumb button above the output now reads "Backup view <device>" and links to the same
  place.

## 2.16.4

Inventory-view wrapping fix. Code + CSS, no DB change.

* The Components and Change-history tables now use a fixed column grid pinned to the content
  width, so they can never grow past the content box -- long cells wrap instead (2.16.3 fixed
  only the Summary "Hardware set" row).
* Docs: the new "User/secret alias conventions" section rendered literal `&rarr;`/`&rArr;`
  entities as text; they are now plain `->` / `=>`.

## 2.16.3

Device-table editor: `pw:` credential aliases (Step 2), plus two view tweaks. Code + CSS, no
DB change. Alias references need engine 9.79+; the first-character escaping of a verbatim value
starting with `$` or `\` needs the engine's de-escape grammar
(`fetchconfig-pw-alias-grammar-engine.md`).

* Credential fields (`user`, `pass`, `enable`, `snmp_user`, `snmp_community`,
  `snmp_write_community`, `snmp_authpass`, `snmp_privpass`) become a dropdown of the
  matching-kind `pw:` aliases plus a verbatim field. An alias is stored and shown as `$Name`
  (never masked, with an info note); a verbatim secret stays masked, a verbatim user name is
  shown in clear. On save a literal is quoted (comma/whitespace) or leading-escaped (`\$`/`\\`),
  never both; interior `\`/`$` are untouched.
* New `ALIAS_REPLACE_ON_SAVE` config key (`off` | `secrets` | `users` | `all`, default `off`):
  fold a verbatim value that matches a defined alias's value back into `$Alias` on save
  (compared in memory, never displayed or logged).
* `snmp_level` is now a dropdown (`noAuthNoPriv` / `authNoPriv` / `authPriv`, or blank to derive
  from the passphrases) instead of free text.
* Inventory view: Hardware set and the change-history Members list show one component per line.

## 2.16.2

Fix: the 2.16.1 Dismiss-button inline script was emitted malformed (a brace-counting bug),
which broke the page's other scripts. Now built correctly, with a balanced-JS regression test.
Code only.

## 2.16.1

The external device-table-change warning banner gains a Dismiss button: it clears the viewer's
one-shot notice server-side (audited), without reloading the page. Code only.

## 2.16

Schema level 2.16: adds `device_inventory_component.fw_version` (firmware / ROMMON version),
written by the engine's SNMP inventory collector. DB change (one nullable column, additive);
run `fetchconfig-web-dbsetup.pl --upgrade`.

* Release minimum engine raised 9.78 -> 9.80 (a soft, non-blocking header warning appears on an
  older engine).
* `fetchconfig-web-dbupdate-2.16.sql` adds `fw_version TEXT` to `device_inventory_component`
  (8.2-safe, idempotent, no grant change).
* The per-device Inventory viewer gains an FW version column (after SW).
* Fixed: the About dialog now reads the applied DB schema level live, instead of caching it for
  the FastCGI process lifetime (it went stale after `--upgrade`).

## 2.15

Device Inventory (engine 9.79+): the DB schema, the SNMP inventory editor options, and a
read-only per-device viewer, plus `pw:` credential allow-list preservation. DB change at schema
2.15 (`--upgrade`); the feature stays inert until an SNMP-inventory engine is configured.

* Schema 2.15 (`fetchconfig-web-dbupdate-2.15.sql`): three writer-owned tables
  (`device_inventory`, `device_inventory_component`, `device_inventory_history`) -- web login
  `SELECT`-only, no foreign keys (all keyed on `dev_id`), 8.2-safe and idempotent.
* Device editor: the `snmp_*` option set (community / version / port / timeout / retries, the
  SNMPv3 set, `snmp_inventory*`, `snmp_fatal`, `snmp_max_repetitions`, `snmp_inventory_interval`;
  `snmp_profile_file` is `default:`-only), offered via **+ add option**. SNMP credential options
  are masked like `pass=`. `procurve-snmp`'s `community` is renamed to `snmp_community`.
* Read-only Inventory page per device (summary, component list, change history), with the same
  per-site access check as the backups page.
* The `pw:` credential allow-list is preserved verbatim from disk and never editable in the web
  UI; `pw: pass` values are masked, the `$alias` stays visible. (Editor alias selection arrived
  in 2.16.3.)
* Editor fixes: an empty option value is no longer written as `key=`; `on/off` options accept
  the engine's permissive forms (`1`/`0`/`yes`/`no`) without blocking a save; every model shows
  `site` as a dropdown; an existing `default:` entry's model is locked (it is the entry key);
  the Defaults tab is sorted by model with a filter box.

## 2.14

Setup devices -> Rename device-id: a web front-end for the engine's device-id rename (requires
fetchconfig 9.78+). Privilege-only DB change (`--upgrade`).

* Rename a device id everywhere -- device table, on-disk backup tree, and dashboard history --
  under the engine's lock, with a mandatory dry-run Preview; runs through the sudo helper. The
  device note moves with it and the rename is audited. An existing device's Device-ID becomes
  read-only in the editor.
* Replay DB change button: flush the history-database outbox after a rename that queued while
  the database was unreachable.
* `fetchconfig-web-dbupdate-2.14.sql` grants the writer role `UPDATE` on `dev_id` for
  `backup_runs` / `backup_versions` (column-scoped on PostgreSQL 8.4+, whole-table below) and
  records schema 2.14. The web login stays `SELECT`-only.

## 2.12

Adds the **Changes** dashboard view (configuration churn) and per-version line
counts.

* **Dashboard -> Changes** (`ENABLE_DASHBOARD`, open + site-scoped): change
  frequency, independent of backup freshness -- KPI tiles, a 16-week churn chart
  (pre-cut-over weeks marked, spikes flagged), a 30-day most-changed leaderboard,
  time-since-change buckets, and a **Top N recently changed - last D days** feed
  (N/days inputs) showing `+added / -removed` line counts, each with a **View diff**
  that opens exactly that version against its predecessor. The Overview gains a
  compact *Recently changed* card. Read-only; no file I/O on load.
* Every Overview and Changes tile **and panel** carries a **scope pill** --
  `global` (whole fleet, for unrestricted viewers) or `restricted` (limited to the
  viewer's sites).
* The **About** dialog now shows the applied **DB schema** version.
* **`fetchconfig-web-dbupdate-2.12.sql`**: adds `lines_added` / `lines_removed`
  (nullable) to `backup_versions`; `dbsetup.pl --upgrade` applies it, grants the
  writer `UPDATE` on them, and grants the web user `SELECT` on `schema_migrations`.
* **Requires fetchconfig 9.77+** (`MIN_FETCHCONFIG_VERSION`) for the line counts,
  which the engine writes and backfills. Older engines: a non-blocking header
  warning; the view works, deltas show `--`.
* **UI / webfonts**: the interface now uses the bundled **IBM Plex Sans**, and the
  config / diff / log views use **IBM Plex Mono** (both SIL OFL 1.1, in `fonts/`),
  loaded via `@font-face` with `font-display: swap` and a system-font fallback --
  so a consistent look where the fonts are installed, the platform fonts where they
  are not. Copy `fonts/` into `WEB_DIR` (see INSTALL).
* **Devices -> Compare devices**: a side-by-side comparison of **any two
  devices** (any models/extractors -- an old-style extractor on one side and
  generic on the other is fine). Pick each device (with an optional per-site
  filter and type-to-filter) and a backup version -- the latest of each by
  default, or an older one for a point-in-time comparison. The result reuses the
  aligned diff view (secrets masked) with a difference count, *Only differences*
  and *Ignore whitespace* toggles, **Swap**, a plain-text **Download diff**, and
  **New comparison**. Access is per device: site-limited users can only pick and
  compare devices in their own sites.
* An **unknown or unsupported `action`** now returns a proper *404 Not Found*
  error page instead of silently falling back to the device list.
* CSS cleanup
* UI cleanup to ensure consistency
* Corrected several documentation issues.

## 2.11

Adds the optional **Backup Dashboard**, backed by history tables the fetchconfig
engine (**9.75**) writes through its optional DB writer. With the dashboard off,
nothing changes. Also adds a schema-version ledger and an `--upgrade` mode for the
setup tool.

### Dashboard (`ENABLE_DASHBOARD`, default 0)

* **Overview** ("Backup health"): fleet KPIs, freshness bar, status donut,
  backup-age histogram, 14-day trend and a **By site** panel -- all with a
  Fresh/Stale/Failed/Never colour legend. Open to every user (site-limited users
  see only their own sites); never filtered.
* **All devices** (admin): Device / Site (`code / description`) / Model / Last
  backup / Status / Size, with **View** (`?dev=`), a Device/Site/Status filter,
  sortable Last backup (default) and Status, a pager and **Export CSV**. Devices
  with no DB row yet show **No data** (vs **Never** = a row but no good backup).
* **Tools -> Cleanup dashboard** (admin): delete orphaned statistics (device-ids
  no longer in the device table), all-or-nothing, via a writer connection.
* **Backups** page: a small **SHA1** button per backup copies that version's
  integrity checksum (from `backup_versions`), shown only when on file.
* After login, users land on the Overview when the dashboard is enabled.
* DB-only and best-effort: with the schema missing/empty the pages show setup
  guidance (including the exact `db:` line, password masked) instead of failing.

### Database

* **`schema_migrations` ledger + `fetchconfig-web-dbsetup.pl --upgrade`** (run as
  root): applies every pending `fetchconfig-web-dbupdate-*.sql` and sets up the
  writer role and grants -- all via Perl DBI, **no `psql` dependency**.
* **`fetchconfig-web-dbupdate-2.11.sql`**: the three history tables
  (`backup_current`, `backup_runs`, `backup_versions`) + indexes; 8.2-safe,
  idempotent. `--upgrade` makes the **writer** own them (the web login stays
  `SELECT`-only); the ledger stays superuser-owned.
* Timestamps are a **naive local wall-clock epoch** (single box, one TZ).

### Other

* `db_pass` is added to the secret-masking rules.
* The editor's third tab is renamed **"General parameters"** and holds the
  admin-only `db:` fields (round-tripped into the `default:`-level `db:` line).

## 2.10

Requires fetchconfig 9.74 (was 9.72). A security-hardening release (no database
change) that also adds template-integrity awareness to the Templates page.
Addresses an external source review: mandatory bcrypt, secure-by-default HTTPS,
and a subprocess output cap, plus authorization and documentation hardening.

### Security

* **Require bcrypt by default (`REQUIRE_BCRYPT`, default 1).** New and changed
  passwords are never written as the weaker Apache MD5 (`$apr1$`); if
  `Crypt::Bcrypt` cannot be loaded the login screen says so and **login is
  disabled**, rather than silently using a weak hash. Legacy `$apr1$` hashes
  still verify and upgrade to bcrypt on the owner's next login. Set
  `REQUIRE_BCRYPT=0` to allow the fallback on a stack without the module (e.g. an
  AIX dev box). [F-01]
* **Secure by default -- `HTTPS_ENABLED` now defaults to 1.** The `Secure` cookie
  flag and HSTS are on unless you opt out. A new `effective_https()` also
  auto-detects TLS from the web-server environment (`HTTPS` / `REQUEST_SCHEME`)
  and, with the new **`TRUST_FORWARDED_PROTO`** (default 0), from a reverse
  proxy's `X-Forwarded-Proto`. **HTTP-only deployments must now set
  `HTTPS_ENABLED=0`** (see *Upgrading to 2.10*). [F-02]
* **Subprocess output cap -- `CAPTURE_MAX_BYTES` (default 50 MiB, 0 = off).**
  Every captured subprocess (fetchconfig runs, *Backup Now*, the privileged
  helper) is bounded so a runaway child cannot exhaust worker memory; on overflow
  the child is terminated and a controlled error is returned (*Backup Now* keeps
  the partial transcript). [F-04]
* **Password-reset transport documented.** `SITE_URL` may be `http://` so the app
  can run HTTP-only, but that sends the reset token over cleartext -- use
  `https://` in production. (Reset tokens are already SHA-256-hashed at rest,
  single-use and TTL-bound, and are never derived from the `Host` header.) [F-03]
* **Fixed: secrets could leak in the configuration *compare* view.**
  `render_unified_diff()` masked each line *after* the diff marker (`-`/`+`/`<`/
  `>`) was prepended, which moved the start of the line and defeated every
  `^`-anchored masking rule -- the Aruba CX indented `key`, both SNMP community
  forms, the Hirschmann positional community, and the radius/tacacs `key` (incl.
  the Nexus numeric type). It now masks the config content and re-attaches the
  marker, so the compare view masks exactly what the normal config view does.
  (The side-by-side view and the normal config view were never affected.)

### Templates

* **New "Orig" column** on Tools -> *Templates*, classifying each file by its
  SHA-1 against the `integrity.sha1` manifest fetchconfig ships (fetchconfig owns
  the templates): **Original** (hash matches a shipped template), **Edited** (hash
  listed but differs -- a shipped template modified locally, which will be
  overwritten on the next fetchconfig update, shown as a warning), or **Custom**
  (no hash available -- the admin's own template, including any template in a
  directory that has no manifest, such as an additional template directory).
* **Shipped templates are protected from in-place changes.** On an Original/Edited
  row, *Edit* and *Delete* are disabled and *Rename* is replaced by a green
  **Copy** button that creates an editable custom copy -- name pre-filled
  `<name>-cust` (editable; `.tmpl` is always added), into a chosen configured
  template directory or, when none are configured, the source template's own
  directory. An existing name, or a shipped manifest name, is never overwritten.
  Custom templates keep full edit/rename/delete as before.

### Hardening and documentation

* **Authorization regression guard** (`t/E0-authz-matrix.t`): asserts every
  privileged handler keeps an authorization check -- an in-body predicate, the
  dispatcher's central device-scope guard, or delegation to one that checks. [A-01]
* **Output-encoding regression tests** for the central `esc()` HTML encoder. [A-02]
* **Security hardening checklist** added to INSTALL (non-root CGI; config, session
  and backup-repo permissions; scoped sudo; enforced HTTPS/HSTS). [A-03]
* **Dependency-scanning guidance** added to DEVELOPER (scan the deployed Perl
  modules and OS packages, not just the source). [A-04]
* New tests `t/E1`..`t/E4` cover require-bcrypt, `effective_https()`, the capture
  cap, and output encoding.

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

## 1.51

Adds the audit log and an external-change tripwire for the device table.

* **Audit log** -- a new append-only `audit_log` table records state-changing
  actions (device-table saves as one row per changed option with old -> new,
  restores, backup runs, deletes/cleanups, user/site/password/logo/template
  changes, logins/logouts/denied attempts); secret values are stored as `***`.
  The web DB user gets INSERT + SELECT only, so the log is immutable from the
  app; audit writes are fail-open (a failure warns in the footer, the action
  still completes).
* **Audit log viewer** (Tools, admin): 100 rows/page newest-first, AJAX-loaded,
  user/action/object/text/date filters, CSV export, and top and bottom pagers.
* **External-change tripwire** -- the app stores the device table's content token
  after its own writes and flags an `external_change` (audit row plus an amber
  banner on login and editor open) when the table was changed outside the
  application; an mtime-only touch is ignored. The editor banner notes it has
  loaded the current on-disk table.
* **`fetchconfig-web-clean-audit.pl`** -- prune old audit rows via a dedicated
  privileged role; the prune is itself audited and never deletes its own records.
* **Backup Now** gains a wall-clock timeout (`BACKUP_TIMEOUT`, default 120s);
  output is shown even on error/timeout and pass/fail is read from the output.
* The per-device empty-backup check becomes a site-wide **Empty Backup Cleanup**
  tool (check / delete, with a spinner and AJAX result).
* New **LICENSE-ADDITIONS** and **PRIVACY** documents and a `cpanfile`;
  `render-doc.py` also renders the GPLv3 LICENSE verbatim.

## 1.50

A large release: per-site access control and a rewritten device-table editor.

* **Per-site device access** -- devices carry a `site=` tag; site codes live in
  new `sites` / `user_sites` tables and users are assigned one or more. A
  site-limited user sees and edits only their own devices (Devices / Status /
  Reports filtered, direct URLs guarded, saves merged into the full table
  server-side); admins manage codes and assignments. (Run
  `fetchconfig-web-dbupdate.sql`; all users start unrestricted.)
* **Device-table editor rewritten for large tables** -- devices show as collapsed
  summary rows and the editable card is fetched on demand (`edit_card`);
  unexpanded devices round-trip verbatim. For ~2500 devices the page drops from
  ~9.5 MB to ~1 MB. Writes take an exclusive flock and re-check a
  hires-mtime + size + content-digest staleness token under it.
* **Generic template model** -- `model=generic` with a template drop-down, a
  read-only **Template viewer** and a split-view **Template editor** (syntax
  check, single `.bak`, revert); template writes go through a privileged helper
  (`TEMPLATE_HELPER`, sudo). A **directory allow-list** (`directory:` lines) turns
  the repository / template / report / fetch_run fields into drop-downs of allowed
  aliases, and a table using a non-listed directory is refused.
* **Reports page** -- lists the HTML change-reports fetchconfig writes into
  `report_dir` (View / Download / Delete / prune older than N days); all access
  goes through the login.
* New config keys **`HELP_BASE_URL`**, **`FONT_BASE_URL`**, **`IMAGE_BASE_URL`**,
  **`TEMPLATE_HELPER`**, **`SHOW_RENDER_TIME`**, **`HTTPS_ENABLED`** and
  **`SESSION_MAX_LIFETIME`** (an absolute session cap).
* **UI** -- application-style drop-down menus (one page per tool / user action),
  the green/blue section-box layout with a 900px minimum, an **About** dialog, a
  report-logo drop-down and upload tool, session rotation on password change, and
  a throttled sweep of expired session files.
* A device-table save is validated by fetchconfig (`-t` and `--list-allowed-dirs`)
  before it is written; new **INSTALL.md**.

## 1.15
* After logging in, an unauthenticated user who opened a specific page URL
  (e.g. ?action=report) is returned to that page instead of always landing on
  Devices. Only a whitelist of read-only landing actions is honoured (no
  open redirect, no state-changing action).
* The Status page table is wrapped in the same green "tool-section" box as the
  Tools pages, for a consistent look.
* The template viewer (Tools) and the new Reports page use the backup-table
  style: the green "tool-section" box with a bordered list and View/Edit/
  Download/Delete as buttons.
* New "Reports" page (top menu, between Status and Setup): lists the HTML
  change-reports fetchconfig writes into the email: report_dir, newest first,
  with styled table and button actions; View (collapsible per-device diffs,
  parsed and escaped, Expand/Collapse
  all), Download (streamed as an attachment through the CGI), Delete, and a
  "delete reports older than N days" prune. All file access goes through the
  login since the web server cannot read the report directory directly.
* Removed the per-device "Check backup suffixes" button from the backups page;
  the Tools page "Check devices for consistent backup suffixes" covers this.
* New template-driven "generic" model: a device selects model=generic and a
  model=<template> option, with model= rendered as a drop-down of the templates
  fetchconfig reports. Adopts fetchconfig's tab-separated --list-allowed-dirs /
  -t output and its exit codes (a missing directory blocks the editor and
  viewer with the fetchconfig output; "stay" is highlighted as a transition).
* Tools: "Template viewer" lists the generic-model templates read-only with
  syntax highlighting, and "Template editor" edits them in a split view with a
  syntax check, single .tmpl.bak backup, revert, and unsaved-changes guard.
  Template writes go through a new privileged helper
  (fetchconfig-web-install-template.pl, run via sudo, configured by
  TEMPLATE_HELPER); non-regular files (symlinks, hard links) are refused.
* Directory allow-list: the device table may carry "directory:" lines
  (repository / template / fetch_run / report, each $ALIAS + path), read
  server-side from
  the table so they cannot be forged and written back verbatim, armored with
  "must be edited on the server" comments (shown red in the Setup view). When
  present, the editor's repository=, template_dir= and on_fetch_run fields
  become drop-downs of the allowed aliases (expanded path shown in gray;
  on_fetch_run splits into a directory + a command field), saved lines store the
  $ALIAS, and a table using a directory not on the list cannot be saved.
* New config keys FONT_BASE_URL, IMAGE_BASE_URL, HELP_BASE_URL (URL-path bases,
  validated at startup) and TEMPLATE_HELPER; integer config keys now report a
  clear configuration error on an invalid value instead of silently defaulting.
* A device-table save is now validated by fetchconfig (-t and
  --list-allowed-dirs against the exact bytes) before being written, so an
  invalid table never reaches disk; the Bulk edit page runs the same checks.
* Added a Makefile.PL and a t/ unit-test suite (Test::More), plus
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
* New models: "mediant-sbc" (AudioCodes Mediant SBC, Cisco-style CLI;
  user/pass/enable, optional transport=ssh|telnet|auto, adds an enum_transport
  editor field and an AudioCodes-syntax highlighter) and "nexus-ssh" (Cisco
  Nexus / NX-OS over SSH, with a dedicated NX-OS highlighter).
* Tools: run the device scans (without-backups / empty / suffix) in parallel,
  controlled by MAX_PARALLEL_SCAN (1..5, default 1); the progress line shows
  how many scan processes are active.
* Fixed intermittent scan failures by rewriting session files atomically (temp
  file + rename) and hardening child-process I/O (EINTR retry, checked
  waitpid, ASCII-safe JSON); each failed device now shows why.
* Tools: new "Empty Directory Cleanup" (fetchconfig.pl -e / -e -D) and "Check
  devices for consistent backup suffixes" (fetchconfig.pl -s), plus a per-device
  "Check backup suffixes" button; and, under Restore device table, "Delete
  backups older than N days" (always keeps the newest).
* Login page shows a full-page backdrop image (IMAGE_BASE_URL/back.jpg) behind
  the title bar, login box and bottom-centred footer.
* New config keys FONT_BASE_URL and IMAGE_BASE_URL (URL-path bases for fonts
  and images).
* Config: the fetchconfig executable is now two keys -- FETCHCONFIG_PATH
  (install dir, also used to find Constants.pm) and FETCHCONFIG_BIN
  (executable name); the old single full-path form is no longer accepted.
* The page footer shows the installed fetchconfig version, and a warning
  banner appears if it is older than the required minimum or cannot be
  determined.
* Device-table editor: numeric time fields show their unit (s / ms); the Email
  tab gained optional "port" and "tls" (off|starttls|ssl) options; the aruba-
  cx-ssh model gained optional prompt_settle_ms.
* Fixed: coriant-8600 no longer wrongly requires an "enable" password.
* Backup-filename parsing tolerates fetchconfig's filename_append_suffix (the
  backup list dates/times stay correct and "Download latest configuration"
  keeps a dotted suffix, else .cfg).
* Empty-backup check also recognises fetchconfig's newer "N zero-byte
  backup(s)" message.
* Security hardening: device ids/usernames reject a leading "-" (central
  valid_id, so an id can't be read as a CLI option); unsalted {SHA} password
  hashes removed ($apr1$/$1$/$5$/$6$/DES kept); session cookie SameSite=Lax;
  uniform 2s delay on failed logins; Backup-Now cleartext temp file auto-removed
  on exit; SESSION_TTL is now an idle timeout; numeric/boolean config keys
  validated with fallback to defaults.
* Licensed under the GNU GPL v3+ (headers in both programs, LICENSE file,
  README section).
* render-doc.py runs on Python 3 and 2.7.
* Documentation reworked (added a "How fetchconfig.pl is invoked" reference
  and a security overview; wider HTML manual).
* APP_VERSION is a built-in constant, overridable by the config.

## 1.11
* Config file default path is now /etc/fetchconfig-web.cfg (was
  /etc/fetchconfig.cfg); rename on upgrade.
* Backup list: new "Download latest configuration" button (newest backup as
  "<Device-ID>-YYMMDD-HHMMSS.cfg", web-binary models as their decoded file).
* New "Status" page (nav, between Devices and Setup): a table of every device's
  last-run status from the per-device .status files -- Device-ID, start/end
  date+time, duration, state and changed, colour-coded, with dropdown filters,
  sorting, paging and a load-time line (N/A when no status file).
* Tools: new "View fetchconfig log" -- opens the scheduled (cron) run's output
  (FETCHCONFIG_LOG) on its own page, split into collapsible per-device sections
  (green ok / red failed, failed expanded), with Expand/Collapse all and a
  LOG_MAX_DEVICES cap (default 1000).
* Backup Now overlay: shows the elapsed runtime (with a "this can take a while"
  note after 10s) and, when a per-device .status file exists (fetchconfig
  >= 9.52), the last run's runtime/state/changed.
* Devices page: statistics panel shows a "Device table load time".
* Device-table editor, Email tab: added the optional "footer" option.
* Fixed: with multiple email: lines the editor wrongly reported from/to/smtp
  missing (the mandatory check now merges all email: lines); and email: values
  are no longer needlessly quoted for spaces (only commas force quoting).
* Button labels made sentence case app-wide (Backup now, Compare selected, ...).

## 1.10
* New device models: "procurve-snmp" (HP ProCurve ProVision incl. 4000M/8000M,
  backed up over SNMP+TFTP -- no user/pass, mandatory "community" secret,
  masked; text backup, no highlighter); "aruba-cx-ssh" (Aruba CX / AOS-CX over
  SSH, no enable, with a dedicated AOS-CX highlighter); "planet-ssh" (PLANET
  managed switches, Cisco-IOS-like, reuses the IOS highlighter);
  "tplink-web-sg105e" and "procurve-web-1700" (web-managed, no CLI: opaque
  uuencoded backups, so Compare/checkboxes are hidden and the view offers a
  Download of the transparently uudecoded binary; procurve-web-1700 makes user
  optional).
* Devices page: added a Hostname column with its own filter (IPv4 sorts numeric,
  then names); the pager gained First/Last buttons (editor Devices tab too); the
  "+ Add model defaults" button adds at the top.
* Fixed UTF-8 handling: backups with non-ASCII characters (e.g. umlauts) are now
  decoded before display (no mojibake), and the Copy button's legacy fallback
  puts UTF-8 text on the clipboard correctly over plain HTTP.

## 1.9
* New device model "zyxel" (user/pass/repository/keep/timeout mandatory; enable,
  show_cmd, debug optional), with a dedicated IOS-like highlighter.

## 1.8
* Device-table editor (Setup -> Edit device table): a structured three-tab
  editor (Devices / Defaults / Email) driven by a per-model option catalog,
  replacing raw-table editing. Masked-secret fields with keep-on-save, per-model
  "+ add option" menus, host validation (IPv4/IPv6/FQDN), duplicate-ID checks, a
  "Preview raw table" step, an mtime concurrency guard, and a timestamped backup
  to $BACKUP_DEVICE_TABLE before each save (table overwritten in place; option
  parsing/serialisation matches fetchconfig exactly). Devices tab paginates at
  100 and has Device-ID/comment filters (cookie-persisted).
* Bulk Edit (Setup, admin only): plain-text editor for the device lines only;
  saving replaces the DEVICES SECTION with all-or-nothing validation, the mtime
  guard and a backup (default:/email: untouched).
* Tools (admins only): "Check for orphaned backups" / "Delete orphaned backups"
  (fetchconfig -o / -o -D); "Devices without backups" and "Check devices for
  empty backups" scans (fetchconfig -l / -z) with a live progress bar and
  Start/Cancel; and "Restore device table" -- list the timestamped backups with
  View / Restore / Delete (Restore backs up first; strict name validation) and
  compare any two configs (unified or side-by-side, newer green / older red,
  quote-aware; passwords masked with a reveal checkbox).
* "admin_function" per-user right (a full admin, like the built-in admin),
  managed from the User page; new users-table column (see README for the upgrade
  SQL).
* Config syntax highlighting on the backup view for cisco-ios / cisco-ios-ssh
  (extensible per-model registry; cosmetic only, same masking/escaping).
* New device model "hirschmann" (user/pass/repository/keep/timeout mandatory;
  enable, show_cmd optional).
* UI: model filter is a dropdown of models in use (cookie-persisted); a live
  "devices filtered" count; floating Top/Bottom nav on long pages; editor action
  buttons moved to the top; User page areas separated into boxes.
* Fixed: "Check devices for empty backups" misparsed the single-device -z output
  and treated -z exit 1 ("empties found") as an error; and the read-only Compare
  form used the wrong enctype.

## 1.7
* Intermediate development version introducing the first structured
  device-table editor; superseded by the consolidated 1.8 above.

## 1.6
* User accounts moved from the htpasswd file to a PostgreSQL database
  (DBI/DBD::Pg). Standalone setup script fetchconfig-web-dbsetup.pl creates
  the database/table, can import existing htpasswd accounts, and can write
  /etc/fetchconfig.cfg. New-password hashing is pure-Perl Apache MD5
  ($apr1$), so the htpasswd binary and its sudo rule are no longer needed.
* Per-user "edit_device_table" right (grantable from the User page) that
  also grants read access to the Setup page.
* Default-password login warning until an account changes away from the
  default password.
* All configuration moved to an external file, /etc/fetchconfig.cfg
  (key = value); only the config-file path, app title, and cookie name stay
  hard-coded.

## 1.5 and earlier
* Login, device list with live filter and sortable Model/Device-ID columns,
  per-device backup list with Date/Time columns, backup content view with
  copy-to-clipboard, unified "Compare" and "Side by Side" diff views,
  "Backup Now" and "Check Empty Backups", the read-only Setup page, in-UI
  user management, and the Help page. CSRF protection and server-side
  session store throughout.

