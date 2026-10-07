#!/usr/bin/perl
#
# fetchconfig-web-clean-audit.pl -- prune old rows from the fetchconfig-web
# audit log.
#
# Copyright (c) 2026, Rainer Tammer
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.  You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# The fetchconfig-web audit_log table is append-only for the web application:
# the web database user is granted INSERT + SELECT only, so neither the
# application nor a compromised web process can alter or delete audit records
# (Level B immutability). Purging old records is therefore a deliberate,
# privileged maintenance action, performed by this standalone script with a
# database role that holds DELETE on audit_log. Use -s to print the SQL that
# creates exactly such a role.
#
# Retention (GDPR storage limitation): the audit log is not pruned
# automatically. Run this script (e.g. from cron) with a retention period that
# matches your organisation's policy. See PRIVACY.md.

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case bundling);

# ---- version / copyright, shared with fetchconfig-web --------------------
# The built-in values match the application; both can be overridden by the
# config file (APP_VERSION / COPYRIGHT), exactly as the web UI does.
use constant APP_VERSION_INTERNAL => '1.60';
use constant DEFAULT_COPYRIGHT    => 'Copyright (c) 2026, Rainer Tammer';

my $CONFIG_FILE = '/etc/fetchconfig-web.cfg';

# ---- command line ---------------------------------------------------------
my ($opt_help, $opt_version, $opt_keep, $opt_list, $opt_sql, $opt_user, $opt_pass);
GetOptions(
    'h|help|?'   => \$opt_help,
    'v|version'  => \$opt_version,
    't|keep=i'   => \$opt_keep,
    'l|list'     => \$opt_list,
    's|sql'      => \$opt_sql,
    'u|dbuser=s' => \$opt_user,
    'p|dbpass=s' => \$opt_pass,
) or usage(2);

# Read config early: it supplies DB connection defaults and any version /
# copyright override for -v.
my $cfg = read_config($CONFIG_FILE);

if ($opt_version) { print version_line($cfg), "\n"; exit 0; }
if ($opt_help)    { usage(0); }
if ($opt_sql)     { print_role_sql($cfg); exit 0; }

# From here on we need to talk to the database. -t <days> is required for both
# a delete and an -l preview (the preview counts rows older than <days>, so it
# is meaningless without one).
my $days = $opt_keep;
unless (defined $days) {
    print STDERR $opt_list
        ? "Error: -l requires -t <days> (it previews how many records older than\n"
          . "<days> days would be deleted).\n\n"
        : "Nothing to do: specify -t <days> (with -l to preview, or without to delete).\n\n";
    usage(2);
}
if ($days < 0) {
    print STDERR "Error: -t <days> must be zero or a positive number.\n";
    exit 2;
}

require DBI;

my $dbname = $cfg->{DBinst} // '';
my $dbhost = $cfg->{DBhost} // 'localhost';
if ($dbname eq '') {
    print STDERR "Error: DBinst is not set in $CONFIG_FILE and no database name is known.\n";
    exit 2;
}

# Admin credentials: -u/-p, else prompt. The password prompt suppresses echo.
my $user = defined $opt_user ? $opt_user : prompt("Database admin user: ");
my $pass = defined $opt_pass ? $opt_pass : prompt_noecho("Password for '$user': ");

my $dsn = "dbi:Pg:dbname=$dbname;host=$dbhost";
my $dbh = DBI->connect($dsn, $user, $pass,
    { RaiseError => 0, PrintError => 0, AutoCommit => 1 });
