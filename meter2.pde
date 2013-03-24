#include <EEPROM.h>
#include <Wire.h>
#include "RTClib.h"
#include <SdFat.h>
#include <SdFatUtil.h>
#include <avr/power.h>
#include <avr/sleep.h>

#define DEBUG 1

#ifdef DEBUG
# define DEBUGPL(a) Serial.println(a)
# define DEBUGP(a) Serial.print(a)
# define DEBUGPN(a,b) Serial.print(a,b)
#else
# define DEBUGPL(a)
# define DEBUGP(a)
# define DEBUGPN(a,b)
#endif

/* http://www.nongnu.org/avr-libc/user-manual/group__avr__power.html */

RTC_DS1307 RTC;
uint8_t today;

Sd2Card card;
SdVolume volume;
SdFile file;
SdFile root;
// filename to store data on SD card - format YYYYMMDD.csv\0
char filename[13];

const int  dataLedPin    =  4;  // LED indicating sensor data is received
const int  logLedPin     =  3;  // LED flashes during a log attemp

const int logInterrupt = 0; // ATmega 168 and 328 - interrupt 0 = pin 2, 1 = pin 3
const int interruptPin = 2;

uint32_t last_write; // millis when we last wrote a log entry
#define WRITE_DELAY 60 // wait this long between logging values
byte last_sensor_count; // the value of the sensor last time we checked
uint32_t last_data_led_on; // time we last turned the data led on

// count of pulses from the electricity meter in WRTIE_DELAY milliseconds
// a byte can hold 255 pulses and if we hit this in 1 minute we'd be
// consuming a hell of a lot. If WRITE_DELAY is more than a minute
// a byte might not be big enough but if we increase the size of the
// sensor storage type we'd have to protect all reads/writes to it
// from interrupts
volatile byte sensor = 0;  // Counts power pulses in interrupt, 1 pulse = 1 watt
unsigned long total = 0;  // Total power used today

int sleep_count = 0;

// store error strings in flash to save RAM
#define error(s) error_P(PSTR(s))

void error_P(const char* str) {
    PgmPrint("error: ");
    SerialPrintln_P(str);
    if (card.errorCode()) {
        PgmPrint("SD error: ");
        Serial.print(card.errorCode(), HEX);
        Serial.print(',');
        Serial.println(card.errorData(), HEX);
    }
    while(1);
}

// Write CR LF to a file
void writeCRLF(SdFile& f) {
    f.write((uint8_t*)"\r\n", 2);
}

// Write an unsigned number to a file
void writeNumber(SdFile& f, uint32_t n) {
    uint8_t buf[10];
    uint8_t i = 0;
    do {
        i++;
        buf[sizeof(buf) - i] = n%10 + '0';
        n /= 10;
    } while (n);
    f.write(&buf[sizeof(buf) - i], i);
}

// Write a string to a file
void writeString(SdFile& f, char *str) {
    uint8_t n;
    for (n = 0; str[n]; n++);
    f.write((uint8_t *)str, n);
}

// create the filename we will write to based on the current datetime
// we return a ptr to the null terminated string for the filename
char * create_file(DateTime d)
{
    uint8_t month, day;
    uint16_t year;
    uint32_t all = 0;
    char *name;
    uint8_t i = 5;

    // calculate YYYYMMDD
    year = d.year();
    month = d.month();
    day = d.day();
    all = (uint32_t)year * 10000;
    all += (uint32_t)month * 100;
    all += (uint32_t)day;

    filename[sizeof(filename) - 1] = '\0';
    filename[sizeof(filename) - 2] = 'v';
    filename[sizeof(filename) - 3] = 's';
    filename[sizeof(filename) - 4] = 'c';
    filename[sizeof(filename) - 5] = '.';
    do {
        i++;
        filename[sizeof(filename) - i] = all%10 + '0';
        all /= 10;
    } while (all);

    name = &filename[sizeof(filename) - i];

    // create (if necessary) the file and append
    file.open(&root, name, O_CREAT | O_WRITE | O_APPEND);
    if (!file.isOpen()) error ("file.create");

    return name;
}

