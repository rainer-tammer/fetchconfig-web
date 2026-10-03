package FCWebTest;
#
# Test helper for fetchconfig-web.
#
# fetchconfig-web.cgi is a single CGI *script*, not a module, and it ends with
# "main(); exit;" and pulls in CGI/DBI/etc. To unit-test its pure functions we:
#   1. provide lightweight stub modules for CGI, CGI::Cookie, DBI, DBD::Pg and
#      Algorithm::Diff, so the script's "use" lines succeed on a bare box;
#   2. write a minimal temporary config so read_config() is happy;
#   3. slurp the script, repoint $CONFIG_FILE at the temp config, strip the
#      trailing "main(); exit;" so nothing runs at load time, and eval it into
#      the caller's namespace.
#
# After load_cgi() the script's subs (version_cmp, mask_secrets, valid_id,
# %MODEL_CATALOG, ...) are available in package main:: for testing.
#
# Copyright (C) 2026 Rainer Tammer. GNU GPL v3 or later.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Spec;
use File::Path qw(make_path);
use Cwd qw(abs_path);
use Exporter 'import';

our @EXPORT_OK = qw(load_cgi cgi_path make_config stub_libdir);

# Locate fetchconfig-web.cgi relative to this file (t/lib -> project root).
sub cgi_path {
    my $here = abs_path(__FILE__);
    my ($vol, $dir) = File::Spec->splitpath($here);
    # $dir = .../t/lib/ ; go up two levels to the project root.
    my $root = abs_path(File::Spec->catdir($dir, File::Spec->updir, File::Spec->updir));
    return File::Spec->catfile($root, 'fetchconfig-web.cgi');
}

