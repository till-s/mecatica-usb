-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Multiplexer to dispatch control requests directed to
-- interfaces or endpoints.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2MuxEpCtlPkg.all;

entity Usb2MuxEpCtl is

   generic (
      AGENTS_G          : Usb2CtlEpAgentConfigArray
   );
   port (
      usb2Clk           : in  std_logic;
      usb2Rst           : in  std_logic;

      -- connection to the Ctl endpoint
      usb2CtlReqParamIb : in  Usb2CtlReqParamType;
      usb2CtlExtOb      : out Usb2CtlExtType;
      usb2CtlEpExtOb    : out Usb2EndpPairIbType;

      -- connections to all the agents
      -- do *NOT* connect any of the agents to usb2CtlReqParamIb !
      -- The mux propagates 'vld' once it went through its arbitration
      usb2CtlReqParamOb : out Usb2CtlReqParamArray( AGENTS_G'range );
      usb2CtlExtIb      : in  Usb2CtlExtArray( AGENTS_G'range )     := ( others => USB2_CTL_EXT_NAK_C );

      usb2CtlEpExtIb    : in  Usb2EndpPairIbArray( AGENTS_G'range ) := ( others => USB2_ENDP_PAIR_IB_INIT_C )
   );

end entity Usb2MuxEpCtl;

architecture Impl of Usb2MuxEpCtl is

   type StateType is ( ARB, FWD );

   subtype MuxIdxType is natural range AGENTS_G'range;

   type RegType is record
      state     : StateType;
      sel       : MuxIdxType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state     => ARB,
      sel       => AGENTS_G'low
   );

   signal r     : RegType := REG_INIT_C;
   signal rin   : RegType;

   function accept(
      constant p : in Usb2CtlReqParamType;
      constant x : in Usb2CtlEpAgentConfigType
   ) return boolean is
   begin
      if ( x.filtDir   and ( p.dev2Host  /= usb2ReqTypeIsDev2Host  ( x.reqType ) ) ) then
         return false;
      end if;
      if ( x.filtType  and ( p.reqType   /= usb2ReqTypeGetType     ( x.reqType ) ) ) then
         return false;
      end if;
      if ( x.filtRecpt and ( p.recipient /= usb2ReqTypeGetRecipient( x.reqType ) ) ) then
         return false;
      end if;
      if ( x.filtIdx and ( p.index(7 downto 0) /= x.reqIndex ) ) then
         return false;
      end if ;
      return true;
   end function accept;

begin

   P_COMB : process ( r, usb2CtlReqParamIb, usb2CtlExtIb, usb2CtlEpExtIb ) is
      variable v : RegType;
   begin
      v                 := r;

      usb2CtlExtOb      <= USB2_CTL_EXT_NAK_C;
      usb2CtlEpExtOb    <= usb2CtlEpExtIb( r.sel );
      usb2CtlReqParamOb <= ( others => usb2CtlReqParamIb );

      for i in usb2CtlReqParamOb'range loop
         usb2CtlReqParamOb(i).vld <= '0';
      end loop;

      if ( usb2CtlReqParamIb.vld = '0' ) then
         v.state := ARB;
      end if;

      case ( r.state ) is
         when ARB =>
            -- don't propagate 'vld' to the EPs until a choice is made

            if ( usb2CtlReqParamIb.vld = '1' ) then
               L_ARB : for i in AGENTS_G'range loop
                  if ( accept( usb2CtlReqParamIb, AGENTS_G(i) ) ) then
                     v.state      := FWD;
                     v.sel        := i;
                     -- blank NAK during this cycle!
                     usb2CtlExtOb <= USB2_CTL_EXT_INIT_C;
                     exit L_ARB;
                  end if;
               end loop;
            end if;

         when FWD =>
            usb2CtlReqParamOb(r.sel).vld <= usb2CtlReqParamIb.vld;
            usb2CtlExtOb                 <= usb2CtlExtIb( r.sel );
      end case;

      rin               <= v;
   end process P_COMB;

   P_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( usb2Rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

end architecture Impl;
