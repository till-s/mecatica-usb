-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

package Usb2UtilPkg is

   attribute KEEP       : string;
   attribute MARK_DEBUG : string;

   function toStr(constant x : in boolean) return string;

   function toSl(constant x : in boolean) return std_logic;

   function ite(constant x: in boolean; constant a,b: integer)
   return integer;

   function ite(constant x: in boolean; constant a,b: std_logic_vector)
   return std_logic_vector;

   function ite(constant x: in boolean; constant a,b: unsigned)
   return unsigned;

   function ite(constant x: in boolean; constant a,b: signed)
   return signed;

   function ite(constant x: in boolean; constant a,b: real)
   return real;

   function ite(constant x: in boolean; constant a,b: string)
   return string;

   -- number of bits required to represent 'x'
   function numBits(constant x : positive) return positive;

end package Usb2UtilPkg;

package body Usb2UtilPkg is

   function toStr(constant x : in boolean) return string is
   begin
      if ( x ) then return "TRUE"; else return "FALSE"; end if;
   end function toStr;

   function toSl(constant x : in boolean) return std_logic is
   begin
      if ( x ) then return '1'; else return '0'; end if;
   end function toSl;

   function ite(constant x: in boolean; constant a,b: integer)
   return integer is
   begin
      if ( x ) then return a; else return b; end if;
   end function ite;

   function ite(constant x: in boolean; constant a,b: std_logic_vector)
   return std_logic_vector is
   begin
      if ( x ) then return a; else return b; end if;
   end function ite;

   function ite(constant x: in boolean; constant a,b: unsigned)
   return unsigned is
   begin
      if ( x ) then return a; else return b; end if;
   end function ite;

   function ite(constant x: in boolean; constant a,b: signed)
   return signed is
   begin
      if ( x ) then return a; else return b; end if;
   end function ite;

   function ite(constant x: in boolean; constant a,b: real)
   return real is
   begin
      if ( x ) then return a; else return b; end if;
   end function ite;

   function ite(constant x: in boolean; constant a,b: string)
   return string is
   begin
      if ( x ) then return a; else return b; end if;
   end function ite;

   function numBits(constant x : positive)
   return positive is
      variable r : positive := 1;
      variable c : positive := 2;
   begin
      while ( x >= c ) loop
         c := c * 2;
         r := r + 1;
      end loop;
      return r;
   end function numBits;

end package body Usb2UtilPkg;
