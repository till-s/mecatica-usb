-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;

entity Usb2FSLSRxBitShift is
   port (
      -- sampling clock must be 4 times outClk and phase-synchronous to outClk
      smplClk        : in  std_logic;
      smplRst        : in  std_logic;
      -- synchronized into 'smplClk' domain by user
      j              : in  std_logic;
      se0            : in  std_logic;

      -- clocking of output data
      outClk         : in  std_logic;
      outRst         : in  std_logic;

      lineState      : out std_logic_vector(1 downto 0) := "11";
      err            : out std_logic                    := '0';
      active         : out std_logic                    := '0';
      valid          : out std_logic                    := '0'; -- qualifies 'data'
      data           : out std_logic_vector(7 downto 0) := (others => '0')
   );
end entity Usb2FSLSRxBitShift;

architecture rtl of Usb2FSLSRxBitShift is
   -- oversampling rate
   constant NSMPL_C     : integer := 4;

   type StateType is (IDLE, SYNC, RUN, EOP);

   type RegType is record
      state            : StateType;
      jkSR             : std_logic_vector(NSMPL_C - 1 downto 0);
      dataSR           : std_logic_vector(7 downto 0);
      outReg           : std_logic_vector(7 downto 0);
      outVld           : std_logic;
      -- presc relies on NSMPL_C = 4!
      presc            : unsigned(1 downto 0);
      nstuff           : unsigned(3 downto 0);
      nbits            : unsigned(3 downto 0);
      err              : std_logic;
      clkAdj           : std_logic;
      se0Lst           : std_logic;
      lineState        : std_logic_vector(1 downto 0);
      active           : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- start in EOP state waiting for SE0 and J to stabilize
      state            => EOP,
      jkSR             => (others => '1'),
      dataSR           => (others => '0'),
      outReg           => (others => '0'),
      outVld           => '0',
      presc            => (others => '0'),
      nstuff           => (others => '0'),
      nbits            => (others => '0'),
      err              => '0',
      clkAdj           => '0',
      se0Lst           => '0',
      lineState        => (others => '0'),
      active           => '0'
   );

   signal r            : RegType := REG_INIT_C;
   signal rin          : RegType;
   signal outAck       : std_logic := '0';
   signal rxAct        : std_logic := '0';

   signal clkrec       : std_logic_vector(NSMPL_C - 1 downto 0);
   signal se0Seen      : boolean   := false;
   signal jSeen        : boolean   := false;
   signal lineStateLoc : std_logic_vector(1 downto 0);

begin

   clkrec <= j & r.jkSR(r.jkSR'left) & r.jkSR(NSMPL_C/2 - 1 downto 0);

   P_COMB : process ( r, j, se0, clkrec, outAck ) is
      variable v : RegType;
   begin
      v            := r;
      v.jkSR       := j & r.jkSR(r.jkSR'left downto 1);
      v.clkAdj     := '0';
      v.se0Lst     := se0;

      if ( r.clkAdj = '0' ) then
         v.presc := r.presc - 1;
      end if;

      v.nbits(v.nbits'left) := '0';

      if ( outAck = '1' ) then
         v.outVld := '0';
      end if;

      if ( r.presc = 0 ) then
         if ( j = r.jkSR(r.jkSR'left) ) then
            v.lineState(0) := j;
            v.lineState(1) := not j;
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
         if ( r.outVld = '0' ) then
            v.outReg := v.dataSR;
         end if;
         
         if ( ( not v.err and v.nbits(v.nbits'left) )= '1' ) then
            v.outVld := '1';
         end if;
      end if;

      case ( r.state ) is
         when IDLE =>
            v.nbits      := (others => '0');
            v.err        := '0';
            -- hold 'presc' in "00" state so that the line state
            -- is evaluated at every clock until sync is achieved
            v.presc  := (others => '0');
            -- should not use the first j-k transition for syncing
            -- ('Note' in 7.1.14.1: ... the first SYNC field bit
            -- should not be used to synchronize the receiver...).
            if ( clkrec = "1100" ) then
               -- synchronize phase of the prescaler
               v.presc := to_unsigned(NSMPL_C - 1, r.presc'length);
               v.state := SYNC;
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

         when EOP =>
            if ( (se0 or r.se0Lst) = '0' and ( (j and r.jkSR(r.jkSR'left)) = '1' ) ) then
               v.err       := '0';
               v.lineState := "01";
               if ( r.jkSR(r.jkSR'left - 1 downto 1) = "11" ) then
                  v.state  := IDLE;
               end if;
            end if;
      end case;

      if ( ( se0 and r.se0Lst ) = '1' ) then
         v.active    := '0';
         v.lineState := "00";
         v.state     := EOP;
      end if;

      err          <= v.err;
      lineStateLoc <= v.lineState;
      rin          <= v;
   end process P_COMB;

   P_SEQ : process ( smplClk ) is
   begin
      if ( rising_edge( smplClk ) ) then
         if ( smplRst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   P_OUT : process ( outClk ) is
   begin
      if ( rising_edge( outClk ) ) then
         if ( outRst = '1' ) then
            outAck    <= '0';
            rxAct     <= '0';
            se0Seen   <= false;
            jSeen     <= false;
         else
            outAck    <= '0';
            if ( r.active = '1' ) then
               rxAct  <= '1';
            end if;
            if ( rxAct = '1' ) then
               if ( lineStateLoc = "00" ) then
                  se0Seen <= true;
               end if;
               if ( se0Seen and (lineStateLoc = "01" ) ) then
                  jSeen   <= true;
               end if;
               if ( jSeen ) then
                  rxAct   <= '0';
                  se0Seen <= false;
                  jSeen   <= false;
               end if;
            end if;
            if ( r.outVld = '1' ) then
               outAck <= '1';
               data   <= r.outReg;
            end if;
            rxAct <= r.active;
         end if;
      end if;
   end process P_OUT;

   lineState <= lineStateLoc;
   valid     <= outAck;
   active    <= rxAct;

end architecture rtl;
