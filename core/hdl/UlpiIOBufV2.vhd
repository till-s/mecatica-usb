-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;

use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;

entity UlpiIOBuf is
   generic (
      MARK_DEBUG_G    : boolean := true;
      -- whether to request the NXT register to be placed in a IOB;
      -- this is good in ulpi output-clock mode but may be disadvantageous
      -- in ulpi input-clock mode; if a phase-shifted clock is used
      -- (for timing reasons) then putting the register into the fabric
      -- gives the tool freedom to tweak hold-timing.
      ULPI_NXT_IOB_G  : boolean := true;
      -- whether to request the DIR register to be placed in a IOB;
      -- (see additional comments above)
      ULPI_DIR_IOB_G  : boolean := true;
      -- whether to request the data input registers to be placed in IOB;
      -- (see additional comments above)
      ULPI_DIN_IOB_G  : boolean := true;
      -- whether STP must not be asserted while NXT is low
      -- during transmit (USB3340) - bad because it requires
      -- combinatorials after the STP register which means
      -- this register cannot be placed into IOB :-(
      -- The 3340 datasheet claims that STP must not be
      -- asserted while NXT is low -- however, experiments
      -- indicated that this actually caused malfunction but
      -- asserting STP (after the last data are consumed)
      -- regardless of NXT being hi or lo worked as it should.
      ULPI_STP_MODE_G : UlpiStpModeType := NORMAL
   );
   port (
      ulpiClk    : in  std_logic;

      -- whether to generate a stop after transmitting
      -- (must be suppressed in the case of a register read)
      genStp     : in  std_logic;
      -- whether this is a register operation (turn-around cycle
      -- must be treated differently)
      regOpr     : in  std_logic;
      -- whether NXT must be asserted during STP (UNUSED/unsupporte by this architecture)
      waiNxt     : in  std_logic;
      -- force stop (if PHY has dir asserted)
      frcStp     : in  std_logic;

      -- TX interface
      txVld      : in  std_logic;
      txDat      : in  std_logic_vector(7 downto 0);
      txRdy      : out std_logic;
      txDon      : out std_logic;
      txErr      : out std_logic;
      txSta      : in  std_logic := '1';

      -- RX interface
      ulpiRx     : out UlpiRxType;

      -- ULPI interface; route directly to IOBUFs
      ulpiIb     : in  UlpiIbType;
      ulpiOb     : out UlpiObType
   );
end entity UlpiIOBuf;

--   dir   nxt nxtr  dou   douvld  buf   bufVld  txVld   txRdy   txD
--    0     0   0     0      0                     1       1      d0
--    0     0   0     d0     1                     1       1      d1
--    0     1   0     d0     1     d1       1      1       0      d1
--    0     1   1     d1     1      x       0      1       1      d2
--    0     0   1     d2     1              0      1       1      d3   
--    0     1   0     d2     1      d3             1              d4
--    0         1     d3
architecture rtl of UlpiIOBuf is

   attribute IOB        : string;
   attribute MARK_DEBUG : string;

   type RegType is record
      buf    : std_logic_vector(7 downto 0);
      douVld : std_logic;
      bufVld : std_logic;
      trn    : std_logic;
      txBsy  : std_logic;
      sta    : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      buf    => (others => '0'),
      douVld => '0',
      bufVld => '0',
      trn    => '0',
      txBsy  => '0',
      sta    => '0'
   );

   signal r     : RegType                      := REG_INIT_C;
   signal rin   : RegType;

   signal din_r : std_logic_vector(7 downto 0) := (others => '0');
   signal dir_r : std_logic                    := '1';
   signal nxt_r : std_logic                    := '0';
   signal stp_i : std_logic                    := '0';
   signal stp_r : std_logic                    := '0';
   signal stpin : std_logic                    := '0';
   signal dou_r : std_logic_vector(7 downto 0) := (others => '0');
   signal douin : std_logic_vector(7 downto 0) := (others => '0');

   attribute IOB of stp_r  : signal is "TRUE";
   attribute IOB of dou_r  : signal is "TRUE";
   attribute IOB of din_r  : signal is toStr( ULPI_DIN_IOB_G );
   attribute IOB of dir_r  : signal is toStr( ULPI_DIR_IOB_G );
   attribute IOB of nxt_r  : signal is toStr( ULPI_NXT_IOB_G );
   attribute IOB of stp_i  : signal is toStr( ULPI_NXT_IOB_G );

   attribute MARK_DEBUG of r     : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of din_r : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of dir_r : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of nxt_r : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of stp_i : signal is toStr( MARK_DEBUG_G );

