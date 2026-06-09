# Example on Lattice CrossLink-NX Evaluation Board

This board happened to be available for me to test mecatica
with a Lattice device (most notably these don't support initializing
the fabric from the bitstream; all initialization requires a reset
signal).

The board uses a LIFCL-40-9BG400C device.

## ULPI Phy Board

I could re-use the same [board](git@github.com:till-s/kicad-pmod-ulpi-test.git)
that I had developed for the zybo board (vivado).

The board uses all three PMOD connectors available on the CrossLink
eval. board. Make sure to set jumpers for 3V3 IO for all banks!

## Example Functions

The example (by default) only enables the ACM function (as there
is no register interface to the other devices like on Zynq).

## Clocking

Unfortunately the ULPI board feeds its clock to a FPGA pin which
is not clock-capable (same problem encountered on ZYBO). Radiant's
DRCs reject this configuration stubbornly and it took me quite a
while to figure out how to disable this check (after all the docs
say it *is* possible to use general routing even if it is, of course,
much inferior).

Unlike vivado, radiant does not seem to offer clock buffer primitives
and thus gives us less control over how to work around the clock
routing problem.

I was only able to keep general routing to a minimum by engaging
a PLL (which then feeds the clock network). This also gives us
the option to introduce a phase shift if we have difficulties achieving
timing closure. It proved not to be necessary, however.

Unfortunately, radiant does not provide a way to instantiate
any IP from TCL so that we had to add all the IP design files to
git. Hope that doesn't violate the license agreement - I can't see
how you could share a project otherwise.

## How to Build the Example

Execute the following steps

     chdir <this_directory>
     radiantc tcl/Usb2Example.tcl

This creates a radiant project in a new 'Usb2Example/'
subdirectory. Start up the radiant GUI, navigate to the project
file, open and create the bitstream.

## Bitstream Notes

The programmer refused to do anything - turns out I had to ensure
the `ftdi_sio` kernel module (linux) was not bound to the FTDI.
The simplest way to achieve this is simply unloading the module.
A better way is writing suitable udev rules.