# Create a directory of stub modules so the script's use-lines load without the
# real CGI/DBI/DBD::Pg/Algorithm::Diff being installed. Returns the dir path.
sub stub_libdir {
    my $dir = tempdir(CLEANUP => 1);

    _write($dir, 'CGI.pm', <<'PM');
package CGI;
sub new { bless {}, shift }
sub header { shift; return "Content-Type: text/html\n\n"; }
sub param { return; }
sub escapeHTML {
    my ($s, $t) = @_; $t = $s unless defined $t && $t ne 'CGI';
    $t = '' unless defined $t;
    $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g;
    $t =~ s/"/&quot;/g; $t =~ s/'/&#39;/g; return $t;
}
sub escape {
    my ($s, $t) = @_; $t = $s unless defined $t && $t ne 'CGI';
    $t = '' unless defined $t;
    $t =~ s/([^A-Za-z0-9_.\-])/sprintf('%%%02X', ord $1)/ge; return $t;
}
sub start_form { '<form>' } sub end_form { '</form>' }
sub textfield { '<input type="text">' } sub password_field { '<input type="password">' }
sub submit { my ($s,%a)=@_; my $v=$a{-value}//'Submit'; qq{<input type="submit" value="$v">} }
sub hidden { '<input type="hidden">' } sub checkbox { '<input type="checkbox">' }
sub url { '/cgi-bin/fetchconfig-web.cgi' }
1;
PM

    _write($dir, 'CGI/Cookie.pm', <<'PM');
package CGI::Cookie;
sub new { bless {}, shift } sub parse { {} } sub fetch { () }
sub value {} sub name {}
1;
PM

    _write($dir, 'DBI.pm', <<'PM');
package DBI;
sub connect { return undef; }
1;
PM

    _write($dir, 'DBD/Pg.pm', <<'PM');
package DBD::Pg;
our $VERSION = '0.00_stub';
1;
PM

    _write($dir, 'Algorithm/Diff.pm', <<'PM');
package Algorithm::Diff;
use Exporter 'import';
our @EXPORT_OK = qw(sdiff LCS traverse_sequences);
sub sdiff { () } sub LCS { () } sub traverse_sequences { }
1;
PM

    return $dir;
}

# Write a minimal valid config file and return its path.
sub make_config {
    my (%over) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $dt   = File::Spec->catfile($dir, 'device_table'); _touch($dt);
    my $sess = File::Spec->catdir($dir, 'sessions');       mkdir $sess;
    my $fcp  = File::Spec->catdir($dir, 'fc');             mkdir $fcp;
    mkdir File::Spec->catdir($fcp, 'fetchconfig');
    my %cfg = (
        DEVICE_TABLE     => $dt,
        REPOSITORY       => File::Spec->catdir($dir, 'repo'),
        FETCHCONFIG_PATH => $fcp,
        FETCHCONFIG_BIN  => 'fetchconfig.pl',
        SESSION_DIR      => $sess,
        DBinst           => 'fc', DBuser => 'fc', DBhost => 'localhost',
        %over,
    );
    my $path = File::Spec->catfile($dir, 'fetchconfig-web.cfg');
    open(my $fh, '>', $path) or die "cannot write $path: $!";
    # Skip keys whose value is undef (a caller may pass KEY => undef to mean
    # "leave this unset" rather than writing a bogus "KEY = " line).
    for (sort keys %cfg) {
        next unless defined $cfg{$_};
        print $fh "$_ = $cfg{$_}\n";
    }
    close($fh);
    return ($path, $dir, $fcp);
}

# Load the CGI's functions into package main. Pass the config path to use.
sub load_cgi {
    my ($config_path) = @_;
    my $stub = stub_libdir();
    unshift @INC, $stub;

    my $src = do {
        local $/;
        open(my $fh, '<', cgi_path()) or die "cannot read CGI: $!";
        <$fh>;
    };

    # Repoint the hard-coded config path at our temp config.
    my $q = quotemeta("'/etc/fetchconfig-web.cfg'");
    $src =~ s/$q/"'" . $config_path . "'"/e;

    # Neutralise the file-scope "run" statements so nothing executes (or exits)
    # on eval, while keeping every sub and data-table definition (which tests
    # need). These three blocks are the only top-level executable code:
    #   1. the read_config() config-error check + show_login_form/exit
    #   2. the SESSION_DIR make_path check
    #   3. the trailing main(); exit 0;
    # Everything else at file scope is harmless "my %table = (...)" data.
    $src =~ s/^if \(my \$cfg_err = read_config\(\)\) \{.*?^\}\n//ms;
    $src =~ s/^if \(!-d \$SESSION_DIR\) \{.*?^\}\n//ms;
    $src =~ s/^\s*main\(\);\s*$//m;
    $src =~ s/^\s*exit\s+0;\s*$//m;

    # A second load_cgi() in one test process re-defines every sub and constant,
    # which is intentional but otherwise floods the output with "redefined"
    # warnings. The CGI's own "use strict; use warnings;" would re-enable them
    # for the rest of the file, so inject "no warnings 'redefine','once'"
    # immediately after the FIRST pragma -- before the "use constant" lines,
    # whose BEGIN-time redefinition warnings fire during compilation of the
    # eval'd source. (Test-only transform; the shipped script is unchanged.)
    $src =~ s/^(use\s+warnings\s*;)/$1\nno warnings 'redefine', 'once';/m;

    $src .= "\n1;\n";

    # Eval into package main so the subs are callable as main::foo(). A test may
    # load_cgi() more than once (e.g. to switch to a second config); that
    # re-defines every sub and constant, which is intentional here. The pragma
    # must be in scope at the point the eval RUNS (that is where the redefine
    # warnings fire), so wrap the eval itself -- prepending "no warnings" inside
    # the eval'd string is not enough for sub/constant redefinition.
    # Silence only the noise a deliberate reload makes -- "Subroutine/Constant
    # subroutine ... redefined" and "used only once" -- while letting every
    # other warning through unchanged. A __WARN__ filter catches all of them
    # uniformly, including the "use constant" redefinitions that fire from
    # constant.pm's own glob assignment and so ignore a lexical pragma here.
    my $ok = do {
        no warnings 'redefine', 'once';
        local $SIG{__WARN__} = sub {
            my $w = shift;
            return if $w =~ /(?:Constant subroutine|Subroutine) \S+ redefined/;
            return if $w =~ /used only once: possible typo/;
            warn $w;
        };
        eval "package main;\nno warnings 'redefine', 'once';\n" . $src . "\n";
    };
    die "loading CGI failed: $@" unless $ok;
    return 1;
}

sub _write {
    my ($dir, $rel, $content) = @_;
    my $path = File::Spec->catfile($dir, split m{/}, $rel);
    my ($vol, $d) = File::Spec->splitpath($path);
    make_path($d) if $d ne '' && !-d $d;
    open(my $fh, '>', $path) or die "cannot write $path: $!";
    print $fh $content; close($fh);
}
sub _touch { my ($f) = @_; open(my $fh, '>', $f) or die "touch $f: $!"; close($fh); }

1;
