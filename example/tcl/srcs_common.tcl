# Copyright Till Straumann, 2026. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

set common_srcs_dir [file dir [info script]]

set example_common_src_files [list \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2Pkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2PrivPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/UlpiPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2UtilPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2AppCfgPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2DescPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/UlpiIOBuf.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/UlpiFSLSEmul.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2FSLSRxBitShift.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2FSLSRx.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2FSLSTx.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/UlpiIO.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/UlpiLineState.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2Bram.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2CCSync.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2MboxSync.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/UsbCrcTbl.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2PktRx.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2PktTx.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2PktProc.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2StdCtlEp.vhd"] \
 [file normalize "${common_srcs_dir}/../../core/hdl/Usb2Core.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/common/hdl/Usb2Fifo.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/common/hdl/Usb2FifoEp.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/common/hdl/Usb2EpCDCEtherNotify.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/common/hdl/Usb2EpGenericCtlPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/common/hdl/Usb2EpGenericCtl.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/common/hdl/Usb2MuxEpCtlPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/common/hdl/Usb2MuxEpCtl.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCACM/hdl/Usb2EpCDCACMCtl.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCACM/hdl/Usb2EpCDCACMNotify.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCACM/hdl/Usb2EpCDCACM.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/AUDIO/hdl/Usb2EpAudioCtl.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/AUDIO/hdl/Usb2EpAudioInpStrm.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/AUDIO/hdl/Usb2EpI2SPlayback.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/AUDIO/hdl/Usb2EpBADDSpkr.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCECM/hdl/Usb2EpCDCECM.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCNCM/hdl/Usb2EpCDCNCMCtl.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCNCM/hdl/Usb2EpCDCNCMInp.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCNCM/hdl/Usb2EpCDCNCMOut.vhd"] \
 [file normalize "${common_srcs_dir}/../../endpoints/CDCNCM/hdl/Usb2EpCDCNCM.vhd"] \
 [file normalize "${common_srcs_dir}/../hdl/StdLogPkg.vhd"] \
 [file normalize "${common_srcs_dir}/../hdl/Usb2ExampleDev.vhd"] \
]

unset common_srcs_dir
