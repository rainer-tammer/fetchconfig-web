#!/usr/bin/perl
# fetchconfig-web - Web interface for the fetchconfig network configuration tool
# Copyright (C) 2026  Rainer Tammer
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://gnu.org>.
#
#
# fetchconfig-web-dbsetup.pl
#
# One-off setup helper for the fetchconfig-web user database on PostgreSQL.
#
# It can (each step is a Y/N prompt, so you can re-run it safely and skip
# whatever is already done):
#
#   1. Create the application database (default name: fetchconfig), using a
#      PostgreSQL *maintenance* login (typically the "postgres" superuser),
#      owned by the application DB user.
#   2. Create the "users" table in that database.
#   3. Import existing accounts from an htpasswd-format file
#      (/www/passwd/fetchconfig) -- password hashes are copied verbatim, so
#      everyone's current password keeps working.
#   4. Ensure an "admin" account exists: if none was imported, create
#      "admin" with the password "fetchconfig" (fetchconfig-web then nags
#      to change it on login until it's changed).
#
# Requires the DBI and DBD::Pg Perl modules. Written for PostgreSQL 9.2+
# (no features newer than 9.2 are used).
#
# The connection settings are asked for interactively rather than being
# hard-coded, since this script needs two different logins (the maintenance
# login to create the database, and the application login that
# fetchconfig-web itself will use). Point fetchconfig-web.cgi at the same
# database by setting its $DBinst / $DBuser / $DBpass / $DBhost to match the
# application login used here.

use strict;
use warnings;
use DBI;
use Digest::MD5 ();
use FindBin;

# -------------------------------------------------------------------------
# Fixed settings
# -------------------------------------------------------------------------

my $DEFAULT_DBNAME   = 'fetchconfig';        # application database name
my $MAINT_DBNAME     = 'postgres';           # maintenance DB to connect to for CREATE DATABASE
my $HTPASSWD_FILE    = '/www/passwd/fetchconfig';
my $BOOTSTRAP_USER   = 'admin';
my $BOOTSTRAP_PASS   = 'fetchconfig';

# =========================================================================
# Small interactive helpers
# =========================================================================

sub prompt {
    my ($label, $default) = @_;
    my $suffix = defined $default && $default ne '' ? " [$default]" : '';
    print "$label$suffix: ";
    my $ans = <STDIN>;
    return defined $default ? $default : '' unless defined $ans;
    chomp $ans;
    $ans =~ s/^\s+|\s+$//g;
    $ans = $default if $ans eq '' && defined $default;
    return $ans;
}

# Prompt without echoing (for passwords). Falls back to a visible prompt if
# stty isn't available (e.g. a non-tty); the fallback still works, it just
# shows the typed characters.
sub prompt_secret {
    my ($label) = @_;
    print "$label: ";
    my $noecho = system('stty -echo 2>/dev/null') == 0;
    my $ans = <STDIN>;
    if ($noecho) {
        system('stty echo 2>/dev/null');
        print "\n";
    }
    $ans = '' unless defined $ans;
    chomp $ans;
    return $ans;
}

sub yesno {
    my ($question, $default_yes) = @_;
    my $hint = $default_yes ? '[Y/n]' : '[y/N]';
    while (1) {
        print "$question $hint: ";
        my $ans = <STDIN>;
        return $default_yes ? 1 : 0 unless defined $ans;   # EOF -> default
        chomp $ans;
        $ans =~ s/^\s+|\s+$//g;
        return $default_yes ? 1 : 0 if $ans eq '';
        return 1 if $ans =~ /^y(es)?$/i;
        return 0 if $ans =~ /^n(o)?$/i;
        print "Please answer y or n.\n";
    }
}

sub die_clean {
    my ($msg) = @_;
    print STDERR "\nERROR: $msg\n";
    exit 1;
}

# =========================================================================
# Password hashing -- pure-Perl Apache MD5 ($apr1$), same routine
# fetchconfig-web.cgi uses, so hashes are interchangeable.
# =========================================================================

sub random_salt {
    my @itoa64 = ('.', '/', 0 .. 9, 'A' .. 'Z', 'a' .. 'z');
    my $salt = '';
    # /dev/urandom where available, else rand() -- salt secrecy isn't required.
    my $bytes;
    if (open(my $rf, '<:raw', '/dev/urandom')) {
        read($rf, $bytes, 8);
        close($rf);
    } else {
        $bytes = join('', map { chr(int(rand(256))) } 1 .. 8);
    }
    $salt .= $itoa64[ ord(substr($bytes, $_, 1)) & 0x3f ] for 0 .. 7;
    return $salt;
}

sub apr1_hash {
    my ($password) = @_;
    my $magic = '$apr1$';
    my $salt  = random_salt();
    return md5_crypt($password, "$magic$salt\$", $magic);
}

# Pure-Perl MD5-crypt (PHK). Identical algorithm for $1$ and $apr1$; only
# the magic string differs. Kept byte-for-byte in sync with the copy in
# fetchconfig-web.cgi.
sub md5_crypt {
    my ($password, $existing_hash, $magic) = @_;

    my $salt = $existing_hash;
    $salt =~ s/^\Q$magic\E//;
    $salt =~ s/\$.*$//;
    $salt = substr($salt, 0, 8);

    my $ctx1 = Digest::MD5->new;
    $ctx1->add($password);
    $ctx1->add($magic);
    $ctx1->add($salt);

    my $ctx2 = Digest::MD5->new;
    $ctx2->add($password);
    $ctx2->add($salt);
    $ctx2->add($password);
    my $final = $ctx2->digest;

    my $pwlen = length($password);
    my $i = $pwlen;
    while ($i > 0) {
        $ctx1->add(substr($final, 0, $i > 16 ? 16 : $i));
        $i -= 16;
    }

    $i = $pwlen;
    while ($i) {
        if ($i & 1) { $ctx1->add("\0"); }
        else        { $ctx1->add(substr($password, 0, 1)); }
        $i >>= 1;
    }

    $final = $ctx1->digest;

    for my $round (0 .. 999) {
        my $ctx3 = Digest::MD5->new;
        $ctx3->add($round & 1 ? $password : $final);
        $ctx3->add($salt)     if ($round % 3);
        $ctx3->add($password) if ($round % 7);
        $ctx3->add($round & 1 ? $final : $password);
        $final = $ctx3->digest;
    }

    my @itoa64 = ('.', '/', 0 .. 9, 'A' .. 'Z', 'a' .. 'z');
    my @f = unpack('C16', $final);
    my $result = '';
    for my $g ([0, 6, 12], [1, 7, 13], [2, 8, 14], [3, 9, 15], [4, 10, 5]) {
        my $v = ($f[$g->[0]] << 16) | ($f[$g->[1]] << 8) | $f[$g->[2]];
        for (1 .. 4) { $result .= $itoa64[$v & 0x3f]; $v >>= 6; }
    }
    my $v = $f[11];
    for (1 .. 2) { $result .= $itoa64[$v & 0x3f]; $v >>= 6; }

    return "$magic$salt\$$result";
}

