-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

-- Private package for USB data types, constants, functions etc.
-- which are only to be used within the core

package Usb2PrivPkg is

   type Usb2PkTxSubType is record
      rdy   : std_logic;
      -- if an error occurs then the stream is aborted (sender must stop)
      -- i.e., 'don' may be asserted before all the data are sent!
      err   : std_logic;
      don   : std_logic;
   end record Usb2PkTxSubType;

   constant USB2_PKTX_SUB_INIT_C : Usb2PkTxSubType := (
      rdy   => '0',
      err   => '0',
      don   => '0'
   );

end package Usb2PrivPkg;
