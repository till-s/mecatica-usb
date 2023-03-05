-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- CDC ECM Endpoint with a FIFO interface. It also demonstrates
-- the implementation of a control interface via device requests (EP0).
-- Asynchronous clock domains are supported.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

entity Usb2EpCDCECM is
   generic (
      -- interface number of control interface
      CTL_IFC_NUM_G              : natural;
      ASYNC_G                    : boolean   := false;
      -- FIFO parameters (ld_fifo_depth are the width of the internal
      -- address pointers, i.e., ceil( log2( depth - 1 ) )
      LD_FIFO_DEPTH_INP_G        : natural;
      -- for max. throughput the OUT fifo must be big enough
      -- to hold at least two maximally sized packets.
      LD_FIFO_DEPTH_OUT_G        : natural;
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
      fifoMinFillInp             : in  unsigned(LD_FIFO_DEPTH_INP_G - 1 downto 0) := (others => '0');
      -- if more then 'timeFillInp' clock cycles expire since the last
      -- item was written to the IN fifo the contents are passed to USB (even
      -- if 'minFillInp' has not been reached). Similary to termios'
      -- VMIN+VTIME.
      --  - All-ones waits indefinitely.
      --  - Time may be reduced while the timer is running.
      fifoTimeFillInp            : in  unsigned(FIFO_TIMER_WIDTH_G - 1 downto 0)  := (others => '0');

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
      fifoDonInp                 : in  std_logic;
      fifoWenaInp                : in  std_logic;
      fifoFullInp                : out std_logic;
      -- (approximate) fill level. The deassertion of fifoFullInp and the value of
      -- fifoFilledInp are delayed by several cycles of the slower clock if ASYNC_G.
      fifoFilledInp              : out unsigned(LD_FIFO_DEPTH_INP_G downto 0);

      fifoDataOut                : out Usb2ByteType;
      -- read-enable; data are *not* read while fifoEmptyOut is asserted.
      -- I.e., it is safe to hold fifoRenaOut steady until fifoEmptyOut
      -- is deasserted.
      fifoDonOut                 : out std_logic;
      fifoRenaOut                : in  std_logic;
      fifoEmptyOut               : out std_logic;
      -- (approximate) fill level. The deassertion of fifoEmptyOut and the value of
      -- fifoFilledOut are delayed by several cycles of the slower clock if ASYNC_G.
      fifoFilledOut              : out unsigned(LD_FIFO_DEPTH_OUT_G downto 0);
      fifoFramesOut              : out unsigned(LD_FIFO_DEPTH_OUT_G downto 0);

      carrier                    : in  std_logic := CARRIER_DFLT_G
   );

   attribute MARK_DEBUG of packetFilter   : signal is toStr( MARK_DEBUG_G );

end entity Usb2EpCDCECM;

architecture Impl of Usb2EpCDCECM is

   constant IFC_NUM_C      : Usb2ByteType := Usb2ByteType( toUsb2InterfaceNumType( CTL_IFC_NUM_G ) );

   signal cen             : std_logic := '0';
   signal usb2EpRst       : std_logic;

   signal epRstLoc        : std_logic;

begin

   epRstOut  <= epRstLoc;

   usb2EpRst <= usb2Rst or not epInpRunning( usb2DataEpIb ) or not epOutRunning( usb2DataEpIb );

   P_COMB_CTL  : process ( usb2Ep0ReqParam ) is
   begin

      usb2Ep0CtlExt <= USB2_CTL_EXT_NAK_C;
      cen           <= '0';

      if (     usb2Ep0ReqParam.vld = '1'
           and not usb2Ep0ReqParam.dev2Host
           and usb2Ep0ReqParam.reqType = USB2_REQ_TYP_TYPE_CLASS_C
           and usb2CtlReqDstInterface( usb2Ep0ReqParam, CTL_IFC_NUM_G )
           and usb2Ep0ReqParam.request = USB2_REQ_CLS_CDC_SET_ETHERNET_PACKET_FILTER_C
         ) then
         usb2Ep0CtlExt.ack <= '1';
         usb2Ep0CtlExt.err <= '0';
         usb2Ep0CtlExt.don <= '1';
         cen               <= '1';
      end if;
   end process P_COMB_CTL;

   P_SEQ_CTL : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( usb2Rst = '1' ) then
            packetFilter <= (others => '0');
         elsif ( cen = '1' ) then
            packetFilter <= usb2Ep0ReqParam.value( packetFilter'range );
         end if;
      end if;
   end process P_SEQ_CTL;

   U_NOTIFY : entity work.Usb2EpCDCEtherNotify
      generic map (
         CTL_IFC_NUM_G               => CTL_IFC_NUM_G,
         ASYNC_G                     => ASYNC_G,
         CARRIER_DFLT_G              => CARRIER_DFLT_G,
         SEND_CARRIER_FIRST_G        => true,
         MARK_DEBUG_G                => MARK_DEBUG_G
      )
      port map (
         usb2Clk                     => usb2Clk,
         usb2Rst                     => usb2Rst,

         usb2NotifyEpIb              => usb2NotifyEpIb,
         usb2NotifyEpOb              => usb2NotifyEpOb,

         speedInp                    => speedInp,
         speedOut                    => speedOut,

         epClk                       => epClk,
         epRst                       => epRstLoc,

         carrier                     => carrier
      );

   U_FIFO   : entity work.Usb2FifoEp
      generic map (
         LD_FIFO_DEPTH_INP_G         => LD_FIFO_DEPTH_INP_G,
         LD_FIFO_DEPTH_OUT_G         => LD_FIFO_DEPTH_OUT_G,
         TIMER_WIDTH_G               => FIFO_TIMER_WIDTH_G,
         OUT_REG_OUT_G               => FIFO_OUT_REG_OUT_G,
         ASYNC_G                     => ASYNC_G,
         LD_MAX_FRAMES_INP_G         => LD_FIFO_DEPTH_INP_G,
         LD_MAX_FRAMES_OUT_G         => LD_FIFO_DEPTH_OUT_G
      )
      port map (
         usb2Clk                     => usb2Clk,
         usb2Rst                     => usb2EpRst,
         usb2RstOut                  => open,

         usb2EpIb                    => usb2DataEpIb,
         usb2EpOb                    => usb2DataEpOb,

         minFillInp                  => fifoMinFillInp,
         timeFillInp                 => fifoTimeFillInp,
         
         epClk                       => epClk,
         epRstOut                    => epRstLoc,

         datInp                      => fifoDataInp,
         donInp                      => fifoDonInp,
         wenInp                      => fifoWenaInp,
         filledInp                   => fifoFilledInp,
         fullInp                     => fifoFullInp,

         datOut                      => fifoDataOut,
         donOut                      => fifoDonOut,
         renOut                      => fifoRenaOut,
         filledOut                   => fifoFilledOut,
         framesOut                   => fifoFramesOut,
         emptyOut                    => fifoEmptyOut
      );
end architecture Impl;
