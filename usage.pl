use DBI;
use strict;
use warnings;
use Data::Dumper;

# this was the price per kwh ages ago
use constant price_per_kwh => 0.1617;

# Set DBI_DSN, DBI_USER and DBI_PASS
# I use DBD::ODBC of course
my $h = DBI->connect('dbi:ODBC:asus2', "sa", "easysoft");

my $s = q|select sum(watts) as watts, sum(watts) / 1000 * 0.1617 as cost,
	convert(varchar(10), dateadd(ss,unixtime,'1970-01-01'), 103) as "date"
	from home_electricity group by convert(varchar(10), dateadd(ss,unixtime,'1970-01-01'), 103)
	order by 3|;

my $r = $h->selectall_arrayref($s);
print Dumper($r);

open my $f, ">", "usage.csv";
$r = $h->selectall_arrayref($s);
foreach my $res (@$r) {
    print $f "$res->[0],$res->[1],$res->[2]\n";
}
close $f;


