GHDL=ghdl

VIVADO=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/

SRCS+= UsbUtilPkg.vhd
SRCS+= UlpiPkg.vhd Usb2Pkg.vhd
SRCS+= UlpiIO.vhd UlpiIOTb.vhd
SRCS+= Usb2PktRx.vhd UsbCrcTbl.vhd UsbCrcTblTb.vhd
SRCS+= Usb2PktTx.vhd

PROG=ulpiiotb usbcrctbltb

all: $(PROG)
	for i in $(PROG); do ./$$i; done

build: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(addprefix -P,$(VIVADO)) $<

$(PROG): $(SRCS:%.vhd=%.o)
	$(GHDL) -e $(addprefix -P,$(VIVADO)) -Wl,-no-pie $@

UlpiIOTb.o: UlpiIO.o UlpiPkg.o Usb2Pkg.o Usb2PktRx.o Usb2PktTx.o
UlpiIO.o Usb2PktRx.o Usb2PktTx.o: UsbUtilPkg.o UlpiPkg.o Usb2Pkg.o
UsbCrcTblTb.o: UsbCrcTbl.o Usb2Pkg.o

.PHONY: all build clean

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw
