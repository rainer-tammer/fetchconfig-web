#!/usr/bin/perl
#
# Makefile.PL for fetchconfig-web.
#
# fetchconfig-web is NOT a CPAN-style installable module: it is a single CGI
# script (plus helper scripts, static assets and docs) that is deployed by
# copying files into your web server's cgi-bin and document tree. This
# Makefile.PL exists to give a standard "perl Makefile.PL && make test"
# workflow for the t/ unit-test suite. It deliberately does NOT install
# anything -- "make install" only prints a pointer to the deployment
# instructions in README.md.
#
# Copyright (C) 2026 Rainer Tammer. GNU GPL v3 or later.

use strict;
use warnings;
use ExtUtils::MakeMaker;

# --- explicit prerequisite check ------------------------------------------
# MakeMaker only *warns* about missing/old prerequisites and then carries on.
# We want "perl Makefile.PL" to check up front and report clearly (and fail)
# if a required module is missing or too old, like a well-behaved distribution.
my %REQUIRE = (
    'DBI'             => '1.641',
    'DBD::Pg'         => '3.15.0',
    'Algorithm::Diff' => '0',
    'CGI'             => '4.53',
    'Test::More'      => '0',
);

sub _check_prereqs {
    my @missing; my @tooold;
    for my $mod (sort keys %REQUIRE) {
        my $need = $REQUIRE{$mod};
        # Load without importing; capture "not installed" vs other errors.
        my $ok = eval "require $mod; 1";
        if (!$ok) {
            push @missing, "$mod" . ($need ne '0' ? " (need $need or newer)" : "");
            next;
        }
        next if $need eq '0';
        # Compare installed vs required. $mod->VERSION($need) dies if too old.
        my $have = eval { $mod->VERSION } // 'unknown';
        my $good = eval { $mod->VERSION($need); 1 };
        if (!$good) {
            push @tooold, "$mod $have installed, but $need or newer is required";
        }
    }
    return (\@missing, \@tooold);
}

my ($missing, $tooold) = _check_prereqs();
if (@$missing || @$tooold) {
    warn "\n";
    warn "=" x 70, "\n";
    warn "fetchconfig-web: unmet Perl module prerequisites\n";
    warn "=" x 70, "\n";
    if (@$missing) {
        warn "\nMissing modules:\n";
        warn "  - $_\n" for @$missing;
    }
    if (@$tooold) {
        warn "\nModules too old:\n";
        warn "  - $_\n" for @$tooold;
    }
    warn <<'HINT';

Install them from your OS packages, for example:

  Debian/Ubuntu : apt install libdbi-perl libdbd-pg-perl \
                              libalgorithm-diff-perl libcgi-pm-perl
  RHEL/Rocky    : dnf install perl-DBI perl-DBD-Pg perl-Algorithm-Diff perl-CGI
  SUSE/SLES     : zypper install perl-DBI perl-DBD-Pg perl-Algorithm-Diff perl-CGI

or from CPAN:  cpan DBI DBD::Pg Algorithm::Diff CGI

HINT
    die "Prerequisite check failed; install the modules above and re-run "
      . "'perl Makefile.PL'.\n";
}

WriteMakefile(
    NAME          => 'fetchconfig_web',
    VERSION       => '1.53',
    AUTHOR        => 'Rainer Tammer',
    ABSTRACT      => 'Web front-end for the fetchconfig network device configuration backup tool',
    LICENSE       => 'gpl_3',

    # Runtime dependencies of fetchconfig-web.cgi. The explicit check above
    # enforces these at "perl Makefile.PL" time with clear errors; these
    # entries keep MYMETA / cpan clients informed too.
    PREREQ_PM => {
        'DBI'             => '1.641',
        'DBD::Pg'         => '3.15.0',
        'Algorithm::Diff' => 0,
        'CGI'             => '4.53',
    },
    # The test suite only needs core Test::More.
    TEST_REQUIRES => {
        'Test::More' => 0,
    },

    # No installable modules on purpose (see the note above and MY::install).
    PL_FILES  => {},
    test      => { TESTS => 't/*.t' },
    clean     => { FILES => 'Makefile.old MYMETA.*' },
);

# Each test file adds t/lib to @INC itself (via FindBin), so the harness needs
# no special -I. We only override install (below).
package MY;

# "make doc" regenerates fetchconfig-web-documentation.html from README.md via
# render-doc.py. It requires a Python interpreter (python3 preferred, else
# python) and fails with a clear message if none is found.
sub postamble {
    return <<'MAKE';
# ---- documentation -------------------------------------------------------
DOC_SRC = README.md
DOC_OUT = fetchconfig-web-documentation.html

doc :
	@py=""; \
	for cand in python3 python; do \
	    if $$cand --version >/dev/null 2>&1; then py=$$cand; break; fi; \
	done; \
	if [ -z "$$py" ]; then \
	    echo "make doc: error: no Python interpreter found (need python3 or python) -- cannot run render-doc.py." >&2; \
	    exit 1; \
	fi; \
	echo "make doc: using $$py to render $(DOC_OUT) from $(DOC_SRC)"; \
	$$py render-doc.py $(DOC_SRC) $(DOC_OUT)

MAKE
}

# Replace the standard install targets with a note: this project is deployed by
# copying files, as documented in README.md -- nothing is installed here.
sub install {
    return <<'MAKE';
install ::
	@echo ""
	@echo "fetchconfig-web is not installed by 'make'."
	@echo "It is deployed by copying files into your web server, as described"
	@echo "in the 'Deploying' section of README.md (copy fetchconfig-web.cgi to"
	@echo "cgi-bin, install the config file, fonts and images, and run"
	@echo "fetchconfig-web-dbsetup.pl once for the user database)."
	@echo ""
	@echo "Use 'make test' to run the unit-test suite."
	@echo ""

install_vendor :: install
install_site :: install
install_perl :: install
MAKE
}
