-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity Usb2FifoTb is
end entity Usb2FifoTb;

architecture Sim of Usb2FifoTb is
   constant LDD_C    : natural    := 3;
   constant TIM_C    : natural    := 3;

   signal clk        : std_logic  := '0';
   signal run        : boolean    := true;

   signal wen        : std_logic  := '0';
   signal ren        : std_logic  := '0';
   signal empty      : std_logic  := '0';
   signal full       : std_logic  := '0';
   signal din        : unsigned(7 downto 0)         := (others => 'U');
   signal dou        : std_logic_vector(7 downto 0);
   signal exp        : unsigned(7 downto 0)         := (others => '0');
   signal minFill    : unsigned(LDD_C - 1 downto 0) := (others => '0');
   signal timer      : unsigned(TIM_C - 1 downto 0) := (others => '0');

   procedure tick is begin wait until rising_edge(clk); end procedure tick;

begin

   process is begin
      if ( run ) then wait for 5 us; clk <= not clk; else wait; end if;
   end process;

   U_DUT : entity work.Usb2Fifo
      generic map (
         DATA_WIDTH_G => 8,
         LD_DEPTH_G   => LDD_C,
         LD_TIMER_G   => TIM_C,
         EXACT_THR_G  => true
      )
      port map (
         clk          => clk,
         rst          => open,

         din          => std_logic_vector(din),
         wen          => wen,
         full         => full,
         
         dou          => dou,
         ren          => ren,
         empty        => empty,

         filled       => open,

         minFill      => minFill,
         timer        => timer
      );


   P_READ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ( ren and not empty) = '1' ) then
            assert unsigned(dou) = exp report "READBACK MISMATCH" severity failure;
            exp <= exp + 1;
         end if;
      end if;
   end process P_READ;

   P_DRV : process is
   begin
      tick;
      ren   <= '1';
      timer <= (others => '1');
      tick;
      minFill <= to_unsigned(3, minFill'length);
      tick;
      wen <= '1';
      din <= (others => '0');
      tick;
      din <= din + 1;
      tick;
      din <= din + 1;
      tick;
      wen <= '0';
      tick;
      tick;
      tick;
      assert exp = 0 report "should not have read" severity failure;
      wen <= '1';
      din <= din + 1;
      tick;
      wen <= '0';
      tick;
      tick;
      tick;
      tick;
      tick;
      tick;
      assert exp = 4 report "should read 4 items" severity failure;
      tick;
      assert exp = 4 report "should still read 4 items" severity failure;
      timer <= to_unsigned(2, timer'length);
      din   <= din + 1;
      wen   <= '1';
      tick;
      for i in 3 downto 0 loop
      wen   <= '0';
      assert exp = 4 report "should still read 4 items" severity failure;
      tick;
      end loop;
      assert exp = 5 report "should read 5 items" severity failure;
      tick;
      assert exp = 5 report "should read 5 items" severity failure;
      ren   <= '0';
      timer <= (others => '1');
      for i in 0 to 3 loop
      wen   <= '1';
      din   <= din + 1;
      tick;
      end loop;
      wen   <= '0';
      tick;
      ren   <= '1';
      tick;
      for i in 0 to 3 loop
      assert exp = 5 + i report "read error" severity failure;
      tick;
      end loop;
      

      run <= false;
      wait;
   end process P_DRV;
   

end architecture Sim;
