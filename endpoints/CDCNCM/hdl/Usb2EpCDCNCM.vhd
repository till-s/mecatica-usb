-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- CDC NCM Endpoint with a FIFO interface. It also demonstrates
-- the implementation of a control interface via device requests (EP0).
-- Asynchronous clock domains are supported.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

entity Usb2EpCDCNCM is
   generic (
      -- interface number of control interface
      CTL_IFC_NUM_G              : natural;
      ASYNC_G                    : boolean   := false;
      -- epClk ticks we hold off sending data (IN direction) trying
      -- to gather more packets into the NTB (empty = auto; based on
      -- NTB size)
      TIMEOUT_INP_TICKS_G        : unsigned  := "";
      -- FIFO parameters (ld_fifo_depth are the width of the internal
      -- address pointers, i.e., ceil( log2( depth - 1 ) ))
      LD_RAM_DEPTH_INP_G         : natural;
      -- max. # of datagrams in IN  direction (0 = auto-sized based on RAM_DEPTH)
      MAX_NTB_SIZE_INP_G         : natural   := 0;
      --- number of datagrams (0 = auto selection based on NTB_SIZE)
      MAX_DGRAMS_INP_G           : natural   := 0;
      -- for max. throughput the OUT fifo must be big enough
      -- to hold at least two maximally sized packets.
      LD_RAM_DEPTH_OUT_G         : natural;
      -- max. NTB size *must not* be a multiple of the max. packet
      -- size (0: auto-selection based on ram depth)
      MAX_NTB_SIZE_OUT_G         : natural   := 0;
      -- max. # of datagrams in OUT direction (0 = no limit)
      MAX_DGRAMS_OUT_G           : natural   := 0;

      -- support the GET_NET_ADDRESS/SET_NET_ADDRESS requests
      SUPPORT_NET_ADDRESS_G      : boolean   := false;
      DFLT_MAC_ADDR_G            : Usb2ByteArray(0 to 5) := (others => (others => '0'));

      CARRIER_DFLT_G             : std_logic := '1';
      MARK_DEBUG_G               : boolean   := false
   );
   port (
      usb2Clk                    : in  std_logic;
      usb2Rst                    : in  std_logic;
      usb2EpRstOut               : out std_logic;

      -- ********************************************
      -- signals below here are in the usb2Clk domain
      -- ********************************************

      -- EP0 interface
      usb2Ep0ReqParam            : in  Usb2CtlReqParamType := USB2_CTL_REQ_PARAM_INIT_C;
      usb2Ep0CtlExt              : out Usb2CtlExtType      := USB2_CTL_EXT_NAK_C;

      -- Control interface endpoint pair
      usb2CtlEpIb                : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2CtlEpOb                : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

      -- Data interface bulk endpoint pair
      usb2DataEpIb               : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2DataEpOb               : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

      -- Notification (interrupt) endpoint pair
      usb2NotifyEpIb             : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2NotifyEpOb             : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

      -- note that this is in the USB2 clock domain; if you really
      -- need this (and if ASYNC_G) you need to sync from the epClk 
      -- yourself...
      packetFilter               : out std_logic_vector(4 downto 0);

      speedInp                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );
      speedOut                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );

      -- mac address (network-byte order; only valid if SUPPORT_NET_ADDRESS_G)
      macAddress                 : out Usb2ByteArray(0 to 5);

      -- *******************************************************
      -- signals below here are in the epClk domain (if ASYNC_G)
      -- *******************************************************

      -- FIFO output clock (may be different from usb2Clk if ASYNC_G is true)
      epClk                      : in  std_logic;
      -- endpoint reset from USB
      epRstOut                   : out std_logic;

      -- FIFO Interface

      fifoDataInp                : in  Usb2ByteType;
      -- write-enable; data are *not* written while fifoFullInp is asserted.
      -- I.e., it is safe to hold fifoDataInp/fifoWenaInp steady until fifoFullInp
      -- is deasserted.
      fifoLastInp                : in  std_logic;
      -- abort/kill a partial packet in the INP FIFO by rewinding the write-pointer.
      -- Useful, e.g., when a bad CRC is detected.
      fifoAbrtInp                : in  std_logic := '0';
      fifoWenaInp                : in  std_logic;
      fifoFullInp                : out std_logic;
      -- data are only accepted if Wena and not Full and not Busy
      fifoBusyInp                : out std_logic;
      -- approximate number of available slots (reports 1 less than is
      -- actually available) < 0 means the fifo is full.
      fifoAvailInp               : out signed(LD_RAM_DEPTH_INP_G downto 0);

      fifoDataOut                : out Usb2ByteType;
      fifoLastOut                : out std_logic;
      -- abort a partially sent packet by rewinding the read pointer of the OUT
      -- FIFO. Useful, e.g., when a collision is detected. The packet remains
      -- in the FIFO and can be replayed.
      fifoAbrtOut                : in  std_logic := '0';
      -- read-enable; data are *not* read while fifoEmptyOut is asserted.
      -- I.e., it is safe to hold fifoRenaOut steady until fifoEmptyOut
      -- is deasserted.
      fifoRenaOut                : in  std_logic;
      -- when set then the transmitter must pad to min-length and append a CRC
      fifoCrcOut                 : out std_logic;
      fifoEmptyOut               : out std_logic;

      carrier                    : in  std_logic := CARRIER_DFLT_G
   );

   attribute MARK_DEBUG of usb2NotifyEpOb : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of packetFilter   : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of carrier        : signal is toStr( MARK_DEBUG_G );

