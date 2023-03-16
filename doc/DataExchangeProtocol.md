# Data-Exchange Protocol Between Endpoints and Usb2Core

## Basic Handshake

Non-ISO endpoints use a set of simple handshake signals when communicating
with the `Usb2Core`. For isochronous endpoints consult the dedicated
sections below.

The basic handshake signals are

<dl><dt>

`vld`

</dt><dd>

  Asserted by the data *source* when valid data are presented on the
  `data` and `usr` lines.

</dd><dt>

`don`

</dt><dd>

  Asserted by the data *source* when a frame is complete.
  `vld` *must never* be concurrently asserted with `don`.

</dd><dt>

`rdy`

</dt><dd>

  Asserted by the data *sink* when it is ready to consume
  data or the end-of-frame marker (indicated by `don`).

  Thus a data item is transferred during a cycle when

    ( vld and rdy ) = '1'

  and an end-of-frame marker is transferred during a cycle
  when

    ( don and rdy ) = '1'

</dd></dl>


### Rules

#### No Withdrawal of Handshake

In neither direction the endpoint may deassert a handshake signal
once it has been asserted without it being "acknowledged" by the
core:

 - the data source *must not* deassert `vld` (once it
   has been asserted) before `vld and rdy = 1`.
 - the data source *must not* deassert `don` (once it
   has been asserted) before `don and rdy = 1`.
 - the data sink *must not* deassert `rdy` (once it
   has been asserted) before `(vld or don) and rdy = 1`.

#### No Throttling

The `Usb2Core` does not provide any data buffering (besides the
internal storage used for handling retransmission). Therefore,
once an endpoint signals it has data (*IN* endpoint asserting `vld`)
or is ready to receive data (*OUT* endpoint asserting `rdy`) it
must be able to transfer an entire chunk of the maximal packet
size supported by the endpoint or the remaining data of a frame
(whichever is less).

The core may throttle data by controlling `rdy` (*IN* direction)
or `vld` (*OUT* direction), respectively, but the endpoint *must not*.
Note, however, that *for non-ISO transactions* the core never throttles
traffic in *OUT* direction because data are supplied from the internal
packet buffer.

Mecatica USB provides a generic FIFO (`Usb2FifoEp.vhd`) for use by
endpoints which does provide buffering as well as clock-domain
crossing and which offers a simpler interface.

## Framing

The core's packet engine takes care of converting frames sent by
the endpoint into a sequence of *IN* packets of the maximum packet
size defined in the endpoint descriptor followed by a smaller
or *null* packet (AKA *ZLP* - zero-length packet) which marks the
last packet of a frame (see USB spec.).

Similarly, *OUT* packets are assembled into frames separated
by `don = 1` markers.

## Retransmission

The core takes care of retransmission and checksums etc. (non-ISO
endpoints only).

### *IN* Direction

In *IN* direction the core accepts one packet from the endpoint
and while transmitting to ULPI stores the packet into an internal
buffer. If the host does not `ACK` the packet then the core "replays"
it from the buffer. This operation is transparent to the endpoint
(`rdy` remains deasserted during a replay procedure).

### *OUT* Direction

Data are received into an internal buffer and the endpoint is only
notified (`vld = 1`) once the checksum has been validated. In case
of a bad checksum the buffer contents are erased and retransmission
by the host is triggered (by means of the USB data-toggle mechanism).
This operation is transparent to the endpoint.

Note that there is always a one-packet latency before the endpoint
may start reading packet data. I.e., a packet must have been successfully
received (into the internal buffer) and only then the endpoint is
notified via `vld`.

However, the endpoint *must* signal that it is willing to accept
a packet (`rdy = 1`) at the *start* of packet transmission. I.e.,
the core will not store a packet into its buffer if the destination
endpoint is not ready. Instead, the packet will be dropped resulting
in a "NAK" handshake. In case of a high-speed endpoint the `rdy`
state is polled (using the "PING" protocol) even before attemping
to send a packet.

## Non-ISO Endpoint to Core Transfer (*IN* direction)

In *IN* direction two modes of operation are supported: unframed
and framed transfers.

### Unframed Transfer

Unframed transfers are simpler but do not support the framing
mechanism defined by USB (a sequence of max-sized packets followed
by a non-max packet). It can only be used if the host-side does
not expect framing.

For unframed transfers the endpoint must assert the `bFramedInp`
signal (`bFramedInp = '1'`) and never assert `don`.

In unframed mode the core waits for `vld` to be asserted and
then keeps filling a packets until `vld` is deasserted or the
maximum packet size is reached. During each cycle when

    vld and rdy = '1'

a data octet is transferred to the core.

Note that it is not possible to send "*null*"-packets (ZLP) in unframed
mode.

### Framed Transfer

In framed mode the core takes care of fragmenting a frame into
chunks of the maximum packet size. Note, however, that

 - the endpoint *must not* deassert `vld` until the entire frame
   is transmitted.
 - the endpoint *must* deassert `vld` and assert `don` immediately
   after the last data item has been transferred.
 - null (empty) packets are supported. They are sent by asserting
   `don` without any preceding ("`vld`") data transfer.

It is "legal" for an endpoint to throttle traffic if it deasserts
`vld` *precisely* at boundaries of the maximum packet size.

## Non-ISO Core to Endpoint Transfer (*OUT* direction)

Data transfer in *OUT* direction differs slightly from *IN* direction

 - there is no unframed mode; the `don` frame markers may simply be
   consumed (by the endpoint signalling `rdy`) and discarded.
 - the semantics of `rdy` are different in order to support high-speed
   NYET/PING.

