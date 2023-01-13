-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

entity I2SPlaybackTb is
end entity I2SPlaybackTb;

architecture sim of I2SPlaybackTb is

   constant SPF_C         : natural   := 48; -- samples per frame
   -- first frame sent is used to synchronize receiver and
   -- will not appear on i2s
   constant NFRMS_EXP_C   : natural   := 3;

   signal usb2Clk         : std_logic := '0';
   signal bclk            : std_logic := '0';
   signal pblrc           : std_logic := '1';
   signal pbdat           : std_logic := '1';
   signal pblrclst        : std_logic := '1';

   procedure sendFrame(
      signal ob : inout Usb2EndpPairObType
   ) is
      variable dat : unsigned(7 downto 0);
   begin
      wait until rising_edge( usb2Clk );
      dat := (others => '0');
      ob.mstOut.vld <= '1';
      for i in 1 to 6*48 loop
        ob.mstOut.dat <= std_logic_vector( dat );
        dat           := dat + 1;
        wait until rising_edge( usb2Clk );
      end loop;
      ob.mstOut.vld <= '0';
      ob.mstOut.don <= '1';
      wait until rising_edge( usb2Clk );
      ob.mstOut.don <= '0';
      wait until rising_edge( usb2Clk );
   end procedure sendFrame;

   signal epOb : usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;

   signal run  : boolean := true;

begin

   process is
   begin
      if ( not run ) then
         wait;
      else
         wait for 10 ns;
         usb2Clk <= not usb2Clk;
      end if;
   end process;

   process is
   begin
      if ( not run ) then
         wait;
      else
         wait for 99 ns;
         bclk <= not bclk;
      end if;
   end process;

   P_TEST : process is
   begin
      sendFrame( epOb );
      sendFrame( epOb );
      sendFrame( epOb );
      sendFrame( epOb );
      wait;
   end process P_TEST;

   P_SND : process (usb2Clk) is
      variable got : natural := 0;
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( epOb.mstOut.vld = '1' ) then
            got := got + 1;
            report integer'image(got) & " bytes sent";
         end if;
      end if;
   end process P_SND;

   P_RCV : process ( bclk ) is
      variable sreg  : std_logic_vector(47 downto 0) := (others => '0');
      variable cmp   : unsigned(47 downto 0)         := x"050403020100";
      variable smpls : natural := 0;
      variable frms  : natural := 0;
   begin
      if ( rising_edge( bclk ) ) then
         pblrclst <= pblrc;
         sreg := pbdat & sreg(sreg'left downto 1);
         if ( ( not pblrc and pblrclst ) = '1' ) then
            if ( sreg /= x"000000000000" ) then
               if ( unsigned(sreg) /= cmp ) then
                  for i in 5 downto 0 loop
                     report "sreg[" & integer'image(i) & "] " & integer'image(to_integer(unsigned(sreg(8*i+7 downto 8*i))));
                     report "cmp [" & integer'image(i) & "] " & integer'image(to_integer(unsigned(cmp(8*i+7 downto 8*i))));
                  end loop;
                  report "smpls" & integer'image(smpls);
                  report "frms " & integer'image(frms);
               end if;
               assert unsigned(sreg) = cmp report "unexpected data received" severity failure;
               smpls := smpls + 1;
               for i in 0 to 5 loop
                  cmp(8*i + 7 downto 8*i) := cmp(8*i + 7 downto 8*i) + x"06";
               end loop;
               if ( smpls = SPF_C ) then
                  cmp   := x"050403020100";
                  smpls := 0;
                  frms  := frms + 1;
               end if;

               if ( frms = NFRMS_EXP_C ) then
                  assert frms = NFRMS_EXP_C report "missing frames?" severity failure;
                  report "TEST PASSED";
                  run <= false;
               end if;
            end if;
         end if;
      end if;
   end process P_RCV;
   

   process (bclk) is
      variable cnt : natural :=0;
   begin
      if ( rising_edge( bclk ) ) then
         if ( cnt = 0 ) then
            pblrc <= not pblrc;
            cnt   := 23;
         else
            cnt   := cnt - 1;
         end if;
      end if;
   end process;

   U_DUT : entity work.I2SPlayback
      port map (
         usb2Clk  => usb2Clk,
         usb2Rst  => '0',
         usb2Rx   => USB2_RX_INIT_C,
         usb2EpIb => epOb,
 
         i2sBCLK  => bclk,
         i2sPBLRC => pblrc,
         i2sPBDAT => pbdat
      );
end architecture sim;
