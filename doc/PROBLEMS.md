# ULPI Problems

On my test assembly using a USB3340 PHY in CLOCKIN mode
(i.e., the 60MHz clock is provided by the FPGA) I experienced
a strange problem (hi-speed):

TX transactions sometimes fail; the PHY does not seem
to to send anything on USB. I conclude this from

  - host reports transaction error
  - PHY does not report RXCMD (line-state change) after
    packet transmission.
  - successful TXCMD deassert NXT after a few bytes
    (probably because some internal buffer fills and
    the sync preamble has to be sent). The problematic
    packets lack this NXT deassertion.

Weirdly, the problem is correlated with what has been
received previously! If, e.g., the transmission was an ACK
to an OUT transacion then it worked when OUT sent all zeroes
but failed when the data were all FFx

```
OUT DATA0 0x00, 0x00, ...   -> ACK OK
OUT DATA0 0xff, 0xff, ...   -> ACK failed
```

the timing between EOP and ACK was identical. However, if I
delayed the ACK phase significantly (above what's allowed
by the USB2 spec) then ACK consistently was sent.

Eventually, I could solve this by tightening the constraints.

*** Strangely *** this came back with ISO transfers.
I could transfer 100s of megabytes via BULK (all kinds
of data) without any problem. But ISO OUT with feedback
IN (sound playback) behaved the same way ACK had earlier.
Note that I had BULK and ISO in the *same* design, same
constraints on the ULPI port etc.
And yet, playing silence (all zeros) works but playing
sound causes the feedback packet transmission to fail
(in the same way described above).

```
OK: (note that NXT usually also takes a 1cycle longer
    to be taken by NXT than the failing case)

OUT DATA0 0x00, 0x00, ... IN,  TXCMD, feedback data OK
                                                       ____     ___
DIR   ________________________________________________/    \___/   \
                                            __
STP   ____________________________________ /  \_______________________
                           _____    ______________
NXT   ____________________/     \__/              \____________________

DAT   00 00 00 00 00 _TXCMD__ d0 d0 d1 d2 d3 0 0 0 0 0  !squech, squelch


BAD:

                                               Utter silence on DIR
DIR   ___________________________________________________________
                                         __
STP   _________________________________ /  \_______________________
                         _______________________
NXT   __________________/                       \____________________

DAT   00 00 00 00 00 _TXCMD__ d0 d1 d2 d3 0 0 0 0 0 0 0 0 0 0 0 0 0 0

                       ^       ^                     ^
                  NXT earlier, no NXT deassertion   no line state upd
```

The timing from the previous RX (DIR deassertion) is the same in
both cases (6 clocks)

UPDATE: I built a second test board but loaded the REFCLK oscillator
and operate this one in OUTPUT clock mode. So far it has *not* 
exhibited this problem.
