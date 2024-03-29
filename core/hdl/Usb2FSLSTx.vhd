-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;

entity Usb2FSLSTx is
   port (
      clk            : in  std_logic;
      rst            : in  std_logic;
      -- TX data
      data           : in  std_logic_vector(7 downto 0);
      -- handshake
      stp            : in  std_logic;
      nxt            : out std_logic;
      -- serial output
      j              : out std_logic;
      se0            : out std_logic;
      -- alternate output (vp = j)
      vm             : out std_logic;
      -- send K (signal remote wakeup)
      sendK          : in  std_logic := '0';
      -- status
      active         : out std_logic;
      -- drive outputs
      oe             : out std_logic
   );
end entity Usb2FSLSTx;

architecture rtl of Usb2FSLSTx is
   -- oversampling rate
   constant NSMPL_C     : integer := 4;

   constant SYNC_C      : std_logic_vector(7 downto 0) := x"80";

   -- count terminates at -1
   constant NSTUFF_C    : unsigned(3 downto 0) := to_unsigned(6 - 1, 4);

   type StateType is (IDLE, SYNC, RUN, EOP);

   type RegType is record
      state            : StateType;
      dataSR           : std_logic_vector(7 downto 0);
      -- presc relies on NSMPL_C = 4!
      phase            : std_logic_vector(7 downto 0);
      nstuff           : unsigned(3 downto 0);
      j                : std_logic;
      vm               : std_logic;
      se0              : std_logic_vector(1 downto 0);
      nxt              : std_logic;
      rdy              : std_logic;
      act              : std_logic;
      stp              : std_logic;
      stpDat           : std_logic;
      frcStuffErr      : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state            => IDLE,
      dataSR           => SYNC_C,
      phase            => (others => '0'),
      nstuff           => NSTUFF_C,
      j                => '1',
      vm               => '0',
      se0              => "10",
      nxt              => '0',
      rdy              => '0',
      act              => '0',
      stp              => '0',
      stpDat           => '0',
      frcStuffErr      => '0'
   );

   signal r            : RegType := REG_INIT_C;
   signal rin          : RegType;
   signal syn          : std_logic;

begin

   P_COMB : process ( r, data, stp, sendK ) is
      variable v : RegType;
   begin
      v        := r;

      v.nxt    := '0';
      -- read next byte or STP in the cycle following NXT
      v.rdy    := r.nxt;

      syn      <= '1';
      oe       <= '1';

      -- must always evaluate 'stp' during the 'rdy' cycle --
      -- the 'phase' may not have changed due to bit-stuffing...
      if ( ( r.rdy and stp ) = '1' ) then
         v.stp    := '1';
         v.stpDat := data(7);
      end if;

      case ( r.state ) is

         when IDLE =>
            v.nstuff      := NSTUFF_C;
            v.phase       := "01000000";
            v.dataSR      := "00" & SYNC_C(SYNC_C'left downto 2);
            v.frcStuffErr := '0';
            v.stp         := '0';

            if ( sendK = '1' ) then
               syn        <= '0';
            elsif ( data(7 downto 4) = ULPI_TXCMD_TX_C ) then
               syn      <= '0'; -- already send 1st bit during this cycle to reduce latency
               v.j      := '1';
               v.act    := '1';
               v.state  := SYNC;
            else
               oe       <= '0';
            end if;

         when SYNC | RUN =>
            if ( (not r.frcStuffErr and r.nstuff(r.nstuff'left) ) = '1' ) then
               v.j      := not r.j;
               v.nstuff := NSTUFF_C;
            else
               -- bit-stuffing
               if ( r.dataSR(0) = '0' ) then
                  v.j      := not r.j;
                  v.nstuff := NSTUFF_C;
               else
                  v.nstuff := r.nstuff - 1;
               end if;

               -- micro-state machine
               v.phase  := r.phase(0) & r.phase(r.phase'left downto 1);
               v.dataSR := '0' & r.dataSR(r.dataSR'left downto 1);

               if ( ( r.state = RUN ) and (r.frcStuffErr = '0') ) then
                  v.nxt := r.phase(3);
               end if;
               if ( r.phase(1) = '1' ) then
                  if ( r.state = SYNC ) then
                     v.dataSR := not data(3 downto 0) & data(3 downto 0);
                     v.state  := RUN;
                  else
                     v.dataSR := data;
                     -- evaluate v.stp; it may have been asserted during *this* cycle
                     if ( ( r.frcStuffErr or v.stp ) = '1' ) then
                        if ( v.stpDat = '0' ) then
                           v.state := EOP;
                           v.act   := '0';
                        else
                           v.frcStuffErr := '1';
                           v.dataSR      := (others => '1');
                        end if;
                        v.stpDat := '0';
                     end if;
                  end if;
               end if;
            end if;

         when EOP =>
            -- bit-stuffing must be performed even after the last byte.
            -- Had a host-controller not accepting the message if this was not
            -- done...
            if ( (not r.frcStuffErr and r.nstuff(r.nstuff'left) ) = '1' ) then
               v.j      := not r.j;
               v.nstuff := NSTUFF_C;
            else
               -- entering this state the last j/k from the shift operations
               -- is active.
               v.se0 := not r.se0(0) & r.se0(1);
               v.j   := not r.se0(1);

               if ( r.se0 = "00" ) then
                  -- se0 is loaded with "10" which is OK
                  v.state := IDLE;
               end if;
            end if;

      end case;

      v.vm := not v.j;
      if ( v.se0(0) = '1' ) then
         v.vm := '0';
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

   nxt     <= r.nxt;
   j       <= r.j  and syn;
   vm      <= r.vm or  (not syn and not r.se0(0));
   se0     <= r.se0(0);
   active  <= r.act;

end architecture rtl;
