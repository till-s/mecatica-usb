-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Instantiation of a CDC ACM Endpoint with a FIFO interface as well
-- as the necessary IO-Buffers

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library unisim;
use     unisim.vcomponents.all;

use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;
use     work.Usb2AppCfgPkg.all;
use     work.StdLogPkg.all;

entity Usb2ExampleDev is
   generic (
      SYS_CLK_PERIOD_NS_G  : real     := 20.0;
      ULPI_CLK_MODE_INP_G  : boolean  := true;

      -- ULPI INPUT CLOCK MODE PARAMETERS

      -- in ULPI INPUT clock mode the ULPI clock is generated from
      -- sysClk with an MMCM - depending on the system clock rate
      -- the CLK_MULT_F_G/CLK0_DIV_G/REF_CLK_DIV_G must be set to
      -- generate the 60MHz ULPI clock at CLKOUT0 of the MMCM
      REF_CLK_DIV_G        : positive := 1;
      CLK_MULT_F_G         : real     := 24.0;
      CLK0_DIV_G           : positive := 20;
      -- CLKOUT2 is not currently used by could be employed to
      -- generate 200MHz for an IDELAY control module
      CLK2_DIV_G           : positive := 6;
      -- CLKOUT1 is used to generate a phase-shifted clock that
      -- toggles the DDR which produces the ULPI clock. This phase
      -- shift helps with timing and *must* be at least slightly negative
      -- or the multicycle exception constraint must be removed!
      -- (use a negative phase-shift to compensate
      -- the significant delays in the clock path and the output delay of the ULPI
      -- transceiver).
      CLK1_INP_PHASE_G     : real     := -29.25;

      -- ULPI OUTPUT CLOCK MODE PARAMETERS

      -- in ULPI output clock mode the internal ULPI clock is phase-shifted
      -- by an MMCM to help timing
      -- phase must be a multiple of 45/CLK0_DIV = 3.0 (in output mode CLK0_DIV_G
      -- is not used!)
      -- Note that a small positive phase *must* be used -- otherwise the
      -- multicycle exception in the constraints must be removed!
      -- (delay the internal clock to compensate for the output delay of the
      -- ULPI transceiver)
      CLK0_OUT_PHASE_G     : real     := 15.0;

      MARK_DEBUG_G         : boolean  := true
   );
   port (
      refClkNb             : in    std_logic;

      -- connect to the device pin
      ulpiClk              : inout std_logic;
      -- reset the ulpi low-level interface; should not be necessary
      ulpiRst              : in    std_logic := '0';
      ulpiStp              : inout std_logic;
      ulpiDir              : in    std_logic;
      ulpiNxt              : in    std_logic;
      ulpiDat              : inout std_logic_vector(7 downto 0);

      ulpiClkOut           : out   std_logic;

      usb2Rst              : out   std_logic;

      refLocked            : out   std_logic;

      -- control vector
      -- CDC-ACM
      -- iRegs(0,0)(10 downto 0)  : min. fill level of the IN fifo until data are sent to USB
      -- iRegs(0,0)(25)           : DSR
      -- iRegs(0,0)(26)           : DCD
      -- iRegs(0,0)(27)           : enable 'blast' mode; OUT fifo is constantly drained; IN fifo
      --                         is blast with an incrementing 8-bit counter.
      -- iRegs(0,0)(28)           : disable 'loopback' mode; OUT fifo is fed into IN fifo; loopback
      --                         is *enabled* by default. Note        : 'blast' overrides 'loopback'.
      -- iRegs(0,0)(29)           : assert forced ULPI STP (useful to bring the PHY to reason if it holds DIR)
      -- iRegs(0,0)(30)           : mask/disable IN/OUT fifo's write/read enable when set.
      -- iRegs(0,0)(31)           : USB remote wakeup

      -- iRegs(0,1)               : IN fifo fill timer (in ulpi CLK cycles)
      --                            fill-level and fill-timer work like termios VMIN/VTIME
      -- CDC-ECM
      -- iRegs(1,0)(10 downto 0)  : min. fill level of the IN fifo until data are sent to USB
      -- iRegs(1,0)(31)           : carrier indicator
      -- iRegs(1,1)               : IN fifo fill timer (in ulpi CLK cycles)
      iRegs                : in    RegArray(0 to 1, 0 to 1);
      -- status vector
      -- CDC-ACM
      -- oRegs(0,0)               : fifo sizes, IN  fifo fill level
      -- oRegs(0,1)               : RTS, DTR, lineBreak, OUT fifo fill level
      -- CDC-ECM
      -- oRegs(1,0)               : fifo sizes, packetFilter, IN fifo fill level
      -- oRegs(1,1)               : OUT fifo frames & fill level
      oRegs                : out   RegArray(0 to 1, 0 to 1);

      regReq               : in    UlpiRegReqType;
      regRep               : out   UlpiRegRepType;

      acmFifoOutDat        : out   Usb2ByteType;
      acmFifoOutEmpty      : out   std_logic;
      acmFifoOutFill       : out   unsigned(15 downto 0);
      acmFifoOutRen        : in    std_logic := '1';

      acmFifoInpDat        : in    Usb2ByteType := (others => '0');
      ecmFifoInpDon        : in    std_logic;
      acmFifoInpFull       : out   std_logic;
      acmFifoInpFill       : out   unsigned(15 downto 0);
      acmFifoInpWen        : in    std_logic := '1';

      acmLineBreak         : out   std_logic := '0';
      acmDTR               : out   std_logic := '0';
      acmRTS               : out   std_logic := '0';

      baddVolMaster        : out signed(15 downto 0)  := (others => '0');
      baddVolLeft          : out signed(15 downto 0)  := (others => '0');
      baddVolRight         : out signed(15 downto 0)  := (others => '0');
      baddMuteMaster       : out std_logic            := '0';
      baddMuteLeft         : out std_logic            := '0';
      baddMuteRight        : out std_logic            := '0';
      baddPowerState       : out unsigned(1 downto 0) := (others => '0');

      ecmFifoOutDat        : out   Usb2ByteType;
      ecmFifoOutDon        : out   std_logic;
      ecmFifoOutEmpty      : out   std_logic;
      ecmFifoOutFill       : out   unsigned(15 downto 0);
      ecmFifoOutFrms       : out   unsigned(15 downto 0);
      ecmFifoOutRen        : in    std_logic := '1';

      ecmFifoInpDat        : in    Usb2ByteType := (others => '0');
      ecmFifoInpFull       : out   std_logic;
      ecmFifoInpFill       : out   unsigned(15 downto 0);
      ecmFifoInpWen        : in    std_logic := '1';

      clk2Nb               : out   std_logic := '0';

      i2sBCLK              : in    std_logic;
      i2sPBLRC             : in    std_logic;
      i2sPBDAT             : out   std_logic
   );
