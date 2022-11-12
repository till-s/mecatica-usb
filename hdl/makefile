GHDL=ghdl
VIVADO=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/

SRCS+= UsbUtilPkg.vhd
SRCS+= UlpiPkg.vhd Usb2Pkg.vhd
SRCS+= Usb2TstPkg.vhd
SRCS+= Usb2AppCfgPkg.vhd
SRCS+= Usb2DescPkg.vhd
SRCS+= UlpiIO.vhd UlpiIOTb.vhd
SRCS+= Usb2PktRx.vhd UsbCrcTbl.vhd UsbCrcTblTb.vhd
SRCS+= Usb2PktTx.vhd
SRCS+= Usb2PktProc.vhd
SRCS+= Bram.vhd
SRCS+= Usb2StdCtlEp.vhd
SRCS+= Usb2Core.vhd
SRCS+= Usb2PktProcTb.vhd
SRCS+= Usb2PktTxTb.vhd

GHDLFLAGS=$(addprefix -P,$(VIVADO)) -g

PROG=ulpiiotb usbcrctbltb usb2pktproctb usb2pkttxtb

all: $(PROG)
	for i in $(PROG); do if ! ./$$i; then echo "$$i FAILED"; exit 1; fi  done
	echo "All Tests PASSED"

build: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

$(PROG): $(SRCS:%.vhd=%.o)
	$(GHDL) -e $(GHDLFLAGS) -Wl,-no-pie $@

Usb2PktProcTb.o UlpiIOTb.o: UlpiIO.o Usb2PktRx.o Usb2PktTx.o Usb2Core.o
Usb2PktTxTb.o Usb2Core.o Usb2PktProcTb.o UlpiIO.o Usb2PktRx.o Usb2PktTx.o Usb2PktProc.o Usb2StdCtlEp.o Usb2TstPkg.o: UsbUtilPkg.o UlpiPkg.o Usb2Pkg.o Usb2DescPkg.o
Usb2PktRx.o Usb2PktTx.o: UsbCrcTbl.o
UsbCrcTblTb.o: UsbCrcTbl.o Usb2Pkg.o
Usb2PktProcTb.o: Usb2TstPkg.o Usb2PktProc.o Usb2StdCtlEp.o
Usb2PktProc.o: Bram.o

Usb2Core.o: UlpiIO.o Usb2PktProc.o Usb2PktRx.o Usb2PktTx.o Usb2StdCtlEp.o

Usb2PktTxTb.o: UlpiIO.o Usb2PktTx.o

Usb2DescPkg.o: Usb2AppCfgPkg.o
Usb2AppCfgPkg.o Usb2DescPkg.o: Usb2Pkg.o
Usb2StdCtlEp.o: Usb2DescPkg.o

$(patsubst %.vhd,%.o,$(filter %Tb.vhd,$(SRCS))): Usb2TstPkg.o

.PHONY: all build clean

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw
