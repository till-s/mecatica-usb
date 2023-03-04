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

-- notification endpoint used by ECM or NCM

entity Usb2EpCDCEtherNotify is
   generic (
      -- interface number of control interface
      CTL_IFC_NUM_G              : natural;
      -- interface number of control interface
      ASYNC_G                    : boolean   := false;
      CARRIER_DFLT_G             : std_logic := '1';
      -- ECM: must send SPEED CHANGE (6.3.3) *after* ever connection state change
      -- NCM: must send SPEED CHANGE (6.3.3) *prior to* ever connection state change
      SEND_CARRIER_FIRST_G       : boolean   := true;
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

      -- note that this is in the USB2 clock domain; if you really
      -- need this (and if ASYNC_G) you need to sync from the epClk 
      -- yourself...

      speedInp                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );
      speedOut                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );

      -- *******************************************************
      -- signals below here are in the epClk domain (if ASYNC_G)
      -- *******************************************************

      -- FIFO output clock (may be different from usb2Clk if ASYNC_G is true)
      epClk                      : in  std_logic;
      epRst                      : in  std_logic;

      carrier                    : in  std_logic := CARRIER_DFLT_G
   );

   attribute MARK_DEBUG of usb2NotifyEpOb : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of carrier        : signal is toStr( MARK_DEBUG_G );

end entity Usb2EpCDCEtherNotify;

