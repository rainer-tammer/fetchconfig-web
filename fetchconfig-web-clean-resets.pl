#!/usr/bin/perl
#
# fetchconfig-web-clean-resets.pl -- prune spent password-reset tokens and
# stale login-throttle counters from the fetchconfig-web database.
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
# The web application itself expires reset tokens (used flag + expiry) and ages
# out throttle counters by a time window, so neither table grows without bound
# in practice. This tool is housekeeping: it physically removes the rows the
# application no longer needs, so the tables stay small. It is safe to run from
# cron. The web DB user already has DELETE on login_attempts; it does NOT have
# DELETE on password_resets (tokens are marked used, never deleted, by the
# app), so this tool needs a role with DELETE on both -- use -s to print the
# SQL that creates exactly such a role.
#
# What it removes (with -t <days>, default 7):
#   password_resets : rows that are used = TRUE, OR expired more than <days>
#                     days ago (a spent/old token is of no further use).
#   login_attempts  : rows whose last_fail is older than <days> days (the
#                     cooldown/window is minutes, so a day-old counter is dead).

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case bundling);

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

my $cfg = read_config($CONFIG_FILE);

if ($opt_version) { print version_line($cfg), "\n"; exit 0; }
if ($opt_help)    { usage(0); }
if ($opt_sql)     { print_role_sql($cfg); exit 0; }

my $days = defined $opt_keep ? $opt_keep : 7;
if ($days < 0) {
    print STDERR "Error: -t <days> must be zero or a positive number.\n";
    exit 2;
}

my $dbname = $cfg->{DBinst} // 'fetchconfig';
my $dbhost = $cfg->{DBhost} // 'localhost';

my $user = defined $opt_user ? $opt_user : prompt("Database admin user: ");
my $pass = defined $opt_pass ? $opt_pass : prompt_noecho("Password for '$user': ");

require DBI;
my $dsn = "dbi:Pg:dbname=$dbname;host=$dbhost";
my $dbh = DBI->connect($dsn, $user, $pass,
    { RaiseError => 0, PrintError => 0, AutoCommit => 1 });
unless ($dbh) {
    print STDERR "Error: could not connect to database '$dbname' on '$dbhost' as '$user':\n  "
        . (DBI->errstr // 'unknown error') . "\n";
    exit 1;
}

# Count what would be removed.
my ($pr) = $dbh->selectrow_array(
    "SELECT count(*) FROM password_resets
       WHERE used = TRUE
          OR expires < now() - (? || ' days')::interval", undef, $days);
my ($la) = $dbh->selectrow_array(
    "SELECT count(*) FROM login_attempts
       WHERE last_fail < now() - (? || ' days')::interval", undef, $days);
unless (defined $pr && defined $la) {
    print STDERR "Error: could not query the tables (does the role have SELECT on\n"
        . "password_resets and login_attempts?):\n  "
        . ($dbh->errstr // 'unknown error') . "\n";
    $dbh->disconnect;
    exit 1;
}

if ($opt_list) {
    print "$pr spent/expired reset token" . ($pr == 1 ? '' : 's')
        . " and $la stale throttle row" . ($la == 1 ? '' : 's')
        . " would be deleted (nothing was changed).\n";
    $dbh->disconnect;
    exit 0;
}

my $d1 = $dbh->do(
    "DELETE FROM password_resets
       WHERE used = TRUE
          OR expires < now() - (? || ' days')::interval", undef, $days);
my $d2 = $dbh->do(
    "DELETE FROM login_attempts
       WHERE last_fail < now() - (? || ' days')::interval", undef, $days);
unless (defined $d1 && defined $d2) {
    print STDERR "Error: delete failed (does the role have DELETE on both tables?):\n  "
        . ($dbh->errstr // 'unknown error') . "\n";
    $dbh->disconnect;
    exit 1;
}
my $n1 = ($d1 eq '0E0') ? 0 : $d1;
my $n2 = ($d2 eq '0E0') ? 0 : $d2;

$dbh->disconnect;
print "Deleted $n1 reset token" . ($n1 == 1 ? '' : 's')
    . " and $n2 throttle row" . ($n2 == 1 ? '' : 's') . ".\n";
exit 0;

# ---- helpers --------------------------------------------------------------

sub version_line {
    my ($c) = @_;
    my $ver = (defined $c->{APP_VERSION} && $c->{APP_VERSION} ne '')
              ? $c->{APP_VERSION} : APP_VERSION_INTERNAL;
    my $cr  = (defined $c->{COPYRIGHT} && $c->{COPYRIGHT} ne '')
              ? $c->{COPYRIGHT} : DEFAULT_COPYRIGHT;
    return "fetchconfig-web-clean-resets.pl $ver -- $cr";
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
                $v =~ s/^"(.*)"$/$1/;
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
    my $ok = eval { system('stty', '-echo') == 0 };
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
-- Create a database role that may prune the reset/throttle tables and nothing
-- else. Run these as a PostgreSQL superuser (e.g. the 'postgres' account).
-- Replace the role name and password to taste; then run this script with
-- -u/-p (or let it prompt) using these credentials.

CREATE ROLE reset_cleaner LOGIN PASSWORD 'change-this-password';
GRANT CONNECT ON DATABASE $db TO reset_cleaner;
GRANT USAGE   ON SCHEMA public TO reset_cleaner;
GRANT SELECT, DELETE ON password_resets TO reset_cleaner;
GRANT SELECT, DELETE ON login_attempts  TO reset_cleaner;
SQL
}

sub usage {
    my ($exit) = @_;
    my $fh = $exit ? \*STDERR : \*STDOUT;
    print $fh <<"USAGE";
fetchconfig-web-clean-resets.pl -- prune spent reset tokens and stale throttle
counters from the fetchconfig-web database.

Usage:
  fetchconfig-web-clean-resets.pl [-t <days>] [-u user] [-p pass]
  fetchconfig-web-clean-resets.pl -l [-t <days>] [-u user] [-p pass]
  fetchconfig-web-clean-resets.pl -s
  fetchconfig-web-clean-resets.pl -v | -h

Options:
  -t, --keep <days>   Keep rows from the last <days> days (default 7). Deletes
                      used OR expired-more-than-<days>-ago reset tokens, and
                      login-throttle rows whose last failure is older than
                      <days> days.
  -l, --list          Preview only: print how many rows WOULD be deleted.
  -s, --sql           Print SQL to create a minimal 'reset_cleaner' role (SELECT
                      + DELETE on password_resets and login_attempts) and exit.
  -u, --dbuser <u>    Database role to connect as (else prompt).
  -p, --dbpass <p>    Its password (else prompt without echo).
  -v, --version       Print version and exit.
  -h, --help          This help.

Connection defaults (DBinst/DBhost) come from $CONFIG_FILE.
USAGE
    exit $exit;
}
