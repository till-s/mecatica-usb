-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

-- Example for how to extend EP0 functionality.
-- This module implements 'send-break' for CDC-ACM.

entity CDCACMSendBreak is
   generic (
      CDC_IFC_NUM_G   : Usb2InterfaceNumType
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';
      
      usb2SOF         : in  boolean;
      usb2Ep0ReqParam : in  Usb2CtlReqParamType;
      usb2Ep0CtlExt   : out Usb2CtlExtType;
      lineBreak       : out std_logic
   );
end entity CDCACMSendBreak;

architecture Impl of CDCACMSendBreak is

   type StateType is (IDLE, DONE);

   type RegType is record
      state     : stateType;
      timer     : unsigned(16 downto 0);
      ctlExt    : Usb2CtlExtType;
      indef     : boolean;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => IDLE,
      timer    => (others => '0'),
      ctlExt   => USB2_CTL_EXT_INIT_C,
      indef    => false
   );

   signal r    : RegType := REG_INIT_C;
   signal rin  : RegType;

   function accept(constant x: Usb2CtlReqParamType)
   return boolean is
   begin
      if ( x.dev2Host or x.reqType /= USB2_REQ_TYP_TYPE_CLASS_C or not usb2CtlReqDstInterface( x, CDC_IFC_NUM_G ) ) then
         return false;
      end if;
      return x.request = USB2_REQ_CLS_CDC_SEND_BREAK_C;
   end function accept;

begin

   P_COMB : process ( r, usb2Ep0ReqParam, usb2SOF ) is
      variable v : RegType;
   begin
      v := r;

      -- reset flags
      v.ctlExt.ack := '0';
      v.ctlExt.err := '0';
      v.ctlExt.don := '0';

      if ( usb2SOF and ( r.timer(r.timer'left) = '1' ) and not r.indef ) then
         v.timer := r.timer - 1;
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( usb2Ep0ReqParam.vld = '1' ) then
               v.ctlExt.ack := '1';
               v.ctlExt.err := '1';
               v.ctlExt.don := '1';
               v.state      := DONE;
               if ( accept(usb2Ep0ReqParam) ) then
                  v.ctlExt.err         := '0';
                  v.timer(15 downto 0) := unsigned(usb2Ep0ReqParam.value);
                  v.timer(16)          := '1';
                  if    ( usb2Ep0ReqParam.value = x"0000" ) then
                     v.indef     := false;
                     v.timer(16) := '0';
                  elsif ( usb2Ep0ReqParam.value = x"ffff" ) then
                     v.indef     := true;
                  end if;
               end if;
            end if;

         when DONE => -- flags are asserted during this cycle
            v.state := IDLE;
      end case;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   usb2Ep0CtlExt <= r.ctlExt;
   lineBreak     <= r.timer(r.timer'left);

end architecture Impl;
