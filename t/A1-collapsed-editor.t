use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();

no warnings 'once';
# Build an original table: comment, default, three devices (two GMG, one HAM).
my $orig = [
    { kind=>'comment', raw=>'# c' },
    { kind=>'default', model=>'procurve-ssh', opts=>[['user','admin'],['pass','defpass']] },
    { kind=>'device', id=>'sw1', host=>'10.0.0.1', model=>'procurve-ssh',
      opts=>[['user','m'],['pass','SECRET1'],['comment','GMG'],['site','GMG']] },
    { kind=>'device', id=>'sw2', host=>'10.0.0.2', model=>'procurve-ssh',
      opts=>[['user','m'],['pass','SECRET2'],['comment','GMG'],['site','GMG']] },
    { kind=>'device', id=>'sw3', host=>'10.0.0.3', model=>'procurve-ssh',
      opts=>[['user','m'],['pass','SECRET3'],['comment','HAM'],['site','HAM']] },
];

# Simulate the collapsed editor form: only sw2 (idx 3) expanded+edited; the
# rest submit the "untouched" marker.
my %FORM = (
    rec_count => 5,
    r0_kind=>'comment',  r0_untouched=>1,
    r1_kind=>'default',  r1_untouched=>1,
    r2_kind=>'device',   r2_untouched=>1,
    r3_kind=>'device', r3_model=>'procurve-ssh', r3_id=>'sw2', r3_host=>'10.0.0.2',
    r3_opt_user=>'m', r3_opt_pass=>'\\__unchanged__/', r3_opt_comment=>'GMG-EDITED', r3_opt_site=>'GMG',
    r4_kind=>'device',   r4_untouched=>1,
);
{
    no warnings 'redefine';
    local *CGI::param = sub {
        my ($s,$k)=@_;
        return (sort keys %FORM) if @_<2 || !defined $k;
        return $FORM{$k};
    };
    local *CGI::multi_param = sub { () };
    my ($recs) = main::reconstruct_records_from_form($orig);
    is(scalar(@$recs), 5, 'all 5 records reconstructed from a mostly-collapsed form');
    my %dev = map { $_->{id} => $_ } grep { $_->{kind} eq 'device' } @$recs;
    my $pass = sub { my $r=shift; (map {$_->[1]} grep {$_->[0] eq 'pass'} @{$r->{opts}})[0] };
    my $cmt  = sub { my $r=shift; (map {$_->[1]} grep {$_->[0] eq 'comment'} @{$r->{opts}})[0] };
    is($pass->($dev{sw1}), 'SECRET1', 'untouched device sw1 keeps its password');
    is($pass->($dev{sw3}), 'SECRET3', 'untouched device sw3 keeps its password');
    is($cmt->($dev{sw1}),  'GMG',     'untouched device sw1 keeps its comment');
    is($pass->($dev{sw2}), 'SECRET2', 'expanded device sw2 restores masked password');
    is($cmt->($dev{sw2}),  'GMG-EDITED', 'expanded device sw2 applies the edited comment');
}


# --- from_form (Back to editor) renders devices expanded, preserving model ---
# Regression: the preview->editor round-trip must keep a generic device's
# device-model and its template model= (a reconstructed record's position can
# differ from disk, so a collapsed row's disk-indexed re-fetch showed the wrong
# device). render_device_expanded_row embeds the submitted values directly.
{
    my $r = { kind=>'device', id=>'sw1', host=>'h', model=>'generic',
              opts=>[['model','cisco-ios'],['transport','ssh'],['user','a'],
                     ['pass','p'],['site','GPN']] };
    my $h = main::render_device_expanded_row(7, $r);
    like($h, qr/dev-row dev-row-open/, 'expanded row is pre-opened');
    like($h, qr/<option value="generic" selected/, 'device Model stays generic');
    like($h, qr/<option value="cisco-ios" selected/, 'template model= preserved');
    like($h, qr/data-idx="7"/, 'row keeps its real table index');
}

