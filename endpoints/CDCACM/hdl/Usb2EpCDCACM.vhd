-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- CDC ACM Endpoint with a FIFO interface. It also demonstrates
-- the implementation of a control interface via device requests (EP0).
-- Asynchronous clock domains are supported.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

entity Usb2EpCDCACM is
   generic (
      -- interface number of control interface
      CTL_IFC_NUM_G              : natural;
      -- enable line-break support
      ENBL_LINE_BREAK_G          : boolean := true;
      -- enable support for get/set line state + coding
      -- if this is enabled then you *must* connect
      -- usb2Ep0ObExt/usb2Ep0IbExt as well as usb2NotifyEpIb/usb2NotifyEpOb!
      ENBL_LINE_STATE_G          : boolean := false;
      ASYNC_G                    : boolean := false;
      -- FIFO parameters (ld_fifo_depth are the width of the internal
      -- address pointers, i.e., ceil( log2( depth - 1 ) )
      LD_FIFO_DEPTH_INP_G        : natural;
      -- for max. throughput the OUT fifo must be big enough
      -- to hold at least two maximally sized packets.
      LD_FIFO_DEPTH_OUT_G        : natural;
      -- add an output register to the OUT FIFO (to help timing)
      FIFO_OUT_REG_OUT_G         : boolean  := false;
      -- width of the IN fifo timer (counts in 60MHz cycles)
      FIFO_TIMER_WIDTH_G         : positive := 1
   );
   port (
      usb2Clk                    : in  std_logic;
      usb2Rst                    : in  std_logic;

      -- ********************************************
      -- signals below here are in the usb2Clk domain
      -- ********************************************

      -- ULPI RX interface
      usb2Rx                     : in  Usb2RxType;

      -- EP0 interface
      usb2Ep0ReqParam            : in  Usb2CtlReqParamType := USB2_CTL_REQ_PARAM_INIT_C;
      usb2Ep0CtlExt              : out Usb2CtlExtType      := USB2_CTL_EXT_NAK_C;
      usb2Ep0ObExt               : out Usb2EndpPairIbType;
      usb2Ep0IbExt               : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;

      -- Data interface bulk endpoint pair
      usb2DataEpIb               : in  Usb2EndpPairObType;
      usb2DataEpOb               : out Usb2EndpPairIbType;
      -- Notification interface bulk endpoint pair
      usb2NotifyEpIb             : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2NotifyEpOb             : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

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

      -- Control signals (if ENBL_LINE_STATE_G).
      -- These signals are in the usb2 clock domain; if you need them
      -- you need to synchronize your self (if ASYNC_G)
      rate                       : out unsigned(31 downto 0) := (others => '0');
      stopBits                   : out unsigned( 1 downto 0) := (others => '0');
      parity                     : out unsigned( 2 downto 0) := (others => '0');
      dataBits                   : out unsigned( 4 downto 0) := (others => '0');

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
      fifoWenaInp                : in  std_logic;
      fifoFullInp                : out std_logic;
      -- (approximate) fill level. The deassertion of fifoFullInp and the value of
      -- fifoFilledInp are delayed by several cycles of the slower clock if ASYNC_G.
      fifoFilledInp              : out unsigned(LD_FIFO_DEPTH_INP_G downto 0);

      fifoDataOut                : out Usb2ByteType;
      -- read-enable; data are *not* read while fifoEmptyOut is asserted.
      -- I.e., it is safe to hold fifoRenaOut steady until fifoEmptyOut
      -- is deasserted.
      fifoRenaOut                : in  std_logic;
      fifoEmptyOut               : out std_logic;
      -- (approximate) fill level. The deassertion of fifoEmptyOut and the value of
      -- fifoFilledOut are delayed by several cycles of the slower clock if ASYNC_G.
      fifoFilledOut              : out unsigned(LD_FIFO_DEPTH_OUT_G downto 0);

      -- Control signals
      -- Line break (if ENBL_LINE_BREAK_G) -- this must match
      -- the functional descriptor's bmCapabilities(2)
      lineBreak                  : out std_logic := '0';
      -- Line state (if ENBL_LINE_STATE_G) -- this must match
      -- the functional descriptor's bmCapabilities(1)
      DTR                        : out std_logic := '0';
      RTS                        : out std_logic := '0';

      overRun                    : in  std_logic := '0';
      parityError                : in  std_logic := '0';
      framingError               : in  std_logic := '0';
      ringDetected               : in  std_logic := '0';
      breakState                 : in  std_logic := '0';
      txCarrier                  : in  std_logic := '0';
      rxCarrier                  : in  std_logic := '0'
   );
end entity Usb2EpCDCACM;

architecture Impl of Usb2EpCDCACM is
begin

   G_LINE_BREAK : if ( ENBL_LINE_BREAK_G or ENBL_LINE_STATE_G ) generate
   begin
      U_BRK : entity work.Usb2EpCDCACMCtl
         generic map (
            ASYNC_G                     => ASYNC_G,
            SUPPORT_LINE_G              => ENBL_LINE_STATE_G,
            SUPPORT_BREAK_G             => ENBL_LINE_BREAK_G
         )
         port map (
            usb2Clk                     => usb2Clk,
            usb2Rst                     => usb2Rst,
            usb2SOF                     => usb2Rx.pktHdr.sof,
            usb2Ep0ReqParam             => usb2Ep0ReqParam,
            usb2Ep0CtlExt               => usb2Ep0CtlExt,
            usb2Ep0ObExt                => usb2Ep0ObExt,
            usb2Ep0IbExt                => usb2Ep0IbExt,
            rate                        => rate,
            stopBits                    => stopBits,
            parity                      => parity,
            dataBits                    => dataBits,

            epClk                       => epClk,
            lineBreak                   => lineBreak,
            DTR                         => DTR,
            RTS                         => RTS
         );
   end generate G_LINE_BREAK;

   G_NOTIFY : if ( ENBL_LINE_STATE_G ) generate
      U_NOTIFY : entity work.Usb2EpCDCACMNotify
         generic map (
            CTL_IFC_NUM_G               => CTL_IFC_NUM_G,
            ASYNC_G                     => ASYNC_G
         )
         port map (
            usb2Clk                     => usb2Clk,
            usb2Rst                     => usb2Rst,

            usb2NotifyEpIb              => usb2NotifyEpIb,
            usb2NotifyEpOb              => usb2NotifyEpOb,

            epClk                       => epClk,

            overRun                     => overRun,
            parityError                 => parityError,
            framingError                => framingError,
            ringDetected                => ringDetected,
            breakState                  => breakState,
            txCarrier                   => txCarrier,
            rxCarrier                   => rxCarrier
         );
   end generate G_NOTIFY;

   U_FIFO : entity work.Usb2FifoEp
         generic map (
            LD_FIFO_DEPTH_INP_G         => LD_FIFO_DEPTH_INP_G,
            LD_FIFO_DEPTH_OUT_G         => LD_FIFO_DEPTH_OUT_G,
            TIMER_WIDTH_G               => FIFO_TIMER_WIDTH_G,
            OUT_REG_OUT_G               => FIFO_OUT_REG_OUT_G,
            ASYNC_G                     => ASYNC_G
         )
         port map (
            usb2Clk                     => usb2Clk,
            usb2Rst                     => usb2Rst,

            usb2EpIb                    => usb2DataEpIb,
            usb2EpOb                    => usb2DataEpOb,

            minFillInp                  => fifoMinFillInp,
            timeFillInp                 => fifoTimeFillInp,
            
            epClk                       => epClk,
            epRstOut                    => epRstOut,

            datInp                      => fifoDataInp,
            wenInp                      => fifoWenaInp,
            filledInp                   => fifoFilledInp,
            fullInp                     => fifoFullInp,

            datOut                      => fifoDataOut,
            renOut                      => fifoRenaOut,
            filledOut                   => fifoFilledOut,
            emptyOut                    => fifoEmptyOut
         );
end architecture Impl;
