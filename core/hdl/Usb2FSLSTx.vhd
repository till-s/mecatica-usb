
-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;

entity Usb2FSLSTx is
   generic (
      CLK_FREQ_G     : real := 48.0E6
   );
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
      -- status
      active         : out std_logic
   );
end entity Usb2FSLSTx;

architecture rtl of Usb2FSLSTx is
   -- oversampling rate
   constant NSMPL_C     : integer := 4;

   constant SYNC_C      : std_logic_vector(7 downto 0) := x"80";

   type StateType is (IDLE, SYNC, RUN, EOP);

   type RegType is record
      state            : StateType;
      dataSR           : std_logic_vector(7 downto 0);
      -- presc relies on NSMPL_C = 4!
      presc            : unsigned(1 downto 0);
      nstuff           : unsigned(3 downto 0);
      nbits            : unsigned(3 downto 0);
      j                : std_logic;
      se0              : std_logic_vector(1 downto 0);
      nxt              : std_logic;
      rdy              : std_logic;
      act              : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state            => IDLE,
      dataSR           => SYNC_C,
      presc            => (others => '0'),
      nstuff           => (others => '0'),
      nbits            => (others => '0'),
      j                => '1',
      se0              => "10",
      nxt              => '0',
      rdy              => '0',
      act              => '0'
   );

   signal r            : RegType := REG_INIT_C;
   signal rin          : RegType;

begin

   P_COMB : process ( r, data, stp ) is
      variable v : RegType;
   begin
      v        := r;

      v.presc  := r.presc - 1;

      v.nxt    := '0';
      -- read next byte or STP in the cycle following NXT
      v.rdy    := r.nxt;

      case ( r.state ) is
         when IDLE =>
            v.nstuff := to_unsigned(4, r.nstuff'length);
            v.nbits  := to_unsigned(8-3-1, v.nbits'length);
            v.presc  := to_unsigned(NSMPL_C - 1, v.presc'length);
            v.dataSR := '0' & SYNC_C(SYNC_C'left downto 1);
            if ( data(7 downto 4) = ULPI_TXCMD_TX_C ) then
               v.j      := '0';
               v.act    := '1';
               v.state  := SYNC;
            end if;

         when SYNC | RUN =>
            if ( r.presc = 0 ) then
               if ( r.nstuff(r.nstuff'left) = '1' ) then
                  v.j      := not r.j;
                  v.nstuff := to_unsigned(4, r.nstuff'length); 
               else
                  if ( r.dataSR(0) = '0' ) then
                     v.j      := not r.j;
                  else
                     v.nstuff := r.nstuff - 1;
                  end if;
                  if ( r.nbits(r.nbits'left) = '1' ) then
                     if ( r.state = SYNC ) then
                        v.dataSR := not data(3 downto 0) & data(3 downto 0);
                        v.nbits  := to_unsigned(8-3, v.nbits'length);
                        v.state  := RUN;
                     else
                        v.nxt := '1';
                     end if;
                  else
                     v.dataSR := '0' & r.dataSR(r.dataSR'left downto 1);
                     v.nbits  := r.nbits - 1;
                  end if;
               end if;
            end if;

         when EOP =>
            if ( r.presc = 0 ) then
               -- enter with se0 = "10"; -> "11" -> "01" -> "00"
               v.se0 := not r.se0(0) & r.se0(1);
               v.j   := not r.se0(1);

               if ( r.se0 = "00" ) then
                  -- se0 is loaded with "10" which is OK
                  v.state := IDLE;
                  v.act   := '0';
               end if;
            end if;

      end case;

      if ( r.rdy = '1' ) then
         if ( stp = '1' ) then
            v.state  := EOP;
         else
            v.dataSR := data;
            v.nbits  := to_unsigned(8-3, v.nbits'length);
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

   nxt     <= r.nxt;
   j       <= r.j;
   se0     <= r.se0(0);
   active  <= r.act;

end architecture rtl;
