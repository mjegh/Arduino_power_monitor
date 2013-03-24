const int  dataLedPin    =  4;  // LED indicating sensor data is received
const int  logLedPin     =  5;  // LED flashes during a log attemp

const int logInterrupt = 1; // ATmega 168 and 328 - interrupt 0 = pin 2, 1 = pin 3
const int interruptPin = 3;

#define LOOPDELAY 60000

// count of pulses from the electricity meter in LOOPDELAY ms
// a byte can hold 255 pulses a minute and if we hit this we'd be
// consuming a hell of a lot. If LOOPDELAY is more than a minute
// a byte might not be big enough but if we increase the size of the
// sensor storage type we'd have to protect all reads/writes to it
// from interrupts - a byte is all that can be read/written in a single instruction
volatile byte sensor = 0;  // Counts power pulses in interrupt, 1 pulse = 1 watt
unsigned long total = 0;  // Total power used since the sketch started ???
//unsigned long last_reading = 0;


void setup(void)
{
  Serial.begin(19200);	// opens serial port, sets data rate to 19200 bps


  pinMode(dataLedPin, OUTPUT);    // LED interrupt indicator initialization
  pinMode(logLedPin, OUTPUT);

  pinMode(interruptPin, INPUT);
  // enable 20k pullup resistor:
  digitalWrite(interruptPin, HIGH);
  attachInterrupt(logInterrupt, interruptHandler, FALLING);
  interrupts();

  Serial.println("Start");
}

void loop(void)
{
  // flash the data LED
  digitalWrite(dataLedPin, HIGH);
  delay(50);
  digitalWrite(dataLedPin, LOW);

  // reading/writing volatile data shared with an ISR needs to
  // be done with interrupts disabled unless the data can be read
  // in an atomic operation e.g., a byte
  if( sensor != 0 ) {
     digitalWrite(logLedPin, HIGH);
     Log();
     digitalWrite(logLedPin, LOW);
     //last_reading = sensor;
  } else {
      Serial.println(sensor, DEC);
  }

  // wait a while - interrupts do fire during delay
  delay(LOOPDELAY);
}

void Log()
{
    unsigned long sensor_count;
    uint8_t oldSREG = SREG;   // save interrupt register
    cli();                    // prevent interrupts while accessing the count
    sensor_count = sensor; //get the count from the interrupt handler
    sensor = 0;           //reset the watts count
    //last_reading = 0;
    SREG = oldSREG;           // restore interrupts

    total += sensor_count; //total watts counter
    Serial.print(sensor_count, DEC);
    Serial.print(',');
    Serial.println(total);
}

// interrupt from interruptPin
// a pulse from the meter LED, just increment sensor count
// one pulse = 1 watt
// NB interrupts are automatically disabled in a ISR
void interruptHandler() {
  sensor += 1;
}