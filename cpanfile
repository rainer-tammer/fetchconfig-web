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
requires 'DBI',             '1.641';     # database access
requires 'DBD::Pg',         '3.15.0';    # PostgreSQL driver
requires 'Algorithm::Diff', '0';         # side-by-side / unified config diffs
requires 'CGI',             '4.53';      # CGI request/response (non-core since 5.22)

# --- runtime: modules distributed with Perl (core since 5.8) ---------------
# Declared for completeness so the dependency graph is accurate; normally
# already present with the Perl interpreter.
requires 'Digest::MD5',  '0';            # device-table staleness token
requires 'Time::HiRes',  '0';            # sub-second mtime in that token
requires 'MIME::Base64', '0';            # inline base64 logo previews
requires 'Fcntl',        '0';            # flock constants for table locking

# --- optional: enables one specific tool -----------------------------------
# Needed only by the "Tools -> Disk space" page (free-space figures). The tool
# loads it lazily and degrades gracefully if it is absent; the rest of the
# application does not depend on it.
recommends 'Filesys::Df', '0';

# --- test suite ------------------------------------------------------------
on 'test' => sub {
    requires 'Test::More', '0';          # core; the unit tests use only this
};
