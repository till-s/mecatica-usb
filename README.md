# Mecatica Usb

by Till Straumann, 2023.

## Introduction

Mecatica Usb is a versatile and generic USB-2-device implementation in
VHDL supporting an ULPI-standard interface (using an off-the shelf ULPI
PHY chip).

The main use-case are FPGA applications which benefit from a high- or
full-speed USB-2 interface.

A few generic function classes (CDC-ACM, CDC-ECM) are implemented which
can be connected to the generic core IP. USB descriptors can be created
using a python tool. Users may create their own endpoint implementations
and attach these to the USB-2 core.

An example design for the Digilent-ZYBO board is provided which instantiates
the USB-2 core as well as some functions (including an example for isochronous
transfers) is included.

<details><summary><h2>
What About USB-3
</h2></summary>

To date, no Xilinx-FPGA family MGT supports the USB-3 standard; therefore,
no effort has been made to support USB-3. However, for many applications
USB-2 still provides attractive medium-speed connectivity for data transfer
and/or management tasks and at the same time can supply power (USB-C) over
a single cable.

</details>

## License

Mecatica Usb is released under the [European-Union Public
License](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12)

<details><summary><h2>
Features
</h2></summary>

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

The Mecatica Usb package also comes with an example design for the Digilent
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

</details>

<details><summary><h2>
Usb2Core
</h2></summary>

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

</dd><dt>

`usb2DevStatus`

</dt><dd>

  Record holding global (and dynamic) information about the device such as

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

</dd><dt>

`usb2RemoteWake`

</dt><dd>

  Signal remote wakeup. In order to take effect remote-wakeup must
  have been enable by the host and marked as supported in the currently
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
 - *Halt-feature* and *STALL* support (`setHaltInp`, `clrHaltInp`, `setHaltOut`,
   `clrHaltOut`, `stalledInp`, `stalledOut`).

#### Configuration Information

The `config` record conveys the currently active transfer-type and maximum
packet size of an endpoint pair. This also includes information whether an
endpoint is currently running. Usb interfaces may have multiple alt-settings
and only endpoints which are part of the currently active alt-setting are
running; others may have to be explicitly reset. E.g., the CDC ECM specification
mandates (3.3) that when the host selects the first alt-setting (which must not
have *any* endpoints) to "recover the network aspects of a device to known states".

An endpoint shall detect if it is currently running by using the `epInpRunning()`
and `epOutRunning()` functions.

More details are explained in `Usb2Pkg.vhd`.

#### Data Exchange

Data exchange between endpoints and the `Usb2Core` is explained in the
separate [document](doc/DataExchangeProtocol.md) and `Usb2Pkg.vhd`.

Note that the `mstCtl` member is for internal use only and is not used
by normal endpoints which only require

 - `mstOut` - output: data and handshake for *OUT*-directed endpoints.
 - `subInp` - output: handshake for *IN*-directed endpoints.
 - `mstInp` - input: data and handshake for *IN*-directed endpoints.
 - `subOut` - input: handshake for *OUT*-directed endpoints.
 - `bFramedInp` - input: configuration signal; signals the type of framing
   used by the endpoint. This is in most cases a static configuration-type
   signal.

#### Halt Feature

Mecatica Usb supports the Usb *HALT* feature (host may "halt" endpoints
via standard control requests, see 9.4.5 of the USB spec.). The respective
signals are:

 - `stalledInp`, `stalledOut` - input: may be asserted by the endpoint to
   signal an error condition which causes the endpoint's "halt"-bit to be
   set. While this bit is set the core will reply with *STALL* acknowledge
   messages to the host. The halt-bit remains set after the `stalled` input
   is deasserted once the host issues a `CLEAR_FEATURE` request to the endpoint.
   The host may also set the halt-bit itself by issuing a `SET_FEATURE` request.
 - `haltedInp`, `haltedOut` - output: signals whether the endpoint is currently
   halted.

Consult the USB specification for more information about this feature.

### Endpoint Zero Interface

The endpoint zero interface lets functions communicate with the control
endpoint zero.

The endpoint zero interface consists of the signals

  - `usb2Ep0ReqParam` - output; holds the information passed by the `SETUP` phase
    of a control transaction.
  - `usb2Ep0CtlExt` - input: signals to `EP0` whether an external agent is able to
    handle the currently active request. This port also communicates when the agent
    is done handling the request as well as error status information.
  - `usb2EpIb(0)` - input: the external agent supplies data and handshake signals
    during the data phase of a control request here.
  - `usb2EpOb(0)` - output: the external agent observes data and handshake signals
    during the data phase of a control request here.

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

The `Usb2Core` expects the descriptors to be passed as a generic (`DESCRIPTORS_G`).
The application is expected to set this to

    DESCRIPTORS_G => USB2_APP_DESCRIPTORS_C

The `Usb2DescPkg` also provides utility functions that can be used to navigate
the descriptors in order to extract information for configuring details of
the application via generics (the example application checks some capability bits
in the CDC ACM functional descriptor sets certain generics based on the outcome).

The `UsbCore` also offers the option to store the descriptors in block ram. This
feature is enabled by setting

    DESCRIPTOR_BRAM_G => true

This may save some (minor amount of) LUTs when block ram is available. It also
let's the application *patch/overwrite* descriptors at run-time via a dedicated
port (this port is ignored when `DESCRIPTOR_BRAM_G = false`):

 - `descRWClk` - input: clock for writing BRAM (may be asynchronous to the usb
   clock.
 - `descRWIb`  - input: command port
   - `addr`: address
   - `cen`: clock-enable; must be asserted together with the address to cause
     a read or write operation. Read data is presented at `descRWOb` with one
     cycle of latency.
   - `wen`: write-enable; must be asserted together with `cen` to issue a write
     operation. The write date is presented at `wdata`.
 - `descRWOb`  - output: read-back data (1 cycle of latency).

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

</details>

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
