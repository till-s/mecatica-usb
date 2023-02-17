-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity Usb2FifoFrmdTb is
end entity Usb2FifoFrmdTb;

architecture Sim of Usb2FifoFrmdTb is
   constant LDD_C    : natural    := 3;

   signal clk        : std_logic  := '0';
   signal run        : boolean    := true;

   signal don        : std_logic  := '0';
   signal sof        : std_logic;
   signal wen        : std_logic  := '0';
   signal ren        : std_logic  := '0';
   signal empty      : std_logic  := '0';
   signal full       : std_logic  := '0';
   signal din        : unsigned(7 downto 0)         := (others => '0');
   signal cmp        : unsigned(7 downto 0)         := (others => '0');
   signal dou        : std_logic_vector(7 downto 0);
   signal exp        : unsigned(7 downto 0)         := (others => '0');
   signal minFill    : unsigned(LDD_C - 1 downto 0) := (others => '0');

   procedure tick is begin wait until rising_edge(clk); end procedure tick;

begin

   process is begin
      if ( run ) then wait for 5 us; clk <= not clk; else wait; end if;
   end process;

   U_DUT : entity work.Usb2Fifo
      generic map (
         DATA_WIDTH_G => 8,
         LD_DEPTH_G   => LDD_C,
         FRAMED_G     => true
      )
      port map (
         wrClk        => clk,
         wrRst        => open,

         din          => std_logic_vector(din),
         don          => don,
         wen          => wen,
         full         => full,
         wrFilled     => open,
         
         rdClk        => clk,
         rdRst        => open,

         dou          => dou,
         sof          => sof,
         ren          => ren,
         empty        => empty,
         rdFilled     => open,

         minFill      => minFill,
         timer        => open
      );

   P_DIN : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         if ( (not full and not don and wen) = '1' ) then
            din <= din + 1;
         end if;
      end if;
   end process P_DIN;

   P_CHK : process (clk) is
      variable l : integer := 0;
      variable h : integer := 0;
   begin
      if ( rising_edge( clk ) ) then
         if ( (ren and not empty) = '1' ) then
            if ( h = 1 ) then
               assert sof = '0' report "SOF unexpected" severity failure;
               l := 256*to_integer(unsigned(dou)) + l;
               h := 0;
            elsif ( l = 0 ) then
               assert sof = '1' report "SOF missing" severity failure;
               l := to_integer(unsigned(dou));
               h := 1;
            else
               assert unsigned(dou) = cmp report "data mismatch" severity failure;
               cmp <= cmp + 1;
               l := l - 1;
            end if;
         end if;
      end if;
   end process P_CHK;


   P_DRV : process is
   begin
      tick;
      tick;
      wen <= '1';
      tick;
      assert full = '0' report "unexpected full" severity failure;
      tick;
      assert full = '0' report "unexpected full" severity failure;
      don <= '1';
      tick;
      assert full = '0' report "unexpected full" severity failure;
      don <= '0';
      tick;
      assert full = '1' report "unexpected not full" severity failure;
      tick;
      assert full = '0' report "unexpected full" severity failure;
      tick;
      don <= '1';
      tick;
      don <= '0';
      wen <= '0';
      tick;
      assert full = '1' report "unexpected not full" severity failure;
      tick;
      assert full = '1' report "unexpected full" severity failure;
      ren <= '1';
      tick;
      assert empty = '0' report "unexpected empty" severity failure;
      assert sof   = '1' report "SOF missing" severity failure;

      while empty = '0' loop
         tick;
      end loop;
      ren <= '0';
      tick;
      wen <= '1';
      tick;
      tick;
      wen <= '0';
      don <= '1';
      tick;
      tick;
      don <= '0';
      tick;
      ren <= '1';


      while cmp /= din loop
         tick;
      end loop;

      run <= false;
      report "Test PASSED";
      wait;
   end process P_DRV;
   

end architecture Sim;
