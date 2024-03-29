-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Generic control endpoint - package definitions

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

package Usb2EpGenericCtlPkg is

   -- users/clients of the generic control endpoint use these to define
   -- the requests they support.

   type Usb2EpGenericReqDefType is record
      dev2Host           : std_logic;
      request            : Usb2CtlRequestCodeType;
      dataSize           : natural;
   end record Usb2EpGenericReqDefType;

   constant USB2_EP_GENERIC_REQ_DEF_INIT_C : Usb2EpGenericReqDefType := (
      dev2Host           => '0',
      request            => (others => '0'),
      dataSize           => 0
   );

   type Usb2EpGenericReqDefArray is array (natural range <>) of Usb2EpGenericReqDefType;

   constant USB2_EP_GENERIC_REQ_DEF_ARRAY_EMPTY_C : Usb2EpGenericReqDefArray(0 to -1 ) := (
      others => USB2_EP_GENERIC_REQ_DEF_INIT_C
   );

   function maxParamSize(
      constant x: in Usb2EpGenericReqDefArray
   ) return natural;

   function selected(
      constant v: in std_logic_vector;
      constant r: in Usb2CtlRequestCodeType;
      constant x: in Usb2EpGenericReqDefArray
   ) return boolean;
 
   function idxOf(
      constant r: in Usb2CtlRequestCodeType;
      constant x: in Usb2EpGenericReqDefArray
   ) return integer;

   function concat(
      constant x: in Usb2EpGenericReqDefArray := USB2_EP_GENERIC_REQ_DEF_ARRAY_EMPTY_C;
      constant y: in Usb2EpGenericReqDefArray := USB2_EP_GENERIC_REQ_DEF_ARRAY_EMPTY_C
   ) return Usb2EpGenericReqDefArray;

   function ite(
      constant b: in boolean;
      constant x: in Usb2EpGenericReqDefArray;
      constant y: in Usb2EpGenericReqDefArray := USB2_EP_GENERIC_REQ_DEF_ARRAY_EMPTY_C
   ) return Usb2EpGenericReqDefArray;

end package Usb2EpGenericCtlPkg;

package body Usb2EpGenericCtlPkg is

   function maxParamSize(
      constant x: in Usb2EpGenericReqDefArray
   ) return natural is
      variable rv : natural := 0;
   begin
      for i in x'range loop
         if ( x(i).dataSize > rv ) then
            rv := x(i).dataSize;
         end if;
      end loop;
      return rv;
   end function maxParamSize;

   function idxOf(
      constant r: in Usb2CtlRequestCodeType;
      constant x: in Usb2EpGenericReqDefArray
   ) return integer is
      variable v : integer;
   begin
      for i in x'range loop
         if ( x(i).request = r ) then
            return i;
         end if;
      end loop;
      return -1;
   end function idxOf;

   function selected(
      constant v: in std_logic_vector;
      constant r: in Usb2CtlRequestCodeType;
      constant x: in Usb2EpGenericReqDefArray
   ) return boolean is
      constant i : integer := idxOf( r, x );
   begin
      if ( i < 0 ) then
         return false;
      end if;
      return v(i) = '1';
   end function selected;
 
   function concat(
      constant x: in Usb2EpGenericReqDefArray := USB2_EP_GENERIC_REQ_DEF_ARRAY_EMPTY_C;
      constant y: in Usb2EpGenericReqDefArray := USB2_EP_GENERIC_REQ_DEF_ARRAY_EMPTY_C
   ) return Usb2EpGenericReqDefArray is
   begin
      if ( x'length > 0 and y'length > 0 ) then
         return x & y;
      elsif ( x'length > 0 ) then
         return x;
      else
         return y;
      end if;
   end function concat;

   function ite(
      constant b: in boolean;
      constant x: in Usb2EpGenericReqDefArray;
      constant y: in Usb2EpGenericReqDefArray := USB2_EP_GENERIC_REQ_DEF_ARRAY_EMPTY_C
   ) return Usb2EpGenericReqDefArray is
   begin
      if ( b ) then return x; else return y; end if;
   end function ite;

end package body Usb2EpGenericCtlPkg;
