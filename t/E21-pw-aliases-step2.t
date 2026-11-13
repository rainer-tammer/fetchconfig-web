use strict; use warnings;
use Test::More;
use File::Spec;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# pw: credential aliases, Step 2 (fetchconfig-web 2.16.3): credential fields
# accept a $Alias reference OR a verbatim value, with first-character-only
# escaping and comma/space quoting (quote XOR escape). Aliases are shown/stored
# in clear and are never masked or redacted; a verbatim value that equals a
# defined alias may be folded to the alias on save (ALIAS_REPLACE_ON_SAVE).
# See fetchconfig-pw-alias-grammar-engine.md.
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

my $stub = File::Spec->catfile($fcp, 'fetchconfig.pl');
open($w,'>',$stub) or die $!; print $w "#!/usr/bin/perl\nexit 0;\n"; close($w); chmod 0755, $stub;

load_cgi($cfg); main::read_config();
$main::_pw_aliases_cache = undef;

# $SECRET_KEEP / $ALIAS_REPLACE_ON_SAVE are file-lexicals in the cgi; the mode is
# therefore driven through the config file (set_mode rewrites it and re-reads).
my $KEEP = '\\__unchanged__/';
sub set_mode {
    my ($mode) = @_;
    open(my $cr,'<',$cfg) or die $!; my @ln = grep { !/^\s*ALIAS_REPLACE_ON_SAVE\s*=/ } <$cr>; close($cr);
    open(my $cw,'>',$cfg) or die $!; print $cw @ln; print $cw "ALIAS_REPLACE_ON_SAVE = $mode\n"; close($cw);
    main::read_config();
    $main::_pw_aliases_cache = undef;
}

# --- alias table parsed by kind -------------------------------------------
is_deeply([main::pw_alias_names('user')], ['$NetUser'],              'pw_alias_names(user)');
is_deeply([main::pw_alias_names('pass')], ['$NetPass','$RoCommunity'],'pw_alias_names(pass) sorted');
ok( main::pw_alias_defined('$NetPass','pass'),  'pw_alias_defined pass-kind');
ok(!main::pw_alias_defined('$NetPass','user'),  'wrong-kind alias not defined for user slot');
ok(!main::pw_alias_defined('$Nope','pass'),     'undefined alias not defined');

# --- cred_parse_value: alias vs literal + first-char de-escape --------------
is_deeply([main::cred_parse_value('pass','$NetPass')], ['$NetPass','alias'], 'defined alias -> (name, alias)');
is_deeply([main::cred_parse_value('user','$NetUser')], ['$NetUser','alias'], 'user alias -> alias');
is_deeply([main::cred_parse_value('pass','$Nope')],    ['$Nope',undef],      'undefined $name -> literal');
is_deeply([main::cred_parse_value('pass','\\$abc')],   ['$abc',undef],       '\\$abc -> literal $abc');
is_deeply([main::cred_parse_value('pass','\\\\secret')],['\\secret',undef],  '\\\\secret -> literal \\secret');
is_deeply([main::cred_parse_value('pass','"a,b"')],    ['a,b',undef],        'quoted "a,b" -> literal a,b');
is_deeply([main::cred_parse_value('pass','DOMAIN\\user')], ['DOMAIN\\user',undef], 'interior backslash untouched');
is_deeply([main::cred_parse_value('pass','ab$cd')],    ['ab$cd',undef],      '$ not first char -> literal');

# --- cred_serialize_value: alias bare / literal quote XOR escape ------------
is(main::cred_serialize_value('$NetPass','alias',0), '$NetPass',  'alias emitted bare');
is(main::cred_serialize_value('$abc',undef,0),       '\\$abc',    'literal leading $ -> escaped');
is(main::cred_serialize_value('\\secret',undef,0),   '\\\\secret','literal leading \\ -> escaped');
is(main::cred_serialize_value('a,b',undef,0),        '"a,b"',     'literal with comma -> quoted');
is(main::cred_serialize_value('my pass',undef,0),    '"my pass"', 'literal with space -> quoted (device line)');
is(main::cred_serialize_value('DOMAIN\\user',undef,0),'DOMAIN\\user','interior backslash emitted bare');
is(main::cred_serialize_value('$a,b',undef,0),       '"$a,b"',    'leading $ + comma -> quoted (not escaped)');

