Arduino_power_monitor

A project to monitor the electricity used at my house. Includes the code for
the arduino and a schematic of the additional circuitry.

My first blog post was "Monitoring my house power with an Arduino and Perl" at http://www.martin-evans.me.uk/node/86. There are additions "New data shield" at http://martin-evans.me.uk/node/88 and then my final version "Version 2 electricty meter power logging" at http://martin-evans.me.uk/node/94.

The files in this repository are:

meter_reader_schematic1.png
  My first got at a meter reader before I got a data shield.
  I used meter.pl to log to a file the power usage.

meter1.pde
  arduino script which matches schematic 1 and meter1.pl.

meter.pl
  The Perl script to read the power usage from the arduino serial port.

meter_reader_schematic2.png
  My current schematic which matches the code in meter2.pde.

meter2.pde
  arduino script which matches schematic 2 but needs a data shield
  and an SD card.