void setup(void)
{
    char *fn; // filename
#ifdef DEBUG
    Serial.begin(57600);
#endif
    Wire.begin();
    RTC.begin();

    if (! RTC.isrunning()) {
        DEBUGPL("RTC is NOT running!");
        // following line sets the RTC to the date & time this sketch was compiled
        //RTC.adjust(DateTime(__DATE__, __TIME__));
    }
    DateTime now = RTC.now();

    today = now.day(); // store todays day

    // initialize the SD card
    if (!card.init())
        error("volume.init failed");

    // initialize a FAT volume
    if (!volume.init(&card)) error("volume.init failed");

    // open the root directory
    if (!root.openRoot(&volume)) error("openRoot failed");

    fn = create_file(now);
    DEBUGP("Writing to: ");
    DEBUGPL(fn);

    pinMode(dataLedPin, OUTPUT);    // LED interrupt indicator initialization
    pinMode(logLedPin, OUTPUT);

    last_write = now.unixtime();
    last_data_led_on = 0;

    pinMode(interruptPin, INPUT);
    // enable 20k pullup resistor:
    digitalWrite(interruptPin, HIGH);
    attachInterrupt(logInterrupt, interruptHandler, FALLING);
    interrupts(); // now setup, enable interrupts

    //22mA
    power_adc_disable(); // reduced by .3mA
    //power_timer0_disable(); // breaks if you disable this
    power_timer1_disable();
    power_timer2_disable(); // with these 2 21.4mA
    power_spi_disable(); // 20.9mA
    //power_twi_disable(); // 20.5 mA causes some sort of halt when writing to sd card
    //power_usart0_disable();  // causes some sort of halt when writing to sd card
}

void sleepNow()
{
    /* Now is the time to set the sleep mode. In the Atmega8 datasheet
     * http://www.atmel.com/dyn/resources/prod_documents/doc2486.pdf on page 35
     * there is a list of sleep modes which explains which clocks and
     * wake up sources are available in which sleep modus.
     *
     * In the avr/sleep.h file, the call names of these sleep modus are to be found:
     *
     * The 5 different modes are:
     *     SLEEP_MODE_IDLE         -the least power savings
     *     SLEEP_MODE_ADC
     *     SLEEP_MODE_PWR_SAVE
     *     SLEEP_MODE_STANDBY
     *     SLEEP_MODE_PWR_DOWN     -the most power savings
     *
     *  the power reduction management <avr/power.h>  is described in
     *  http://www.nongnu.org/avr-libc/user-manual/group__avr__power.html
     */

  // in IDLE mode the clocks run
  // In all other modes they do not run except the watchdog timer.
  //set_sleep_mode(SLEEP_MODE_PWR_SAVE);   // sleep mode is set here 8.6mA
  set_sleep_mode(SLEEP_MODE_PWR_DOWN);   // sleep mode is set here 7.7mA


  sleep_enable();          // enables the sleep bit in the mcucr register
                             // so sleep is possible. just a safety pin

  power_adc_disable();
  power_spi_disable();
  power_timer0_disable();
  power_timer1_disable();
  power_timer2_disable();

  sleep_mode();            // put the device to sleep

                             // THE PROGRAM CONTINUES FROM HERE AFTER WAKING UP
  sleep_disable();         // first thing after waking from sleep:
                            // disable sleep...
  power_all_enable();
}
void loop(void)
{
    unsigned long m_time;
    uint32_t ctime;

    DateTime now = RTC.now();
    m_time = now.unixtime();

    sleep_count++;

    if (sensor != 0 && (last_sensor_count != sensor)) {
        last_sensor_count = sensor;
        // flash the data LED
        digitalWrite(dataLedPin, HIGH);
        delay(50);
        digitalWrite(dataLedPin, LOW);
    }

    // reading/writing volatile data shared with an ISR needs to
    // be done with interrupts disabled unless the data can be read
    // in an atomic operation e.g., a byte
    if ( sensor != 0 ) {
    if ((m_time - last_write) > WRITE_DELAY) {
          last_write = m_time;
            digitalWrite(logLedPin, HIGH);
            Log();
            digitalWrite(logLedPin, LOW);
        }
    }
  // check if it should go asleep because of time
  if (sleep_count >= 0) {
      //Serial.println("Timer: Entering Sleep mode");
      delay(100);     // this delay is needed, the sleep
                      //function will provoke a Serial error otherwise!!
      sleep_count = 0;
      sleepNow();     // sleep function called here
  }
}

void Log()
{
    byte sensor_copy = sensor;

    sensor = 0;           // reset the watts count
    total += sensor_copy; // total watts counter

    DateTime now = RTC.now();
    if (now.day() != today) {
        // if day changed close old file and open a new one
        file.close();
        create_file(now);
        total = 0;  // reset total watts used today
    }
    // write time, watts, watts_total to SD
    writeNumber(file, now.unixtime());
    writeString(file, ",");
    writeNumber(file, sensor_copy);
    writeString(file, ",");
    writeNumber(file, total);
    writeCRLF(file);
    file.sync();

    DEBUGP(now.unixtime());
    DEBUGP(',');
    DEBUGPN(sensor_copy, DEC);
    DEBUGP(',');
    DEBUGPL(total);


}

// interrupt from interruptPin
// a pulse from the meter LED, just increment sensor count
// one pulse = 1 watt
// NB interrupts are automatically disabled in a ISR
void interruptHandler() {
  sensor += 1;
}

