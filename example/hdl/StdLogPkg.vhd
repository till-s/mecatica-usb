-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- helper types derived from std_logic

library ieee;
use     ieee.std_logic_1164.all;

package StdLogPkg is 

   subtype Slv32 is std_logic_vector(31 downto 0);

   type Slv32Array is array(natural range <>) of Slv32;

   type RegArray is array(natural range <>, natural range <>) of Slv32;

end package StdLogPkg;
