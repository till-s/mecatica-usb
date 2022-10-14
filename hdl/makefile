GHDL=ghdl

VIVADO=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/

SRCS+= UlpiIO.vhd UlpiPkg.vhd UlpiIOTb.vhd Usb2Pkg.vhd Usb2PktRx.vhd UsbCrcTbl.vhd

PROG=ulpiiotb

all: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(addprefix -P,$(VIVADO)) $<

$(PROG): $(SRCS:%.vhd=%.o)
	$(GHDL) -e $(addprefix -P,$(VIVADO)) -Wl,-no-pie $@

UlpiIOTb.o: UlpiIO.o UlpiPkg.o Usb2Pkg.o Usb2PktRx.o
UlpiIO.o Usb2PktRx.o: UlpiPkg.o Usb2Pkg.o
Usb2PktRx.o: UsbCrcTbl.o

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw
