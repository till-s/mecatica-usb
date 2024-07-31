-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

-- decouple a valid/ready handshaked stream with registers
--    no combinatorial path from rdOb  -> rdyIb or vldOb
--    no combinatorial path from vldIb -> rdyIb or vldOb
--    no combinatorial path from datIb -> datOb
entity Usb2StrmBuf is
   generic (
      DATA_WIDTH_G : natural := 8
   );
   port (
      clk          : in  std_logic;
      rst          : in  std_logic := '0';
      vldIb        : in  std_logic;
      rdyIb        : out std_logic;
      datIb        : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      vldOb        : out std_logic;
      rdyOb        : in  std_logic;
      datOb        : out std_logic_vector(DATA_WIDTH_G - 1 downto 0)
   );
end entity Usb2StrmBuf;

architecture rtl of Usb2StrmBuf is
   -- output buffer
   signal bufVld   : std_logic := '0';
   signal buf      : std_logic_vector(DATA_WIDTH_G - 1 downto 0) := (others => '0');
   -- overflow/temp buffer
   signal tmpVld   : std_logic := '0';
   signal tmp      : std_logic_vector(DATA_WIDTH_G - 1 downto 0) := (others => '0');

   signal rdyIbLoc : std_logic;

begin

   -- can accept data when we have space in either buffer
   rdyIbLoc <= (not bufVld or not tmpVld);

   P_BUF : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            bufVld <= '0';
            tmpVld <= '0';
         else
            if ( rdyIbLoc = '1' ) then
               -- buffer data
               bufVld <= vldIb;
               buf    <= datIb;
            end if;
            if ( tmpVld = '0' ) then
               -- catch in overflow buffer if not ready
               tmpVld <= (bufVld and not rdyOb);
               tmp    <= buf;
            elsif ( rdyOb = '1' ) then
               tmpVld <= '0';
            end if;
         end if;
      end if;
   end process P_BUF;

   P_COMB : process ( tmp, buf, tmpVld ) is
   begin
      if ( tmpVld = '1' ) then
         datOb <= tmp;
      else
         datOb <= buf;
      end if;
   end process P_COMB;

   vldOb <= ( bufVld or tmpVld );
   rdyIb <= rdyIbLoc;

end architecture rtl;
