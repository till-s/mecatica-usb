library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;

entity UlpiIO is
   generic (
      MARK_DEBUG_G       : boolean         := true;
      ULPI_NXT_IOB_G     : boolean         := true;
      ULPI_DIR_IOB_G     : boolean         := true;
      ULPI_DIN_IOB_G     : boolean         := true;
      ULPI_STP_MODE_G    : UlpiStpModeType := NORMAL
   );
   port (
      rst                : in    std_logic := '0';
      ulpiClk            : in    std_logic;
      ulpiIb             : in    UlpiIbType;
      ulpiOb             : out   UlpiObType;

      forceStp           : in    std_logic := '0';

      ulpiRx             : out   UlpiRxType;
      ulpiTxReq          : in    UlpiTxReqType  := ULPI_TX_REQ_INIT_C;
      ulpiTxRep          : out   UlpiTxRepType ;

      regReq             : in    UlpiRegReqType := ULPI_REG_REQ_INIT_C;
      regRep             : out   UlpiRegRepType
   );
end entity UlpiIO;

architecture Impl of UlpiIO is

   attribute IOB        : string;
   attribute IOBDELAY   : string;

   type TxStateType       is (INIT, IDLE, TXREG1, TXREG2, TX, RD1, DON);

   type TxPktStateType    is (IDLE, RUN);

   type TxRegType is record
      state       : TxStateType;
      rep         : UlpiRegRepType;
      genStp      : std_logic;
      stpWaiNxt   : std_logic;
      -- blank DIR for the RX channel during register-RX back-to-back cycle
      blank       : std_logic;
   end record TxRegType;

   constant TX_REG_INIT_C : TxRegType := (
      state       => INIT,
      rep         => ULPI_REG_REP_INIT_C,
      genStp      => '1',
      stpWaiNxt   => '0',
      blank       => '0'
   );

   procedure ABRT(variable v : inout TxRegType) is
   begin
      v           := v;
      v.rep.err   := '1';
      v.rep.ack   := '1';
      v.state     := DON;
   end procedure ABRT;


   signal douRst        : std_logic;
   signal douCen        : std_logic;

   signal rTx           : TxRegType := TX_REG_INIT_C;
   signal rinTx         : TxRegType;

   signal txVld         : std_logic := '0';
   signal txDat         : std_logic_vector(7 downto 0) := (others => '0');
   signal txRdy         : std_logic;
   signal txDon         : std_logic;
   signal txErr         : std_logic;
   signal txSta         : std_logic := '0';
   signal txNxt         : std_logic := '0';
   signal ulpiRxLoc     : UlpiRxType;

   attribute MARK_DEBUG of  txVld          : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of  txDat          : signal is toStr( MARK_DEBUG_G );

-- MARK_DEBUG prevents FSM extraction; explicitly create a copy of the state for debugging

   signal rTxStateDbg                      : unsigned(2 downto 0);
   attribute MARK_DEBUG of rTxStateDbg     : signal is toStr( MARK_DEBUG_G );

