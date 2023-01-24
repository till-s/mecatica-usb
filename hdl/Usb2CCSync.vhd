-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- simple CC synchronizer for single bits
-- use the companion Usb2CCSync.xdc file!

library ieee;
use     ieee.std_logic_1164.all;

entity Usb2CCSync is
   generic (
      STAGES_G : natural   := 2;
      INIT_G   : std_logic := '0'
   );
   port (
      clk      : in  std_logic;
      rst      : in  std_logic := '0';
      -- the signal being synchronized should *NOT* be
      -- the output a combinatorial (or in rare cases
      -- an incorrect value may be sampled). Sync to a
      -- register in the source clock domain!
      d        : in  std_logic;
      -- the 'tgl' output asserts when the last two stages
      -- differ; MUST use a minimum of 3 stages to use this!
      tgl      : out std_logic;
      q        : out std_logic
   );
end entity Usb2CCSync;

architecture Impl of Usb2CCSync is

   attribute ASYNC_REG  : string;

   signal ccSync        : std_logic_vector(STAGES_G - 1 downto 0) := (others => INIT_G);

   attribute ASYNC_REG  of ccSync : signal is "TRUE";

begin
   P_SYNC : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            ccSync <= (others => INIT_G);
         else
            ccSync <= ccSync(ccSync'left - 1 downto 0) & d;
         end if;
      end if;
   end process P_SYNC;

   G_TGL : if ( STAGES_G > 2 ) generate
      tgl <= ccSync(ccSync'left) xor ccSync(ccSync'left - 1);
   end generate G_TGL;

   G_ERR : if ( STAGES_G <= 2 ) generate
      tgl <= '0';
   end generate;

   q <= ccSync(ccSync'left);
end architecture Impl;