# --- the generic model= option is labelled "model template" ---
{
    my $f = main::render_option_field('r1','generic','model','cisco-ios',0,'device','',1);
    like($f, qr/<label>model template\b/, 'generic model= labelled "model template"');
}


# --- from_form keeps default passwords and all devices (index alignment) ---
# After Preview -> Back to editor the records are rebuilt (and possibly
# compacted), so each must carry its original disk index (_form_idx) and
# rec_count must cover the highest index; otherwise the masked-secret write-back
# reads the wrong $orig record (wiping default passwords) and high-index devices
# are dropped.
{
    my $orig = [
        { kind=>'default', model=>'cisco-ios',
          opts=>[['user','admin'],['pass','DEFPASS'],['enable','DEFEN']] },
        { kind=>'device', id=>'sw1', host=>'h', model=>'cisco-ios',
          opts=>[['user','x'],['pass','DEVPASS']] },
    ];
    local %main::_FORM = (
        rec_count => 2,
        r0_kind=>'default', r0_model=>'cisco-ios', r0_opt_user=>'admin',
        r0_opt_pass=>'\\__unchanged__/', r0_opt_enable=>'\\__unchanged__/',
        r1_kind=>'device', r1_untouched=>1,
    );
    no warnings 'redefine';
    local *CGI::param = sub {
        my ($s,$k)=@_; return (sort keys %main::_FORM) if @_<2||!defined $k;
        return $main::_FORM{$k};
    };
    local *CGI::multi_param = sub { () };
    my ($recs) = main::reconstruct_records_from_form($orig);
    my ($def) = grep { $_->{kind} eq 'default' } @$recs;
    my $p = (map { $_->[1] } grep { $_->[0] eq 'pass' } @{$def->{opts}})[0];
    my $e = (map { $_->[1] } grep { $_->[0] eq 'enable' } @{$def->{opts}})[0];
    is($p, 'DEFPASS', 'default password preserved through from_form');
    is($e, 'DEFEN',   'default enable preserved through from_form');
    is($def->{_form_idx}, 0, 'default keeps its original disk index');
}

# --- edited marker (red dot) round-trips and only for actually-changed devices ---
{
    my $r_edit = { kind=>'device', id=>'sw1', host=>'h', model=>'generic',
                   opts=>[['model','cisco-ios'],['user','a'],['pass','p'],['site','GPN']],
                   _edited=>1 };
    my $r_plain = { kind=>'device', id=>'sw2', host=>'h', model=>'generic',
                    opts=>[['model','cisco-ios'],['user','a'],['pass','p'],['site','GPN']] };
    like(main::render_device_expanded_row(5,$r_edit),  qr/dev-row-open dev-edited/, 'edited device gets the dev-edited marker');
    unlike(main::render_device_expanded_row(6,$r_plain), qr/dev-edited/, 'unedited (merely opened) device has no marker');
}

# reconstruct carries _edited from the r{n}_edited form field
{
    my $orig = [ { kind=>'device', id=>'sw1', host=>'h', model=>'cisco-ios',
                   opts=>[['user','x'],['pass','P']] } ];
    local %main::_FORM = (
        rec_count => 1,
        r0_kind=>'device', r0_model=>'cisco-ios', r0_id=>'sw1', r0_host=>'h',
        r0_opt_user=>'x', r0_opt_pass=>'\__unchanged__/',
        r0_open=>1, r0_edited=>1,
    );
    no warnings 'redefine';
    local *CGI::param = sub { my($s,$k)=@_; return (sort keys %main::_FORM) if @_<2||!defined $k; return $main::_FORM{$k}; };
    local *CGI::multi_param = sub { () };
    my ($recs) = main::reconstruct_records_from_form($orig);
    is($recs->[0]{_edited}, 1, 'reconstruct carries _edited from the form');
}

done_testing();