library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

package Usb2AppCfgPkg is

   -- GHDL 2.0 doesn't like an array constant being defined in the
   -- package body -- I got 'NULL access dereferenced' errors.
   function USB2_APP_CFG_DESCRIPTORS_F return Usb2ByteArray;

   -- the actual descriptors are defined by the application
   -- which must supply the package body
   constant USB2_APP_CFG_DESCRIPTORS_C    :  Usb2ByteArray := USB2_APP_CFG_DESCRIPTORS_F;
   -- number of endpoints (including EP 0)

   -- device desriptor
   function USB2_APP_DEV_DESCRIPTOR_F return  Usb2ByteArray;

   constant USB2_APP_DEV_DESCRIPTOR_C  :  Usb2ByteArray := USB2_APP_DEV_DESCRIPTOR_F;

end package Usb2AppCfgPkg;