unless ($dbh) {
    print STDERR "Error: could not connect to database '$dbname' on '$dbhost' as '$user':\n  "
        . (DBI->errstr // 'unknown error') . "\n";
    exit 1;
}

# Count rows strictly older than the retention window (excluding the prune
# records themselves, which are never deleted).
my $count_sql = "SELECT count(*) FROM audit_log
                  WHERE ts < now() - (? || ' days')::interval
                    AND action <> 'audit_prune'";   # keep the prune history
my ($n) = $dbh->selectrow_array($count_sql, undef, $days);
unless (defined $n) {
    print STDERR "Error: could not query audit_log (does the role have SELECT on it?):\n  "
        . ($dbh->errstr // 'unknown error') . "\n";
    $dbh->disconnect;
    exit 1;
}

if ($opt_list) {
    print "$n record" . ($n == 1 ? '' : 's')
        . " older than $days day" . ($days == 1 ? '' : 's')
        . " would be deleted (nothing was changed).\n";
    $dbh->disconnect;
    exit 0;
}

# Delete.
if ($n == 0) {
    print "No records older than $days day" . ($days == 1 ? '' : 's') . "; nothing to delete.\n";
    $dbh->disconnect;
    exit 0;
}
my $del = $dbh->do(
    "DELETE FROM audit_log
       WHERE ts < now() - (? || ' days')::interval
         AND action <> 'audit_prune'",   # never delete the prune records themselves
    undef, $days);
unless (defined $del) {
    print STDERR "Error: delete failed (does the role have DELETE on audit_log?):\n  "
        . ($dbh->errstr // 'unknown error') . "\n";
    $dbh->disconnect;
    exit 1;
}
my $ndel = ($del eq '0E0') ? 0 : $del;

# Record the prune itself in the audit log -- but ONLY when rows were actually
# deleted ($ndel > 0). A run that removed nothing (e.g. the count and delete
# disagreed, or only prune records were in range) writes no entry, so the log
# is not cluttered with "deleted 0 records" rows.
# Best-effort: a failure here does not undo the delete or change the exit code.
if ($ndel > 0) {
    my $who = $user;                      # the DB role that ran the prune
    my $ip  = $ENV{SSH_CLIENT} ? (split /\s+/, $ENV{SSH_CLIENT})[0] : '';
    my $detail = "pruned audit log: deleted $ndel record"
               . ($ndel == 1 ? '' : 's')
               . " older than $days day" . ($days == 1 ? '' : 's')
               . " (-t $days)";
    # $dbh->do returns the row count on success, or undef on failure (the
    # connection uses RaiseError=>0, so a failed INSERT does NOT die -- we must
    # check the return value explicitly, otherwise the failure would be silent).
    my $res = eval {
        $dbh->do(
            'INSERT INTO audit_log
               (username, ip, action, object_type, object_id, detail)
             VALUES (?,?,?,?,?,?)',
            undef, $who, $ip, 'audit_prune', 'audit_log', undef, $detail);
    };
    unless (defined $res) {
        my $err = $dbh->errstr // $@ // 'unknown error';
        $err =~ s/\s+/ /g; $err =~ s/^\s+|\s+$//g;
        warn "Note: the $ndel-record prune was done, but could NOT be recorded in\n"
           . "the audit log: $err\n"
           . "The role needs INSERT on audit_log AND USAGE on the id sequence\n"
           . "(audit_log_id_seq). Run the grants printed by '"
           . "$0 -s' (they include the sequence grant).\n";
    }
}

$dbh->disconnect;
print "Deleted $ndel record" . ($ndel == 1 ? '' : 's')
    . " older than $days day" . ($days == 1 ? '' : 's') . ".\n";
exit 0;

# ---- helpers --------------------------------------------------------------

sub version_line {
    my ($c) = @_;
    my $ver = (defined $c->{APP_VERSION} && $c->{APP_VERSION} ne '')
            ? $c->{APP_VERSION} : APP_VERSION_INTERNAL;
    my $cr  = (defined $c->{COPYRIGHT} && $c->{COPYRIGHT} ne '')
            ? $c->{COPYRIGHT} : DEFAULT_COPYRIGHT;
    return "fetchconfig-web-clean-audit.pl (fetchconfig-web $ver)\n$cr";
}

sub read_config {
    my ($path) = @_;
    my %kv;
    if (open(my $fh, '<', $path)) {
        while (my $line = <$fh>) {
            $line =~ s/\r?\n$//;
            next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
            if ($line =~ /^\s*([A-Za-z_][\w]*)\s*=\s*(.*?)\s*$/) {
                my ($k, $v) = ($1, $2);
                $v =~ s/^"(.*)"$/$1/;            # strip optional surrounding quotes
                $kv{$k} = $v;
            }
        }
        close($fh);
    }
    return \%kv;
}

sub prompt {
    my ($msg) = @_;
    print $msg;
    my $in = <STDIN>;
    $in = '' unless defined $in;
    $in =~ s/\r?\n$//;
    return $in;
}

sub prompt_noecho {
    my ($msg) = @_;
    print $msg;
    my $ok = eval { system('stty', '-echo') == 0 };   # best effort; POSIX terminals
    my $in = <STDIN>;
    if ($ok) { system('stty', 'echo'); print "\n"; }
    $in = '' unless defined $in;
    $in =~ s/\r?\n$//;
    return $in;
}

sub print_role_sql {
    my ($c) = @_;
    my $db = $c->{DBinst} // 'fetchconfig';
    print <<"SQL";
-- Create a database role that may prune the audit log and nothing else.
-- Run these as a PostgreSQL superuser (e.g. the 'postgres' account). Replace
-- the role name and password to taste; then run this script with -u/-p (or let
-- it prompt) using these credentials.
--
-- The role gets, on audit_log only (no access to any other table):
--   SELECT  -- for the -l preview and the targeted DELETE ... WHERE,
--   DELETE  -- to prune old rows,
--   INSERT  -- so this script can record a "pruned the audit log" entry
--            (the prune is itself an audited event).
-- It also needs USAGE/SELECT on the id sequence to insert that one row.

CREATE ROLE audit_cleaner LOGIN PASSWORD 'change-this-password';
GRANT CONNECT ON DATABASE $db TO audit_cleaner;
GRANT USAGE   ON SCHEMA public TO audit_cleaner;
GRANT SELECT, INSERT, DELETE ON audit_log TO audit_cleaner;
GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO audit_cleaner;
SQL
}

sub usage {
    my ($exit) = @_;
    my $fh = $exit ? \*STDERR : \*STDOUT;
    print $fh <<"USAGE";
fetchconfig-web-clean-audit.pl -- prune old rows from the fetchconfig-web audit log.

Usage:
  fetchconfig-web-clean-audit.pl -t <days> [-u user] [-p pass]
  fetchconfig-web-clean-audit.pl -l -t <days> [-u user] [-p pass]
  fetchconfig-web-clean-audit.pl -s
  fetchconfig-web-clean-audit.pl -v | -h

Options:
  -t, --keep <days>   Keep records from the last <days> days; delete older ones
                      (deletes rows with ts < now() - <days> days). The prune
                      records themselves (action 'audit_prune') are never
                      deleted, so the history of when/how the log was pruned is
                      retained.
  -l, --list          Preview only: print how many records WOULD be deleted for
                      the given -t <days>; delete nothing.
  -s, --sql           Print the PostgreSQL statements that create a role allowed
                      to delete audit-log records (SELECT + DELETE on audit_log
                      only), then exit. Run those as a DB superuser.
  -u, --dbuser <u>    Database user to connect as. If omitted, you are prompted.
  -p, --dbpass <p>    Password for that user. If omitted, you are prompted
                      (without echo).
  -v, --version       Print the version and copyright, then exit.
  -h, --help, -?      Show this help, then exit.

Database connection:
  The database name (DBinst) and host (DBhost) are read from
  $CONFIG_FILE. The connection USER and PASSWORD are NOT taken from
  that file: this script must connect with a role that holds DELETE on the
  audit_log table.

IMPORTANT -- DB admin rights required:
  The fetchconfig-web audit log is append-only for the application: the web
  database user has INSERT + SELECT only and CANNOT delete audit records (this
  is the audit log's immutability guarantee). To prune old records you must run
  this script with a database role that has DELETE on audit_log. Use -s to
  print the SQL that creates exactly such a role (SELECT + INSERT + DELETE on
  audit_log and nothing else). The prune itself is recorded in the audit log
  (action 'audit_prune', including the -t value used), which is why the role
  also needs INSERT.

Examples:
  fetchconfig-web-clean-audit.pl -s | psql -U postgres -d fetchconfig
  fetchconfig-web-clean-audit.pl -l -t 365 -u audit_cleaner
  fetchconfig-web-clean-audit.pl -t 365 -u audit_cleaner
USAGE
    exit $exit;
}
