-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

-- CRC table (as a combinatorial process)

entity UsbCrcTbl is
   generic (
      POLY_G : std_logic_vector(15 downto 0)
   );
   port (
      x   : in  std_logic_vector( 7 downto 0);
      y   : out std_logic_vector(15 downto 0)
   );
end entity UsbCrcTbl;

architecture Impl of UsbCrcTbl is
begin

   P_COMB : process ( x ) is
      variable v : std_logic_vector(15 downto 0);
      variable s : std_logic;
   begin
      v          := (others => '0');
      v(x'range) := x;
      for i in 1 to 8 loop
         s := v(0);
         v := '0' & v(v'left downto 1);
         if ( s = '1' ) then
            v := v xor POLY_G;
         end if;
      end loop;

      y <= v;
   end process P_COMB;

end architecture Impl;
