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

   function toChar(constant x : in std_logic) return character;

   function toStr(constant x : in unsigned) return string;
   -- converts std_logic_vector to an integer number (13)
   function toStr(constant x : in std_logic_vector) return string;
   -- print a bit-string (1101)
   function toBitStr(constant x : in std_logic_vector) return string;
   function toStr(constant x : in signed) return string;

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

   function toStr(constant x : in unsigned)
   return string is
   begin
      return integer'image(to_integer(x));
   end function toStr;

   function toStr(constant x : in std_logic_vector)
   return string is
   begin
      return integer'image(to_integer(unsigned(x)));
   end function toStr;

   function toStr(constant x : in signed)
   return string is
   begin
      return integer'image(to_integer(x));
   end function toStr;

   function toChar(constant x : in std_logic) return character is
   begin
      -- there seems to be no other way :-(. Synopsis generated
      -- shorter strings than ghdl (which has quotes around std_logic
      -- values); found no way to use std_logic'image().
      case x is
         when 'U' => return 'U';
         when 'X' => return 'X';
         when '0' => return '0';
         when '1' => return '1';
         when 'Z' => return 'Z';
         when 'W' => return 'W';
         when 'L' => return 'L';
         when 'H' => return 'H';
         when others =>
      end case;
         return '-';
   end function;

   function toBitStr(constant x : in std_logic_vector) return string is
      variable s      : string(1 to x'length);
      variable b      : std_logic;
      variable c      : character;
   begin
      for i in x'left downto x'right loop
         s(x'left - i + 1) := toChar(x(i));
      end loop;
      return s;
   end function toBitStr;

end package body Usb2UtilPkg;
