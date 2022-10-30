library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

package UsbUtilPkg is

   attribute KEEP       : string;
   attribute MARK_DEBUG : string;

   function toStr(constant x : in boolean) return string;

   function toSl(constant x : in boolean) return std_logic;

end package UsbUtilPkg;

package body UsbUtilPkg is

   function toStr(constant x : in boolean) return string is
   begin
      if ( x ) then return "TRUE"; else return "FALSE"; end if;
   end function toStr;

   function toSl(constant x : in boolean) return std_logic is
   begin
      if ( x ) then return '1'; else return '0'; end if;
   end function toSl;

end package body UsbUtilPkg;
