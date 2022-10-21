library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

package UsbUtilPkg is
   attribute KEEP       : string;
   attribute MARK_DEBUG : string;

   function toStr(constant x : in boolean) return string;
end package UsbUtilPkg;

package body UsbUtilPkg is

   function toStr(constant x : in boolean) return string is
   begin
      if ( x ) then return "TRUE"; else return "FALSE"; end if;
   end function toStr;

end package body UsbUtilPkg;