end entity Usb2ExampleDev;

architecture Impl of Usb2ExampleDev is
   attribute MARK_DEBUG                        : string;

   constant USE_MMCM_C                         : boolean := true;

   constant N_EP_C                             : natural := USB2_APP_MAX_ENDPOINTS_F(USB2_APP_DESCRIPTORS_C);

   constant CDC_ACM_BULK_EP_IDX_C              : natural := 1;
   constant CDC_ACM_IRQ_EP_IDX_C               : natural := 2;
   constant BADD_ISO_EP_IDX_C                  : natural := 3;
   constant CDC_ECM_BULK_EP_IDX_C              : natural := 4;
   constant CDC_ECM_IRQ_EP_IDX_C               : natural := 5;

   constant CDC_ACM_IFC_NUM_C                  : natural := 0; -- uses 2 interfaces
   constant BADD_IFC_NUM_C                     : natural := 2; -- uses 2 interfaces
   constant CDC_ECM_IFC_NUM_C                  : natural := 4;

   constant LD_ACM_FIFO_DEPTH_INP_C            : natural := 10;
   constant LD_ACM_FIFO_DEPTH_OUT_C            : natural := 10;
   -- min. 2 ethernet frames -> 4kB
   constant LD_ECM_FIFO_DEPTH_INP_C            : natural := 12;
   constant LD_ECM_FIFO_DEPTH_OUT_C            : natural := 12;

   signal acmFifoTimer                         : unsigned(31 downto 0) := (others => '0');
   signal acmFifoMinFill                       : unsigned(LD_ACM_FIFO_DEPTH_INP_C - 1 downto 0) := (others => '0');
   signal acmFifoDatInp                        : Usb2ByteType := (others => '0');
   signal acmFifoWenInp                        : std_logic    := '0';
   signal acmFifoFullInp                       : std_logic    := '0';
   signal acmFifoFilledInp                     : unsigned(LD_ACM_FIFO_DEPTH_INP_C downto 0) := (others => '0');
   signal acmFifoDatOut                        : Usb2ByteType := (others => '0');
   signal acmFifoRenOut                        : std_logic    := '0';
   signal acmFifoEmptyOut                      : std_logic    := '0';
   signal acmFifoFilledOut                     : unsigned(LD_ACM_FIFO_DEPTH_OUT_C downto 0) := (others => '0');
   signal acmFifoDisable                       : std_logic    := '0';
   signal acmFifoBlast                         : std_logic    := '0';
   signal acmFifoLoopback                      : std_logic    := '0';

   signal ecmFifoFilledInp                     : unsigned(LD_ECM_FIFO_DEPTH_INP_C downto 0) := (others => '0');
   signal ecmFifoFilledOut                     : unsigned(LD_ECM_FIFO_DEPTH_OUT_C downto 0) := (others => '0');
   signal ecmFifoFramesOut                     : unsigned(LD_ECM_FIFO_DEPTH_OUT_C downto 0) := (others => '0');

   signal ecmFifoTimer                         : unsigned(31 downto 0) := (others => '0');
   signal ecmFifoMinFill                       : unsigned(LD_ECM_FIFO_DEPTH_INP_C - 1 downto 0) := (others => '0');
   signal ecmPacketFilter                      : std_logic_vector(4 downto 0);

   signal ulpiClkLoc                           : std_logic;
   signal ulpiClkLocNb                         : std_logic;
   signal ulpiForceStp                         : std_logic;

   signal usb2RstLoc                           : std_logic;

   signal ulpiIb                               : UlpiIbType;
   signal ulpiOb                               : UlpiObType;

   type   MuxSelType                           is ( NONE, CDCACM, BADD, CDCECM );

   signal usb2Ep0ReqParamIn                    : Usb2CtlReqParamType;
   signal usb2Ep0ReqParam                      : Usb2CtlReqParamType;
   signal usb2Ep0CDCACMCtlExt                  : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
   signal usb2Ep0CDCECMCtlExt                  : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
   signal usb2Ep0BADDCtlExt                    : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
   signal usb2Ep0CtlExt                        : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
   signal usb2Ep0BADDCtlEpExt                  : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal usb2Ep0CDCACMCtlEpExt                : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal usb2Ep0CtlEpExt                      : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal usb2DevStatus                        : Usb2DevStatusType;

   signal usb2RemoteWake                       : std_logic;

   signal muxSel                               : MuxSelType         := NONE;
   signal muxSelIn                             : MuxSelType         := NONE;

   signal gnd                                  : std_logic := '0';

   signal usb2Rx                               : Usb2RxType;

   signal DTR, RTS, lineBreak, DCD, DSR        : std_logic;

   signal usb2EpIb                             : Usb2EndpPairIbArray(1 to N_EP_C - 1) := ( others => USB2_ENDP_PAIR_IB_INIT_C );

   -- note EP0 output can be observed here; an external agent extending EP0 functionality
   -- needs to listen to this.
   signal usb2EpOb                             : Usb2EndpPairObArray(0 to N_EP_C - 1) := ( others => USB2_ENDP_PAIR_OB_INIT_C );


   attribute MARK_DEBUG                        of usb2Ep0ReqParam   : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG                        of usb2Ep0CtlExt     : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG                        of usb2Ep0CtlEpExt   : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG                        of muxSel            : signal is toStr(MARK_DEBUG_G);

