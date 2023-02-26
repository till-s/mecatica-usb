-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.Usb2PrivPkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;

-- Main USB packet processing engine; it handles USB
-- transaction sequences and muxes/demuxes from/to
-- endpoints.

entity Usb2PktProc is
   generic (
      SIMULATION_G    : boolean       := false;
      MARK_DEBUG_G    : boolean       := true;
      NUM_ENDPOINTS_G : positive      := 1;
      INP_TIMO_MS_G   : Usb2TimerType := Usb2TimerType( to_signed( 1000, Usb2TimerType'length ) )
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';
      devStatus       : in  Usb2DevStatusType;
      epConfig        : in  Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_G - 1);
      epIb            : in  Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_G - 1);
      epOb            : out Usb2EndpPairObArray(0 to NUM_ENDPOINTS_G - 1);

      usb2Rx          : in  usb2RxType;

      txDataMst       : out Usb2StrmMstType;
      txDataSub       : in  Usb2PkTxSubType
   );
end entity Usb2PktProc;

architecture Impl of Usb2PktProc is

   function simt(constant a,b: in natural) return Usb2TimerType is
      variable v : integer;
   begin
      if ( SIMULATION_G ) then v := a; else v := b; end if;
      v := v - 2; -- timer expired = '-1'
      return Usb2TimerType(to_signed(v, Usb2TimerType'length));
   end function simt;

   function toStr(constant x : std_logic_vector) return string is
      variable s : string(1 to x'length);
   begin
      for j in x'left downto x'right loop
         s(x'length - j) := std_logic'image(x(j))(2);
      end loop;
      return s;
   end function toStr;

   function toStr(constant x : unsigned) return string is
   begin
      return toStr( std_logic_vector( x ) );
   end function toStr;


   -- NOTE: there is a 1 clock delay in the receive path due to IO buffering
   --                  1 clock delay after EOP to pktHdr.vld
   --                  TIME_DATA_TX_C clocks to get out of WAIT_TX state
   --                  1 clock delay from txDataMst.vld to TXCMD being sent to UlpiIO
   --                  1 clock delay in UlpiIO to get into TX state
   --                  1 clock delay in the transmit path due to IO buffering
   --
   --       and        1 clock delay in HSK state

   -- receive (tok, rx-data) -transmit (hsk); ULPI: HS: 1-14 clocks, FS: 7-18 clocks
   constant TIME_HSK_TX_C        : Usb2TimerType := simt(20,   1);

   -- receive (tok) -transmit (tx-data)     ; ULPI: HS: 1-14 clocks, FS: 7-18 clocks
   constant TIME_DATA_TX_C       : Usb2TimerType := simt(20,   1);
   -- transmit (tx-data) - receive (hsk)    ; ULPI: HS: 92  clocks, FS: 80 clocks (no range given)
   -- transmit (tx-data) - receive (hsk)    ; USB2: HS: 92-102   clocks, FS: 80 - 90 clocks
   -- ULPI: RXCMD delay     2-4 (HS+FS)
   --       TX-Start delay  1-2 (HS), 1-10 (FS) 
   --
   -- min timeout on wire: our timeout - tx-delay - rx-delay - our-latency
   --   our-timeout-min = usb_min_timeout + (tx-delay + rx-delay + our-latency)_max
   --   our-timeout-max = usb_max_timeout + (tx-delay + rx-delay + our-latency)_min
   --      HS_min       =   92            + (2        + 4        + 2)  = 100
   --      HS_max       =  102            + (1        + 2        + 2)  = 107
   --      FS_min       =   80            + (10       + 4        + 2)  = 96
   --      FS_max       =   90            + ( 1       + 2        + 2)  = 95
   --
   constant TIME_WAIT_ACK_C      : Usb2TimerType := simt(20,  96);
   -- receive (tok) - receive(data-pid)     ; USB2: HS: 92-102, FS: 80 - 90 since only receive-path
   --                                         latency is involved these values can be used verbatim
   -- UPDATE: Hmm - this timeout is mentioned (Fig. 8-32) but it's not clear what the value is.
   --         The (FS) 80-90 clock time is for a receive-transmit (they mention IN -> DATA) timeout.
   --         Linux - host takes longer than the 85 cycles I tried and I found a forum post
   --            https://electronics.stackexchange.com/questions/394648/in-usb-2-0-whats-the-maximum-delay-between-setup-and-data0-packets
   --         with few answers but one claiming that the timeout should be indefinite!
--   constant TIME_WAIT_DATA_PID_C : Usb2TimerType := to_unsigned( simt(30,  85) , Usb2TimerType'length);
   constant TIME_WAIT_DATA_PID_C : Usb2TimerType := USB2_TIMER_MAX_C;

   constant LD_BUFSZ_C           : natural   := 11;
   constant BUF_WIDTH_C          : natural   :=  9;

   constant MILLI_SEC_C          : signed(16 downto 0) := to_signed( 60000-2, 17 );

   type StateType is (
      IDLE,
      DATA_INP,
      DATA_REP,
      ISO_INP,
      DATA_PID,
      DATA_OUT,
      ISO_OUT,
      DRAIN,
      DUMP,
      WAIT_DON,
      WAIT_ACK,
      HSK,
      WAIT_TX,
      WAIT_FS_SE0,
      WAIT_FS_J,
      WAIT_FS_K
   );

   subtype IsoXactNumType is unsigned(1 downto 0);

   type IsoXactNumArray is array(natural range <>) of IsoXactNumType;

   type RegType   is record
      state           : StateType;
      nxtState        : StateType;
      dataTglInp      : std_logic_vector(NUM_ENDPOINTS_G - 1 downto 0);
      dataTglOut      : std_logic_vector(NUM_ENDPOINTS_G - 1 downto 0);
      isoXactInp      : IsoXactNumArray (0 to NUM_ENDPOINTS_G - 1);
      isoXactOut      : IsoXactNumArray (0 to NUM_ENDPOINTS_G - 1);
      timer           : Usb2TimerType;
      se0JTimer       : Usb2TimerType;
      se0JSeen        : boolean;
      lineState       : std_logic_vector(1 downto 0);
      rxActive        : boolean;
      prevDevState    : Usb2DevStateType;
      tok             : Usb2PidType;
      epIdx           : Usb2EndpIdxType;
      dataCounter     : Usb2PktSizeType;
      pid             : Usb2PidType;
      tmp             : std_logic_vector(7 downto 0);
      tmpVld          : std_logic;
      bufRWIdx        : unsigned(LD_BUFSZ_C - 1 downto 0);
      bufVldIdx       : unsigned(LD_BUFSZ_C - 1 downto 0);
      bufEndIdx       : unsigned(LD_BUFSZ_C - 1 downto 0);
      bufInpVld       : std_logic;
      bufInpPart      : std_logic;
      bufInpEpIdx     : Usb2EndpIdxType;
      donFlg          : std_logic;
      nakDon          : std_logic;
      retries         : unsigned(1 downto 0);
      -- prescaler to generate 1ms ticks
      milliSec        : signed(16 downto 0);
      -- we only support a single buffer for retry operations. If the buffer
      -- is currently occupied by unacked IN data the engine waits for the host
      -- to retry the unacked transaction (on the same endpoint) until it
      -- can handle transactions directed to other endpoints. In the rare
      -- case when three retries fail this could lead to a deadlock since
      -- the buffer is never released. Use the 'retryTimeout' for this case:
      -- if this timeout expires while bufInpVld or bufInpPart then we release
      -- the buffer and mark the endpoint as 'dead' (acks STALL henceforth).
      retryTimeout    : Usb2TimerType;
      deadInp         : std_logic_vector(NUM_ENDPOINTS_G - 1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      nxtState        => IDLE,
      dataTglInp      => (others => '0'),
      dataTglOut      => (others => '0'),
      isoXactInp      => (others => (others => '0' )),
      isoXactOut      => (others => (others => '0' )),
      timer           => USB2_TIMER_EXPIRED_C,
      se0JTimer       => (others => '0'),
      se0JSeen        => false,
      lineState       => "11",
      rxActive        => false,
      prevDevState    => DEFAULT,
      tok             => USB2_PID_SPC_NONE_C,
      epIdx           => USB2_ENDP_ZERO_C,
      dataCounter     => (others => '0'),
      pid             => USB2_PID_HSK_ACK_C,
      tmp             => (others => '0'),
      tmpVld          => '0',
      bufRWIdx        => (others => '0'),
      bufVldIdx       => (others => '0'),
      bufEndIdx       => (others => '0'),
      bufInpVld       => '0',
      bufInpPart      => '0',
      bufInpEpIdx     => USB2_ENDP_ZERO_C,
      donFlg          => '0',
      nakDon          => '0',
      retries         => (others => '0'),
      milliSec        => (others => '1'),
      retryTimeout    => USB2_TIMER_EXPIRED_C,
      deadInp         => (others => '0')
   );

   type BufReaderType is record
      bufRdIdx        : unsigned ( LD_BUFSZ_C - 1 downto 0);
      epIdx           : Usb2EndpIdxType;
      isSetup         : boolean;
      mstOut          : Usb2StrmMstType;
      dataCounter     : Usb2PktSizeType;
   end record BufReaderType;

   constant BUF_READER_INIT_C : BufReaderType := (
      bufRdIdx        => (others => '0'),
      epIdx           => USB2_ENDP_ZERO_C,
      isSetup         => false,
      mstOut          => USB2_STRM_MST_INIT_C,
      dataCounter     => (others => '1')
   );

   signal r                                     : RegType := REG_INIT_C;
   signal rin                                   : RegType;

   signal rd                                    : BufReaderType := BUF_READER_INIT_C;
   signal rdin                                  : BufReaderType;

   signal bufWrEna                              : std_logic := '0';
   signal bufReadbackInp                        : std_logic_vector(BUF_WIDTH_C - 1 downto 0) := (others => '0');
   signal bufReadOut                            : std_logic_vector(BUF_WIDTH_C - 1 downto 0) := (others => '0');
   signal bufWriteInp                           : std_logic_vector(BUF_WIDTH_C - 1 downto 0) := (others => '0');
   signal epConfigDbg                           : Usb2EndpPairConfigArray(epConfig'range);
   signal epIbDbg                               : Usb2EndpPairIbType;
   signal epObDbg                               : Usb2EndpPairObType;
   signal epObLoc                               : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_G - 1);

   attribute MARK_DEBUG of r                    : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of rd                   : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of epConfigDbg          : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufReadOut           : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufWriteInp          : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufWrEna             : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufReadbackInp       : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of epIbDbg              : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of epObDbg              : signal is toStr(MARK_DEBUG_G);

   function checkTokHdr(
      constant h: Usb2PktHdrType;
      constant s: Usb2DevStatusType;
      constant c: Usb2EndpPairConfigArray
   ) return boolean
   is
      variable epidx : Usb2EndpIdxType;
      variable daddr : Usb2DevAddrType;
   begin
      epidx := usb2TokenPktEndp( h );
      daddr := usb2TokenPktAddr( h );

      -- reject SOF tokens
      if ( h.sof ) then
         return false;
      end if;

      -- ping only in hi-speed mode
      if ( ( USB2_PID_SPC_PING_C = h.pid ) and not s.hiSpeed ) then
         return false;
      end if;

      if ( epidx = USB2_ENDP_ZERO_C ) then
         -- directed to default control pipe
         -- always accept the default pipe at the default address
         return (    daddr = USB2_DEV_ADDR_DFLT_C
                  or daddr = s.devAddr            );
      end if;
      -- reject endpoint out of range
      if ( epidx >= NUM_ENDPOINTS_G ) then
         return false;
      end if;
      -- address must match and the device must be configured
      if ( ( daddr /= s.devAddr ) or ( s.state /= CONFIGURED ) ) then
         return false;
      end if;

      -- the endpoint must exist
      if (    USB2_PID_TOK_OUT_C   = h.pid
           or USB2_PID_SPC_PING_C  = h.pid
           or USB2_PID_TOK_SETUP_C = h.pid ) then
         if ( c( to_integer( epidx ) ).maxPktSizeOut = 0 ) then
            return false;
         end if;
      else 
         if ( c( to_integer( epidx ) ).maxPktSizeInp = 0 ) then
            return false;
         end if;
      end if;
      -- setup transactions can only go to control endpoints
      if ( USB2_PID_TOK_SETUP_C = h.pid ) then
         if ( c( to_integer( epidx ) ).transferTypeOut /= USB2_TT_CONTROL_C ) then
            return false;
         end if;
      end if;

      return true;
   end function checkTokHdr;

   -- assume the PID is a INP/OUT/SETUP token!
   function isTokInp(constant x : Usb2PidType) return boolean is
   begin
      return x = USB2_PID_TOK_IN_C;
   end function isTokInp;

   function checkDatHdr(constant h: Usb2PktHdrType) return boolean is
   begin
      return ( h.pid = USB2_PID_DAT_DATA0_C or h.pid = USB2_PID_DAT_DATA1_C );
   end function checkDatHdr;

   function sequenceOutMatch(constant v : in RegType; constant h : in Usb2PktHdrType) return boolean is
   begin
      return    ( v.dataTglOut( to_integer( v.epIdx ) ) = h.pid(3) )
            or  ( v.tok(3 downto 2) = USB2_PID_TOK_SETUP_C(3 downto 2) );
   end function sequenceOutMatch;

   procedure invalidateBuffer(variable v : inout RegType) is
   begin
      v            := v;
      v.bufInpVld  := '0';
      v.bufInpPart := '0';
      v.bufRWIdx   := v.bufVldIdx;
   end procedure invalidateBuffer;

begin

   epOb        <= epObLoc;
   epConfigDbg <= epConfig;

   -- at least one cycle of TIME_DATA_TX_C is required for pre-loading the replay ram readout. Otherwise
   -- the algorithm must be changed.
   assert to_integer( TIME_DATA_TX_C ) /= 0 report "TIME_DATA_TX_C must not be zero!" severity failure;

   P_COMB : process ( r, rd, devStatus, epConfig, epIb, epObLoc, txDataSub, bufReadbackInp, usb2Rx ) is
      variable v         : RegType;
      variable ei        : Usb2EndpPairIbType;
      variable haltedInp : boolean;
      variable haltedOut : boolean;
   begin
      v                := r;
      v.prevDevState   := devStatus.state;
      ei               := epIb( to_integer( r.epIdx ) );
      haltedInp        := ( (devStatus.haltedInp( to_integer( r.epIdx ) ) or r.deadInp( to_integer( r.epIdx ) ) )  = '1');
      haltedOut        := (devStatus.haltedOut( to_integer( r.epIdx ) ) = '1');
      epIbDbg          <= ei;

      txDataMst        <= ei.mstInp;
      txDataMst.vld    <= '0';
      txDataMst.don    <= '0';
      txDataMst.usr    <= r.pid;
      bufWrEna         <= '0';
      bufWriteInp      <= '0' & usb2Rx.mst.dat;

      if ( usb2Rx.pktHdr.vld = '1' and usb2Rx.pktHdr.sof ) then
         v.isoXactInp := (others => (others => '1'));
         v.isoXactOut := (others => (others => '1'));
      end if;

      for i in epObLoc'range loop
         epObLoc(i).subInp        <= USB2_STRM_SUB_INIT_C;
         epObLoc(i).haltedInp     <= devStatus.haltedInp(i) or r.deadInp(i);
         epObLoc(i).haltedOut     <= devStatus.haltedOut(i);
         epObLoc(i).config        <= epConfig(i);

         if ( epConfig( i ).transferTypeOut = USB2_TT_CONTROL_C ) then
            epObLoc(i).mstCtl     <= rd.mstOut;
            epObLoc(i).mstCtl.vld <= '0';
            epObLoc(i).mstCtl.don <= '0';
            epObLoc(i).mstOut     <= rd.mstOut;
            epObLoc(i).mstOut.vld <= '0';
            epObLoc(i).mstOut.don <= '0';
            if ( rd.isSetup ) then
               epObLoc( to_integer( rd.epIdx ) ).mstCtl <= rd.mstOut;
            else
               epObLoc( to_integer( rd.epIdx ) ).mstOut <= rd.mstOut;
            end if;
         else
            epObLoc(i).mstCtl  <= USB2_STRM_MST_INIT_C;
            if ( epConfig( i ).transferTypeOut = USB2_TT_ISOCHRONOUS_C ) then
               epObLoc(i).mstOut        <= usb2Rx.mst;
               epObLoc(i).mstOut.usr    <= "00" & std_logic_vector( r.isoXactOut(i) );
               epObLoc(i).mstOut.vld    <= '0';
               epObLoc(i).mstOut.don    <= '0';
            else
               epObLoc(i).mstOut  <= rd.mstOut;
               if ( i /= rd.epIdx ) then
                  epObLoc(i).mstOut.vld <= '0';
                  epObLoc(i).mstOut.don <= '0';
               end if;
            end if;
         end if;
      end loop;

      -- record line state
      if ( usb2Rx.isRxCmd ) then
         v.lineState   := usb2Rx.rxCmd(1 downto 0);
      end if;

      v.rxActive := usb2Rx.rxActive;

      -- count time since SE0 -> J (well, we assume it's J)
      -- this happens *before* rxActive or dir are deasserted 
      if ( devStatus.hiSpeed ) then
         v.se0JTimer := (others => '0');
         v.se0JSeen  := true;
      else
         if ( usb2Rx.rxActive ) then
            if ( not r.rxActive ) then
               -- rx just became active
               -- reset and hold timer until SE0
               v.se0JTimer := USB2_TIMER_EXPIRED_C;
            end if;
            if (    r.lineState = ULPI_RXCMD_LINE_STATE_SE0_C
                and v.lineState = ULPI_RXCMD_LINE_STATE_FS_J_C ) then
               -- start timer
               v.se0JTimer := to_signed(1, v.se0JTimer'length);
            end if;
         end if;
         if ( not usb2TimerExpired( r.se0JTimer ) ) then
            v.se0JTimer := r.se0JTimer + 1;
         end if;
      end if;

      if ( not usb2TimerExpired( r.timer ) ) then
         v.timer := r.timer - 1;
      end if;

      case ( r.state ) is
         when IDLE =>
            v.donFlg := '0';
            if ( ( usb2Rx.pktHdr.vld = '1' ) ) then
               if ( checkTokHdr( usb2Rx.pktHdr, devStatus, epConfig ) ) then
                  -- ignore SE0-J in hi-speed mode
                  v.se0JSeen       := devStatus.hiSpeed;
                  v.tok            := usb2Rx.pktHdr.pid;
                  v.epIdx          := usb2TokenPktEndp( usb2Rx.pktHdr );
                  v.timer          := USB2_TIMER_EXPIRED_C;
                  ei               := epIb( to_integer( v.epIdx ) );
                  haltedInp        := ( (devStatus.haltedInp( to_integer( v.epIdx ) ) or r.deadInp( to_integer( v.epIdx ) ) ) = '1');
                  haltedOut        := (devStatus.haltedOut( to_integer( v.epIdx ) ) = '1');
                  -- don't propagate RX RDY back to IN endpoint of they advertise
                  -- an unframed stream
                  v.nakDon         := ei.bFramedInp;
                  if ( USB2_PID_SPC_PING_C = usb2Rx.pktHdr.pid ) then
                     -- cannot accept OUTbound data while the retry buffer is in use
                     if ( (not r.bufInpVld and not r.bufInpPart and epIb( to_integer( v.epIdx ) ).subOut.rdy) = '1' ) then
                        v.pid      := USB2_PID_HSK_ACK_C;
                     else
                        v.pid      := USB2_PID_HSK_NAK_C;
                     end if;
                     v.timer       := TIME_HSK_TX_C;
                     v.nxtState    := HSK;
                     v.state       := WAIT_TX;
                  elsif ( isTokInp( usb2Rx.pktHdr.pid ) ) then
                     v.dataCounter := epConfig( to_integer( v.epIdx ) ).maxPktSizeInp - 1;
                     v.timer       := TIME_DATA_TX_C;
                     v.state       := WAIT_TX;
                     if    ( epConfig( to_integer( v.epIdx ) ).transferTypeInp = USB2_TT_ISOCHRONOUS_C ) then
                        if ( r.isoXactInp( to_integer( v.epIdx ) ) = "00" ) then
                           -- if the last transaction (r.ixoXactInp = "00") has already been sent then wait for the next
                           -- microframe!
                           v.state                               := r.state;
                           v.timer                               := USB2_TIMER_EXPIRED_C;
                        else
                           v.nxtState                            := ISO_INP;
                           v.pid                                 := USB2_PID_DAT_DATA0_C;
                           if ( ei.mstInp.vld = '0' ) then
                              -- must send a null packet if there is no data (usb 5.6.5)
                              if ( (not ei.mstInp.don or ei.bFramedInp ) = '1' ) then
                                 v.donFlg := '1';
                                 -- in this case, we also must prevent the TX DON from being seen by the endpoint
                                 v.nakDon := '1';
                              end if;
                           end if;
                           v.isoXactInp( to_integer( v.epIdx ) ) := "00";
                           if ( ei.mstInp.vld = '1' ) then
                              if ( r.isoXactInp( to_integer( v.epIdx ) ) = "11" ) then
                                 v.isoXactInp( to_integer( v.epIdx ) ) := unsigned( ei.mstInp.usr(1 downto 0) );
                              else
                                 v.isoXactInp( to_integer( v.epIdx ) ) := r.isoXactInp( to_integer( v.epIdx ) ) - 1;
                              end if;
                              case ( v.isoXactInp( to_integer( v.epIdx ) ) ) is
                                 when "01" => v.pid := USB2_PID_DAT_DATA1_C;
                                 when "10" => v.pid := USB2_PID_DAT_DATA2_C;
                                 when others =>
                              end case;
                           end if;
                        end if;
                     elsif ( haltedInp ) then
                        v.pid      := USB2_PID_HSK_STALL_C;
                        v.timer    := TIME_HSK_TX_C;
                        v.nxtState := HSK;
                     elsif (    ( ( ei.mstInp.vld or ei.mstInp.don or r.bufInpVld) = '0' )
                             -- if buffer is currently in use we have to wait for retries to finish
                             or ( ( ( r.bufInpVld or r.bufInpPart ) = '1' ) and ( r.bufInpEpIdx /= v.epIdx ) )
                           )  then
                        v.pid      := USB2_PID_HSK_NAK_C;
                        v.timer    := TIME_HSK_TX_C;
                        v.nxtState := HSK;
                     else
-- For now we retry forever
--                        if ( r.bufInpVld = '1' ) then
--                           -- a retry
--                           if ( r.retries < 2 ) then
--                              v.retries := r.retries + 1;
--                              v.state   := DATA_REP;
--                              v.timer   := TIME_DATA_TX_C;
--                           else
--                              -- should stall/halt the device or endpoint? for now we just drop
--                              v.retries   := 0;
--                              v.bufRWIdx  := r.bufVldIdx;
--                              v.bufInpVld := '0';
--      
                        if ( r.dataTglInp( to_integer( v.epIdx ) ) = '0' ) then
                           v.pid := USB2_PID_DAT_DATA0_C;
                        else
                           v.pid := USB2_PID_DAT_DATA1_C;
                        end if;
                        if ( (r.bufInpVld or r.bufInpPart) = '1' ) then
                           v.nxtState  := DATA_REP;
                           -- pre-load next readout
                           v.bufRWIdx  := r.bufRWIdx + 1;
                           v.tmpVld    := '0';
                           if ( r.bufRWIdx = r.bufEndIdx ) then
                              -- empty packet - avoid DATA_REP; the WAIT_ACK phase
                              -- handles the 'don' handshaking
                              v.nxtState := WAIT_DON;
                              v.donFlg   := '1';
                              v.bufRWIdx := r.bufRWIdx;
                           end if;
                        else
                           v.nxtState := DATA_INP;
                        end if;
                     end if;
                  else
                     v.dataCounter := epConfig( to_integer( v.epIdx ) ).maxPktSizeOut - 1;
                     v.timer       := TIME_WAIT_DATA_PID_C;
                     v.state       := DATA_PID;
-- This happens anyways...
--                   if (     ( r.lstWasInp( ei ) = '1' ) and
--                        and ( epConfig( to_integer( v.epIdx ) ).transferTypeOut = USB2_TT_CONTROL_C ) then
--                      -- this must be a status transaction; if the last ack was lost then we take
--                      -- this as an ACK (8.5.3.3)
--                   invalidateBuffer( v );
--                   end if;
                  -- make sure there is nothing left in the write area
                  end if;
               end if;
            elsif ( usb2TimerExpired( r.retryTimeout ) and ( ( r.bufInpVld or r.bufInpPart ) = '1' ) ) then
               v.deadInp( to_integer( r.bufInpEpIdx ) ) := '1';
               invalidateBuffer( v );
            end if;

         when DATA_PID =>
            if ( ( usb2Rx.pktHdr.vld = '1' ) ) then
               if    ( epConfig( to_integer( r.epIdx ) ).transferTypeOut = USB2_TT_ISOCHRONOUS_C ) then
                  v.pid   := USB2_PID_SPC_NONE_C;
                  v.state := DRAIN;
                  if ( usb2PidGroup( usb2Rx.pktHdr.pid ) = USB2_PID_GROUP_DAT_C and not haltedOut ) then
                     -- no super-sophisticated sequence checking; in particular: we don't check if the
                     -- EP configuration actually asked for multiple transactions per micro-frame.
                     -- When needed the user may track the number of packets received (usr) as well as the PIDs
                     -- and identify lost packets.
                     if (   (    r.isoXactOut( to_integer( r.epIdx ) ) = "11"
                             and (   USB2_PID_DAT_DATA0_C(3 downto 2) = usb2Rx.pktHdr.pid(3 downto 2)
                                  or USB2_PID_DAT_MDATA_C(3 downto 2) = usb2Rx.pktHdr.pid(3 downto 2) ) ) 
                         or (     r.isoXactOut( to_integer( r.epIdx ) ) = "00"
                             and (   USB2_PID_DAT_DATA1_C(3 downto 2) = usb2Rx.pktHdr.pid(3 downto 2)
                                  or USB2_PID_DAT_MDATA_C(3 downto 2) = usb2Rx.pktHdr.pid(3 downto 2) ) ) 
                         or (     r.isoXactOut( to_integer( r.epIdx ) ) = "01"
                             and (   USB2_PID_DAT_DATA2_C(3 downto 2) = usb2Rx.pktHdr.pid(3 downto 2) ) ) ) then
                        v.isoXactOut( to_integer( r.epIdx ) ) := r.isoXactOut( to_integer( r.epIdx ) ) + 1;
                        v.state := ISO_OUT; 
                     end if;
                  end if;
               elsif ( checkDatHdr( usb2Rx.pktHdr ) ) then
                  if ( haltedOut ) then
                     v.pid   := USB2_PID_HSK_STALL_C;
                     v.state := DRAIN;
                  elsif ( not sequenceOutMatch( v, usb2Rx.pktHdr ) ) then
                     -- sequence mismatch; discard packet and ACK
                     v.pid   := USB2_PID_HSK_ACK_C;
                     v.state := DRAIN;
                  elsif (     ( ( r.bufInpVld or r.bufInpPart or not ei.subOut.rdy ) = '1' )
                          -- always ack setup packets
                          and ( USB2_PID_TOK_SETUP_C(3 downto 2) /= r.tok(3 downto 2) )
                        ) then
                     v.pid   := USB2_PID_HSK_NAK_C;
                     v.state := DRAIN;
                  else
                     v.pid       := USB2_PID_HSK_ACK_C;
                     v.state     := DATA_OUT;
                     -- write destination header into the buffer
                     bufWriteInp <= '1' & r.tok & std_logic_vector( r.epIdx );
                     bufWrEna    <= '1';
                     v.bufRWIdx  := r.bufRWIdx + 1;
                  end if;
               else
                  if ( epConfig( to_integer( r.epIdx ) ).transferTypeOut = USB2_TT_ISOCHRONOUS_C ) then
                     epObLoc( to_integer( rd.epIdx ) ).mstOut.don <= '1';
                     epObLoc( to_integer( rd.epIdx ) ).mstOut.err <= '1';
                  end if;
                  v.state    := IDLE;
               end if;   
            elsif ( usb2TimerExpired( r.timer ) ) then
               if ( epConfig( to_integer( r.epIdx ) ).transferTypeOut = USB2_TT_ISOCHRONOUS_C ) then
                  epObLoc( to_integer( rd.epIdx ) ).mstOut.don <= '1';
                  epObLoc( to_integer( rd.epIdx ) ).mstOut.err <= '1';
               end if;
               v.state := IDLE;
            end if;   

         when ISO_OUT =>
            epObLoc( to_integer( r.epIdx ) ).mstOut.vld <= usb2Rx.mst.vld;
            epObLoc( to_integer( r.epIdx ) ).mstOut.don <= usb2Rx.mst.don;
            epObLoc( to_integer( r.epIdx ) ).mstOut.err <= usb2Rx.mst.err;
            if ( usb2Rx.mst.don = '1' ) then
               v.state := IDLE;
            end if;

         when ISO_INP =>
            if ( r.donFlg = '1' ) then
               txDataMst.don                               <= r.donFlg;
               epObLoc( to_integer( r.epIdx ) ).subInp.rdy <= txDataSub.don and not r.nakDon;
               if ( txDataSub.don = '1' ) then
                  v.state       := IDLE;
               end if;
            else
               epObLoc( to_integer( r.epIdx ) ).subInp.rdy <= txDataSub.rdy;
               txDataMst.vld                               <= ei.mstInp.vld;
               txDataMst.don                               <= ei.mstInp.don;

               if ( ei.bFramedInp = '1' ) then
                  -- if they don't want us to frame the input data
                  -- then we must assert txDatMst.don as soon as ei.mstInp.vld turns off
                  -- we then proceed to the ACK phase
                  txDataMst.don <= not ei.mstInp.vld;

                  if ( ei.mstInp.vld = '0' ) then
                     v.donFlg      := '1';
                  end if;
               end if;
              
               -- consume one item and create a fragment if we filled the segment
               if ( ( ei.mstInp.vld and txDataSub.rdy ) = '1' ) then
                  v.dataCounter := r.dataCounter - 1;
                  if ( r.dataCounter = 0 ) then
                     v.donFlg := '1';
                  end if;
               end if;

               -- if we consumed the last item then we're done
               if ( ei.mstInp.don = '1' ) then
                  v.donFlg := '1';
               end if;

               if ( (    (    (not ei.bFramedInp and not ei.mstInp.don)
                           or (    ei.bFramedInp and     ei.mstInp.vld)
                         )
                     and txDataSub.don
                     and txDataSub.err
                    ) = '1' ) then
                  -- phy abort
                  v.state := DUMP;
               end if;
            end if;

         when DUMP =>
            epObLoc( to_integer( r.epIdx ) ).subInp.rdy <= '1';
            if ( (   (not ei.bFramedInp and     ei.mstInp.don)
                  or (    ei.bFramedInp and not ei.mstInp.vld)
                  ) = '1' ) then
                  v.state := IDLE;
            end if;

         when DATA_OUT | DRAIN =>
            if ( r.state = DATA_OUT ) then
               bufWrEna <= usb2Rx.mst.vld;
               if ( usb2Rx.mst.vld = '1' ) then
                  v.bufRWIdx := r.bufRWIdx + 1;
               end if;
            end if;
            if ( usb2Rx.mst.don = '1' ) then
               if ( usb2Rx.mst.err = '1' or r.pid = USB2_PID_SPC_NONE_C ) then
                  -- corrupted or ISO_OUT; no handshake
                  v.state   := IDLE;
               else
                  if ( r.state = DATA_OUT ) then
                     -- toggle / reset only if sequence bits matched (-> we are in DATA_OUT state)
                     -- and there was no crc or other reception error
                     if ( r.tok(3 downto 2) = USB2_PID_TOK_SETUP_C(3 downto 2) ) then
                        v.dataTglOut( to_integer( r.epIdx ) ) := '1';
                        v.dataTglInp( to_integer( r.epIdx ) ) := '1';
                     else
                        v.dataTglOut( to_integer( r.epIdx ) ) := not r.dataTglOut( to_integer( r.epIdx ) );
                     end if;
                     -- release the buffer
                     v.bufVldIdx := r.bufRWIdx;
                  end if;
                  v.timer    := TIME_HSK_TX_C;
                  v.nxtState := HSK;
                  v.state    := WAIT_TX;
               end if;
            end if;

         when DATA_INP =>
            bufWriteInp    <= '0' & ei.mstInp.dat;
            txDataMst.vld  <= ei.mstInp.vld;
            txDataMst.don  <= ei.mstInp.don;

            if ( ei.bFramedInp = '1' ) then
               -- if they don't want us to frame the input data
               -- then we must assert txDatMst.don as soon as ei.mstInp.vld turns off
               -- we then proceed to the ACK phase
               txDataMst.don <= not ei.mstInp.vld;

               if ( ei.mstInp.vld = '0' ) then
                  v.donFlg      := '1';
                  v.bufInpVld   := '1';
                  v.bufInpPart  := '0';
                  v.state       := WAIT_DON;
               end if;
            end if;

            -- txDataSub.don = '1' and txDataSub.err = '1' is an abort condition of the PHY
            -- don't consume the data in this case.
            -- Note that if bFramedInp is asserted (unframed stream) then 'txDataSub.don' cannot
            -- be asserted here since we just assert txDataMst.don during this cycle and immediately
            -- proceed to WAIT_DON.
            epObLoc( to_integer( r.epIdx ) ).subInp.rdy <= txDataSub.rdy or (txDataSub.don and not txDataSub.err);

            if ( ( ei.mstInp.vld and txDataSub.rdy and not (txDataSub.don and txDataSub.err) ) = '1' ) then
               -- store consumed data in buffer
               v.bufRWIdx       := r.bufRWIdx + 1;
               bufWrEna         <= '1';
               v.dataCounter    := r.dataCounter - 1;
               v.bufInpPart     := '1';
               v.bufInpEpIdx    := r.epIdx;
               v.retryTimeout   := INP_TIMO_MS_G;
               if ( r.dataCounter = 0 ) then
                  v.donFlg      := '1';
                  v.bufInpVld   := '1';
                  v.bufInpPart  := '0';
                  v.state       := WAIT_DON;
                  -- doesn't matter if the data counter will overflow
                  -- v.dataCounter := r.dataCounter;
               end if;
            end if;

            if ( (ei.mstInp.don and txDataSub.rdy) = '1' ) then
               -- if this is a 'don' cycle then we must turn subInp.rdy
               -- until txDataSub.don is asserted
               v.donFlg     := not txDataSub.don;
               v.bufInpVld  := '1';
               v.bufInpPart := '0';
               v.state      := WAIT_DON;
            end if;

            if ( txDataSub.don = '1' ) then
               -- we can end up here
               --   1) if the master signals an error
               --   2) if the PHY signals an error
               --   3) if a NULL packet is sent (rdy never asserted)
               v.donFlg      := '0';
               v.state       := IDLE;
               if ( ei.mstInp.err = '1' ) then
                  -- mstInp.err                               => PHY should abort TX packet
                  -- tx should send a bad packet; we'll not see an ack
                  -- also: it doesn't matter if we write to the buffer
                  -- bufWrEna   <= '0';
                  invalidateBuffer( v );
               elsif ( txDataSub.err = '1' ) then
                  -- PHY abort (keep current buffer contents)
                  -- save buffer and set bufRWIdx early so that readback data will be available
                  v.bufEndIdx  := r.bufRWIdx;
                  v.bufRWIdx   := r.bufVldIdx;
               else
                  -- txDataSub.don = '1' w/o error implies that the master had
                  -- already asserted 'don'; -> buffer complete.
                  v.bufInpVld  := '1';
                  v.bufInpPart := '0';
                  v.state      := WAIT_DON;
               end if;
            end if;

            -- replay INP data from the buffer (retry)
         when DATA_REP =>
            txDataMst.err <= '0';
            txDataMst.dat <= r.tmp;
            txDataMst.vld <= '1';
            if ( r.tmpVld = '1' ) then
               txDataMst.dat <= r.tmp;
            else
               txDataMst.dat <= bufReadbackInp(7 downto 0);
            end if;
            if    ( txDataSub.don = '1' ) then
               -- aborted by PHY
               -- set bufRWIdx early so that readback data will be available
               v.bufRWIdx    := r.bufVldIdx;
               v.state       := IDLE;
            elsif ( txDataSub.rdy = '1' ) then
               v.dataCounter := r.dataCounter - 1;
               -- either we consumed the tmp buf or it was invalid already
               v.tmpVld      := '0';
               -- schedule reading next word we would have space in the buffer
               v.bufRWIdx    := r.bufRWIdx + 1;
               if ( r.bufRWIdx = r.bufEndIdx ) then
                  -- RWIdx has already advanced to the next word when we sent the last
                  -- 'good' one
                  if ( r.bufInpPart = '1' ) then
                     -- continue reading
                     v.state    := DATA_INP;
                  else
                     v.donFlg   := '1';
                     v.state    := WAIT_DON;
                     v.bufRWIdx := r.bufRWIdx;
                  end if;
               end if;
            elsif ( r.tmpVld = '0' ) then
               -- must catch the readout in the tmp buffer
               v.tmpVld   := '1';
               v.tmp      := bufReadbackInp(7 downto 0);
            end if;

         when WAIT_TX =>
            -- if we get here on the way to DATA_REP state then
            -- we must catch the first readout
            if ( r.tmpVld = '0' ) then
               v.tmpVld := '1';
               v.tmp    := bufReadbackInp(7 downto 0);
            end if;
            if ( r.se0JSeen ) then
               if ( usb2TimerExpired( r.timer ) ) then
                  v.state := r.nxtState;
               end if;
            elsif ( usb2TimerExpired( r.se0JTimer ) ) then
               -- SE0 has not been detected yet; reset timer
               v.timer    := r.timer;
            else
               v.timer    := r.timer - r.se0JTimer;
               v.se0JSeen := true;
            end if;

         when WAIT_DON =>
            txDataMst.don <= r.donFlg;
            if ( r.donFlg = '1' ) then
               if ( txDataSub.don = '1' ) then
                  if ( txDataSub.err = '1' ) then
                     -- PHY abort (keep current buffer contents)
                     -- save buffer and set bufRWIdx early so that readback data will be available
                     v.bufEndIdx   := r.bufRWIdx;
                     v.bufRWIdx    := r.bufVldIdx;
                     v.state       := IDLE;
                  else
                     v.donFlg := '0';
                  end if;
               end if;
            else
               v.timer    := TIME_WAIT_ACK_C;
               if ( devStatus.hiSpeed ) then
                  v.state := WAIT_ACK;
               else
                  v.state := WAIT_FS_SE0;
                  -- timer starts only once we have seen the SE0 -> J transition
                  usb2TimerPause( v.timer );
               end if;
            end if;

         when WAIT_FS_SE0 =>
            if ( usb2Rx.isRxCmd and ( usb2Rx.rxCmd(1 downto 0) = ULPI_RXCMD_LINE_STATE_SE0_C ) ) then
               v.state    := WAIT_FS_J;
            end if;

         when WAIT_FS_J =>
            if ( usb2Rx.isRxCmd and ( usb2Rx.rxCmd(1 downto 0) = ULPI_RXCMD_LINE_STATE_FS_J_C ) ) then
               v.state := WAIT_FS_K;
               -- now start the timer
               usb2TimerStart( v.timer );
            end if;

         when WAIT_FS_K =>
            if ( usb2Rx.isRxCmd and ( usb2Rx.rxCmd(1 downto 0) = ULPI_RXCMD_LINE_STATE_FS_K_C ) ) then
               v.state    := WAIT_ACK;
               v.timer    := USB2_TIMER_MAX_C; -- should never expire; frame has started already
               -- we still use a timeout so that we can simply bypass the WAIT_FS... states
               -- in high-speed mode
            end if;

         when WAIT_ACK =>
            if ( ( usb2Rx.pktHdr.vld = '1' ) and ( usb2Rx.pktHdr.pid = USB2_PID_HSK_ACK_C ) ) then
               v.dataTglInp( to_integer( r.epIdx ) ) := not r.dataTglInp( to_integer( r.epIdx ) );
               -- ok to throw stored data away
               invalidateBuffer( v );
               v.state := IDLE;
            elsif ( usb2TimerExpired( r.timer ) or ( usb2Rx.pktHdr.vld = '1' ) ) then
               -- timeout or NAK: save buffer
               v.bufEndIdx   := r.bufRWIdx;
               -- set bufRWIdx early so that readback data will be available
               v.bufRWIdx    := r.bufVldIdx;
               v.state       := IDLE;
            end if;

         when HSK =>
            -- one cycle delay in case we change v.pid
            txDataMst.don <= r.donFlg;
            v.donFlg      := '1';
            -- SETUP does not participate in PING protocol
            if ( devStatus.hiSpeed and r.pid = USB2_PID_HSK_ACK_C and r.tok = USB2_PID_TOK_OUT_C and ei.subOut.rdy = '0' ) then
               v.pid := USB2_PID_HSK_NYET_C;
            end if;
            if ( haltedInp or haltedOut ) then
               v.pid := USB2_PID_HSK_STALL_C;
            end if;
            if ( txDataSub.don = '1' ) then
               -- no need to wait until transmission is done;
               -- we can go back to idle - the phy cannot receive
               -- anything until after TX is done anyways.
               v.state := IDLE;
            end if;

      end case;

      -- 9.4.5: CLEAR_FEATURE ENDPOINT_HALT always results in the data toggle being reset
      v.dataTglInp := v.dataTglInp and not devStatus.clrHaltedInp(r.dataTglInp'range);
      v.dataTglOut := v.dataTglOut and not devStatus.clrHaltedOut(r.dataTglOut'range);

      if ( devStatus.state /= DEFAULT and devStatus.state /= ADDRESS and devStatus.state /= CONFIGURED ) then
         -- discard everything we've done
         rin <= r;
      else
         rin <= v;
      end if;

      if ( r.milliSec( r.milliSec'left ) = '1' ) then
         v.milliSec := MILLI_SEC_C; 
         if ( not usb2TimerExpired( r.retryTimeout ) ) then
            v.retryTimeout := r.retryTimeout - 1;
         end if;
      else
         v.milliSec := r.milliSec - 1;
      end if;

      epObDbg <= epObLoc( to_integer( r.epIdx ) );

   end process P_COMB;

   P_COMB_READER : process ( r.bufVldIdx, rd, epIb, bufReadOut, epConfig ) is
      variable v : BufReaderType;
   begin
      v := rd;

      v.mstOut.don := '0';
      v.mstOut.vld := '0';
      if ( rd.mstOut.don = '1' ) then
         -- mark as processed
         v.dataCounter := (others => '1');
         v.isSetup     := false;
      else
         -- see if we have anything new to offer
         if ( ( rd.bufRdIdx = r.bufVldIdx ) or ( bufReadOut(8) = '1' ) ) then
            -- End of packet sequence (setup packets do not require an empty data packet)
            if ( rd.dataCounter < epConfig( to_integer( rd.epIdx) ).maxPktSizeOut or rd.isSetup ) then
               v.mstOut.don := '1';
            end if;
            if ( rd.bufRdIdx /= r.bufVldIdx ) then
               -- new packet header
               v.epIdx       := unsigned( bufReadOut(3 downto 0) );
               v.isSetup     := (bufReadOut(7 downto 4) = USB2_PID_TOK_SETUP_C);
               v.dataCounter := (others => '0');
               v.bufRdIdx    := rd.bufRdIdx + 1;
            end if;
         else
            -- new data
            v.dataCounter := rd.dataCounter + 1;
            v.mstOut.vld  := '1';
            v.mstOut.dat  := bufReadOut(7 downto 0);
            v.bufRdIdx    := rd.bufRdIdx + 1;
         end if;
      end if;

      rdin <= v;
   end process P_COMB_READER;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r  <= REG_INIT_C;
            rd <= BUF_READER_INIT_C;
         else
            r  <= rin;
            rd <= rdin;
         end if;
      end if;
   end process P_SEQ;

   U_BUF : entity work.Usb2Bram
      generic map (
         DATA_WIDTH_G => BUF_WIDTH_C,
         ADDR_WIDTH_G => LD_BUFSZ_C,
         EN_REGA_G    => false,
         EN_REGB_G    => false
      )
      port map (
         clka         => clk,
         ena          => '1',

         -- through this port we write OUT data and readback INP data (for retries)
         wea          => bufWrEna,
         addra        => r.bufRWIdx,
         rdata        => bufReadbackInp,
         wdata        => bufWriteInp,

         -- readout of OUT data (after checksum is validated)
         clkb         => clk,
         enb          => '1',
         web          => '0',
         addrb        => rdin.bufRdIdx,
         rdatb        => bufReadOut,
         wdatb        => open
      );

end architecture Impl;
