# fetchconfig-web -- Data Privacy (GDPR)

This document describes how **fetchconfig-web** processes personal data, for the
purpose of the EU General Data Protection Regulation (GDPR). It is written for
the **operator** -- the organisation that installs and runs the software -- who
is the party responsible under the GDPR.

> This document is provided for information and as implementation guidance. It
> is not legal advice. The operator should review it against their own
> circumstances and, where needed, with a qualified data-protection adviser.

## 1. Where the software runs, and who is responsible

fetchconfig-web runs **entirely on the operator's own system** (the operator's
web server and the operator's PostgreSQL database). All data it processes stays
on that system.

- **The author / provider of the software does not operate the software,
  receive, process, or store any user data, and has no access to any
  installation.** The software contains no telemetry and makes no network
  connection to the author or to any third party. There is no "phone home".
- **The operator deploying fetchconfig-web is the sole data controller** within
  the meaning of Art. 4(7) GDPR for all personal data the software processes.
  The operator decides the purposes and means of processing and is responsible
  for fulfilling the controller's obligations (information, lawful basis,
  retention, data-subject rights, security).

The remainder of this document describes what the software does, so the
operator can meet those obligations.

## 2. Personal data the software processes

All of the following is stored only on the operator's own server/database:

### 2.1 User accounts (PostgreSQL `users` table)
- **Username** -- chosen by the administrator who creates the account; may be a
  person's name or a role name.
- **Password hash** -- the password is stored only as a salted one-way hash
  (Apache MD5 `$apr1$`, or the system `crypt()` MD5/SHA-256/SHA-512 schemes).
  The plaintext password is never stored.
- **Authorisation flags** -- edit right, admin function, report-download right,
  and the user's site assignments.

### 2.2 Login sessions (files in `SESSION_DIR`)
Each logged-in session is a file containing the **username**, an expiry
timestamp, a CSRF token, a password-change flag and the login time. Session
files do **not** contain an IP address. They are created on login, slid forward
on activity, and removed on logout, on expiry, or by the periodic sweep (see
`SESSION_TTL` and `SESSION_MAX_LIFETIME`).

### 2.3 Audit log (PostgreSQL `audit_log` table)
The audit log records security- and change-relevant events. Each entry may
contain:
- **Username** of the acting user;
- **IP address** of the request (the web server's `REMOTE_ADDR`);
- a timestamp, the action, the affected object, and for configuration changes
  the field and its old/new values.

The IP address and the username together can identify a natural person, so the
audit log is the most privacy-relevant store. **Secret values** (device
passwords, enable/SNMP secrets) are stored as `***`, never in clear; user
passwords are never written to the audit log in any form.

### 2.4 Device data (fetchconfig device table and backups)
fetchconfig-web reads and edits fetchconfig's device table and configuration
backups. These describe **network infrastructure** (hostnames, addresses,
device credentials) and are generally not personal data; they may incidentally
contain a person's name if the operator has entered one (e.g. in a comment).
Device credentials are displayed masked and are operationally sensitive
regardless of data-protection status.

## 3. Purposes and legal basis

The software exists to let authorised staff manage network-device
configuration backups. For the personal data above, the applicable legal basis
is normally:

- **Art. 6(1)(f) GDPR -- legitimate interests**: operating access control and
  keeping a security/accountability record (who logged in, who changed what)
  are legitimate interests of the operator in running and securing its own
  infrastructure. Logging failed logins and the originating IP address serves
  the legitimate interest of detecting and investigating unauthorised access.
- Where the operator is under a **legal obligation** to keep such records
  (Art. 6(1)(c)), that obligation is an additional basis.

The operator should perform and document the balancing test for the legitimate
interests basis, and inform its users (e.g. staff) as required by Art. 13.

## 4. Retention (storage limitation, Art. 5(1)(e))

- **Session files** expire automatically (idle timeout `SESSION_TTL`; absolute
  cap `SESSION_MAX_LIFETIME`) and are removed; they are not a long-term store.
- **The audit log is append-only and is NOT pruned automatically.** This is
  deliberate: the web application cannot alter or delete audit records (its
  database user has INSERT + SELECT only). The operator must therefore define a
  retention period consistent with its policy and the storage-limitation
  principle, and prune older records with the supplied maintenance script
  `fetchconfig-web-clean-audit.pl` (run by a privileged database role; see that
  script's `-h` and `-s` options). A typical approach is a scheduled job that
  keeps, for example, 365 days.
- **User accounts** persist until an administrator deletes them; deleting a user
  removes the account row and its session/site assignments.

## 5. Data-subject rights

The operator, as controller, must be able to honour the rights in
Art. 15-21 GDPR. In practice:

- **Access / portability** (Art. 15, 20): the data for a given person is their
  `users` row and the `audit_log` rows bearing their username; both are
  retrievable from the database, and the audit viewer can filter by user and
  export CSV.
- **Rectification** (Art. 16): account data can be changed in the user
  management UI.
- **Erasure** (Art. 17): a user account can be deleted. Note that erasure of
  **audit-log** entries can lawfully be **refused or deferred** where retaining
  them is necessary for the establishment, exercise or defence of legal claims
  or for security/accountability (Art. 17(3)); the operator decides this and, if
  erasure is required, prunes with the maintenance script using an appropriate
  retention window.
- **Objection / restriction** (Art. 18, 21): handled organisationally by the
  operator.

## 6. Security of processing (Art. 32)

The software provides, and the operator should keep enabled:
- passwords stored only as salted hashes; a configurable minimum password
  length; a login delay and generic error on failed login to slow brute force;
- session cookies that are `HttpOnly` and `SameSite=Lax`, with the `Secure`
  flag when `HTTPS_ENABLED` is set; session idle timeout and absolute lifetime;
- CSRF protection on all state-changing actions; parameterised SQL; output
  escaping; path-traversal and input validation;
- an **append-only, immutable audit log** (the application cannot modify or
  delete it) with secret values redacted;
- **serving over HTTPS/TLS is strongly recommended** so that credentials and
  the session cookie are encrypted in transit (`HTTPS_ENABLED = 1`).

The operator is responsible for the surrounding measures: TLS termination,
operating-system and database access control, file-system permissions on
`SESSION_DIR` and the backup directories, and database backups.

## 7. Recipients and transfers

The software sends no personal data to the author or to any third party, and
performs no transfer outside the operator's own systems. If the operator
configures e-mail reporting, report e-mails are sent via the operator's own
mail infrastructure to the recipients the operator configures; that is a
processing activity under the operator's control.

## 8. Operator checklist

- [ ] Record the controller identity and contact (and DPO, if one is required).
- [ ] Document the legitimate-interests balancing test (Section 3).
- [ ] Inform users (Art. 13) that access and changes are logged, including IP.
- [ ] Set and enforce an audit-log retention period (Section 4).
- [ ] Enable HTTPS and set `HTTPS_ENABLED = 1`.
- [ ] Restrict file-system and database access to the necessary accounts.
