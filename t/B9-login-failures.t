use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

my ($c) = make_config(); load_cgi($c); main::read_config();
no warnings 'once', 'redefine';

# fmt_age
is(main::fmt_age(0),    '0s',       'fmt_age: 0');
is(main::fmt_age(45),   '45s',      'fmt_age: seconds');
is(main::fmt_age(192),  '3m 12s',   'fmt_age: minutes');
is(main::fmt_age(3864), '1h 04m',   'fmt_age: hours');

# Page: admin-only, audit-log look, filter bar + pagers + styled confirm + nav.
{
    local *main::csrf_field    = sub { '' };
    local *main::user_is_admin = sub { 1 };
    local *main::db_connect    = sub { bless {}, 'MDBLF' };
    local *main::page_head     = sub { '' };
    local *main::page_foot     = sub { '' };
    local *main::top_bottom_nav = sub { '[[TOPBOTTOM]]' };
    my $out = '';
    { open(my $fh,'>',\$out); my $sv=select($fh); main::show_login_failures('admin'); select($sv); }
    like($out, qr/tool-section-title">Login failures/, 'section title');
    like($out, qr/class="list audit-list"/,            'audit-log table style');
    like($out, qr/id="lf-kind".*?<option value="ip">IP.*?<option value="user">Account/s, 'Type dropdown: IP / Account');
    like($out, qr/id="lf-from".*id="lf-to"/s,          'From/To date filters');
    like($out, qr/ap-first.*ap-prev.*ap-next.*ap-last/s, 'First/Prev/Next/Last pager');
    like($out, qr/audit-pager-bottom/,                 'bottom pager too');
    like($out, qr/\[\[TOPBOTTOM\]\]/,                  'Top/Bottom nav included');
    like($out, qr/id="lf-reload"/,                     'Reload button');
    like($out, qr/<form[^>]*data-confirm="Delete all login-failure counters[^"]*"[^>]*data-confirm-danger="y"/,
         'Clear all FORM carries data-confirm (the interceptor reads it from the form)');
    like($out, qr/action=login_failures_data/,         'rows fetched from the data endpoint');
}

# Data endpoint: JSON rows, throttled flag, admin-only.
{
    local *main::user_is_admin = sub { 1 };
    local *main::db_connect    = sub { bless {}, 'MDBLF' };
    my $out = '';
    { open(my $fh,'>',\$out); my $sv=select($fh); main::show_login_failures_data('admin'); select($sv); }
    like($out, qr/"total":2/,                 'data: total count');
    like($out, qr/"keyval":"1\.2\.3\.4"/,     'data: IP row present');
    like($out, qr/"throttled":true/,          'data: 7-failure key flagged throttled');
    like($out, qr/"throttled":false/,         'data: 2-failure key not throttled');
    like($out, qr/"kind":"IP"/,               'data: kind label IP');
    like($out, qr/"kind":"Account"/,          'data: kind label Account');
}

# Non-admin refused (both page and data endpoint).
{
    local *main::db_connect    = sub { bless {}, 'MDBLF' };
    local *main::user_is_admin = sub { 0 };
    local *main::page_head     = sub { '' };
    local *main::page_foot     = sub { '' };
    my $pg = ''; { open(my $fh,'>',\$pg); my $sv=select($fh); main::show_login_failures('joe'); select($sv); }
    like($pg, qr/administrators only/, 'non-admin: page refused');
    my $dt = ''; { open(my $fh,'>',\$dt); my $sv=select($fh); main::show_login_failures_data('joe'); select($sv); }
    like($dt, qr/"forbidden"/,         'non-admin: data endpoint refused');
}

# Filter SQL is parameterized and maps the dropdown correctly.
{
    no warnings 'redefine';
    local *main::param_store = {};
    # drive login_failures_filter_sql via $cgi params
    local *CGI::param = sub { my ($s,$k)=@_; my %p=(f_kind=>'ip', f_from=>'2026-10-01', f_to=>'2026-10-08'); return $p{$k}; };
    my ($w,$b) = main::login_failures_filter_sql();
    like($w, qr/kind = 'ip'/,          'filter: kind=ip');
    like($w, qr/last_fail >= \?/,      'filter: from bound');
    like($w, qr/last_fail <  \(\?::date \+ 1\)/, 'filter: to end-of-day');
    is(scalar @$b, 2,                  'filter: two date binds, kind inlined safely');
}

# Wiring in the shipped source.
{
    my $src = do { open(my $fh,'<',cgi_path()) or die $!; local $/; <$fh> };
    like($src, qr/action eq 'tool_login_failures'/,   'viewer dispatched');
    like($src, qr/action eq 'login_failures_data'/,   'data endpoint dispatched');
    like($src, qr/action eq 'clear_login_failures'/,  'clear dispatched');
    like($src, qr/\bclear_login_failures\b.*reset_password/s, 'clear is state-changing');
    like($src, qr/\$su->\('Login failures',/,         'Tools menu entry');
}

done_testing();

package MDBLF;
sub new { bless {}, shift }
sub disconnect {}
sub selectrow_array {
    my ($s,$sql,@rest)=@_;
    return (2) if $sql =~ /count\(\*\) FROM login_attempts/;
    return ();
}
sub prepare { my ($s,$sql)=@_; return bless { sql=>$sql }, 'MDBLF::Sth' }
package MDBLF::Sth;
sub execute { 1 }
sub fetchall_arrayref {
    return [
        { kind=>'ip',   keyval=>'1.2.3.4', failures=>7, last_fail=>'2026-10-08 13:00:00', age_secs=>60 },
        { kind=>'user', keyval=>'bob',     failures=>2, last_fail=>'2026-10-08 12:50:00', age_secs=>660 },
    ];
}
