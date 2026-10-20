use strict; use warnings;
use Test::More;
use File::Spec;
use File::Temp ();
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# Server-side validation regressions (2.06). Each block below covers a defect
# where the only thing stopping bad input was the browser: the UI rendered a
# dropdown, greyed out a control or hid a menu, and the POST handler took the
# submitted value on trust. A forged request bypasses all of those.
#
#   F1  per-site scope on the action-less ?dev= route
#   F2  secret write-back keyed on the catalog type (destroyed stored secrets)
#   F3  upload_logo / delete_logo had no authorization check at all
#   F4  lock_dir was not checked against the directory allow-list

my ($cfg, $dir, $fcp) = make_config();
my %kv; { open(my $r,'<',$cfg) or die $!;
          while(<$r>){ chomp; my($a,$b)=split/\s*=\s*/,$_,2; $kv{$a}=$b if defined $b; }
          close($r); }

# Device table with a directory: allow-list that includes a lock kind.
open(my $w, '>', $kv{DEVICE_TABLE}) or die "write table: $!";
print $w <<'DT';
# DEFAULT OPTIONS SECTION

# directory allow list - must be directly edited on the server
directory: repository $REPO1     /usr/local/fetchconfig/config
directory: template   $TEMPLATE1 /usr/local/fetchconfig/templates
directory: lock       $LOCKS     /var/run/fetchconfig-locks
# directory allow list - must be directly edited on the server

cisco-ios sw1 10.0.0.1 user=x,pass=y,repository=$REPO1,keep=5
DT
close($w);

# Stub fetchconfig --list-allowed-dirs so read_allowed_dirs() sees the block.
my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open($w, '>', $stub) or die $!;
print $w <<'STUB';
#!/usr/bin/perl
my $lad=0; for(@ARGV){$lad=1 if $_ eq '--list-allowed-dirs';}
exit 0 unless $lad;
print "1\trepository\t\$REPO1\t/usr/local/fetchconfig/config\n";
print "2\ttemplate\t\$TEMPLATE1\t/usr/local/fetchconfig/templates\n";
print "3\tlock\t\$LOCKS\t/var/run/fetchconfig-locks\n";
exit 0;
STUB
close($w); chmod 0755, $stub;

load_cgi($cfg); main::read_config();
no warnings 'once';
my $src = do { local $/; open(my $f,'<',cgi_path()) or die $!; <$f> };

# --- F4: lock_dir is subject to the directory allow-list ---------------------
# The editor renders lock_dir as a restricted dropdown whenever the allow-list
# block is present, but directory_allowlist_violations() dispatched on only
# repository/template_dir/on_fetch_run/report_dir, so a forged lock_dir went
# straight through.
{
    my @base = (['user','u'],['pass','p'],['repository','$REPO1'],['keep','5']);
    my $viol = sub {
        my ($k,$v) = @_;
        my @o = grep { $_->[0] ne $k } @base; push @o, [$k,$v];
        my @e = main::directory_allowlist_violations(
                    [{ kind=>'device', model=>'cisco-ios', id=>'sw1',
                       host=>'10.0.0.1', opts=>\@o }]);
        return scalar @e;
    };
    # Control: the kinds that always worked must keep working.
    ok( $viol->('repository',   '/etc'),   'F4 control: off-list repository rejected');
    ok( $viol->('template_dir', '/etc'),   'F4 control: off-list template_dir rejected');
    ok(!$viol->('repository',   '$REPO1'), 'F4 control: allow-listed repository accepted');

    ok( $viol->('lock_dir', '/etc/evil'), 'F4: off-list lock_dir rejected');
    ok( $viol->('lock_dir', '$NOPE'),     'F4: bogus lock_dir alias rejected');
    ok(!$viol->('lock_dir', '$LOCKS'),    'F4: allow-listed lock_dir accepted');
    ok(!$viol->('lock_dir', '/var/run/fetchconfig-locks'),
                                          'F4: literal allow-listed lock_dir accepted');
}

