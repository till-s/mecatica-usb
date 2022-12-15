GHDL=ghdl
VIVADO=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/

-include config.mk

SRCS+= UsbUtilPkg.vhd
SRCS+= UlpiPkg.vhd Usb2Pkg.vhd
SRCS+= Usb2TstPkg.vhd
SRCS+= Usb2AppCfgPkg.vhd
SRCS+= Usb2DescPkg.vhd
SRCS+= UlpiIO.vhd UlpiIOTb.vhd
SRCS+= Usb2PktRx.vhd UsbCrcTbl.vhd UsbCrcTblTb.vhd
SRCS+= Usb2PktTx.vhd
SRCS+= Usb2PktProc.vhd
SRCS+= Usb2Bram.vhd
SRCS+= Usb2StdCtlEp.vhd
SRCS+= Usb2Core.vhd
SRCS+= Usb2PktProcTb.vhd
SRCS+= Usb2PktTxTb.vhd
SRCS+= Usb2HskTb.vhd
SRCS+= Usb2FifoTb.vhd
SRCS+= Usb2FifoEp.vhd
SRCS+= Usb2FifoEpTb.vhd
SRCS+= CDCACMSendBreak.vhd
SRCS+= UlpiLineState.vhd
SRCS+= Usb2IsoTb.vhd

GHDLFLAGS=$(addprefix -P,$(VIVADO)) -g

PROG=UlpiIOTb UsbCrcTblTb Usb2PktProcTb Usb2PktTxTb Usb2FifoTb Usb2FifoEpTb Usb2HskTb 

all: $(PROG)
	for i in $(PROG); do if ! ./$$i; then echo "$$i FAILED"; exit 1; fi  done
	echo "All Tests PASSED"

build: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

.SECONDEXPANSION:

$(PROG): $$@.o $(patsubst %.vhd,%.o,$(filter-out $(addsuffix .vhd,$(PROG)),$(SRCS)))
	$(GHDL) -e $(GHDLFLAGS) -o $@ -Wl,-no-pie $@

Usb2PktProcTb.o UlpiIOTb.o: UlpiIO.o Usb2PktRx.o Usb2PktTx.o Usb2Core.o
Usb2FifoEpTb.o Usb2FifoEp.o Usb2PktTxTb.o Usb2HskTb.o Usb2Core.o Usb2PktProcTb.o UlpiIO.o Usb2PktRx.o Usb2PktTx.o Usb2PktProc.o Usb2StdCtlEp.o Usb2TstPkg.o: UsbUtilPkg.o UlpiPkg.o Usb2Pkg.o Usb2DescPkg.o
Usb2PktRx.o Usb2PktTx.o: UsbCrcTbl.o
UsbCrcTblTb.o: UsbCrcTbl.o Usb2Pkg.o
Usb2PktProcTb.o: Usb2Core.o Usb2TstPkg.o Usb2PktProc.o Usb2StdCtlEp.o
Usb2PktProc.o: Usb2Bram.o
Usb2IsoTb.o: Usb2Core.o Usb2TstPkg.o

Usb2Core.o: UlpiIO.o Usb2PktProc.o Usb2PktRx.o Usb2PktTx.o Usb2StdCtlEp.o UlpiLineState.o

Usb2HskTb.o Usb2PktTxTb.o: UlpiIO.o Usb2PktTx.o

CDCACMLineBreak.o: Usb2Pkg.o

Usb2DescPkg.o: Usb2AppCfgPkg.o
Usb2AppCfgPkg.o Usb2DescPkg.o: Usb2Pkg.o
Usb2StdCtlEp.o: Usb2DescPkg.o

Usb2Fifo.o: Usb2Bram.o

Usb2FifoEp.o: Usb2Fifo.o

Usb2FifoTb.o: Usb2Fifo.o

Usb2FifoEpTb.o: Usb2FifoEp.o Usb2Core.o CDCACMSendBreak.o

UlpiLineState.o: UlpiPkg.o UsbUtilPkg.o

$(patsubst %.vhd,%.o,$(filter %Tb.vhd,$(SRCS))): Usb2TstPkg.o

.PHONY: all build clean

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw
