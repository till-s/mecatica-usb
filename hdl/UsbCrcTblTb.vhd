library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity UsbCrcTblTb is
end entity UsbCrcTblTb;

architecture Sim of UsbCrcTblTb is
   signal clk : std_logic := '0';

   constant POLY_C : std_logic_vector(4 downto 0) := "10100";
   constant CHCK_C : std_logic_vector(4 downto 0) := "00110";

   signal   x      : std_logic_vector(7 downto 0) := (others => 'X');
   signal   y      : std_logic_vector(POLY_C'range);

   type     Slv8Array is array(natural range <>) of std_logic_vector(7 downto 0);

   constant tstVec1 : Slv8Array := (
      x"bf",
      x"bb"
   );

   constant tstVec2 : Slv8Array := (
      x"c9",
      x"fd"
   );

   signal done : boolean := false;

   procedure tick is
   begin
      wait until rising_edge( clk );
   end procedure tick;

begin

   P_CLK : process is
   begin
      if ( done ) then wait; end if;
      wait for 10 ns;
      clk <= not clk;
   end process P_CLK;

   P_TST : process is
   begin
      tick;
      x               <= tstVec1(0) xor x"1f";
      tick;
      x               <= tstVec1(1) xor ( "000" & y );
      tick;
      assert y = CHCK_C report "Checksum 1 mismatch" severity failure;
      tick;
      x               <= tstVec2(0) xor x"1f";
      tick;
      x               <= tstVec2(1) xor ( "000" & y );
      tick;
      assert y = CHCK_C report "Checksum 2 mismatch" severity failure;
      done <= true;
      report "TEST PASSED";
      wait;
   end process P_TST;

   U_DUT : entity work.UsbCrcTbl
      generic map (
         POLY_G => POLY_C
      )
      port map (
         x      => x,
         y      => y
      );
end architecture Sim;

