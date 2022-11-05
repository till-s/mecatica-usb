GHDL=ghdl

VIVADO=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/

SRCS+= UsbUtilPkg.vhd
SRCS+= UlpiPkg.vhd Usb2Pkg.vhd
SRCS+= UlpiIO.vhd UlpiIOTb.vhd
SRCS+= Usb2PktRx.vhd UsbCrcTbl.vhd UsbCrcTblTb.vhd
SRCS+= Usb2PktTx.vhd
SRCS+= Usb2PktProc.vhd
SRCS+= Usb2PktProcTb.vhd
SRCS+= Bram.vhd
SRCS+= Usb2StdCtlEp.vhd
SRCS+= Usb2DescPkg.vhd
SRCS+= Usb2AppCfgPkg.vhd

PROG=ulpiiotb usbcrctbltb usb2pktproctb

all: $(PROG)
	for i in $(PROG); do ./$$i; done

build: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(addprefix -P,$(VIVADO)) $<

$(PROG): $(SRCS:%.vhd=%.o)
	$(GHDL) -e $(addprefix -P,$(VIVADO)) -Wl,-no-pie $@

Usb2PktProcTb.o UlpiIOTb.o: UlpiIO.o UlpiPkg.o Usb2Pkg.o Usb2PktRx.o Usb2PktTx.o
Usb2PktProcTb.o UlpiIO.o Usb2PktRx.o Usb2PktTx.o Usb2PktProc.o Usb2StdCtlEp.o: UsbUtilPkg.o UlpiPkg.o Usb2Pkg.o
Usb2PktRx.o Usb2PktTx.o: UsbCrcTbl.o
UsbCrcTblTb.o: UsbCrcTbl.o Usb2Pkg.o
Usb2PktProcTb.o: Usb2PktProc.o Usb2StdCtlEp.o
Usb2PktProc.o: Bram.o

Usb2DescPkg.o: Usb2AppCfgPkg.o
Usb2AppCfgPkt.o Usb2DescPkg.o: Usb2Pkg.o
Usb2StdCtlEp.o: Usb2DescPkg.o

.PHONY: all build clean

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw
