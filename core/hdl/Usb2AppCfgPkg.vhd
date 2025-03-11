-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

package Usb2AppCfgPkg is

   -- GHDL 2.0 doesn't like an array constant being defined in the
   -- package body -- I got 'NULL access dereferenced' errors.
   -- Therefore, the application (which must supply the body of this
   -- package as to define this function which just returns a local
   -- constant)
   function usb2AppGetDescriptors return Usb2ByteArray;

   -- the actual descriptors are defined by the application
   -- which must supply the package body
   constant USB2_APP_DESCRIPTORS_C    :  Usb2ByteArray;
   -- number of endpoints (including EP 0)

end package Usb2AppCfgPkg;
