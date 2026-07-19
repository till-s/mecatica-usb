-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Instantiation of a multiple functions.
-- LEGACY wrapper offering only a single ACM function

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;
use     work.Usb2MuxEpCtlPkg.all;
use     work.Usb2ExamplePkg.all;

entity Usb2ExampleDev is
   generic (
      ULPI_CLK_MODE_INP_G                : boolean          := true;
      ULPI_EMU_MODE_G                    : UlpiEmuModeType  := NONE;
      FSLS_INPUT_MODE_VPVM_G             : boolean          := true;

      -- descriptors
      DESCRIPTORS_G                      : Usb2ByteArray;
      -- whether to use BRAM to store descriptors
      DESCRIPTORS_BRAM_G                 : boolean         := true;

      LD_ACM_FIFO_DEPTH_INP_G            : natural         := 10;
      LD_ACM_FIFO_DEPTH_OUT_G            : natural         := 10;
      -- asynchronous EP clock ?
      CDC_ACM_ASYNC_G                    : boolean         := false;

      -- min. 2 ethernet frames -> 4kB
      LD_ECM_FIFO_DEPTH_INP_G            : natural         := 12;
      LD_ECM_FIFO_DEPTH_OUT_G            : natural         := 12;
      -- asynchronous EP clock ?
      CDC_ECM_ASYNC_G                    : boolean         := false;


      LD_NCM_RAM_DEPTH_INP_G             : natural         := 12;
      LD_NCM_RAM_DEPTH_OUT_G             : natural         := 12;
      -- asynchronous EP clock ?
      CDC_NCM_ASYNC_G                    : boolean         := false;

      -- asynchronous EP clock for audio IN (dev->host) interface
      AUD_INP_ASYNC_G                    : boolean         := false;
      LD_AUD_INP_FIFO_DEPTH_G            : natural         := 8;
      AUD_INP_VOL_RNG_MIN_G              : integer         := -127*256;
      AUD_INP_VOL_RNG_MAX_G              : integer         :=  127*256;
      AUD_INP_VOL_RNG_RES_G              : integer         :=    1*256;
      -- cannot be read from descriptors but must be such that the
      -- endpoint max. packet size is not overflown.
      AUD_INP_SAMPLE_FREQ_G              : natural         := 48000;

      -- BADD Speaker volume range
      BADD_VOL_RNG_MIN_G                 : integer         := -127*256;
      BADD_VOL_RNG_MAX_G                 : integer         := +127*256;
      BADD_VOL_RNG_RES_G                 : integer         :=    1*256;

      -- external control-endpoint agents
      CTL_EP0_AGENTS_CONFIG_G            : Usb2CtlEpAgentConfigArray := USB2_CTL_EP_AGENT_CONFIG_EMPTY_C;

      -- automatically request remote-wakeup when at least one
      -- inbound endpoint has data
      AUTO_REMWAKE_G                     : boolean         := true;

      MARK_DEBUG_EP0_CTL_MUX_G           : boolean         := false;
      MARK_DEBUG_ULPI_IO_G               : boolean         := false;
      MARK_DEBUG_ULPI_LINE_STATE_G       : boolean         := false;
      MARK_DEBUG_PKT_RX_G                : boolean         := false;
      MARK_DEBUG_PKT_TX_G                : boolean         := false;
      MARK_DEBUG_PKT_PROC_G              : boolean         := false;
      MARK_DEBUG_EP0_G                   : boolean         := false;
      MARK_DEBUG_SND_G                   : boolean         := false
   );
   port (
      -- sampling clock; required if ULPI_EMU_MODE_G /= NONE;
      -- used by a non-ulpi transceiver to sample the raw line
      -- signals. This clock must run at 4*ulpiClk and must be
      -- phase-locked to ulpiClk. The ulpiClk itself must run
      -- at the *bit rate* for non-emulation modes.
      fslsSmplClk          : in  std_logic := '0';
      fslsSmplRst          : in  std_logic := '0';
      -- FS/LS ULPI emulation interface
      fslsIb               : in  FsLsIbType := FSLS_IB_INIT_C;
      fslsOb               : out FsLsObType := FSLS_OB_INIT_C;

      usb2Clk              : in  std_logic;
      -- reset USB (** DONT *** create a loop usb2RstOut => usb2Rst )
      usb2Rst              : in  std_logic := '0';
      -- reset USB requested by host
      usb2RstOut           : out std_logic;
      -- reset the ulpi low-level interface; should not be necessary
      ulpiRst              : in  std_logic := '0';

      -- ULPI interface
      ulpiIb               : in  UlpiIbType := ULPI_IB_INIT_C;
      ulpiOb               : out UlpiObType := ULPI_OB_INIT_C;
      ulpiRx               : out UlpiRxType;
      -- Force a STP on the ulpi interface
      -- Only use if you know what you are doing.
      ulpiForceStp         : in  std_logic := '0';

      usb2RemoteWake       : in  std_logic := '0';
      usb2HiSpeedEn        : in  std_logic := '1';

      -- initiate a device disconnect from USB; once the USB interface is
      -- physically disconnected
      --    - usb2Rst is asserted internally (reflected in usb2DevStatus.usb2Rst)
      --    - usb2DisconnectAck is asserted (needed because usb2Rst could also
      --      be caused by a reset from the host)
      --    - core and endpoints remain in reset until ulpiRst is pulsed; this
      --      will restart everything.
      -- NOTE: not supported for the FSLS/emulation mode because the core
      --       has no control over the FS/LS pull-ups.
      usb2DisconnectReq    : in  std_logic := '0';
      usb2DisconnectAck    : out std_logic := '0';

      ulpiRegReq           : in  UlpiRegReqType                                 := ULPI_REG_REQ_INIT_C;
      ulpiRegRep           : out UlpiRegRepType;

      -- Descriptor BRAM interface (only if DESCRIPTORS_BRAM_G => true)
      usb2DescRWClk        : in  std_logic                                      := '0';
      usb2DescRWIb         : in  Usb2DescRWIbType                               := USB2_DESC_RW_IB_INIT_C;
      usb2DescRWOb         : out Usb2DescRWObType                               := USB2_DESC_RW_OB_INIT_C;

      -- External EP0 agent(s)
      usb2Ep0ReqParam      : out Usb2CtlReqParamArray( CTL_EP0_AGENTS_CONFIG_G'range );
      usb2Ep0ObExt         : out Usb2EndpPairObType;
      usb2Ep0IbExt         : in  Usb2EndpPairIbArray( CTL_EP0_AGENTS_CONFIG_G'range ) := (others => USB2_ENDP_PAIR_IB_INIT_C );
      usb2Ep0CtlExt        : in  Usb2CtlExtArray( CTL_EP0_AGENTS_CONFIG_G'range ):= (others => USB2_CTL_EXT_NAK_C);

      -- device status
      usb2DevStatus        : out Usb2DevStatusType;

      -- ACM FIFO CLOCK DOMAIN
      acmFifoClk           : in  std_logic := '0';
      acmFifoRstOut        : out std_logic := '0';

      acmFifoOutDat        : out Usb2ByteType                                   := (others => '0');
      acmFifoOutEmpty      : out std_logic                                      := '0';
      acmFifoOutFill       : out unsigned(15 downto 0)                          := (others => '0');
      acmFifoOutRen        : in  std_logic                                      := '1';

      acmFifoInpDat        : in  Usb2ByteType                                   := (others => '0');
      acmFifoInpFull       : out std_logic                                      := '0';
      acmFifoInpFill       : out unsigned(15 downto 0)                          := (others => '0');
      acmFifoInpWen        : in  std_logic                                      := '1';
      acmFifoInpMinFill    : in  unsigned(LD_ACM_FIFO_DEPTH_INP_G - 1 downto 0) := (others => '0');
      acmFifoInpTimer      : in  unsigned(31 downto 0)                          := (others => '0');

      -- only supported if respective capabilites are
      -- enabled in the descriptors.
      acmLineBreak         : out std_logic := '0';
      acmDTR               : out std_logic := '0';
      acmRTS               : out std_logic := '0';
      acmDCD               : in  std_logic := '0';
      acmDSR               : in  std_logic := '0';
      acmOverRun           : in  std_logic := '0';
      acmParityError       : in  std_logic := '0';
      acmFramingError      : in  std_logic := '0';
      acmRingDetect        : in  std_logic := '0';
      acmBreakState        : in  std_logic := '0';

      -- ACM extra control bits
      -- *** IN THE USB2 CLOCK DOMAIN ***
      -- *** You must synchronize these yourself when driving from
      -- *** the acmFifoClk domain (and CDC_ACM_ASYNC_G => true)
      acmRate              : out unsigned(31 downto 0) := (others => '0');
      acmStopBits          : out unsigned( 1 downto 0) := (others => '0');
      acmParity            : out unsigned( 2 downto 0) := (others => '0');
      acmDataBits          : out unsigned( 4 downto 0) := (others => '0');

      -- functionality of the ACM interface; Fifo interface
      -- to this entity is only active if this input is asserted.
      -- Otherwise 'blast' or 'loopback' mode are active.
      acmFifoLocal         : in  std_logic := '0';

      baddVolMaster        : out signed(15 downto 0)  := (others => '0');
      baddVolLeft          : out signed(15 downto 0)  := (others => '0');
      baddVolRight         : out signed(15 downto 0)  := (others => '0');
      baddMuteMaster       : out std_logic            := '0';
      baddMuteLeft         : out std_logic            := '0';
      baddMuteRight        : out std_logic            := '0';
      baddPowerState       : out unsigned(1 downto 0) := (others => '0');

      -- ECM FIFO CLOCK DOMAIN
      ecmFifoClk           : in  std_logic    := '0';
      ecmFifoRstOut        : out std_logic    := '0';

      ecmFifoOutDat        : out Usb2ByteType                                   := (others => '0');
      ecmFifoOutLast       : out std_logic                                      := '0';
      ecmFifoOutEmpty      : out std_logic                                      := '0';
      ecmFifoOutFill       : out unsigned(15 downto 0)                          := (others => '0');
      ecmFifoOutFrms       : out unsigned(15 downto 0)                          := (others => '0');
      ecmFifoOutRen        : in  std_logic                                      := '1';

      ecmFifoInpDat        : in  Usb2ByteType                                   := (others => '0');
      ecmFifoInpLast       : in  std_logic                                      := '0';
      ecmFifoInpFull       : out std_logic                                      := '0';
      ecmFifoInpFill       : out unsigned(15 downto 0)                          := (others => '0');
      ecmFifoInpWen        : in  std_logic                                      := '0';
      ecmFifoInpMinFill    : in  unsigned(LD_ECM_FIFO_DEPTH_INP_G - 1 downto 0) := (others => '0');
      ecmFifoInpTimer      : in  unsigned(31 downto 0)                          := (others => '0');

      ecmCarrier           : in  std_logic    := '0';

      -- other ECM status signals in usb2Clk domain!
      ecmPacketFilter      : out std_logic_vector(4 downto 0)                   := (others => '1');
      ecmSpeedInp          : in  unsigned(31 downto 0)                          := to_unsigned( 100000000, 32 );
      ecmSpeedOut          : in  unsigned(31 downto 0)                          := to_unsigned( 100000000, 32 );

      -- NCM FIFO CLOCK DOMAIN
      ncmFifoClk           : in  std_logic    := '0';
      ncmFifoRstOut        : out std_logic    := '0';

      ncmFifoOutDat        : out Usb2ByteType := (others => '0');
      ncmFifoOutLast       : out std_logic    := '0';
      ncmFifoOutAbrt       : in  std_logic    := '0';
      ncmFifoOutEmpty      : out std_logic    := '0';
      ncmFifoOutNeedCrc    : out std_logic    := '0';
      ncmFifoOutRen        : in  std_logic    := '1';

      ncmFifoInpDat        : in  Usb2ByteType := (others => '0');
      ncmFifoInpLast       : in  std_logic    := '1';
      ncmFifoInpAbrt       : in  std_logic    := '0';
      ncmFifoInpBusy       : out std_logic    := '1';
      ncmFifoInpFull       : out std_logic    := '0';
      ncmFifoInpAvail      : out signed(15 downto 0) := (others => '0');
      ncmFifoInpWen        : in  std_logic    := '0';

      ncmCarrier           : in  std_logic    := '0';

      -- other NCM status signals in usb2Clk domain!
      ncmPacketFilter      : out std_logic_vector(4 downto 0) := (others => '1');
      ncmSpeedInp          : in  unsigned(31 downto 0)        := to_unsigned( 100000000, 32 );
      ncmSpeedOut          : in  unsigned(31 downto 0)        := to_unsigned( 100000000, 32 );
      ncmMacAddr           : out Usb2ByteArray(0 to 5)        := (others => (others => '0'));
      -- set multicast filters request is streamed out here
      ncmMCFilterDat       : out Usb2ByteType := (others => '0');
      -- request is terminated by vld = '1', don = '1'. During this
      -- cycle the data are *not* valid (allows for clearing the filters
      -- with a single cycle (vld = don = '1'). 'lst' is asserted during
      -- the last data-valid cycle.
      -- There might be gaps with 'vld' deasserted. Receiver must wait for
      -- 'don' to terminate reception.
      ncmMCFilterVld       : out std_logic := '0';
      ncmMCFilterLst       : out std_logic := '0';
      ncmMCFilterDon       : out std_logic := '0';

      -- I2S
      i2sBCLK              : in  std_logic := '0';
      i2sPBLRC             : in  std_logic := '0';
      i2sPBDAT             : out std_logic := '0';

      -- audio INP stream
      -- clock -- unused if AUD_INP_ASYNC_G = false
      -- the fifo clock must be synchronous to the audio sample clock
      -- and at least num_channels*sample_size_in_bytes times faster
      -- than the audio clock.
      audioInpFifoClk      : in  std_logic := '0';
      audioInpFifoRstOut   : out std_logic := '0';
      -- up to 2-channels with 24 bits. Actual number of bits used is
      -- defined by the descriptors.
      audioInpFifoDat      : in  std_logic_vector(47 downto 0) := (others => '0');
      audioInpFifoVld      : in  std_logic := '0';

      -- always in the usb clock domain!
      audioInpVolMaster    : out signed(15 downto 0)  := (others => '0');
      audioInpVolLeft      : out signed(15 downto 0)  := (others => '0');
      audioInpVolRight     : out signed(15 downto 0)  := (others => '0');
      audioInpMuteMaster   : out std_logic            := '0';
      audioInpMuteLeft     : out std_logic            := '0';
      audioInpMuteRight    : out std_logic            := '0';
      audioInpPowerState   : out unsigned(1 downto 0) := (others => '0');
      audioInpSelectorSel  : out unsigned(7 downto 0) := (others => '0')

   );
end entity Usb2ExampleDev;

architecture Impl of Usb2ExampleDev is

   function ACM_CFG_F return Usb2MultiAcmCfgArray is
      variable v : Usb2MultiAcmCfgArray(0 to 0);
   begin
      v(0)                := USB2_MULTI_ACM_CFG_DFLT_C;
      v(0).ldFifoDepthInp := LD_ACM_FIFO_DEPTH_INP_G;
      v(0).ldFifoDepthOut := LD_ACM_FIFO_DEPTH_OUT_G;
      v(0).clkAsync       := CDC_ACM_ASYNC_G;
      return v;
   end function ACM_CFG_F;

   signal acmFifoClkLoc   : std_logic_vector(0 downto 0);
   signal acmFifoOb       : Usb2AcmFifoObArray(0 to 0);
   signal acmFifoIb       : Usb2AcmFifoIbArray(0 to 0);
   signal acmFifoIbExtra  : Usb2AcmFifoIbExtraArray(0 to 0);

begin

   acmFifoClkLoc(0)                   <= acmFifoClk;

   acmFifoRstOut                      <= acmFifoOb(0).rst;
   acmFifoOutDat                      <= acmFifoOb(0).outDat;
   acmFifoOutEmpty                    <= acmFifoOb(0).outEmpty;
   acmFifoOutFill                     <= acmFifoOb(0).outFill;
   acmFifoInpFull                     <= acmFifoOb(0).inpFull;
   acmFifoInpFill                     <= acmFifoOb(0).inpFill;
   acmLineBreak                       <= acmFifoOb(0).lineBreak;
   acmDTR                             <= acmFifoOb(0).DTR;
   acmRTS                             <= acmFifoOb(0).RTS;
   acmRate                            <= acmFifoOb(0).bitRate;
   acmStopBits                        <= acmFifoOb(0).stopBits;
   acmParity                          <= acmFifoOb(0).parity;
   acmDataBits                        <= acmFifoOb(0).dataBits;

   acmFifoIb(0).outRen                <= acmFifoOutRen;
   acmFifoIb(0).inpDat                <= acmFifoInpDat;
   acmFifoIb(0).inpWen                <= acmFifoInpWen;
   acmFifoIb(0).loopback              <= not acmFifoLocal;
   acmFifoIb(0).DCD                   <= acmDCD;
   acmFifoIb(0).DSR                   <= acmDSR;
   acmFifoIb(0).overRun               <= acmOverRun;
   acmFifoIb(0).parityError           <= acmParityError;
   acmFifoIb(0).framingError          <= acmFramingError;
   acmFifoIb(0).ringDetect            <= acmRingDetect;
   acmFifoIb(0).breakState            <= acmBreakState;

   acmFifoIbExtra(0).inpMinFill       <= resize( acmFifoInpMinFill, acmFifoIbExtra(0).inpMinFill'length );
   acmFifoIbExtra(0).inpTimer         <= acmFifoInpTimer;
 
   U_DEV : entity work.Usb2ExampleMultiAcmDev
      generic map (
         ULPI_CLK_MODE_INP_G          => ULPI_CLK_MODE_INP_G,
         ULPI_EMU_MODE_G              => ULPI_EMU_MODE_G,
         FSLS_INPUT_MODE_VPVM_G       => FSLS_INPUT_MODE_VPVM_G,
         DESCRIPTORS_G                => DESCRIPTORS_G,
         DESCRIPTORS_BRAM_G           => DESCRIPTORS_BRAM_G,
         ACM_FIFO_CONFIG_G            => ACM_CFG_F,
         LD_ECM_FIFO_DEPTH_INP_G      => LD_ECM_FIFO_DEPTH_INP_G,
         LD_ECM_FIFO_DEPTH_OUT_G      => LD_ECM_FIFO_DEPTH_OUT_G,
         CDC_ECM_ASYNC_G              => CDC_ECM_ASYNC_G,
         LD_NCM_RAM_DEPTH_INP_G       => LD_NCM_RAM_DEPTH_INP_G,
         LD_NCM_RAM_DEPTH_OUT_G       => LD_NCM_RAM_DEPTH_OUT_G,
         CDC_NCM_ASYNC_G              => CDC_NCM_ASYNC_G,
         AUD_INP_ASYNC_G              => AUD_INP_ASYNC_G,
         LD_AUD_INP_FIFO_DEPTH_G      => LD_AUD_INP_FIFO_DEPTH_G,
         AUD_INP_VOL_RNG_MIN_G        => AUD_INP_VOL_RNG_MIN_G,
         AUD_INP_VOL_RNG_MAX_G        => AUD_INP_VOL_RNG_MAX_G,
         AUD_INP_VOL_RNG_RES_G        => AUD_INP_VOL_RNG_RES_G,
         AUD_INP_SAMPLE_FREQ_G        => AUD_INP_SAMPLE_FREQ_G,
         BADD_VOL_RNG_MIN_G           => BADD_VOL_RNG_MIN_G,
         BADD_VOL_RNG_MAX_G           => BADD_VOL_RNG_MAX_G,
         BADD_VOL_RNG_RES_G           => BADD_VOL_RNG_RES_G,
         CTL_EP0_AGENTS_CONFIG_G      => CTL_EP0_AGENTS_CONFIG_G,
         AUTO_REMWAKE_G               => AUTO_REMWAKE_G,
         MARK_DEBUG_EP0_CTL_MUX_G     => MARK_DEBUG_EP0_CTL_MUX_G,
         MARK_DEBUG_ULPI_IO_G         => MARK_DEBUG_ULPI_IO_G,
         MARK_DEBUG_ULPI_LINE_STATE_G => MARK_DEBUG_ULPI_LINE_STATE_G,
         MARK_DEBUG_PKT_RX_G          => MARK_DEBUG_PKT_RX_G,
         MARK_DEBUG_PKT_TX_G          => MARK_DEBUG_PKT_TX_G,
         MARK_DEBUG_PKT_PROC_G        => MARK_DEBUG_PKT_PROC_G,
         MARK_DEBUG_EP0_G             => MARK_DEBUG_EP0_G,
         MARK_DEBUG_SND_G             => MARK_DEBUG_SND_G
      )
      port map (
         fslsSmplClk                  => fslsSmplClk,
         fslsSmplRst                  => fslsSmplRst,
         fslsIb                       => fslsIb,
         fslsOb                       => fslsOb,
         usb2Clk                      => usb2Clk,
         usb2Rst                      => usb2Rst,
         usb2RstOut                   => usb2RstOut,
         ulpiRst                      => ulpiRst,
         ulpiIb                       => ulpiIb,
         ulpiOb                       => ulpiOb,
         ulpiRx                       => ulpiRx,
         ulpiForceStp                 => ulpiForceStp,
         usb2RemoteWake               => usb2RemoteWake,
         usb2HiSpeedEn                => usb2HiSpeedEn,
         usb2DisconnectReq            => usb2DisconnectReq,
         usb2DisconnectAck            => usb2DisconnectAck,
         ulpiRegReq                   => ulpiRegReq,
         ulpiRegRep                   => ulpiRegRep,
         usb2DescRWClk                => usb2DescRWClk,
         usb2DescRWIb                 => usb2DescRWIb,
         usb2DescRWOb                 => usb2DescRWOb,
         usb2Ep0ReqParam              => usb2Ep0ReqParam,
         usb2Ep0ObExt                 => usb2Ep0ObExt,
         usb2Ep0IbExt                 => usb2Ep0IbExt,
         usb2Ep0CtlExt                => usb2Ep0CtlExt,
         usb2DevStatus                => usb2DevStatus,
         acmFifoClk                   => acmFifoClkLoc,
         acmFifoOb                    => acmFifoOb,
         acmfifoIb                    => acmfifoIb,
         acmfifoIbExtra               => acmfifoIbExtra,
         baddVolMaster                => baddVolMaster,
         baddVolLeft                  => baddVolLeft,
         baddVolRight                 => baddVolRight,
         baddMuteMaster               => baddMuteMaster,
         baddMuteLeft                 => baddMuteLeft,
         baddMuteRight                => baddMuteRight,
         baddPowerState               => baddPowerState,
         ecmFifoClk                   => ecmFifoClk,
         ecmFifoRstOut                => ecmFifoRstOut,
         ecmFifoOutDat                => ecmFifoOutDat,
         ecmFifoOutLast               => ecmFifoOutLast,
         ecmFifoOutEmpty              => ecmFifoOutEmpty,
         ecmFifoOutFill               => ecmFifoOutFill,
         ecmFifoOutFrms               => ecmFifoOutFrms,
         ecmFifoOutRen                => ecmFifoOutRen,
         ecmFifoInpDat                => ecmFifoInpDat,
         ecmFifoInpLast               => ecmFifoInpLast,
         ecmFifoInpFull               => ecmFifoInpFull,
         ecmFifoInpFill               => ecmFifoInpFill,
         ecmFifoInpWen                => ecmFifoInpWen,
         ecmFifoInpMinFill            => ecmFifoInpMinFill,
         ecmFifoInpTimer              => ecmFifoInpTimer,
         ecmCarrier                   => ecmCarrier,
         ecmPacketFilter              => ecmPacketFilter,
         ecmSpeedInp                  => ecmSpeedInp,
         ecmSpeedOut                  => ecmSpeedOut,
         ncmFifoClk                   => ncmFifoClk,
         ncmFifoRstOut                => ncmFifoRstOut,
         ncmFifoOutDat                => ncmFifoOutDat,
         ncmFifoOutLast               => ncmFifoOutLast,
         ncmFifoOutAbrt               => ncmFifoOutAbrt,
         ncmFifoOutEmpty              => ncmFifoOutEmpty,
         ncmFifoOutNeedCrc            => ncmFifoOutNeedCrc,
         ncmFifoOutRen                => ncmFifoOutRen,
         ncmFifoInpDat                => ncmFifoInpDat,
         ncmFifoInpLast               => ncmFifoInpLast,
         ncmFifoInpAbrt               => ncmFifoInpAbrt,
         ncmFifoInpBusy               => ncmFifoInpBusy,
         ncmFifoInpFull               => ncmFifoInpFull,
         ncmFifoInpAvail              => ncmFifoInpAvail,
         ncmFifoInpWen                => ncmFifoInpWen,
         ncmCarrier                   => ncmCarrier,
         ncmPacketFilter              => ncmPacketFilter,
         ncmSpeedInp                  => ncmSpeedInp,
         ncmSpeedOut                  => ncmSpeedOut,
         ncmMacAddr                   => ncmMacAddr,
         ncmMCFilterDat               => ncmMCFilterDat,
         ncmMCFilterVld               => ncmMCFilterVld,
         ncmMCFilterLst               => ncmMCFilterLst,
         ncmMCFilterDon               => ncmMCFilterDon,
         i2sBCLK                      => i2sBCLK,
         i2sPBLRC                     => i2sPBLRC,
         i2sPBDAT                     => i2sPBDAT,
         audioInpFifoClk              => audioInpFifoClk,
         audioInpFifoRstOut           => audioInpFifoRstOut,
         audioInpFifoDat              => audioInpFifoDat,
         audioInpFifoVld              => audioInpFifoVld,
         audioInpVolMaster            => audioInpVolMaster,
         audioInpVolLeft              => audioInpVolLeft,
         audioInpVolRight             => audioInpVolRight,
         audioInpMuteMaster           => audioInpMuteMaster,
         audioInpMuteLeft             => audioInpMuteLeft,
         audioInpMuteRight            => audioInpMuteRight,
         audioInpPowerState           => audioInpPowerState,
         audioInpSelectorSel          => audioInpSelectorSel
      );
end architecture Impl;
