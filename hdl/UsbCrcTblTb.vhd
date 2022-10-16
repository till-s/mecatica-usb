library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity UsbCrcTblTb is
end entity UsbCrcTblTb;

architecture Sim of UsbCrcTblTb is
   signal clk : std_logic := '0';

   constant POLY_C : std_logic_vector(4 downto 0) := "10100";
   constant CHCK_C : std_logic_vector(4 downto 0) := "00110";

   constant PO05_C : std_logic_vector(15 downto 0) := x"00" & "000" & POLY_C;
   constant PO16_C : std_logic_vector(15 downto 0) := x"A001";
   constant CH16_C : std_logic_vector(15 downto 0) := x"B001";

   signal   x      : std_logic_vector(7 downto 0) := (others => 'X');
   signal   y      : std_logic_vector(POLY_C'range);
   signal   y05    : std_logic_vector(15 downto 0);
   signal   y16    : std_logic_vector(PO16_C'range);
   signal   c16    : std_logic_vector(PO16_C'range);

   type     Slv8Array is array(natural range <>) of std_logic_vector(7 downto 0);

   constant tstVec1 : Slv8Array := (
      x"bf",
      x"bb"
   );

   constant tstVec2 : Slv8Array := (
      x"c9",
      x"fd"
   );

   constant tstVec3 : Slv8Array := (
      x"c7",
      x"3d",
      x"25",
      x"93",
      x"ba",
      x"bb",
      x"b3",
      x"5e",
      x"54",
      x"5a",
      x"ac",
      x"5a",
      x"6c",
      x"ee",
      x"00",
      x"ab",
      -- last two bytes are one's complement of CRC (seeded all ones) up to here
      x"a2",
      x"c1"
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
      variable v16 : std_logic_vector(PO16_C'range);
   begin
      tick;
      x               <= tstVec1(0) xor x"1f";
      tick;
      x               <= tstVec1(1) xor ( "000" & y );
      tick;
      assert y = CHCK_C report "CRC5 1 mismatch" severity failure;
      tick;
      x               <= tstVec2(0) xor x"1f";
      tick;
      x               <= tstVec2(1) xor ( "000" & y );
      tick;
      assert y = CHCK_C report "CRC5 2 mismatch" severity failure;
      v16             := (others => '1');
      x               <= v16(7 downto 0) xor tstVec3(0);
      c16             <= v16;
      tick;
      for i in 1 to tstVec3'length-1 loop
         v16 := (x"00" & c16(15 downto 8)) xor y16;
         x   <= v16(7 downto 0) xor tstVec3(i);
         c16 <= v16;
         tick;
      end loop;
         v16 := (x"00" & c16(15 downto 8)) xor y16;
         c16 <= v16;
         tick;
      
      assert (c16 = CH16_C) report "CRC16  mismatch" severity failure;
      
      done <= true;
      report "TEST PASSED";
      wait;
   end process P_TST;

   U_DUT : entity work.UsbCrcTbl
      generic map (
         POLY_G => PO05_C
      )
      port map (
         x      => x,
         y      => y05
      );
   y <= y05(4 downto 0);

   U_DUT16 : entity work.UsbCrcTbl
      generic map (
         POLY_G => PO16_C
      )
      port map (
         x      => x,
         y      => y16
      );
end architecture Sim;

