# TSILL Usb

by Till Straumann, 2023.

## Introduction

TSILL Usb is a versatile and generic USB-2-device implementation in
VHDL supporting an ULPI-standard interface (using an off-the shelf ULPI
PHY chip).

The main use-case are FPGA applications which benefit from a high- or
full-speed USB-2 interface.

A few generic function classes (CDC-ACM, CDC-ECM) are implemented which
can be connected to the generic core IP. USB descriptors can be created
using a python tool.

An example design for the Digilent-ZYBO board is provided which instantiates
the USB-2 core as well as some functions (including an example for isochronous
transfers) is included.

## What About USB-3

To date, no Xilinx-FPGA family MGT supports the USB-3 standard; therefore,
no effort has been made to suport USB-3. However, for many applications
USB-2 still provides attractive medium-speed connectivity for data transfer
and/or management tasks and at the same time can supply power (USB-C) over
a single cable.

## License

TSILL Usb is released under the [European-Union Public
License](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12)

## Features

The Usb2Core implements the following features:

 - Standard ULPI interface in Output- and Input-clock mode. Note, however,
   that I have experienced [strange problems](./doc/PROBLEMS.md) when trying
   to operate a `USB3340` in Input-clock mode. When I added a crystal to
   the board and strapped the device for Output-clock mode these problems
   disappeared!

 - Optionally provides access to ULPI-PHY registers via dedicated port for
   special use cases.

 - Speed negotiation (device starts as full-speed and tries to negotiate
   high-speed); low-speed is currently *not supported*.

 - Extensible Endpoint-Zero implementation. The endpoint handles the standard
   requests (such as `SET_ADDRESS`, `GET_DESCRIPTOR` etc.) but also features
   interface ports that allow the application to handle class- or vendor-
   specific requests.

 - Handles the details of USB-2 transfers (such as retransmission, CRCs,
   (de-)fragmenting from/to max. packet size etc.) and (de-)multiplexes
   transfers to individual endpoints as (optionally) framed byte-streams.

 - Descriptors are usually hard-coded into the application. Optionally, the
   descriptors can be stored in block-ram and tweaked by the application
   (no structural changes must be performed; this is intended, e.g. for
   tweaking an ethernet MAC address or other details.

 - Synchronous design; all signals are synchronous to the ULPI clock;
   endpoints may use an included FIFO to decouple clock domains. The
   featured functions all use such a FIFO which may be configured for
   asynchronous operation.

 - A tool written in Python is provided which makes assembling descriptors
   easy.

 - Example constraints for the ULPI interface (for clock-output and clock-
   input modes).

In addition to the `Usb2Core` a few standard functions which implement
standard USB device classes are provided. Compliant host-OS drivers should
support these functions out of the box (tested under linux).

 - CDC ACM function. This function presents a simple FIFO interface to the
   FPGA client firmware. The CDC ACM *LineState* and *SendBreak* capabilites
   are supported and accessible from dedicated interface ports.

     On the host this function can be accessed as an ordinary `tty` device.
     (Alternatively, the function may, e.g., be detached from the kernel
     driver and accessed directly using `libusb`.)
   
 - CDC ECM function. This function presents a simple FIFO interface to the
   FPGA client firmware and is recognized as an ethernet device on the host.
   This allows host software to leverage the power of the network stack
   (provided that some sort of networking is also implemented in the FPGA).

 - BADD Speaker class audio function. This is mainly demonstrating the
   implementation of an isochronous endpoint pair. Audio played on the host
   (under linux: using the vanilla `snd-usb-audio` driver) is converted
   into a `i2s` stream in the FPGA and forwarded to an audio-codec.  

The TSILL Usb package also comes with an example design for the Digilent
ZYBO (first version) development board which features a Zynq-XC7Z010 device.
While this board is already old - it is the one I have and porting the design
to its successor or a similar one should be straightforward.

 - KiCAD hardware-design of an extension board hosting a USB connector
   and (USB3340) ULPI PHY device. The board uses 3 PMOD connector sites.

 - Instantiates all available functions.

     - ACM can sink/source data for throughput measurements.
     - ECM Ethernet function.
     - BADD Speaker function forward `i2s` stream to the on-board SSM2603
       audio coded.

 - Demo software

     - Application using libusb for exercising max. throughput.
     - A trivial demo driver which implements an ethernet device
       *on the Zynq target* interfacing to the ECM FIFO is provided.
       This demonstrates and exercises the ECM ethernet function by
       connecting the Zynq-linux network stack to the host's networking.

## Usb2Core

The Usb2Core aggregates all the standard components necessary to provide
core functionality:

 - ULPI PHY Interface
 - Line state monitor (speed negotiation, suspend/resume, reset from USB etc.)
 - Packet engine ((de)-fragmentation, CRC, endpoint (de)-multiplexing, packet
   sequencing and retransmission etc)
 - Endpoint Zero standard functionality

### ULPI Interface

The ULPI Interface is designed to minimize combinatorial paths and push
critical registers into IOBs when desirable. Meeting timing on low-level
devices can become non-trivial if these important design goals are not
observed.

#### Generics

A number of generics controls the properties of the ULPI interface:
<dl>
<dt>
<tt ULPI_NXT_IOB_G />
</dt>
  <dd>Whether to place the register for <tt NXT/> into an `IOB` should be `true`
      for output-clock mode and `false` for input-clock mode. In the latter case
      it is better to place this register in fabric because it leaves the tool
      more freedom to adjust hold-timing. In output-clock mode the ULPI interface
      is basically source-synchronous (in the PHY-\>FPGA direction) and placing
      this register into `IOB` is advantageous.
  </dd>
<dt>
`ULPI_DIR_IOB_G`
</dt>
  <dd>See `ULPI_DIR_NXT_IOB_G`.
  </dd>
<dt>
`ULPI_DIN_IOB_G`
</dt>
  <dd>See `ULPI_DIR_NXT_IOB_G`. Controls placing of the data-in registers.
  </dd>
</dl>

#### Ports
<dl>
<dt>clk
</dl>

### Endpoint Zero Interface

### Endpoint Interface

### Descriptors

### Constraints

## USB Function Implementations

### CDC ACM Function

### CDC ECM Function

### BADD-Speaker Function

## Descriptor-Generating Tool

## Example Design

### Zynq Platform with Example Device

#### Extension Board

### Device Functions

### Test Software

### Building the Example Design