# --- F2: the mask sentinel always restores the stored secret -----------------
# option_spec() falls back to %COMMON_OPTS for a model missing from the
# catalog, and 'enable' is not in that set -- so a write-back keyed on
# $spec->{type} eq 'secret' stored the literal mask string as the password.
# The editor re-offers an unknown model as a selected "(unknown)" option, so
# this fired on an ordinary save, with no attacker involved.
{
    my $MASK = '\\__unchanged__/';
    ok(!defined main::option_spec('NOT_A_REAL_MODEL','enable'),
       'F2 precondition: unknown model has no spec for enable');
    ok( defined main::option_spec('cisco-ios','enable'),
       'F2 precondition: known model does have one');

    my $roundtrip = sub {
        my ($model) = @_;
        my $orig = [ { kind=>'device', id=>'sw1', host=>'10.0.0.1', model=>$model,
                       opts=>[['user','m'],['enable','REALENABLE'],['pass','REALPASS']] } ];
        my %FORM = (
            rec_count  => 1,
            r0_kind    => 'device', r0_model => $model,
            r0_id      => 'sw1',    r0_host  => '10.0.0.1',
            r0_opt_user => 'm', r0_opt_enable => $MASK, r0_opt_pass => $MASK,
        );
        no warnings 'redefine';
        local *CGI::param = sub {
            my ($s,$k)=@_;
            return (sort keys %FORM) if @_<2 || !defined $k;
            return $FORM{$k};
        };
        local *CGI::multi_param = sub { () };
        my ($recs) = main::reconstruct_records_from_form($orig);
        my %o = map { $_->[0] => $_->[1] } @{ $recs->[0]{opts} };
        return \%o;
    };

    my $known = $roundtrip->('cisco-ios');
    is($known->{enable}, 'REALENABLE', 'F2 control: known model keeps enable');
    is($known->{pass},   'REALPASS',   'F2 control: known model keeps pass');

    my $unknown = $roundtrip->('NOT_A_REAL_MODEL');
    is($unknown->{enable}, 'REALENABLE',
       'F2: unknown model keeps enable (not the literal mask)');
    is($unknown->{pass},   'REALPASS',
       'F2: unknown model keeps pass');
    isnt($unknown->{enable}, $MASK, 'F2: mask string is never stored as a secret');
}

# --- F1: per-site scope on the action-less ?dev= route -----------------------
# main()'s %dev_scoped guard is keyed on the action NAME, and the device page
# is reached with no action at all, so the guard never ran for it. These are
# source assertions: device_accessible() needs a live DB, so the runtime
# decision is covered by t/A0-sites.t -- what is guarded here is that the call
# is present in both handlers and cannot be dropped again.
{
    for my $sub (qw(show_backup_list show_backup_content)) {
        my ($body) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        ok(defined $body && length $body, "F1: found sub $sub");
        like($body, qr/device_accessible\s*\(\s*\$user\s*,\s*\$dev\s*\)/,
             "F1: $sub enforces per-site scope");
        # The check must precede the data access it protects.
        my $acc = defined $body ? index($body, 'device_accessible') : -1;
        my $use = defined $body
                ? ($sub eq 'show_backup_list' ? index($body, 'list_backups')
                                              : index($body, 'get_backup_content'))
                : -1;
        ok($acc >= 0 && $use >= 0 && $acc < $use,
           "F1: $sub checks scope before reading backup data");
    }
}

# --- F3: the logo handlers carry their own authorization ---------------------
# Tools is admin-only, but that was enforced only by the hidden menu and by
# show_tool_logo(); main() has no central authorization gate, so a forged POST
# reached these handlers directly.
{
    for my $sub (qw(do_upload_logo do_delete_logo)) {
        my ($body) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        ok(defined $body && length $body, "F3: found sub $sub");
        like($body, qr/user_may_use_tools\s*\(\s*\$user\s*\)/,
             "F3: $sub checks user_may_use_tools");
        # Must refuse before touching the report directory.
        my $chk = defined $body ? index($body, 'user_may_use_tools') : -1;
        my $act = defined $body ? index($body, 'report_directory')   : -1;
        ok($chk >= 0 && $act >= 0 && $chk < $act,
           "F3: $sub refuses before resolving report_dir");
    }
}

