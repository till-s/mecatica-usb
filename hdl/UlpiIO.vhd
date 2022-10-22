library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library unisim;
use     unisim.vcomponents.all;

use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

entity UlpiIO is
   generic (
      MARK_DEBUG_G  : boolean          := true;
      GEN_ILA_G     : boolean          := false
   );
   port (
      rst           :  in    std_logic := '0';
      clk           :  in    std_logic;
      stp           :  out   std_logic := '0';
      dir           :  in    std_logic;
      nxt           :  in    std_logic;
      dat           :  inout std_logic_vector(7 downto 0);

      ulpiRx        :  out   UlpiRxType;
      ulpiTxReq     :  in    UlpiTxReqType := ULPI_TX_REQ_INIT_C;
      ulpiTxRep     :  out   UlpiTxRepType;

      regReq        :  in    UlpiRegReqType;
      regRep        :  out   UlpiRegRepType
   );
end entity UlpiIO;

architecture Impl of UlpiIO is

   attribute IOB        : string;
   attribute IOBDELAY   : string;

   type TxStateType       is (INIT, IDLE, TX1, TX2, WR, RD1, RD2, DON);

   type TxPktStateType    is (IDLE, RUN, LAST);

   type TxRegType is record
      state       : TxStateType;
      rep         : UlpiRegRepType;
      stp         : std_logic;
      pktState    : TxPktStateType;
   end record TxRegType;

   constant TX_REG_INIT_C : TxRegType := (
      state       => INIT,
      rep         => ULPI_REG_REP_INIT_C,
      stp         => '0',
      pktState    => IDLE
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
   signal stp_r   : std_logic                   := '0';
   signal dat_o   : std_logic_vector(dat'range) := (others => '0');
   signal dat_t   : std_logic_vector(dat'range);
   signal trn_r   : std_logic                   := '0';

   signal dirCtl  : std_logic;
   signal dir_r   : std_logic := '1';
   signal dou_ce  : std_logic := '0';
   signal dou_rst : std_logic := '0';

   attribute IOB of dir_r        : signal is "TRUE";
   attribute IOB of din_r        : signal is "TRUE";
   attribute IOBDELAY of din_r   : signal is "NONE";
   attribute IOB of dou_r        : signal is "TRUE";
   attribute IOB of nxt_r        : signal is "TRUE";
   attribute IOB of stp_r        : signal is "TRUE";

   signal txData     : std_logic_vector(7 downto 0);
   signal txDataRst  : std_logic;

   signal douRst  : std_logic;
   signal douCen  : std_logic;

   signal rTx     : TxRegType := TX_REG_INIT_C;
   signal rinTx   : TxRegType;
   signal dou_tx  : std_logic_vector(7 downto 0) := (others => '0');
   signal stp_tx  : std_logic := '0';

   -- blank DIR for the RX channel during register-RX back-to-back cycle
   signal blank   : std_logic := '0';

   component Ila_256 is
      port (
         clk          : in  std_logic;
         probe0       : in  std_logic_vector(63 downto 0) := (others => '0');
         probe1       : in  std_logic_vector(63 downto 0) := (others => '0');
         probe2       : in  std_logic_vector(63 downto 0) := (others => '0');
         probe3       : in  std_logic_vector(63 downto 0) := (others => '0');
         trig_in      : in  std_logic := '0';
         trig_in_ack  : out std_logic;
         trig_out     : out std_logic;
         trig_out_ack : in  std_logic := '0'
      );
   end component Ila_256;

   signal stateVec  : unsigned(2 downto 0);
   signal regReqDbg : UlpiRegReqType;

   attribute KEEP       of stateVec  : signal is toStr( GEN_ILA_G );
   attribute KEEP       of regReqDbg : signal is toStr( GEN_ILA_G );

   
   attribute MARK_DEBUG of  din_r          : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  dou_tx         : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  dou_rst        : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  dou_ce         : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  dir_r          : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  nxt_r          : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  stp_tx         : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  regReqDbg      : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  trn_r          : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  stateVec       : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  blank          : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  rTx            : signal is toStr( MARK_DEBUG_G );

begin

   regReqDbg <= regReq;
   stateVec  <= to_unsigned( TxStateType'pos( rTx.state ), stateVec'length );


   P_COMB_TX : process ( rTx, regReq, dir_r, din_r, nxt_r, nxt, ulpiTxReq ) is
      variable v : TxRegType;
   begin
      v          := rTx;
      dou_tx     <= ulpiTxReq.dat;
      dou_ce     <= '1';
      v.rep.ack  := '0';
      stp_tx     <= '0';
      blank      <= '0';

      case ( rTx.state ) is

         when INIT =>
            v.state := IDLE;

         when IDLE =>
            v.pktState := IDLE;
            v.rep.err  := '0';
            if ( ( dir_r = '0' ) ) then
               if    ( ulpiTxReq.vld = '1' ) then
                  v.pktState   := RUN;
                  v.state      := WR;
                  dou_ce       <= '1';
               elsif ( regReq.vld = '1' ) then
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
               if ( rTx.pktState = RUN ) then
                  -- this is a packet data transmission
                  if ( ulpiTxReq.vld = '0' ) then
                     -- transmission done; the last cycle registers the TX status
                     v.pktState := LAST;
                     stp_tx     <= '1';
                     v.state    := DON;
                  end if;
               else
                  stp_tx  <= '1';
                  v.state := DON;
               end if;
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
               blank   <= '1';
            end if;

         when DON =>
            if ( rTx.rep.ack = '1' or ( rTx.pktState /= IDLE ) ) then
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

      rinTx         <= v;
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

   dirCtl  <= dir or dir_r;

   dat_o   <= dou_r;

   dou_rst <= rst or dir_r;

   P_DOU  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( dou_rst = '1' ) then
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
            stp_r   <= '0';
            trn_r   <= '0';
         else
            dir_r   <= dir;
            din_r   <= dat_i;
            nxt_r   <= nxt;
            stp_r   <= stp_tx;
            -- is the registered cycle a turn-around cycle?
            trn_r   <= ( dir xor dir_r );
         end if;
      end if;
   end process P_DIR;

   G_DATB :  for i in dat'range generate
      U_BUF : IOBUF port map ( IO => dat(i), I => dat_o(i), T => dirCtl, O => dat_i(i) );
   end generate G_DATB;

   stp    <= stp_r;
   regRep <= rTx.rep;

   ulpiRx.dat <= din_r;
   ulpiRx.nxt <= nxt_r;
   ulpiRx.dir <= dir_r and not blank;
   ulpiRx.trn <= trn_r;

   G_ILA : if ( GEN_ILA_G ) generate
   begin

      U_ULPI_ILA : component Ila_256
         port map (
            clk                  => clk,
            trig_in              => '0',
            trig_out_ack         => '1',

            probe0( 7 downto  0) => din_r,
            probe0(15 downto  8) => dou_tx,
            probe0(          16) => dou_rst,
            probe0(          17) => dou_ce,
            probe0(          18) => dir_r,
            probe0(          19) => nxt_r,
            probe0(          20) => stp_tx,
            probe0(          21) => regReqDbg.vld,
            probe0(          22) => regReqDbg.extnd,
            probe0(          23) => trn_r,
            probe0(31 downto 24) => regReqDbg.addr,
            probe0(39 downto 32) => regReqDbg.wdat,
            probe0(42 downto 40) => std_logic_vector( stateVec ), 
            probe0(          43) => blank,
            probe0(          44) => rTx.rep.ack,
            probe0(          45) => rTx.rep.err,
            probe0(53 downto 46) => rTx.rep.rdat,
            probe0(63 downto 54) => (others => '0'),

            probe1(63 downto  0) => (others => '0'),

            probe2(63 downto  0) => (others => '0'),

            probe3(63 downto  0) => (others => '0')

         );
   end generate G_ILA;

   ulpiTxRep.nxt <= dou_ce;
   ulpiTxRep.err <= rTx.rep.err;
   ulpiTxRep.don <= toSl( ( rTx.state = DON ) and (rTx.pktState /= IDLE ) );

end architecture Impl;