# =========================================================================
# htpasswd import
# =========================================================================

sub read_htpasswd {
    my ($file) = @_;
    my %creds;
    open(my $fh, '<', $file) or return undef;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
        my ($u, $h) = split(/:/, $line, 2);
        next unless defined $u && defined $h && $u ne '';
        $creds{$u} = $h;
    }
    close($fh);
    return \%creds;
}

# =========================================================================
# Main
# =========================================================================

# =========================================================================
# Dashboard history schema -- "--upgrade" mode
# =========================================================================
# Creates/upgrades the Backup Dashboard history schema (schema_migrations +
# backup_current / backup_runs / backup_versions), the writer role, and the
# grants. Connection parameters come from the existing fetchconfig-web config
# (so you do not retype them); you are prompted only for a DB superuser (to run
# DDL / CREATE ROLE / GRANT) and the writer user name. 8.2-safe, idempotent.

my $CFG_PATH = '/etc/fetchconfig-web.cfg';   # default; -f overrides (arg handling below)

# Every versioned dbupdate this release knows, OLDEST FIRST. Each entry:
#   [ id, sql-file, signature-check ]
# --upgrade applies, in order, every id not already in schema_migrations: if its
# signature is already present (applied by hand before the ledger existed) it is
# just recorded; otherwise the .sql is applied via DBI (run_sql_file_dbi -- no
# external psql, no binary dependency) and then recorded. Append a line per
# new release.
my @UPDATES = (
    [ '1.50', 'fetchconfig-web-dbupdate-1.50.sql', sub { tbl_exists($_[0], 'sites') } ],
    [ '1.51', 'fetchconfig-web-dbupdate-1.51.sql', sub { tbl_exists($_[0], 'audit_log') } ],
    [ '1.60', 'fetchconfig-web-dbupdate-1.60.sql', sub { tbl_exists($_[0], 'login_attempts') } ],
    [ '1.62', 'fetchconfig-web-dbupdate-1.62.sql', sub { tbl_exists($_[0], 'device_notes') } ],
    [ '2.08', 'fetchconfig-web-dbupdate-2.08.sql', sub { col_exists($_[0], 'users', 'read_debug') } ],
    [ '2.11', 'fetchconfig-web-dbupdate-2.11.sql', sub { tbl_exists($_[0], 'backup_current') } ],
);

sub tbl_exists {
    my ($dbh, $t) = @_;
    my ($x) = $dbh->selectrow_array(
        q{SELECT 1 FROM information_schema.tables
           WHERE table_schema = 'public' AND table_name = ?}, undef, $t);
    return $x;
}

sub col_exists {
    my ($dbh, $t, $c) = @_;
    my ($x) = $dbh->selectrow_array(
        q{SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = ? AND column_name = ?},
        undef, $t, $c);
    return $x;
}

sub migration_applied {
    my ($dbh, $id) = @_;
    my ($x) = $dbh->selectrow_array(
        'SELECT 1 FROM schema_migrations WHERE id = ?', undef, $id);
    return $x;
}

sub record_migration {
    my ($dbh, $id) = @_;
    # idempotent (8.2-safe: no ON CONFLICT)
    $dbh->do(q{INSERT INTO schema_migrations (id, applied_at)
               SELECT ?, ? WHERE NOT EXISTS
                   (SELECT 1 FROM schema_migrations WHERE id = ?)},
             undef, $id, time(), $id);
}

sub ensure_ledger {
    my ($dbh) = @_;
    return if tbl_exists($dbh, 'schema_migrations');
    $dbh->do(q{CREATE TABLE schema_migrations (id TEXT PRIMARY KEY, applied_at BIGINT)})
        or die_clean("CREATE TABLE schema_migrations failed: " . $dbh->errstr);
    print "Created schema_migrations ledger.\n";
}

