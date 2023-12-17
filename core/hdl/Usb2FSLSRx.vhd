
-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;

entity Usb2FSLSRx is
   generic (
      CLK_FREQ_G     : real := 48.0E6
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic;
      -- synchronized into 'clk' domain by user
      j              : in  std_logic;
      se0            : in  std_logic;
      -- while txactive we can't update RXCMD
      txActive       : in  std_logic;
      -- sync detected -> EOP
      active         : out std_logic;
      valid          : out std_logic;
      data           : out std_logic_vector(7 downto 0);
      rxCmdVld       : out std_logic;
      suspended      : out std_logic;
      usb2Reset      : out std_logic;
      remWake        : in  std_logic := '0';
      sendK          : out std_logic
   );
end entity Usb2FSLSRx;

architecture rtl of Usb2FSLSRx is
   -- oversampling rate
   constant NSMPL_C     : integer := 4;

   constant TIME_SUSP_C : integer := integer( 3.0E-3 * CLK_FREQ_G );
   constant TIME_REMW_C : integer := integer( 5.0E-3 * CLK_FREQ_G ) - TIME_SUSP_C;
   constant TIME_SNDK_C : integer := integer( 1.5E-3 * CLK_FREQ_G );
   constant TIME_RST_C  : integer := integer( 3.0E-6 * CLK_FREQ_G );

   type StateType is (IDLE, SUSP, SNDK, SYNC, RUN, EOP, RESET);

   type RegType is record
      state            : StateType;
      jkSR             : std_logic_vector(NSMPL_C - 1 downto 0);
      dataSR           : std_logic_vector(7 downto 0);
      -- presc relies on NSMPL_C = 4!
      presc            : unsigned(1 downto 0);
      nstuff           : unsigned(3 downto 0);
      nbits            : unsigned(3 downto 0);
      err              : std_logic;
      errFlagged       : std_logic;
      clkAdj           : std_logic;
      se0Lst           : std_logic;
      active           : std_logic;
      suspended        : std_logic;
      timer            : integer range -1 to TIME_SUSP_C - 1;
      rxCmd            : std_logic_vector(7 downto 0);
      rxCmdLst         : std_logic_vector(7 downto 0);
      rxCmdVld         : std_logic_vector(1 downto 0);
      sendK            : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- start in EOP state waiting for SE0 and J to stabilize
      state            => EOP,
      jkSR             => (others => '1'),
      dataSR           => (others => '0'),
      presc            => (others => '0'),
      nstuff           => (others => '0'),
      nbits            => (others => '0'),
      err              => '0',
      errFlagged       => '0',
      clkAdj           => '0',
      se0Lst           => '0',
      active           => '0',
      suspended        => '0',
      timer            => TIME_RST_C - 1,
      -- initialize to invalid line state
      rxCmd            => x"03",
      rxCmdLst         => x"03",
      rxCmdVld         => (others => '0'),
      sendK            => '0'
   );

   signal r            : RegType := REG_INIT_C;
   signal rin          : RegType;

   signal clkrec       : std_logic_vector(NSMPL_C - 1 downto 0);