# Every other handler that writes through the Tools surface should already
# carry the same check -- a cheap guard against the next one forgetting.
{
    my @unguarded;
    for my $sub (qw(do_upload_logo do_delete_logo do_clear_login_failures
                    do_notes_orphan_delete)) {
        my ($body) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        next unless defined $body;
        push @unguarded, $sub
            unless $body =~ /user_may_use_tools|user_is_admin/;
    }
    is_deeply(\@unguarded, [], 'F3: no Tools write handler is left unguarded')
        or diag("unguarded: @unguarded");
}

# --- F5: option values are checked against their catalog type ---------------
# The editor renders each option with a widget derived from its spec (number
# field, on/off select, transport select). That is browser-side only; the save
# path never re-read the type, so a forged POST wrote any string.
{
    my @base = (['user','u'],['pass','p'],['repository','$REPO1'],['keep','5']);
    my $bad = sub {
        my ($k,$v,$model) = @_;
        $model = 'cisco-ios' unless defined $model;
        my @o = grep { $_->[0] ne $k } @base; push @o, [$k,$v];
        # validate_records returns an ARRAYREF of error strings.
        my $e = main::validate_records(
                    [{ kind=>'device', model=>$model, id=>'sw1',
                       host=>'10.0.0.1', opts=>\@o }]);
        # Count only errors naming the option under test, so an unrelated
        # complaint about the synthetic record cannot read as a pass.
        return scalar grep { /\Q$k\E/ } @$e;
    };

    # int
    ok(!$bad->('timeout','30'),   'F5 control: int accepts a whole number');
    ok( $bad->('timeout','abc'),  'F5: int rejects a non-number');
    ok( $bad->('timeout','-1'),   'F5: int rejects a negative');
    ok( $bad->('timeout','1e9'),  'F5: int rejects exponent notation');
    ok( $bad->('keep','99999999999999999999'), 'F5: int rejects an absurd magnitude');

    # enum_transport -- on a model that declares it. cisco-ios does not, and
    # there the value is correctly preserved as unrecognized instead.
    ok(!$bad->('transport','ssh','mediant-sbc'),
       'F5 control: transport accepts ssh');
    ok(!$bad->('transport','telnet','mediant-sbc'),
       'F5 control: transport accepts telnet');
    ok( $bad->('transport','PWN','mediant-sbc'),
       'F5: transport rejects an off-list value');
    ok(!$bad->('transport','PWN','cisco-ios'),
       'F5: transport on a model without it is preserved, not rejected');

    # debug (on/off), case-insensitively
    ok(!$bad->('debug','on'),     'F5 control: debug accepts on');
    ok(!$bad->('debug','OFF'),    'F5: debug accepts OFF (case-insensitive)');
    ok( $bad->('debug','BANANA'), 'F5: debug rejects an off-list value');

    # enum_timezone
    ok(!$bad->('timezone','hide'),   'F5 control: timezone accepts hide');
    ok( $bad->('timezone','SHOWME'), 'F5: timezone rejects an off-list value');

    # An option the model does not declare has no type to check, and the editor
    # deliberately preserves it as an "(unrecognized)" chip. That behaviour
    # must survive the fix -- this is the control that stops the validation
    # from being over-eager.
    ok(!$bad->('community','public'),
       'F5: an unrecognized option key is still preserved, not rejected');

    # Same for a model missing from the catalog: common options stay typed,
    # model-specific ones are preserved.
    ok( $bad->('timeout','abc','NOT_A_REAL_MODEL'),
       'F5: common options stay typed on an unknown model');
    ok(!$bad->('community','public','NOT_A_REAL_MODEL'),
       'F5: model-specific options preserved on an unknown model');

    # enum_report_logo lives on the email: line. valid_logo_name() was applied
    # when listing/uploading/serving a logo but not on save, so a traversal
    # path could be written into the table for fetchconfig to resolve.
    my $email_bad = sub {
        my ($k,$v) = @_;
        my $e = main::validate_records(
                    [{ kind=>'email', opts=>[['from','a@b'],['to','c@d'],[$k,$v]] }]);
        return scalar grep { /\Q$k\E/ } @$e;
    };
    ok(!$email_bad->('report_logo','logo.png'),
       'F5 control: a plain logo name is accepted');
    ok( $email_bad->('report_logo','../../../etc/passwd'),
       'F5: report_logo rejects a traversal path');
    ok( $email_bad->('report_days','abc'),
       'F5: int on the email line is typed too');
}

