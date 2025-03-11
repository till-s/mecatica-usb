# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

GHDL=ghdl
VIVADO=/opt/ghdl/v2.0.0-gcc/vivado-2021.2/
vpath %.vhd ../core/hdl $(wildcard ../endpoints/*/hdl)
GHDLFLAGS=$(addprefix -P,$(VIVADO)) -g

-include config.mk

SRCS+= Usb2UtilPkg.vhd
SRCS+= UlpiPkg.vhd Usb2Pkg.vhd Usb2PrivPkg.vhd
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
SRCS+= Usb2FifoFrmdTb.vhd
SRCS+= Usb2FifoAsyncTb.vhd
SRCS+= Usb2FifoEp.vhd
SRCS+= Usb2FifoEpTb.vhd
SRCS+= Usb2FifoEpFrmdTb.vhd
SRCS+= Usb2EpCDCACM.vhd
SRCS+= Usb2EpCDCACMCtl.vhd
SRCS+= Usb2EpCDCACMNotify.vhd
SRCS+= UlpiLineState.vhd
SRCS+= Usb2IsoTb.vhd
SRCS+= UlpiIOBuf.vhd
SRCS+= UlpiIOBufTb.vhd
SRCS+= UlpiIOBufAltTb.vhd
SRCS+= Usb2EpAudioCtl.vhd
SRCS+= Usb2EpAudioCtlTb.vhd
SRCS+= Usb2CCSync.vhd
SRCS+= Usb2MboxSync.vhd
ifneq ($(VIVADO),)
# this one needs unisim
SRCS += Usb2EpI2SPlayback.vhd
SRCS += Usb2EpI2SPlaybackTb.vhd
endif
SRCS += OthSpeedCfgTb.vhd
SRCS += Usb2EpCDCEtherNotify.vhd
SRCS += Usb2EpGenericCtlPkg.vhd
SRCS += Usb2EpGenericCtl.vhd
SRCS += Usb2EpCDCNCM.vhd
SRCS += Usb2EpCDCNCMOut.vhd
SRCS += Usb2EpCDCNCMCtl.vhd
SRCS += Usb2EpCDCNCMInp.vhd
SRCS += Usb2EpCDCNCMInpTb.vhd
SRCS += Usb2EpCDCNCMOutTb.vhd
SRCS += Usb2Ep0StringTb.vhd
SRCS += Usb2CDCACMTb.vhd
SRCS += Usb2FSLSRx.vhd
SRCS += Usb2FSLSRxBitShift.vhd
SRCS += Usb2FSLSTx.vhd
SRCS += Usb2FSLSTb.vhd
SRCS += UlpiFSLSEmul.vhd
SRCS += Usb2PktProcFSLSTb.vhd
SRCS += Usb2ExtractMacAddrTb.vhd
SRCS += Usb2StrmBuf.vhd
SRCS += Usb2StrmBufTb.vhd


PROG+=UlpiIOTb
PROG+=UsbCrcTblTb
PROG+=Usb2PktProcTb
PROG+=Usb2PktTxTb
PROG+=Usb2FifoTb
PROG+=Usb2FifoFrmdTb
PROG+=Usb2FifoEpTb
PROG+=Usb2FifoEpFrmdTb
PROG+=Usb2HskTb
PROG+=UlpiIOBufAltTb
PROG+=UlpiIOBufTb
PROG+=Usb2IsoTb
PROG+=Usb2EpAudioCtlTb
PROG+=Usb2FifoAsyncTb
ifneq ($(VIVADO),)
PROG+=Usb2EpI2SPlaybackTb
endif
PROG += OthSpeedCfgTb
PROG += Usb2EpCDCNCMOutTb
PROG += Usb2EpCDCNCMInpTb
PROG += Usb2Ep0StringTb
PROG += Usb2CDCACMTb
PROG += Usb2FSLSTb
PROG += Usb2PktProcFSLSTb
PROG += Usb2ExtractMacAddrTb
PROG += Usb2StrmBufTb

all: test

test: $(addsuffix @run,$(PROG)) Usb2EpCDCNCMCheck Usb2FifoEpFrmdLstTb
	echo "All Tests PASSED"


.PHONY: $(addsuffix $@run, $(PROG))

$(addsuffix @run,$(PROG)):%@run:%
	./$(@:%@run=%) $($(@:%@run=%)_RUNFLAGS) --ieee-asserts=disable-at-0

#	for i in $(PROG); do if ! ./$$i $; then echo "$$i FAILED"; exit 1; fi  done

build: $(PROG)

%.o: %.vhd
	$(GHDL) -a $(GHDLFLAGS) $($(@:%.o=%)_GHDLFLAGS) $<

$(PROG): %Tb : %Tb.o
	$(GHDL) -e $(GHDLFLAGS) $($(@:%.o=%)_GHDLFLAGS) -o $@ -Wl,-no-pie $@

$(patsubst %.vhd,%.o,$(filter-out %Pkg.vhd, $(SRCS))): Usb2Pkg.o Usb2PrivPkg.o UlpiPkg.o Usb2UtilPkg.o Usb2DescPkg.o

Usb2DescPkg.o: Usb2AppCfgPkg.o Usb2UtilPkg.o
Usb2AppCfgPkg.o Usb2DescPkg.o: Usb2Pkg.o
Usb2TstPkg.o Usb2PrivPkg.o: Usb2Pkg.o UlpiPkg.o Usb2UtilPkg.o
Usb2EpGenericCtlPkg.o: Usb2Pkg.o Usb2UtilPkg.o

$(patsubst %.vhd,%.o,$(filter %Tb.vhd,$(SRCS))): Usb2TstPkg.o

UlpiIO.o: UlpiIOBuf.o
Usb2Core.o: UlpiIO.o UlpiLineState.o Usb2PktRx.o Usb2PktTx.o Usb2PktProc.o Usb2StdCtlEp.o UlpiFSLSEmul.o
Usb2FifoEp.o: Usb2Fifo.o Usb2CCSync.o Usb2Bram.o
Usb2MboxSync.o: Usb2CCSync.o
Usb2Fifo.o: Usb2Bram.o Usb2MboxSync.o
Usb2PktProc.o: Usb2Bram.o
Usb2PktRx.o: UsbCrcTbl.o
Usb2PktTx.o: UsbCrcTbl.o

UlpiIOBufTb.o: UlpiIOBuf.o
UlpiIOBufAltTb.o: UlpiIOBuf.o
UlpiIOTb.o: UlpiIO.o Usb2PktRx.o Usb2PktTx.o
Usb2FifoEpTb.o: Usb2Core.o Usb2FifoEp.o Usb2EpCDCACMCtl.o
Usb2EpCDCACMCtl.o: Usb2EpGenericCtlPkg.o Usb2EpGenericCtl.o
Usb2EpCDCACMNotify.o: Usb2CCSync.o
Usb2EpCDCACM.o: Usb2FifoEp.o Usb2EpCDCACMNotify.o Usb2EpCDCACMCtl.o
Usb2EpGenericCtl.o: Usb2EpGenericCtlPkg.o
Usb2FifoEpFrmdTb.o: Usb2Core.o Usb2FifoEp.o
Usb2FifoTb.o: Usb2Fifo.o
Usb2FifoFrmdTb.o: Usb2Fifo.o
Usb2FifoAsyncTb.o: Usb2Fifo.o
Usb2HskTb.o: Usb2PktTx.o UlpiIO.o
Usb2IsoTb.o: Usb2Core.o
Usb2PktProcTb.o: Usb2Core.o
Usb2PktTxTb.o: Usb2PktTx.o UlpiIO.o
UsbCrcTblTb.o: UsbCrcTbl.o
OthSpeedCfgTb.o: Usb2Core.o

Usb2EpAudioCtlTb.o: Usb2Core.o Usb2EpAudioCtl.o Usb2EpAudioInpStrm.o
Usb2EpI2SPlayback.o: Usb2CCSync.o
Usb2EpI2SPlaybackTb_GHDLFLAGS=-fsynopsys
Usb2EpI2SPlaybackTb.o: Usb2Core.o Usb2EpI2SPlayback.o

Usb2EPCDCNCMCtl.o: Usb2EpGenericCtl.o
Usb2EpCDCNCMOut.o: Usb2Bram.o
Usb2EpCDCNCMInp.o: Usb2Bram.o
Usb2EpCDCNCM.o: Usb2EpCDCNCMOut.o Usb2EpCDCNCMInp.o Usb2EpCDCNCMCtl.o Usb2EpCDCEtherNotify.o
Usb2EpCDCNCMOutTb.o: Usb2EpCDCNCM.o
Usb2EpCDCNCMInpTb.o: Usb2EpCDCNCMInp.o

Usb2EpCDCNCMOutTb: NCMOutTst.txt NCMOutCmp.txt
Usb2EpCDCNCMInpTb: NCMInpTst.txt

Usb2Ep0StringTb.o: Usb2Core.o
Usb2CDCACMTb.o: Usb2Core.o Usb2EpCDCACM.o

Usb2FSLSRx.o: UlpiPkg.o Usb2FSLSRxBitShift.o
Usb2FSLSTx.o: UlpiPkg.o

Usb2StrmBufTb.o: Usb2StrmBuf.o

Usb2ExtractMacAddrTb.o: Usb2Pkg.o UlpiPkg.o Usb2UtilPkg.o Usb2DescPkg.o Usb2AppCfgPkg.o

Usb2FSLSTb.o: UlpiPkg.o Usb2FSLSRx.o Usb2FSLSTx.o
Usb2PktProcFSLSTb.o: UlpiPkg.o Usb2Pkg.o Usb2PrivPkg.o Usb2UtilPkg.o Usb2TstPkg.o UlpiFSLSEmul.o Usb2PktRx.o Usb2PktTx.o Usb2PktProc.o

UlpiFSLSEmul.o: UlpiPkg.o Usb2UtilPkg.o Usb2FSLSRx.o Usb2FSLSTx.o Usb2CCSync.o

NCMInpTst.txt: NCMOutCmp.txt
	cp $^ $@

NCMOutTst.txt NCMOutCmp.txt:
	./ncm.py -pNCM -o

NCMInpCmp.txt: Usb2EpCDCNCMInpTb
	./$^

Usb2EpCDCNCMCheck: NCMInpCmp.txt
	./ncm.py -i

.PHONY: all build clean Usb2EpCDCNCMCheck Usb2FifoEpFrmdLstTb

Usb2FifoEpFrmdLstTb: Usb2FifoEpFrmdTb@run
Usb2FifoEpFrmdLstTb: Usb2FifoEpFrmdTb_RUNFLAGS=-gDON_IS_LAST_G=true
	

clean:
	$(RM) $(SRCS:%.vhd=%.o) work-*.cf ulpiiotb e~*.o $(PROG) dump.ghw
	$(RM) NCMOutTst.txt NCMOutCmp.txt
	$(RM) NCMInpTst.txt NCMInpCmp.txt
