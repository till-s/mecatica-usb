
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
      -- sampling clock must be 4 times outClk and phase-synchronous to outClk
      smplClk        : in  std_logic;
      smplRst        : in  std_logic;
      -- synchronized into 'smplClk' domain by user
      j              : in  std_logic;
      se0            : in  std_logic;

      -- output clock
      outClk         : in  std_logic;
      outRst         : in  std_logic;

      txActive       : in  std_logic;
      valid          : out std_logic;
      data           : out std_logic_vector(7 downto 0);
      active         : out std_logic;
      rxCmdVld       : out std_logic;
      suspended      : out std_logic;
      usb2Reset      : out std_logic;
      remWake        : in  std_logic := '0';
      sendK          : out std_logic
   );
end entity Usb2FSLSRx;

architecture rtl of Usb2FSLSRx is

   constant TIME_SUSP_C : integer := integer( 3.0E-3 * CLK_FREQ_G );
   constant TIME_REMW_C : integer := integer( 5.0E-3 * CLK_FREQ_G ) - TIME_SUSP_C;
   constant TIME_SNDK_C : integer := integer( 1.5E-3 * CLK_FREQ_G );
   constant TIME_RST_C  : integer := integer( 3.0E-6 * CLK_FREQ_G );

   type StateType is (RUN, SUSP, SNDK, EOP, RESET);

   type RegType is record
      state            : StateType;
      errFlagged       : std_logic;
      suspended        : std_logic;
      timer            : integer range -1 to TIME_SUSP_C - 1;
      sendK            : std_logic;
      rxCmdLst         : std_logic_vector(7 downto 0);
      rxCmdTrn         : std_logic;
      rxCmdVldLst      : std_logic;
      active           : std_logic;
      rxBlanked        : boolean;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- start in EOP state waiting for SE0 and J to stabilize
      state            => EOP,
      errFlagged       => '0',
      suspended        => '0',
      timer            => TIME_RST_C - 1,
      sendK            => '0',
      rxCmdLst         => x"03",
      rxCmdTrn         => '0',
      rxCmdVldLst      => '0',
      active           => '0',
      rxBlanked        => false
   );

   signal r            : RegType := REG_INIT_C;
   signal rin          : RegType;

   signal rxAct        : std_logic;
   signal rxActBlanked : std_logic;
   signal rxVld        : std_logic;
   signal rxErr        : std_logic;
   signal lineState    : std_logic_vector(1 downto 0);
   signal rxDat        : std_logic_vector(7 downto 0);
   signal rxCmdLoc     : std_logic_vector(7 downto 0) := (others => '0');
   signal nxt          : std_logic;

begin

   rxCmdLoc( ULPI_RXCMD_RX_ACTIVE_BIT_C ) <= rxActBlanked;
   rxCmdLoc( ULPI_RXCMD_RX_ERROR_BIT_C  ) <= rxErr and not r.errFlagged;
   rxCmdLoc( 1 downto 0                 ) <= lineState;

   P_COMB : process ( r, remWake, txActive, rxAct, rxErr, rxVld, rxCmdLoc, nxt ) is
      variable v           : RegType;
      variable rxCmdVldLoc : std_logic;
   begin
      v           := r;

      if ( r.timer >= 0 ) then
         v.timer := r.timer - 1;
      end if;

      nxt         <= '0';
      v.rxCmdTrn  := '0';
      rxCmdVldLoc := r.rxCmdTrn;

      if ( rxAct = '0' ) then
         v.errFlagged := '0';
      end if;

      case ( r.state ) is
         when RUN =>
            if ( r.timer < 0 ) then
               v.state     := SUSP;
               v.suspended := '1';
               v.timer     := TIME_REMW_C - 1;
            end if;

         when SUSP =>
            -- resume signalling is ended by a low-speed EOP which should bring
            -- us back to RUN
            if ( ( r.timer < 0 ) and ( remWake = '1' ) ) then
               v.state := SNDK;
               v.timer := TIME_SNDK_C - 1;
               v.sendK := '1';
            end if;

         when SNDK =>
            if ( r.timer < 0 ) then
               v.sendK := '0';
            end if;

         when EOP | RESET =>
            if ( rxCmdLoc(1 downto 0) = ULPI_RXCMD_LINE_STATE_FS_J_C ) then
               v.state := RUN;
               v.timer := TIME_SUSP_C - 1;
            end if;
      end case;

      if ( txActive = '1' ) then
         v.rxBlanked := true;
      end if;

      if ( rxCmdLoc(1 downto 0) = ULPI_RXCMD_LINE_STATE_SE0_C ) then
         v.suspended         := '0';
         v.rxBlanked         := false;
         if ( r.state /= EOP and r.state /= RESET ) then
            v.timer := TIME_RST_C - 1;
            v.state := EOP;
         elsif ( r.timer < 0 ) then
            v.state := RESET;
         end if;
      end if;

      if ( not v.rxBlanked ) then
         nxt      <= rxVld;
      end if;

      if ( txActive = '0' ) then

         -- while transmitting track line-state changes but blank rxActive
         if ( not v.rxBlanked ) then
            v.active := rxAct;
         end if;

         if ( v.active = '1' ) then
            if ( (r.active = '0' ) and (r.rxCmdVldLst = '0') and not r.rxBlanked ) then
               -- active just became asserted and no RXCMD currently in progress -> assert NXT
               nxt <= '1';
            end if;
         elsif ( rxCmdLoc /= r.rxCmdLst ) then
            rxCmdVldLoc := '1';
            if ( r.rxCmdTrn = '0' ) then
               -- DIR not currently asserted; need a turn-around cycle
               v.rxCmdTrn := '1';
            end if;
         end if;
         -- check if our rxcmd will actually be 'seen'
         if ( ( nxt = '0' ) and ( ( r.active = '1' ) or ( (not v.rxCmdTrn and rxCmdVldLoc) = '1') ) ) then
            v.rxCmdLst   := rxCmdLoc;
            -- ERROR is only asserted once; mark;
            if ( rxCmdLoc( ULPI_RXCMD_RX_ERROR_BIT_C ) = '1' ) then
               v.errFlagged := '1';
            end if;
         end if;

      end if;

      v.rxCmdVldLst := rxCmdVldLoc;
      rxCmdVld      <= rxCmdVldLoc;
      rxActBlanked  <= v.active;

      rin      <= v;
   end process P_COMB;

   P_SEQ : process ( outClk ) is
   begin
      if ( rising_edge( outClk ) ) then
         if ( outRst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   U_SHFT : entity work.Usb2FSLSRxBitShift
      port map (
         smplClk    => smplClk,
         smplRst    => smplRst,
         j          => j,
         se0        => se0,

         outClk     => outClk,
         outRst     => outRst,

         lineState  => lineState,
         err        => rxErr,
         active     => rxAct,
         valid      => rxVld,
         data       => rxDat
      );

   suspended      <= r.suspended;
   usb2Reset      <= '1' when r.state = RESET else '0';
   sendK          <= r.sendK;
   active         <= rxActBlanked;
   data           <= rxDat when nxt = '1' else rxCmdLoc;
   valid          <= nxt;
   
end architecture rtl;
