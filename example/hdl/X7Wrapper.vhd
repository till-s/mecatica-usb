-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Wrapper for Xilinx 7-series; instantiation of an MMCM, IO-buffers
-- and the multi-function USB device.

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
use     work.Usb2MuxEpCtlPkg.all;

entity X7Wrapper is
   generic (
      SYS_CLK_PERIOD_NS_G                : real     := 20.0;
      ULPI_CLK_MODE_INP_G                : boolean  := true;

      -- Note that the terms 'INPUT' and 'OUTPUT' clock, respectively
      -- follow the definitions in the ULPI spec, i.e., the directions
      -- are with reference to the ULPI-PHY and therefore opposite to
      -- the directions as seen by the FPGA. E.g., OUTPUT clock mode
      -- is when the PHY drives the clock to a FPGA input pin.

      -- ULPI INPUT CLOCK MODE PARAMETERS

      -- in ULPI INPUT clock mode the ULPI clock is generated from
      -- sysClk with an MMCM - depending on the system clock rate
      -- the CLK_MULT_F_G/CLK0_DIV_G/REF_CLK_DIV_G must be set to
      -- generate the 60MHz ULPI clock at CLKOUT0 of the MMCM
      REF_CLK_DIV_G                      : positive := 1;
      CLK_MULT_F_G                       : real     := 24.0;
      CLK0_DIV_G                         : positive := 20;
      -- CLKOUT2 is not currently used by could be employed to
      -- generate 200MHz for an IDELAY control module
      CLK2_DIV_G                         : positive := 6;
      -- CLK3 generates the audio bit clock (if the audio
      -- interface runs in subordinate mode
      CLK3_DIV_G                         : positive := 100;
      -- CLKOUT1 is used to generate a phase-shifted clock that
      -- toggles the DDR which produces the ULPI clock. This phase
      -- shift helps with timing and *must* be at least slightly negative
      -- or the multicycle exception constraint must be removed!
      -- (use a negative phase-shift to compensate
      -- the significant delays in the clock path and the output delay of the ULPI
      -- transceiver).
      CLK1_INP_PHASE_G                   : real     := -29.25;

      -- ULPI OUTPUT CLOCK MODE PARAMETERS

      -- in ULPI output clock mode the internal ULPI clock is phase-shifted
      -- by an MMCM to help timing
      -- phase must be a multiple of 45/CLK0_DIV = 3.0 (in output mode CLK0_DIV_G
      -- is not used!)
      -- Note that a small positive phase *must* be used -- otherwise the
      -- multicycle exception in the constraints must be removed!
      -- (delay the internal clock to compensate for the output delay of the
      -- ULPI transceiver)
      CLK0_OUT_PHASE_G                   : real     := 15.0;

      MARK_DEBUG_EP0_CTL_MUX_G           : boolean  := false;
      MARK_DEBUG_ULPI_IO_G               : boolean  := false;
      MARK_DEBUG_ULPI_LINE_STATE_G       : boolean  := false;
      MARK_DEBUG_PKT_RX_G                : boolean  := false;
      MARK_DEBUG_PKT_TX_G                : boolean  := false;
      MARK_DEBUG_PKT_PROC_G              : boolean  := false;
      MARK_DEBUG_EP0_G                   : boolean  := false;
      MARK_DEBUG_SND_G                   : boolean  := false
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
      -- iRegs(0,0)(26)           : DSR
      -- iRegs(0,0)(27)           : USB remote wakeup
      -- iRegs(0,0)(28)           : enable 'local' mode when the ACM is controlled from AXI.
      -- iRegs(0,0)(29)           : assert forced ULPI STP (useful to bring the PHY to reason if it holds DIR)
      -- iRegs(0,0)(30)           : mask/disable IN/OUT fifo's write/read enable when set.
      -- iRegs(0,0)(31)           : DCD
      -- iRegs(0,1)               : IN fifo fill timer (in ulpi CLK cycles)
      --                            fill-level and fill-timer work like termios VMIN/VTIME
      -- CDC-ECM
      -- iRegs(1,0)(10 downto 0)  : min. fill level of the IN fifo until data are sent to USB
      -- iRegs(1,0)(31)           : carrier indicator
      -- iRegs(1,1)               : IN fifo fill timer (in ulpi CLK cycles)
      -- CDC-NCM
      -- iRegs(2,0)(31)           : carrier indicator
      iRegs                : in    RegArray(0 to 2, 0 to 1);
      -- status vector
      -- CDC-ACM
      -- oRegs(0,0)(15 downto  0) : IN  fifo fill level
      -- oRegs(0,0)(23 downto 21) : device type "001"
      -- oRegs(0,0)(27 downto 24) : ld of OUT fifo size
      -- oRegs(0,0)(31 downto 28) : ld of IN  fifo size

      -- oRegs(0,1)(15 downto  0) : OUT fifo fill level
      -- oRegs(0,1)(16)           : DTR
      -- oRegs(0,1)(17)           : RTS
      -- oRegs(0,1)(18)           : lineBreak
      -- CDC-ECM
      -- oRegs(1,0)(15 downto  0) : IN fifo fill level
      -- oRegs(1,0)(20 downto 16) : packet filter flags
      -- oRegs(1,0)(23 downto 21) : device type "010"
      -- oRegs(1,0)(27 downto 24) : ld of OUT fifo size
      -- oRegs(1,0)(31 downto 28) : ld of IN  fifo size
      -- oRegs(1,1)(15 downto  0) : OUT fifo fill level
      -- oRegs(1,1)(31 downto 16) : OUT fifo # of frames
      -- CDC-NCM
      -- oRegs(2,0)(15 downto  0) : IN fifo fill level
      -- oRegs(2,0)(23 downto 21) : device type "011"
      -- oRegs(2,0)(27 downto 24) : ld of OUT fifo size
      -- oRegs(2,0)(31 downto 28) : ld of IN  fifo size
      -- oRegs(2,1)(          16) : OUT fifo not empty
      oRegs                : out   RegArray(0 to 2, 0 to 1);

      regReq               : in    UlpiRegReqType;
      regRep               : out   UlpiRegRepType;

      acmFifoOutDat        : out   Usb2ByteType;
      acmFifoOutEmpty      : out   std_logic;
      acmFifoOutFill       : out   unsigned(15 downto 0);
      acmFifoOutRen        : in    std_logic := '1';

      acmFifoInpDat        : in    Usb2ByteType := (others => '0');
      acmFifoInpFull       : out   std_logic;
      acmFifoInpFill       : out   unsigned(15 downto 0);
      acmFifoInpWen        : in    std_logic := '1';

      acmFifoRstOut        : out   std_logic;

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
      ecmFifoOutLast       : out   std_logic;
      ecmFifoOutEmpty      : out   std_logic;
      ecmFifoOutFill       : out   unsigned(15 downto 0);
      ecmFifoOutFrms       : out   unsigned(15 downto 0);
      ecmFifoOutRen        : in    std_logic := '1';

      ecmFifoInpDat        : in    Usb2ByteType := (others => '0');
      ecmFifoInpLast       : in    std_logic;
      ecmFifoInpFull       : out   std_logic;
      ecmFifoInpFill       : out   unsigned(15 downto 0);
      ecmFifoInpWen        : in    std_logic := '0';

      ecmFifoRstOut        : out   std_logic;

      ncmFifoOutDat        : out   Usb2ByteType := (others => '0');
      ncmFifoOutLast       : out   std_logic := '0';
      ncmFifoOutEmpty      : out   std_logic := '0';
      ncmFifoOutRen        : in    std_logic := '1';

      ncmFifoInpDat        : in    Usb2ByteType := (others => '0');
      ncmFifoInpLast       : in    std_logic := '1';
      ncmFifoInpBusy       : out   std_logic := '1';
      ncmFifoInpFull       : out   std_logic := '0';
      ncmFifoInpAvail      : out   signed(15 downto 0) := (others => '0');
      ncmFifoInpWen        : in    std_logic := '0';

      ncmFifoRstOut        : out   std_logic;

      clk2Nb               : out   std_logic := '0';
      clk3Nb               : out   std_logic := '0';

      i2sBCLK              : in    std_logic;
      i2sPBLRC             : in    std_logic;
      i2sPBDAT             : out   std_logic
   );
end entity X7Wrapper;

architecture Impl of X7Wrapper is

   constant FW_ACM_C                           : std_logic_vector(2 downto 0) := "001";
   constant FW_ECM_C                           : std_logic_vector(2 downto 0) := "010";
   constant FW_NCM_C                           : std_logic_vector(2 downto 0) := "011";

   constant USE_MMCM_C                         : boolean := true;

   constant LD_ACM_FIFO_DEPTH_INP_C            : natural := 10;
   constant LD_ACM_FIFO_DEPTH_OUT_C            : natural := 10;
   -- min. 2 ethernet frames -> 4kB
   constant LD_ECM_FIFO_DEPTH_INP_C            : natural := 12;
   constant LD_ECM_FIFO_DEPTH_OUT_C            : natural := 12;

   -- min. 2 ethernet frames -> 4kB
   constant LD_NCM_RAM_DEPTH_INP_C             : natural := 12;
   constant LD_NCM_RAM_DEPTH_OUT_C             : natural := 12;

   constant ECM_MAC_IDX_C                      : integer :=
      usb2EthMacAddrStringDescriptor( USB2_APP_DESCRIPTORS_C, USB2_IFC_SUBCLASS_CDC_ECM_C );
   constant NCM_MAC_IDX_C                      : integer :=
      usb2EthMacAddrStringDescriptor( USB2_APP_DESCRIPTORS_C, USB2_IFC_SUBCLASS_CDC_NCM_C );
   constant USE_MAC_IDX_C                      : integer := ite( NCM_MAC_IDX_C < 0, ECM_MAC_IDX_C, NCM_MAC_IDX_C );

   signal acmFifoTimer                         : unsigned(31 downto 0) := (others => '0');
   signal acmFifoMinFill                       : unsigned(LD_ACM_FIFO_DEPTH_INP_C - 1 downto 0) := (others => '0');

   signal acmFifoFilledInp                     : unsigned(15 downto 0) := (others => '0');
   signal acmFifoFilledOut                     : unsigned(15 downto 0) := (others => '0');
   signal acmFifoLocal                         : std_logic    := '0';

   signal ecmFifoFilledInp                     : unsigned(15 downto 0) := (others => '0');
   signal ecmFifoFilledOut                     : unsigned(15 downto 0) := (others => '0');
   signal ecmFifoFramesOut                     : unsigned(15 downto 0) := (others => '0');

   signal ecmFifoTimer                         : unsigned(31 downto 0) := (others => '0');
   signal ecmFifoMinFill                       : unsigned(LD_ECM_FIFO_DEPTH_INP_C - 1 downto 0) := (others => '0');
   signal ecmPacketFilter                      : std_logic_vector(4 downto 0);
   signal ecmCarrier                           : std_logic;

   signal ncmFifoAvailInp                      : signed(15 downto 0)   := (others => '1');
   signal ncmFifoEmptyOut                      : std_logic;
   signal ncmCarrier                           : std_logic;

   signal ulpiClkLoc                           : std_logic;
   signal ulpiClkLocNb                         : std_logic;
   signal ulpiForceStp                         : std_logic;

   signal usb2RstLoc                           : std_logic;
   signal usb2RstFromHost                      : std_logic;

   signal ulpiIb                               : UlpiIbType;
   signal ulpiOb                               : UlpiObType;

   signal usb2RemoteWake                       : std_logic;

   signal descRWIb                             : Usb2DescRWIbType   := USB2_DESC_RW_IB_INIT_C;
   signal descRWOb                             : Usb2DescRWObType   := USB2_DESC_RW_OB_INIT_C;

   signal macAddrPatchDone                     : std_logic := '1';

   signal gnd                                  : std_logic := '0';

   signal DTR, RTS, lineBreak, DCD, DSR        : std_logic;

begin

   -- Output assignments

   ulpiClkOut      <= ulpiClkLoc;
   usb2RstLoc      <= not macAddrPatchDone;
   usb2Rst         <= usb2RstFromHost or ulpiRst or usb2RstLoc;

   acmFifoOutFill  <= resize( acmFifoFilledOut, acmFifoOutFill'length );
   acmFifoInpFill  <= resize( acmFifoFilledInp, acmFifoInpFill'length );
   ecmFifoOutFill  <= resize( ecmFifoFilledOut, ecmFifoOutFill'length );
   ecmFifoOutFrms  <= resize( ecmFifoFramesOut, ecmFifoOutFrms'length );
   ecmFifoInpFill  <= resize( ecmFifoFilledInp, ecmFifoInpFill'length );

   ncmFifoOutEmpty <= ncmFifoEmptyOut;
   ncmFifoInpAvail <= resize(ncmFifoAvailInp, ncmFifoInpAvail'length);

   -- Register assignments
   P_RG : process (
      acmFifoFilledInp,
      acmFifoFilledOut,
      ecmFifoFilledInp,
      ecmFifoFilledOut,
      ecmFifoFramesOut,
      ecmPacketFilter,
      ncmFifoAvailInp,
      ncmFifoEmptyOut,
      DTR, RTS, lineBreak
   ) is
   begin
      oRegs <= (others => (others => (others => '0')));

      oRegs(0,0)(31 downto 28)           <= std_logic_vector(to_unsigned(LD_ACM_FIFO_DEPTH_INP_C, 4));
      oRegs(0,0)(27 downto 24)           <= std_logic_vector(to_unsigned(LD_ACM_FIFO_DEPTH_OUT_C, 4));
      oRegs(0,0)(23 downto 21)           <= FW_ACM_C;
      oRegs(0,0)(20 downto 16)           <= (others => '0');
      oRegs(0,0)(15 downto  0)           <= std_logic_vector(resize(acmFifoFilledInp, 16));

      oRegs(0,1)(15 downto  0)           <= std_logic_vector(resize(acmFifoFilledOut, 16));
      oRegs(0,1)(16)                     <= DTR;
      oRegs(0,1)(17)                     <= RTS;
      oRegs(0,1)(18)                     <= lineBreak;

      oRegs(1,0)(31 downto 28)           <= std_logic_vector(to_unsigned(LD_ECM_FIFO_DEPTH_INP_C, 4));
      oRegs(1,0)(27 downto 24)           <= std_logic_vector(to_unsigned(LD_ECM_FIFO_DEPTH_OUT_C, 4));
      oRegs(1,0)(23 downto 21)           <= FW_ECM_C;
      oRegs(1,0)(20 downto 16)           <= ecmPacketFilter;
      oRegs(1,0)(15 downto  0)           <= std_logic_vector(resize(ecmFifoFilledInp, 16));

      oRegs(1,1)(31 downto 16)           <= std_logic_vector(resize(ecmFifoFramesOut, 16));
      oRegs(1,1)(15 downto  0)           <= std_logic_vector(resize(ecmFifoFilledOut, 16));

      oRegs(2,0)(31 downto 28)           <= std_logic_vector(to_unsigned(LD_NCM_RAM_DEPTH_INP_C, 4));
      oRegs(2,0)(27 downto 24)           <= std_logic_vector(to_unsigned(LD_NCM_RAM_DEPTH_OUT_C, 4));
      oRegs(2,0)(23 downto 21)           <= FW_NCM_C;
      oRegs(2,0)(20 downto 16)           <= (others => '0');
      oRegs(2,0)(15 downto  0)           <= std_logic_vector(resize(ncmFifoAvailInp, 16));
      oRegs(2,1)(31 downto 17)           <= (others => '0');
      oRegs(2,1)(          16)           <= not ncmFifoEmptyOut;
      oRegs(2,1)(15 downto  0)           <= (others => '0');
   end process P_RG;


   acmDTR          <= DTR;
   acmRTS          <= RTS;
   acmLineBreak    <= lineBreak;
   acmFifoMinFill  <= unsigned(iRegs(0,0)(acmFifoMinFill'range));
   acmFifoTimer    <= unsigned(iRegs(0,1)(acmFifoTimer'range));
   DCD             <= iRegs(0,0)(31);
   ulpiForceStp    <= iRegs(0,0)(29);
   acmFifoLocal    <= iRegs(0,0)(28);
   usb2RemoteWake  <= iRegs(0,0)(27);
   DSR             <= iRegs(0,0)(26);

   ecmFifoMinFill  <= unsigned(iRegs(1,0)(ecmFifoMinFill'range));
   ecmCarrier      <= iRegs(1,0)(31);
   ecmFifoTimer    <= unsigned(iRegs(1,1)(ecmFifoTimer'range));

   ncmCarrier      <= iRegs(2,0)(31);

   -- USB2 Core

   U_USB2_DEV : entity work.Usb2ExampleDev
      generic map (
         ULPI_CLK_MODE_INP_G          => ULPI_CLK_MODE_INP_G,
         DESCRIPTORS_G                => USB2_APP_DESCRIPTORS_C,
         DESCRIPTORS_BRAM_G           => true,

         LD_ACM_FIFO_DEPTH_INP_G      => LD_ACM_FIFO_DEPTH_INP_C,
         LD_ACM_FIFO_DEPTH_OUT_G      => LD_ACM_FIFO_DEPTH_OUT_C,
         CDC_ACM_ASYNC_G              => false,

         LD_ECM_FIFO_DEPTH_INP_G      => LD_ECM_FIFO_DEPTH_INP_C,
         LD_ECM_FIFO_DEPTH_OUT_G      => LD_ECM_FIFO_DEPTH_OUT_C,
         CDC_ECM_ASYNC_G              => false,

         LD_NCM_RAM_DEPTH_INP_G       => LD_NCM_RAM_DEPTH_INP_C,
         LD_NCM_RAM_DEPTH_OUT_G       => LD_NCM_RAM_DEPTH_OUT_C,
         CDC_NCM_ASYNC_G              => false,

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
         usb2Clk                      => ulpiClkLoc,

         usb2Rst                      => usb2RstLoc,
         usb2RstOut                   => usb2RstFromHost,
         ulpiRst                      => ulpiRst,

         ulpiIb                       => ulpiIb,
         ulpiOb                       => ulpiOb,

         ulpiForceStp                 => ulpiForceStp,

         usb2RemoteWake               => usb2RemoteWake,

         ulpiRegReq                   => regReq,
         ulpiRegRep                   => regRep,

         usb2HiSpeedEn                => '1',

         usb2DescRWClk                => ulpiClkLoc,
         usb2DescRWIb                 => descRWIb,
         usb2DescRWOb                 => descRWOb,

         acmFifoClk                   => ulpiClkLoc,
         acmFifoRstOut                => acmFifoRstOut,

         acmFifoOutDat                => acmFifoOutDat,
         acmFifoOutEmpty              => acmFifoOutEmpty,
         acmFifoOutFill               => acmFifoFilledOut,
         acmFifoOutRen                => acmFifoOutRen,

         acmFifoInpDat                => acmFifoInpDat,
         acmFifoInpFull               => acmFifoInpFull,
         acmFifoInpFill               => acmFifoFilledInp,
         acmFifoInpWen                => acmFifoInpWen,
         acmFifoInpMinFill            => acmFifoMinFill,
         acmFifoInpTimer              => acmFifoTimer,

         acmLineBreak                 => lineBreak,
         acmDTR                       => DTR,
         acmRTS                       => RTS,
         acmDCD                       => DCD,
         acmDSR                       => DSR,

         acmFifoLocal                 => acmFifoLocal,

         baddVolMaster                => baddVolMaster,
         baddVolLeft                  => baddVolLeft,
         baddVolRight                 => baddVolRight,
         baddMuteMaster               => baddMuteMaster,
         baddMuteLeft                 => baddMuteLeft,
         baddMuteRight                => baddMuteRight,
         baddPowerState               => baddPowerState,

         ecmFifoClk                   => ulpiClkLoc,
         ecmFifoRstOut                => ecmFifoRstOut,

         ecmFifoOutDat                => ecmFifoOutDat,
         ecmFifoOutLast               => ecmFifoOutLast,
         ecmFifoOutEmpty              => ecmFifoOutEmpty,
         ecmFifoOutFill               => ecmFifoFilledOut,
         ecmFifoOutFrms               => ecmFifoFramesOut,
         ecmFifoOutRen                => ecmFifoOutRen,

         ecmFifoInpDat                => ecmFifoInpDat,
         ecmFifoInpLast               => ecmFifoInpLast,
         ecmFifoInpFull               => ecmFifoInpFull,
         ecmFifoInpFill               => ecmFifoFilledInp,
         ecmFifoInpWen                => ecmFifoInpWen,
         ecmFifoInpMinFill            => ecmFifoMinFill,
         ecmFifoInpTimer              => ecmFifoTimer,

         ecmPacketFilter              => ecmPacketFilter,

         ecmCarrier                   => ecmCarrier,

         ncmFifoClk                   => ulpiClkLoc,
         ncmFifoRstOut                => ncmFifoRstOut,

         ncmFifoOutDat                => ncmFifoOutDat,
         ncmFifoOutLast               => ncmFifoOutLast,
         ncmFifoOutEmpty              => ncmFifoEmptyOut,
         ncmFifoOutRen                => ncmFifoOutRen,

         ncmFifoInpDat                => ncmFifoInpDat,
         ncmFifoInpLast               => ncmFifoInpLast,
         ncmFifoInpBusy               => ncmFifoInpBusy,
         ncmFifoInpFull               => ncmFifoInpFull,
         ncmFifoInpAvail              => ncmFifoAvailInp,
         ncmFifoInpWen                => ncmFifoInpWen,

         ncmCarrier                   => ncmCarrier,

         i2sBCLK                      => i2sBCLK,
         i2sPBLRC                     => i2sPBLRC,
         i2sPBDAT                     => i2sPBDAT
      );

   -- Patch device DNA into the iMACAddress descriptor (which is a string,
   -- so we must convert to utf-16-le which is trivial for '0'-'F')
   G_PATCH_MAC_ADDR : if ( USE_MAC_IDX_C >= 0 ) generate
      signal   dnaShift                 : std_logic := '0';
      signal   dnaRead                  : std_logic := '0';
      signal   dnaOut                   : std_logic := '0';

      -- each nibble is one unicode character
      constant OFFBEG_C                 : Usb2DescIdxType := 2 + 2*2;   -- header + 2 unicode char
      constant OFFEND_C                 : Usb2DescIdxType := 2 + 2*11;  -- header + 11 unicode chars

      constant SREG_INIT_C              : std_logic_vector(4 downto 0) := ( 0 => '1', others => '0');

      type StateType is ( INIT, SHIFT_AND_PATCH, DONE );

      type RegType is record
         state        : StateType;
         dnaRead      : std_logic;
         offset       : Usb2DescIdxType;
         -- one extra bit as a marker
         sreg         : std_logic_vector(4 downto 0);
      end record RegType;

      constant REG_INIT_C : RegType := (
         state        => INIT,
         dnaRead      => '1',
         offset       => (2 + 2*2),
         sreg         => SREG_INIT_C
      );

      signal   r      : RegType := REG_INIT_C;
      signal   rin    : RegType;

      function ascii(constant x : in std_logic_vector(3 downto 0))
      return Usb2ByteType is
         variable v : unsigned(Usb2ByteType'range);
      begin
         v := 16#30# + resize(unsigned(x), v'length);
         if ( unsigned(x) > 9 ) then
            v := v + 7;
         end if;
         return Usb2ByteType(v);
      end function ascii;

   begin

      dnaRead         <= r.dnaRead;

      P_COMB : process ( r, dnaOut, descRWIb ) is
         variable v : RegType;
      begin
         v                := r;
         macAddrPatchDone <= '0';
         dnaShift         <= '0';
         descRWIb         <= USB2_DESC_RW_IB_INIT_C;
         descRWIb.addr    <= to_unsigned( USE_MAC_IDX_C + r.offset, descRWIb.addr'length );
         descRWIb.wdata   <= ascii( r.sreg(3 downto 0) );

         case ( r.state ) is
            when INIT =>
               v.state   := SHIFT_AND_PATCH;
               v.dnaRead := '0';

            when SHIFT_AND_PATCH =>
               if ( r.sreg(r.sreg'left) = '1' ) then
                  -- got a nibble; write
                 descRWIb.cen <= '1';
                 descRWIb.wen <= '1';
                 if ( r.offset = OFFEND_C ) then
                    v.state  := DONE;
                 else
                    v.offset := r.offset + 2; -- next unicode char
                    v.sreg   := SREG_INIT_C;
                 end if;
               else
                  dnaShift <= '1';
                  v.sreg   := r.sreg(r.sreg'left - 1 downto 0) & dnaOut;
               end if;

            when DONE =>
               macAddrPatchDone <= '1';
         end case;

         rin <= v;
      end process P_COMB;

      P_SEQ  : process ( ulpiClkLoc ) is
      begin
         if ( rising_edge( ulpiClkLoc ) ) then
            -- while clock not stable hold in reset
            if ( ulpiRst = '1' ) then
               r <= REG_INIT_C;
            else
               r <= rin;
            end if;
         end if;
      end process P_SEQ;

      U_DNA_PORT : DNA_PORT
         port map (
            CLK                        => ulpiClkLoc,
            DIN                        => '0',
            READ                       => dnaRead,
            SHIFT                      => dnaShift,
            DOUT                       => dnaOut
         );

   end generate G_PATCH_MAC_ADDR;


   -- Clock generation

   G_MMCM : if ( ULPI_CLK_MODE_INP_G or USE_MMCM_C ) generate

      signal clkFbI, clkFbO    : std_logic;
      signal refClkLoc         : std_logic;

      constant CLK_MULT_F_C    : real    := ite( ULPI_CLK_MODE_INP_G, CLK_MULT_F_G,        15.000 );
      constant REF_PERIOD_C    : real    := ite( ULPI_CLK_MODE_INP_G, SYS_CLK_PERIOD_NS_G, 16.667 );
      constant CLK0_DIV_C      : natural := ite( ULPI_CLK_MODE_INP_G, CLK0_DIV_G,          15     );
      constant CLK2_DIV_C      : natural := ite( ULPI_CLK_MODE_INP_G, CLK2_DIV_G,          15     );
      constant CLK3_DIV_C      : natural := ite( ULPI_CLK_MODE_INP_G, CLK3_DIV_G,          75     );
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
            CLKOUT3_DIVIDE => CLK3_DIV_C,
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
            CLKOUT3 => clk3Nb,     -- 1-bit output: CLKOUT3
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
