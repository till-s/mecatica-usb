library ieee;
use     ieee.std_logic_1164.all;

use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

entity UlpiIOBuf is
   generic (
      MARK_DEBUG_G : boolean := true
   );
   port (
      ulpiClk    : in  std_logic;

      -- whether to generate a stop after transmitting
      -- (must be suppressed in the case of a register read)
      genStp     : in  std_logic;

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

architecture Impl of UlpiIOBuf is

   -- direct synthesis to use RST and CE as coded (minimize lut cascading for timing)
   attribute DIRECT_ENABLE : string;
   attribute DIRECT_RESET  : string;
   attribute IOB           : string;
   attribute MARK_DEBUG    : string;

   signal dou_r            : std_logic_vector(7 downto 0) := (others => '0');
   attribute IOB of dou_r  : signal is "TRUE";
   signal douVld           : std_logic                    := '0';
   signal buf              : std_logic_vector(7 downto 0) := (others => '0');
   signal bufVld           : std_logic                    := '0';
   signal dou_i            : std_logic_vector(7 downto 0) := (others => '0');
   signal douRst           : std_logic                    := '1';
   attribute DIRECT_RESET  of douRst : signal is "TRUE";
   signal last             : std_logic;
   signal douCE            : std_logic                    := '0';
   attribute DIRECT_ENABLE of douCE  : signal is "TRUE";
   signal lastCE           : std_logic;
   attribute DIRECT_ENABLE of lastCE : signal is "TRUE";
   signal stp_r            : std_logic                    := '0';
   attribute IOB           of stp_r  : signal is "TRUE";
   signal lst_r            : std_logic                    := '0';
   attribute MARK_DEBUG    of lst_r  : signal is toStr( MARK_DEBUG_G );
   signal din_r            : std_logic_vector(7 downto 0) := (others => '0');
   attribute IOB           of din_r  : signal is "TRUE";
   attribute MARK_DEBUG    of din_r  : signal is toStr( MARK_DEBUG_G );
   signal dir_r            : std_logic                    := '1';
   attribute IOB of dir_r  : signal is "TRUE";
   attribute MARK_DEBUG    of dir_r  : signal is toStr( MARK_DEBUG_G );
   signal nxt_r            : std_logic                    := '0';
   attribute IOB of nxt_r  : signal is "TRUE";
   attribute MARK_DEBUG    of nxt_r  : signal is toStr( MARK_DEBUG_G );
   signal trn_r            : std_logic                    := '0';
   attribute MARK_DEBUG    of trn_r  : signal is toStr( MARK_DEBUG_G );
   signal stp_rb           : std_logic                    := '0';
   attribute IOB           of stp_rb : signal is "TRUE";
   attribute MARK_DEBUG    of stp_rb : signal is toStr( MARK_DEBUG_G );
   signal don_r            : std_logic                    := '0';
   attribute MARK_DEBUG    of don_r  : signal is toStr( MARK_DEBUG_G );

   signal err_i            : std_logic;

begin

   P_MUX : process ( bufVld, buf, txDat, last ) is
   begin
      if ( ( bufVld or last ) = '1' ) then
         dou_i <= buf;
      else
         dou_i <= txDat;
      end if;
   end process P_MUX;

   last    <= not txVld and not bufVld and ( douVld and ulpiIb.nxt );
   douCE   <= ( ( ulpiIb.nxt or not douVld ) and ( txVld or bufVld ) ) or last;

   P_SEQ : process ( ulpiClk ) is
   begin
      if ( rising_edge( ulpiClk ) ) then
         if ( douRst = '1' ) then
            dou_r <= (others => '0');
         elsif ( douCE = '1' ) then
            dou_r <= dou_i;
         end if;
         if ( (last or dir_r) = '1' ) then
            douVld <= '0';
         elsif ( txVld = '1' ) then
            douVld <= '1';
         end if;
         if ( ( ( bufVld and ulpiIb.nxt ) or dir_r ) = '1' ) then
            bufVld <= '0';
         elsif ( ( txVld and not ulpiIb.nxt and douVld ) = '1' ) then
            bufVld <= '1';
         end if;
         -- to simplify: we may latch into the buffer
         -- ignoring 'douVld' since the buffer is not marked as valid
         if ( bufVld = '0' ) then
            if ( ( txVld and not ulpiIb.nxt ) = '1' ) then
               buf <= txDat;
            else
               buf <= (others => txSta);
            end if;
         end if;
         if ( douRst = '1' ) then
            lst_r <= '0';
            stp_r <= '0';
         elsif ( lastCE = '1' ) then
            lst_r <= '1';
            stp_r <= genStp;
         end if;
         don_r  <= ( lst_r and (ulpiIb.nxt or not genStp) ) and not dir_r;
         dir_r  <= ulpiIb.dir;
         din_r  <= ulpiIb.dat;
         nxt_r  <= ulpiIb.nxt;
         -- is the registered cycle a turn-around cycle?
         trn_r  <= ( ulpiIb.dir xor dir_r );
         stp_rb <= ulpiIb.stp;
      end if;
   end process P_SEQ;

   lastCE     <= last;

   douRst     <= ( lst_r and (ulpiIb.nxt or not genStp) ) or dir_r;

   txRdy      <= ( not douVld or not bufVld );

   ulpiOb.dat <= dou_r;
   ulpiOb.stp <= stp_r;

   err_i      <= dir_r and (douVld or lst_r);
   txDon      <= err_i or don_r;
   txErr      <= err_i;

   ulpiRx.dat <= din_r;
   ulpiRx.nxt <= nxt_r;
   ulpiRx.dir <= dir_r;
   ulpiRx.trn <= trn_r;

end architecture Impl;
