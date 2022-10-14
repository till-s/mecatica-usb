library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity UsbCrcTbl is
   generic (
      POLY_G         : std_logic_vector
   );
   port (
      x : in  std_logic_vector(7 downto 0);
      y : out std_logic_vector(POLY_G'range)
   );
end entity UsbCrcTbl;

architecture Impl of UsbCrcTbl is
begin

   P_COMB : process ( x ) is
      variable v : std_logic_vector(7 downto 0);
      variable s : std_logic;
   begin
      v := x;
      for i in 1 to 8 loop
         s := v(0);
         v := '0' & v(7 downto 1);
         if ( s = '1' ) then
            v(POLY_G'range) := v(POLY_G'range) xor POLY_G;
         end if;
      end loop;

      y <= v(POLY_G'range);
   end process P_COMB;

end architecture Impl;
