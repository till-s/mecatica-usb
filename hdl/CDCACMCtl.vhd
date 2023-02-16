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

entity CDCACMCtl is
   generic (
      CDC_IFC_NUM_G   : Usb2InterfaceNumType;
      -- whether to enable support for set/get line coding, set line-state
      -- if this is enabled then usb2Ep0ObExt/usb2EpIbExt must be connected!
      SUPPORT_LINE_G  : boolean := false;
      -- whether to enable support for send break
      SUPPORT_BREAK_G : boolean := true
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';
      
      usb2SOF         : in  boolean;
      usb2Ep0ReqParam : in  Usb2CtlReqParamType;
      usb2Ep0CtlExt   : out Usb2CtlExtType;

      usb2Ep0IbExt    : in  Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;
      usb2Ep0ObExt    : out Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      lineBreak       : out std_logic;
      DTR             : out std_logic := '0';
      RTS             : out std_logic := '0';
      rate            : out unsigned(31 downto 0) := (others => '0');
      stopBits        : out unsigned( 1 downto 0) := (others => '0');
      parity          : out unsigned( 2 downto 0) := (others => '0');
      dataBits        : out unsigned( 4 downto 0) := (others => '0')
   );
end entity CDCACMCtl;

architecture Impl of CDCACMCtl is

   type StateType is (IDLE, SEND, RECV, DONE);

   constant LCODING_SZ_C : natural := 7;

   type RegType is record
      state     : stateType;
      timer     : unsigned(16 downto 0);
      ctlExt    : Usb2CtlExtType;
      indef     : boolean;
      DTR       : std_logic;
      RTS       : std_logic;
      buf       : Usb2ByteArray(0 to LCODING_SZ_C - 1);
      idx       : unsigned(3 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => IDLE,
      timer    => (others => '0'),
      ctlExt   => USB2_CTL_EXT_INIT_C,
      indef    => false,
      DTR      => '0',
      RTS      => '0',
      buf      => (others => (others => '0')),
      idx      => (others => '1')
   );

   signal r    : RegType := REG_INIT_C;
   signal rin  : RegType;

   signal ob   : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

   function accept(constant x: Usb2CtlReqParamType)
   return boolean is
   begin
      if ( x.reqType /= USB2_REQ_TYP_TYPE_CLASS_C or not usb2CtlReqDstInterface( x, CDC_IFC_NUM_G ) ) then
         return false;
      end if;
      return true;
   end function accept;

begin

   P_COMB : process ( r, usb2Ep0ReqParam, usb2Ep0IbExt, usb2SOF ) is
      variable v : RegType;
   begin
      v := r;

      -- reset flags
      v.ctlExt.ack     := '0';
      v.ctlExt.err     := '0';
      v.ctlExt.don     := '0';
      ob               <= USB2_ENDP_PAIR_IB_INIT_C;
      if ( r.idx(r.idx'left) = '1' ) then
         ob.mstInp.dat    <= (others => 'X');
      else
         ob.mstInp.dat    <= r.buf( to_integer( r.idx(2 downto 0) ) );
      end if;

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
                  case ( usb2Ep0ReqParam.request ) is
                     when USB2_REQ_CLS_CDC_SEND_BREAK_C =>
                        if ( SUPPORT_BREAK_G and not usb2Ep0ReqParam.dev2Host ) then
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
                     when USB2_REQ_CLS_CDC_SET_CONTROL_LINE_STATE_C =>
                        if ( SUPPORT_LINE_G and not usb2Ep0ReqParam.dev2Host ) then
                           v.ctlExt.err         := '0';
                           v.DTR                := usb2Ep0ReqParam.value(0);
                           v.RTS                := usb2Ep0ReqParam.value(1);
                        end if;
                     when USB2_REQ_CLS_CDC_SET_LINE_CODING_C =>
                        if ( SUPPORT_LINE_G and not usb2Ep0ReqParam.dev2Host ) then
                           v.ctlExt.err := '0';
                           v.ctlExt.don := '0';
                           v.idx        := to_unsigned( LCODING_SZ_C - 1, v.idx'length );
                           v.state      := RECV;
                        end if;
                     when USB2_REQ_CLS_CDC_GET_LINE_CODING_C =>
                        if ( SUPPORT_LINE_G and     usb2Ep0ReqParam.dev2Host ) then
                           v.ctlExt.err := '0';
                           v.ctlExt.don := '0';
                           v.idx        := to_unsigned( LCODING_SZ_C - 1, v.idx'length );
                           v.state      := SEND;
                        end if;
                     when others =>
                  end case;
               end if;
            end if;

         when SEND =>
            ob.mstInp.vld <= not r.idx( r.idx'left );
            ob.mstInp.don <=     r.idx( r.idx'left );
            if ( usb2Ep0IbExt.subInp.rdy = '1' ) then
               if ( r.idx( r.idx'left ) = '0' ) then
                  v.idx := r.idx - 1;
               else
                  -- done
                  v.ctlExt.ack := '1';
                  v.ctlExt.don := '1';
                  v.state      := DONE;
               end if;
            end if;

         when RECV =>
            ob.subOut.rdy <= '1';
            if ( usb2Ep0IbExt.mstOut.vld = '1' ) then
               if ( r.idx( r.idx'left ) = '0' ) then
                  v.buf( to_integer( r.idx(2 downto 0) ) ) := usb2Ep0IbExt.mstOut.dat;
                  v.idx                                    := r.idx - 1;
               end if;
            end if;
            if ( usb2Ep0IbExt.mstOut.don = '1' ) then
               v.ctlExt.ack := '1';
               v.ctlExt.don := '1';
               v.state      := DONE;
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

   G_BREAK_SUP : if ( SUPPORT_BREAK_G ) generate
      lineBreak     <= r.timer(r.timer'left);
   end generate G_BREAK_SUP;

   G_LINE_SUP : if ( SUPPORT_LINE_G ) generate
      function toUnsigned(constant x : Usb2ByteArray) return unsigned is
         variable v : unsigned(8*x'length - 1 downto 0) := (others => '0');
      begin
         for i in x'range loop
            v := resize( v & unsigned(x(i)), v'length );
         end loop;
         return v;
      end function;
   begin
      DTR           <= r.DTR;
      RTS           <= r.RTS;
      rate          <= toUnsigned( r.buf(3 to 6) );
      stopBits      <= unsigned( r.buf(2)(stopBits'range) );
      parity        <= unsigned( r.buf(1)(parity'range)   );
      dataBits      <= unsigned( r.buf(0)(dataBits'range) );
      usb2Ep0ObExt  <= ob;
   end generate G_LINE_SUP;

end architecture Impl;