begin

   assert ULPI_STP_MODE_G = NORMAL report "other ULPI_STOP_MODE settings not implemented" severity failure;

   P_COMB : process (r, dou_r, stp_r, dir_r, ulpiIb, txVld, txDat, frcStp, txSta, genStp, regOpr) is
      variable v : RegType;
   begin
      v     := r;
      douin <= dou_r;

      v.trn := ulpiIb.dir xor dir_r;

      stpin <= frcStp;
      v.sta := '0';

      -- apparently (found with logic-analyzer) the USB3340 can still
      -- send RXCMD-interrupts even after we put a TXCMD on the bus; it seems
      -- they only consider a TX 'started' once they ack with 'nxt'.
      -- While the ULPI spec says that TX and RX have higher priority than
      -- RXCMD it does not specify the precise starting point of a TX...
      -- OTOH, the spec says that a register operation has lower priority
      -- than RXCMD which may preempt a register op.
      -- Once txBsy is set we start checking for ( txBsy and dir ) to detect
      -- an abort condition.
      if ( ( r.douVld and not ulpiIb.dir and ( ulpiIb.nxt or regOpr ) ) = '1' ) then
         v.txBsy := '1';
      end if;

      if ( txVld = '1' ) then
         if ( r.douVld = '0' ) then
            v.douVld := '1';
            douin    <= txDat;
         elsif ( ulpiIb.nxt = '1' ) then
            if ( r.bufVld = '1' ) then
               douin    <= r.buf;
               v.bufVld := '0';
            else
               douin    <= txDat;
            end if;
         elsif ( r.bufVld = '0' ) then
            v.bufVld := '1';
            v.buf    := txDat;
         end if;
      else
         if ( ulpiIb.nxt = '1' ) then
            if ( r.bufVld = '1' ) then
               v.bufVld := '0';
               douin    <= r.buf;
            elsif ( r.douVld = '1' ) then
               if ( regOpr = '1' ) then
                  -- turn-around during STP may be taken over
                  -- by a back-to-back RX operation and this is
                  -- not an error; the PHY does not use any data/status
                  -- send by the link during STP (3.8.3.3, fig. 27)
                  v.douVld := '0';
                  douin    <= (others => '0');
                  stpin    <= genStp;
                  v.sta    := genStp;
               elsif ( r.sta = '0' ) then
                  -- append status + STP cycle
                  douin    <= (others => txSta);
                  stpin    <= '1';
                  v.sta    := '1'; 
               end if;
            end if;
         end if;
      end if;

      -- status cycle done
      if ( r.sta = '1' ) then
         v.douVld := '0';
         douin    <= (others => '0');
      end if;

      txErr <= '0';
      txDon <= '0';

      if ( ( r.txBsy and not r.douVld ) = '1' ) then
         v.txBsy  := '0';
         txDon    <= '1';
      end if;

      if ( ( r.txBsy and dir_r ) = '1' ) then
         txErr    <= '1';
         txDon    <= '1';
         v.bufVld := '0';
         v.douVld := '0';
         v.txBsy  := '0';
         stpin    <= '0';
         douin    <= (others => '0');
      end if;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( ulpiClk ) is
   begin
      if ( rising_edge( ulpiClk ) ) then
         r     <= rin;
         din_r <= ulpiIb.dat;
         nxt_r <= ulpiIb.nxt;
         stp_i <= ulpiIb.stp;
         dir_r <= ulpiIb.dir;
         dou_r <= douin;
         stp_r <= stpin;
      end if;
   end process P_SEQ;

   txRdy      <= (not r.bufVld or not r.douVld);

   ulpiRx.dat <= din_r;
   ulpiRx.nxt <= nxt_r;
   ulpiRx.dir <= dir_r;
   ulpiRx.trn <= r.trn;
   ulpiRx.stp <= stp_i;

   ulpiOb.dat <= dou_r;
   ulpiOb.stp <= stp_r;

end architecture rtl;
