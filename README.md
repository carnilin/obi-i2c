# About

Simple I<sup>2</sup>C Master implementation with an OBI protocol wrapper, both written in SystemVerilog.<br><br>
I<sup>2</sup>C Master module implementation was taken from:<br> 
> Chu, P. P. (2018). FPGA prototyping by SystemVerilog examples: Xilinx MicroBlaze MCS SoC edition (2nd ed.). Wiley.


# Registers

Let B be the base address the OBI I<sup>2</sup>C device is assigned to. The register map is as follows:

```
B + 0 -- Status Register
B + 4 -- Data Register
B + 8 -- Speed Register
```

All registers are 32-bit.

### Status Register

This <b>read-only</b> register is  and is used to store the status values of the I<sup>2</sup>C master device and the values retrieved from I<sup>2</sup>C slave devices in a read operation. With bit 31 being the left-most bit, the meaning of the bits is as follows:

```
[31:10] -- Hard Wired To 0
[9]     -- Ready
[8]     -- Acknowledge
[7:0]   -- Data
```

The I<sup>2</sup>C Ready signal on bit 9 is used to indicate that the I<sup>2</sup>C Master is ready to accept new instructions from the CPU. This bit should be checked in driver functions before writing any data to the Data or Speed Register, typically in a "while !" loop.<br>

Bits 7-0 hold the data read from the <b>last issued</b> read operation. Reading the register does not clear the stored data, but issuing a new write command after a read command overwrites the Status Register data with the new write data. This means that any data received from a read command should be read immediately after the command is done. Bit 8 holds the ackowledge bit received from the slave device in a write operation. 

### Data Register
This register drives the command and data inputs to the I<sup>2</sup>C Master module. Writing into this register is the primary way to send/receive data over I<sup>2</sup>C. With bit 31 being the left-most bit, the meaning of the bits is as follows:

```
[31:11] -- Unused
[10:8]  -- Command
[7:0]   -- Data
```

Bits 10-8 are the three command bits that select the action the I<sup>2</sup>C Master should perform. There are 5 different commands:

```
START   = 3'b000;
WRITE   = 3'b001;
READ    = 3'b010;
STOP    = 3'b011;
RESTART = 3'b100;
```

WRITE and READ commands can only be performed after a START or RESTART command was given but before a STOP command is given. The WRITE command sends the data from bits 7-0 to the I<sup>2</sup>C Bus. The I<sup>2</sup>C Master begins executing a new command the moment it is written into the Data Register, i.e. without delay. During execution, the Ready bit in the Status Register will be 0, which indicates to the CPU that it should wait before writing to the Data Register.

### Speed Register

The speed register is used to control the I<sup>2</sup>C frequency, that the I<sup>2</sup>C Master communicates with. With bit 31 being the left-most bit, the meaning of the bits is as follows:

```
[31:16] -- Unused
[15:0]  -- Divisor
```

The 16-bit divisor value is intepreted as the amount of system clock periods that represents a quarter of an I<sup>2</sup>C clock period. Let $D$ be the Divisor value, $f_{i2c}$ the frequency of I<sup>2</sup>C communication we want to set and $f_{sys}$ the frequency of the system clock. The values are related by the equation
```math 
D = \dfrac{f_{sys}}{4 \times f_{i2c}}
```
