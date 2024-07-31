-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity Usb2StrmBufTb is
end entity Usb2StrmBufTb;

architecture sim of Usb2StrmBufTb is
   signal clk   : std_logic := '0';
   signal run   : boolean   := true;
   signal vldIb : std_logic := '0';
   signal rdyIb : std_logic;
   signal datIb : std_logic_vector(31 downto 0);
   signal vldOb : std_logic;
   signal rdyOb : std_logic := '0';
   signal datOb : std_logic_vector(31 downto 0) := (others => '0');
   signal valIb : integer   := 0;
   signal valOb : integer   := 0;
begin
   P_CLK : process is
   begin
      wait for 10 ns;
      clk <= not clk;
      if ( not run ) then wait; end if;
   end process P_CLK;

   P_SRC : process (clk) is
      variable s1    : integer := 33;
      variable s2    : integer := 88;
      variable locnt : natural := 0; 
      variable r     : real;
   begin
      if ( rising_edge( clk ) ) then
         if ( ( vldIb and rdyIb ) = '1' ) then
            valIb <= valIb + 1;
            uniform( s1, s2, r );
            locnt := natural( round( 10.0 / (1.0 + 10.0*r) ) );
            if ( locnt /= 0 ) then
               vldIb <= '0';
            end if;
         end if;
         if ( locnt > 0 ) then 
            locnt := locnt - 1;
         else
            vldIb <= '1';
         end if;
      end if;
   end process P_SRC;

   P_SNK : process (clk) is
      variable s1    : integer := 133;
      variable s2    : integer := 388;
      variable locnt : natural := 0; 
      variable r     : real;
      variable exp   : natural := 0;
   begin
      if ( rising_edge( clk ) ) then
         if ( ( vldOb and rdyOb ) = '1' ) then
            assert valOb = exp report "output data mismatch" severity failure;
            if ( valOb = 30000 ) then
               report "Test PASSED";
               run <= false;
            end if;
            exp := exp + 1;
            uniform( s1, s2, r );
            locnt := natural( round( 10.0 / (1.0 + 10.0*r) ) );
            if ( locnt /= 0 ) then
               rdyOb <= '0';
            end if;
         end if;
         if ( locnt > 0 ) then 
            locnt := locnt - 1;
         else
            rdyOb <= '1';
         end if;
      end if;
   end process P_SNK;

   datIb <= std_logic_vector( to_unsigned( valIb, datIb'length ) );
   valOb <= to_integer( unsigned( datOb ) );

   U_DUT : entity work.Usb2StrmBuf
      generic map (
         DATA_WIDTH_G => datIb'length
      )
      port map (
         clk          => clk,
         vldIb        => vldIb,
         rdyIb        => rdyIb,
         datIb        => datIb,
         vldOb        => vldOb,
         rdyOb        => rdyOb,
         datOb        => datOb
      );
end architecture sim;
