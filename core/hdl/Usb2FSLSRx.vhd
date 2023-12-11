
-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity Usb2FSLSRx is
   generic (
      CLK_FREQ_G : real := 48.0E6
   );
   port (
      clk        : in  std_logic;
      rst        : in  std_logic;
      -- synchronized into 'clk' domain by user
      j          : in  std_logic;
      se0        : in  std_logic;
      -- sync detected -> EOP
      active     : out std_logic;
      valid      : out std_logic;
      data       : out std_logic_vector(7 downto 0)
   );
end entity Usb2FSLSRx;

architecture rtl of Usb2FSLSRx is
   -- oversampling rate
   constant NSMPL_C     : integer := 4;

   constant TIME_SUSP_C : integer := integer( 3.0E-3 * CLK_FREQ_G );
   constant TIME_RST_C  : integer := integer( 3.0E-6 * CLK_FREQ_G );

   type StateType is (IDLE, SUSP, SYNC, RUN, EOP, RESET);

   type RegType is record
      state            : StateType;
      jkSR             : std_logic_vector(NSMPL_C - 1 downto 0);
      dataSR           : std_logic_vector(7 downto 0);
      -- presc relies on NSMPL_C = 4!
      presc            : unsigned(1 downto 0);
      nstuff           : unsigned(3 downto 0);
      nbits            : unsigned(3 downto 0);
      err              : std_logic;
      clkAdj           : std_logic;
      se0Lst           : std_logic;
      active           : std_logic;
      timer            : integer range -1 to TIME_SUSP_C - 1;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state            => IDLE,
      jkSR             => (others => '1'),
      dataSR           => (others => '0'),
      presc            => (others => '0'),
      nstuff           => (others => '0'),
      nbits            => (others => '0'),
      err              => '0',
      clkAdj           => '0',
      se0Lst           => '0',
      active           => '0',
      timer            => TIME_SUSP_C - 1
   );

   signal r            : RegType := REG_INIT_C;
   signal rin          : RegType;

   signal CLKREC_F : std_logic_vector(NSMPL_C - 1 downto 0);

begin

   CLKREC_F <= j & r.jkSR(r.jkSR'left) & r.jkSR(NSMPL_C/2 - 1 downto 0);

   P_COMB : process ( r, j, se0, CLKREC_F ) is
      variable v : RegType;
   begin
      v        := r;
      v.jkSR   := j & r.jkSR(r.jkSR'left downto 1);
      v.clkAdj := '0';
      v.se0Lst := se0;

      if ( r.timer >= 0 ) then
         v.timer := r.timer - 1;
      end if;

      if ( r.clkAdj = '0' ) then
         v.presc := r.presc - 1;
      end if;

      v.nbits(v.nbits'left) := '0';

      if ( r.presc = 0 ) then
         if    ( j /= r.jkSR(0) ) then
            if ( r.nstuff(r.nstuff'left) /= '1' ) then
               v.dataSR := '0' & r.dataSR(r.dataSR'left downto 1);
               v.nbits  := r.nbits + 1;
            end if;
            v.nstuff    := to_unsigned(4, r.nstuff'length);
         else
            if ( r.nstuff(r.nstuff'left) = '1' ) then
               v.err    := '1';
            else
               v.dataSR := '1' & r.dataSR(r.dataSR'left downto 1);
               v.nbits  := r.nbits  + 1;
               v.nstuff := r.nstuff - 1;
            end if;
         end if;
      end if;

      case ( r.state ) is
         when IDLE =>
            v.nbits  := (others => '0');
            v.active := '0';
            v.err    := '0';
            if ( r.timer < 0 ) then
               v.state := SUSP;
            end if;
            -- should not use the first j-k transition for syncing
            -- ('Note' in 7.1.14.1: ... the first SYNC field bit
            -- should not be used to synchronize the receiver...).
            if ( CLKREC_F = "1100" ) then
               -- synchronize phase of the prescaler
               v.presc := to_unsigned(NSMPL_C - 1, r.presc'length);
               v.state := SYNC;
            end if;

         when SUSP =>
            -- resume signalling is ended by a low-speed EOP which should bring
            -- us back to IDLE

         when SYNC =>
            v.nbits := (others => '0');
            if ( CLKREC_F = "0000" and r.presc = 0 ) then
               -- KK part of sync pattern
               v.state  := RUN;
               v.active := '1';
            end if;

         when RUN =>
            if ( r.presc = 0 ) then
               case ( CLKREC_F ) is
                  -- still in sync or no transition
                  when "1100" | "0011" | "0000" | "1111" =>
                  -- our clock too fast
                  when "1000" | "0111" =>
                     v.clkAdj := '1';
                  -- our clock too slow
                  when "1110" | "0001" =>
                     v.presc  := to_unsigned(NSMPL_C - 2, r.presc'length);
                  -- sync error
                  when others =>
                     v.err    := '1';
                     v.nbits  := (others => '0');
               end case;
            end if;

         when EOP | RESET =>
            if ( r.state = RESET ) then
               v.nbits  := (others => '0');
               v.active := '0';
               v.err    := '0';
            end if;
            if ( (se0 or r.se0Lst) = '0' and ( (j and r.jkSR(r.jkSR'left)) = '1' ) ) then
               v.state := IDLE;
               v.timer := TIME_SUSP_C - 1;
            end if;
      end case;

      if ( ( se0 and r.se0Lst ) = '1' ) then
         if ( r.state /= EOP and r.state /= RESET ) then
            v.timer := TIME_RST_C - 1;
            v.state := EOP;
         elsif ( r.timer < 0 ) then
            v.state := RESET;
         end if;
      end if;

      rin     <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   data   <= r.dataSR;
   valid  <= r.nbits(r.nbits'left);
   active <= r.active;
end architecture rtl;
