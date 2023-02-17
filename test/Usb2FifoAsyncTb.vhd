-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity Usb2FifoAsyncTb is
end entity Usb2FifoAsyncTb;

architecture Sim of Usb2FifoAsyncTb is
   constant LDD_C    : natural    := 3;
   constant TIM_C    : natural    := 3;

   signal rclk       : std_logic  := '0';
   signal wclk       : std_logic  := '0';
   signal rrst       : std_logic  := '0';
   signal wrst       : std_logic  := '0';
   signal wResetting : std_logic  := '0';
   signal rResetting : std_logic  := '0';

   signal wrun       : boolean    := true;
   signal rrun       : boolean    := true;

   signal enReader   : std_logic  := '1';

   signal wen        : std_logic  := '0';
   signal ren        : std_logic  := '0';
   signal empty      : std_logic  := '0';
   signal full       : std_logic  := '0';
   signal din        : unsigned(7 downto 0)         := (others => 'U');
   signal dou        : std_logic_vector(7 downto 0);
   signal exp        : unsigned(7 downto 0)         := (others => '0');
   signal minFill    : unsigned(LDD_C - 1 downto 0) := (others => '0');
   signal timer      : unsigned(TIM_C - 1 downto 0) := (others => '0');
   signal rdFilled   : unsigned(LDD_C     downto 0);
   signal wrFilled   : unsigned(LDD_C     downto 0);

   function ite(x : natural) return std_logic is
   begin
      if ( x mod 2 = 0 ) then return '0'; else return '1'; end if;
   end function ite;

   signal rrnd        : natural := 2;
   signal wrnd        : natural := 4;

   procedure rtick is begin wait until rising_edge(rclk); end procedure rtick;
   procedure wtick is begin wait until rising_edge(wclk); end procedure wtick;

begin

   process is begin
      if ( rrun or wrun ) then wait for 5 us; rclk <= not rclk; else wait; end if;
   end process;

   process is begin
      if ( rrun or wrun ) then wait for 2.223 us; wclk <= not wclk; else wait; end if;
   end process;

   process is begin
      wait until (not rrun and not wrun);
      report "Test PASSED";
      wait;
   end process;

   ren <= ite( rrnd ) and enReader;
   wen <= ite( wrnd );

   U_DUT : entity work.Usb2Fifo
      generic map (
         DATA_WIDTH_G => 8,
         LD_DEPTH_G   => LDD_C,
         LD_TIMER_G   => TIM_C,
         EXACT_THR_G  => false,
         ASYNC_G      => true
      )
      port map (
         wrClk        => wclk,
         wrRst        => wrst,
         wrRstOut     => wResetting,

         din          => std_logic_vector(din),
         wen          => wen,
         full         => full,
         wrFilled     => wrFilled,
         
         rdClk        => rclk,
         rdRst        => rrst,
         rdRstOut     => rResetting,

         dou          => dou,
         ren          => ren,
         empty        => empty,
         rdFilled     => rdFilled,

         minFill      => minFill,
         timer        => timer
      );

   P_READ : process ( rclk ) is
   begin
      if ( rising_edge( rclk ) ) then
         if ( ( ren and not empty) = '1' ) then
            assert unsigned(dou) = exp report "READBACK MISMATCH" severity failure;
            if ( exp = x"FF" ) then
               rrun <= false;
            else
               exp <= exp + 1;
            end if;
         end if;
         rrnd <= (rrnd * 75) mod 65537;
      end if;
   end process P_READ;

   P_DRV : process is
   begin
      rtick;
      rtick;

      timer <= (others => '1');

      rtick;
      minFill <= to_unsigned(3, minFill'length);
      rtick;

      wtick;
      din <= (others => '0');
      L_W : while ( true ) loop
         if ( ( wen and not full ) = '1' ) then
            if ( din = x"ff" ) then
               exit L_W;
            else
               din <= din + 1;
            end if;
         end if;
         wrnd <= (wrnd * 75) mod 65537;
         wtick;
      end loop;
      wrnd <= 2; -- takes wen low
      wtick;

      while wrFilled /= 0 loop
         wtick;
      end loop;

      wrnd <= 1;
      while wrFilled /= 5 loop
         wtick;
      end loop;
      wrnd <= 2;
      while ( empty = '1' ) loop
         wtick;
      end loop;
      wrst <= '1';
      wtick;
      while ( wResetting = '1' ) loop
        wrst <= '0';
        wtick;
      end loop;
      assert empty    = '1' report "Not empty after reset" severity failure;
      assert wrFilled = 0   report "Empty but filled /= 0??" severity failure;

      wrun <= false;
      wait;
   end process P_DRV;
   

end architecture Sim;
