-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Mailbox synchronizer.
-- A token is passed between two clock domains. The current
-- holder of the token latches data from and posts data to
-- the other side.
library ieee;
use     ieee.std_logic_1164.all;

entity Usb2MboxSync is
   generic (
      STAGES_A2B_G : natural := 2;
      STAGES_B2A_G : natural := 2;
      DWIDTH_A2B_G : natural := 0;
      DWIDTH_B2A_G : natural := 0;
      -- whether to register outputs
      OUTREG_A2B_G : boolean := false;
      OUTREG_B2A_G : boolean := false
   );
   port (
      clkA     : in  std_logic;
      cenA     : out std_logic;
      dinA     : in  std_logic_vector(DWIDTH_A2B_G - 1 downto 0) := (others => '0');
      douA     : out std_logic_vector(DWIDTH_B2A_G - 1 downto 0);

      clkB     : in  std_logic;
      cenB     : out std_logic;
      dinB     : in  std_logic_vector(DWIDTH_B2A_G - 1 downto 0) := (others => '0');
      douB     : out std_logic_vector(DWIDTH_A2B_G - 1 downto 0)
   );
end entity Usb2MboxSync;

architecture Impl of Usb2MboxSync is

   attribute KEEP       : string;

   signal trigA         : std_logic := '0';
   signal trigB         : std_logic := '0';

   signal monA          : std_logic;
   signal monB          : std_logic;

   signal cenALoc       : std_logic;
   signal cenBLoc       : std_logic;

   signal douA_r        : std_logic_vector(douA'range) := (others => '0');
   signal douB_r        : std_logic_vector(douB'range) := (others => '0');
   signal cenA_r        : std_logic := '0';
   signal cenB_r        : std_logic := '0';

begin

   -- create a block to help write constraints
   B_Usb2MboxSync : block is

      signal a2bData       : std_logic_vector(DWIDTH_A2B_G - 1 downto 0) := (others => '0');
      signal b2aData       : std_logic_vector(DWIDTH_B2A_G - 1 downto 0) := (others => '0');

      attribute KEEP of a2bData : signal is "TRUE";
      attribute KEEP of b2aData : signal is "TRUE";

   begin

      U_SYNC_A2B : entity work.Usb2CCSync
         generic map (
            STAGES_G => STAGES_A2B_G
         )
         port map (
            clk      => clkB,
            d        => trigA,
            q        => monB
         );

      U_SYNC_B2A : entity work.Usb2CCSync
         generic map (
            STAGES_G => STAGES_B2A_G
         )
         port map (
            clk      => clkA,
            d        => trigB,
            q        => monA
         );

      cenALoc <= trigA xor  monA;
      cenBLoc <= trigB xnor monB;

      P_A : process ( clkA ) is
      begin
         if ( rising_edge( clkA ) ) then
            trigA     <= monA;
            if ( cenALoc = '1' ) then
               a2bData <= dinA;
               douA_r  <= b2aData;
            end if;
            cenA_r <= cenALoc;
         end if;
      end process P_A;

      G_OUTREGA : if ( OUTREG_B2A_G ) generate
         douA <= douA_r;
         cenA <= cenA_r;
      end generate G_OUTREGA;

      G_NO_OUTREGA : if ( not OUTREG_B2A_G ) generate
         douA <= b2aData;
         cenA <= cenALoc;
      end generate G_NO_OUTREGA;

      P_B : process ( clkB ) is
      begin
         if ( rising_edge( clkB ) ) then
            trigB     <= not monB;
            if ( cenBLoc = '1' ) then
               b2aData <= dinB;
               douB_r  <= a2bData;
            end if;
            cenB_r <= cenBLoc;
         end if;
      end process P_B;

      G_OUTREGB : if ( OUTREG_A2B_G ) generate
         douB <= douB_r;
         cenB <= cenB_r;
      end generate G_OUTREGB;

      G_NO_OUTREGB : if ( not OUTREG_A2B_G ) generate
         douB <= a2bData;
         cenB <= cenBLoc;
      end generate G_NO_OUTREGB;

   end block B_Usb2MboxSync;

end architecture Impl;