# Apply a dbupdate .sql file via DBI -- NO external psql, no binary dependency.
# Strips psql backslash meta-command lines (\set ...), runs any "CREATE LANGUAGE
# plpgsql" on its own (tolerating "already exists"), then executes the rest (the
# script's own BEGIN;...COMMIT; with the idempotent PL/pgSQL temp function) as a
# single multi-statement do() -- with no placeholders, DBD::Pg uses PQexec, which
# runs several statements and handles $tag$ dollar-quoting server-side. The .sql
# files are 8.2-safe and self-record in schema_migrations.
sub run_sql_file_dbi {
    my ($dbh, $file) = @_;
    my $path = "$FindBin::Bin/$file";
    open(my $fh, '<', $path) or die_clean("update script not found: $path ($!)");
    local $/; my $sql = <$fh>; close $fh;
    # Drop psql meta-command lines (\set ON_ERROR_STOP ..., etc.).
    $sql =~ s/^[ \t]*\\[^\n]*\n?//mg;
    # CREATE LANGUAGE plpgsql on its own; tolerate "already exists" (PG >= 9.0
    # ships it; 8.2 may need it). RaiseError is off, so a failure here is harmless
    # and does not poison the connection (AutoCommit = 1).
    while ($sql =~ s/^[ \t]*CREATE\s+LANGUAGE\s+plpgsql\s*;//im) {
        $dbh->do('CREATE LANGUAGE plpgsql');
    }
    return unless $sql =~ /\S/;
    $dbh->do($sql)
        or die_clean("applying $file via DBI failed: " . ($dbh->errstr // 'unknown'));
}

# Read key=value settings from the fetchconfig-web config file.
sub read_cfg {
    my ($path) = @_;
    open(my $fh, '<', $path)
        or die_clean("cannot read config $path: $! (use -f <path> to point elsewhere)");
    my %cfg;
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+//;
        next if $line eq '' || $line =~ /^#/;
        my ($k, $v) = split(/=/, $line, 2);
        next unless defined $k && defined $v;
        $k =~ s/\s+$//; $v =~ s/^\s+//; $v =~ s/\s+$//;
        $cfg{$k} = $v;
    }
    close($fh);
    return \%cfg;
}

# Connect as a DB superuser/CREATEROLE account, with a (r)e-enter/(a)bort loop
# on failure (bad login, or connected but lacking the privilege to migrate).
sub connect_super {
    my ($dsn, $dbname, $dbhost) = @_;
    while (1) {
        print "\n-- DB superuser login (to run DDL, CREATE ROLE, GRANT) --\n";
        my $user = prompt('DB superuser name', 'postgres');
        my $pass = prompt_secret('DB superuser password');
        my $dbh  = DBI->connect($dsn, $user, $pass,
            { RaiseError => 0, PrintError => 0, AutoCommit => 1 });
        if (!$dbh) {
            print "  Connection failed: " . ($DBI::errstr // 'unknown') . "\n";
        }
        else {
            my ($super, $createrole) = $dbh->selectrow_array(
                'SELECT rolsuper, rolcreaterole FROM pg_roles WHERE rolname = current_user');
            if ($super || $createrole) { return ($dbh, $user, $pass); }
            print "  Role \"$user\" lacks SUPERUSER / CREATEROLE -- cannot create the writer role or grant.\n";
            $dbh->disconnect;
        }
        my $c = prompt('(r)e-enter / (a)bort', 'r');
        die_clean("aborted by user.") if $c =~ /^a/i;
    }
}

sub do_grants {
    my ($dbh, $webuser, $writer, $writerpass, $writer_exists) = @_;
    if (!$writer_exists) {
        my $q  = $dbh->quote_identifier($writer);
        my $qp = $writerpass; $qp =~ s/'/''/g;
        $dbh->do(qq{CREATE ROLE $q LOGIN PASSWORD '$qp'})
            or die_clean("CREATE ROLE failed: " . $dbh->errstr);
        print "Created writer role \"$writer\".\n";
    }
    else {
        print "Writer role \"$writer\" already exists -- leaving it (grants refreshed).\n";
    }
    my $qw = $dbh->quote_identifier($writer);
    my $qu = $dbh->quote_identifier($webuser);
    # Ownership: the history tables are owned by the writer role (the fetchconfig
    # engine), so the engine can maintain its own data -- including the future
    # cleanup DELETE -- without a superuser, while the web user stays SELECT-only.
    # (The writer owning them is why the GRANTs below are, for the writer,
    # belt-and-suspenders.) The migration ledger schema_migrations is deliberately
    # left owned by the superuser that runs --upgrade: neither the web app nor the
    # writer should be able to alter the record of which migrations ran. Future
    # schema changes run as the superuser here, which can ALTER regardless of owner.
    for my $t (qw(backup_current backup_runs backup_versions)) {
        next unless tbl_exists($dbh, $t);
        $dbh->do("ALTER TABLE $t OWNER TO $qw")
            or die_clean("ALTER TABLE $t OWNER TO failed: " . $dbh->errstr);
    }
    print "Owner: backup_current/backup_runs/backup_versions -> \"$writer\".\n";
    # Web (read) user: SELECT only.
    $dbh->do("GRANT SELECT ON backup_current, backup_runs, backup_versions TO $qu");
    # Writer: SELECT + INSERT on all three (SELECT is required by the pre-9.5
    # DML), UPDATE on backup_current, UPDATE(expired, expired_at) on backup_versions.
    $dbh->do("GRANT SELECT, INSERT ON backup_current, backup_runs, backup_versions TO $qw");
    $dbh->do("GRANT UPDATE ON backup_current TO $qw");
    $dbh->do("GRANT UPDATE (expired, expired_at) ON backup_versions TO $qw");
    print "Granted: web user \"$webuser\" SELECT; writer \"$writer\" SELECT+INSERT+UPDATE.\n";
}

sub do_upgrade {
    print "=" x 70, "\n";
    print "fetchconfig-web -- Dashboard history schema upgrade\n";
    print "=" x 70, "\n\n";

    my $cfg     = read_cfg($CFG_PATH);
    my $dbname  = $cfg->{DBinst} or die_clean("DBinst not found in $CFG_PATH");
    my $webuser = $cfg->{DBuser} or die_clean("DBuser not found in $CFG_PATH");
    my $dbhost  = $cfg->{DBhost} // 'localhost';
    print "Config $CFG_PATH: database=$dbname host=$dbhost web user=$webuser\n";

    my $dsn = "dbi:Pg:dbname=$dbname;host=$dbhost";
    my ($dbh) = connect_super($dsn, $dbname, $dbhost);

    ensure_ledger($dbh);

    # Apply every pending versioned update, oldest first (older .sql scripts
    # included), bringing any prior DB fully up to date.
    for my $u (@UPDATES) {
        my ($id, $file, $sig) = @$u;
        if (migration_applied($dbh, $id)) { print "Migration $id: already applied.\n"; next; }
        if ($sig->($dbh)) {
            record_migration($dbh, $id);
            print "Migration $id: already present -- recorded in ledger.\n";
            next;
        }
        print "Applying migration $id ($file) ...\n";
        run_sql_file_dbi($dbh, $file);                                   # via DBI, no external psql
        record_migration($dbh, $id);
        print "  done.\n";
    }

    # Writer role: reuse the name recorded on a previous --upgrade (app_state),
    # so the operator is asked for it only the first time.
    my $writer;
    if (tbl_exists($dbh, 'app_state')) {
        ($writer) = $dbh->selectrow_array(
            q{SELECT value FROM app_state WHERE key = 'dashboard_writer'});
    }
    if (defined $writer && $writer ne '') {
        print "\nWriter role: using \"$writer\" (recorded by a previous --upgrade).\n";
    }
    else {
        print "\n-- Writer role (the fetchconfig engine's db: db_user) --\n";
        $writer = prompt('fetchconfig writer DB user', 'fetchconfig_dashboard');
        die_clean("writer user name is required.") if $writer eq '';
        if ($writer !~ /^[A-Za-z_][A-Za-z0-9_]*\z/) {
            print "WARNING: \"$writer\" contains non-ASCII or SQL-unsafe characters; it will be\n";
            print "         double-quoted as an identifier everywhere. The default\n";
            print "         fetchconfig_dashboard avoids quoting.\n";
        }
        if ($writer eq $webuser) {
            print "WARNING: the writer equals the fetchconfig-web DB user (\"$webuser\"); the\n";
            print "         least-privilege separation is lost -- the web role would also gain\n";
            print "         INSERT/UPDATE on the history tables.\n";
        }
    }
    my ($writer_exists) = $dbh->selectrow_array(
        'SELECT 1 FROM pg_roles WHERE rolname = ?', undef, $writer);
    my $writerpass;
    if (!$writer_exists) {
        $writerpass = prompt_secret("Password for new writer role \"$writer\"");
        die_clean("writer password is required to create the role.") if $writerpass eq '';
    }
    do_grants($dbh, $webuser, $writer, $writerpass, $writer_exists);

    # Record the chosen writer name so the dashboard's "tables empty" info panel
    # can print the exact db: string (the web app otherwise cannot know which
    # role name was chosen here). Pre-9.5 upsert (UPDATE then INSERT).
    if (tbl_exists($dbh, 'app_state')) {
        my $rows = $dbh->do(q{UPDATE app_state SET value = ?, ts = now() WHERE key = 'dashboard_writer'},
                            undef, $writer);
        if (!$rows || $rows == 0) {
            $dbh->do(q{INSERT INTO app_state (key, value, ts) VALUES ('dashboard_writer', ?, now())},
                     undef, $writer);
        }
        print "Recorded writer name in app_state (for the dashboard info panel).\n";
    }

    $dbh->disconnect;

    print "\n", "=" x 70, "\n";
    print "Done. Next:\n";
    print "  1. Set ENABLE_DASHBOARD = 1 in $CFG_PATH\n";
    print "  2. Configure the fetchconfig engine (device_table default: line):\n";
    print "       db: db_inst=$dbname,db_user=$writer,db_pass=<writer password>,db_host=$dbhost\n";
    print "=" x 70, "\n";
}

# -------------------------------------------------------------------------
# Argument handling
# -------------------------------------------------------------------------
my $UPGRADE  = 0;
{
    my @args = @ARGV;
    while (@args) {
        my $a = shift @args;
        if    ($a eq '--upgrade')              { $UPGRADE = 1; }
        elsif ($a eq '-f' || $a eq '--config') { $CFG_PATH = shift @args // die_clean("$a needs a path argument"); }
        else  { die_clean("unknown argument: $a (usage: $0 [--upgrade] [-f <config>])"); }
    }
}

if ($UPGRADE) { do_upgrade(); exit 0; }

print "=" x 70, "\n";
print "fetchconfig-web -- PostgreSQL user database setup\n";
print "=" x 70, "\n\n";

my $dbname = prompt('Application database name', $DEFAULT_DBNAME);
die_clean("Database name must be a plain identifier (letters, digits, _).")
    unless $dbname =~ /^[A-Za-z_][A-Za-z0-9_]*$/;

my $dbhost = prompt('PostgreSQL host', 'localhost');

# --- Step 1: create the application database (optional) -------------------

if (yesno("\nCreate the application database \"$dbname\" now?", 0)) {
    print "\n-- Maintenance login (to run CREATE DATABASE; e.g. the postgres superuser) --\n";
    my $maint_db   = prompt('Maintenance database', $MAINT_DBNAME);
    my $maint_user = prompt('Maintenance DB user', 'postgres');
    my $maint_pass = prompt_secret('Maintenance DB password');

    print "\n-- Application login (the account fetchconfig-web.cgi will use) --\n";
    my $app_user = prompt('Application DB user');
    my $app_pass = prompt_secret('Application DB password');
    die_clean("Application DB user is required.") if $app_user eq '';

    my $maint_dsn = "dbi:Pg:dbname=$maint_db;host=$dbhost";
    print "\nConnecting to maintenance database $maint_db on $dbhost ...\n";
    my $mdbh = DBI->connect($maint_dsn, $maint_user, $maint_pass,
        { RaiseError => 0, PrintError => 0, AutoCommit => 1 })
        or die_clean("Cannot connect to maintenance DB: " . ($DBI::errstr // 'unknown'));

    # Does the role exist? Create it if not (so the app login works).
    my ($role_exists) = $mdbh->selectrow_array(
        'SELECT 1 FROM pg_roles WHERE rolname = ?', undef, $app_user);
    if (!$role_exists) {
        if (yesno("Application role \"$app_user\" does not exist. Create it?", 1)) {
            my $q_user = $app_user; $q_user =~ s/"/""/g;
            my $q_pass = $app_pass; $q_pass =~ s/'/''/g;
            $mdbh->do(qq{CREATE ROLE "$q_user" LOGIN PASSWORD '$q_pass'})
                or die_clean("CREATE ROLE failed: " . $mdbh->errstr);
            print "Created role \"$app_user\".\n";
        }
    }

    # Create the database, owned by the app user. Identifier is validated
    # above, so quoting it is safe.
    my ($db_exists) = $mdbh->selectrow_array(
        'SELECT 1 FROM pg_database WHERE datname = ?', undef, $dbname);
    if ($db_exists) {
        print "Database \"$dbname\" already exists -- skipping CREATE DATABASE.\n";
    } else {
        my $q_owner = $app_user; $q_owner =~ s/"/""/g;
        $mdbh->do(qq{CREATE DATABASE "$dbname" OWNER "$q_owner"})
            or die_clean("CREATE DATABASE failed: " . $mdbh->errstr);
        print "Created database \"$dbname\" owned by \"$app_user\".\n";
    }
    $mdbh->disconnect;
}

# --- Application login for the remaining steps ----------------------------

print "\n-- Connect to \"$dbname\" as the application DB user --\n";
my $app_user2 = prompt('Application DB user');
my $app_pass2 = prompt_secret('Application DB password');
die_clean("Application DB user is required.") if $app_user2 eq '';

my $app_dsn = "dbi:Pg:dbname=$dbname;host=$dbhost";
print "\nConnecting to $dbname on $dbhost as $app_user2 ...\n";
my $dbh = DBI->connect($app_dsn, $app_user2, $app_pass2,
    { RaiseError => 0, PrintError => 0, AutoCommit => 1 })
    or die_clean("Cannot connect to application DB: " . ($DBI::errstr // 'unknown'));

# --- Step 2: create the users table --------------------------------------

my ($table_exists) = $dbh->selectrow_array(
    q{SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'users'});

if ($table_exists) {
    print "\nTable \"users\" already exists -- leaving it as-is.\n";
} elsif (yesno(qq{\nCreate the "users" table in "$dbname" now?}, 1)) {
    # PostgreSQL 9.2-compatible DDL: no IF NOT EXISTS on columns, no
    # generated identity, plain BOOLEAN default.
    $dbh->do(q{
        CREATE TABLE users (
            username             TEXT     PRIMARY KEY,
            pass_hash            TEXT     NOT NULL,
            edit_device_table    BOOLEAN  NOT NULL DEFAULT FALSE,
            admin_function       BOOLEAN  NOT NULL DEFAULT FALSE,
            download_full_report BOOLEAN  NOT NULL DEFAULT FALSE,
            download_full_config BOOLEAN  NOT NULL DEFAULT FALSE,
            read_debug           BOOLEAN  NOT NULL DEFAULT FALSE,
            email                TEXT
        )
    }) or die_clean("CREATE TABLE failed: " . $dbh->errstr);
    print "Created table \"users\".\n";
}

# --- Step 2b: per-site access tables (v1.50) -----------------------------
# "sites" holds the site/location codes; id 0 is the reserved "All sites"
# sentinel. "user_sites" maps users to the sites they may access; a user who
# holds site 0 is unrestricted.
my ($sites_exists) = $dbh->selectrow_array(
    q{SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'sites'});
if ($sites_exists) {
    print "Table \"sites\" already exists -- leaving it as-is.\n";
} else {
    $dbh->do(q{
        CREATE TABLE sites (
            id           INTEGER  PRIMARY KEY,
            code         TEXT     NOT NULL UNIQUE,
            description  TEXT     NOT NULL DEFAULT ''
        )
    }) or die_clean("CREATE TABLE sites failed: " . $dbh->errstr);
    $dbh->do(q{INSERT INTO sites (id, code, description) VALUES (0, '*', 'All sites')})
        or die_clean("seed sites failed: " . $dbh->errstr);
    # 8.2-compatible: plain CREATE (reached only right after the sites table was
    # just created, so the sequence does not exist yet).
    $dbh->do(q{CREATE SEQUENCE sites_id_seq START WITH 1 MINVALUE 1});
    print "Created table \"sites\" (seeded id 0 = All sites).\n";
}
my ($usites_exists) = $dbh->selectrow_array(
    q{SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'user_sites'});
if ($usites_exists) {
    print "Table \"user_sites\" already exists -- leaving it as-is.\n";
} else {
    $dbh->do(q{
        CREATE TABLE user_sites (
            username  TEXT     NOT NULL REFERENCES users(username) ON DELETE CASCADE,
            site_id   INTEGER  NOT NULL REFERENCES sites(id)       ON DELETE RESTRICT,
            PRIMARY KEY (username, site_id)
        )
    }) or die_clean("CREATE TABLE user_sites failed: " . $dbh->errstr);
    print "Created table \"user_sites\".\n";
}

# Grant the application DB user the privileges it needs on the site tables and
# sequence. When this script creates them it connects AS that user, so it is
# already the owner and these grants are a harmless no-op; they are issued
# explicitly so the schema works the same way regardless of who owns the
# objects (e.g. if the tables were created by a different role).
{
    my $q_user = $dbh->quote_identifier($app_user2);
    for my $stmt (
        "GRANT SELECT, INSERT, UPDATE, DELETE ON sites TO $q_user",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON user_sites TO $q_user",
        "GRANT USAGE, SELECT, UPDATE ON SEQUENCE sites_id_seq TO $q_user",
    ) {
        $dbh->do($stmt);   # best effort; ignore if already granted / owner
    }
    print "Granted \"$app_user2\" access to the site tables.\n";
}

# --- Step 2c: audit log (v1.51) ------------------------------------------
# "audit_log" is an append-only record of state-changing actions. The app DB
# user is granted INSERT + SELECT only (no UPDATE/DELETE), so it can write and
# read the log but never alter or erase it -- only a DBA can. "app_state" is a
# small mutable key/value table used e.g. for the device-table change tripwire.
my ($audit_exists) = $dbh->selectrow_array(
    q{SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'audit_log'});
if ($audit_exists) {
    print "Table \"audit_log\" already exists -- leaving it as-is.\n";
} else {
    # 8.2-compatible DDL (explicit sequence; no bigserial shorthand/DO blocks).
    $dbh->do(q{CREATE SEQUENCE audit_log_id_seq START WITH 1 MINVALUE 1})
        or die_clean("CREATE SEQUENCE audit_log_id_seq failed: " . $dbh->errstr);
    $dbh->do(q{
        CREATE TABLE audit_log (
            id           BIGINT      NOT NULL PRIMARY KEY
                                     DEFAULT nextval('audit_log_id_seq'),
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
        )
    }) or die_clean("CREATE TABLE audit_log failed: " . $dbh->errstr);
    $dbh->do(q{CREATE INDEX audit_log_ts_idx     ON audit_log (ts)});
    $dbh->do(q{CREATE INDEX audit_log_user_idx   ON audit_log (username)});
    $dbh->do(q{CREATE INDEX audit_log_action_idx ON audit_log (action)});
    $dbh->do(q{CREATE INDEX audit_log_object_idx ON audit_log (object_id)});
    print "Created table \"audit_log\" (append-only).\n";
}
my ($appstate_exists) = $dbh->selectrow_array(
    q{SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'app_state'});
if ($appstate_exists) {
    print "Table \"app_state\" already exists -- leaving it as-is.\n";
} else {
    $dbh->do(q{
        CREATE TABLE app_state (
            key       TEXT        PRIMARY KEY,
            value     TEXT,
            username  TEXT,
            ts        TIMESTAMPTZ
        )
    }) or die_clean("CREATE TABLE app_state failed: " . $dbh->errstr);
    print "Created table \"app_state\".\n";

    # --- v1.60: login throttle + password-reset tokens -------------------
    $dbh->do(q{
        CREATE TABLE login_attempts (
            kind       TEXT        NOT NULL,
            keyval     TEXT        NOT NULL,
            failures   INTEGER     NOT NULL DEFAULT 0,
            last_fail  TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (kind, keyval)
        )
    }) or die_clean("CREATE TABLE login_attempts failed: " . $dbh->errstr);
    $dbh->do(q{CREATE INDEX login_attempts_last_idx ON login_attempts (last_fail)});
    print "Created table \"login_attempts\".\n";

    $dbh->do(q{
        CREATE TABLE password_resets (
            token_hash TEXT        NOT NULL PRIMARY KEY,
            username   TEXT        NOT NULL,
            created    TIMESTAMPTZ NOT NULL DEFAULT now(),
            expires    TIMESTAMPTZ NOT NULL,
            used       BOOLEAN     NOT NULL DEFAULT FALSE
        )
    }) or die_clean("CREATE TABLE password_resets failed: " . $dbh->errstr);
    $dbh->do(q{CREATE INDEX password_resets_user_idx ON password_resets (username)});
    $dbh->do(q{CREATE INDEX password_resets_exp_idx  ON password_resets (expires)});
    print "Created table \"password_resets\".\n";

    # --- v1.62: per-device notes -----------------------------------------
    $dbh->do(q{CREATE SEQUENCE device_notes_id_seq START WITH 1 MINVALUE 1})
        or die_clean("CREATE SEQUENCE device_notes_id_seq failed: " . $dbh->errstr);
    $dbh->do(q{
        CREATE TABLE device_notes (
            note_id    INTEGER     NOT NULL PRIMARY KEY
                       DEFAULT nextval('device_notes_id_seq'),
            device_id  TEXT        NOT NULL,
            note       TEXT        NOT NULL DEFAULT '',
            keep       BOOLEAN     NOT NULL DEFAULT FALSE,
            created    TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated    TIMESTAMPTZ NOT NULL DEFAULT now()
        )
    }) or die_clean("CREATE TABLE device_notes failed: " . $dbh->errstr);
    $dbh->do(q{CREATE UNIQUE INDEX device_notes_devid_idx   ON device_notes (device_id)});
    $dbh->do(q{CREATE INDEX        device_notes_updated_idx ON device_notes (updated)});
    print "Created table \"device_notes\".\n";
}
{
    my $q_user = $dbh->quote_identifier($app_user2);
    for my $stmt (
        # Level B immutability: INSERT + SELECT only on audit_log (no UPDATE/DELETE).
        "GRANT SELECT, INSERT ON audit_log TO $q_user",
        "GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO $q_user",
        # app_state is mutable (token updates).
        "GRANT SELECT, INSERT, UPDATE ON app_state TO $q_user",
        # v1.60: throttle counters (created/incremented/cleared at run time).
        "GRANT SELECT, INSERT, UPDATE, DELETE ON login_attempts TO $q_user",
        # v1.60: reset tokens (create/look-up/mark-used; pruned by a DBA tool).
        "GRANT SELECT, INSERT, UPDATE ON password_resets TO $q_user",
        # v1.62: device notes (created/edited/deleted at run time).
        "GRANT SELECT, INSERT, UPDATE, DELETE ON device_notes TO $q_user",
        "GRANT USAGE, SELECT ON SEQUENCE device_notes_id_seq TO $q_user",
    ) {
        $dbh->do($stmt);   # best effort; ignore if already granted / owner
    }
    print "Granted \"$app_user2\" audit-log access (INSERT + SELECT only).\n";
}

# --- Step 3: import from htpasswd (optional) -----------------------------

my $imported = 0;
if (-e $HTPASSWD_FILE) {
    my $creds = read_htpasswd($HTPASSWD_FILE);
    my $n = $creds ? scalar(keys %$creds) : 0;
    if ($n && yesno("\nImport $n account(s) from $HTPASSWD_FILE?", 1)) {
        my $ins = $dbh->prepare(
            'INSERT INTO users (username, pass_hash, edit_device_table, admin_function) VALUES (?, ?, ?, ?)');
        my $upd = $dbh->prepare(
            'UPDATE users SET pass_hash = ? WHERE username = ?');
        for my $u (sort keys %$creds) {
            my ($exists) = $dbh->selectrow_array(
                'SELECT 1 FROM users WHERE username = ?', undef, $u);
            if ($exists) {
                if (yesno("  User \"$u\" already in DB -- overwrite its password hash?", 0)) {
                    $upd->execute($creds->{$u}, $u) and print "  updated $u\n";
                } else {
                    print "  skipped $u\n";
                }
            } else {
                # admin behaves as a full admin regardless of these columns,
                # so store the flags to match (TRUE for admin, FALSE for
                # everyone else) rather than leaving admin's row misleadingly
                # showing 'f'.
                my $flag = ($u eq $BOOTSTRAP_USER) ? 1 : 0;
                if ($ins->execute($u, $creds->{$u}, $flag, $flag)) {
                    print "  imported $u\n";
                    $imported++;
                } else {
                    print STDERR "  FAILED to import $u: " . $dbh->errstr . "\n";
                }
            }
        }
    }
} else {
    print "\nNo htpasswd file at $HTPASSWD_FILE -- skipping import.\n";
}

# --- Step 4: ensure an admin account exists ------------------------------

my ($admin_exists) = $dbh->selectrow_array(
    'SELECT 1 FROM users WHERE username = ?', undef, $BOOTSTRAP_USER);
if ($admin_exists) {
    print "\nAccount \"$BOOTSTRAP_USER\" is present -- left untouched.\n";
} else {
    print "\nNo \"$BOOTSTRAP_USER\" account found.\n";
    my $hash = apr1_hash($BOOTSTRAP_PASS);
    $dbh->do('INSERT INTO users (username, pass_hash, edit_device_table, admin_function) VALUES (?, ?, TRUE, TRUE)',
             undef, $BOOTSTRAP_USER, $hash)
        or die_clean("Failed to create bootstrap admin: " . $dbh->errstr);
    print "Created \"$BOOTSTRAP_USER\" with the default password \"$BOOTSTRAP_PASS\".\n";
    print "  --> Log in and change it immediately; fetchconfig-web will warn until you do.\n";
}

# --- Step 4b: start every user unrestricted (site 0) ---------------------
# So nobody is locked out after enabling per-site access; administrators then
# tighten assignments on the User page. admin always keeps site 0.
$dbh->do(q{INSERT INTO user_sites (username, site_id)
           SELECT username, 0 FROM users
           WHERE NOT EXISTS (SELECT 1 FROM user_sites us
                             WHERE us.username = users.username AND us.site_id = 0)})
    or warn "Note: could not seed user_sites: " . $dbh->errstr . "\n";

$dbh->disconnect;

# --- Step 5: write the fetchconfig-web config file (optional) ----------------
#
# fetchconfig-web.cgi reads all its settings from this file. We fill in the
# database values from what was entered above; the non-DB settings are
# written at their defaults for you to review/adjust. The file holds the DB
# password in clear text, so it is created mode 0600.

# $CFG_PATH is set in the argument-handling block near the top.

sub cfg_body {
    my ($dbname, $dbuser, $dbpass, $dbhost) = @_;
    return <<"CFG";
# $CFG_PATH -- fetchconfig-web configuration (key = value)
# Written by fetchconfig-web-dbsetup.pl. Review the non-database settings
# below and adjust paths to match your installation. Keep this file
# readable only by the web-server user (mode 0600), as it holds the
# database password in clear text.

# --- fetchconfig ---
DEVICE_TABLE            = /usr/local/fetchconfig/device_table
FETCHCONFIG_PATH        = /usr/local/fetchconfig
FETCHCONFIG_BIN         = fetchconfig.pl
# "Last scheduled run" log shown by Tools -> View last fetchconfig schedule log.
FETCHCONFIG_LOG         = /usr/local/fetchconfig/fetchconfig.log
# The system user whose crontab holds the fetchconfig backup job. Used ONLY by
# Tools -> Show schedule (read-only). Uncomment and set to enable that tool; it
# also needs TEMPLATE_HELPER + sudo (same grant as the debug-log reader). Put
# the cron entry in this user's crontab, not root's.
#CRON_USER              = fetchconfig
LOG_MAX_DEVICES         = 1000
MAX_PARALLEL_SCAN       = 1
# Syntax highlighting for template-backed ("generic") devices whose template
# does not declare a syntax_style: auto = detect from content (default),
# none = plain text, or a scheme name (cisco-ios, json, xml, generic, ...).
GENERIC_SYNTAX          = auto

# --- Backup Now / sudo ---
BACKUP_DEVICE_TABLE     = /usr/local/fetchconfig/backup
USE_SUDO_FOR_BACKUP_NOW = 1
SUDO_BIN                = /usr/bin/sudo
# Wall-clock limit (seconds) for a single "Backup Now" run; if a device does not
# respond the run is terminated and the partial output is still shown. 0 = no
# limit. Default 120.
BACKUP_TIMEOUT          = 120
# Max combined (stdout+stderr) bytes captured from a single subprocess, guarding
# worker memory against a runaway child. 0 disables the cap. Default 50 MiB.
CAPTURE_MAX_BYTES       = 52428800
# Privileged helper for the Tools template editor's Save/Revert (run via sudo).
# Leave empty to disable sudo saving (then the template directories must be
# writable by the web-server user). See "Template editor" in README.md.
TEMPLATE_HELPER         = /usr/local/fetchconfig/fetchconfig-web-install-template.pl

# --- web paths ---
# WEB_DIR is the FILESYSTEM directory that holds the static web assets
# (fetchconfig-web.css, fonts, images and the help tree). It is used only for
# on-disk presence checks. BASE_URL is the URL base under which that same
# directory is served by the web server; the browser merges it with the site's
# host name. CSS_BASE_URL / FONT_BASE_URL / IMAGE_BASE_URL / JS_BASE_URL /
# HELP_BASE_URL are the (URL and on-disk) sub-paths under those roots. The stylesheet must exist
# at WEB_DIR + CSS_BASE_URL + /fetchconfig-web.css or every page is unstyled and
# a red "directories not configured" banner is shown.
# JS_BASE_URL holds js/mermaid.min.js (the Template viewer's state-machine
# diagram); the IBM Plex Sans webfont it needs lives under FONT_BASE_URL. Copy
# the release's js/ and fonts/ directories into WEB_DIR to enable the diagram.
# HELP_BASE_URL is the help tree: help.html lives directly in it, and the two
# "additional help" menus are scanned from its fetchconfig-web/ and fetchconfig/
# subdirectories (copy whichever *.html documents you want exposed into those).
WEB_DIR                 = /www/virtual/fetchconfig/htdocs
BASE_URL                = /
CSS_BASE_URL            = /css
FONT_BASE_URL           = /fonts
IMAGE_BASE_URL          = /images
JS_BASE_URL             = /js
HELP_BASE_URL           = /help

# --- sessions ---
SESSION_DIR             = /www/fetchconfig-web/sessions
BACKUP_TMP_DIR          = /www/fetchconfig-web/sessions
# Idle timeout (SESSION_TTL slides on activity); absolute lifetime force-expires
# a session this long after login regardless of activity (0 = idle only).
SESSION_TTL             = 28800
SESSION_MAX_LIFETIME    = 86400

# --- user policy ---
PROTECTED_USER          = admin
MIN_PASSWORD_LENGTH     = 8
DEFAULT_PASSWORD        = fetchconfig

# --- password rules ---
# Composition rules for new passwords; 0 = off. PASSWORD_MIN_CLASSES is how
# many of the four character classes (upper, lower, digit, special) must be
# present. A new password must also differ from DEFAULT_PASSWORD and from the
# username.
MAX_PASSWORD_LENGTH     = 64
PASSWORD_MIN_UPPER      = 0
PASSWORD_MIN_LOWER      = 0
PASSWORD_MIN_DIGIT      = 0
PASSWORD_MIN_SPECIAL    = 0
PASSWORD_MIN_CLASSES    = 0

# --- email / password reset ---
# EMAIL = 1 enables the self-service "Forgot password?" flow (needs Net::SMTP
# and the SMTP_* settings). With EMAIL = 0 (default) the link only tells users
# to contact the administrator. SMTP_SECURITY: starttls (default), ssl or none.
# SMTP AUTH is used only when EMAIL_AUTH = 1.
EMAIL                   = 0
SMTP_HOST               = mail.example.com
SMTP_PORT               = 587
SMTP_SECURITY           = starttls
EMAIL_AUTH              = 0
#SMTP_USER              = fetchconfig-web
#SMTP_PASS              = secret
EMAIL_FROM              = fetchconfig-web\@example.com
# Public base URL (scheme + host[:port], no path) used to build the reset link.
# REQUIRED when EMAIL = 1 -- the link is never derived from the request's Host
# header; without SITE_URL no reset email is sent.
SITE_URL                = https://fetchconfig.example.com

# --- security ---
# Secure by default. HTTPS_ENABLED=1 forces the session cookie's "Secure" flag
# and HSTS. The app also auto-detects a TLS request from the web-server
# environment; with TRUST_FORWARDED_PROTO=1 it additionally trusts a reverse
# proxy's X-Forwarded-Proto header. Set HTTPS_ENABLED=0 for an HTTP-only
# deployment, otherwise the Secure cookie is never sent over plain HTTP and
# login appears to fail.
HTTPS_ENABLED           = 1
TRUST_FORWARDED_PROTO   = 0
# Require bcrypt (Crypt::Bcrypt) for password hashing. 1 = never fall back to the
# weaker Apache MD5 hash; if the module is missing, login is disabled with a
# clear notice. Set 0 only on a stack without Crypt::Bcrypt (e.g. AIX dev).
REQUIRE_BCRYPT          = 1

# --- diagnostics / branding ---
# Set to 1 to show load/render-time lines across the UI (device list, status,
# log and template-list "load time" lines, plus the device-table editor render
# time). Default 0.
SHOW_RENDER_TIME        = 0
# APP_VERSION overrides the version shown in the footer; normally leave it
# commented out so the application reports its own version.
#APP_VERSION            = 2.07
COPYRIGHT               = 2026 (c) Rainer Tammer

# --- Dashboard ---
# Enable the Backup Dashboard, which reads the backup-history tables written by
# the fetchconfig engine's optional DB writer. 0 = hidden (default), 1 = shown.
# Requires the history schema -- run "fetchconfig-web-dbsetup.pl --upgrade" -- and
# the engine's "db:" option set on the device_table "default:" line.
ENABLE_DASHBOARD        = 0

# --- PostgreSQL user database ---
DBinst                  = $dbname
DBuser                  = $dbuser
DBpass                  = $dbpass
DBhost                  = $dbhost
CFG
}

if (yesno("\nWrite the fetchconfig-web config file to $CFG_PATH now?", 0)) {
    if (-e $CFG_PATH && !yesno("$CFG_PATH already exists -- overwrite it?", 0)) {
        print "Left $CFG_PATH untouched.\n";
    } else {
        if (open(my $cf, '>', $CFG_PATH)) {
            print $cf cfg_body($dbname, $app_user2, $app_pass2, $dbhost);
            close($cf);
            chmod(0600, $CFG_PATH);
            print "Wrote $CFG_PATH (mode 0600). Review the non-database\n";
            print "settings in it and adjust paths to match your installation.\n";
        } else {
            print STDERR "Could not write $CFG_PATH: $!\n";
            print STDERR "(Are you running as a user that can write to /etc?)\n";
            print STDERR "You can create it by hand -- see README.\n";
        }
    }
} else {
    print "\nNot writing $CFG_PATH. Create it by hand (see README) with at\n";
    print "least these database settings:\n";
    print "  DBinst = $dbname\n";
    print "  DBuser = $app_user2\n";
    print "  DBpass = <the application DB password>\n";
    print "  DBhost = $dbhost\n";
}

print "\n", "=" x 70, "\n";
print "Done.\n";
print "=" x 70, "\n";

exit 0;
