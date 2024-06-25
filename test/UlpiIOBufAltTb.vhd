-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;

entity UlpiIOBufAltTb is
end entity UlpiIOBufAltTb;

architecture sim of UlpiIOBufAltTb is
   signal clk     : std_logic := '0';
   signal nxt     : std_logic := '0';
   signal stp     : std_logic := '0';
   signal dou     : std_logic_vector(7 downto 0);
   signal txVld   : std_logic := '0';
   signal txRdy   : std_logic := '0';
   signal txDat   : std_logic_vector(7 downto 0) := (others => '0');

   signal cnt     : integer   := 1;
   signal cmp     : integer   := 1;
   signal run     : boolean   := true;
   signal ulpiIb  : UlpiIbType;
   signal ulpiOb  : UlpiObType;
begin

   txDat <= std_logic_vector( to_unsigned( cnt mod 256, 8 ) );

   P_CLK : process is
   begin
      if ( not run ) then wait; end if;
      wait for 5 us;
      clk <= not clk;
   end process P_CLK;   

   P_DRV : process (clk) is
      variable s1 : positive := 345;
      variable s2 : positive := 666;
      variable rn : real;
   begin
      if ( rising_edge( clk ) ) then

         if ( cnt = 1 ) then
            txVld <= '1';
         end if;

         if ( (txVld and txRdy) = '1' ) then
            cnt <= cnt + 1;
            if ( cnt = 100 ) then
               txVld <= '0';
            end if;
         end if;

         if ( dou /= x"00" ) then
            uniform(s1, s2 ,rn);
            if ( rn > 0.5 ) then
               nxt <= not nxt;
            end if;
         end if;

         if ( nxt = '1' ) then
            assert to_integer( unsigned(dou) ) = cmp report "data mismatch" severity failure;
            if ( cmp = 100 ) then
               nxt <= '0';
            end if;
            cmp <= cmp + 1;
         end if;

         if ( stp = '1' ) then
            assert ( cmp = 101 ) report "end count mismatch" severity failure;
            run <= false;
            report "TEST PASSED";
         end if;

      end if;
   end process P_DRV;

   ulpiIb.nxt <= nxt;
   ulpiIb.dir <= '0';
   ulpiIb.dat <= (others => '0');
   ulpiIb.stp <= ulpiOb.stp;
   stp        <= ulpiOb.stp;
   dou        <= ulpiOb.dat;

   U_DUT : entity work.UlpiIOBuf
      port map (
         ulpiClk     => clk,
         genStp      => '1',
         regOpr      => '0',
         frcStp      => '0',
         waiNxt      => '0',
         txVld       => txVld,
         txRdy       => txRdy,
         txDat       => txDat,
         txErr       => open,
         txSta       => '0',
         ulpiRx      => open,
         ulpiIb      => ulpiIb,
         ulpiOb      => ulpiOb
      );

end architecture sim;
