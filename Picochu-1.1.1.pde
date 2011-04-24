#include <stdio.h>
#include <util/crc16.h>
#include <TinyGPS.h>
#include <OneWire.h>
#define EN  11
#define TX0 7
#define TX1 5

OneWire ds(9); // DS18x20 Temperature chip i/o One-wire

//Tempsensor variables
byte address0[8] = {
  0x28, 0x73, 0xCD, 0xF5, 0x2, 0x0, 0x0, 0xAE}; // External DS18B20 Temp Sensor
int temp0 = 0;

// gets temperature data from onewire sensor network, need to supply byte address, it'll check to see what type of sensor and convert
// appropriately
int getTempdata(byte sensorAddress[8]) {
  int HighByte, LowByte, TReading, SignBit, Tc_100, Whole;
  byte data[12], i, present = 0;

  ds.reset();
  ds.select(sensorAddress);
  ds.write(0x44,1);         // start conversion, with parasite power on at the end

  delay(3000);     // maybe 750ms is enough, maybe not
  // we might do a ds.depower() here, but the reset will take care of it.

  present = ds.reset();
  ds.select(sensorAddress);    
  ds.write(0xBE);         // Read Scratchpad

  for ( i = 0; i < 9; i++) {           // we need 9 bytes
    data[i] = ds.read();
  }
  LowByte = data[0];
  HighByte = data[1];
  TReading = (HighByte << 8) + LowByte;
  SignBit = TReading & 0x8000;  // test most sig bit
  if (SignBit) // negative
  {
    TReading = (TReading ^ 0xffff) + 1; // 2's comp
  }

  if (sensorAddress[0] == 0x10) {
    Tc_100 = TReading * 50;    // multiply by (100 * 0.0625) or 6.25
  }
  else { 
    Tc_100 = (6 * TReading) + TReading / 4;    // multiply by (100 * 0.0625) or 6.25
  }


  Whole = Tc_100 / 100;  // separate off the whole and fractional portions

  if (SignBit) // If its negative
  {
    Whole = Whole * -1;
  }
  return Whole;
}

TinyGPS gps;

char msg[120];
int count = 1;

uint16_t crccat(char *msg)
{
  uint16_t x;
  for(x = 0xFFFF; *msg; msg++)
    x = _crc_xmodem_update(x, *msg);
  snprintf(msg, 8, "*%04X\n", x);
  return(x);
}

void setup()
{
  // Setup the GPS serial port
  Serial.begin(9600);

  count = 1;

  // Set up the pins used to control the radio module and switch
  // it on

  pinMode(EN,  OUTPUT);
  pinMode(TX0, OUTPUT);
  pinMode(TX1, OUTPUT);
  digitalWrite(EN, HIGH);

  rtty_send(".... Starting PicoChu-1 MK2 ....\n");
}

void loop()
{
  long lat, lng;
  unsigned long time;

  /* Got any data yet? */
  if(Serial.available() <= 0) return;
  if(!gps.encode(Serial.read())) return;

  /* Yes, prepare the string */
  gps.get_position(&lat, &lng, NULL);
  gps.get_datetime(NULL, &time, NULL);
  int numbersats = 99;
  numbersats = gps.sats();


  snprintf(msg, 120,
  "$$PICOCHU-1,%i,%02li:%02li:%02li,%s%li.%05li,%s%li.%05li,%li,%i,%i",
  count++, time / 1000000, time / 10000 % 100, time / 100 % 100,
  (lat >= 0 ? "" : "-"), labs(lat / 100000), labs(lat % 100000),
  (lng >= 0 ? "" : "-"), labs(lng / 100000), labs(lng % 100000),
  gps.altitude() / 100,
  numbersats,
  getTempdata(address0)


  );

  /* Append the checksum, skipping the $$ prefix */
  crccat(msg + 2);

  /* Transmit it! */

  digitalWrite(EN, HIGH); /*Power on the ntx2*/
  rtty_send(msg);  /*Send the gps data*/

  if(count % 200 == 0)
  {
    int i;
    digitalWrite(EN, LOW); /*Power off the ntx2*/
    for(i = 0; i < 600; i++) delay(1000);
    digitalWrite(EN, HIGH); /*Power on the ntx2*/
  }
}

// --------------------------------------------------------------------------------- 
// RTTY Code 
// 
// Code to send strings via RTTY.  The RTTY parameters are defined by constants 
// below. 
// --------------------------------------------------------------------------------- 

// The number of bits per character (7), number of start bits (1), number of stop bits (2) 
// and the baud rate. 

#define ASCII 7  
#define START 1 
#define STOP 2 
#define BAUD 50 
#define INTER_BIT_DELAY (1000/BAUD) 

// rtty_send: sends a null-terminated string via radio to the ground trackers 
void rtty_send( char * s ) // The null-terminated string to transmit 
{ 
  char c; 
  while ( c = *s++ ) { 
    int i; 
    for ( i = 0; i < START; ++i ) { 
      rtty_bit(0); 
    } 

    int b;    
    for ( i = 0, b = 1; i < ASCII; ++i, b *= 2 ) { 
      rtty_bit(c&b); 
    } 

    for ( i = 0; i < STOP; ++i ) { 
      rtty_bit(1); 
    } 
  } 

  // Note that when idling RTTY specifies that it be in the 'mark' state (or 1).  This 
  // is achieved by the stop bits that were sent at the end of the last character.  
} 

// rtty_bit: sends a single bit via RTTY 
void rtty_bit(int b) // Send 0 if b is 0, 1 if otherwise 
{ 
  digitalWrite(TX0,(b>0)?HIGH:LOW); 
  digitalWrite(TX1,(b>0)?LOW:HIGH); 
  delay(INTER_BIT_DELAY); 
}


