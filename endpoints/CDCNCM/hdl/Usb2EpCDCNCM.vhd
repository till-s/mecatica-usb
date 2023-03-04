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
      -- FIFO parameters (ld_fifo_depth are the width of the internal
      -- address pointers, i.e., ceil( log2( depth - 1 ) )
      LD_RAM_DEPTH_INP_G         : natural;
      -- for max. throughput the OUT fifo must be big enough
      -- to hold at least two maximally sized packets.
      LD_RAM_DEPTH_OUT_G         : natural;
      -- add an output register to the OUT FIFO (to help timing)
      FIFO_OUT_REG_OUT_G         : boolean   := false;
      -- width of the IN fifo timer (counts in 60MHz cycles)
      FIFO_TIMER_WIDTH_G         : positive  := 1;
      CARRIER_DFLT_G             : std_logic := '1';
      MARK_DEBUG_G               : boolean   := false
   );
   port (
      usb2Clk                    : in  std_logic;
      usb2Rst                    : in  std_logic;

      -- ********************************************
      -- signals below here are in the usb2Clk domain
      -- ********************************************

      -- EP0 interface
      usb2Ep0ReqParam            : in  Usb2CtlReqParamType := USB2_CTL_REQ_PARAM_INIT_C;
      usb2Ep0CtlExt              : out Usb2CtlExtType      := USB2_CTL_EXT_NAK_C;

      -- Data interface bulk endpoint pair
      usb2DataEpIb               : in  Usb2EndpPairObType;
      usb2DataEpOb               : out Usb2EndpPairIbType;

      -- Notification (interrupt) endpoint pair
      usb2NotifyEpIb             : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2NotifyEpOb             : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

      -- note that this is in the USB2 clock domain; if you really
      -- need this (and if ASYNC_G) you need to sync from the epClk 
      -- yourself...
      packetFilter               : out std_logic_vector(4 downto 0);

      speedInp                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );
      speedOut                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );

      -- FIFO control (in usb2Clk domain!)
      --
      -- number of slots in the IN direction that need to be accumulated
      -- before USB is notified (improves throughput at the expense of latency)
      fifoMinFillInp             : in  unsigned(LD_RAM_DEPTH_INP_G - 2 downto 0) := (others => '0');
      -- if more then 'timeFillInp' clock cycles expire since the last
      -- item was written to the IN fifo the contents are passed to USB (even
      -- if 'minFillInp' has not been reached). Similary to termios'
      -- VMIN+VTIME.
      --  - All-ones waits indefinitely.
      --  - Time may be reduced while the timer is running.
      fifoTimeFillInp            : in  unsigned(FIFO_TIMER_WIDTH_G - 2 downto 0)  := (others => '0');

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
      fifoWenaInp                : in  std_logic;
      fifoFullInp                : out std_logic;
      -- (approximate) fill level. The deassertion of fifoFullInp and the value of
      -- fifoFilledInp are delayed by several cycles of the slower clock if ASYNC_G.
      fifoFilledInp              : out unsigned(LD_RAM_DEPTH_INP_G downto 0);

      fifoDataOut                : out Usb2ByteType;
      fifoLastOut                : out std_logic;
      -- read-enable; data are *not* read while fifoEmptyOut is asserted.
      -- I.e., it is safe to hold fifoRenaOut steady until fifoEmptyOut
      -- is deasserted.
      fifoRenaOut                : in  std_logic;
      fifoEmptyOut               : out std_logic;

      carrier                    : in  std_logic := CARRIER_DFLT_G
   );

   attribute MARK_DEBUG of usb2NotifyEpOb : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of packetFilter   : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of carrier        : signal is toStr( MARK_DEBUG_G );

end entity Usb2EpCDCNCM;

architecture Impl of Usb2EpCDCNCM is

   signal epRstLoc                        : std_logic          := '0';

   signal epOut                           : usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal epInp                           : usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;


   signal usb2RamWrPtrOut                 : unsigned(LD_RAM_DEPTH_OUT_G downto 0);
   signal usb2RamRdPtrOut                 : unsigned(LD_RAM_DEPTH_OUT_G downto 0);
   signal epRamWrPtrOut                   : unsigned(LD_RAM_DEPTH_OUT_G downto 0);
   signal epRamRdPtrOut                   : unsigned(LD_RAM_DEPTH_OUT_G downto 0);

begin

   U_EP_OUT : entity work.Usb2EpCDCNCMOut
      generic map (
         LD_RAM_DEPTH_G => LD_RAM_DEPTH_OUT_G
      )
      port map (
         usb2Clk        => usb2Clk,
         usb2Rst        => usb2Rst,

         usb2EpIb       => usb2DataEpIb,
         usb2EpOb       => epOut,

         ramWrPtrOb     => usb2RamWrPtrOut,
         ramRdPtrIb     => usb2RamRdPtrOut,

         epClk          => epClk,
         epRst          => epRstLoc,

         ramRdPtrOb     => epRamRdPtrOut,
         ramWrPtrIb     => epRamWrPtrOut,

         fifoDataOut    => fifoDataOut,
         fifoLastOut    => fifoLastOut,
         fifoRenaOut    => fifoRenaOut,
         fifoEmptyOut   => fifoEmptyOut
      );

   usb2DataEpOb <= usb2MergeEndpPairIb( epInp, epOut );


   G_SYNC : if ( not ASYNC_G ) generate
      usb2RamRdPtrOut <= epRamRdPtrOut;
      epRamWrPtrOut   <= usb2RamWrPtrOut;
   end generate G_SYNC;


end architecture Impl;
