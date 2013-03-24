use DBI;
use strict;
use warnings;
use Data::Dumper;

# this was the price per kwh ages ago
use constant price_per_kwh => 0.1617;

my @files;
if (!defined($ARGV[0])) {
	 @files = glob "*.csv";
	 print join(",", @files), "\n";
} else {
	 @files = $ARGV[0];
}

# Set DBI_DSN, DBI_USER and DBI_PASS
# I use DBD::ODBC of course
my $h = DBI->connect();

my $s = $h->prepare(q/insert into home_electricity (unixtime, watts) values(?,?)/);

foreach (@files) {
   open(my $fd, "<", $_) or die "failed to open $ARGV[0]";

   while(<$fd>) {
		  my @values = split(',', $_);
		  $s->execute($values[0], $values[1]);
   }
   close $fd;
}

$s = q|select sum(watts) as watts, sum(watts) / 1000 * 0.1617 as cost, convert(varchar(10), dateadd(ss,unixtime,'1970-01-01'), 103) as "date" from home_electricity group by convert(varchar(10), dateadd(ss,unixtime,'1970-01-01'), 103)|;

my $r = $h->selectall_arrayref($s);
print Dumper($r);
