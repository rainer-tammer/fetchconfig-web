# cpanfile -- Perl dependency manifest for fetchconfig-web.
#
# This mirrors the prerequisites declared in Makefile.PL and lets GitHub's
# dependency graph (and tools like Dependabot / cpanm) track the Perl modules
# the application needs. It is not required to run the application; install
# dependencies from it with:
#
#   cpanm --installdeps .
#
# Keep the versions in sync with Makefile.PL (PREREQ_PM / TEST_REQUIRES).

# --- runtime: non-core modules the application requires --------------------
# The floors below are the versions the code actually needs, so the stock
# packages of RHEL 9, SLES 15, Ubuntu LTS and Debian all satisfy them without
# CPAN. Do not raise them to express security policy: enterprise distributions
# backport fixes without bumping the version string, so a higher floor rejects
# a patched vendor build while accepting an unpatched one from CPAN. Security
# guidance belongs in INSTALL.md instead.
requires 'DBI',             '1.614';     # database access (what DBD::Pg itself requires)
requires 'DBD::Pg',         '3.0.0';     # PostgreSQL driver; no pg_* driver attributes are used
requires 'Algorithm::Diff', '0';         # side-by-side / unified config diffs
requires 'CGI',             '4.31';      # non-core since 5.22; 4.31 is the -samesite cookie floor

# --- runtime: modules distributed with Perl (core since 5.8) ---------------
# Declared for completeness so the dependency graph is accurate; normally
# already present with the Perl interpreter.
requires 'Digest::MD5',  '0';            # device-table staleness token
requires 'Time::HiRes',  '0';            # sub-second mtime in that token
requires 'MIME::Base64', '0';            # inline base64 logo previews
requires 'Fcntl',        '0';            # flock constants for table locking

# --- optional: each enables one specific capability ------------------------
# All of these are loaded lazily and the application degrades gracefully when
# they are absent -- but note what each absence costs.
#
# Needed only by the "Tools -> Disk space" page (free-space figures).
recommends 'Filesys::Df', '0';
# Enables bcrypt ($2b$) password hashing at BCRYPT_COST. WITHOUT it, new and
# changed passwords fall back to the legacy Apache MD5 ($apr1$) format, so this
# is a security-relevant option rather than a cosmetic one.
recommends 'Crypt::Bcrypt', '0';
# Required for STARTTLS/SSL on the password-reset mail (EMAIL = 1). Net::SMTP
# itself is core (libnet); this is what gives it TLS. Note: Net::SMTP::SSL is
# NOT used and must not be installed in its place.
recommends 'IO::Socket::SSL', '0';
# Enables the persistent FastCGI accept loop (mod_fcgid). Without it the script
# runs as plain CGI. CGI::Fast is NOT used and is not a dependency.
recommends 'FCGI', '0';

# --- test suite ------------------------------------------------------------
on 'test' => sub {
    requires 'Test::More', '0';          # core; the unit tests use only this
};
