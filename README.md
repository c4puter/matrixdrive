# I2C LED matrix driver firmware

This is firmware to convert an ATXMEGA8E5 into a simple, generic I2C LED matrix driver.
It has the following features:

- Up to 8 row lines, 16 column lines
- Four graphics modes for each LED: off, blink, dim, on
- Blink rate, scan rate configurable at runtime
- 7-bit slave address totally configurable by pullup resistors (or omit the resistors and it defaults to 0x39)
- Readout of internal temperature and supply voltage
- Low-power mode can be enabled at runtime: shuts down ADC and matrix scan, wake on I2C. Can leave a set of non-scanned LEDs (all one column or all one row) lit.

## I2C protocol

The I2C interface is register-based as usual.
All registers are sixteen bits long, and eight-bit addresses represent sixteen-bit words.
Registers are sent and received in **little-endian format**.
Multiple contiguous register locations may be written in a burst.
Note that both half-words must be written; a stop condition after the first half-word will discard it.

    Write protocol
    +---+------------+---+---+---------+---+----------+---+-----------+---+-----+---+
    | S | slave addr | W | A | address | A | low byte | A | high byte | A | ... | P |
    +---+------------+---+---+---------+---+----------+---+-----------+---+-----+---+
    
    Read protocol, simple (address already set)
    +---+------------+---+---+-------------+---+-------------+---+-----+---+
    | S | slave addr | R | A | data (recv) | A | data (recv) | A | ... | P |
    +---+------------+---+---+-------------+---+-------------+---+-----+---+
    
    Read protocol, combined (address set in same sequence)
    +---+------------+---+---+---------+---+----+
    | S | slave addr | W | A | address | A | rS |
    +---+--------+---+---+---+---------+---+----+--------+---+-----+---+
    | slave addr | R | A | data (recv) | A | data (recv) | A | ... | P |
    +------------+---+---+-------------+---+-------------+---+-----+---+
    
        A   acknowledge (0)         rS  repeated start
        P   stop                    S   start
        R   read (1)                W   write (0)

## Register addresses

### 0x00 through 0x0f: LED bitmap

Each address represents a column, with eight two-bit row values in it.

        +-------+-------+-------+-------+-------+-------+-------+-------+
     15 | ROW7H | ROW7L | ROW6H | ROW6L | ROW5H | ROW5L | ROW4H | ROW4L | 8
        +-------+-------+-------+-------+-------+-------+-------+-------+
      7 | ROW3H | ROW3L | ROW2H | ROW2L | ROW1H | ROW1L | ROW0H | ROW0L | 0
        +-------+-------+-------+-------+-------+-------+-------+-------+

    ROWnH..ROWnL:   11  on
                    10  blink
                    01  dim
                    00  off

### 0x20: main control flags

    +-------+-----------+-----------+--------+---------+---+---+---+
    | LP_EN | LP_ROW_EN | LP_COL_EN | ADC_EN | SCAN_EN | R | R | R |
    +---+---+---+---+---+---+---+---+--------+---------+---+---+---+
    | R | R | R | R | R | R | R | R |
    +---+---+---+---+---+---+---+---+

- `LP_EN` - write a 1 to this field to enter low-power mode. Chip will go to sleep, and wake on I2C address match.
- `LP_ROW_EN`, `LP_COL_EN` - when in low-power mode, or when `SCAN_EN` is zero, continue displaying one row or one column of LEDs. Can be programmed in the same operation as `LP_EN`. `LP_ROW_EN` and `LP_COL_EN` are mutually exclusive; setting both is equivalent to setting neither.
- `ADC_EN` - run the ADC to measure temperature and VCC. If zero, the output registers for those values will continue to give the last reading that completed (or all zeros if no reading has been performed since startup). Ignored in low-power mode.
- `SCAN_EN` - operate the LED matrix. Set to 1 for normal operation. If this bit is cleared while scanning, the matrix will be shut down (rather than freezing at whichever row was active at the moment), then the `LP_ROW_EN` and `LP_COL_EN` bits will be read, and if exactly one is set, the matrix will statically display one row or one column.
- `R` - reserved. Always write to zero; read value is undefined.

### 0x30: static display bitmap

This register holds the bitmap to be displayed on a single row or column in static mode (low-power or no scan).
If both or neither of `LP_ROW_EN` and `LP_COL_EN` is set (i.e., they are not mutually exclusive), no static bitmap will be displayed and this register will be ignored.

