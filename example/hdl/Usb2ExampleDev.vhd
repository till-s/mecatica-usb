-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Instantiation of a multiple endpoints.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;
use     work.Usb2AppCfgPkg.all;
use     work.Usb2MuxEpCtlPkg.all;

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

      ulpiRegReq           : in  UlpiRegReqType                                 := ULPI_REG_REQ_INIT_C;
      ulpiRegRep           : out UlpiRegRepType;

      -- Descriptor BRAM interface (only if DESCRIPTORS_BRAM_G => true)
      usb2DescRWClk        : in  std_logic                                      := '0';
      usb2DescRWIb         : in  Usb2DescRWIbType                               := USB2_DESC_RW_IB_INIT_C;
      usb2DescRWOb         : out Usb2DescRWObType                               := USB2_DESC_RW_OB_INIT_C;

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

      ecmPacketFilter      : out std_logic_vector(4 downto 0)                   := (others => '0');

      ecmCarrier           : in  std_logic    := '0';

      -- NCM FIFO CLOCK DOMAIN
      ncmFifoClk           : in  std_logic    := '0';
      ncmFifoRstOut        : out std_logic    := '0';

      ncmFifoOutDat        : out Usb2ByteType := (others => '0');
      ncmFifoOutLast       : out std_logic    := '0';
      ncmFifoOutEmpty      : out std_logic    := '0';
      ncmFifoOutRen        : in  std_logic    := '1';

      ncmFifoInpDat        : in  Usb2ByteType := (others => '0');
      ncmFifoInpLast       : in  std_logic    := '1';
      ncmFifoInpBusy       : out std_logic    := '1';
      ncmFifoInpFull       : out std_logic    := '0';
      ncmFifoInpAvail      : out signed(15 downto 0) := (others => '0');
      ncmFifoInpWen        : in  std_logic    := '0';

      ncmCarrier           : in  std_logic    := '0';

      i2sBCLK              : in  std_logic    := '0';
      i2sPBLRC             : in  std_logic    := '0';
      i2sPBDAT             : out std_logic    := '0'
   );
end entity Usb2ExampleDev;