# --- F6: the repeatable-option index is bounded -----------------------------
# "<key>__<n>" carries n in the submitted field NAME, and it was used directly
# as an array subscript -- one crafted field pre-extended a Perl array to that
# length, costing hundreds of MB and seconds of CPU per request.
{
    cmp_ok(main::OPT_REPEAT_MAX_INDEX(), '>', 1000,
           'F6: repeat cap leaves room for the indices the editor emits');
    cmp_ok(main::OPT_REPEAT_MAX_INDEX(), '<', 1_000_000,
           'F6: repeat cap is small enough to bound allocation');

    my $orig = [ { kind=>'email', opts=>[['from','a@b'],['to','c@d']] } ];
    my %FORM = (
        rec_count => 1,
        r0_kind   => 'email',
        r0_opt_from => 'a@b', r0_opt_to => 'c@d',
        # One legitimate repeatable, one far past the cap.
        'r0_opt_report_hide__1000'      => 'keepme',
        'r0_opt_report_hide__100000000' => 'dropme',
    );
    my $t0 = time;
    my $recs;
    {
        no warnings 'redefine';
        local *CGI::param = sub {
            my ($s,$k)=@_;
            return (sort keys %FORM) if @_<2 || !defined $k;
            return $FORM{$k};
        };
        local *CGI::multi_param = sub { () };
        ($recs) = main::reconstruct_records_from_form($orig);   # list context
    }
    my $elapsed = time - $t0;
    cmp_ok($elapsed, '<=', 5, 'F6: a huge repeat index does not stall the request');

    my @hide = map { $_->[1] } grep { $_->[0] eq 'report_hide' } @{ $recs->[0]{opts} };
    ok(  (grep { $_ eq 'keepme' } @hide), 'F6: in-range repeatable value kept');
    ok( !(grep { $_ eq 'dropme' } @hide), 'F6: out-of-range repeat index dropped');

    cmp_ok(main::REC_MAX(), '<=', 100000, 'F6: rec_count cap tightened');
    like($src, qr/my \@all_params = \$cgi->param\(\);/,
         'F6: the parameter list is read once, not per record');
}

# --- F5b: unknown names/values are kept, but still checked for illegal input -
# Unknown models and unknown option keys are deliberately NOT rejected -- they
# are kept and labelled "(unknown)" / "(unrecognized)" so a device table
# written by a newer fetchconfig stays editable. That forward compatibility
# must not become a hole: the illegal-content checks still apply to them.
{
    my @base = (['user','u'],['pass','p'],['repository','$REPO1'],['keep','5']);
    my $errs = sub {
        my ($model, @extra) = @_;
        my $e = main::validate_records(
                    [{ kind=>'device', model=>$model, id=>'sw1',
                       host=>'10.0.0.1', opts=>[@base, @extra] }]);
        return $e;
    };

    # The forward-compatibility contract itself.
    ok(!@{ $errs->('NOT_A_REAL_MODEL') },
       'F5b: an unknown model is kept, not rejected');
    ok(!@{ $errs->('cisco-ios', ['brand_new_option','1']) },
       'F5b: an unknown option key is kept, not rejected');
    ok(!@{ $errs->('NOT_A_REAL_MODEL', ['brand_new_option','1']) },
       'F5b: both together are kept (newer device table stays editable)');

    # ... but illegal content in an UNKNOWN model name is still refused.
    for my $m ('bad model', 'bad=model', 'bad,model', 'bad"model', '') {
        my $shown = $m eq '' ? '(empty)' : $m;
        ok(scalar @{ $errs->($m) },
           "F5b: illegal model name '$shown' still rejected");
    }

    # ... and in an UNKNOWN option NAME. The character class is what stops an
    # unknown key carrying '=' or ',' and forging an extra key/value pair.
    for my $k ('bad key', 'bad=key', 'bad,key', 'bad"key') {
        ok(scalar @{ $errs->('cisco-ios', [$k,'x']) },
           "F5b: illegal option name '$k' still rejected");
    }

    # ... and in an UNKNOWN option VALUE: a newline would forge a second
    # device line in the table.
    for my $pair (["newline","a\nb"], ["carriage return","a\rb"], ["tab","a\tb"]) {
        my ($label,$v) = @$pair;
        ok(scalar @{ $errs->('cisco-ios', ['brand_new_option',$v]) },
           "F5b: $label in an unknown option value still rejected");
        ok(scalar @{ $errs->('NOT_A_REAL_MODEL', ['brand_new_option',$v]) },
           "F5b: $label rejected on an unknown model too");
    }

    # A comma or whitespace in a value is NOT rejected: serialize_opts quotes
    # it and parse_opts reads it back, so it round-trips intact. Confirm that
    # round-trip rather than asserting the absence of a check.
    ok(!@{ $errs->('cisco-ios', ['brand_new_option','a,b']) },
       'F5b: a comma in a value is allowed (quoted on write)');
    my $line = main::serialize_opts([['brand_new_option','a,b'],['user','u']]);
    my $back = main::parse_opts($line);
    my %got  = map { $_->[0] => $_->[1] } @$back;
    is($got{brand_new_option}, 'a,b',
       'F5b: ... and survives the serialize/parse round-trip intact');
    is(scalar @$back, 2,
       'F5b: ... without splitting into an extra option');
}

