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

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

entity Usb2EpCDCACMNotify is
   generic (
      CTL_IFC_NUM_G              : natural;
      ASYNC_G                    : boolean   := false;
      MARK_DEBUG_G               : boolean   := false
   );
   port (
      usb2Clk                    : in  std_logic;
      usb2Rst                    : in  std_logic;

      -- ********************************************
      -- signals below here are in the usb2Clk domain
      -- ********************************************

      -- Notification (interrupt) endpoint pair
      usb2NotifyEpIb             : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2NotifyEpOb             : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

      -- *******************************************************
      -- signals below here are in the epClk domain (if ASYNC_G)
      -- *******************************************************

      -- endpoint clock
      epClk                      : in  std_logic := '0';

      overRun                    : in  std_logic := '0';
      parityError                : in  std_logic := '0';
      framingError               : in  std_logic := '0';
      ringDetected               : in  std_logic := '0';
      breakState                 : in  std_logic := '0';
      txCarrier                  : in  std_logic := '0';
      rxCarrier                  : in  std_logic := '0'
   );

   attribute MARK_DEBUG of usb2NotifyEpOb : signal is toStr( MARK_DEBUG_G );

end entity Usb2EpCDCACMNotify;

architecture Impl of Usb2EpCDCACMNotify is

   constant MAX_MSG_SIZE_C : natural                      := 8 + 2;
   constant MEND_MSG_C     : natural                      := MAX_MSG_SIZE_C - 1;
   constant MSZ_C          : std_logic_vector(7 downto 0) := x"02";

   constant REQ_TYP_C      : Usb2ByteType := usb2MakeRequestType(
                                                true,
                                                USB2_REQ_TYP_TYPE_CLASS_C,
                                                USB2_REQ_TYP_RECIPIENT_IFC_C
                                             );

   constant IFC_NUM_C      : Usb2ByteType := Usb2ByteType( toUsb2InterfaceNumType( CTL_IFC_NUM_G ) );

   signal din             : std_logic_vector(6 downto 0) := (others => '0');
   signal dou             : std_logic_vector(din'range);


   type StateType is ( IDLE, SEND, DONE );

   type RegType is record
      state        : StateType;
      idx          : natural range 0 to MAX_MSG_SIZE_C - 1;
      dat          : std_logic_vector(din'range);
      edge         : std_logic_vector(din'range);
      ldat         : std_logic_vector(din'range);
   end record RegType;

   constant REG_INIT_C    : RegType := (
      state        => IDLE,
      idx          => 0,
      dat          => (others => '0'),
      edge         => (others => '0'),
      ldat         => (others => '0')
   );

   signal r               : RegType   := REG_INIT_C;
   signal rin             : RegType;

   attribute MARK_DEBUG   of r   : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG   of dou : signal is toStr( MARK_DEBUG_G );

   constant DIFF_MSK_C    : std_logic_vector(din'range) := (0 => '1', 1 => '1', others => '0');
   constant ALL_ZERO_C    : std_logic_vector(din'range) := (others => '0');

begin

   din(6) <= overRun;
   din(5) <= parityError;
   din(4) <= framingError;
   din(3) <= ringDetected;
   din(2) <= breakState;
   din(1) <= txCarrier;
   din(0) <= rxCarrier;

   G_ASYNC : if ( ASYNC_G ) generate
      G_CC_SYNC : for i in din'range generate
         U_SYNC : entity work.Usb2CCSync
            generic map (
               INIT_G => '0'
            )
            port map (
               clk    => usb2Clk,
               d      => din(i),
               q      => dou(i)
            );
      end generate G_CC_SYNC;
   end generate G_ASYNC;

   G_SYNC : if ( not ASYNC_G ) generate
      dou <= din;
   end generate G_SYNC;

   P_COMB_NOTE : process (r, dou, usb2NotifyEpIb ) is
      variable v : RegType;
   begin

      v               := r;
      usb2NotifyEpOb  <= USB2_ENDP_PAIR_IB_INIT_C;

      v.ldat          := dou;

      -- detect raising edge in the 'transient' signals and latch in 'edge'
      v.edge := r.edge or (dou and not r.ldat and not DIFF_MSK_C);

      case ( r.state ) is
         when IDLE =>
            v.ldat := dou;
            -- raising edge on the 'transient' signals, diff on the consistent signals triggers
            -- notification; use 'v.edge' in order not to lose an edge that was just detected
            -- during this cycle.
            if ( ( (v.edge and not DIFF_MSK_C) or ( (r.dat xor dou) and DIFF_MSK_C ) ) /= ALL_ZERO_C ) then
               v.dat    := (v.edge and not DIFF_MSK_C) or (dou and DIFF_MSK_C);
               v.edge   := (others => '0');
               v.state  := SEND;
            end if;

         when SEND =>
            usb2NotifyEpOb.mstInp.don <= '0';
            usb2NotifyEpOb.mstInp.vld <= '1';
            usb2NotifyEpOb.mstInp.dat <= (others => '0');

            if ( usb2NotifyEpIb.subinp.rdy = '1' ) then
               if ( r.idx = MEND_MSG_C ) then
                  v.state := DONE;
               else
                  v.idx   := r.idx + 1;
               end if;
            end if;

            case ( r.idx ) is
               when  0 => usb2NotifyEpOb.mstInp.dat <= REQ_TYP_C;
               when  1 => usb2NotifyEpOb.mstInp.dat <= Usb2ByteType( USB2_NOT_CLS_CDC_SERIAL_STATE_C );
               -- when 2 => covered by others
               -- when 3 => covered by others
               when  4 => usb2NotifyEpOb.mstInp.dat <= IFC_NUM_C;
               -- when 5 => covered by others
               when  6 => usb2NotifyEpOb.mstInp.dat <= MSZ_C;
               -- when 7 => covered by others
               when  8 => usb2NotifyEpOb.mstInp.dat              <= (others => '0');
                          usb2NotifyEpOb.mstInp.dat(r.dat'range) <= r.dat;
               -- when 9 => covered by others
               when others =>  null;
            end case;

         when DONE =>
            v.idx := 0;
                          v.dat := r.dat and DIFF_MSK_C;
            usb2NotifyEpOb.mstInp.don <= '1';
            usb2NotifyEpOb.mstInp.vld <= '0';
            if ( usb2NotifyEpIb.subinp.rdy = '1' ) then
               v.state      := IDLE;
            end if;
      end case;

      rin    <= v;
   end process P_COMB_NOTE;

   P_SEQ_NOTE : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( ( usb2Rst or not epInpRunning( usb2NotifyEpIb ) ) = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ_NOTE;

end architecture Impl;