architecture Impl of Usb2ExampleDev is

   function acmCapabilities return Usb2ByteType is
      variable i                     : integer;
      variable v                     : Usb2ByteType := (others => '0');
      constant IDX_BM_CAPABILITIES_C : natural      := 3;
   begin
      i := usb2NextCsDescriptor(DESCRIPTORS_G, 0, USB2_CS_DESC_SUBTYPE_CDC_ACM_C);
      assert i >= 0 report "CDCACM functional descriptor not found" severity failure;
      if ( i >= 0 ) then
         v := DESCRIPTORS_G( i + IDX_BM_CAPABILITIES_C );
      end if;
      return v;
   end function acmCapabilities;

   constant HAVE_ACM_C                         : boolean :=
      ( usb2NextIfcAssocDescriptor(
           DESCRIPTORS_G,
           0,
           USB2_IFC_CLASS_CDC_C,
           USB2_IFC_SUBCLASS_CDC_ACM_C,
           USB2_IFC_PROTOCOL_NONE_C
        ) >= 0 );
           
   constant HAVE_BADD_C                        : boolean :=
      ( usb2NextIfcAssocDescriptor(
           DESCRIPTORS_G,
           0,
           USB2_IFC_CLASS_AUDIO_C,
           USB2_IFC_SUBCLASS_AUDIO_SPEAKER_C
           -- accept UAC2 or UAC3
        ) >= 0 );

    constant HAVE_ECM_C                        : boolean :=
      ( usb2NextIfcAssocDescriptor(
           DESCRIPTORS_G,
           0,
           USB2_IFC_CLASS_CDC_C,
           USB2_IFC_SUBCLASS_CDC_ECM_C,
           USB2_IFC_PROTOCOL_NONE_C
        ) >= 0 );

    constant HAVE_NCM_C                        : boolean :=
      ( usb2NextIfcAssocDescriptor(
           DESCRIPTORS_G,
           0,
           USB2_IFC_CLASS_CDC_C,
           USB2_IFC_SUBCLASS_CDC_NCM_C,
           USB2_IFC_PROTOCOL_NONE_C
        ) >= 0 );
 
   constant N_EP_C                             : natural := usb2AppGetMaxEndpointAddr(DESCRIPTORS_G);

   constant CDC_ACM_BULK_EP_IDX_C              : natural := 0                       + ite( HAVE_ACM_C,  1, 0 );
   constant CDC_ACM_IRQ_EP_IDX_C               : natural := CDC_ACM_BULK_EP_IDX_C   + ite( HAVE_ACM_C,  1, 0 );
   constant BADD_ISO_EP_IDX_C                  : natural := CDC_ACM_IRQ_EP_IDX_C    + ite( HAVE_BADD_C, 1, 0 );
   constant CDC_ECM_BULK_EP_IDX_C              : natural := BADD_ISO_EP_IDX_C       + ite( HAVE_ECM_C,  1, 0 );
   constant CDC_ECM_IRQ_EP_IDX_C               : natural := CDC_ECM_BULK_EP_IDX_C   + ite( HAVE_ECM_C,  1, 0 );
   constant CDC_NCM_BULK_EP_IDX_C              : natural := CDC_ECM_IRQ_EP_IDX_C    + ite( HAVE_NCM_C,  1, 0 );
   constant CDC_NCM_IRQ_EP_IDX_C               : natural := CDC_NCM_BULK_EP_IDX_C   + ite( HAVE_NCM_C,  1, 0 );

   constant CDC_ACM_CTL_IFC_NUM_C              : natural := 0; -- uses 2 interfaces
   constant BADD_CTL_IFC_NUM_C                 : natural := CDC_ACM_CTL_IFC_NUM_C   + ite( HAVE_ACM_C,  2, 0 );
   constant CDC_ECM_CTL_IFC_NUM_C              : natural := BADD_CTL_IFC_NUM_C      + ite( HAVE_BADD_C, 2, 0 );
   constant CDC_NCM_CTL_IFC_NUM_C              : natural := CDC_ECM_CTL_IFC_NUM_C   + ite( HAVE_ECM_C,  2, 0 );

   constant CDC_ACM_BM_CAPABILITIES            : Usb2ByteType := acmCapabilities;
   constant ENBL_LINE_BREAK_C                  : boolean      := (CDC_ACM_BM_CAPABILITIES(2) = '1');
   constant ENBL_LINE_STATE_C                  : boolean      := (CDC_ACM_BM_CAPABILITIES(1) = '1');

   constant HAVE_ACM_AGENT_C                   : boolean := HAVE_ACM_C and ( ENBL_LINE_BREAK_C or ENBL_LINE_STATE_C );

   constant CDC_ACM_EP0_AGENT_IDX_C            : natural := 0;
   constant BADD_EP0_AGENT_IDX_C               : natural := CDC_ACM_EP0_AGENT_IDX_C + ite( HAVE_ACM_AGENT_C,  1, 0 );
   constant CDC_ECM_EP0_AGENT_IDX_C            : natural := BADD_EP0_AGENT_IDX_C    + ite( HAVE_BADD_C,       1, 0 );
   constant CDC_NCM_EP0_AGENT_IDX_C            : natural := CDC_ECM_EP0_AGENT_IDX_C + ite( HAVE_ECM_C,        1, 0 );
   constant NUM_EP0_AGENTS_C                   : natural := CDC_NCM_EP0_AGENT_IDX_C + ite( HAVE_NCM_C,        1, 0 );

   signal acmFifoDatInp                        : Usb2ByteType := (others => '0');
   signal acmFifoWenInp                        : std_logic    := '0';
   signal acmFifoFullInp                       : std_logic    := '0';
   signal acmFifoFilledInp                     : unsigned(LD_ACM_FIFO_DEPTH_INP_G downto 0) := (others => '0');
   signal acmFifoDatOut                        : Usb2ByteType := (others => '0');
   signal acmFifoRenOut                        : std_logic    := '0';
   signal acmFifoEmptyOut                      : std_logic    := '0';
   signal acmFifoFilledOut                     : unsigned(LD_ACM_FIFO_DEPTH_OUT_G downto 0) := (others => '0');
   signal acmFifoBlast                         : std_logic    := '0';
   signal acmFifoLoopback                      : std_logic    := '0';

   signal ecmFifoFilledInp                     : unsigned(LD_ECM_FIFO_DEPTH_INP_G downto 0) := (others => '0');
   signal ecmFifoFilledOut                     : unsigned(LD_ECM_FIFO_DEPTH_OUT_G downto 0) := (others => '0');
   signal ecmFifoFramesOut                     : unsigned(LD_ECM_FIFO_DEPTH_OUT_G downto 0) := (others => '0');

   signal ncmFifoAvailInp                      : signed(LD_NCM_RAM_DEPTH_INP_G downto 0) := (others => '1');
   signal ncmFifoEmptyOut                      : std_logic;

   signal usb2RstLoc                           : std_logic;

   signal usb2Ep0ReqParamIn                    : Usb2CtlReqParamType;
   signal usb2Ep0ReqParam                      : Usb2CtlReqParamType;

   signal usb2Ep0CtlExt                        : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;

   signal usb2Ep0CtlExtArr                     : Usb2CtlExtArray(0 to NUM_EP0_AGENTS_C - 1)     := ( others => USB2_CTL_EXT_NAK_C );
   signal usb2Ep0CtlEpExt                      : Usb2EndpPairIbType                             := USB2_ENDP_PAIR_IB_INIT_C;
   signal usb2Ep0CtlEpExtArr                   : Usb2EndpPairIbArray(0 to NUM_EP0_AGENTS_C - 1) := ( others => USB2_ENDP_PAIR_IB_INIT_C );

   signal usb2DevStatus                        : Usb2DevStatusType;

   signal macAddrPatchDone                     : std_logic := '1';

   signal gnd                                  : std_logic := '0';

   signal usb2Rx                               : Usb2RxType;

   signal DTR, RTS                             : std_logic;

   signal usb2EpIb                             : Usb2EndpPairIbArray(0 to N_EP_C - 1) := ( others => USB2_ENDP_PAIR_IB_INIT_C );

   -- note EP0 output can be observed here; an external agent extending EP0 functionality
   -- needs to listen to this.
   signal usb2EpOb                             : Usb2EndpPairObArray(0 to N_EP_C - 1) := ( others => USB2_ENDP_PAIR_OB_INIT_C );


   attribute MARK_DEBUG                        of usb2Ep0ReqParam   : signal is toStr(MARK_DEBUG_EP0_CTL_MUX_G);
   attribute MARK_DEBUG                        of usb2Ep0CtlExt     : signal is toStr(MARK_DEBUG_EP0_CTL_MUX_G);
   attribute MARK_DEBUG                        of usb2Ep0CtlEpExt   : signal is toStr(MARK_DEBUG_EP0_CTL_MUX_G);