# The explanatory note must stay with the code, so the next audit does not
# re-flag the forward-compatibility decision as a missing check.
{
    like($src, qr/DELIBERATE, NOT AN OVERSIGHT/,
         'F5b: the rationale note is present in validate_records');
    like($src, qr/\(unrecognized\)/, 'F5b: note names the unrecognized label');
    like($src, qr/\(unknown\)/,      'F5b: note names the unknown label');
}

# --- L1: report delete/prune are admin-gated, server-side AND in the UI ------
# These were open to every logged-in user: the Reports page rendered the
# controls for everyone and neither handler checked a permission.
{
    for my $sub (qw(do_delete_report do_prune_reports)) {
        my ($body) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        ok(defined $body && length $body, "L1: found sub $sub");
        like($body, qr/user_may_use_tools\s*\(\s*\$user\s*\)/,
             "L1: $sub checks user_may_use_tools");
        my $chk = defined $body ? index($body, 'user_may_use_tools') : -1;
        my $act = defined $body ? index($body, 'report_directory')   : -1;
        ok($chk >= 0 && $act >= 0 && $chk < $act,
           "L1: $sub refuses before resolving report_dir");
    }
    # The buttons must also be hidden -- hiding is presentation, the handler
    # check above is the control, and we want both.
    my ($rep) = $src =~ /\nsub show_reports \{(.*?)\n\}\n/s;
    ok(defined $rep && length $rep, 'L1: found sub show_reports');
    like($rep, qr/my \$may_admin = user_may_use_tools\(\$user\);/,
         'L1: show_reports computes an admin flag');
    like($rep, qr/if \(\$may_admin\)/, 'L1: ... and gates the controls on it');
}