end entity Usb2EpCDCNCM;

architecture Impl of Usb2EpCDCNCM is

   function MAX_NTB_SIZE_INP_F return natural is
   begin
      if ( MAX_NTB_SIZE_INP_G > 0 ) then
         return MAX_NTB_SIZE_INP_G;
      else
         return 2**(LD_RAM_DEPTH_INP_G - 1);
      end if;
   end function MAX_NTB_SIZE_INP_F;

   function MAX_NTB_SIZE_OUT_F return natural is
   begin
      if ( MAX_NTB_SIZE_OUT_G > 0 ) then
         return MAX_NTB_SIZE_OUT_G;
      else
         -- avoid being a multiple of the max-pkt size!
         return 2**(LD_RAM_DEPTH_INP_G - 1) - 1;
      end if;
   end function MAX_NTB_SIZE_OUT_F;

   function MAX_DGRAMS_INP_F return natural is
   begin
      if ( MAX_DGRAMS_INP_G > 0 ) then
         return MAX_DGRAMS_INP_G;
      else
         -- 4 datagrams per 2k NTB
         return MAX_NTB_SIZE_INP_F/512;
      end if;
   end function MAX_DGRAMS_INP_F;

   function TIMEOUT_INP_TICKS_F return unsigned is
   begin
      return ite( TIMEOUT_INP_TICKS_G'length > 0,
                  TIMEOUT_INP_TICKS_G,
                  to_unsigned( MAX_NTB_SIZE_INP_F, numBits( MAX_NTB_SIZE_INP_F ) ) );
   end function TIMEOUT_INP_TICKS_F;

   constant TIMEOUT_INP_TICKS_C           : unsigned           := TIMEOUT_INP_TICKS_F;

   signal epRstLoc                        : std_logic          := '0';
   signal usb2EpRstLoc                    : std_logic          := '0';
   signal usb2EpRst                       : std_logic;

   signal epOut                           : usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal epInp                           : usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

   signal usb2RamWrPtrOut                 : unsigned(LD_RAM_DEPTH_OUT_G downto 0);
   signal usb2RamRdPtrOut                 : unsigned(LD_RAM_DEPTH_OUT_G downto 0);
   signal epRamWrPtrOut                   : unsigned(LD_RAM_DEPTH_OUT_G downto 0);
   signal epRamRdPtrOut                   : unsigned(LD_RAM_DEPTH_OUT_G downto 0);

   signal usb2RamWrPtrInp                 : unsigned(LD_RAM_DEPTH_INP_G downto 0);
   signal usb2RamRdPtrInp                 : unsigned(LD_RAM_DEPTH_INP_G downto 0);
   signal epRamWrPtrInp                   : unsigned(LD_RAM_DEPTH_INP_G downto 0);
   signal epRamRdPtrInp                   : unsigned(LD_RAM_DEPTH_INP_G downto 0);

   signal usb2MaxNTBSizeInp               : unsigned(31                 downto 0);
   signal epMaxNTBSizeInp                 : unsigned(LD_RAM_DEPTH_INP_G downto 0);