begin

   -- Output assignments

   ulpiClkOut <= ulpiClkLoc;
   usb2RstLoc <= usb2DevStatus.usb2Rst or ulpiRst;
   usb2Rst    <= usb2RstLoc;

   -- Register assignments
   P_RG : process (
      acmFifoFilledInp,
      acmFifoFilledOut,
      ecmFifoFilledInp,
      ecmFifoFilledOut,
      ecmFifoFramesOut,
      ecmPacketFilter,
      DTR, RTS, lineBreak
   ) is
   begin
      oRegs <= ((others => (others => '0')), (others => (others => '0')));

      oRegs(0,0)(31 downto 28)           <= std_logic_vector(to_unsigned(LD_ACM_FIFO_DEPTH_INP_C, 4));
      oRegs(0,0)(27 downto 24)           <= std_logic_vector(to_unsigned(LD_ACM_FIFO_DEPTH_OUT_C, 4));
      oRegs(0,0)(23 downto 16)           <= (others => '0');
      oRegs(0,0)(15 downto  0)           <= std_logic_vector(resize(acmFifoFilledInp, 16));

      oRegs(0,1)(15 downto  0)           <= std_logic_vector(resize(acmFifoFilledOut, 16));
      oRegs(0,1)(16)                     <= DTR;
      oRegs(0,1)(17)                     <= RTS;
      oRegs(0,1)(18)                     <= lineBreak;

      oRegs(1,0)(31 downto 28)           <= std_logic_vector(to_unsigned(LD_ECM_FIFO_DEPTH_INP_C, 4));
      oRegs(1,0)(27 downto 24)           <= std_logic_vector(to_unsigned(LD_ECM_FIFO_DEPTH_OUT_C, 4));
      oRegs(1,0)(23 downto 21)           <= (others => '0');
      oRegs(1,0)(20 downto 16)           <= ecmPacketFilter;
      oRegs(1,0)(15 downto  0)           <= std_logic_vector(resize(ecmFifoFilledInp, 16));

      oRegs(1,1)(31 downto 16)           <= std_logic_vector(resize(ecmFifoFramesOut, 16));
      oRegs(1,1)(15 downto  0)           <= std_logic_vector(resize(ecmFifoFilledOut, 16));
   end process P_RG;


   acmDTR          <= DTR;
   acmRTS          <= RTS;
   acmLineBreak    <= lineBreak;
   acmFifoMinFill  <= unsigned(iRegs(0,0)(acmFifoMinFill'range));
   acmFifoTimer    <= unsigned(iRegs(0,1)(acmFifoTimer'range));
   ulpiForceStp    <= iRegs(0,0)(29);
   usb2RemoteWake  <= iRegs(0,0)(31);
   acmFifoDisable  <= iRegs(0,0)(30);
   acmFifoBlast    <= iRegs(0,0)(27);
   DCD             <= iRegs(0,0)(26);
   DSR             <= iRegs(0,0)(25);
   acmFifoLoopback <= not iRegs(0,0)(28);

   -- USB2 Core

   U_USB2_CORE : entity work.Usb2Core
      generic map (
         MARK_DEBUG_ULPI_IO_G         => true,
         MARK_DEBUG_ULPI_LINE_STATE_G => false,
         MARK_DEBUG_PKT_RX_G          => true,
         MARK_DEBUG_PKT_TX_G          => false,
         MARK_DEBUG_PKT_PROC_G        => true,
         MARK_DEBUG_EP0_G             => true,
         ULPI_NXT_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_DIR_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_DIN_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_STP_MODE_G              => NORMAL,
         DESCRIPTORS_G                => USB2_APP_DESCRIPTORS_C
      )
      port map (
         clk                          => ulpiClkLoc,

         ulpiRst                      => ulpiRst,
         usb2Rst                      => usb2RstLoc,

         ulpiIb                       => ulpiIb,
         ulpiOb                       => ulpiOb,

         ulpiRegReq                   => regReq,
         ulpiRegRep                   => regRep,

         ulpiForceStp                 => ulpiForceStp,

         usb2DevStatus                => usb2DevStatus,

         usb2Rx                       => usb2Rx,

         usb2Ep0ReqParam              => usb2Ep0ReqParamIn,
         usb2Ep0CtlExt                => usb2Ep0CtlExt,
         usb2Ep0CtlEpIbExt            => usb2Ep0CtlEpExt,

         usb2HiSpeedEn                => '1',
         usb2RemoteWake               => usb2RemoteWake,

         usb2EpIb                     => usb2EpIb,
         usb2EpOb                     => usb2EpOb
      );

   -- Control EP-0 mux

   B_EP0_MUX : block is
   begin

      P_MUX : process (
         muxSel,
         usb2Ep0ReqParamIn,
         usb2Ep0CDCACMCtlExt,
         usb2Ep0CDCECMCtlExt,
         usb2Ep0BADDCtlExt,
         usb2Ep0BADDCtlEpExt,
         usb2Ep0CDCACMCtlEpExt
      ) is
         variable v : MuxSelType;
      begin

         v := muxSel;

         usb2Ep0CtlExt   <= USB2_CTL_EXT_NAK_C;
         usb2Ep0CtlEpExt <= USB2_ENDP_PAIR_IB_INIT_C;

         usb2Ep0ReqParam <= usb2Ep0ReqParamIn;

         -- reset state
         if ( usb2Ep0ReqParamIn.vld = '0' ) then
            v := NONE;
         end if;

         if ( muxSel = NONE ) then
            -- don't propagate 'vld' to the EPs until a choice is made
            usb2Ep0ReqParam.vld <= '0';

            if ( usb2Ep0ReqParamIn.vld = '1' ) then
               -- new mux setting
               if ( usb2Ep0ReqParamIn.reqType = USB2_REQ_TYP_TYPE_CLASS_C ) then
                  if    ( usb2CtlReqDstInterface( usb2Ep0ReqParamIn, toUsb2InterfaceNumType( CDC_ACM_IFC_NUM_C ) ) ) then
                     v := CDCACM;
                  elsif ( usb2CtlReqDstInterface( usb2Ep0ReqParamIn, toUsb2InterfaceNumType( BADD_IFC_NUM_C ) ) ) then
                     v := BADD;
                  elsif ( usb2CtlReqDstInterface( usb2Ep0ReqParamIn, toUsb2InterfaceNumType( CDC_ECM_IFC_NUM_C ) ) ) then
                     v := CDCECM;
                  end if;
               end if;
               -- blank the 'ack/don' flags during this cycle
               if ( v /= NONE ) then
                  usb2Ep0CtlExt <= USB2_CTL_EXT_INIT_C;
               end if;
            end if;
         end if;

         if    ( muxSel = CDCACM  ) then
            usb2Ep0CtlExt   <= usb2Ep0CDCACMCtlExt;
            usb2Ep0CtlEpExt <= usb2Ep0CDCACMCtlEpExt;
         elsif ( muxSel = CDCECM  ) then
            usb2Ep0CtlExt   <= usb2Ep0CDCECMCtlExt;
         elsif ( muxSel = BADD ) then
            usb2Ep0CtlExt   <= usb2Ep0BADDCtlExt;
            usb2Ep0CtlEpExt <= usb2Ep0BADDCtlEpExt;
         end if;

         muxSelIn <= v;
      end process P_MUX;

      P_SEL : process( ulpiClkLoc ) is
      begin
         if ( rising_edge( ulpiClkLoc ) ) then
            if ( usb2RstLoc = '1' ) then
               muxSel <= NONE;
            else
               muxSel <= muxSelIn;
            end if;
         end if;
      end process P_SEL;

   end block B_EP0_MUX;

   -- CDC ACM Endpoint
   B_EP_CDCACM : block is
      signal cnt : unsigned(7 downto 0) := (others => '0');
   begin

      U_CDCACM : entity work.Usb2EpCDCACM
         generic map (
            CTL_IFC_NUM_G               => CDC_ACM_IFC_NUM_C,
            LD_FIFO_DEPTH_INP_G         => LD_ACM_FIFO_DEPTH_INP_C,
            LD_FIFO_DEPTH_OUT_G         => LD_ACM_FIFO_DEPTH_OUT_C,
            FIFO_TIMER_WIDTH_G          => acmFifoTimer'length,
            ENBL_LINE_BREAK_G           => true,
            ENBL_LINE_STATE_G           => true
         )
         port map (
            usb2Clk                    => ulpiClkLoc,
            usb2Rst                    => usb2RstLoc,

            usb2Rx                     => usb2Rx,

            usb2Ep0ReqParam            => usb2Ep0ReqParam,
            usb2Ep0CtlExt              => usb2Ep0CDCACMCtlExt,
            usb2Ep0ObExt               => usb2Ep0CDCACMCtlEpExt,
            usb2Ep0IbExt               => usb2EpOb(0),

            usb2DataEpIb               => usb2EpOb(CDC_ACM_BULK_EP_IDX_C),
            usb2DataEpOb               => usb2EpIb(CDC_ACM_BULK_EP_IDX_C),
            usb2NotifyEpIb             => usb2EpOb(CDC_ACM_IRQ_EP_IDX_C),
            usb2NotifyEpOb             => usb2EpIb(CDC_ACM_IRQ_EP_IDX_C),

            fifoMinFillInp             => acmFifoMinFill,
            fifoTimeFillInp            => acmFifoTimer,

            epClk                      => ulpiClkLoc,
            epRstOut                   => open,

            -- FIFO Interface

            fifoDataInp                => acmFifoDatInp,
            fifoWenaInp                => acmFifoWenInp,
            fifoFullInp                => acmFifoFullInp,
            fifoFilledInp              => acmFifoFilledInp,
            fifoDataOut                => acmFifoDatOut,
            fifoRenaOut                => acmFifoRenOut,
            fifoEmptyOut               => acmFifoEmptyOut,
            fifoFilledOut              => acmFifoFilledOut,

            lineBreak                  => lineBreak,
            DTR                        => DTR,
            RTS                        => RTS,
            rxCarrier                  => DCD,
            txCarrier                  => DSR
         );

      P_CNT : process ( ulpiClkLoc ) is
      begin
         if ( rising_edge( ulpiClkLoc ) ) then

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
         cnt,
         acmFifoDisable,
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
         wen             := not acmFifoFullInp  and not acmFifoDisable;
         ren             := not acmFifoEmptyOut and not acmFifoDisable;
         if    ( acmFifoBlast = '1' ) then
            acmFifoDatInp    <= std_logic_vector( cnt );
            wen              := wen and '1';
            ren              := ren and '1';
         elsif ( acmFifoLoopback = '1' ) then
            acmFifoDatInp    <= acmFifoDatOut;
            wen              := wen and not acmFifoEmptyOut;
            ren              := ren and not acmFifoFullInp;
         else
            acmFifoDatInp    <= acmFifoInpDat;
            acmFifoOutEmpty  <= acmFifoEmptyOut;
            acmFifoInpFull   <= acmFifoFullInp;
            wen              := wen and acmFifoInpWen;
            ren              := ren and acmFifoOutRen;
         end if;
         acmFifoWenInp <= wen;
         acmFifoRenOut <= ren;
      end process P_COMB;

      acmFifoOutDat   <= acmFifoDatOut;
      acmFifoOutFill  <= resize( acmFifoFilledOut, acmFifoOutFill'length );

      acmFifoInpFill  <= resize( acmFifoFilledInp, acmFifoInpFill'length );
   end block B_EP_CDCACM;

   B_EP_ISO_BADD : block is
   begin
      U_BADD : entity work.Usb2EpBADD
         generic map (
            AC_IFC_NUM_G              => toUsb2InterfaceNumType(BADD_IFC_NUM_C),
            SAMPLE_SIZE_G             => 2,
            MARK_DEBUG_G              => false,
            MARK_DEBUG_BCLK_G         => false
         )
         port map (
            usb2Clk                   => ulpiClkLoc,
            usb2Rst                   => usb2RstLoc,
            usb2RstBsy                => open,

            usb2Ep0ReqParam           => usb2Ep0ReqParam,
            usb2Ep0CtlExt             => usb2Ep0BADDCtlExt,
            usb2Ep0ObExt              => usb2Ep0BADDCtlEpExt,
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
   end block B_EP_ISO_BADD;

   B_EP_CDCECM : block is

      signal ecmCarrier               : std_logic;

   begin

      ecmFifoMinFill  <= unsigned(iRegs(1,0)(ecmFifoMinFill'range));
      ecmCarrier      <= iRegs(1,0)(31);
      ecmFifoTimer    <= unsigned(iRegs(1,1)(ecmFifoTimer'range));

      U_CDCECM : entity work.Usb2EpCDCECM
         generic map (
            CTL_IFC_NUM_G              => CDC_ECM_IFC_NUM_C,
            LD_FIFO_DEPTH_INP_G        => LD_ECM_FIFO_DEPTH_INP_C,
            LD_FIFO_DEPTH_OUT_G        => LD_ECM_FIFO_DEPTH_OUT_C,
            FIFO_TIMER_WIDTH_G         => ecmFifoTimer'length,
            CARRIER_DFLT_G             => '0'
         )
         port map (
            usb2Clk                    => ulpiClkLoc,
            usb2Rst                    => usb2RstLoc,

            usb2Ep0ReqParam            => usb2Ep0ReqParam,
            usb2Ep0CtlExt              => usb2Ep0CDCECMCtlExt,

            usb2DataEpIb               => usb2EpOb(CDC_ECM_BULK_EP_IDX_C),
            usb2DataEpOb               => usb2EpIb(CDC_ECM_BULK_EP_IDX_C),
            usb2NotifyEpIb             => usb2EpOb(CDC_ECM_IRQ_EP_IDX_C),
            usb2NotifyEpOb             => usb2EpIb(CDC_ECM_IRQ_EP_IDX_C),

            fifoMinFillInp             => ecmFifoMinFill,
            fifoTimeFillInp            => ecmFifoTimer,

            packetFilter               => ecmPacketFilter,

            epClk                      => ulpiClkLoc,
            epRstOut                   => open,

            -- FIFO Interface
            fifoDataInp                => ecmFifoInpDat,
            fifoDonInp                 => ecmFifoInpDon,
            fifoWenaInp                => ecmFifoInpWen,
            fifoFullInp                => ecmFifoInpFull,
            fifoFilledInp              => ecmFifoFilledInp,
            fifoDataOut                => ecmFifoOutDat,
            fifoDonOut                 => ecmFifoOutDon,
            fifoRenaOut                => ecmFifoOutRen,
            fifoEmptyOut               => ecmFifoOutEmpty,
            fifoFilledOut              => ecmFifoFilledOut,
            fifoFramesOut              => ecmFifoFramesOut,

            carrier                    => ecmCarrier
         );

      ecmFifoOutFill <= resize(ecmFifoFilledOut, ecmFifoOutFill'length);
      ecmFifoOutFrms <= resize(ecmFifoFramesOut, ecmFifoOutFrms'length);
      ecmFifoInpFill <= resize(ecmFifoFilledInp, ecmFifoInpFill'length);

   end block B_EP_CDCECM;

   -- Clock generation

   G_MMCM : if ( ULPI_CLK_MODE_INP_G or USE_MMCM_C ) generate

      signal clkFbI, clkFbO    : std_logic;
      signal refClkLoc         : std_logic;

      constant CLK_MULT_F_C    : real    := ite( ULPI_CLK_MODE_INP_G, CLK_MULT_F_G,        15.000 );
      constant REF_PERIOD_C    : real    := ite( ULPI_CLK_MODE_INP_G, SYS_CLK_PERIOD_NS_G, 16.667 );
      constant CLK0_DIV_C      : natural := ite( ULPI_CLK_MODE_INP_G, CLK0_DIV_G,          15     );
      constant CLK2_DIV_C      : natural := ite( ULPI_CLK_MODE_INP_G, CLK2_DIV_G,          15     );
      constant REF_CLK_DIV_C   : natural := ite( ULPI_CLK_MODE_INP_G, REF_CLK_DIV_G,        1     );
      -- phase must be a multiple of 45/CLK0_DIV_G
      constant CLKOUT0_PHASE_C : real    := ite( ULPI_CLK_MODE_INP_G, 0.00,                CLK0_OUT_PHASE_G);
      constant CLKOUT1_PHASE_C : real    := ite( ULPI_CLK_MODE_INP_G, CLK1_INP_PHASE_G,    0.0    );

      signal ulpiClkRegLoc     : std_logic := '0';
      signal ulpiClkRegNb      : std_logic;
      signal ulpiClk_i         : std_logic;
      signal ulpiClk_o         : std_logic := '0';
      signal ulpiClk_t         : std_logic := '1';

   begin

      U_ULPI_CLK_IOBUF : IOBUF
         port map (
            IO   => ulpiClk,
            O    => ulpiClk_i,
            I    => ulpiClk_o,
            T    => ulpiClk_t
         );

      G_REFCLK_ULPI : if ( not ULPI_CLK_MODE_INP_G ) generate
         refClkLoc <= ulpiClk_i;
         ulpiClk_t <= '1';
      end generate G_REFCLK_ULPI;

      G_REF_SYS : if ( ULPI_CLK_MODE_INP_G ) generate
         refClkLoc <= refClkNb;
         ulpiClk_t <= '0';
      end generate G_REF_SYS;

      U_MMCM : MMCME2_BASE
         generic map (
            BANDWIDTH => "OPTIMIZED",  -- Jitter programming (OPTIMIZED, HIGH, LOW)
            CLKFBOUT_MULT_F => CLK_MULT_F_C,    -- Multiply value for all CLKOUT (2.000-64.000).
            CLKFBOUT_PHASE => 0.0,     -- Phase offset in degrees of CLKFB (-360.000-360.000).
            CLKIN1_PERIOD => REF_PERIOD_C,      -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
            -- CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
            CLKOUT1_DIVIDE => CLK0_DIV_C,
            CLKOUT2_DIVIDE => CLK2_DIV_C,
            CLKOUT3_DIVIDE => CLK0_DIV_C,
            CLKOUT4_DIVIDE => CLK0_DIV_C,
            CLKOUT5_DIVIDE => CLK0_DIV_C,
            CLKOUT6_DIVIDE => CLK0_DIV_C,
            CLKOUT0_DIVIDE_F => real(CLK0_DIV_C),   -- Divide amount for CLKOUT0 (1.000-128.000).
            -- CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
            CLKOUT0_DUTY_CYCLE => 0.5,
            CLKOUT1_DUTY_CYCLE => 0.5,
            CLKOUT2_DUTY_CYCLE => 0.5,
            CLKOUT3_DUTY_CYCLE => 0.5,
            CLKOUT4_DUTY_CYCLE => 0.5,
            CLKOUT5_DUTY_CYCLE => 0.5,
            CLKOUT6_DUTY_CYCLE => 0.5,
            -- CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
            CLKOUT0_PHASE => CLKOUT0_PHASE_C,
            CLKOUT1_PHASE => CLKOUT1_PHASE_C,
            CLKOUT2_PHASE => 0.0,
            CLKOUT3_PHASE => 0.0,
            CLKOUT4_PHASE => 0.0,
            CLKOUT5_PHASE => 0.0,
            CLKOUT6_PHASE => 0.0,
            CLKOUT4_CASCADE => FALSE,  -- Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
            DIVCLK_DIVIDE => REF_CLK_DIV_C, -- Master division value (1-106)
            REF_JITTER1 => 0.0,        -- Reference input jitter in UI (0.000-0.999).
            STARTUP_WAIT => FALSE      -- Delays DONE until MMCM is locked (FALSE, TRUE)
         )
         port map (
            -- Clock Outputs: 1-bit (each) output: User configurable clock outputs
            CLKOUT0 => ulpiClkLocNb,     -- 1-bit output: CLKOUT0
            CLKOUT0B => open,   -- 1-bit output: Inverted CLKOUT0
            CLKOUT1 => ulpiClkRegNb,     -- 1-bit output: CLKOUT1
            CLKOUT1B => open,   -- 1-bit output: Inverted CLKOUT1
            CLKOUT2 => clk2Nb,     -- 1-bit output: CLKOUT2
            CLKOUT2B => open,   -- 1-bit output: Inverted CLKOUT2
            CLKOUT3 => open,     -- 1-bit output: CLKOUT3
            CLKOUT3B => open,   -- 1-bit output: Inverted CLKOUT3
            CLKOUT4 => open,     -- 1-bit output: CLKOUT4
            CLKOUT5 => open,     -- 1-bit output: CLKOUT5
            CLKOUT6 => open,     -- 1-bit output: CLKOUT6
            -- Feedback Clocks: 1-bit (each) output: Clock feedback ports
            CLKFBOUT => clkFbO,   -- 1-bit output: Feedback clock
            CLKFBOUTB => open, -- 1-bit output: Inverted CLKFBOUT
            -- Status Ports: 1-bit (each) output: MMCM status ports
            LOCKED => refLocked, -- 1-bit output: LOCK
            -- Clock Inputs: 1-bit (each) input: Clock input
            CLKIN1 => refClkLoc,       -- 1-bit input: Clock
            -- Control Ports: 1-bit (each) input: MMCM control ports
            PWRDWN => '0',       -- 1-bit input: Power-down
            RST => '0',             -- 1-bit input: Reset
            -- Feedback Clocks: 1-bit (each) input: Clock feedback ports
            CLKFBIN => clkFbI      -- 1-bit input: Feedback clock
         );

      B_FB     : BUFG port map ( I => clkFbO, O => clkFbI );

      G_CLKDDR : if ( ULPI_CLK_MODE_INP_G ) generate
         U_BUF : BUFG
            port map (
               I => ulpiClkRegNb,
               O => ulpiClkRegLoc
            );

         U_DDR : ODDR
            generic map (
               DDR_CLK_EDGE => "SAME_EDGE"
            )
            port map (
               C    => ulpiClkRegLoc,
               CE   => '1',
               D1   => '1',
               D2   => '0',
               R    => '0',
               S    => '0',
               Q    => ulpiClk_o
            );
      end generate G_CLKDDR;

   end generate G_MMCM;

   G_NO_MMCM : if ( not ULPI_CLK_MODE_INP_G and not USE_MMCM_C ) generate
      ulpiClkLocNb    <= ulpiClk;
   end generate G_NO_MMCM;

   G_NO_CLKDDR : if ( not ULPI_CLK_MODE_INP_G ) generate
      ulpiClk         <= 'Z';
   end generate G_NO_CLKDDR;

   U_REFBUF :  BUFG port map ( I => ulpiClkLocNb,    O => ulpiClkLoc );

   -- IO Buffers

   B_BUF : block is
      signal   ulpiDirNDly : std_logic;
      signal   ulpiNxtNDly : std_logic;
   begin

      ulpiIb.dir <= ulpiDirNDly;
      ulpiIb.nxt <= ulpiNxtNDly;

      U_DIR_IBUF : IBUF port map ( I => ulpiDir   , O => ulpiDirNDly );
      U_NXT_IBUF : IBUF port map ( I => ulpiNxt   , O => ulpiNxtNDly );

      U_STP_BUF  : IOBUF
         port map (
            IO => ulpiStp,
            I  => ulpiOb.stp,
            O  => ulpiIb.stp,
            T  => '0'
         );

      G_DAT_BUF : for i in ulpiIb.dat'range generate
         signal ulpiDatNDly : std_logic;
      begin

         ulpiIb.dat(i) <= ulpiDatNDly;

         U_BUF : IOBUF
            port map (
               IO => ulpiDat(i),
               I  => ulpiOb.dat(i),
               O  => ulpiDatNDly,
               T  => ulpiDirNDly
           );
      end generate G_DAT_BUF;

   end block B_BUF;

end architecture Impl;