Note that because the display is static, there are no options for blinking or dimming.

    If exclusively LP_ROW_EN is set in 0x20 (main control flags):
    +-------+-------+-------+-------+-------+-------+------+-------+
    | COL15 | COL14 | COL13 | COL12 | COL11 | COL10 | COL9 | COL 8 |
    +-------+-------+-------+-------+-------+-------+------+-------+
    | COL7  | COL6  | COL5  | COL4  | COL3  | COL2  | COL1 | COL 0 |
    +-------+-------+-------+-------+-------+-------+------+-------+

    If exclusively LP_COL_EN is set in 0x20 (main control flags):
    +---+---+---+---+---+---+---+---+
    | R | R | R | R | R | R | R | R |
    +---+--++---+-+-+---++--+---+---+--+------+------+------+
    | ROW7 | ROW6 | ROW5 | ROW4 | ROW3 | ROW2 | ROW1 | ROW0 |
    +------+------+------+------+------+------+------+------+

### 0x31: static display address

This register holds the row number (if `LP_ROW_EN` is set) or column number (if `LP_COL_EN` is set) of the row or column to be displayed statically.

    If exclusively LP_ROW_EN is set in 0x20 (main control flags):
    +---+---+---+---+---+---+---+---+
    | R | R | R | R | R | R | R | R |
    +---+---+---+---+---+---+---+---+---+-------+
    | R | R | R | R | R | nROW2 | nROW1 | nROW0 |
    +---+---+---+---+---+-------+-------+-------+

    If exclusively LP_COL_EN is set in 0x20 (main control flags):
    +---+---+---+---+---+---+---+---+
    | R | R | R | R | R | R | R | R |
    +---+---+---+---+---+---+---+---+-------+-------+
    | R | R | R | R | nCOL3 | nCOL2 | nCOL1 | nCOL0 |
    +---+---+---+---+-------+-------+-------+-------+

### 0x40: scan rate

This register holds the scan rate, as the number of microseconds between one row and the next. The refresh rate will then be equal to:

                           1
    f_refresh = -----------------------
                8 × 1µs × value of 0x40

If this register is set below the minimum scan period, scan will commence *at* the minimum scan period.

TODO: document the minimum value for this register.

### 0x41: blink rate

This register holds the blinking period for any LEDs set to blink, in milliseconds. Note that blinking is achieved by alternating between ON and OFF in separate scans. If this is set to a value lower than twice the total refresh rate, behavior is undefined.

### 0x50: temperature value

This register holds the last measured temperature of the device, in sixteen-bit signed integer degrees Celsius. Temperature measurement frequency is not defined, but is guaranteed to be at least 1 Hz (and may be significantly higher, and not fixed). See the Atmel ATXMEGA8E5 datasheet for accuracy specifications; two-point calibration is performed.

### 0x51: power supply value

This register holds the last measured supply voltage of the device, in sixteen-bit signed integer millivolts. Voltage measurement frequency is not defined, but is guaranteed to be at least 1 Hz (and may be significantly higher, and not fixed). See the Atmel ATXMEGA8E5 datasheet for accuracy specifications for measurement of Vcc/10 vs the internal bandgap reference.

## Pinout

                        +----------+
            V+      ----| 17     6 |---- ROW0 / ADDR0   (PA0)
            V+      ----| 32     5 |---- ROW1 / ADDR1   (PA1)
                        |        4 |---- ROW2 / ADDR2   (PA2)
                        |        3 |---- ROW3 / ADDR3   (PA3)
                        |        2 |---- ROW4 / ADDR4   (PA4)
                        |       31 |---- ROW5 / ADDR5   (PA5)
            PDI_D   ----|  7    30 |---- ROW6 / ADDR6   (PA6)
     NRST / PDI_C   ----|  8    29 |---- ROW7           (PA7)
                        |          |
                        |       14 |---- COL0           (PC2)
                        |       13 |---- COL1           (PC3)
    (PC0)   SDA     ----| 16    12 |---- COL2           (PC4)
    (PC1)   SCL     ----| 15    11 |---- COL3           (PC5)
                        |       10 |---- COL4           (PC6)
                        |        9 |---- COL5           (PC7)
                        |       28 |---- COL6           (PD0)
                        |       27 |---- COL7           (PD1)
                        |       26 |---- COL8           (PD2)
                        |       25 |---- COL9           (PD3)
                        |       24 |---- COL10          (PD4)
                        |       23 |---- COL11          (PD5)
                        |       22 |---- COL12          (PD6)
                        |       21 |---- COL13          (PD7)
            GND     ----|  1    20 |---- COL14          (PR0)
            GND     ----| 18    19 |---- COL15          (PR1)
                        +----------+

The combined `ROWn / ADDRn` pins set the address through pullup resistors, which should have a nominal value between 10k and 200k. Bits with pullup are 1, bits without pullup are 0. With no pullups, the default address is as mentioned above (as 0x00 is a reserved address).

For a preprogrammed chip (which I currently have no plans to offer, but hey, you never know...), pins `PDI_D` and `PDI_C` may be left disconnected. If `PDI_C` is to be used for its alternative function as a reset pin, a stronger external pullup (around 10k) should be added unless the trace connected to this pin is short.