begin

   clkrec <= j & r.jkSR(r.jkSR'left) & r.jkSR(NSMPL_C/2 - 1 downto 0);

   P_COMB : process ( r, j, se0, clkrec, remWake ) is
      variable v : RegType;
   begin
      v            := r;
      v.jkSR       := j & r.jkSR(r.jkSR'left downto 1);
      v.clkAdj     := '0';
      v.se0Lst     := se0;
      v.rxCmdVld   := '0' & r.rxCmdVld(r.rxCmdVld'left downto 1);

      if ( r.timer >= 0 ) then
         v.timer := r.timer - 1;
      end if;

      if ( r.clkAdj = '0' ) then
         v.presc := r.presc - 1;
      end if;

      v.nbits(v.nbits'left) := '0';

      if ( r.presc = 0 ) then
         if ( r.rxCmd(1 downto 0) /= ULPI_RXCMD_LINE_STATE_SE0_C ) then
            if ( j = r.jkSR(r.jkSR'left) ) then
               v.rxCmd(ULPI_RXCMD_J_BIT_C) := j;
               v.rxCmd(ULPI_RXCMD_K_BIT_C) := not j;
            end if;
         end if;
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
            v.nbits      := (others => '0');
            v.active     := '0';
            v.err        := '0';
            v.errFlagged := '0';
            -- hold 'presc' in "00" state so that the line state
            -- is evaluated at every clock until sync is achieved
            v.presc  := (others => '0');
            if ( r.timer < 0 ) then
               v.state     := SUSP;
               v.suspended := '1';
               v.timer     := TIME_REMW_C - 1;
            end if;
            -- should not use the first j-k transition for syncing
            -- ('Note' in 7.1.14.1: ... the first SYNC field bit
            -- should not be used to synchronize the receiver...).
            if ( clkrec = "1100" ) then
               -- synchronize phase of the prescaler
               v.presc := to_unsigned(NSMPL_C - 1, r.presc'length);
               v.state := SYNC;
            end if;

         when SUSP =>
            -- resume signalling is ended by a low-speed EOP which should bring
            -- us back to IDLE
            if ( ( r.timer < 0 ) and ( remWake = '1' ) ) then
               v.state := SNDK;
               v.timer := TIME_SNDK_C - 1;
               v.sendK := '1';
            end if;

         when SNDK =>
            if ( r.timer < 0 ) then
               v.sendK := '0';
            end if;

         when SYNC =>
            v.nbits := (others => '0');
            if ( clkrec = "0000" and r.presc = 0 ) then
               -- KK part of sync pattern
               v.state  := RUN;
               v.active := '1';
            end if;

         when RUN =>
            if ( r.presc = 0 ) then
               case ( clkrec ) is
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
            if ( (se0 or r.se0Lst) = '0' and ( (j and r.jkSR(r.jkSR'left) and r.jkSR(r.jkSR'left-1)) = '1' ) ) then
               v.rxCmd(1 downto 0) := ULPI_RXCMD_LINE_STATE_FS_J_C;
               v.state             := IDLE;
               v.timer             := TIME_SUSP_C - 1;
            end if;
      end case;

      if ( v.err = '1' ) then
         -- while there is an error ulpi NXT must not be asserted
         v.nbits(v.nbits'left) := '0';
      end if;

      if ( ( se0 and r.se0Lst ) = '1' ) then
         v.suspended         := '0';
         v.rxCmd(1 downto 0) := ULPI_RXCMD_LINE_STATE_SE0_C;
         if ( r.state /= EOP and r.state /= RESET ) then
            v.timer := TIME_RST_C - 1;
            v.state := EOP;
         elsif ( r.timer < 0 ) then
            v.state := RESET;
         end if;
      end if;

      v.rxCmd( ULPI_RXCMD_RX_ACTIVE_BIT_C ) := v.active;
      v.rxCmd( ULPI_RXCMD_RX_ERROR_BIT_C  ) := ( v.err and not r.errFlagged );

      if ( txActive = '0' ) then
         if ( v.active = '1' ) then
            if ( (r.active = '0' ) and (r.rxCmdVld = "00") ) then
               -- active just became asserted and no RXCMD currently in progress -> assert NXT
               v.nbits(v.nbits'left) := '1';
            end if;
         elsif ( v.rxCmd /= r.rxCmdLst ) then
            v.rxCmdVld(0) := '1';
            if ( r.rxCmdVld(0) = '0' ) then
               -- DIR not currently asserted; need a turn-around cycle
               v.rxCmdVld(1) := '1';
            end if;
         end if;
         -- check if our rxcmd will actually be 'seen'
         if ( ( r.nbits(r.nbits'left) = '0' ) and ( ( r.active = '1' ) or (r.rxCmdVld = "01") ) ) then
            v.rxCmdLst   := r.rxCmd;
            -- ERROR is only asserted once; mark;
            if ( r.rxCmd( ULPI_RXCMD_RX_ERROR_BIT_C ) = '1' ) then
               v.errFlagged := '1';
            end if;
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

   data           <= r.dataSR when ( r.nbits(r.nbits'left) = '1' ) else r.rxCmd;
   valid          <= r.nbits(r.nbits'left);
   active         <= r.active;
   rxCmdVld       <= r.rxCmdVld(0);
   suspended      <= r.suspended;
   usb2Reset      <= '1' when r.state = RESET else '0';
   sendK          <= r.sendK;
   
end architecture rtl;
