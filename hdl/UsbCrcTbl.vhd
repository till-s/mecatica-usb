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
   function max(constant a,b: in natural) return natural is
   begin
      if ( a > b ) then return a; else return b; end if;
   end function max;
begin

   P_COMB : process ( x ) is
      constant M : natural := max(POLY_G'length, x'length);
      variable v : std_logic_vector(M - 1 downto 0);
      variable s : std_logic;
   begin
      v          := (others => '0');
      v(x'range) := x;
      for i in 1 to 8 loop
         s := v(0);
         v := '0' & v(v'left downto 1);
         if ( s = '1' ) then
            v(POLY_G'range) := v(POLY_G'range) xor POLY_G;
         end if;
      end loop;

      y <= v(POLY_G'range);
   end process P_COMB;

end architecture Impl;
