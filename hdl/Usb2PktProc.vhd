library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

entity Usb2PktProc is
   generic (
      SIMULATION_G    : boolean  := false;
      MARK_DEBUG_G    : boolean  := true;
      NUM_ENDPOINTS_G : positive := 1
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';
      devStatus       : in  Usb2DevStatusType;
      epConfig        : in  Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_G - 1);
      epIb            : in  Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_G - 1);
      epOb            : out Usb2EndpPairObArray(0 to NUM_ENDPOINTS_G - 1);

      txDataMst       : out Usb2StrmMstType;
      txDataSub       : in  Usb2StrmSubType;
      rxPktHdr        : in  Usb2PktHdrType;
      rxDataMst       : in  Usb2StrmMstType
   );
end entity Usb2PktProc;

architecture Impl of Usb2PktProc is

   function simt(constant a,b: in natural) return natural is
   begin
      if ( SIMULATION_G ) then return a; else return b; end if;
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


   -- NOTE: there is a 1 clock delay in the recive path due to IO buffering
   --       also     a 1 clock delay in the transmit path due to IO buffering

   -- receive (tok, rx-data) -transmit (hsk); ULPI: HS: 1-14 clocks, FS: 7-18 clocks
   constant TIME_HSK_TX_C        : Usb2TimerType := to_unsigned( simt(20,  10) , Usb2TimerType'length);

   -- receive (tok) -transmit (tx-data)     ; ULPI: HS: 1-14 clocks, FS: 7-18 clocks
   constant TIME_DATA_TX_C       : Usb2TimerType := to_unsigned( simt(20,  10) , Usb2TimerType'length);
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
   -- adding our own 2 cycle latency we'd conclude a max time of 102 - 8 = 94 (HS) and kk
   constant TIME_WAIT_ACK_C      : Usb2TimerType := to_unsigned( simt(20,  96) , Usb2TimerType'length);
   -- receive (tok) - receive(data-pid)     ; USB2: HS: 92-102, FS: 80 - 90 since only receive-path
   --                                         latency is involved these values can be used verbatim
   constant TIME_WAIT_DATA_PID_C : Usb2TimerType := to_unsigned( simt(30,  85) , Usb2TimerType'length);

   constant LD_BUFSZ_C           : natural   := 11;
   constant BUF_WIDTH_C          : natural   :=  9;

   type StateType is ( IDLE, DATA_INP, DATA_REP, ISO_INP, DATA_PID, DATA_OUT, ISO_OUT, DRAIN, WAIT_ACK, HSK );

   type RegType   is record
      state           : StateType;
      dataTglInp      : std_logic_vector(NUM_ENDPOINTS_G - 1 downto 0);
      dataTglOut      : std_logic_vector(NUM_ENDPOINTS_G - 1 downto 0);
      timer           : Usb2TimerType;
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
      donFlg          : std_logic;
      retries         : unsigned(1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      dataTglInp      => (others => '0'),
      dataTglOut      => (others => '0'),
      timer           => (others => '0'),
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
      donFlg          => '0',
      retries         => (others => '0')
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

   attribute MARK_DEBUG of r                    : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of rd                   : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of epConfigDbg          : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufReadOut           : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufWriteInp          : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufWrEna             : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of bufReadbackInp       : signal is toStr(MARK_DEBUG_G);

   function checkTokHdr(
      constant h: Usb2PktHdrType;
      constant s: Usb2DevStatusType;
      constant c: Usb2EndpPairConfigArray) return boolean
   is
      variable epidx : Usb2EndpIdxType;
      variable daddr : Usb2DevAddrType;
   begin
      epidx := usb2TokenPktEndp( h );
      daddr := usb2TokenPktAddr( h );

      -- reject non-tokens or SOF tokens
      if ( not usb2PidIsTok( h.pid ) or ( USB2_PID_TOK_SOF_C(3 downto 2) = h.pid(3 downto 2) ) ) then
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
      if (    USB2_PID_TOK_OUT_C  (3 downto 2) = h.pid(3 downto 2) 
           or USB2_PID_TOK_SETUP_C(3 downto 2) = h.pid(3 downto 2)  ) then
         if ( c( to_integer( epidx ) ).maxPktSizeOut = 0 ) then
            return false;
         end if;
      else 
         if ( c( to_integer( epidx ) ).maxPktSizeInp = 0 ) then
            return false;
         end if;
      end if;
      -- setup transactions can only go to control endpoints
      if ( USB2_PID_TOK_SETUP_C(3 downto 2) = h.pid(3 downto 2) ) then
         if ( c( to_integer( epidx ) ).transferTypeOut /= USB2_TT_CONTROL_C ) then
            return false;
         end if;
      end if;

      return true;
   end function checkTokHdr;

   -- assume the PID is a INP/OUT/SETUP token!
   function isTokInp(constant x : Usb2PidType) return boolean is
   begin
      return x(3 downto 2) = USB2_PID_TOK_IN_C(3 downto 2);
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

   epConfigDbg <= epConfig;

   assert to_integer( TIME_DATA_TX_C ) /= 0 report "TIME_DATA_TX_C must not be zero!" severity failure;

   P_COMB : process ( r, rd, devStatus, epConfig, epIb, txDataSub, rxPktHdr, rxDataMst, bufReadbackInp ) is
      variable v  : RegType;
      variable ei : Usb2EndpPairIbType;
   begin
      v                := r;
      v.prevDevState   := devStatus.state;
      ei               := epIb( to_integer( r.epIdx ) );

      txDataMst        <= ei.mstInp;
      txDataMst.vld    <= '0';
      txDataMst.don    <= '0';
      txDataMst.usr    <= r.pid;
      bufWrEna         <= '0';
      bufWriteInp      <= '0' & rxDataMst.dat;

      for i in epOb'range loop
         epOb(i).subInp <= USB2_STRM_SUB_INIT_C;

         if ( epConfig( i ).transferTypeOut = USB2_TT_CONTROL_C ) then
            epOb(i).mstCtl     <= rd.mstOut;
            epOb(i).mstCtl.vld <= '0';
            epOb(i).mstCtl.don <= '0';
            epOb(i).mstOut     <= rd.mstOut;
            epOb(i).mstOut.vld <= '0';
            epOb(i).mstOut.don <= '0';
            if ( rd.isSetup ) then
               epOb( to_integer( rd.epIdx ) ).mstCtl <= rd.mstOut;
            else
               epOb( to_integer( rd.epIdx ) ).mstOut <= rd.mstOut;
            end if;
         else
            epOb(i).mstCtl  <= USB2_STRM_MST_INIT_C;
            if ( epConfig( i ).transferTypeOut = USB2_TT_ISOCHRONOUS_C ) then
               epOb(i).mstOut        <= rxDataMst;
               epOb(i).mstOut.vld    <= '0';
               epOb(i).mstOut.don    <= '0';
            else
               epOb(i).mstOut  <= rd.mstOut;
               if ( i /= rd.epIdx ) then
                  epOb(i).mstOut.vld <= '0';
                  epOb(i).mstOut.don <= '0';
               end if;
            end if;
         end if;
      end loop;



      if ( r.timer > 0 ) then
         v.timer := r.timer - 1;
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( ( rxPktHdr.vld = '1' ) and checkTokHdr( rxPktHdr, devStatus, epConfig ) ) then
               v.tok         := rxPktHdr.pid;
               v.epIdx       := usb2TokenPktEndp( rxPktHdr );
               ei            := epIb( to_integer( v.epIdx ) );
               if ( isTokInp( rxPktHdr.pid ) ) then
                  v.dataCounter := epConfig( to_integer( v.epIdx ) ).maxPktSizeInp - 1;
                  v.timer       := TIME_DATA_TX_C;
                  if    ( ei.stalledInp = '1' ) then
                     v.pid     := USB2_PID_HSK_STALL_C;
                     v.timer   := TIME_HSK_TX_C;
                     v.state   := HSK;
                  elsif ( epConfig( to_integer( r.epIdx ) ).transferTypeInp = USB2_TT_ISOCHRONOUS_C ) then
                     v.state   := ISO_INP;
                     v.pid     := USB2_PID_DAT_DATA0_C;
                  elsif ( (ei.mstInp.vld or ei.mstInp.don or r.bufInpVld) = '0' ) then
                     v.pid     := USB2_PID_HSK_NAK_C;
                     v.timer   := TIME_HSK_TX_C;
                     v.state   := HSK;
                  else
-- For now we retry forever
--                  if ( r.bufInpVld = '1' ) then
--                     -- a retry
--                     if ( r.retries < 2 ) then
--                        v.retries := r.retries + 1;
--                        v.state   := DATA_REP;
--                        v.timer   := TIME_DATA_TX_C;
--                     else
--                        -- should stall/halt the device or endpoint? for now we just drop
--                        v.retries   := 0;
--                        v.bufRWIdx  := r.bufVldIdx;
--                        v.bufInpVld := '0';
--
                     if ( r.dataTglInp( to_integer( r.epIdx ) ) = '0' ) then
                        v.pid := USB2_PID_DAT_DATA0_C;
                     else
                        v.pid := USB2_PID_DAT_DATA1_C;
                     end if;
                     if ( (r.bufInpVld or r.bufInpPart) = '1' ) then
                        v.state    := DATA_REP;
                        -- pre-load next readout
                        v.bufRWIdx := r.bufRWIdx + 1;
                        v.tmpVld   := '0';
                        if ( r.bufRWIdx = r.bufEndIdx ) then
                           -- empty packet - avoid DATA_REP
                           v.timer    := TIME_WAIT_ACK_C;
                           v.state    := WAIT_ACK;
                           v.donFlg   := '1';
                           v.bufRWIdx := r.bufRWIdx;
                        end if;
                     else
                        v.state := DATA_INP;
                     end if;
                  end if;
               else
                  v.dataCounter := epConfig( to_integer( v.epIdx ) ).maxPktSizeOut - 1;
                  v.timer       := TIME_WAIT_DATA_PID_C;
                  v.state       := DATA_PID;
                  -- make sure there is nothing left in the write area
                  invalidateBuffer( v );
               end if;
            end if;

         when DATA_PID =>
            if ( ( rxPktHdr.vld = '1' ) ) then
               if ( checkDatHdr( rxPktHdr ) ) then
                  if ( ei.stalledOut = '1' ) then
                     v.pid   := USB2_PID_HSK_STALL_C;
                     v.state := DRAIN;
                  elsif ( epConfig( to_integer( r.epIdx ) ).transferTypeOut = USB2_TT_ISOCHRONOUS_C ) then
                     v.state := ISO_OUT; 
                  elsif ( not sequenceOutMatch( v, rxPktHdr ) ) then
                     -- sequence mismatch; discard packet and ACK
                     v.pid   := USB2_PID_HSK_ACK_C;
                     v.state := DRAIN;
                  elsif ( ei.subOut.rdy = '0' ) then
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
                     epOb( to_integer( rd.epIdx ) ).mstOut.don <= '1';
                     epOb( to_integer( rd.epIdx ) ).mstOut.err <= '1';
                  end if;
                  v.state    := IDLE;
               end if;   
            elsif ( r.timer = 0 ) then
               if ( epConfig( to_integer( r.epIdx ) ).transferTypeOut = USB2_TT_ISOCHRONOUS_C ) then
                  epOb( to_integer( rd.epIdx ) ).mstOut.don <= '1';
                  epOb( to_integer( rd.epIdx ) ).mstOut.err <= '1';
               end if;
               v.state := IDLE;
            end if;   

         when ISO_OUT =>
            epOb( to_integer( r.epIdx ) ).mstOut <= rxDataMst;
            if ( rxDataMst.don = '1' ) then
               v.state := IDLE;
            end if;

         when ISO_INP =>
            if ( r.timer = 0 ) then
               epOb( to_integer( r.epIdx ) ).subInp <= txDataSub;
               txDataMst.vld                        <= ei.mstInp.vld;
               txDataMst.don                        <= ei.mstInp.don;
               
-- assume the endpoint is are well behaved and does not try to send excessive data
--               if ( ( ei.mstInp.vld and txDataSub.rdy ) = '1' ) then
--                  v.dataCounter := r.dataCounter - 1;
--                  if ( r.dataCounter = '0' ) then
--                     epOb( to_integer( r.epIdx ) ).subInp.vld <= '0';
--                     epOb( to_integer( r.epIdx ) ).subInp.err <= '1';
--                     epOb( to_integer( r.epIdx ) ).subInp.don <= '1';
--                     v.state := ISO_INP_ABRT;
--                  end if;
--               end if;

               if ( (ei.mstInp.don and txDataSub.don) = '1' ) then
                  v.state := IDLE;
               end if;
            end if;
 
         when DATA_OUT | DRAIN =>
            if ( r.state = DATA_OUT ) then
               bufWrEna <= rxDataMst.vld;
               if ( rxDataMst.vld = '1' ) then
                  v.bufRWIdx := r.bufRWIdx + 1;
               end if;
            end if;
            if ( rxDataMst.don = '1' ) then
               if ( rxDataMst.err = '1' ) then
                  -- corrupted; no handshake
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
                  v.timer   := TIME_HSK_TX_C;
                  v.state   := HSK;
               end if;
               -- if there was a good packet we have already advanced v.bufVldIdx
               -- and invalidateBuffer() does no harm here
               invalidateBuffer( v );
            end if;

         when DATA_INP =>
            bufWriteInp <= '0' & ei.mstInp.dat;
            if ( r.timer = 0 ) then
               epOb( to_integer( r.epIdx ) ).subInp <= txDataSub;
               txDataMst.vld                        <= ei.mstInp.vld;
               txDataMst.don                        <= ei.mstInp.don;
               
               if ( ( ei.mstInp.vld and txDataSub.rdy ) = '1' ) then
                  v.bufRWIdx    := r.bufRWIdx + 1;
                  bufWrEna      <= '1';
                  v.dataCounter := r.dataCounter - 1;
                  v.bufInpPart  := '1';
                  if ( r.dataCounter = 0 ) then
                     v.donFlg      := '1';
                     v.bufInpVld   := '1';
                     v.bufInpPart  := '0';
                     v.timer       := TIME_WAIT_ACK_C;
                     v.state       := WAIT_ACK;
                     -- doesn't matter if the data counter will overflow
                     -- v.dataCounter := r.dataCounter;
                  end if;
               end if;

               if ( txDataSub.don = '1' ) then
                  v.donFlg      := '0';
                  if ( ei.mstInp.err = '1' ) then
                     -- mstInp.err                               => PHY should abort TX packet
                     -- tx should send a bad packet; we'll not see an ack
                     v.timer    := r.timer;
                     v.state    := IDLE;
                     -- it doesn't matter if we write 
                     -- bufWrEna   <= '0';
                     invalidateBuffer( v );
                  else
                     if ( ei.mstInp.don = '1' ) then
                        -- buffer complete
                        v.bufInpVld  := '1';
                        v.bufInpPart := '0';
                     end if;
                     -- txDataSub.don = '1' and mstInp.don = '0' => aborted by PHY
                     v.timer       := TIME_WAIT_ACK_C;
                     v.state       := WAIT_ACK;
                  end if;
               end if;
            end if;

            -- replay INP data from the buffer (retry)
         when DATA_REP =>
            txDataMst.err <= '0';
            txDataMst.dat <= r.tmp;
            if ( r.timer = 0 ) then
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
                        v.timer    := TIME_WAIT_ACK_C;
                        v.state    := WAIT_ACK;
                        v.bufRWIdx := r.bufRWIdx;
                     end if;
                  end if;
               elsif ( r.tmpVld = '0' ) then
                  -- must catch the readout in the tmp buffer
                  v.tmpVld   := '1';
                  v.tmp      := bufReadbackInp(7 downto 0);
               end if;
            elsif ( r.tmpVld = '0' ) then
               -- must still catch the first word off the pipeline
               v.tmpVld   := '1';
               v.tmp      := bufReadbackInp(7 downto 0);
            end if;

         when WAIT_ACK =>

            txDataMst.don <= r.donFlg;
            if ( r.donFlg = '1' ) then
               if ( txDataSub.don = '1' ) then
                  v.donFlg      := '0';
               end if;
            else
                if    ( ( rxPktHdr.vld = '1' ) and ( rxPktHdr.pid = USB2_PID_HSK_ACK_C ) ) then
                  v.dataTglInp( to_integer( r.epIdx ) ) := not r.dataTglInp( to_integer( r.epIdx ) );
                  -- ok to throw stored data away
                  invalidateBuffer( v );
                  v.state := IDLE;
               elsif ( ( r.timer = 0 ) or ( rxPktHdr.vld = '1' ) ) then
                  -- timeout or NAK: save buffer
                  v.bufEndIdx   := r.bufRWIdx;
                  -- set bufRWIdx early so that readback data will be available
                  v.bufRWIdx    := r.bufVldIdx;
                  v.state       := IDLE;
              end if;
            end if;

         when HSK =>
            if ( rd.isSetup ) then
               if ( ( rd.mstOut.don and ei.subOut.don ) = '1' ) then
                  if ( ei.subOut.err = '1' ) then
--                     v.pid := USB2_PID_HSK_STALL_C;
                  end if;
               end if;
            end if;
            if ( (ei.stalledInp or ei.stalledOut) = '1' ) then
               v.pid := USB2_PID_HSK_STALL_C;
            end if;
            if ( r.timer = 0 ) then
               txDataMst.don <= '1';
               if ( txDataSub.don = '1' ) then
                  -- no need to wait until transmission is done;
                  -- we can go back to idle - the phy cannot receive
                  -- anything until after TX is done anyways.
                  v.state := IDLE;
               end if;
            end if;

      end case;

      if ( devStatus.clrHalt = '1' ) then
         v.dataTglInp := r.dataTglInp and not devStatus.selHaltInp(r.dataTglInp'range);
         v.dataTglOut := r.dataTglOut and not devStatus.selHaltOut(r.dataTglOut'range);
      end if;
      if ( devStatus.setHalt = '1' ) then
         v.dataTglInp := r.dataTglInp or devStatus.selHaltInp(r.dataTglInp'range);
         v.dataTglOut := r.dataTglOut or devStatus.selHaltOut(r.dataTglOut'range);
      end if;

      if ( devStatus.state /= DEFAULT and devStatus.state /= ADDRESS and devStatus.state /= CONFIGURED ) then
         -- discard everything we've done
         rin <= r;
      else
         rin <= v;
      end if;

   end process P_COMB;

   P_COMB_READER : process ( r.bufVldIdx, rd, epIb, bufReadOut, epConfig ) is
      variable v : BufReaderType;
   begin
      v := rd;

      -- if we terminated a frame we wait for the downstream to ack.
      -- Could handle other endpoints meanwhile but let's keep it
      -- simple...
      if ( rd.mstOut.don = '1' ) then
         if ( epIb( to_integer( rd.epIdx ) ).subOut.don = '1' ) then
            v.mstOut.don         := '0';
            -- mark as processed
            v.dataCounter := (others => '1');
            v.isSetup     := false;
         end if;
      else
         if ( ( rd.mstOut.vld and epIb( to_integer( rd.epIdx ) ).subOut.rdy ) = '1' ) then
            -- they consumed an item
            v.mstOut.vld  := '0';
         end if;
         if ( v.mstOut.vld = '0' ) then
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

   U_BUF : entity work.Bram
      generic map (
         DATA_WIDTH_G => BUF_WIDTH_C,
         ADDR_WIDTH_G => LD_BUFSZ_C,
         EN_REGA_G    => false,
         EN_REGB_G    => false
      )
      port map (
         clk          => clk,
         rst          => rst,
         ena          => '1',

         -- through this port we write OUT data and readback INP data (for retries)
         wea          => bufWrEna,
         addra        => r.bufRWIdx,
         rdata        => bufReadbackInp,
         wdata        => bufWriteInp,

         -- readout of OUT data (after checksum is validated)
         enb          => '1',
         web          => '0',
         addrb        => rdin.bufRdIdx,
         rdatb        => bufReadOut,
         wdatb        => open
      );

end architecture Impl;
