-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

entity UsbCrcTblTb is
end entity UsbCrcTblTb;

architecture Sim of UsbCrcTblTb is
   signal clk : std_logic := '0';

   constant POLY_C : std_logic_vector(4 downto 0) := USB2_CRC5_POLY_C(4 downto 0);
   constant CHCK_C : std_logic_vector(4 downto 0) := USB2_CRC5_CHCK_C(4 downto 0);

   constant PO05_C : std_logic_vector(15 downto 0) := x"00" & "000" & POLY_C;
   constant PO16_C : std_logic_vector(15 downto 0) := USB2_CRC16_POLY_C;
   constant CH16_C : std_logic_vector(15 downto 0) := USB2_CRC16_CHCK_C;

   signal   x      : std_logic_vector(7 downto 0) := (others => 'X');
   signal   x16    : std_logic_vector(7 downto 0);
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

   signal tst3      : natural   := 0;

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
      x"c1",
      "XXXXXXXX" -- dummy terminator to avoid index overflow
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
      x               <= tstVec1(0) xor USB2_CRC5_INIT_C(7 downto 0);
      tick;
      x               <= tstVec1(1) xor ( "000" & y );
      tick;
      assert y = CHCK_C report "CRC5 1 mismatch" severity failure;
      tick;
      x               <= tstVec2(0) xor USB2_CRC5_INIT_C(7 downto 0);
      tick;
      x               <= tstVec2(1) xor ( "000" & y );
      tick;
      assert y = CHCK_C report "CRC5 2 mismatch" severity failure;
      c16             <= USB2_CRC16_INIT_C;
      tick;
      while ( tst3 < tstVec3'high ) loop
         c16  <= y16 xor (x"00" & c16(15 downto 8));
         tst3 <= tst3 + 1;
         tick;
      end loop;
      
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

   x16 <= tstVec3(tst3) xor c16(7 downto 0);

   U_DUT16 : entity work.UsbCrcTbl
      generic map (
         POLY_G => PO16_C
      )
      port map (
         x      => x16,
         y      => y16
      );
end architecture Sim;

