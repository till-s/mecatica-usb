# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

GHDL=ghdl
VIVADO=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/
vpath %.vhd ../hdl
GHDLFLAGS=$(addprefix -P,$(VIVADO)) -g

-include config.mk

SRCS+= Usb2UtilPkg.vhd
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
SRCS+= Usb2Fifo.vhd
SRCS+= Usb2FifoTb.vhd
SRCS+= Usb2FifoEp.vhd
SRCS+= Usb2FifoEpTb.vhd
SRCS+= CDCACMSendBreak.vhd
SRCS+= UlpiLineState.vhd
SRCS+= Usb2IsoTb.vhd
SRCS+= UlpiIOBuf.vhd
SRCS+= UlpiIOBufTb.vhd


PROG=UlpiIOTb UsbCrcTblTb Usb2PktProcTb Usb2PktTxTb Usb2FifoTb Usb2FifoEpTb Usb2HskTb UlpiIOBufTb Usb2IsoTb

all: $(PROG)
	for i in $(PROG); do if ! ./$$i; then echo "$$i FAILED"; exit 1; fi  done
	echo "All Tests PASSED"

build: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $<

$(PROG): %Tb : %Tb.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ -Wl,-no-pie $@

$(patsubst %.vhd,%.o,$(filter-out %Pkg.vhd, $(SRCS))): Usb2Pkg.o UlpiPkg.o Usb2UtilPkg.o Usb2DescPkg.o

Usb2DescPkg.o: Usb2AppCfgPkg.o
Usb2AppCfgPkg.o Usb2DescPkg.o: Usb2Pkg.o
Usb2TstPkg.o: Usb2Pkg.o UlpiPkg.o Usb2UtilPkg.o

$(patsubst %.vhd,%.o,$(filter %Tb.vhd,$(SRCS))): Usb2TstPkg.o

UlpiIO.o: UlpiIOBuf.o
Usb2Core.o: UlpiIO.o UlpiLineState.o Usb2PktRx.o Usb2PktTx.o Usb2PktProc.o Usb2StdCtlEp.o
Usb2FifoEp.o: Usb2Fifo.o
Usb2Fifo.o: Usb2Bram.o
Usb2PktProc.o: Usb2Bram.o
Usb2PktRx.o: UsbCrcTbl.o
Usb2PktTx.o: UsbCrcTbl.o

UlpiIOBufTb.o: UlpiIOBuf.o
UlpiIOTb.o: UlpiIO.o Usb2PktRx.o Usb2PktTx.o
Usb2FifoEpTb.o: Usb2Core.o Usb2FifoEp.o CDCACMSendBreak.o
Usb2FifoTb.o: Usb2Fifo.o
Usb2HskTb.o: Usb2PktTx.o UlpiIO.o
Usb2IsoTb.o: Usb2Core.o
Usb2PktProcTb.o: Usb2Core.o
Usb2PktTxTb.o: Usb2PktTx.o UlpiIO.o
UsbCrcTblTb.o: UsbCrcTbl.o

.PHONY: all build clean

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw
