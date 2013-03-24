# read/write serial port win32

use strict;
use warnings;

use Win32::SerialPort qw( :STAT 0.19 );

my $port = Win32::SerialPort->new('COM12');

my $time = time;

if( ! defined($port) ) {
	die("Can't open COM12: $^E\n");
}

my $outfd;
open ($outfd, ">>", "log.txt") or die "Failed to open output file - $!n";

my $output = select(STDOUT);
$|++;
select($outfd);
$|++;
select $output;

$port->initialize();

#$port->baudrate(19200);
$port->baudrate(57600);
$port->parity('none');
$port->databits(8);
$port->stopbits(1);
$port->write_settings();

$port->are_match("\n");


while(1) {
    my $char = $port->lookfor();
    if ($char) {
	#print "length=", length($char), "\n";
	$char =~ s/\xd//g;
	#print "length=", length($char), "\n";
	my $now = time;
	print $char, "\n";
	#chomp $char;
	my ($period_watts, $total_watts) = split(",", $char);
	if ($total_watts) {
	    print $outfd "$now,$period_watts,$total_watts\n";
	    print "$now,$period_watts,$total_watts\n";
	}
    }
}


$port->close();

exit(0);