begin

   U_ULPI_BUF : entity work.UlpiIOBuf
      generic map (
         MARK_DEBUG_G    => MARK_DEBUG_G,
         ULPI_NXT_IOB_G  => ULPI_NXT_IOB_G,
         ULPI_DIR_IOB_G  => ULPI_DIR_IOB_G,
         ULPI_DIN_IOB_G  => ULPI_DIN_IOB_G,
         ULPI_STP_MODE_G => ULPI_STP_MODE_G
      )
      port map (
         ulpiClk         => ulpiClk,
         ulpiIb          => ulpiIb,
         ulpiOb          => ulpiOb,

         genStp          => rTx.genStp,
         waiNxt          => rTx.stpWaiNxt,
         frcStp          => forceStp,

         txVld           => txVld,
         txDat           => txDat,
         txRdy           => txRdy,
         txDon           => txDon,
         txErr           => txErr,
         txSta           => txSta,

         ulpiRx          => ulpiRxLoc
      );

   rTxStateDbg <= to_unsigned( TxStateType'pos( rTx.state ), rTxStateDbg'length );

   P_COMB_TX : process ( rTx, regReq, ulpiTxReq, ulpiRxLoc, txRdy, txDon, txErr ) is
      variable v : TxRegType;
   begin
      v          := rTx;
      txDat      <= (others => '0');
      txVld      <= '0';
      txSta      <= '0';
      txNxt      <= '0';
      v.rep.ack  := '0';

      case ( rTx.state ) is

         when INIT =>
            v.state := IDLE;

         when IDLE =>
            v.rep.err  := '0';
            v.blank    := '0';
            if ( ( ulpiRxLoc.dir = '0' ) ) then
               if    ( ulpiTxReq.vld = '1' ) then
                  v.state      := TX;
                  v.stpWaiNxt  := '1';
                  v.genStp     := '1';
               elsif ( regReq.vld = '1' ) then
                  txDat(7 downto 6) <= "1" & regReq.rdnwr;
                  v.stpWaiNxt  := '0';
                  v.genStp     := not regReq.rdnwr;
                  v.blank      := '1';
                  if ( regReq.extnd = '1' ) then
                     txDat(5 downto 0)  <= "101111";
                     v.state            := TXREG1;
                  else
                     -- assume addr /= 101111
                     txDat(5 downto 0)  <= regReq.addr(5 downto 0);
                     v.state            := TXREG2;
                  end if;
                  txVld <= '1';
               end if;
            end if;

         when TXREG1  =>
            txDat  <= regReq.addr;
            txVld  <= '1';
            if ( txErr = '1' ) then
               ABRT( v );
            elsif ( txRdy = '1' ) then
               v.state := TXREG2;
            end if;

         when TXREG2  =>
            -- in case the operation is a READ the data we latch here
            -- is not visible because DIR flips the direction of the
            -- output buffers.
            txDat  <= regReq.wdat;
            txVld  <= '1';
            if ( txErr = '1' ) then
               ABRT( v );
            elsif ( txRdy = '1' ) then
               if ( regReq.rdnwr = '1' ) then
                  txVld   <= '0';
                  v.state := RD1;
               else
                  v.state := DON;
               end if;
            end if;

         when TX   =>
            txNxt <= ulpiTxReq.vld and txRdy;
            txDat <= ulpiTxReq.dat;
            txVld <= ulpiTxReq.vld;
            txSta <= ulpiTxReq.err;
            if ( txDon = '1' ) then
               v.state := IDLE;
            end if;

         when RD1 =>
            if ( txErr = '1' ) then
               ABRT( v );
            elsif ( ulpiRxLoc.dir = '1' ) then
               v.rep.err := ulpiRxLoc.nxt;
               v.state   := DON;
            end if;

         when DON =>
            v.blank := '0'; -- make sure not to blank a back-to-back RX operation
            if ( rTx.rep.ack = '1' ) then
               v.state := IDLE;
            else
               if ( regReq.rdnwr = '1' ) then
                  v.rep.rdat   := ulpiRxLoc.dat;
                  if ( ulpiRxLoc.nxt = '1' ) then
                     v.rep.err := '1';
                  end if;
                  v.rep.ack    := '1';
               else
                  if ( txErr = '1' ) then
                     v.rep.err := '1';
                     v.rep.ack := '1';
                  else
                     v.rep.ack := txDon;
                  end if;
               end if;
            end if;
      end case;

      rinTx         <= v;
      ulpiRx        <= ulpiRxLoc;
      ulpiRx.dir    <= ulpiRxLoc.dir and not rTx.blank;
   end process P_COMB_TX;

   P_SEQ_TX : process ( ulpiClk ) is
   begin
      if ( rising_edge( ulpiClk ) ) then
         if ( rst = '1' ) then
            rTx <= TX_REG_INIT_C;
         else
            rTx <= rinTx;
         end if;
      end if;
   end process P_SEQ_TX;

   regRep        <= rTx.rep;

   ulpiTxRep.nxt <= txNxt;
   ulpiTxRep.err <= txErr;
   ulpiTxRep.don <= toSl( rTx.state = TX ) and txDon;

end architecture Impl;