begin

   usb2EpRst <= usb2Rst or not epInpRunning( usb2DataEpIb ) or not epOutRunning( usb2DataEpIb );

   U_EP_CTL : entity work.Usb2EpCDCNCMCtl
      generic map (
         CTL_IFC_NUM_G             => CTL_IFC_NUM_G,
         MAX_NTB_SIZE_INP_G        => MAX_NTB_SIZE_INP_F,
         MAX_NTB_SIZE_OUT_G        => MAX_NTB_SIZE_OUT_F,
         MAX_DGRAMS_OUT_G          => MAX_DGRAMS_OUT_G,
         SUPPORT_NET_ADDRESS_G     => SUPPORT_NET_ADDRESS_G,
         MAC_ADDR_G                => DFLT_MAC_ADDR_G
      )
      port map (
         usb2Clk                   => usb2Clk,
         usb2Rst                   => usb2Rst,

         usb2Ep0ReqParam           => usb2Ep0ReqParam,
         usb2Ep0CtlExt             => usb2Ep0CtlExt,

         usb2Ep0IbExt              => usb2CtlEpIb,
         usb2Ep0ObExt              => usb2CtlEpOb,

         maxNTBSizeInp             => usb2MaxNTBSizeInp,
         macAddress                => macAddress
      );

   U_EP_NOT : entity work.Usb2EpCDCEtherNotify
      generic map (
         CTL_IFC_NUM_G             => CTL_IFC_NUM_G,
         ASYNC_G                   => ASYNC_G,
         CARRIER_DFLT_G            => CARRIER_DFLT_G,
         SEND_CARRIER_FIRST_G      => false,
         MARK_DEBUG_G              => false
      )
      port map (
         usb2Clk                   => usb2Clk,
         usb2Rst                   => usb2Rst,

         usb2NotifyEpIb            => usb2NotifyEpIb,
         usb2NotifyEpOb            => usb2NotifyEpOb,

         speedInp                  => speedInp,
         speedOut                  => speedOut,

         epClk                     => epClk,
         epRst                     => epRstLoc,

         carrier                   => carrier
      );

   U_EP_INP : entity work.Usb2EpCDCNCMInp
      generic map (
         LD_RAM_DEPTH_G            => LD_RAM_DEPTH_INP_G,
         MAX_DGRAMS_G              => MAX_DGRAMS_INP_F,
         MAX_NTB_SIZE_G            => MAX_NTB_SIZE_INP_F,
         EP_TIMER_WIDTH_G          => TIMEOUT_INP_TICKS_C'length
      )
      port map (
         usb2Clk                   => usb2Clk,
         usb2Rst                   => usb2EpRst,

         usb2EpIb                  => usb2DataEpIb,
         usb2EpOb                  => epInp,

         ramRdPtrOb                => usb2RamRdPtrInp,
         ramWrPtrIb                => usb2RamWrPtrInp,

         epClk                     => epClk,
         epRst                     => epRstLoc,

         ramWrPtrOb                => epRamWrPtrInp,
         ramRdPtrIb                => epRamRdPtrInp,

         maxNTBSize                => epMaxNTBSizeInp,
         timeout                   => TIMEOUT_INP_TICKS_C,

         fifoDataInp               => fifoDataInp,
         fifoLastInp               => fifoLastInp,
         fifoAbrtInp               => fifoAbrtInp,
         fifoWenaInp               => fifoWenaInp,
         fifoFullInp               => fifoFullInp,
         fifoBusyInp               => fifoBusyInp,
         fifoAvailInp              => fifoAvailInp
      );


   U_EP_OUT : entity work.Usb2EpCDCNCMOut
      generic map (
         LD_RAM_DEPTH_G            => LD_RAM_DEPTH_OUT_G
      )
      port map (
         usb2Clk                   => usb2Clk,
         usb2Rst                   => usb2EpRst,

         usb2EpIb                  => usb2DataEpIb,
         usb2EpOb                  => epOut,

         ramWrPtrOb                => usb2RamWrPtrOut,
         ramRdPtrIb                => usb2RamRdPtrOut,

         epClk                     => epClk,
         epRst                     => epRstLoc,

         ramRdPtrOb                => epRamRdPtrOut,
         ramWrPtrIb                => epRamWrPtrOut,

         fifoDataOut               => fifoDataOut,
         fifoLastOut               => fifoLastOut,
         fifoAbrtOut               => fifoAbrtOut,
         fifoRenaOut               => fifoRenaOut,
         fifoCrcOut                => fifoCrcOut,
         fifoEmptyOut              => fifoEmptyOut
      );

   usb2DataEpOb <= usb2MergeEndpPairIb( epInp, epOut );
   epRstOut     <= epRstLoc;
   usb2EpRstOut <= usb2EpRstLoc;

   G_SYNC : if ( not ASYNC_G ) generate
      usb2RamRdPtrOut <= epRamRdPtrOut;
      epRamWrPtrOut   <= usb2RamWrPtrOut;
      epRamRdPtrInp   <= usb2RamRdPtrInp;
      usb2RamWrPtrInp <= epRamWrPtrInp;
      epMaxNTBSizeInp <= usb2MaxNTBSizeInp(epMaxNTBSizeInp'range);
      epRstLoc        <= usb2Rst;
      usb2EpRstLoc    <= usb2EpRst;
   end generate G_SYNC;

   G_ASYNC : if ( ASYNC_G ) generate

      constant A2B_L : natural := epMaxNTBSizeInp'length + usb2RamRdPtrInp'length + usb2RamWrPtrOut'length + 1;
      constant B2A_L : natural := usb2RamWrPtrInp'length + usb2RamRdPtrOut'length + 1;

      signal resettingA     : std_logic := '1'; -- signal initial reset

      signal rstARtn        : std_logic; -- rst A full round trip
      signal rstASeenAtB    : std_logic;

      signal dinA2B, douA2B : std_logic_vector(A2B_L - 1 downto 0);
      signal dinB2A, douB2A : std_logic_vector(B2A_L - 1 downto 0);

      subtype slv is std_logic_vector;

   begin

      dinA2B <= slv( usb2MaxNTBSizeInp(epMaxNTBSizeInp'range) ) & slv( usb2RamRdPtrInp ) & slv( usb2RamWrPtrOut ) & resettingA;
      dinB2A <= slv( epRamWrPtrInp ) & slv( epRamRdPtrOut ) & rstASeenAtB;

      P_ASSIGN : process ( douA2B, douB2A ) is
         variable l,h : natural;
      begin
         rstASeenAtB     <= douA2B( 0 );
         l := 1;
         h := l + epRamWrPtrOut'length;
         epRamWrPtrOut   <= unsigned( douA2B(h - 1 downto l) );
         l := h;
         h := l + epRamRdPtrInp'length;
         epRamRdPtrInp   <= unsigned( douA2B(h - 1 downto l) );
         l := h;
         h := l + epMaxNTBSizeInp'length;
         epMaxNTBSizeInp <= unsigned( douA2B(h - 1 downto l) );

         rstARtn         <= douB2A( 0 );
         l := 1;
         h := l + usb2RamRdPtrOut'length;
         usb2RamRdPtrOut <= unsigned( douB2A(h - 1 downto l) );
         l := h;
         h := l + usb2RamWrPtrInp'length;
         usb2RamWrPtrInp <= unsigned( douB2A(h - 1 downto l) );
      end process P_ASSIGN;

      P_RESET : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( usb2EpRst = '1' ) then
               resettingA <= '1';
            elsif ( rstARtn = '1' ) then
               -- reset has done one round-trip
               resettingA <= '0';
            end if;
         end if;
      end process P_RESET;

      epRstLoc     <= rstASeenAtB;
      usb2EpRstLoc <= usb2EpRst or resettingA;

      U_CC_SYNC : entity work.Usb2MboxSync
         generic map (
            STAGES_A2B_G           => 3,
            STAGES_B2A_G           => 3,
            DWIDTH_A2B_G           => dinA2B'length,
            DWIDTH_B2A_G           => dinB2A'length,
            OUTREG_A2B_G           => true,
            OUTREG_B2A_G           => true
         )
         port map (
            clkA                   => usb2Clk,
            cenA                   => open,
            dinA                   => dinA2B,
            douA                   => douB2A,

            clkB                   => epClk,
            dinB                   => dinB2A,
            douB                   => douA2B
         );
   end generate G_ASYNC;

end architecture Impl;