# --- round-trip: parse(serialize(x)) == x ----------------------------------
for my $pair (['$NetPass','alias'], ['$abc',undef], ['\\secret',undef],
              ['a,b',undef], ['DOMAIN\\user',undef], ['ab$cd',undef]) {
    my ($v,$m) = @$pair;
    my $tok = main::cred_serialize_value($v,$m,0);
    my ($v2,$m2) = main::cred_parse_value('pass',$tok);
    is($v2, $v, "round-trip value: $v");
    is(($m2//''), ($m//''), "round-trip meta: $v");
}

# --- masking: alias visible, literal masked, user never masked --------------
my $mk = main::mask_secrets('user=admin,pass=$NetPass,enable=realsecret');
like($mk, qr/pass=\$NetPass/,  'alias in pass= is NOT masked');
like($mk, qr/enable=\?\*\*\*\?/,'verbatim enable= IS masked');
like($mk, qr/user=admin/,      'user= is not masked');
like(main::mask_secrets('pass=realsecret'), qr/pass=\?\*\*\*\?/, 'verbatim pass= masked');
is(main::mask_secrets_opt('pass','$NetPass'), '$NetPass', 'mask_secrets_opt leaves alias visible');
is(main::mask_secrets_opt('pass','literal'),  $KEEP, 'mask_secrets_opt masks a literal secret');

# --- audit redaction: alias visible, literal redacted ----------------------
is(main::audit_redact('pass','$NetPass'), '$NetPass', 'audit keeps the alias visible');
is(main::audit_redact('pass','realsecret'), '***',    'audit redacts a literal secret');

# --- fold-on-save (ALIAS_REPLACE_ON_SAVE) ----------------------------------
set_mode('off');
{
    my $o = main::fold_cred_aliases([['pass','s3cr,et=1'],['user','backup']]);
    is_deeply($o, [['pass','s3cr,et=1'],['user','backup']], 'off: nothing folded');
}
set_mode('secrets');
{
    my $o = main::fold_cred_aliases([['pass','s3cr,et=1'],['user','backup']]);
    is_deeply($o->[0], ['pass','$NetPass','alias'], 'secrets: matching pass folded to alias');
    is_deeply($o->[1], ['user','backup'],           'secrets: user NOT folded');
}
set_mode('users');
{
    my $o = main::fold_cred_aliases([['pass','s3cr,et=1'],['user','backup']]);
    is_deeply($o->[0], ['pass','s3cr,et=1'],         'users: pass NOT folded');
    is_deeply($o->[1], ['user','$NetUser','alias'],  'users: matching user folded to alias');
}
set_mode('all');
{
    my $o = main::fold_cred_aliases([['pass','public'],['enable','nomatch']]);
    is_deeply($o->[0], ['pass','$RoCommunity','alias'], 'all: pass folded to community alias');
    is_deeply($o->[1], ['enable','nomatch'],            'all: non-matching value left verbatim');
}
set_mode('off');

# --- serialize device line: alias bare, literal escaped --------------------
my $line = main::serialize_opts([['user','$NetUser','alias'],['pass','$ecret'],['enable','a,b']]);
is($line, 'user=$NetUser,pass=\\$ecret,enable="a,b"', 'serialize_opts: alias bare, $literal escaped, comma quoted');

# --- editor render: credential control + snmp_level dropdown ----------------
my $h_alias = main::render_option_field('r0','cisco-ios','pass','$NetPass',0,'device');
like($h_alias, qr/class="cred-alias-sel"/,          'pass field: alias dropdown rendered');
like($h_alias, qr/<option value="\$NetPass" selected>/,'pass field: current alias selected');
like($h_alias, qr/not a real secret/,               'pass field: secret alias note');
my $h_lit = main::render_option_field('r0','cisco-ios','pass','plainpw',0,'device');
like($h_lit, qr/type="password"/,                   'verbatim pass field uses a password input');
like($h_lit, qr/\Q$KEEP\E/,                         'verbatim secret shows the keep placeholder');
my $h_user = main::render_option_field('r0','cisco-ios','user','admin',0,'device');
like($h_user, qr/not a real user name/,             'user field: user-kind alias note text');
like($h_user, qr/type="text"/,                      'user field is not masked (text input)');
my $h_lvl = main::render_option_field('r0','cisco-ios','snmp_level','authPriv',0,'device');
like($h_lvl, qr/<option value="authPriv" selected>authPriv/, 'snmp_level is a dropdown with the value selected');
like($h_lvl, qr/noAuthNoPriv/,                      'snmp_level offers noAuthNoPriv');

# --- source wiring ---------------------------------------------------------
my $src = do { local $/; open(my $f,'<',cgi_path()) or die $!; <$f> };
like($src, qr/ALIAS_REPLACE_ON_SAVE/,               'config key wired in the cgi');
like($src, qr/serialize_opts\(fold_cred_aliases\(normalize_dir_opts/,
     'device/default save path folds credential aliases');
like($src, qr/window\.FCWEB_PW_ALIASES/,            'pw alias names shipped to the editor JS');

done_testing();
