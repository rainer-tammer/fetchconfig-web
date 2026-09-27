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
            username           TEXT     PRIMARY KEY,
            pass_hash          TEXT     NOT NULL,
            edit_device_table  BOOLEAN  NOT NULL DEFAULT FALSE,
            admin_function     BOOLEAN  NOT NULL DEFAULT FALSE
        )
    }) or die_clean("CREATE TABLE failed: " . $dbh->errstr);
    print "Created table \"users\".\n";
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

$dbh->disconnect;

# --- Step 5: write the fetchconfig-web config file (optional) ----------------
#
# fetchconfig-web.cgi reads all its settings from this file. We fill in the
# database values from what was entered above; the non-DB settings are
# written at their defaults for you to review/adjust. The file holds the DB
# password in clear text, so it is created mode 0600.

my $CFG_PATH = '/etc/fetchconfig-web.cfg';

sub cfg_body {
    my ($dbname, $dbuser, $dbpass, $dbhost) = @_;
    return <<"CFG";
# $CFG_PATH -- fetchconfig-web configuration (key = value)
# Written by fetchconfig-web-dbsetup.pl. Review the non-database settings
# below and adjust paths to match your installation. Keep this file
# readable only by the web-server user (mode 0600), as it holds the
# database password in clear text.

# --- fetchconfig paths ---
DEVICE_TABLE            = /usr/local/fetchconfig/device_table
REPOSITORY              = /usr/local/fetchconfig/config
FETCHCONFIG_LOG         = /usr/local/fetchconfig/fetchconfig.log
FONT_BASE_URL           = /fetchconfig-web/fonts
IMAGE_BASE_URL          = /fetchconfig-web/images

# --- fetchconfig binary paths ---
FETCHCONFIG_PATH        = /usr/local/fetchconfig
FETCHCONFIG_BIN         = fetchconfig.pl

# --- device table editor backups ---
BACKUP_DEVICE_TABLE     = /usr/local/fetchconfig/backup

# --- Backup Now / sudo ---
USE_SUDO_FOR_BACKUP_NOW = 1
SUDO_BIN                = /usr/bin/sudo

# --- sessions ---
SESSION_DIR             = /www/fetchconfig-web/sessions
BACKUP_TMP_DIR          = /www/fetchconfig-web/sessions
SESSION_TTL             = 28800

# --- device table parsing ---
DEVICE_ID_FIELD         = 1

# --- PostgreSQL user database ---
DBinst                  = $dbname
DBuser                  = $dbuser
DBpass                  = $dbpass
DBhost                  = $dbhost

# --- user policy ---
PROTECTED_USER          = admin
MIN_PASSWORD_LENGTH     = 8
DEFAULT_PASSWORD        = fetchconfig

# --- misc ---
HELP_FILE               = /www/pub/fetchconfig-web/help.html
APP_VERSION             = 1.14
COPYRIGHT               = 2026 (c) Rainer Tammer
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
