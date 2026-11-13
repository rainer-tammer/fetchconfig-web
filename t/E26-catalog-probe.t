use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.17.13: existence probes use pg_catalog, not information_schema.
#
# On PostgreSQL 8.2 the information_schema.tables/columns views are very slow
# (a catalog-wide join with per-row ACL checks). A single such probe in the
# device-table editor measured ~340ms -- the largest part of the render. The
# runtime probes now hit pg_class / pg_attribute (indexed on name, sub-ms).
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

ok(main->can('db_table_exists'),  'db_table_exists helper defined');
ok(main->can('db_column_exists'), 'db_column_exists helper defined');

# --- functional: a fake handle that records the SQL and returns a canned row --
{
    package FakeDBH;
    sub new { bless { ret => $_[1], sql => undef, args => undef }, $_[0] }
    sub selectrow_array {
        my ($self, $sql, undef, @args) = @_;
        $self->{sql}  = $sql;
        $self->{args} = [@args];
        return $self->{ret} ? (1) : ();
    }
}

my $yes = FakeDBH->new(1);
is(main::db_table_exists($yes, 'device_inventory'), 1, 'table present => 1');
like($yes->{sql}, qr/pg_catalog\.pg_class/,     'db_table_exists queries pg_class');
unlike($yes->{sql}, qr/information_schema/,      'db_table_exists avoids information_schema');
is_deeply($yes->{args}, ['public', 'device_inventory'], 'schema defaults to public; table bound');

my $no = FakeDBH->new(0);
is(main::db_table_exists($no, 'nope'), 0, 'absent table => 0');
is(main::db_table_exists(undef, 'x'), 0, 'undef handle => 0 (never dies)');

my $col = FakeDBH->new(1);
is(main::db_column_exists($col, 'device_inventory', 'sysname'), 1, 'column present => 1');
like($col->{sql}, qr/pg_catalog\.pg_attribute/, 'db_column_exists queries pg_attribute');
unlike($col->{sql}, qr/information_schema/,      'db_column_exists avoids information_schema');
is_deeply($col->{args}, ['public', 'device_inventory', 'sysname'], 'schema/table/column bound');
is(main::db_column_exists(undef, 'x', 'y'), 0, 'undef handle => 0');

# --- the hot runtime paths no longer reference information_schema -------------
for my $sub (qw(device_inventory_summary_init show_inventory_dashboard
                dashboard_schema_state db_schema_version)) {
    my ($body) = $src =~ /sub $sub \{(.*?)\n\}/s;
    ok($body, "located $sub");
    unlike($body, qr/information_schema/, "$sub uses the fast pg_catalog probe");
    like($body, qr/db_(?:table|column)_exists/, "$sub calls a catalog helper");
}

# Migration .sql files legitimately keep information_schema (one-time DDL): not
# our concern here -- we only touched runtime probes.

done_testing();
