library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library unisim;
use     unisim.vcomponents.all;

use     work.UlpiPkg.all;

entity UlpiIO is
   port (
      rst         :  in    std_logic := '0';
      clk         :  in    std_logic;
      stp         :  out   std_logic := '0';
      dir         :  in    std_logic;
      nxt         :  in    std_logic;
      dat         :  inout std_logic_vector(7 downto 0);

      regReq      :  in    UlpiRegReqType;
      regRep      :  out   UlpiRegRepType
   );
end entity UlpiIO;

architecture Impl of UlpiIO is

   attribute IOB      : string;
   attribute IOBDELAY : string;

   type TxStateType   is (INIT, IDLE, TX1, TX2, WR, RD1, RD2, DON);

   type TxRegType is record
      state       : TxStateType;
      rep         : UlpiRegRepType;
      stp         : std_logic;
   end record TxRegType;

   constant TX_REG_INIT_C : TxRegType := (
      state       => INIT,
      rep         => ULPI_REG_REP_INIT_C,
      stp         => '0'
   );

   procedure ABRT(variable v : inout TxRegType) is
   begin
      v           := v;
      v.rep.err   := '1';
      v.state     := DON;
   end procedure ABRT;

   signal dat_i   : std_logic_vector(dat'range);
   signal din_r   : std_logic_vector(dat'range);
   signal dou_r   : std_logic_vector(dat'range);
   signal nxt_r   : std_logic;
   signal dat_o   : std_logic_vector(dat'range) := (others => '0');
   signal dat_t   : std_logic_vector(dat'range);

   signal dirCtl  : std_logic;
   signal dir_r   : std_logic := '1';
   signal dou_ce  : std_logic := '0';

   attribute IOB of dir_r        : signal is "TRUE";
   attribute IOB of din_r        : signal is "TRUE";
   attribute IOBDELAY of din_r   : signal is "NONE";
   attribute IOB of dou_r        : signal is "TRUE";
   attribute IOB of nxt_r        : signal is "TRUE";

   signal txData     : std_logic_vector(7 downto 0);
   signal txDataRst  : std_logic;

   signal douRst  : std_logic;
   signal douCen  : std_logic;

   signal rTx     : TxRegType := TX_REG_INIT_C;
   signal rinTx   : TxRegType;
   signal dou_tx  : std_logic_vector(7 downto 0) := (others => '0');

begin

   P_COMB_TX : process ( rTx, regReq, dir_r, din_r, nxt_r, nxt ) is
      variable v : TxRegType;
   begin
      v          := rTx;
      dou_tx     <= (others => '0');
      dou_ce     <= '1';
      v.rep.ack  := '0';
      v.stp      := '0';

      case ( rTx.state ) is

         when INIT =>
            v.state := IDLE;

         when IDLE =>
            if ( ( dir_r = '0' ) and ( regReq.valid = '1' ) ) then
               v.rep.err := '0';
               dou_tx(7 downto 6) <= "1" & regReq.rdnwr;
               if ( regReq.extnd = '1' ) then
                  dou_tx(5 downto 0)  <= "101111";
                  v.state             := TX1;
               else
                  -- assume addr /= 101111
                  dou_tx(5 downto 0)  <= regReq.addr(5 downto 0);
                  v.state             := TX2;
               end if;
               dou_ce <= '1';
            end if;

         when TX1  =>
            dou_tx <= regReq.addr;
            dou_ce <= nxt;
            if ( dir_r = '1' ) then
               ABRT( v );
            elsif ( nxt = '1' ) then
               v.state := TX2;
            end if;

         when TX2  =>
            -- in case the operation is a READ the data we latch here
            -- is not visible because DIR flips the direction of the
            -- output buffers.
            dou_tx <= regReq.wdat;
            dou_ce <= nxt;
            if ( dir_r = '1' ) then
               ABRT( v );
            elsif ( nxt = '1' ) then
               if ( regReq.rdnwr = '1' ) then
                  v.state := RD1;
               else
                  v.state := WR;
               end if;
            end if;

         when WR   =>
            dou_ce <= nxt;
            if ( dir_r = '1' ) then
               ABRT( v );
            elsif ( nxt = '1' ) then
               v.stp   := '1';
               v.state := DON;
            end if;

         when RD1 =>
            if ( dir_r = '1' ) then
               ABRT( v );
            else
               v.state := RD2;
            end if;

         when RD2 =>
            if ( nxt_r = '1' ) then
               ABRT( v );
            else
               v.state := DON;
            end if;

         when DON =>
            if ( rTx.rep.ack = '1' ) then
               v.state := IDLE;
            else
               if ( regReq.rdnwr = '1' ) then
                  v.rep.rdat := din_r;
                  if ( nxt_r = '1' ) then
                     v.rep.err := '1';
                  end if;
               else
                  if ( dir_r = '1' ) then
                     v.rep.err := '1';
                  end if;
               end if;
               v.rep.ack   := '1';
            end if;
      end case;

      rinTx  <= v;
   end process P_COMB_TX;

   P_SEQ_TX : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            rTx <= TX_REG_INIT_C;
         else
            rTx <= rinTx;
         end if;
      end if;
   end process P_SEQ_TX;

--   type UlpiRegReqType is record
--      addr  : std_logic_vector(7 downto 0);
--      wdat  : std_logic_vector(7 downto 0);
--      extnd : std_logic;
--      valid : std_logic;
--      rdnwr : std_logic;
--   end record UlpiRegReqType;
--
--   constant ULPI_REG_REQ_INIT_C : UlpiRegReqType := (
--      addr  => (others => '0'),
--      wdat  => (others => '0'),
--      extnd => '0',
--      valid => '0',
--      rdnwr => '0'
--   );
--
--   type UlpiRegRepType is record
--      rdat  : std_logic_vector(7 downto 0);
--      ack   : std_logic;
--      err   : std_logic;
--   end record UlpiRegRepType;
--
--   constant ULPI_REG_REP_INIT_C : UlpiRegRepType := (
--      rdat  => (others => '0'),
--      ack   => '0',
--      err   => '0'
--   );
--

   dirCtl <= dir or dir_r;

   dat_o  <= dou_r;

   P_DOU  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ( rst or dir_r ) = '1' ) then
            dou_r <= (others => '0');
         elsif ( dou_ce = '1' ) then
            dou_r <= dou_tx;
         end if;
      end if;
   end process P_DOU;

   P_DIR  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            dir_r   <= '1';
            din_r   <= (others => '0');
            nxt_r   <= '0';
         else
            dir_r   <= dir;
            din_r   <= dat_i;
            nxt_r   <= nxt;
         end if;
      end if;
   end process P_DIR;

   G_DATB :  for i in dat'range generate
      U_BUF : IOBUF port map ( IO => dat(i), I => dat_o(i), T => dirCtl, O => dat_i(i) );
   end generate G_DATB;

   stp    <= rTx.stp;
   regRep <= rTx.rep;

end architecture Impl;