Data transfer is initiated by the endpoint asserting `rdy` to indicate
that it is ready to consume at least the maximum packet size of data.

Once the core observes `rdy` when the host attempts the next *OUT*
transaction the core stores data into its internal buffer. Once the
checksum is verified the core asserts `vld` and the endpoint must
consume the first octet.

Note that there is a latency of an entire packet involved. In order
to maintain high throughput the core must know if the endpoint would
be ready to accept a subsequent packet.

### Semantics of `rdy` After the First Item is Consumed

If `rdy` remains asserted *after the first item (octet) has been consumed*
then the core assumes that it may receive a next packet into its internal
buffer while the endpoint consumes the previous one and that the endpoint
eventually will be ready to consume this second packet as well.

If `rdy` is deasserted after the first item has been consumed then
the core will throttle further transfers (reverting to PING in the
high-speed case) until `rdy` is re-asserted.

Because data are read out of the internal buffer the core keeps
`vld` asserted for the duration of an entire packet.

A high-speed *OUT* endpoint optimized for high-throughput may thus follow
e.g., the following simplified (and not fully optimized) algorithm:

  - Assert `rdy` if the endpoint can consume at least
    2\*max-packet size. Otherwize deassert `rdy` after
    consuming a data item (`vld`) or end-of-frame
    marker (`don`).
  - Consume data or end-of-frame markers while

        ((vld or don) and rdy) = '1'


#### Illustration of a Transfer Delaying Further Packets

This is a diagram of a single packet being transferred and
the endpoint indicating that it cannot accept a further 
back-to-back transfer.


             ____________________
    rdy:  __/                    \________
                              _____________
    vld:  ___________________/            
           0^   1^   2^      3^  4^  5^
            

    0: endpoint signals rdy.
    1: host issues an OUT transaction; Usb2Core accepts it
       since rdy = 1.
    2: core reads data into internal buffer.
    3: checksum has been validated, core asserts vld and the
       first item is transferred from the buffer to the endpoint.
    4: endpoint deasserts rdy signalling that after receiving
       the current packet there is no more space and a second
       packet must be delayed (NYET -> PING).
    5: current packet transmission from buffer to endpoint continues.
    
The host is done transferring the *OUT* packet around time 3 and
because rdy is deasserted at time 4 (cycle following the first
data beat) the core sends a "NYET" handshake which forces the host
to return to the "PING" protocol. This results in throttled throughput.

#### Illustration of a High-Throughput Transfer

This is a diagram of a single packet being transferred and
the endpoint indicating that it can accept a next transfer
back-to-back.


             _____________________________
    rdy:  __/                             
                              _____________
    vld:  ___________________/            
           0^   1^   2^      3^  4^  5^
            

    0: endpoint signals rdy.
    1: host issues an OUT transaction; Usb2Core accepts it
       since rdy = 1.
    2: core reads data into internal buffer.
    3: checksum has been validated, core asserts vld and the
       first item is transferred from the buffer to the endpoint.
    4: endpoint keeps rdy asserted signalling that after receiving
       the current packet it can continue receiving.
    5: current packet transmission from buffer to endpoint continues.
       The host may send a next packet which will be added to the
       buffer (while the first packet is being read out).

The host may continue sending an *OUT* packets after time 4 because
the endpoint indicated that it is capable of absorbing that second
packet once it has successfully be entered into the internal buffer.
 
## Isochronous Endpoint to Core Transfer (*IN* direction)

No buffering or retransmission is supported for isochronous transfers. However,
framed or unframed transfers are possible as outlined above (ISO transfers
honor the `bFramedInp` signal).

So-called high-bandwidth isochronous transfers use multiple packets per microframe
and need special attention because the USB spec. effectively requires that it is known
*in advance* how many packets per microframe are needed for any specific transfer.

This means that a pure streaming interface is not possible for isochronous *IN*
transfers.

The burden of keeping track of the number of packets per microframe is put on
the user; the `Usb2Core` cannot handle this internally. The application *must* indicate
to which of up to three "slots" a particular data item belongs by setting the bits

    mstInp.usr = "0010" -- first of three packets
    mstInp.usr = "0001" -- second of three or first of two packets
    mstInp.usr = "0000" -- third of three, second of two or single packet(s)

For "normal" iso transfers (only one packet per microframe) the `usr` bits can simply
tied to zero.

An endpoint may use the `usb2Rx.pktHdr.sof` flag to synchronize transmission with
(micro)-frames.

## Isochronous Core to Endpoint Transfer (*OUT* direction)

Isochronous *OUT* transfers do not support packet buffering or retransmission.
USB-short packet framing is not supported natively either. I.e., the application
must check the received packet size and reassemble frames when needed.

Data are streamed out as they arrive and individual packets are throttled with the
`vld` flag and delimited with the `don` flag.  When `don` is asserted the endpoint
must inspect `err` and implement proper error handling. `err` indicates a checksum-error
during packet reception.

A high-bandwidth endpoint also must check proper sequencing when multiple packets
are expected in a microframe. Multiple packets received in a microframe have their
`mstOut.usr` bits set as follows:

    mstOut.usr = "0000" -- first  ISO packet received in current microframe
    mstOut.usr = "0001" -- second ISO packet received in current microframe
    mstOut.usr = "0010" -- third  ISO packet received in current microframe

Note that the `subOut.rdy` flag is ignored for isochronous *OUT* transactions since
the endpoint is always assumed to be ready for data.

An endpoint may use the `usb2Rx.pktHdr.sof` flag to synchronize reception with
(micro)-frames.
