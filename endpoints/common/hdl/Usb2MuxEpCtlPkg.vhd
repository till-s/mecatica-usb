-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Package with definitions used by Usb2MuxEpCtl

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

package Usb2MuxEpCtlPkg is

   -- describe what request type and index
   -- identifies a particular agent.
   type Usb2CtlEpAgentConfigType is record
      -- filter based on the request type
      -- can be selectively enabled
      reqType  : Usb2ByteType;
      filtDir  : boolean;
      filtType : boolean;
      filtRecpt: boolean;
      reqIndex : Usb2ByteType;
   end record Usb2CtlEpAgentConfigType;

   function usb2CtlEpMkAgentConfig(
      constant recipient : in Usb2CtlRequestRecipientType;
      constant index     : in integer range 0 to 255;
      constant dev2Host  : in std_logic := 'X';
      constant reqType   : in Usb2CtlRequestTypeType := "XX";
   ) return Usb2CtlEpAgentConfigType;

   constant USB2_CTL_EP_AGENT_CONFIG_INIT_C : Usb2CtlEpAgentConfigType := (
      reqType   => (others => '0'),   
      filtDir   => false,
      filtType  => false,
      filtRecpt => false,
      reqIndex  => (others => '0'),
   );

   type Usb2CtlEpAgentConfigArray is array (natural range <>) of Usb2CtlEpAgentConfigType;

   constant USB2_CTL_EP_AGENT_CONFIG_EMPTY_C : Usb2CtlEpAgentConfigArray(0 to -1) := (others => USB2_CTL_EP_AGENT_CONFIG_INIT_C);

   function ite(
      constant c : in boolean;
      constant a : in Usb2CtlEpAgentConfigArray;
      constant b : in Usb2CtlEpAgentConfigArray
   ) return Usb2CtlEpAgentConfigArray;

   function ite(
      constant c : in boolean;
      constant a : in Usb2CtlEpAgentConfigType;
      constant b : in Usb2CtlEpAgentConfigArray := USB2_CTL_EP_AGENT_CONFIG_EMPTY_C
   ) return Usb2CtlEpAgentConfigArray;


   function usb2CtlEpMkIfcAgentConfig(
      constant index     : in natural range 0 to 255;
      constant dev2Host  : in std_logic := 'X';
      constant reqType   : in Usb2CtlRequestTypeType := "XX"
   ) return Usb2CtlEpAgentConfigType;

   function usb2CtlEpMkCsIfcAgentConfig(
      constant index     : in natural range 0 to 255;
      constant dev2Host  : in std_logic := 'X'
   ) return Usb2CtlEpAgentConfigType;

   function usb2CtlEpMkEpAgentConfig(
      constant index     : in natural range 0 to 255;
      constant dev2Host  : in std_logic := 'X';
      constant reqType   : in Usb2CtlRequestTypeType := "XX"
   ) return Usb2CtlEpAgentConfigType;

end package Usb2MuxEpCtlPkg;

package body Usb2MuxEpCtlPkg is

   function usb2CtlEpMkAgentConfig(
      constant recipient : in Usb2CtlRequestRecipientType;
      constant index     : in integer range 0 to 255;
      constant dev2Host  : in std_logic := 'X';
      constant reqType   : in Usb2CtlRequestTypeType := "XX";
   ) return Usb2CtlEpAgentConfigType is
      variable v   : Usb2CtlEpAgentConfigType;
      variable d2h : boolean;
      variable typ : Usb2CtlRequestTypeType      := "00";
      variable rcp : Usb2CtlRequestRecipientType := "00";
   begin
      d2h         := (dev2Host   = '1');
      v.filtDir   := (dev2Host  /= 'X');
      v.filtType  := (reqType   /= "XX");
      v.filtRecpt := (recipient /= "XX");

      if ( v.filtType ) then
         typ := reqType;
      end if;

      if ( v.filtRecpt ) then
         rcp := recipient;
      end if;

      v.reqType  := usb2MakeRequestType( d2h, typ, rcp );
      v.reqIndex := std_logic_vector( to_unsigned( index, 8 ) );

      return v;

   end function usb2CtlEpMkAgentConfig;

   function usb2CtlEpMkIfcAgentConfig(
      constant index     : in natural range 0 to 255;
      constant dev2Host  : in std_logic := 'X';
      constant reqType   : in Usb2CtlRequestTypeType := "XX"
   ) return Usb2CtlEpAgentConfigType is
   begin
      return usb2CtlEpMkAgentConfig (
         recipient => USB2_REQ_TYP_RECIPIENT_IFC_C,
         index     => index,
         dev2Host  => dev2Host,
         reqType   => reqType
      );
   end function usb2CtlEpMkIfcAgentConfig;

   function usb2CtlEpMkEpAgentConfig(
      constant index     : in natural range 0 to 255;
      constant dev2Host  : in std_logic := 'X';
      constant reqType   : in Usb2CtlRequestTypeType := "XX"
   ) return Usb2CtlEpAgentConfigType is
   begin
      return usb2CtlEpMkAgentConfig (
         recipient => USB2_REQ_TYP_RECIPIENT_EPT_C,
         index     => index,
         dev2Host  => dev2Host,
         reqType   => reqType
      );
   end function usb2CtlEpMkEpAgentConfig;

   function usb2CtlEpMkCsIfcAgentConfig(
      constant index     : in natural range 0 to 255;
      constant dev2Host  : in std_logic := 'X'
   ) return Usb2CtlEpAgentConfigType is
   begin
      return usb2CtlEpMkIfcAgentConfig (
         index     => index,
         dev2Host  => dev2Host,
         reqType   => USB2_REQ_TYP_TYPE_CLASS_C
      );
   end function usb2CtlEpMkCsIfcAgentConfig;

   function ite(
      constant c : in boolean;
      constant a : in Usb2CtlEpAgentConfigArray;
      constant b : in Usb2CtlEpAgentConfigArray
   ) return Usb2CtlEpAgentConfigArray is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;

   function ite(
      constant c : in boolean;
      constant a : in Usb2CtlEpAgentConfigType;
      constant b : in Usb2CtlEpAgentConfigArray := USB2_CTL_EP_AGENT_CONFIG_EMPTY_C
   ) return Usb2CtlEpAgentConfigArray is
      variable v : Usb2CtlEpAgentConfigArray(0 to 0);
   begin
      if ( c ) then
         v(0) := a;
         return v;
      else
         return b;
      end if;
   end function ite;

end package body Usb2MuxEpCtlPkg;