# --- L2: site codes reject the device-table separators ----------------------
# A site code is written into the device table as "site=<code>", so ',', '='
# and '#' would perturb how that line parses. Admin-only on both ends, but the
# value originates outside the device-table editor's own validation.
{
    for my $sub (qw(do_add_site do_edit_site)) {
        my ($body) = $src =~ /\nsub \Q$sub\E \{(.*?)\n\}\n/s;
        ok(defined $body && length $body, "L2: found sub $sub");
        like($body, qr/\$code\s*=~\s*\/\[,=#\]\//,
             "L2: $sub rejects ',' '=' and '#' in a site code");
    }
}

# --- L3: no-helper template rename is atomic ---------------------------------
# The fallback used to test -e $new and then call rename(). POSIX rename()
# replaces an existing target silently, so anything created in the gap was
# destroyed. link() fails if the target exists, closing the window.
{
    my ($body) = $src =~ /\nsub rename_template_file \{(.*?)\n\}\n/s;
    ok(defined $body && length $body, 'L3: found sub rename_template_file');
    like($body, qr/link\(\$old, \$new\)/, 'L3: fallback renames via link()');
    unlike($body, qr/unless \(rename\(\$old, \$new\)\)/,
           'L3: the check-then-act rename() is gone');

    # Drive it: the helper is bypassed when TEMPLATE_HELPER is unset.
    SKIP: {
        no warnings 'once';
        skip 'TEMPLATE_HELPER is set in this fixture', 4
            if defined $main::TEMPLATE_HELPER && $main::TEMPLATE_HELPER ne '';
        my $td = File::Temp::tempdir(CLEANUP => 1);
        open(my $f, '>', "$td/a.tmpl") or die $!; print $f "AAA\n"; close $f;
        open($f,    '>', "$td/a.tmpl.bak") or die $!; print $f "ABAK\n"; close $f;

        my ($ok, $msg) = main::rename_template_file("$td/a.tmpl", "$td/b.tmpl");
        ok($ok, 'L3: rename to a free name succeeds') or diag $msg;
        ok(-e "$td/b.tmpl" && !-e "$td/a.tmpl", 'L3: old name gone, new name present');
        ok(-e "$td/b.tmpl.bak", 'L3: the .bak came across');

        # An occupied target must be refused, and must NOT be overwritten.
        open($f, '>', "$td/c.tmpl") or die $!; print $f "CCC\n"; close $f;
        my ($ok2) = main::rename_template_file("$td/b.tmpl", "$td/c.tmpl");
        my $c = do { local $/; open(my $r,'<',"$td/c.tmpl") or die $!; <$r> };
        ok(!$ok2 && $c eq "CCC\n", 'L3: an existing target is refused, not clobbered');
    }
}

# --- L4: legacy download-right handlers are gone -----------------------------
{
    unlike($src, qr/sub do_set_download_full_report\b/, 'L4: handler removed');
    unlike($src, qr/sub do_set_download_full_config\b/, 'L4: handler removed');
    unlike($src, qr/action eq 'set_download_full_report'/, 'L4: not dispatched');
    unlike($src, qr/action eq 'set_download_full_config'/, 'L4: not dispatched');
    # The audit ACTION NAMES must survive -- do_user_save still emits them, and
    # dropping them would break continuity with rows already in the audit log.
    like($src, qr/'set_download_full_report'/, 'L4: audit label kept');
    like($src, qr/'set_download_full_config'/, 'L4: audit label kept');
}

# --- L5: \z anchors on the name/token validators -----------------------------
# Perl's $ also matches just before a trailing newline, so "a.png\n" satisfied
# /\.png$/ and slipped past these checks.
{
    ok(!main::valid_logo_name("a.png\n"),            'L5: logo name rejects a trailing newline');
    ok( main::valid_logo_name("a.png"),              'L5: ... and still accepts a clean one');
    ok(!main::template_upload_name_ok("x.tmpl\n"),   'L5: template name rejects a trailing newline');
    ok( main::template_upload_name_ok("x.tmpl"),     'L5: ... and still accepts a clean one');
    ok(!main::valid_report_name("report-a.html\n"),  'L5: report name rejects a trailing newline');
    ok( main::valid_report_name("report-a.html"),    'L5: ... and still accepts a clean one');
    ok(!main::valid_id("bob\n"),                     'L5: id rejects a trailing newline');
    ok( main::valid_id("bob"),                       'L5: ... and still accepts a clean one');
    ok(!main::valid_host("10.0.0.1\n"),              'L5: host rejects a trailing newline');
    ok( main::valid_host("10.0.0.1"),                'L5: ... and still accepts a clean one');
    ok( main::valid_host("sw1.example.com"),         'L5: ... and an FQDN');
}

# --- L6: an oversized POST is reported, not silently mistaken for empty ------
{
    my ($body) = $src =~ /\nsub handle_request \{(.*?)\n\}\n/s;
    ok(defined $body && length $body, 'L6: found sub handle_request');
    like($body, qr/cgi_error/, 'L6: handle_request consults cgi_error');
    like($body, qr/can\('cgi_error'\)/,
         'L6: ... guarded with can(), so any CGI-like object is safe');
    # The check must come before the request is dispatched.
    my $err = index($body, 'cgi_error');
    my $ses = index($body, 'SESSION_DIR');
    ok($err >= 0 && $ses >= 0 && $err < $ses,
       'L6: ... and refuses before doing any request work');
}

# --- L7: upload size hint reaches the browser, server stays authoritative ----
# An over-sized upload cannot be reported once it is under way: the server
# answers while the browser is still sending, and the connection is reset
# before the response is read, so the user sees the browser's own error page
# whatever ErrorDocument is set (Apache bug 17722). The only fix is to refuse
# before the request starts -- a convenience, NOT a control.
{
    is(main::UPLOAD_MAX_LOGO(),     100*1024, 'L7: logo cap 100 KB');
    is(main::UPLOAD_MAX_TEMPLATE(), 100*1024, 'L7: template cap 100 KB');
    is(main::UPLOAD_MAX_HEX(),     1024*1024, 'L7: hex cap 1 MB');

    # The three forms hand their cap to the browser.
    like($src, qr/-data_max_upload\s*=>\s*UPLOAD_MAX_LOGO/,
         'L7: logo form carries the cap');
    like($src, qr/data-max-upload="\} \. UPLOAD_MAX_TEMPLATE/,
         'L7: template form carries the cap');
    like($src, qr/data-max-upload="\} \. UPLOAD_MAX_HEX/,
         'L7: hex form carries the cap');

    # The handlers must use the SAME constants, or the hint drifts from the
    # rule it is advertising.
    like($src, qr/my \$limit = UPLOAD_MAX_LOGO;/,     'L7: logo handler uses the constant');
    like($src, qr/my \$limit = UPLOAD_MAX_TEMPLATE;/, 'L7: template handler uses the constant');
    like($src, qr/my \$limit = UPLOAD_MAX_HEX;/,      'L7: hex handler uses the constant');
    unlike($src, qr/my \$limit = \d+ \* 1024;/,
           'L7: no handler keeps its own literal cap');

    # The browser-side check exists and is labelled as advisory only.
    like($src, qr/data-max-upload/,            'L7: submit handler reads the attribute');
    like($src, qr/NOT a control/,              'L7: ... and says it is not a control');
    like($src, qr/Do not remove the server-side check because this exists/,
         'L7: ... and warns against removing the server-side check');
}

# --- L8: large-POST handling (encoding + pre-submit estimate) ----------------
# The device-table editor POSTs every field of every expanded row, and the
# whole request is bounded by $CGI::POST_MAX (and, under mod_fcgid, by
# FcgidMaxRequestLen). CGI.pm's start_form defaults to multipart/form-data,
# which costs ~86 bytes of framing PER FIELD -- on a large table that is
# megabytes of pure overhead for a form with no file input.
{
    # Both big forms must opt out of multipart explicitly, so the saving
    # cannot be lost to a CGI.pm default change.
    # q{} so Perl does not interpolate the $cgi in the pattern text.
    my $edit_pat = quotemeta(q{-id => 'edit-form'});
    my ($edit) = $src =~ /(start_form\([^;]*$edit_pat[^;]*;)/s;
    ok(defined $edit, 'L8: found the device-table editor form');
    like($edit, qr/application\/x-www-form-urlencoded/,
         'L8: editor form is url-encoded, not multipart');
    like($edit, qr/data_max_post/, 'L8: editor form carries the POST cap');

    my $bulk_pat = quotemeta(q{-id => 'bulk-form'});
    my ($bulk) = $src =~ /(start_form\([^;]*$bulk_pat[^;]*;)/s;
    ok(defined $bulk, 'L8: found the bulk-edit form');
    like($bulk, qr/application\/x-www-form-urlencoded/,
         'L8: bulk-edit form is url-encoded, not multipart');
    like($bulk, qr/data_max_post/, 'L8: bulk-edit form carries the POST cap');

    # The cap handed to the browser must be the server's own limit.
    like($src, qr/\Q-data_max_post => \E\$CGI::POST_MAX/,
         'L8: the cap comes from $CGI::POST_MAX, not a copy');

    # The guard and the estimator exist, with the 20% margin.
    like($src, qr/data-max-post/,            'L8: submit handler reads the attribute');
    like($src, qr/fcEstimatePostBytes/,      'L8: estimator present');
    like($src, qr/est \* 1\.2 > cap/,        'L8: 20% margin applied');
    like($src, qr/the server enforces \$CGI::POST_MAX regardless/,
         'L8: documented as advisory, server still enforces');
    # The upload forms must STAY multipart -- a file cannot be url-encoded.
    like($src, qr/start_multipart_form/,     'L8: logo upload stays multipart');
    like($src, qr/enctype="multipart\/form-data"/,
         'L8: template/hex uploads stay multipart');
}

done_testing();
