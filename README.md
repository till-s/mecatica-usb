# Mecatica USB

by Till Straumann, 2023.

## Introduction

Mecatica Usb is a versatile and generic USB2-device implementation in
VHDL supporting an ULPI-standard interface (e.g., driving an off-the shelf
ULPI PHY chip). A serial (full/low-speed only) interface is also supported.

The main use-case are FPGA applications which benefit from a high- or
full-speed USB-2 interface (low-speed is ATM only supported for the serial interface).

A few generic function classes (CDC-ACM, CDC-ECM, CDC-NCM) are implemented
which can be connected to the generic core IP. USB descriptors are generated
easily with a python tool. Users may also create their own endpoint
implementations and attach these to the USB-2 core.

An example design for the Digilent-ZYBO board is provided. This example
design instantiates the USB-2 core as well as some functions (including
an example demonstrating isochronous transfers) is included.

### What About USB-3

To date, no Xilinx-FPGA family MGT supports the USB-3 standard; therefore,
no effort has been made to support USB-3. However, for many applications
USB-2 still provides attractive medium-speed connectivity for data transfer
and/or management tasks and at the same time is capable of supplying power
(USB-C) over a single cable.

## License

Mecatica Usb is released under the [European-Union Public
License](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12)
*with the exception of* the [demo ethernet driver](./example/sw/drv_fifo_eth.c)
which is released under the
[GNU GPLv3.0](https://www.gnu.org/licenses/gpl-3.0-standalone.html).

The EUPL permits including/merging/distributing the licensed code with
products released under some other licenses, e.g., the GPL variants.

I'm also open to use a different license.

## Compatibility

All the functions (CDC-ACM, CDC-ECM, CDC-NCM, UAC2-Speaker) implemented
by Mecatica have been tested under linux (5.15), Windows-10 (no ECM) and
MacOS.

## Language and Hardware

Mecatica is written in VHDL and has been tested with Xilinx and Efinix tools
and hardware. The code is hardware-agnostic and should be portable to other
FPGA families (might need some tweaking so that RAM is properly inferred).

## Performance and Resource Consumption

I was able to achieve aboutn 47MB/s with high-speed bulk transfers (no
other devices or functions connected to the host port). The USB core
and ACM function consume about 1800 LUTs (7Series). Efinix Trion uses
approximately 2500 LEs.

<details><summary><h2>
Features
</h2></summary>

The Usb2Core implements the following features:

 - Standard ULPI interface in output- and input-clock mode. Note, however,
   that I have experienced [strange problems](./doc/PROBLEMS.md) when trying
   to operate a `USB3340` PHY in input-clock mode. When I added a crystal to
   the board and strapped the device for output-clock mode these problems
   disappeared!

 - A serial full-speed (only) interface using legacy transceivers (such
   as STUSB03 or ULPI transceivers in serial mode) is also supported.
   This is useful on low-end FPGAs where meeting timing at 60MHz can
   become a challenge (especially for I/O).

 - Optionally provides access to ULPI-PHY registers via dedicated port for
   special use cases.

 - Speed negotiation (device starts as full-speed and tries to negotiate
   high-speed); low-speed is currently *not supported* (when using an ULPI
   transceiver; low-speed is supported with legacy/serial transceivers).

 - Extensible Endpoint-Zero implementation. The endpoint handles the standard
   requests (such as `SET_ADDRESS`, `GET_DESCRIPTOR` etc.) but also features
   interface ports that allow the application to handle class- or vendor-
   specific requests.

 - Handles the details of USB-2 transfers (such as retransmission, CRCs,
   (de-)fragmentation from/to max. packet size etc.) and (de-)multiplexes
   transfers to individual endpoints as (optionally) framed byte-streams.

 - Descriptors are usually hard-coded into the application. Optionally, the
   descriptors can be stored in block-ram and tweaked by the application
   (no structural changes must be performed!); this is intended, e.g. for
   tweaking an ethernet MAC address or other details.

 - Synchronous design; all signals are synchronous to the ULPI clock;
   endpoints may use an included FIFO to decouple clock domains. The
   featured functions all use such a FIFO which may be configured for
   asynchronous operation.

 - A tool written in Python is provided which makes assembling descriptors
   easy.

 - Example constraints for the ULPI interface (for output-clock and input-
   clock modes).

In addition to the `Usb2Core` a few standard functions which implement
standard USB device classes are provided. Compliant host-OS drivers should
support these functions out of the box (tested under linux, windows-10 and
macos).

 - CDC ACM function. This function presents a simple FIFO interface to the
   FPGA client firmware. The CDC ACM *LineState* and *SendBreak* capabilites
   are supported and accessible from dedicated interface ports.
   The *LineState* capability supports side-band channels (e.g., modem
   signals in both directions; events can be signalled to the host side
   via the function's interrupt endpoint).
   The capabilities may be disabled in the descriptors (which results
   in the corresponding logic to be removed from the design) in order
   to save resources.

     On the host this function can be accessed as an ordinary `tty` device.
     (Alternatively, the function may, e.g., be detached from the kernel
     driver and accessed directly using `libusb`.)

 - CDC ECM function. This function presents a simple FIFO interface to the
   FPGA client firmware and is recognized as an ethernet device on the host.
   This allows host software to leverage the power of the network stack
   (provided that some sort of networking is also implemented in the FPGA).
   ECM is supported by respective class-drivers under linux and macos.

 - CDC NCM function. This function presents the same simple FIFO interface
   as the ECM. It consumes slightly more resources than ECM but is supported
   out of the box by Windows -- which lacks an ECM-class driver. Linux and
   macos support NCM, too.

 - BADD Speaker class audio function. This is mainly demonstrating the
   implementation of an isochronous endpoint pair. Audio played on the host
   (under linux: using the vanilla `snd-usb-audio` driver) is converted
   into a `i2s` stream in the FPGA and forwarded to an audio-codec.
   This example also works with the native class-drivers under windows and
   macos.

The Mecatica Usb package also comes with an example design for the Digilent
ZYBO (first version) development board which features a Zynq-XC7Z010 device.
While this board is already old - it is the one I have and porting the design
to its successor or a similar one should be straightforward.

 - KiCAD hardware-design of an extension board hosting a USB connector
   and (USB3340) ULPI PHY device. The board uses 3 PMOD connector sites.

 - Instantiates all available functions.

     - ACM can sink/source data for throughput measurements.
     - ECM Ethernet function.
     - NCM Ethernet function.
     - BADD Speaker function forward `i2s` stream to the on-board SSM2603
       audio codec.

 - Demo software

     - Application using libusb for exercising max. throughput.
     - A trivial demo driver which implements an ethernet device
       *on the Zynq target* interfacing to the ECM or NCM FIFO is provided.
       This demonstrates and exercises the ECM (or NCM) ethernet function by
       connecting the Zynq-linux network stack to the host's networking.
       You cannot expect high performance from this driver or the
       firmware architecture. The FIFO can sustain the theoretical maximum
       speed of 60MB/s without problems but this is not a good software
       interface. Mecatica is aimed at FPGA applications - for software
       applications you'd use the PS USB interface. Interfacing the
       ethernet functions directly to sofware is a *demo only*.
     - Application to test/demo ACM modem line "interrupts" (uses
       `ioctl(IOCMIWAIT)`).

</details>

<details><summary><h2>
Usb2Core
</h2></summary>

The Usb2Core aggregates all the standard components necessary to provide
core functionality:

 - ULPI PHY Interface or full-speed only serial interface.
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

`ULPI_EMU_MODE_G`

</dt> <dd>

  Set to `NONE` (default) when using the ULPI interface. This generic
  is used to enable the serial (non-ULPI) interface.

</dd><dt>

`ULPI_NXT_IOB_G`

</dt> <dd>

  Whether to place the register for `NXT` into an `IOB` should be `true`
  for output-clock mode and `false` for input-clock mode. In the latter case
  it is better to place this register in fabric because it leaves the tool
  more freedom to adjust hold-timing. In output-clock mode the ULPI interface
  is basically source-synchronous (in the PHY-\>FPGA direction) and placing
  this register into `IOB` is advantageous.

</dd><dt>

`ULPI_DIR_IOB_G`

</dt><dd>

  See `ULPI_DIR_NXT_IOB_G`.

</dd><dt>

`ULPI_DIN_IOB_G`

</dt><dd>

  See `ULPI_DIR_NXT_IOB_G`. Controls placing of the data-in registers.

</dd></dl>

#### Ports

<dl><dt>

`ulpiClk`

</dt><dd>

  Clock for the core. Synchronous to the ULPI interface.

</dd><dt>

`ulpiRst`

</dt><dd>

  Reset for the ULPI interface (ULPI IO block and line-state manager).
  This signal ***must not*** be asserted when the host signals a reset
  (`SE0`) condition (available in `usb2DevStatus` record) because the
  ULPI interface and line-state manager must continue operating.

<dd><dt>

`usb2Rst`

</dt><dd>

  Reset for the Usb2 engine. It is OK to assert this reset when the host
  signals a `SE0` condition.

</dd><dt>

`ulpiIb`, `ulpiOb`

</dt><dd>

  ULPI interface signals. Connect to the ULPI PHY via IO buffers. The
  `ulpiIb.dir` signal should control the direction of the data lines
  (combinatorial path). Consult the example design for more information.

</dd><dt>

`UlpiRegReq`, `UlpiRegRep` (special use-cases only)

</dt><dd>

  Interface to the ULPI PHY registers for specialized testing or debugging
  needs. Ordinary applications may ignore this interface (open); advanced
  users must consult the source code for more information.

</dd></dl>

#### Limitations

Due to the registers in the input and output path the ULPI interface
does not tolerate unexpected incoming traffic too gracefully. It is
unable to drive `TXCMD` on the same cycle `dir = '0'` is observed
and thus unsolicited `RXCMD` reports that happen concurrently -- i.e.,
within a window of a few cycles -- with an attempt to transmit may cause
the transmission to be aborted.

For this reason the various voltage comparator interrupts are disabled.
The especially problematic `VBUS > VA_VBUS_VALID` comparator should not
be used by peripheral devices (see ULPI spec.) anyways.

### Serial Interface

Mecatica supports the use of legacy full- or low-speed transceivers over
a serial interface. When using this serial interface the ULPI interface
should be left unconnected (except for `ulpiClk`).

The serial interface implements (de-)serialization and (de-)bit stuffing
for the RX and TX path, respectively. The serial interface is enabled by
setting the `ULPI_EMU_MODE_G` generic to `FS_ONLY` or `LS_ONLY`, respectively.

The serial interface features an ULPI emulation layer which presents
parallel data to the USB core.

Note that the `ulpiClk` runs at the *bit-clock frequency* in serial mode,
i.e., 12MHz for full- and 1.5MHz for low-speed. This also applies to the
rest of Mecatica: all USB-processing as well as the endpoints etc. are
clocked at the bit-rate.

In addition to `ulpiClk` the serial interface requires a sampling clock
which must be phase-synchronous to the bit-clock at 4-times the bit-rate,
i.e., 48MHz for full- and 6MHz for low-speed.

#### Generics

<dl>
<dt>

`ULPI_EMU_MODE_G`

</dt> <dd>

  This generic is used to enable the serial (non-ULPI) interface.
  Set to `FS_ONLY` for full-speed and to `LS_ONLY` for low-speed,
  respectively.

</dd></dl>

#### Ports

<dl>
<dt>

  `ulpiClk`

</dt><dd>

  In serial mode the `ulpiClk` must run at the *bit-clock rate*
  instead of the usual 60MHz. I.e., 12MHz for full- and 1.5MHz for
  low-speed.

</dd></dt>

  `fslsSmplClk`

</dt><dd>

  Sampling clock used by RX clock recovery. This must be phase-
  synchronous to the bit-clock (`ulpiClk`) and run at 4-times the
  bit rate, i.e., 48MHz for full- and 6MHz for low-speed.

  When defining timing constraints keep in mind that the sampling-
  and bit-clock domains are *not* asynchronous, i.e., their crossing
  paths must be properly constrained by defining appropriate multicycle
  paths.

</dd></dt>

  `fslsIb`

</dt><dd>

  Inbound signals from the serial transceiver. These consist of the outputs
  of the differential- as well as the single-ended receivers.

</dd></dt>

  `fslsOb`

</dt><dd>

  Output signals to the serial transceiver. These consist of the
  single-ended `vp` and `vm` signals as well as the output-enable (`oe`)
  for direction-control of the transceiver. If the transceiver uses
  bi-directional pins then `oe` also controls the FPGA I/O pin direction.

</dd></dl>

### USB Status and Endpoint Interface Signals

<dl><dt>

`usb2DevStatus`

</dt><dd>

  Record holding global (and dynamic) information about the device state
  such as

  - whether remote wakeup is supported and enabled
  - Current Usb2 device state (Usb2-spec, 9.1)
  - Usb2 reset (as signalled by the host). This should be ORed with potential
    other sources of reset and propagated to the `usb2Rst` input.
  - The `halt`-related signals are for internal use only. Corresponding
    signals for endpoint use are part of the `usb2EpOb` records.

</dd><dt>

`usb2Rx` (special use-cases only)

</dt><dd>

  Record providing low-level USB information such as the current token
  being processed etc. The only member which is potentialy useful to
  applications is the frame-number info in the `pktHdr` sub-record:

  - `vld` qualifies the contents of the `pktHdr` record. Other fields
    are only valid while `vld` is asserted high.
  - `sof` is `true` if a start-of-frame packet is being received.
  - `tokDat` are the data bits associated with the token. In combination
    with `sof` the `tokDat` field conveys the frame number.

</dd><dt>

`usb2Ep0ReqParam`, `usb2Ep0CtlExt`, `usb2EpIb(0)`, `usb2EpOb(0)`

</dt><dd>

  Ports where an external agent handling control transfers directed
  to endpoint zero can be handled. Note that standard requests are
  handled internally, however, functionality (e.g., for class-
  specific requests) can be extended by connecting an external
  agent (see dedicated section for more information).

</dd><dt>

`usb2HiSpeedEn`

</dt><dd>

  Global device configuration; signals whether high-speed support
  should be enabled. In most cases this is tied to a static value.
  '1' for high-speed capable applications and '0' for full-speed
  only use cases.

</dd><dt>

`usb2RemoteWake`

</dt><dd>

  Signal remote wakeup. In order to take effect remote-wakeup must
  have been enabled by the host and marked as supported in the currently
  active configuration descriptor.

</dd><dt>

`usb2SelfPowered`

</dt><dd>

  Signal whether the device is currently self powered (for supporting
  the `GET_STATUS`request).

</dd><dt>

`usb2EpIb`, `usbEpOb`

</dt><dd>

  Array of endpoint signals. These are the main ports where endpoints are
  attached. Consult the dedicated section for more information.

</dd></dl>

### Endpoint Interface

Endpoints in Mecatica Usb are grouped in *pairs* sharing the same endpoint
address but supporting different directions (IN/OUT). It is possible that
one direction remains unused (this would be indicated by a missing desriptor
for the unused half of the pair).

The signals used for communication with endpoint pairs are grouped into
an *inbound* (signals originating at the endpoint and being read by
the Usb2Core) port (`usb2EpIb`) and an *outbound* (`usb2EpOb`) port
(signals originating in the Usb2Core and being read by the endpoints).

`usb2EpIb` and `usb2EpOb` are *arrays* with each array element connecting
to an endpoint pair. The array elements are of types `Usb2EndpPairIbType`
and `Usb2EndpPairObType`, respectively.

The signals communicated to/from the endpoints can be divided into three
groups:

 - configuration information (`config`). This record communicates information
   about the currently active configuration and interface alt-setting (such as
   the currently active 'maxPacketSize').
 - data exchange and handshake (`mstOut`, `subInp`, `mstCtl`, `bFramedInp`,
   `mstInp`, and `subOut`).
 - *Halt-feature* (`haltedInp`, `haltedOut`) and *STALL* support (`stalledInp`,
   `stalledOut`). See below for details.

#### Configuration Information

The `config` record conveys the currently active transfer-type and maximum
packet size of an endpoint pair. This also includes information whether an
endpoint is currently "running". Usb interfaces may have multiple alt-settings
and only endpoints which are part of the currently active alt-setting are
"running"; others may have to be explicitly reset. E.g., the CDC ECM specification
mandates (3.3) that when the host selects the first alt-setting (which must not
have *any* endpoints) to "recover the network aspects of a device to known states".

An endpoint shall detect if it is currently running by using the `epInpRunning()`
and `epOutRunning()` functions.

More details are explained in `Usb2Pkg.vhd`.

#### Data Exchange

Data exchange between endpoints and the `Usb2Core` is explained in the
[separate document](./doc/DataExchangeProtocol.md) and
[`Usb2Pkg.vhd`](./core/hdl/Usb2Pkg.vhd).

Note that the `mstCtl` member is for internal use only and is not used
by normal endpoints which only require

<dl>
<dt>

`mstOut` - output

</dt><dd>

  Data and handshake for *OUT*-directed endpoints.

</dd><dt>

`subInp` - output

</dt><dd>

  Handshake for *IN*-directed endpoints.

</dd><dt>

`mstInp` - input

</dt><dd>

  Data and handshake for *IN*-directed endpoints.

</dd><dt>

`subOut` - input

</dt><dd>

  Handshake for *OUT*-directed endpoints.

</dd><dt>

`bFramedInp` - input

</dt><dd>

 Configuration signal; signals the type of framing used by the endpoint.
 This is in most cases a static configuration-type signal.

</dd>
</dl>

#### Halt Feature

Mecatica Usb supports the Usb *HALT* feature (host may "halt" endpoints
via standard control requests, see 9.4.5 of the USB spec.). The respective
signals are:

<dl>
<dt>

`stalledInp`, `stalledOut` - input

</dt><dd>

  May be asserted by the endpoint to signal an error condition which causes
  the endpoint's "halt"-bit to be set. While this bit is set the core will
  reply with *STALL* acknowledge messages to the host. The halt-bit remains
  set after the `stalled` input is deasserted once the host issues a
  `CLEAR_FEATURE` request to the endpoint. The host may also set the halt-bit
  itself by issuing a `SET_FEATURE` request.

</dd><dt>

`haltedInp`, `haltedOut` - output

</dt><dd>

  Signals whether the endpoint is currently halted.

</dd>
</dl>

Consult the USB specification for more information about this feature.

### Endpoint Zero Interface

The endpoint zero interface lets functions communicate with the control
endpoint zero.

The endpoint zero interface consists of the signals

<dl>
<dt>

`usb2Ep0ReqParam` - output

</dt><dd>

  Holds the information passed by the `SETUP` phase of a control transaction.

</dd><dt>

`usb2Ep0CtlExt` - input

</dt><dd>

  Signals to `EP0` whether an external agent is able to handle the currently
  active request. This port also communicates when the agent is done handling
  the request as well as error status information.

</dd><dt>

`usb2EpIb(0)` - input

</dt><dd>

  The external agent supplies data and handshake signals during the data phase
  of a control request here.

</dd><dt>

`usb2EpOb(0)` - output

</dt><dd>

  The external agent observes data and handshake signals during the data phase
  of a control request here.

</dd>
</dl>

The `usb2EpIb(0)`/`usbEpOb(0)` pair groups the standard in- and outbound
endpoint signals. They follow the same protocol as ordinary endpoint pairs but are
only used during the data phase of endpoint-zero control transactions when an external
agent takes over handling such a transaction.

Note that the `Usb2Core` handles standard requests (such as `GET_DESCRIPTOR` etc.)
internally. The core also deals with the `SETUP` phase of all requests and stores
the setup data in the `usb2Ep0ReqParam` record.

Once the `SETUP` phase is done the core asserts `usb2Ep0ReqParam.vld` and at this
time an external agent may inspect the request parameters and decide if it wants
to handle the request. It *must* assert `ctlExt.ack` for one cycle concurrently
with or after seeing `vld` and at the same time signal with `ctlExt.err` and
`ctlExt.don` how it wants to proceed:

  | `vld` | `ack` | `err` | `don` | Semantics
  | ----- | ----- | ----- | ----- | ---------
  |   1   |   1   |   0   |   0   | Accept request, need more time to process
  |   1   |   1   |   1   |   1   | Reject request
  |   1   |   1   |   0   |   1   | Accept request, processing done

Note that the agent may take several clock cycles between 'seeing' `vld` and
asserting `ack`. Once the request has been accepted the agent is responsible
for handling an (optional) data phase which follows the protocol for endpoint
data exchanged described in the previous section. The respective signals are
bundled in `usb2EpIb(0)` and `usb2EpOb(0)`, respectively.

If the data phase is involving an *IN* endpoint (read request) then the agent
must monitor `usb2Ep0ReqParam.vld` and abort any transacion if this signal is
deasserted. This can happen if the host decides not to read all available data.

If the agent rejects the request (`don = ack = err = 1`) then the request is
passed on to the (internal) standard endpoint-zero and handled there if it
is a standard request. A *protocol-`STALL`* state is entered if the request
is found to be unsupported.

Further information is available in the comments of `Usb2Pkg.vhd`.

### Descriptors

Mecatica Usb uses a semi-static approach with regard to Usb descriptors.
The `Usb2AppCfgPkg.vhd` package declares a constant `USB2_APP_DESCRIPTORS_C`
which is a byte-array holding all descriptors. The contents of this constant
are not directly used by the Usb2Core; however, it's size is used by the
`Usb2DescPkg` to define a numerical data type (`Usb2DescIdxType`) which is
large enough to navigate the entire array.

The `Usb2DescPkg` also provides utility functions that can be used to navigate
the descriptors in order to extract information for configuring details of
the application via generics (the example application checks some capability bits
in the CDC ACM functional descriptor and sets certain generics based on the
outcome).

#### Generics

<dl>
<dt>

`DESCRIPTORS_G`

</dt><dd>

  The `Usb2Core` expects the descriptors to be passed as a generic (`DESCRIPTORS_G`).
  The application is expected to set this to

    DESCRIPTORS_G => USB2_APP_DESCRIPTORS_C

</dd><dt>

`DESCRIPTORS_BRAM_G`

</dt><dd>

The `UsbCore` also offers the option to store the descriptors in block ram. This
feature is enabled by setting

    DESCRIPTOR_BRAM_G => true

This may save some (minor amount of) LUTs when block ram is available. It also
let's the application *patch/overwrite* descriptors at run-time via a dedicated
port( see below).

</dd>
</dl>

#### Ports

If `DESCRIPTORS_BRAM_G = true` then a dedicated port gives access to the
descriptors (this port is ignored when `DESCRIPTOR_BRAM_G = false`):

<dl>
<dt>

`descRWClk` - input

</dt><dd>

  Clock for writing BRAM (may be asynchronous to the usb clock.

<dt>

`descRWIb`  - input

</dt><dd>

  Command port

  <dl><dt>

  `addr`

  </dt><dd>

   Address

  </dd><dt>

  `cen`

  </dt><dd>

   Clock-enable; must be asserted together with the address to cause
   a read or write operation. Read data is presented at `descRWOb` with one
   cycle of latency.

  </dd><dt>

  `wen`

  </dt><dd>

   Write-enable; must be asserted together with `cen` to issue a write
   operation.

  </dd><dt>

  `wdata`

  </dt><dd>

   The write date is presented at `wdata`.

  </dd></dl>

</dd><dt>

`descRWOb`  - output

</dt><dd>

  Read-back data (1 cycle of latency).

</dd>
</dl>

Modifying the descriptors has to be done with *great care* and only if you
know exactly what you are doing! The layout/structure of the descriptors
*must not* be changed. The use-case of this feature is tweaking special data
such as serial-numbers or MAC-addresses etc. Consult the example application.

#### Descriptor Layout

Mecatica Usb expects the descriptors to follow a certain layout. When descriptors
are generated using the python tool this layout is automatically observed.

##### Simple Device

A simple device supports no *DEVICE_QUALIFIER* descriptor. This could be a full-
speed device. It is not clear (to me) from the specification if it is "legal" for
a high-speed only device to forego a *DEVICE_QUALIFIER* descriptor. In any case,
it seems to work under linux, YMMV.

A simple device lists:

 1. The *DEVICE* descriptor
 2. A *CONFIGURATION* descriptor (followed by all *INTERFACE* and *ENDPOINT* descriptors
    etc.). Optionally, more *CONFIGURATION*, *INTERFACE* and *ENDPOINT* descriptors may
    follow.
 3. All string descriptors
 4. A special (non-Usb conformant) *SENTINEL* descriptor to mark the end of the
    table.

##### Dual-Speed Device

A fully compliant high-speed capable device supports *DEVICE_QUALIFIER* and
*OTHER_SPEED_CONFIGURATION* descriptors. Mecatica Usb expects these to be
listed in a specific order as outlined below. Note that no *OTHER_SPEED_CONFIGURATION*
descriptor is actually present but only ordinary *CONFIGURATION* descriptors.
The core automatically patches the descriptor-type of *CONFIGURATION* descriptors
of the currently inactive speed to be read as *OTHER_SPEED_CONFIGURATION*.

  1. Full-speed *DEVICE* descriptor
  2. Full-speed *DEVICE_QUALIFIER* descriptor (holding info about the high-speed
     *DEVICE* descriptor).
  3. Full-speed *CONFIGURATION* descriptor (followed by all *INTERFACE* and *ENDPOINT*
     descriptors etc.). Optionally, more full-speed *CONFIGURATION*, *INTERFACE* and
     *ENDPOINT* descriptors may follow.
  4. A special (non-Usb conformant) *SENTINEL* descriptor to mark the end of the
     full-speed section.
  5. High-speed *DEVICE* descriptor
  6. High-speed *DEVICE_QUALIFIER* descriptor (holding info about the full-speed
     *DEVICE* descriptor).
  7. High-speed *CONFIGURATION* descriptor (followed by all *INTERFACE* and *ENDPOINT*
     descriptors etc.). Optionally, more high-speed *CONFIGURATION*, *INTERFACE* and
     *ENDPOINT* descriptors may follow.
  8. String descriptors. Note that these are shared among all other descriptors.
  9. A special (non-Usb conformant) *SENTINEL* descriptor to mark the end of the
     table.


### Constraints

#### ULPI-IO Timing

Example files for constraining the ULPI I/O ports are provided for input-clock
(`ulpi_clkinp_io_timing.xdc`) as well as output-clock (`ulpi_clkout_io_timing.xdc1`)
mode. These files are pretty generic and assume worst-case timing as per the
ULPI spec. Additional files which are specialized for the USB3340 PHY device are
also present. You will have to customize any of these files for your specific
PHY and board delays.


On low-end devices it may turn out to be not completely trivial to meet timing
due to significant delays in the IO-buffers. The example design mitigates some
of this by using a MMCM to generate a phase-shifted clock which compensates for
some of the delay in the clock path.

#### Synchronizer Constraints

Designs which use the `ASYNC_G` feature of FIFO-based endpoints where the endpoint
clock is asynchronous to the ULPI-clock should add the constraint files associated
with the synchronizer structures to the design. It is *important* to set the
`SCOPE_TO_REF` property for these files in the Xilinx tool (for other vendors similar
steps may be required).

 - `Usb2CCSync.cc`; set `SCOPE_TO_REF` to `Usb2CCSync` and restrict its use to
   "implementation". This file defines a false-path for the clock-crossing signal.
 - `Usb2MboxSync.xdc`; set `SCOPE_TO_REF` to `Usb2MboxSync` and restrict its use
   to "implementation". This file defines the necessary false- and multicycle
   paths for the data crossing the synchronizer.

</details>

<details><summary><h2>
USB Function Implementations
</h2></summary>

### Generic FIFO Interface

All the CDC functions use internal FIFOs; ACM and ECM are based on `Usb2FifoEp.vhd`
which is a generic FIFO which can be used to implement other endpoints as well.
The internal implementaton of NCM is different but it offers the same FIFO interface
ports as the other CDC functions.

This FIFO interface is less complex than the endpoint interface to the `Usb2Core`.

The interface uses

 - a data port including a `LAST` flag which is asserted during the last transfer
   of a frame (only applicable if the function uses frames such as ethernet).
 - read- (`OUT` direction) or write-enable (`IN`) control signals.
 - empty (`OUT` direction) or full (`IN`) handshake signals.

In `OUT` direction data (and `LAST`) are ready and valid as soon as `empty` is deasserted.
Data are consumed by asserting `read-enable`.

In `IN` direction data octets (and `LAST`) are written while write-enable is asserted
and `full` is deasserted.

### CDC ACM Function

To the host the ACM function presents itself as a standard CDC-ACM device. Optionally,
(if enabled in the descriptors) the "line-break" and/or "line-state" features are
supported (ports are available to connect the respective signals).

The ACM function uses *unframed* data. The `LAST` marker is not supported/used. Data are
sent (`IN` direction) as soon as the fifo is empty or the maximum packet size is reached.
If data are sourced slower than they can be sent on the USB this may result in poor
efficiency and many small packets. In order to mitigate this effect the function offers
two ports (which work similar to the termios VTIME/VMIN feature):

 - fifoMinFillInp: data are accumulated in the `IN` fifo until this threshold is reached
   before a USB packet is formed.
 - fifoTimeFillInp: every time a data item is written to the FIFO a timer is reset. If
   the timer (which is clocked at the 60MHz ULPI clock rate) reaches the `fifoTimeFillInp`
   timeout data are sent on the USB even if the `fifoMinFillInp` threshold has not been
   reached yet. A timeout of all-ones results in an infinite timeout.

Thus, data can be accumulated in the FIFO until either the threshold is reached or the
timeout expires - which ever happens first.

The FIFO depth can be configured by means of generics.

While this function is supported on the host side natively by most operating systems
it should be noted that the native drivers probably are not very efficient (a typical
terminal application is not optimized for high throughput). However, as demonstrated by
the examples: it is quite straigntforward to overcome this limitation, e.g., by using
libusb to access the function.

### CDC ECM Function

The ECM function offers the same FIFO interface as the ACM. Because ethernet data are
always framed (using the `LAST` flag) the min-fill threshold and -timer are not used.

The MAC address of the function is defined in the descriptors. The example application
shows how the MAC address could be patched with a unique address (to be read, e.g., from
an EEPROM).

ECM is quite simple and offers offers ethernet connectivity to the firmware downstream
of the function (note, however, that Mecatica does not include a network stack).

The depth of the internal fifo buffer is configurable by means of generics.

The ECM function has a `carrier` input port which should be used to indicate that
the user is ready for handling network traffic (this will signal to the host side
that the ethernet interface is "running").

### CDC NCM Function

The NCM function is very similar to ECM from the firmware perspective. It does use
more FPGA resources due to its higher complexity. Unfortunately, windows does not
natively support ECM so that you may want to use NCM if interfacing to windows is
a requirement.

The NCM has a few features (such as NTB sizes and other parameters which may
help increasing efficiency) that can be tuned with generics.

The NCM function optionally (if enabled in the descriptors) supports the
`SET_NET_ADDRESS` request - however, linux currently does not.

Like ECM the NCM function also supports a `carrier` input port.

### BADD-Speaker Function

This function supports the BADD (UAC3) speaker profile. However, since only linux supports
UAC3 at this point one can also create UAC2 descriptors that are compatible with this
function (and the python tool supports this).

This function mainly serves as an example and test of an isochronous endpoint including
feedback functionality.

</details>

<details><summary><h2>
Example Device
</h2></summary>

The "Example Device" is a wrapper which instantiates all necessary
components as well as all implemented endpoints. It has ports that
connect to all the endpoints (including the control endpoint) and makes
suitable and simple interfaces available to the user.

For most applications the "Example Device" provides a 'plug-and-play'
USB solution. E.g., the ACM function -- from the viewpoint of the
firmware application -- is accessible as a simple pair of FIFOs.

Many features of the "Example Device" are configurable and where possible
the configuration settings are automatically extracted from the application's
USB descriptors which in turn are generated with a python tool.

E.g., if the descriptors do not list a NCM interface then the NCM function
is disabled in the HDL (i.e., the respective components are not instantiated)
and no FPGA resources are spent. All ports of the "Example Device" are
tied-off to suitable default values so that an instantiation of the device
with a small set of enabled features does not unnecessarily clutter
application HDL.

</details>

<details><summary><h2>
Descriptor-Generating Tool
</h2></summary>

### Overview

USB Descriptors for Mecatica are normally generated using a tool written
in python. The core of this tool resides in `scripts/Usb2Desc.py` which
features comments explaining it's use. `Usb2Desc.py` is, however, rarely
used directly as higher level scripts are available.

A brief summary of its workings shall nevertheless be given: descriptors
are represented by python classes with properties that represent items
present in a descriptor. Descriptor objects are always connected to a "context"
and their order in which they appear on USB is the order in which they
were created in the "context".

After all descriptors have been created and populated with their desired
values the context is "wrapped-up". During this step some automatically
generated information (e.g., enumeration of interfaces and endpoints etc.)
is inserted.

Eventually, the tool generates VHDL code for the body of the VHDL package
`AppCfgPkg`. This VHDL file must be included with the set of files handed
to the FPGA toolchain. For convenience the VHDL is annotated with comments
that are helpful when details need to be inspected.

### High-Level Scripts

The higher-level scripts are intended to generate suitable descriptors
for the Mecatica "Example Device" (which is of quite generic use, see
above). `example/py/ExampleDevDesc.py` provides a function that
creates customized descriptors for the "Example Device" based on a
number of parameters. Many of these influence the instantiation of
subcomponents in the "Example Device" and can be used to "prune"
functionality in order to save resources.

Finally, there is the `example/py/genAppCfgPkgBody.py` script which is
a CLI-style driver for `ExampleDevDesc.py`. It can be executed from a
shell and accepts options (use `-h` for help) that are translated
into parameters which are passed to `ExampleDevDesc.py`.

Note that the default output file path is set such that the generated
VHDL ends up as `<script_location>/../example/hdl/AppCfgPkgBody.vhd`.
Thus, unless you plan to create the Zynq example design you must make
sure to use `-f` to generate the file in the desired location and with
the desired name.

Note also that you *must* provide a suitable vendor/product ID; the
tool has not set a default.

Use

      example/py/genAppCfgPkgBody.py -h

for a summary of the available options.

</details>

<details><summary><h2>
Example Design
</h2></summary>

### Zynq Platform with Example Device

#### Extension Board

The hardware design of a simple extension board for the ZYBO (v1) is
available in the `kicad` subdirectory. The extension board hosts a
USB3340 ULPI PHY, a clock and a micro-USB connector. It connects to
three PMOD sites on the ZYBO (JB, JC and JD). The board can be configured
for UPLI input-clock or output-clock mode. Note that [problems](./doc/PROBLEMS.md)
with input-clock mode which disappeared when I populated the clock
generator and strapped the board for clock-output mode.

Unfortunately no suitable clock-capable input is routed from the Zynq
to the PMOD sites. Thus, we have to use an ordinary input for shipping
the clock which will cause Vivado to complain. I didn't experience
problems (60MHz is not that high of a frequency) but I did have to do
some phase shifting in a MMCM.

### Device Functions

### Building the Example Design

#### Generate the Descriptors

As a first step you must generate the VHDL package body which defines the
Usb descriptors for the project.

  1. chdir to the `example` subdirectory
  2. run the python script providing a Usb product ID and optionally a
     vendor id (by default the [0x1209](https://pid.codes) vendor ID is used).

     **_You may use the [0x0001](https://pid.codes/1209/0001/) for private testing
     only. Do not redistribute hardware/firmware using this ID!_**

         py/genAppCfgPkgBody.py -p 0x0001

     The tool supports a number of other options (use `-h` for help). In particular,
     you may disable individual functions (and reduce the amount of resources used).
     The VHDL code extracts all the necessary information from the descriptors and
     configures itself to support only the functions and features present in the
     descriptors:

       - `-S` disables the sound (ISO) function.
       - `-E <macAddr>` enables the CDC ECM ethernet function
       - `-N <macAddr>` enables the CDC NCM ethernet function
       - `-A` disables the CDC ACM function

#### Generate the Vivado Project

A [tcl script](./example/tcl/Usb2Example.tcl) creates the Vivado project for
the example design.

  1. chdir to the `example` directory.
  2. run vivado in batch mode using the script:

         vivado -mode tcl -source tcl/Usb2Example.tcl -tclargs --ulpi-clk-mode-inp 0

     this will create the project for the ULPI output-clock mode (which is also the
     default).

Once the project has been created you may start vivado in GUI mode, navigate to the
project and open it. Proceed to synthesizing, implementing and eventually producing a
bit-file which should be loaded on the target via JTAG or linux on the Zynq target.

### Test Software

Once the firmware is loaded on the target and the PMOD extension board is connected
to a host with a Usb cable the device should be detected by the host:

    $ lsusb -s 1:9
    Bus 001 Device 009: ID 1209:0001 Generic pid.codes Test PID


#### Testing the ACM Device

##### Terminal Loopback Mode

The CDC ACM device should be automatically recognized by linux and bound to the
`cdc-acm` kernel driver which should make a `/dev/ttyACM0` or similar device
available. You can use e.g., `minicom` to test this device. As soon as the
firmware detects the DTR modem control it enables "loopback" on the target
which means that any characters typed into `minicom` will be echoed back.

The "line break" feature is also supported. Type `<Ctrl-A> F` into minicom
and you should see one of the LEDs on the ZYBO board blink.

##### Throughput Test

It is now time to see how much thoughput we can achieve. For this test we
use the `sw/blktst.c` program which uses `libusb-1.0` to communicate with
the device. The program attempts to unbind the `cdc-acm` kernel driver during
initialization. It may be necessary to tweak permissions or to manually unbind
the kernel driver (as root), YMMV.

First you have to compile the `blktst.c` program (on the host system). You
need a C-compiler and libusb-1.0 (with headers). The [`Makefile`](./example/sw/Makefile)
helps with this process:

  1. `chdir example/sw`
  2. `make blktst`

The `blktst` program puts the endpoint into "blast" mode. In this
mode the endpoint discards all incoming data (after reading it) and it
feeds the *OUT* endpoint with an incrementing counter value at the maximum
rate (60MB/s in high-speed, 1.5MB/s in full-speed mode).

`blktst` uses an ample amount of buffer space and schedules bulk-read
(or bulk-write) operations in order to saturate the connection. It transfers
data during several seconds and measures the achieved throughput.

    $ ./blktst -P 0x0001
    High-speed device.
    Successfully transferred (reading) 104857600 bytes in  2.211 s (47.418 MB/s)

(using the product ID you built the firmware with) exercises the *IN* endpoint.
You may try the *OUT* (writing) direction:

    $ ./blktst -P 0x0001 -w
    High-speed device.
    Successfully transferred (writing) 104857600 bytes in  2.286 s (45.874 MB/s)

If `lsusb` lists the device but `blktst` is unable to find or open it then the
most likely cause is lack of the necessary permission. Try running as root
and/or add suitable udev rules (how to do that is beyond the scope of this
document).

##### Important Notes Regarding Throughput

While the native CDC-ACM `tty` driver is useful for low-performance applications
because it gives access to the device using ordinary tty software you will *never*
be able to achieve reasonable throughput with this driver due to the very small buffer
space it uses. Throughput was 100-times less than with the `blktst` program.

Also, keep in mind that the USB is a *bus* and that *all functions* as well as other
devices connected to the same port share bandwidth. Even unused functions may use
a noticeable amount of bandwidth if the host has to periodically poll them for activity.

It is best to unbind any drivers from all other functions and unplug other devices
when performing the throughput test.

#### Testing the ECM Device

The ECM device is supported by the standard linux `cdc_ether` driver which presents
an ethernet device on the host system and connects it to the host networking stack.

In the firmware the ECM device presents a FIFO interface which could be connected
to an in-firmware networking IP. We don't have to burden the example design on the
Zynq device with adding such an IP since there is a complete (software) networking
stack available on the Zynq/ZYBO target (assuming you have linux installed there).

There is a trivial [driver](./example/sw/drv_fifo_eth.c) available which talks to the
ECM device's FIFO interface via AXI and presents an ethernet device *on the target
linux system*. Note that this is a driver which must be cross-compiled and loaded
on the *target*. Also note that this is an extremely inefficient driver. It's for
*demonstration*.

Edit the [Makefile](./example/sw/Makefile) or add a `./example/sw/config-local.mk`
file and define the path to the (target) kernel sources:

    KERNELDIR := /path/to/TARGET/kernel/source/top/
    CROSS_COMPILE := arm-linux-

if you cross-compiler uses a different prefix then modify the definition accordingly.
You can now build the module:

    make modules

You then must load this module on the target and bind the driver
to a suitable platform device which covers the address-range and interrupt
used by the FIFO. Discussion the details of the necessary device-tree entries
etc. is beyond the scope of this document but a snippet is provided here for
illustration:

    ps7-axisub2@43c02000 {
        compatible = "usbExampleFifoEth";
        reg = <0x430c02000 0x1000>;
        interrupt-parent = <&intc>;
        interrupts = <0 31 4>;
    };

Once you have successfully bound this driver you should be able to bring
both interfaces (on the target and the host) up and after assigning IP addresses
they should be able to communicate!

I have successfully tested this under linux and macos. Windows does not have
a native CDC-ECM driver, unfortunately.

#### Testing the NCM Device

The NCM device is supported by the standard linux `cdc_ncm` driver. On the Zynq
it is supported by the same `drv_fifo_eth.ko` demo driver and works exactly the
same way as the ECM device. On the host, NCM is supported by linux, windows and
macos.

#### Testing the BADD Speaker Device

The BADD Speaker device implements a simple audio device that follows the
"Basic Audio Device Definition (v3) - Speaker Profile" and is supported by
the standard linux `usb_snd_audio` driver. Alternatively, the python tool
can generate slightly more complex descriptors conforming to the UAC-2
specification. The `genAppCfgPkgBody.py` script uses this option by default.
It has the advantage that the example works under windows and macos, too.
Neither of these OSes supports UAC-3 (only linux does).

On the target the firmware converts the audio stream into a I2S signal
which drives the SSM2603 audio codec chip on the ZYBO board. By default
the firmware is configured for 24-bit stereo samples at 48kHz.

#### Initialization via I2C

The SSM2603 chip has to be initialized via i2c (not to be confused with
i2s which transfers the sound samples). The demo design does not contain
i2c firmware which means that

  - i2c initialization is performed with the *target software* program
    [`ssm2603`](./example/sw/ssm2603.c).
  - adjusting the volume and muting is not supported. While the endpoint
    provides the respective ports there is no i2c support to propagate
    the volume adjustments to the ssm2603 via i2c.

Build the `ssm2603` program (assuming you have a cross-compiler set up):

    chdir example/sw
    make ssm2603

Then you must install this program on the target somehow and run it there
to enable master mode (at 48kHz, 24-bit stereo). Note that the `i2d-dev`
driver must be loaded.

    # modprobe i2c-dev
    # ssm2603 -U

At this point you should be able to play audio from the host. Sometimes
I have to run `ssm2603 -U` twice or I hear scrambled audio. Probably I
got some delay timng in that program wrong.

I had actually modified my ZYBO board in the past and loaded the optional
crystal:

  - loaded 12.288MHz crystal X1
  - loaded C46, C47
  - removed R129

By default the sound chip's MCLK is generated by the FPGA (12.000MHz) which
results in a jittery and poor audio clock. By using a crystal we have -- in
addition to better audio -- a truly asynchronous audio clock which can exercise
the audio feedback stream. With the 12Mhz clock being synchronous to the
USB clock the audio stream is de-facto synchronous and would work without
feedback.

Note that when running with a 12.288MHz reference the initialization of the audio
chip must be slightly different. The clock difference to 12.000MHz is too big
to be compensated by the audio feedback and distortion will result (in addition
to the wrong pitch of the audio).

    # ssm2603 -M

configures the chip for a 12.288Mhz clock.

</details>
