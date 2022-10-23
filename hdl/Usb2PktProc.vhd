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

   constant NUM_ENDPOINTS_C : natural := ENDPOINTS_G'length;

   constant LD_TIMEOUT_C : natural := 18;

   subtype TimeoutType is unsigned(LD_TIMEOUT_C - 1 downto 0);

   constant TIME_HSK_TX_C        : TimeoutType := to_unsigned(600000 , TimeoutType'length);
   constant TIME_DATA_RX_C       : TimeoutType := to_unsigned(600000 , TimeoutType'length);
   constant TIME_DATA_TX_C       : TimeoutType := to_unsigned(600000 , TimeoutType'length);
   constant TIME_WAIT_ACK_C      : TimeoutType := to_unsigned(600000 , TimeoutType'length);
   constant TIME_WAIT_DATA_PID_C : TimeoutType := to_unsigned(600000 , TimeoutType'length);

   type StateType is ( IDLE, DATA_INP, DATA_PID, DATA_OUT, DRAIN, WAIT_ACK, HSK );

   type RegType   is record
      state           : StateType;
      dataTgl         : std_logic_vector(2*NUM_ENDPOINTS_C - 1 downto 0);
      timeout         : TimeoutType;
      prevDevState    : Usb2DevStateType;
      tok             : Usb2PidType;
      epIdx           : Usb2EndpIdxType;
      epSelected      : boolean;
      dataCounter     : Usb2PktSizeType;
      pid             : Usb2PidType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      dataTgl         => (others => '0'),
      timeout         => (others => '0'),
      prevDevState    => DEFAULT,
      tok             => USB2_PID_SPC_NONE_C,
      epIdx           => USB2_ENDP_ZERO_C,
      epSelected      => false,
      dataCounter     => (others => '0'),
      pid             => USB2_PID_HSK_ACK_C
   );

   signal r                             : RegType := REG_INIT_C;
   signal rin                           : RegType;

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
      return ( h.pid /= USB2_PID_DAT_DATA0_C and h.pid /= USB2_PID_DAT_DATA1_C );
   end function checkDatHdr;

   function sequenceOutMatch(constant v : in RegType; constant h : in Usb2PktHdrType) return boolean is
   begin
      return v.dataTgl( to_integer( v.epIdx & "0" ) ) = h.pid(3);
   end function sequenceOutMatch;
begin

   P_COMB : process ( r, devStatus, epIb, txDataSub, rxPktHdr, rxDataMst ) is
      variable v  : RegType;
      variable ei : Usb2EndpPairIbType;
   begin
      v                := r;
      v.prevDevState   := devStatus.state;
      ei               := USB2_ENDP_PAIR_IB_INIT_C;

      txDataMst        <= USB2_STRM_MST_INIT_C;
      txDataMst.vld    <= '0';
      txDataMst.err    <= '0';
      txDataMst.usr    <= r.pid;

      if ( r.timeout > 0 ) then
         v.timeout := r.timeout - 1;
      else
         -- TODO handle aborting
         v.state   := IDLE;
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( ( rxPktHdr.vld = '1' ) and checkTokHdr( rxPktHdr, devStatus ) ) then
               v.tok         := rxPktHdr.pid;
               v.epIdx       := usb2TokenPktEndp( rxPktHdr );
               v.epSelected  := true;
               v.dataCounter := ENDPOINTS_G( to_integer( v.epIdx ) ).maxPktSizeInp - 1;
               ei            := epIb( to_integer( v.epIdx ) );
               if ( isTokInp( rxPktHdr.pid ) ) then
                  if ( ei.stalledInp = '1' ) then
                     v.pid     := USB2_PID_HSK_STALL_C;
                     v.timeout := TIME_HSK_TX_C;
                     v.state   := HSK;
                  elsif ( (ei.mstInp.vld or ei.mstInp.don) = '0' ) then
                     v.pid     := USB2_PID_HSK_NAK_C;
                     v.timeout := TIME_HSK_TX_C;
                     v.state   := HSK;
                  else
                     if ( r.dataTgl( to_integer( r.epIdx & "1" ) ) = '0' ) then
                        v.pid := USB2_PID_DAT_DATA0_C;
                     else
                        v.pid := USB2_PID_DAT_DATA1_C;
                    end if;
                    v.state   := DATA_INP;
                    v.timeout := TIME_DATA_TX_C;
                  end if;
               else
                  v.timeout := TIME_WAIT_DATA_PID_C;
                  v.state   := DATA_PID;
               end if;
            end if;

         when DATA_PID =>
            if ( ( rxPktHdr.vld = '1' ) and checkDatHdr( rxPktHdr ) ) then
               ei            := epIb( to_integer( r.epIdx ) );
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
                  v.pid   := USB2_PID_HSK_ACK_C;
                  v.state := DATA_OUT;
               end if;
               v.timeout  := TIME_DATA_RX_C;
            end if;   

         when DATA_OUT | DRAIN =>
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
                  end if;
                  v.timeout := TIME_HSK_TX_C;
                  v.state   := HSK;
                  -- TODO defragmentation
               end if;
            end if;

         when DATA_INP =>
            ei := epIb( to_integer( r.epIdx ) );
            if ( txDataSub.rdy = '1' ) then 
               if ( ei.mstInp.don = '1' ) then
                  if ( ei.mstInp.err = '1' ) then
                     -- tx should send a bad packet; we'll not see an ack
                     v.state := IDLE;
                  else
                     v.timeout := TIME_WAIT_ACK_C;
                     v.state   := WAIT_ACK;
                  end if;
               elsif ( v.dataCounter = 0 ) then
                  v.timeout := TIME_WAIT_ACK_C;
                  v.state   := WAIT_ACK;
               else
                  v.dataCounter := r.dataCounter - 1;
               end if;
            end if;

         when WAIT_ACK =>
            if ( ( rxPktHdr.vld = '1' ) and ( rxPktHdr.pid = USB2_PID_HSK_ACK_C ) ) then
               v.dataTgl( to_integer( r.epIdx & "1" ) ) := not r.dataTgl( to_integer( r.epIdx & "1" ) );
               v.state := IDLE;
            end if;

         when HSK =>
            txDataMst.don <= '1';
            if ( txDataSub.rdy = '1' ) then
               -- no need to wait until transmission is done;
               -- we can go back to idle - the phy cannot receive
               -- anything until after TX is done anyways.
               v.state := IDLE;
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

   P_EP_MUX : process ( r, txDataSub, rxDataMst, epIb ) is
   begin
   end process P_EP_MUX;

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

end architecture Impl;