architecture Impl of Usb2EpCDCEtherNotify is

   constant MAX_MSG_SIZE_C : natural := 8 + 8;

   constant MEND_CONN_C    : natural := 7;
   constant MEND_SPEED_C   : natural := 15;
   constant MSZ_SPEED_C    : Usb2ByteType := Usb2ByteType( to_unsigned( 8, Usb2ByteType'length ) );

   constant IFC_NUM_C      : Usb2ByteType := Usb2ByteType( toUsb2InterfaceNumType( CTL_IFC_NUM_G ) );

   constant REQ_TYP_C      : Usb2ByteType := USB2_MAKE_REQ_TYP_F(
                                                true,
                                                USB2_REQ_TYP_TYPE_CLASS_C,
                                                USB2_REQ_TYP_RECIPIENT_IFC_C
                                             );

   function xtract(constant x : unsigned; constant i : in natural) return Usb2ByteType is
   begin
      return Usb2ByteType( x(8*i+7 downto 8*i) );
   end function xtract;

   type StateType is ( INIT, IDLE, SEND, DONE );

   type RegType is record
      state        : StateType;
      carrier      : std_logic;
      speedInp     : unsigned(31 downto 0);
      speedOut     : unsigned(31 downto 0);
      msgCarrier   : boolean;
      sendBoth     : boolean;
      idx          : natural range 0 to MAX_MSG_SIZE_C - 1;
   end record RegType;

   constant REG_INIT_C    : RegType := (
      state        => INIT,
      carrier      => CARRIER_DFLT_G,
      speedInp     => to_unsigned(100000000, 32),
      speedOut     => to_unsigned(100000000, 32),
      msgCarrier   => SEND_CARRIER_FIRST_G,
      sendBoth     => true,
      idx          => 0
   );

   signal r               : RegType   := REG_INIT_C;
   signal rin             : RegType;

   signal cen             : std_logic := '0';

   signal carrierLoc      : std_logic;

   attribute MARK_DEBUG   of r : signal is toStr( MARK_DEBUG_G );

begin

   G_ASYNC : if ( ASYNC_G ) generate
      U_SYNC : entity work.Usb2CCSync
         generic map (
            INIT_G => CARRIER_DFLT_G
         )
         port map (
            clk    => usb2Clk,
            d      => carrier,
            q      => carrierLoc
         );
   end generate G_ASYNC;

   G_SYNC : if ( not ASYNC_G ) generate
      carrierLoc <= carrier;
   end generate G_SYNC;

   P_COMB_NOTE : process (r, carrierLoc, speedInp, speedOut, usb2NotifyEpIb ) is
      variable v : RegType;
   begin

      v               := r;
      usb2NotifyEpOb  <= USB2_ENDP_PAIR_IB_INIT_C;

      case ( r.state ) is
         when INIT =>
            v.state       := SEND; -- after reset always notify
            v.carrier     := carrierLoc;
            v.speedInp    := speedInp;
            v.speedOut    := speedOut;
            v.msgCarrier  := SEND_CARRIER_FIRST_G;
            v.sendBoth    := true;

         when IDLE =>
            if ( carrierLoc /= r.carrier ) then
               v.carrier    := carrierLoc;
               -- ECM (=SEND_CARRIER_FIRST_G says we should follow every
               -- carrier change by a speed message; NCM only requires
               -- carrier to be preceded by speed if connection is established).
               v.sendBoth   := ((carrierLoc = '1') or SEND_CARRIER_FIRST_G);
               v.msgCarrier := not v.sendBoth or SEND_CARRIER_FIRST_G;
               v.state      := SEND;
            elsif ( ( speedInp /= r.speedInp ) or ( speedOut /= r.speedOut ) ) then
               v.speedInp   := speedInp;
               v.speedOut   := speedOut;
               v.msgCarrier := false;
               v.sendBoth   := false;
               v.state      := SEND;
            end if;

         when SEND =>
            usb2NotifyEpOb.mstInp.don <= '0';
            usb2NotifyEpOb.mstInp.vld <= '1';
            usb2NotifyEpOb.mstInp.dat <= (others => '0');

            if ( usb2NotifyEpIb.subinp.rdy = '1' ) then
               if ( (r.msgCarrier and (r.idx = MEND_CONN_C) ) or (r.idx = MEND_SPEED_C) ) then
                  v.state := DONE;
               else
                  v.idx := r.idx + 1;
               end if;
            end if;

            case ( r.idx ) is
               when  0 => usb2NotifyEpOb.mstInp.dat <= REQ_TYP_C;
               when  1 => if ( r.msgCarrier ) then
                            usb2NotifyEpOb.mstInp.dat <= Usb2ByteType( USB2_NOT_CLS_CDC_NETWORK_CONNECTION_C );
                         else
                            usb2NotifyEpOb.mstInp.dat <= Usb2ByteType( USB2_NOT_CLS_CDC_SPEED_CHANGE_C );
                         end if;
               when  2 => if ( r.msgCarrier ) then
                            usb2NotifyEpOb.mstInp.dat(0) <= r.carrier;
                         else
                            -- covered by default
                         end if;
               -- when 3 => covered by others
               when  4 => usb2NotifyEpOb.mstInp.dat <= IFC_NUM_C;
               -- when 5 => covered by others
               when  6 => if ( not r.msgCarrier ) then
                            usb2NotifyEpOb.mstInp.dat <= MSZ_SPEED_C;
                         else
                            -- covered by default
                         end if;
               -- when 7 => covered by others
               when  8 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedInp, 0 );
               when  9 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedInp, 1 );
               when 10 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedInp, 2 );
               when 11 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedInp, 3 );
               when 12 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedOut, 0 );
               when 13 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedOut, 1 );
               when 14 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedOut, 2 );
               when 15 => usb2NotifyEpOb.mstInp.dat <= xtract( r.speedOut, 3 );
               when others =>  null;
            end case;

         when DONE =>
            v.idx := 0;
            usb2NotifyEpOb.mstInp.don <= '1';
            usb2NotifyEpOb.mstInp.vld <= '0';
            if ( usb2NotifyEpIb.subinp.rdy = '1' ) then
               -- ECM: must send SPEED CHANGE (6.3.3) *after* ever connection state change
               -- NCM: must send SPEED CHANGE (6.3.3) *prior to* ever connection state change
               if ( r.sendBoth and (r.msgCarrier = SEND_CARRIER_FIRST_G) ) then
                  v.msgCarrier := not r.msgCarrier;
                  v.state      := SEND;
               else
                  v.state      := IDLE;
               end if;
            end if;
      end case;
      rin <= v;
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
