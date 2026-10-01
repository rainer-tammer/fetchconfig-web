use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);

my ($cfg) = make_config();
load_cgi($cfg); main::read_config();

# rest-of-line verbatim parse (regex with spaces, commas, parens)
my $tbl = "email: from=a\@b,to=c\@d,smtp=s\n"
        . "email: report_hide=(?<=wpa-passphrase )\\S+\n"
        . "email: report_hide=key \\S+, more stuff\n";
my $recs = main::parse_device_table($tbl);
my @hide;
for my $r (@$recs) { next unless $r->{kind} eq 'email';
    for my $p (@{$r->{opts}}) { push @hide, $p->[1] if $p->[0] eq 'report_hide'; } }
is(scalar(@hide), 2, 'two report_hide parsed across lines');
is($hide[0], '(?<=wpa-passphrase )\\S+', 'first regex verbatim');
is($hide[1], 'key \\S+, more stuff', 'second regex verbatim (space + comma preserved)');

# duplicate on one line -> parse_error, line ignored
my $r2 = main::parse_device_table("email: report_hide=aaa report_hide=bbb\n");
ok((grep { $_->{kind} eq 'parse_error' } @$r2), 'two report_hide on one line -> parse_error');
ok(!(grep { $_->{kind} eq 'email' } @$r2), 'the bad line is not kept as an email record');

# serialize: each report_hide on its own line, verbatim; others on main line
my $out = main::serialize_records([ { kind=>'email',
    opts=>[['from','a'],['report_hide','(?<=x )\\S+'],['report_hide','key \\S+']] } ]);
my @el = grep { /^email:/ } split /\n/, $out;
is(scalar(@el), 3, 'three email lines (main + two report_hide)');
like($el[0], qr/^email: from=a$/, 'main email line');
is($el[1], 'email: report_hide=(?<=x )\\S+', 'report_hide line 1 verbatim');
is($el[2], 'email: report_hide=key \\S+', 'report_hide line 2 verbatim');

# validation: bad regex rejected, good accepted
ok( grep(/invalid regular expression/, @{ main::validate_records([ { kind=>'email', opts=>[['report_hide','(unclosed']] } ]) }),
    'bad regex rejected on save');
ok(!grep(/invalid regular expression/, @{ main::validate_records([ { kind=>'email', opts=>[['report_hide','(?<=wpa-passphrase )\\S+']] } ]) }),
    'valid regex accepted');

# editor renders repeatable indexed fields
my $card = main::render_record_card('rk', { kind=>'email',
    opts=>[['from','a'],['report_hide','rx1'],['report_hide','rx2']] }, 'email');
my @names = $card =~ /name="(rk_opt_report_hide__\d+)"/g;
is_deeply(\@names, ['rk_opt_report_hide__0','rk_opt_report_hide__1'], 'two indexed report_hide inputs');


# mask_secrets is an on/off email option
my $ms = main::render_option_field('rk','email','mask_secrets','on',1);
like($ms, qr/<select/, 'mask_secrets renders as a select');
like($ms, qr/value="off"/, 'mask_secrets has off option');


# bracket-balance: a stray trailing } (valid-to-Perl but a typo) is rejected
ok( grep(/unbalanced brackets|stray closing/, @{ main::validate_records([ { kind=>'email', opts=>[['report_hide','(?<=^key )[0-9a-f]{16,}}']] } ]) }),
    'stray trailing } in report_hide rejected');
ok(!grep(/unbalanced|invalid/, @{ main::validate_records([ { kind=>'email', opts=>[['report_hide','[0-9a-f]{16,}']] } ]) }),
    'valid quantifier brace accepted');
is(main::regex_bracket_problem('(a(b)c)'), '', 'balanced groups ok');
like(main::regex_bracket_problem('foo)bar'), qr/unmatched/, 'stray ) flagged');
is(main::regex_bracket_problem('a]b'), '', 'lone literal ] not flagged');

done_testing();
