library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

entity Usb2PktProc is
   generic (
      MARK_DEBUG_G    : boolean := true;
      ENDPOINTS_G     : Usb2EndpPairPropertyArray
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';
      devStatus       : in  Usb2DevStatusType;
      epIb            : in  Usb2EndpPairIbArray(ENDPOINTS_G'range);
      epOb            : out Usb2EndpPairObArray(ENDPOINTS_G'range);

      txDataMst       : out Usb2StrmMstType;
      txDataSub       : in  Usb2StrmSubType;
      rxPktHdr        : in  Usb2PktHdrType;
      rxDataMst       : in  Usb2StrmMstType
   );
end entity Usb2PktProc;

architecture Impl of Usb2PktProc is

   constant NUM_ENDPOINTS_C      : natural := ENDPOINTS_G'length;

   constant LD_TIMER_C           : natural := 18;

   subtype TimerType is unsigned(LD_TIMER_C - 1 downto 0);

   constant SIM_C                : boolean := true;

   function simt(constant a,b: in natural) return natural is
   begin
      if ( SIM_C ) then return a; else return b; end if;
   end function simt;

   constant TIME_HSK_TX_C        : TimerType := to_unsigned( simt(0,  600000) , TimerType'length);
   constant TIME_DATA_RX_C       : TimerType := to_unsigned( simt(0,  600000) , TimerType'length);
   constant TIME_DATA_TX_C       : TimerType := to_unsigned( simt(10, 600000) , TimerType'length);
   constant TIME_WAIT_ACK_C      : TimerType := to_unsigned( simt(10, 600000) , TimerType'length);
   constant TIME_WAIT_DATA_PID_C : TimerType := to_unsigned( simt(0,  600000) , TimerType'length);

   constant LD_BUFSZ_C           : natural   := 11;
   constant BUF_WIDTH_C          : natural   :=  9;

   type StateType is ( IDLE, DATA_INP, DATA_REP, DATA_PID, DATA_OUT, DRAIN, WAIT_ACK, HSK );

   type RegType   is record
      state           : StateType;
      dataTgl         : std_logic_vector(2*NUM_ENDPOINTS_C - 1 downto 0);
      timer           : TimerType;
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
      donFlg          : std_logic;
      retries         : unsigned(1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      dataTgl         => (others => '0'),
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
      dataCounter     => (others => '0')
   );

   signal r                             : RegType := REG_INIT_C;
   signal rin                           : RegType;

   signal rd                            : BufReaderType := BUF_READER_INIT_C;
   signal rdin                          : BufReaderType;

   signal bufWrEna                      : std_logic := '0';
   signal bufReadbackInp                : std_logic_vector(BUF_WIDTH_C - 1 downto 0) := (others => '0');
   signal bufReadOut                    : std_logic_vector(BUF_WIDTH_C - 1 downto 0) := (others => '0');
   signal bufWriteInp                   : std_logic_vector(BUF_WIDTH_C - 1 downto 0) := (others => '0');

   attribute MARK_DEBUG of r            : signal is toStr(MARK_DEBUG_G);

   function checkTokHdr(constant h: Usb2PktHdrType; constant s: Usb2DevStatusType) return boolean is
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
         return (   daddr = USB2_DEV_ADDR_DFLT_C
                 or daddr = s.devAddr            );
      end if;
      -- reject endpoint out of range
      if ( epidx >= ENDPOINTS_G'length ) then
         return false;
      end if;
      -- address must match and the device must be configured
      if ( ( daddr /= s.devAddr ) or ( s.state /= CONFIGURED ) ) then
         return false;
      end if;
      -- the endpoint must exist
      if (    USB2_PID_TOK_OUT_C  (3 downto 2) = h.pid(3 downto 2) 
           or USB2_PID_TOK_SETUP_C(3 downto 2) = h.pid(3 downto 2)  ) then
         if ( ENDPOINTS_G( to_integer( epidx ) ).maxPktSizeOut = 0 ) then
            return false;
         end if;
      else 
         if ( ENDPOINTS_G( to_integer( epidx ) ).maxPktSizeInp = 0 ) then
            return false;
         end if;
      end if;
      -- setup transactions can only go to control endpoints
      if ( USB2_PID_TOK_SETUP_C(3 downto 2) = h.pid(3 downto 2) ) then
         if ( ENDPOINTS_G( to_integer( epidx ) ).transferTypeOut /= USB2_TT_CONTROL_C ) then
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
      return v.dataTgl( to_integer( v.epIdx & "0" ) ) = h.pid(3);
   end function sequenceOutMatch;

   procedure invalidateBuffer(variable v : inout RegType) is
   begin
      v           := v;
      v.bufInpVld := '0';
      v.bufRWIdx  := v.bufVldIdx;
   end procedure invalidateBuffer;

begin

   assert to_integer( TIME_DATA_TX_C ) /= 0 report "TIME_DATA_TX_C must not be zero!" severity failure;

   P_COMB : process ( r, rd, devStatus, epIb, txDataSub, rxPktHdr, rxDataMst, bufReadbackInp ) is
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
      end loop;

      if ( r.timer > 0 ) then
         v.timer := r.timer - 1;
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( ( rxPktHdr.vld = '1' ) and checkTokHdr( rxPktHdr, devStatus ) ) then
               v.tok         := rxPktHdr.pid;
               v.epIdx       := usb2TokenPktEndp( rxPktHdr );
               ei            := epIb( to_integer( v.epIdx ) );
               if ( isTokInp( rxPktHdr.pid ) ) then
                  v.dataCounter := ENDPOINTS_G( to_integer( v.epIdx ) ).maxPktSizeInp - 1;
                  if ( ei.stalledInp = '1' ) then
                     v.pid     := USB2_PID_HSK_STALL_C;
                     v.timer   := TIME_HSK_TX_C;
                     v.state   := HSK;
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
                     if ( r.dataTgl( to_integer( r.epIdx & "1" ) ) = '0' ) then
                        v.pid := USB2_PID_DAT_DATA0_C;
                     else
                        v.pid := USB2_PID_DAT_DATA1_C;
                     end if;
                     if ( r.bufInpVld = '1' ) then
                        v.state    := DATA_REP;
                        -- pre-load next readout
                        v.bufRWIdx := r.bufRWIdx + 1;
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
                     v.timer   := TIME_DATA_TX_C;
                  end if;
               else
                  v.dataCounter := ENDPOINTS_G( to_integer( v.epIdx ) ).maxPktSizeOut - 1;
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
                  v.timer    := TIME_DATA_RX_C;
               else
                  v.state    := IDLE;
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
                        v.dataTgl( to_integer( r.epIdx & "0" ) ) := '1';
                     else
                        v.dataTgl( to_integer( r.epIdx & "0" ) ) := not r.dataTgl( to_integer( r.epIdx & "0" ) );
                     end if;
                     -- release the buffer
                     v.bufVldIdx := r.bufRWIdx;
                  end if;
                  v.timer   := TIME_HSK_TX_C;
                  v.state   := HSK;
                  -- TODO defragmentation
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
               end if;

               if ( ei.mstInp.don = '1' ) then
                  if ( txDataSub.don = '1' ) then
                     if ( ei.mstInp.err = '1' ) then
                        -- tx should send a bad packet; we'll not see an ack
                        v.state    := IDLE;
                        -- it doesn't matter if we write 
                        -- bufWrEna   <= '0';
                        invalidateBuffer( v );
                     else
                        v.timer   := TIME_WAIT_ACK_C;
                        v.state   := WAIT_ACK;
                     end if;
                  end if;
               elsif ( r.dataCounter = 0 ) then
                  v.donFlg      := '1';
                  v.timer       := TIME_WAIT_ACK_C;
                  v.state       := WAIT_ACK;
                  -- doesn't matter if the data counter will overflow
                  -- v.dataCounter := r.dataCounter;
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
               if ( txDataSub.rdy = '1' ) then
                  -- either we consumed the tmp buf or it was invalid already
                  v.tmpVld   := '0';
                  -- schedule reading next word we would have space in the buffer
                  v.bufRWIdx := r.bufRWIdx + 1;
                  if ( r.bufRWIdx = r.bufEndIdx ) then
                     -- RWIdx has already advanced to the next word when we sent the last
                     -- 'good' one
                     v.donFlg   := '1';
                     v.timer    := TIME_WAIT_ACK_C;
                     v.state    := WAIT_ACK;
                     v.bufRWIdx := r.bufRWIdx;
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
                  v.dataTgl( to_integer( r.epIdx & "1" ) ) := not r.dataTgl( to_integer( r.epIdx & "1" ) );
                  -- ok to throw stored data away
                  invalidateBuffer( v );
                  v.state := IDLE;
               elsif ( ( r.timer = 0 ) or ( rxPktHdr.vld = '1' ) ) then
                  -- timeout or NAK: save buffer
                  v.bufInpVld   := '1';
                  v.bufEndIdx   := r.bufRWIdx;
                  -- set bufRWIdx early so that readback data will be available
                  v.bufRWIdx    := r.bufVldIdx;
                  v.state       := IDLE;
              end if;
            end if;

         when HSK =>
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

      -- the spec says that clearing the HALT feature rests the data toggle of an endpoint.
      -- We simply clear it already while halted.
      for i in epIb'range loop
        if ( epIb(i).stalledInp = '1' ) then
           v.dataTgl(2*i+1) := '0';
        end if;
        if ( epIb(i).stalledOut = '1' ) then
           v.dataTgl(2*i+0) := '0';
        end if;
      end loop;

      if ( devStatus.state = CONFIGURED and r.prevDevState /= CONFIGURED ) then
         -- freshly configured; must reset all endpoint state including the toggle bits
         v.dataTgl := (others => '0');
      end if;

      if ( devStatus.state /= DEFAULT and devStatus.state /= ADDRESS and devStatus.state /= CONFIGURED ) then
         -- discard everything we've done
         rin <= r;
      else
         rin <= v;
      end if;

   end process P_COMB;

   P_EP_MUX : process ( rd ) is
   begin
   end process P_EP_MUX;

   P_COMB_READER : process ( r.bufVldIdx, rd, epIb ) is
      variable v : BufReaderType;
   begin
      v := rd;

      -- if we terminated a frame we wait for the downstream to ack.
      -- Could handle other endpoints meanwhile but let's keep it
      -- simple...
      if ( rd.mstOut.don = '1' ) then
         if ( epIb( to_integer( rd.epIdx ) ).subOut.don = '1' ) then
            v.mstOut.don := '0';
         end if;
      else
         if ( ( rd.mstOut.vld and epIb( to_integer( rd.epIdx ) ).subOut.rdy ) = '1' ) then
            -- they consumed an item
            v.mstOut.vld  := '0';
         end if;
         if ( v.mstOut.vld = '0' ) then
            -- see if we have anything new to offer
            if ( ( rd.bufRdIdx = r.bufVldIdx ) or ( bufReadOut(8) = '1' ) ) then
               -- End of packet sequence
               if ( rd.dataCounter < ENDPOINTS_G( to_integer( rd.epIdx) ).maxPktSizeOut ) then
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
         addrb        => rd.bufRdIdx,
         rdatb        => bufReadOut,
         wdatb        => open
      );

end architecture Impl;
