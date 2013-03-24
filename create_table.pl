#
# Drop any existing home_electricty table and create a new one
use DBI;
use strict;
use warnings;

# Set DBI_DSN, DBI_USER and DBI_PASS
# I use DBD::ODBC of course
my $h = DBI->connect();

eval {$h->do(q/drop table home_electricity/)};

$h->do(q/create table home_electricity (unixtime int, watts int)/);