begin

   -- Output assignments

   usb2RstLoc      <= usb2DevStatus.usb2Rst or ulpiRst or usb2Rst;
   usb2RstOut      <= usb2DevStatus.usb2Rst;

   acmDTR          <= DTR;
   acmRTS          <= RTS;

   acmFifoLoopback <= DTR;
   acmFifoBlast    <= not acmFifoLoopback;

   -- USB2 Core

   U_USB2_CORE : entity work.Usb2Core
      generic map (
         MARK_DEBUG_ULPI_IO_G         => MARK_DEBUG_ULPI_IO_G,
         MARK_DEBUG_ULPI_LINE_STATE_G => MARK_DEBUG_ULPI_LINE_STATE_G,
         MARK_DEBUG_PKT_RX_G          => MARK_DEBUG_PKT_RX_G,
         MARK_DEBUG_PKT_TX_G          => MARK_DEBUG_PKT_TX_G,
         MARK_DEBUG_PKT_PROC_G        => MARK_DEBUG_PKT_PROC_G,
         MARK_DEBUG_EP0_G             => MARK_DEBUG_EP0_G,
         ULPI_NXT_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_DIR_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_DIN_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_STP_MODE_G              => NORMAL,
         ULPI_EMU_MODE_G              => ULPI_EMU_MODE_G,
         FSLS_INPUT_MODE_VPVM_G       => FSLS_INPUT_MODE_VPVM_G,
         DESCRIPTORS_G                => DESCRIPTORS_G,
         DESCRIPTOR_BRAM_G            => DESCRIPTORS_BRAM_G
      )
      port map (
         fslsSmplClk                  => fslsSmplClk,
         fslsSmplRst                  => fslsSmplRst,
         fslsIb                       => fslsIb,
         fslsOb                       => fslsOb,

         ulpiClk                      => usb2Clk,

         ulpiRst                      => ulpiRst,
         usb2Rst                      => usb2RstLoc,

         ulpiIb                       => ulpiIb,
         ulpiOb                       => ulpiOb,
         ulpiRx                       => ulpiRx,

         ulpiRegReq                   => ulpiRegReq,
         ulpiRegRep                   => ulpiRegRep,

         ulpiForceStp                 => ulpiForceStp,

         usb2DevStatus                => usb2DevStatus,

         usb2Rx                       => usb2Rx,

         usb2Ep0ReqParam              => usb2Ep0ReqParamIn,
         usb2Ep0CtlExt                => usb2Ep0CtlExt,

         usb2HiSpeedEn                => usb2HiSpeedEn,
         usb2RemoteWake               => usb2RemoteWake,

         usb2EpIb                     => usb2EpIb,
         usb2EpOb                     => usb2EpOb,

         descRWClk                    => usb2DescRWClk,
         descRWIb                     => usb2DescRWIb,
         descRWOb                     => usb2DescRWOb
      );

   G_EP0_MUX : if ( NUM_EP0_AGENTS_C > 0 ) generate

      function cat(
         constant x : Usb2CtlEpAgentConfigArray := USB2_CTL_EP_AGENT_CONFIG_EMPTY_C;
         constant y : Usb2CtlEpAgentConfigType
      ) return Usb2CtlEpAgentConfigArray is
      begin
         return x & y;
      end function cat;

      constant EP0_AGENTS_C : Usb2CtlEpAgentConfigArray := (
         ite( HAVE_ACM_AGENT_C, usb2CtlEpMkCsIfcAgentConfig( CDC_ACM_CTL_IFC_NUM_C ) ) &
         ite( HAVE_BADD_C     , usb2CtlEpMkCsIfcAgentConfig( BADD_CTL_IFC_NUM_C    ) ) &
         ite( HAVE_ECM_C      , usb2CtlEpMkCsIfcAgentConfig( CDC_ECM_CTL_IFC_NUM_C ) ) &
         ite( HAVE_NCM_C      , usb2CtlEpMkCsIfcAgentConfig( CDC_NCM_CTL_IFC_NUM_C ) )
      );

   begin

      -- Control EP-0 mux

      U_EP0_AGENT_MUX : entity work.Usb2MuxEpCtl
         generic map (
            AGENTS_G => EP0_AGENTS_C
         )
         port map (
            usb2Clk           => usb2Clk,
            usb2Rst           => usb2RstLoc,

            usb2CtlReqParamIb => usb2Ep0ReqParamIn,
            usb2CtlExtOb      => usb2Ep0CtlExt,
            usb2CtlEpExtOb    => usb2Ep0CtlEpExt,

            usb2CtlReqParamOb => usb2Ep0ReqParam,
            usb2CtlExtIb      => usb2Ep0CtlExtArr,
            usb2CtlEpExtIb    => usb2Ep0CtlEpExtArr
         );

      usb2EpIb(0) <= usb2Ep0CtlEpExt;

   end generate G_EP0_MUX;


   -- CDC ACM Endpoint
   G_EP_CDCACM : if ( HAVE_ACM_C ) generate
      signal cnt : unsigned(7 downto 0) := (others => '0');
      signal acmEp0CtlExt        : Usb2CtlExtType;
      signal acmEp0ObExt         : Usb2EndpPairIbType;
   begin

      G_ACM_CTL_EXT : if ( HAVE_ACM_AGENT_C ) generate
         usb2Ep0CtlExtArr( CDC_ACM_EP0_AGENT_IDX_C )   <= acmEp0CtlExt;
         usb2Ep0CtlEpExtArr( CDC_ACM_EP0_AGENT_IDX_C ) <= acmEp0ObExt;
      end generate G_ACM_CTL_EXT;

      U_CDCACM : entity work.Usb2EpCDCACM
         generic map (
            CTL_IFC_NUM_G               => CDC_ACM_CTL_IFC_NUM_C,
            LD_FIFO_DEPTH_INP_G         => LD_ACM_FIFO_DEPTH_INP_G,
            LD_FIFO_DEPTH_OUT_G         => LD_ACM_FIFO_DEPTH_OUT_G,
            FIFO_TIMER_WIDTH_G          => acmFifoInpTimer'length,
            ENBL_LINE_BREAK_G           => ENBL_LINE_BREAK_C,
            ENBL_LINE_STATE_G           => ENBL_LINE_STATE_C,
            ASYNC_G                     => CDC_ACM_ASYNC_G
         )
         port map (
            usb2Clk                    => usb2Clk,
            usb2Rst                    => usb2RstLoc,

            usb2Rx                     => usb2Rx,

            usb2Ep0ReqParam            => usb2Ep0ReqParam,
            usb2Ep0CtlExt              => acmEp0CtlExt,
            usb2Ep0ObExt               => acmEp0ObExt,
            usb2Ep0IbExt               => usb2EpOb(0),

            usb2DataEpIb               => usb2EpOb(CDC_ACM_BULK_EP_IDX_C),
            usb2DataEpOb               => usb2EpIb(CDC_ACM_BULK_EP_IDX_C),
            usb2NotifyEpIb             => usb2EpOb(CDC_ACM_IRQ_EP_IDX_C),
            usb2NotifyEpOb             => usb2EpIb(CDC_ACM_IRQ_EP_IDX_C),

            fifoMinFillInp             => acmFifoInpMinFill,
            fifoTimeFillInp            => acmFifoInpTimer,

            rate                       => acmRate,
            stopBits                   => acmStopBits,
            parity                     => acmParity,
            dataBits                   => acmDataBits,

            epClk                      => acmFifoClk,
            epRstOut                   => acmFifoRstOut,

            -- FIFO Interface

            fifoDataInp                => acmFifoDatInp,
            fifoWenaInp                => acmFifoWenInp,
            fifoFullInp                => acmFifoFullInp,
            fifoFilledInp              => acmFifoFilledInp,
            fifoDataOut                => acmFifoDatOut,
            fifoRenaOut                => acmFifoRenOut,
            fifoEmptyOut               => acmFifoEmptyOut,
            fifoFilledOut              => acmFifoFilledOut,

            lineBreak                  => acmLineBreak,
            DTR                        => DTR,
            RTS                        => RTS,
            rxCarrier                  => acmDCD,
            txCarrier                  => acmDSR,
            overRun                    => acmOverRun,
            parityError                => acmParityError,
            framingError               => acmFramingError,
            ringDetected               => acmRingDetect,
            breakState                 => acmBreakState
          );

      P_CNT : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( (acmFifoBlast and acmFifoWenInp) = '1' ) then
               cnt <= cnt + 1;
            end if;
         end if;
      end process P_CNT;


      P_COMB : process (
         acmFifoInpDat,
         acmFifoDatOut,
         acmFifoBlast,
         acmFifoLoopback,
         acmFifoLocal,
         cnt,
         acmFifoFullInp,
         acmFifoEmptyOut,
         acmFifoInpWen,
         acmFifoOutRen
      ) is
         variable wen : std_logic;
         variable ren : std_logic;
      begin
         acmFifoOutEmpty <= '1';
         acmFifoInpFull  <= '1';
         wen             := not acmFifoFullInp;
         ren             := not acmFifoEmptyOut;
         if ( acmFifoLocal = '1' ) then
            acmFifoDatInp    <= acmFifoInpDat;
            acmFifoOutEmpty  <= acmFifoEmptyOut;
            acmFifoInpFull   <= acmFifoFullInp;
            wen              := wen and acmFifoInpWen;
            ren              := ren and acmFifoOutRen;
         elsif ( acmFifoLoopback = '1' ) then
            acmFifoDatInp    <= acmFifoDatOut;
            wen              := wen and not acmFifoEmptyOut;
            ren              := ren and not acmFifoFullInp;
         else -- if ( acmFifoBlast = '1' ) then
            acmFifoDatInp    <= std_logic_vector( cnt );
            wen              := wen and '1';
            ren              := ren and '1';
         end if;
         acmFifoWenInp <= wen;
         acmFifoRenOut <= ren;
      end process P_COMB;

      acmFifoOutDat   <= acmFifoDatOut;
      acmFifoOutFill  <= resize( acmFifoFilledOut, acmFifoOutFill'length );
      acmFifoInpFill  <= resize( acmFifoFilledInp, acmFifoInpFill'length );
   end generate G_EP_CDCACM;

   G_EP_ISO_BADD : if ( HAVE_BADD_C ) generate
   begin
      U_BADD : entity work.Usb2EpBADDSpkr
         generic map (
            AC_IFC_NUM_G              => toUsb2InterfaceNumType(BADD_CTL_IFC_NUM_C),
            SAMPLE_SIZE_G             => 3,
            MARK_DEBUG_G              => MARK_DEBUG_SND_G,
            MARK_DEBUG_BCLK_G         => false
         )
         port map (
            usb2Clk                   => usb2Clk,
            usb2Rst                   => usb2RstLoc,
            usb2RstBsy                => open,

            usb2Ep0ReqParam           => usb2Ep0ReqParam,
            usb2Ep0CtlExt             => usb2Ep0CtlExtArr( BADD_EP0_AGENT_IDX_C ),
            usb2Ep0ObExt              => usb2Ep0CtlEpExtArr( BADD_EP0_AGENT_IDX_C ),
            usb2Ep0IbExt              => usb2EpOb(0),

            usb2Rx                    => usb2Rx,
            usb2EpIb                  => usb2EpOb(BADD_ISO_EP_IDX_C),
            usb2EpOb                  => usb2EpIb(BADD_ISO_EP_IDX_C),
            usb2DevStatus             => usb2DevStatus,

            volMaster                 => baddVolMaster,
            muteMaster                => baddMuteMaster,
            volLeft                   => baddVolLeft,
            volRight                  => baddVolRight,
            muteLeft                  => baddMuteLeft,
            muteRight                 => baddMuteRight,
            powerState                => baddPowerState,

            i2sBCLK                   => i2sBCLK,
            i2sPBLRC                  => i2sPBLRC,
            i2sPBDAT                  => i2sPBDAT
         );
   end generate G_EP_ISO_BADD;

   G_EP_CDCECM : if ( HAVE_ECM_C ) generate
   begin

      U_CDCECM : entity work.Usb2EpCDCECM
         generic map (
            CTL_IFC_NUM_G              => CDC_ECM_CTL_IFC_NUM_C,
            LD_FIFO_DEPTH_INP_G        => LD_ECM_FIFO_DEPTH_INP_G,
            LD_FIFO_DEPTH_OUT_G        => LD_ECM_FIFO_DEPTH_OUT_G,
            FIFO_TIMER_WIDTH_G         => ecmFifoInpTimer'length,
            CARRIER_DFLT_G             => '0',
            ASYNC_G                     => CDC_ECM_ASYNC_G
         )
         port map (
            usb2Clk                    => usb2Clk,
            usb2Rst                    => usb2RstLoc,

            usb2Ep0ReqParam            => usb2Ep0ReqParam,
            usb2Ep0CtlExt              => usb2Ep0CtlExtArr( CDC_ECM_EP0_AGENT_IDX_C ),

            usb2DataEpIb               => usb2EpOb(CDC_ECM_BULK_EP_IDX_C),
            usb2DataEpOb               => usb2EpIb(CDC_ECM_BULK_EP_IDX_C),
            usb2NotifyEpIb             => usb2EpOb(CDC_ECM_IRQ_EP_IDX_C),
            usb2NotifyEpOb             => usb2EpIb(CDC_ECM_IRQ_EP_IDX_C),

            fifoMinFillInp             => ecmFifoInpMinFill,
            fifoTimeFillInp            => ecmFifoInpTimer,

            packetFilter               => ecmPacketFilter,

            epClk                      => ecmFifoClk,
            epRstOut                   => ecmFifoRstOut,

            -- FIFO Interface
            fifoDataInp                => ecmFifoInpDat,
            fifoLastInp                => ecmFifoInpLast,
            fifoWenaInp                => ecmFifoInpWen,
            fifoFullInp                => ecmFifoInpFull,
            fifoFilledInp              => ecmFifoFilledInp,
            fifoDataOut                => ecmFifoOutDat,
            fifoLastOut                => ecmFifoOutLast,
            fifoRenaOut                => ecmFifoOutRen,
            fifoEmptyOut               => ecmFifoOutEmpty,
            fifoFilledOut              => ecmFifoFilledOut,
            fifoFramesOut              => ecmFifoFramesOut,

            carrier                    => ecmCarrier
         );

      ecmFifoOutFill <= resize(ecmFifoFilledOut, ecmFifoOutFill'length);
      ecmFifoOutFrms <= resize(ecmFifoFramesOut, ecmFifoOutFrms'length);
      ecmFifoInpFill <= resize(ecmFifoFilledInp, ecmFifoInpFill'length);

      usb2Ep0CtlEpExtArr( CDC_ECM_EP0_AGENT_IDX_C ) <= USB2_ENDP_PAIR_IB_INIT_C;

   end generate G_EP_CDCECM;

   G_EP_CDCNCM : if ( HAVE_NCM_C ) generate
   begin

      U_CDCNCM : entity work.Usb2EpCDCNCM
         generic map (
            CTL_IFC_NUM_G              => CDC_NCM_CTL_IFC_NUM_C,
            ASYNC_G                    => CDC_NCM_ASYNC_G,
            LD_RAM_DEPTH_INP_G         => LD_NCM_RAM_DEPTH_INP_G,
            LD_RAM_DEPTH_OUT_G         => LD_NCM_RAM_DEPTH_OUT_G,
            CARRIER_DFLT_G             => '0'
         )
         port map (
            usb2Clk                    => usb2Clk,
            usb2Rst                    => usb2RstLoc,
            usb2EpRstOut               => open,

            usb2Ep0ReqParam            => usb2Ep0ReqParam,
            usb2Ep0CtlExt              => usb2Ep0CtlExtArr( CDC_NCM_EP0_AGENT_IDX_C ),

            usb2CtlEpIb                => usb2EpOb(0),
            usb2CtlEpOb                => usb2Ep0CtlEpExtArr( CDC_NCM_EP0_AGENT_IDX_C ),

            usb2DataEpIb               => usb2EpOb(CDC_NCM_BULK_EP_IDX_C),
            usb2DataEpOb               => usb2EpIb(CDC_NCM_BULK_EP_IDX_C),

            usb2NotifyEpIb             => usb2EpOb(CDC_NCM_IRQ_EP_IDX_C),
            usb2NotifyEpOb             => usb2EpIb(CDC_NCM_IRQ_EP_IDX_C),

            packetFilter               => open,
            speedInp                   => open,
            speedOut                   => open,
            macAddress                 => open,

            epClk                      => ncmFifoClk,
            epRstOut                   => ncmFifoRstOut,

            -- FIFO Interface
            fifoDataInp                => ncmFifoInpDat,
            fifoLastInp                => ncmFifoInpLast,
            fifoWenaInp                => ncmFifoInpWen,
            fifoFullInp                => ncmFifoInpFull,
            fifoBusyInp                => ncmFifoInpBusy,
            fifoAvailInp               => ncmFifoAvailInp,

            fifoDataOut                => ncmFifoOutDat,
            fifoLastOut                => ncmFifoOutLast,
            fifoRenaOut                => ncmFifoOutRen,
            fifoEmptyOut               => ncmFifoEmptyOut,

            carrier                    => ncmCarrier
         );

      ncmFifoInpAvail <= resize(ncmFifoAvailInp, ncmFifoInpAvail'length);
      ncmFifoOutEmpty <= ncmFifoEmptyOut;

   end generate G_EP_CDCNCM;

end architecture Impl;
