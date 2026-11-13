use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# pw: credential allow-list (engine 9.79+). Same security model as directory::
# parsed as its own verbatim kind, NEVER editable in the web UI, re-emitted
# from disk on save (never from form data), and "pw: pass" values masked on
# display. Step 1 = preserve on disk + mask.
# --------------------------------------------------------------------------

my ($cfg, $dir, $fcp) = make_config();
open(my $r,'<',$cfg) or die $!; my %kv;
while(<$r>){ chomp; my($k,$v)=split/\s*=\s*/,$_,2; $kv{$k}=$v if defined $v; } close($r);
my $table = $kv{DEVICE_TABLE};

open(my $w,'>',$table) or die $!;
print $w <<'DT';
# DEFAULT OPTIONS SECTION

# credentials

# credential allow list - must be directly edited on the server
pw: user $NetUser backup
pw: pass $NetPass "s3cr,et=1"
pw: pass $RoCommunity public
# credential allow list - must be directly edited on the server

cisco-ios sw1 10.0.0.1 user=x,pass=y
DT
close($w);

# minimal fetchconfig stub: no allowed dirs (so the directory: block is absent)
my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open($w,'>',$stub) or die $!;
print $w "#!/usr/bin/perl\nexit 0;\n";
close($w); chmod 0755, $stub;

load_cgi($cfg); main::read_config();

# --- parse: pw: lines get their own kind, verbatim -------------------------
my $recs = main::parse_device_table(do { open(my $f,'<',$table); local $/; <$f> });
my @pw = grep { $_->{kind} eq 'pw' } @$recs;
is(scalar(@pw), 3, 'three pw: records parsed as kind "pw"');
is($pw[0]{raw}, 'pw: user $NetUser backup', 'pw: line kept verbatim');
ok(!grep({ $_->{kind} eq 'other' && $_->{raw} =~ /^pw:/ } @$recs),
   'pw: lines are NOT mis-classified as "other"');

# --- pw_raw_block reads them straight from disk ----------------------------
my $raw = main::pw_raw_block();
is(scalar(@$raw), 3, 'pw_raw_block returns all three pw: lines');
like($raw->[1], qr/pw: pass \$NetPass "s3cr,et=1"/, 'pw_raw_block is verbatim (unmasked, for disk)');

# --- serialize: re-emits the armored credentials block FROM DISK -----------
# Pass records that contain NO pw records (as a reconstructed form would): the
# block must still appear, proving it comes from disk, not the form.
my $dev = { kind=>'device', model=>'cisco-ios', id=>'sw1', host=>'10.0.0.1',
            opts=>[['user','x'],['pass','y']] };
my $out = main::serialize_records([ $dev ]);
like($out, qr/# credentials/,                                   'serialized: # credentials header');
like($out, qr/# credential allow list - must be directly edited on the server\n/,
     'serialized: armor comment present');
my $armor = () = $out =~ /# credential allow list - must be directly edited on the server/g;
is($armor, 2, 'armor comment wraps the block (before and after)');
like($out, qr/pw: user \$NetUser backup/,                       'serialized: pw: user line (from disk)');
like($out, qr/pw: pass \$NetPass "s3cr,et=1"/,                  'serialized: pw: pass line verbatim to disk (real value)');
like($out, qr/pw: pass \$RoCommunity public/,                   'serialized: third pw line');

# round-trip stable: parse the serialized output, re-serialize, pw block identical
my $out2 = main::serialize_records(main::parse_device_table($out));
is(scalar(() = $out2 =~ /^pw:/mg), 3, 're-serialized still has exactly three pw: lines (no duplication)');

# --- masking: pw: pass values masked, pw: user left as-is ------------------
my $masked = main::mask_pw_pass(do { open(my $f,'<',$table); local $/; <$f> });
like($masked, qr/pw: user \$NetUser backup/,        'pw: user line is NOT masked (username only)');
like($masked, qr/pw: pass \$NetPass\s+\?\*\*\*\?/,  'pw: pass quoted value masked');
like($masked, qr/pw: pass \$RoCommunity\s+\?\*\*\*\?/, 'pw: pass bare value masked');
unlike($masked, qr/s3cr,et=1/,                      'no part of the quoted secret leaks');
unlike($masked, qr/\bpublic\b/,                     'the bare community value does not leak');
# the $alias stays visible (needed for Step 2)
like($masked, qr/\$NetPass/,                        'the $alias stays visible');

# mask_secrets also covers pw: pass (used by the editor Preview etc.)
like(main::mask_secrets('pw: pass $X secret123'), qr/\$X\s+\?\*\*\*\?/, 'mask_secrets masks pw: pass too');

# --- the raw "Device table" view masks ALL secrets (not just pw:) -----------
my $src = do { local $/; open(my $f,'<',cgi_path()) or die $!; <$f> };
like($src, qr/color_comment_lines\(mask_secrets\(\$content\)\)/,
     'Device table view masks every secret via mask_secrets');
like($src, qr/\(\?:directory\|credential\) allow list/,
     'the credential armor comment is highlighted like the directory one');

done_testing();
