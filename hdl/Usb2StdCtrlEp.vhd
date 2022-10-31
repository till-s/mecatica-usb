library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

entity Usb2StdCtlEp is
   generic (
      MARK_DEBUG_G    : boolean := true;
      ENDPOINTS_G     : Usb2EndpPairPropertyArray
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';

      -- connection to the packet engine
      epIb            : in  Usb2EndpPairObType;
      epOb            : out Usb2EndpPairIbType;

      param           : out Usb2CtlReqParamType;
      -- an external agent may take over the
      -- data phase and execution of the control
      -- transaction. It must monitor the 'epIb'
      -- stream(s) and store any data needed.
      -- Once the param.vld is asserted '1' the
      -- external agent needs to 'ack' with the 'err' and 'don'
      -- flags clear.
      -- Once the transaction is processed the
      -- external agent asserts 'don' and conveys status
      -- in 'ack' and 'err'.
      ctlExt          : in  Usb2CtlExtType     := USB2_CTL_EXT_INIT_C;
      epExt           : in  Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      devStatus       : out Usb2DevStatusType
   );
end entity Usb2StdCtlEp;

architecture Impl of Usb2StdCtlEp is
   type StateType is (GET_PARAMS, WAIT_CTL_DONE, WAIT_EXT, WAIT_EXT_DONE, STD_REQUEST, STATUS);

   type RegType   is record
      state       : StateType;
      reqParam    : Usb2CtlReqParamType;
      parmIdx     : unsigned(2 downto 0);
      err         : std_logic;
      protoStall  : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => GET_PARAMS,
      reqParam    => USB2_CTL_REQ_PARAM_INIT_C,
      parmIdx     => (others => '0'),
      err         => '0',
      protoStall  => '0'
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;
begin

   P_COMB : process ( r, epIb, ctlExt, epExt ) is
      variable v : RegType;
   begin
      v    := r;
      epOb <= USB2_ENDP_PAIR_IB_INIT_C;

      epOb.stalledInp <= r.protoStall;
      epOb.stalledOut <= r.protoStall;

      case ( r.state ) is
         when GET_PARAMS =>
            v.err        := '0';
            if ( epIb.mstCtl.vld = '1' ) then

               -- new request; clear the stall condition (protocol error)
               v.protoStall := '0';

               case ( r.parmIdx ) is
                  when "000" =>
                     v.reqParam.dev2Host  := USB2_REQ_TYP_DEV2HOST_F ( epIb.mstCtl.dat );
                     v.reqParam.reqType   := USB2_REQ_TYP_TYPE_F     ( epIb.mstCtl.dat );
                     v.reqParam.recipient := USB2_REQ_TYP_RECIPIENT_F( epIb.mstCtl.dat );
                  when "001" =>
                     v.reqParam.request             := unsigned(epIb.mstCtl.dat);
                  when "010" =>
                     v.reqParam.value( 7 downto 0)  := epIb.mstCtl.dat;
                  when "011" =>
                     v.reqParam.value(15 downto 8)  := epIb.mstCtl.dat;
                  when "100" =>
                     v.reqParam.index( 7 downto 0)  := epIb.mstCtl.dat;
                  when "101" =>
                     v.reqParam.index(15 downto 8)  := epIb.mstCtl.dat;
                  when "110" =>
                     v.reqParam.length( 7 downto 0) := unsigned(epIb.mstCtl.dat);
                  when others =>
                     v.reqParam.length(15 downto 8) := unsigned(epIb.mstCtl.dat);
                     v.state               := WAIT_CTL_DONE;
               end case;
               v.parmIdx := r.parmIdx + 1;
            end if;

         when WAIT_CTL_DONE =>
            if ( epIb.mstCtl.don = '1' ) then
               v.reqParam.vld        := '1';
               v.state               := WAIT_EXT;
            end if;

         when WAIT_EXT =>
            if ( ctlExt.ack = '1' ) then
               if ( ctlExt.err = '1' ) then
                  v.state := STD_REQUEST;
               else
                  v.state := WAIT_EXT_DONE;
               end if;
            end if;

         when WAIT_EXT_DONE =>
            epOb <= epExt;
            if ( ctlExt.don = '1' ) then
               v.err   := ctlExt.err;
               v.state := STATUS;
            end if;

         when STD_REQUEST =>
            -- dispatch standard requests

         when STATUS =>

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

end architecture Impl;
