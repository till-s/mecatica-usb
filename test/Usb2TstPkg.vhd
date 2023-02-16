library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;

package Usb2TstPkg is

   function ulpiTstNumBits(constant x: in natural) return natural;

   type Usb2TstEpCfgType is record
      maxPktSizeInp : natural;
      maxPktSizeOut : natural;
   end record Usb2TstEpCfgType;

   constant USB2_TST_EP_CFG_INIT_C : Usb2TstEpCfgType := (
      maxPktSizeInp => 0,
      maxPktSizeOut => 0
   );

   type Usb2TstEpCfgArray is array (natural range 0 to 15) of Usb2TstEpCfgType;

   constant USB2_TST_NULL_DATA_C : Usb2ByteArray(0 to -1) := ( others => (others => '0') );

   signal ulpiTstOb              : ulpiIbType             := ULPI_IB_INIT_C;
   signal ulpiTstIb              : ulpiObType             := ULPI_OB_INIT_C;
   signal ulpiDatIO              : Usb2ByteType           := (others => 'Z');

   signal ulpiTstClk             : std_logic              := '0';
   signal ulpiTstRun             : boolean                := true;

   procedure ulpiClkTick;

   -- configure this package
   -- must be executed prior to using any other procedures
   procedure usb2TstPkgConfig(
      constant cfg : in Usb2TstEpCfgArray
   );

   procedure usb2TstPkgConfig(
       constant epOb : in Usb2EndpPairObArray;
       constant hs   : in boolean := false
   );

   -- send a byte vector on ULPI
   procedure ulpiTstSendVec(
      signal   ob : inout UlpiIbType;
      constant vc : in    Usb2ByteArray;
      constant s  : in    boolean := true; -- start the transaction (send K RXCMD)
      constant e  : in    boolean := true; -- end the transaction (turn bus, signal EOP)
      constant w  : in    integer := 0     -- introduce 'w' wait cycles
   );

   -- compute CRC
   procedure ulpiTstCrc (
      variable c : inout std_logic_vector;
      constant p : in    std_logic_vector;
      constant x : in    std_logic_vector
   );

   -- send a token on ULPI
   procedure ulpiTstSendTok(
      signal   ob : inout UlpiIbType;
      constant t  : in    std_logic_vector;             -- token to send
      constant e  : in    Usb2EndpIdxType;              -- endpoint
      constant a  : in    Usb2DevAddrType               -- usb device address
   );

   -- send a token on ULPI
   procedure ulpiTstSendTok(
      signal   ob : inout UlpiIbType;
      constant t  : in    std_logic_vector;             -- token to send
      constant x  : in    std_logic_vector(10 downto 0) -- data
   );

   procedure ulpiTstSendSOF(
      signal   ob : inout UlpiIbType;
      constant f  : in    unsigned(10 downto 0)         -- frame number
   );

   -- send handshake on ULPI
   procedure ulpiTstSendHsk(
      signal   ob : inout UlpiIbType;
      constant t  : in    std_logic_vector(3 downto 0) -- handshake PID
   );

   -- wait for and return PID
   procedure ulpiTstWaitPid (
      signal   ob  : inout UlpiIbType;
      variable pid : out   std_logic_vector(3 downto 0); -- return PID here
      constant tim : in    natural := 30                 -- timeout (returns NAK in PID)
   );

   -- wait for handshake and return in PID
   procedure ulpiTstWaitHsk (
      signal   ob  : inout UlpiIbType;
      variable pid : inout std_logic_vector(3 downto 0);
      constant timo: in    natural                      := 30;
      constant st  : in    std_logic_vector(7 downto 0) := x"00" -- expected status (00/ff)
   );

   type Usb2TstRetryPolicyType is ( NO_RETRY, NAK, PING );

   -- send a data packet (compute + append checksum)
   procedure ulpiTstSendDatPkt(
      signal   ob  : inout UlpiIbType;
      constant pid : in    std_logic_vector(3 downto 0); -- DATA0/DATA1
      constant v   : in    Usb2ByteArray;                -- payload
      constant w   : in    natural := 0                  -- wait cycles
   );

   -- send data breaking longer sequences in fragments that fit the maxPktSize
   -- the last fragment is < maxPktSize (possibly an empty packet)
   procedure ulpiTstSendDat(
      signal   ob      : inout UlpiIbType;
      variable stl     : out   boolean;                      -- stalled
      constant v       : in    Usb2ByteArray;                -- payload
      constant epo     : in    Usb2EndpIdxType;              -- endpoint
      constant dva     : in    Usb2DevAddrType;              -- usb device address
      constant stup    : in    boolean := false;             -- send with SETUP token rather than OUT
      constant rtr     : in    natural := 0;                 -- resend 'rtr' times (mimick lost ACK)
      constant w       : in    natural := 0;                 -- wait cycles
      constant timo    : in    natural := 30;                -- timeout to wait for handshake
      constant epid    : in    std_logic_vector(3 downto 0) := USB2_PID_HSK_ACK_C; -- expected handshake
      constant fram    : in    boolean                      := true; -- frame with small tail packet
      constant rtrPol  : in    Usb2TstRetryPolicyType       := NO_RETRY
   );

   -- send data breaking longer sequences in fragments that fit the maxPktSize
   -- the last fragment is < maxPktSize (possibly an empty packet)
   procedure ulpiTstSendDat(
      signal   ob      : inout UlpiIbType;
      constant v       : in    Usb2ByteArray;                -- payload
      constant epo     : in    Usb2EndpIdxType;              -- endpoint
      constant dva     : in    Usb2DevAddrType;              -- usb device address
      constant stup    : in    boolean := false;             -- send with SETUP token rather than OUT
      constant rtr     : in    natural := 0;                 -- resend 'rtr' times (mimick lost ACK)
      constant w       : in    natural := 0;                 -- wait cycles
      constant timo    : in    natural := 30;                -- timeout to wait for handshake
      constant epid    : in    std_logic_vector(3 downto 0) := USB2_PID_HSK_ACK_C; -- expected handshake
      constant fram    : in    boolean                      := true; -- frame with small tail packet
      constant rtrPol  : in    Usb2TstRetryPolicyType       := NO_RETRY
   );

   -- wait for a data packet; may return NAK in 'epi' if endpoint has no data
   procedure ulpiTstRecvDatPkt (
      signal   ob  : inout UlpiIbType;
      variable epi : inout std_logic_vector(3 downto 0); -- expected PID (DATA0/DATA1); returns actual received pid
      variable eda : inout Usb2ByteArray;                -- received data
      variable edal: inout integer;
      constant w   : in    integer := 0;                 -- wait cycles
      constant timo: in    natural := 30;                -- timeout waiting for pid
      constant abrt: in    integer := -1;                -- force PHY abort condition on ULPI after
                                                         -- abrt bytes (-1 -> no abort).
      constant npid: in    boolean := false;             -- dont return mismatching PID
      constant chk : in    boolean := false              -- treat 'eda' as an input for verification
   );

   -- helper with constant comparison data
   procedure ulpiTstWaitDatPkt (
      signal   ob  : inout UlpiIbType;
      variable epi : inout std_logic_vector(3 downto 0); -- expected PID (DATA0/DATA1); returns actual received pid
      constant eda : in    Usb2ByteArray;                -- expected data
      constant w   : in    integer := 0;                 -- wait cycles
      constant timo: in    natural := 30;                -- timeout waiting for pid
      constant abrt: in    integer := -1;                -- force PHY abort condition on ULPI after
                                                         -- abrt bytes (-1 -> no abort).
      constant npid: in    boolean := false              -- dont return mismatching PID
   );

   -- wait for data reassembling until short packet is detected
   procedure ulpiTstRecvDat(
      signal   ob  : inout UlpiIbType;
      variable eda : inout Usb2ByteArray;                     -- received data
      variable edal: inout integer;                           -- length of received data
      constant epi : in    Usb2EndpIdxType;                   -- endpoint
      constant dva : in    Usb2DevAddrType;                   -- usb device address
      constant rtr : in    natural                      := 0; -- let target retry by not sending ACK for 'rtr' times
      constant rak : in    integer                      := 0; -- accept NAK to IN token from target 'rak' times (-1 => inf)
      constant w   : in    natural                      := 0; -- wait cycles
      constant timo: in    natural                      := 30; -- timeout waiting for data (from IN token)
      constant abrt: in    integer                      := -1; -- force PHY abort after 'abrt' bytes
      constant nofr: in    boolean                      := false; -- dont reassemble fragments
      constant estl: in    boolean                      := false; -- expect stall
      constant chk : in    boolean                      := false  -- treat 'eda' as an input for verification
   );

   -- helper with constant comparison data
   procedure ulpiTstWaitDat(
      signal   ob  : inout UlpiIbType;
      constant eda : in    Usb2ByteArray;                     -- expected data
      constant epi : in    Usb2EndpIdxType;                   -- endpoint
      constant dva : in    Usb2DevAddrType;                   -- usb device address
      constant rtr : in    natural                      := 0; -- let target retry by not sending ACK for 'rtr' times
      constant rak : in    integer                      := 0; -- accept NAK to IN token from target 'rak' times (-1 => inf )
      constant w   : in    natural                      := 0; -- wait cycles
      constant timo: in    natural                      := 30; -- timeout waiting for data (from IN token)
      constant abrt: in    integer                      := -1; -- force PHY abort after 'abrt' bytes
      constant nofr: in    boolean                      := false; -- dont reassemble fragments
      constant estl: in    boolean                      := false -- expect stall
   );

   -- send a control sequence
   procedure ulpiTstSendCtlReq(
      signal   ob  : inout UlpiIbType;
      constant cod : in    unsigned;                                           -- request code (supported by this procedure)
      constant dva : in    Usb2DevAddrType;                                    -- usb device address
      constant val : in    std_logic_vector(15 downto 0) := (others => '0');   -- request value
      constant idx : in    std_logic_vector(15 downto 0) := (others => '0');   -- request index
      constant eda : in    Usb2ByteArray := USB2_TST_NULL_DATA_C;              -- expected data (ctl read)
      constant rtr : in    natural := 0;                                       -- rtr passed to underlying transactions
      constant w   : in    natural := 0;                                       -- wait cycles (passed down)
      constant timo: in    natural := 30;                                      -- timeout (passed down)
      constant epid: in    std_logic_vector(3 downto 0) := USB2_PID_HSK_ACK_C; -- expected handshake response to SETUP
      constant typ : in    std_logic_vector := ""                              -- explicit request type; overrides guessing
   );

   -- wait for a register transaction (on ulpi)
   procedure ulpiTstRegWait(
      signal    ob : inout UlpiIbType;
      variable   a : out   natural; -- address
      variable  rnw: out   boolean; -- read (write when false)
      variable   d : out   std_logic_vector(7 downto 0) -- write data
   );

   -- complete a register read transaction (on ulpi)
   procedure ulpiTstRegReadComplete(
      signal    ob : inout UlpiIbType;
      constant   d : in    std_logic_vector(7 downto 0) -- read data
   );

   -- handle initial PHY setup
   procedure ulpiTstHandlePhyInit(
      signal    ob : inout UlpiIbType
   );

end package Usb2TstPkg;

package body Usb2TstPkg is

   function ulpiTstNumBits(constant x: in natural)
   return natural is
      variable tst : natural := 2;
      variable n   : natural := 1;
   begin
-- does not work; log2(8) is slightly less than 3
--      return natural( floor( log2( real( x ) ) ) ) + 1;
      while x >= tst loop
         n   := n + 1;
         tst := 2*tst;
      end loop;
      return n;
   end function ulpiTstNumBits;

   constant MAX_ENDPOINTS_C : natural := 16;

   shared variable dtglInp : std_logic_vector(0 to MAX_ENDPOINTS_C - 1) := (others => '0');
   shared variable dtglOut : std_logic_vector(0 to MAX_ENDPOINTS_C - 1) := (others => '0');
   shared variable hiSpeed : boolean                                    := false;

   shared variable epCfg   : Usb2TstEpCfgArray := (
      -- use initial size so we are able to read the device descriptor
      0      => ( maxPktSizeInp => 8, maxPktSizeOut => 8 ),
      others => ( maxPktSizeInp => 0, maxPktSizeOut => 0 )
   );

   procedure ulpiClkTick
   is
   begin
      wait until rising_edge(ulpiTstClk);
   end procedure ulpiClkTick;

   -- send a byte vector on ULPI
   procedure ulpiTstSendVec(
      signal   ob : inout UlpiIbType;
      constant vc : in    Usb2ByteArray;
      constant s  : in    boolean := true; -- start the transaction (send K RXCMD)
      constant e  : in    boolean := true; -- end the transaction (turn bus)
      constant w  : in    integer := 0     -- introduce 'w' wait cycles
   ) is
      function RXCMD_F(
         constant act : in std_logic := '1';
         constant lin : in std_logic_vector(1 downto 0) := ULPI_RXCMD_LINE_STATE_FS_K_C
      ) return Usb2ByteType is
         variable v : Usb2ByteType := (others => '0');
      begin
         v(ULPI_RXCMD_RX_ACTIVE_BIT_C)          := act;
         v(ULPI_RXCMD_LINE_STATE_FS_K_C'range ) := lin;
         return v;
      end function RXCMD_F;
      constant RXCMD_C : Usb2ByteType := RXCMD_F;
   begin
      if ( ob.dir = '0' ) then
         ob.dir <= '1';
         ob.nxt <= '1';
         ob.dat <= (others => 'Z');
         ulpiClkTick;
         -- turn
      end if;
      if ( s ) then
         -- fake SYNC
         ob.nxt <= '0';
         ob.dat <= RXCMD_C;
         ob.dat( ULPI_RXCMD_LINE_STATE_FS_K_C'range ) <= ULPI_RXCMD_LINE_STATE_FS_K_C;
         ulpiClkTick;
         ob.nxt <= '1';
      end if;
      for i in vc'range loop
         ob.dat <= vc(i);
         for j in 0 to w - 1 loop
            ob.nxt <= '0';
            ob.dat <= RXCMD_C;
            ulpiClkTick;
            ob.dat <= vc(i);
            ob.nxt <= '1';
         end loop;
         ulpiClkTick;
      end loop;
      if ( e ) then
         ob.nxt <= '0';
         ob.dat <= RXCMD_C;
         ob.dat( ULPI_RXCMD_LINE_STATE_SE0_C'range ) <= ULPI_RXCMD_LINE_STATE_SE0_C;
         ulpiClkTick;
         ob.dat( ULPI_RXCMD_LINE_STATE_FS_J_C'range ) <= ULPI_RXCMD_LINE_STATE_FS_J_C;
         ulpiClkTick;
         ob.dat(ULPI_RXCMD_RX_ACTIVE_BIT_C) <= '0';
         ulpiClkTick;
         ob.dir <= '0';
         ulpiClkTick;
         -- turn
      end if;
   end procedure ulpiTstSendVec;

   -- compute CRC
   procedure ulpiTstCrc (
      variable c : inout std_logic_vector;
      constant p : in    std_logic_vector;
      constant x : in    std_logic_vector
   ) is
      variable t : std_logic;
   begin
      c := c;
      for i in x'right to x'left loop
         t := c(0);
         c := '0' & c(c'left downto 1);
         if ( (t xor x(i)) = '1' ) then
            c := c xor p;
         end if;
      end loop;
   end procedure ulpiTstCrc;

   procedure ulpiTstSendRxCmd(
      signal   ob : inout UlpiIbType;
      constant x  : in Usb2ByteType
   ) is
      variable turn : boolean;
   begin
      turn := (ob.dir = '0');
      if ( turn ) then
         ob.dir <= '1';
         ob.dat <= (others => 'Z');
         ob.nxt <= '0';
         ulpiClkTick;
      end if;
      ob.nxt <= '0';
      ob.dat <= x;
      ulpiClkTick;
      if ( turn ) then
         ob.dir <= '0';
         ob.dat <= (others => 'Z');
         ulpiClkTick;
      end if;
      ob.dat <= (others => '0');
      ulpiClkTick;
   end procedure ulpiTstSendRxCmd;

   -- send a token on ULPI
   procedure ulpiTstSendTok(
      signal   ob : inout UlpiIbType;
      constant t  : in    std_logic_vector;             -- token to send
      constant e  : in    Usb2EndpIdxType;              -- endpoint
      constant a  : in    Usb2DevAddrType               -- usb device address
   ) is
      variable x : std_logic_vector(10 downto 0);
   begin
      x := std_logic_vector( e ) & a;
      ulpiTstSendTok( ob, t, x );
   end procedure ulpiTstSendTok;

   procedure ulpiTstSendTok(
      signal   ob : inout UlpiIbType;
      constant t  : in    std_logic_vector;             -- token to send
      constant x  : in    std_logic_vector(10 downto 0) -- data
   ) is
      variable v : Usb2ByteArray(0 to 2);
      variable c : std_logic_vector( 4 downto 0);
      variable e : Usb2EndpIdxType;
   begin
      if ( t'length = 2 ) then
         v(0) := not t & "10" & t & "01";
      else
         v(0) := not t & t;
      end if;
      c    := USB2_CRC5_INIT_C(c'range);
      ulpiTstCrc( c, USB2_CRC5_POLY_C(c'range), x );
      v(1) := x(7 downto 0);
      v(2) := not c & x(10 downto 8);
      ulpiTstSendVec( ob, v );
      if ( v(0)(3 downto 0) = USB2_PID_TOK_SETUP_C ) then
         e := Usb2EndpIdxType( x(10 downto 7) );
         dtglInp( to_integer( unsigned( e ) ) ) := '0';
         dtglOut( to_integer( unsigned( e ) ) ) := '0';
      end if;
   end procedure ulpiTstSendTok;

   procedure ulpiTstSendSOF(
      signal   ob : inout UlpiIbType;
      constant f  : in    unsigned(10 downto 0)         -- frame number
   ) is
   begin
      ulpiTstSendTok( ob, USB2_PID_TOK_SOF_C, std_logic_vector( f ) );
   end procedure ulpiTstSendSOF;

   -- send handshake on ULPI
   procedure ulpiTstSendHsk(
      signal   ob : inout UlpiIbType;
      constant t  : in  std_logic_vector(3 downto 0) -- handshake PID
   ) is
      constant c : Usb2ByteArray := ( 0 => (not t & t ) );
   begin
      ulpiTstSendVec( ob, c );
   end procedure ulpiTstSendHsk;

   -- wait for and return PID
   procedure ulpiTstWaitPid (
      signal   ob  : inout UlpiIbType;
      variable pid : out   std_logic_vector(3 downto 0); -- return PID here
      constant tim : in    natural := 30                 -- timeout (returns NAK in PID)
   ) is
      variable cnt : natural := tim;
   begin
      while ulpiTstIb.dat = x"00" loop
         ulpiClkTick;
         if ( cnt = 0 ) then
            pid := USB2_PID_HSK_NAK_C;
            -- report "Timed out; ticks " & integer'image(tim);
            return;
         else
            cnt := cnt - 1;
         end if;
      end loop;
      assert ulpiTstIb.dat(7 downto 4) = "0100" report "not a TXCMD" severity failure;
      ob.nxt <= '1';
      ulpiClkTick;
      assert ulpiTstIb.dat(7 downto 4) = "0100" report "not a TXCMD" severity failure;
      pid := ulpiTstIb.dat(3 downto 0);
   end procedure ulpiTstWaitPid;

   -- wait for handshake and return in PID
   procedure ulpiTstWaitHsk (
      signal   ob  : inout UlpiIbType;
      variable pid : inout std_logic_vector(3 downto 0);
      constant timo: in    natural                      := 30;
      constant st  : in    std_logic_vector(7 downto 0) := x"00" -- expected status (00/ff)
   ) is
   begin
       ulpiTstWaitPid(ob, pid, timo);
-- usb3340 expects NXT during STP  ob.nxt <= '0';
       assert ulpiTstIb.stp = '0' report "unexpected STP" severity failure;
       ulpiClkTick;
       assert ( ulpiTstIb.stp = '1' )                       report "HSK not stopped"     severity failure;
       assert ( ulpiTstIb.dat = st  )                       report "HSK status mismatch" severity failure;
       assert ( pid(1 downto 0) = USB2_PID_GROUP_HSK_C ) report "PID not a HSK" severity failure;
       ulpiTstSendRxCmd( ob, "000000" & ULPI_RXCMD_LINE_STATE_SE0_C );
       ulpiTstSendRxCmd( ob, "000000" & ULPI_RXCMD_LINE_STATE_FS_J_C );
   end procedure ulpiTstWaitHsk;

   -- send a data packet (compute + append checksum)
   procedure ulpiTstSendDatPkt(
      signal   ob  : inout UlpiIbType;
      constant pid : in    std_logic_vector(3 downto 0); -- DATA0/DATA1
      constant v   : in    Usb2ByteArray;                -- payload
      constant w   : in    natural := 0                  -- wait cycles
   ) is
      variable crc : std_logic_vector(15 downto 0);
      constant h   : Usb2ByteArray := ( 0 => ( not pid & pid ) );
      variable t   : Usb2ByteArray(0 to 1);
      variable x   : std_logic;
   begin
      ulpiTstSendVec( ob, h, true,  false, w );
      ulpiTstSendVec( ob, v, false, false, w );
      crc := USB2_CRC16_INIT_C;
      for i in v'range loop
         ulpiTstCrc( crc, USB2_CRC16_POLY_C, v(i) );
      end loop;
      t(0) := not crc( 7 downto 0);
      t(1) := not crc(15 downto 8);
      ulpiTstSendVec( ob, t, false, true, w );
   end procedure ulpiTstSendDatPkt;

   procedure ulpiTstSendDat(
      signal   ob      : inout UlpiIbType;
      constant v       : in    Usb2ByteArray;                -- payload
      constant epo     : in    Usb2EndpIdxType;              -- endpoint
      constant dva     : in    Usb2DevAddrType;              -- usb device address
      constant stup    : in    boolean := false;             -- send with SETUP token rather than OUT
      constant rtr     : in    natural := 0;                 -- resend 'rtr' times (mimick lost ACK)
      constant w       : in    natural := 0;                 -- wait cycles
      constant timo    : in    natural := 30;                -- timeout to wait for handshake
      constant epid    : in    std_logic_vector(3 downto 0) := USB2_PID_HSK_ACK_C; -- expected handshake
      constant fram    : in    boolean                      := true; -- frame with small tail packet
      constant rtrPol  : in    Usb2TstRetryPolicyType       := NO_RETRY
   ) is
      variable stalled : boolean;
   begin
      ulpiTstSendDat(ob, stalled, v, epo, dva, stup, rtr, w, timo, epid, fram, rtrPol);
      assert stalled = false report "Unexpected stall" severity failure;
   end procedure ulpiTstSendDat;

   -- send data breaking longer sequences in fragments that fit the maxPktSize
   -- the last fragment is < maxPktSize (possibly an empty packet)
   procedure ulpiTstSendDat(
      signal   ob      : inout UlpiIbType;
      variable stl     : out   boolean;                      -- aborted due to stalled
      constant v       : in    Usb2ByteArray;                -- payload
      constant epo     : in    Usb2EndpIdxType;              -- endpoint
      constant dva     : in    Usb2DevAddrType;              -- usb device address
      constant stup    : in    boolean := false;             -- send with SETUP token rather than OUT
      constant rtr     : in    natural := 0;                 -- resend 'rtr' times (mimick lost ACK)
      constant w       : in    natural := 0;                 -- wait cycles
      constant timo    : in    natural := 30;                -- timeout to wait for handshake
      constant epid    : in    std_logic_vector(3 downto 0) := USB2_PID_HSK_ACK_C; -- expected handshake
      constant fram    : in    boolean                      := true; -- frame with small tail packet
      constant rtrPol  : in    Usb2TstRetryPolicyType       := NO_RETRY
   ) is
      variable idx : natural;
      constant epou: natural := to_integer( unsigned( epo ) );
      constant MSZ : natural := epCfg( epou ).maxPktSizeOut;
      variable cln : natural := MSZ;
      variable pid : std_logic_vector(3 downto 0);
      variable rr  : natural;
      variable agn : boolean;  -- try again
   begin
      if ( stup ) then
         assert v'length <= MSZ report "excessive setup data (test prog error)" severity failure;
      end if;

      assert not stup or rtrPol /= PING report "Usb spec does not allow ping for setup transactions" severity failure;
      idx := v'low;
      stl := false;
      L_FRAG : while true loop
         cln := v'high + 1 - idx;
         if ( cln > MSZ ) then
            cln := MSZ;
         end if;
         rr  := 0;
         agn := true;
         while rr <= rtr and agn loop
            agn := false;

            if ( rtrPol = PING ) then
               pid := USB2_PID_HSK_NAK_C;
               while (pid = USB2_PID_HSK_NAK_C) loop
                  ulpiTstSendTok(ob, USB2_PID_SPC_PING_C, epo, dva);
                  ulpiClkTick;
                  ulpiTstWaitHsk(ob, pid, timo);
               end loop;
               assert pid = USB2_PID_HSK_ACK_C report "Unexpected handshake during PING" severity failure;
            end if;

            if ( stup ) then
               ulpiTstSendTok(ob, USB2_PID_TOK_SETUP_C, epo, dva);
            else
               ulpiTstSendTok(ob, USB2_PID_TOK_OUT_C, epo, dva);
            end if;
            ulpiClkTick;

            if ( dtglOut( epou ) = '0' ) then
               ulpiTstSendDatPkt(ob, USB2_PID_DAT_DATA0_C, v(idx to idx + cln - 1), w);
            else
               ulpiTstSendDatPkt(ob, USB2_PID_DAT_DATA1_C, v(idx to idx + cln - 1), w);
            end if;

            ulpiClkTick;
            ulpiTstWaitHsk(ob, pid, timo);
            if ( pid = USB2_PID_HSK_STALL_C ) then
               stl := true;
               return;
            end if;
            if ( (pid = USB2_PID_HSK_NAK_C)  and ( rtrPol = NAK  ) ) then
               agn := (pid = USB2_PID_HSK_NAK_C);
--assert pid /= USB2_PID_HSK_NYET_C report "XXXXXXXXX" severity failure;
            else
               if ( (pid = USB2_PID_HSK_NYET_C) and ( rtrPol = PING ) ) then
                  -- treat NYET as ACK
                  pid := USB2_PID_HSK_ACK_C;
               end if;
               assert pid = epid report "unexpected handshake response to data TX" &
"got " & integer'image(to_integer(unsigned(pid))) & " exp " & integer'image(to_integer(unsigned(epid))) severity failure;
               if ( rr = rtr and pid = USB2_PID_HSK_ACK_C ) then
                  -- accept the last one
                  dtglOut( epou ) := not dtglOut( epou );
                  -- setup initializes in/out toggles to '1'
                  if ( stup ) then
                     dtglInp( epou ) := '1';
                  end if;
               end if;
               rr := rr + 1;
            end if;
            ulpiClkTick;
         end loop;
         idx := idx + cln;
         if ( cln < MSZ or ( (idx = v'high + 1 ) and  ( stup or not fram ) ) ) then
            -- SETUP does not need a zero-length terminator!
            exit L_FRAG;
         end if;
      end loop;
   end procedure ulpiTstSendDat;

   -- wait for a data packet; may return NAK in 'epi' if endpoint has no data
   procedure ulpiTstWaitDatPkt (
      signal   ob  : inout UlpiIbType;
      variable epi : inout std_logic_vector(3 downto 0); -- expected PID (DATA0/DATA1); returns actual received pid
      constant eda : in    Usb2ByteArray;                -- excected data
      constant w   : in    integer := 0;                 -- wait cycles
      constant timo: in    natural := 30;                -- timeout waiting for pid
      constant abrt: in    integer := -1;                -- force PHY abort condition on ULPI after
                                                         -- abrt bytes (-1 -> no abort).
      constant npid: in    boolean := false              -- don't return mismatching PID
   ) is
      variable cmp  : Usb2ByteArray(eda'range);
      variable edal : natural;
   begin
      cmp := eda;
      ulpiTstRecvDatPkt( ob, epi, cmp, edal, w, timo, abrt, npid, chk => true );
   end procedure ulpiTstWaitDatPkt;
   
   procedure ulpiTstRecvDatPkt (
      signal   ob  : inout UlpiIbType;
      variable epi : inout std_logic_vector(3 downto 0); -- expected PID (DATA0/DATA1); returns actual received pid
      variable eda : inout Usb2ByteArray;                -- excected data
      variable edal: inout integer;                      -- length of received data
      constant w   : in    integer := 0;                 -- wait cycles
      constant timo: in    natural := 30;                -- timeout waiting for pid
      constant abrt: in    integer := -1;                -- force PHY abort condition on ULPI after
                                                         -- abrt bytes (-1 -> no abort).
      constant npid: in    boolean := false;             -- don't return mismatching PID
      constant chk : in    boolean := false              -- treat 'eda' as an input for verification
   ) is
      variable pid : std_logic_vector( 3 downto 0);
      variable crc : std_logic_vector(15 downto 0);
      constant ANY : Usb2ByteArray(0 to 0) := (others => x"00");
   begin
      edal := 0;
      ulpiTstWaitPid(ob, pid, timo);
      assert ulpiTstIb.stp = '0' report "unexpected STP" severity failure;
      if ( (      ( pid = USB2_PID_HSK_NAK_C )
              or  ( pid = USB2_PID_HSK_STALL_C ) )
           and not npid ) then
         epi := pid;
         return;
      end if;
report "got " & integer'image(to_integer(unsigned(pid))) & " expected " & integer'image(to_integer(unsigned(epi)));
      assert pid        = epi report "unexpected PID" severity failure;
      crc := USB2_CRC16_INIT_C;
      L_RD : for i in eda'low to eda'high + 2 loop
         for j in 0 to w - 1 loop
            ob.nxt <= '0';
            ulpiClkTick;
         end loop;
         ob.nxt <= '1';
         ulpiClkTick;
         if ( abrt = i - eda'low ) then
report "ABORT";
            ulpiTstSendVec( ob, ANY );
            ulpiClkTick; -- consume turn-around cycle
            return;
         end if;
         if ( not chk and ulpiTstIb.stp = '1' ) then
            exit L_RD;
         end if;
         assert (ulpiTstIb.stp = '0'   )  report "unexpected STP" severity failure;
         if ( i <= eda'high ) then
            if ( chk ) then
if ( ulpiTstIb.dat /= eda(i) ) then
report "got " & integer'image(to_integer(unsigned(ulpiTstIb.dat))) & " exp " & integer'image(to_integer(unsigned(eda(i))));
end if;
               assert (ulpiTstIb.dat = eda(i))  report "unexpected data @ " & integer'image(i) severity failure;
            else
               eda(i) := ulpiTstIb.dat;
            end if;
         end if;
         edal := edal + 1;
         ulpiTstCrc( crc, USB2_CRC16_POLY_C, ulpiTstIb.dat );
      end loop;
      ulpiClkTick;
      assert crc = USB2_CRC16_CHCK_C report "data crc mismatch" severity failure;
      assert (not chk or ulpiTstIb.stp = '1'   )  report "missing STP" severity failure;
      edal := edal - 2; -- don't include checksum
      ob.nxt <= '0';
      ulpiClkTick;
      ulpiTstSendRxCmd( ob, "000000" & ULPI_RXCMD_LINE_STATE_SE0_C );
      ulpiTstSendRxCmd( ob, "000000" & ULPI_RXCMD_LINE_STATE_FS_J_C );
   end procedure ulpiTstRecvDatPkt;

   -- wait for data reassembling until short packet is detected
   procedure ulpiTstRecvDat(
      signal   ob  : inout UlpiIbType;
      variable eda : inout Usb2ByteArray;                     -- expected data
      variable edal: inout integer;                           -- length of received data
      constant epi : in    Usb2EndpIdxType;                   -- endpoint
      constant dva : in    Usb2DevAddrType;                   -- usb device address
      constant rtr : in    natural                      := 0; -- let target retry by not sending ACK for 'rtr' times
      constant rak : in    integer                      := 0; -- accept NAK to IN token from target 'rak' times (-1 => inf)
      constant w   : in    natural                      := 0; -- wait cycles
      constant timo: in    natural                      := 30; -- timeout waiting for data (from IN token)
      constant abrt: in    integer                      := -1; -- force PHY abort after 'abrt' bytes
      constant nofr: in    boolean                      := false;
      constant estl: in    boolean                      := false;
      constant chk : in    boolean                      := false -- treat 'eda' as an input for verification
   ) is
      variable idx : natural;
      constant epin: natural := to_integer( unsigned( epi ) );
      constant MSZ : natural := epCfg( epin ).maxPktSizeInp;
      variable cln : natural := MSZ;
      variable pid : std_logic_vector(3 downto 0) := USB2_PID_HSK_NAK_C;
      variable epid: std_logic_vector(3 downto 0);
      variable slen: natural;
      variable ra  : integer;
   begin
      edal:= 0;
      idx := eda'low;
      L_FRAG : while true loop
         cln := eda'high + 1 - idx;
         if ( cln > MSZ ) then
            cln := MSZ;
         end if;
         for rr in 0 to rtr loop
            ra := 0;
            L_NAK : while ( rak < 0 or ra <=rak ) loop
               ulpiTstSendTok(ob, USB2_PID_TOK_IN_C, epi, dva);
               ulpiClkTick;
               if ( dtglInp( epin ) = '0' ) then
                  pid := USB2_PID_DAT_DATA0_C;
               else
                  pid := USB2_PID_DAT_DATA1_C;
               end if;
               epid := pid;
               ulpiTstRecvDatPkt(ob, pid, eda(idx to idx + cln - 1), edal => slen, w => w, timo => timo, abrt => abrt, chk => chk);
               edal := edal + slen;
               if ( abrt >= 0 ) then
                  return;
               end if;
               ulpiClkTick;
               if ( pid /= USB2_PID_HSK_NAK_C ) then
                  if ( not chk ) then
                     -- read (not check) mode; chunk size is the actual # of bytes read
                     cln := slen;
                  end if;
                  exit L_NAK;
               end if;
               if ( rak >= 0 ) then
                  ra := ra + 1;
               end if;
            end loop L_NAK;
            if ( estl ) then
               assert ( pid = USB2_PID_HSK_STALL_C ) report "ulpiTstWaitDat: expected STALL" severity failure;
               return;
            else
               assert ( pid = epid ) report "ulpiTstWaitDat: IN transaction failed" severity failure;
            end if;
            if ( rr = rtr ) then
               ulpiTstSendHsk(ob, USB2_PID_HSK_ACK_C);
               dtglInp( epin ) := not dtglInp( epin );
               idx := idx + cln;
            else
               ulpiTstSendHsk(ob, USB2_PID_HSK_NAK_C);
            end if;
            ulpiClkTick;
         end loop;
         if ( cln < MSZ or (idx = eda'high + 1 and nofr ) ) then
            exit L_FRAG;
         end if;
      end loop;
   end procedure ulpiTstRecvDat;

   procedure ulpiTstWaitDat(
      signal   ob  : inout UlpiIbType;
      constant eda : in    Usb2ByteArray;                     -- expected data
      constant epi : in    Usb2EndpIdxType;                   -- endpoint
      constant dva : in    Usb2DevAddrType;                   -- usb device address
      constant rtr : in    natural                      := 0; -- let target retry by not sending ACK for 'rtr' times
      constant rak : in    integer                      := 0; -- accept NAK to IN token from target 'rak' times (-1 => inf)
      constant w   : in    natural                      := 0; -- wait cycles
      constant timo: in    natural                      := 30; -- timeout waiting for data (from IN token)
      constant abrt: in    integer                      := -1; -- force PHY abort after 'abrt' bytes
      constant nofr: in    boolean                      := false;
      constant estl: in    boolean                      := false
   ) is
      variable cmp  : Usb2ByteArray(eda'range);
      variable edal : natural;
   begin
      cmp := eda;
      ulpiTstRecvDat(ob, cmp, edal, epi, dva, rtr, rak, w, timo, abrt, nofr, estl, chk => true);
   end procedure ulpiTstWaitDat;

   -- send a control sequence
   procedure ulpiTstSendCtlReq(
      signal   ob  : inout UlpiIbType;
      constant cod : in    unsigned;                                           -- request code (supported by this procedure)
      constant dva : in    Usb2DevAddrType;                                    -- usb device address
      constant val : in    std_logic_vector(15 downto 0) := (others => '0');   -- request value
      constant idx : in    std_logic_vector(15 downto 0) := (others => '0');   -- request index
      constant eda : in    Usb2ByteArray := USB2_TST_NULL_DATA_C;              -- expected data (ctl read)
      constant rtr : in    natural := 0;                                       -- rtr passed to underlying transactions
      constant w   : in    natural := 0;                                       -- wait cycles (passed down)
      constant timo: in    natural := 30;                                      -- timeout (passed down)
      constant epid: in    std_logic_vector(3 downto 0) := USB2_PID_HSK_ACK_C; -- expected handshake response to SETUP
      constant typ : in    std_logic_vector := ""                              -- explicit request type; overrides guessing
   ) is
      constant TYP_I_C   : natural := 0;
      constant LEN_I_H_C : natural := 7;
      constant LEN_I_L_C : natural := 6;
      constant VAL_I_H_C : natural := 3;
      constant VAL_I_L_C : natural := 2;
      constant IDX_I_H_C : natural := 5;
      constant IDX_I_L_C : natural := 4;
      variable len       : unsigned(15 downto 0) := to_unsigned(eda'length, 16);
      variable v         : Usb2ByteArray(0 to 7);
      variable stalled   : boolean;
      constant codl      : unsigned(7 downto 0) := resize(cod, 8);
      variable rpol      : Usb2TstRetryPolicyType;
   begin
      v             := (others => (others => '0'));
      v(1)          := std_logic_vector( resize(cod, v(1)'length) );
      v(VAL_I_L_C)  := val( 7 downto 0);
      v(VAL_I_H_C)  := val(15 downto 8);
      v(IDX_I_L_C)  := idx( 7 downto 0);
      v(IDX_I_H_C)  := idx(15 downto 8);
      v(LEN_I_L_C)  := std_logic_vector(len( 7 downto 0));
      v(LEN_I_H_C)  := std_logic_vector(len(15 downto 8));
      if hiSpeed then
         rpol := PING;
      else
         rpol := NAK;
      end if;
      -- hacks to pass explicit request type values
      if ( typ'length = 8 ) then
         v(TYP_I_C) := typ;
      elsif ( cod'length = 16 ) then
         v(TYP_I_C) := std_logic_vector( cod(15 downto 8 ) );
      else
         case ( codl ) is
            when x"0" & USB2_REQ_STD_GET_CONFIGURATION_C =>
               v(TYP_I_C)(7) := '1';

            when x"0" & USB2_REQ_STD_GET_INTERFACE_C =>
               v(TYP_I_C)(7) := '1';

            when x"0" & USB2_REQ_STD_GET_DESCRIPTOR_C =>
               v(TYP_I_C)(7) := '1';
               len           := len + 20;
               v(LEN_I_L_C)  := std_logic_vector(len( 7 downto 0));
               v(LEN_I_H_C)  := std_logic_vector(len(15 downto 8));


            when x"0" & USB2_REQ_STD_SET_ADDRESS_C =>

            when x"0" & USB2_REQ_STD_SET_CONFIGURATION_C =>
            when x"0" & USB2_REQ_STD_SET_INTERFACE_C =>

            -- hack; works as long as this doesn't overlap with other codes
            when x"23" =>
              v(TYP_I_C) := "00100001";

            when others =>
               assert false report "Unsupported request code" severity failure;
         end case;
      end if;
      ulpiTstSendDat( ob, stalled, v, USB2_ENDP_ZERO_C, dva, true, rtr, w, timo );
      if ( epid = USB2_PID_HSK_STALL_C ) then
         if ( stalled ) then
            return;
         end if;
      else
         assert stalled = false report "Unexpected STALL" severity failure;
      end if;
      ulpiClkTick;
      if ( v(TYP_I_C)(7) = '1' ) then
          ulpiTstWaitDat(ob, eda, USB2_ENDP_ZERO_C, dva, rtr, w => w, timo => timo, estl => (epid = USB2_PID_HSK_STALL_C) );
          ulpiClkTick;
          if ( epid = USB2_PID_HSK_STALL_C ) then
             return;
          end if;
          -- STATUS
report "status start";
          ulpiTstSendDat(ob, USB2_TST_NULL_DATA_C, USB2_ENDP_ZERO_C, dva, false, rtr => 2, w => w, timo => timo, rtrPol => rpol );
report "status end";
       else
          if ( eda'length > 0 ) then
             ulpiTstSendDat( ob, eda, USB2_ENDP_ZERO_C, dva, rtr => 2, w => w, timo => timo, rtrPol => rpol );
          end if;
          ulpiTstWaitDat(ob, USB2_TST_NULL_DATA_C, USB2_ENDP_ZERO_C, dva, rtr => rtr, rak => 2, w => w, timo => timo, estl => (epid = USB2_PID_HSK_STALL_C) );
       end if;
       ulpiClkTick;
    end procedure ulpiTstSendCtlReq;

    procedure usb2TstPkgConfig(
       constant cfg : in Usb2TstEpCfgArray
    ) is
    begin
       epCfg := cfg;
    end procedure usb2TstPkgConfig;

    procedure usb2TstPkgConfig(
       constant epOb : in Usb2EndpPairObArray;
       constant hs   : in boolean := false
    ) is
    begin
       hiSpeed := hs;
       for i in epOb'range loop
          epCfg(i).maxPktSizeInp := to_integer( epOb(i).config.maxPktSizeInp );
          epCfg(i).maxPktSizeOut := to_integer( epOb(i).config.maxPktSizeOut );
       end loop;
    end procedure usb2TstPkgConfig;

   -- wait for a register transaction
   procedure ulpiTstRegWait(
      signal    ob : inout UlpiIbType;
      variable   a : out   natural;
      variable  rnw: out   boolean;
      variable   d : out   std_logic_vector(7 downto 0)
   ) is
   begin
      while ulpiTstIb.dat(7) /= '1' loop
         ulpiClkTick;
      end loop;
      a   := to_integer(unsigned(ulpiTstIb.dat(4 downto 0)));
      rnw := (ulpiTstIb.dat(6) = '1');
      d   := (others => 'U');
      ob.nxt <= '1';
      ulpiClkTick;
      if ( ulpiTstIb.dat(6) = '0' ) then
         -- a write
         ulpiClkTick;
         d := ulpiTstIb.dat;
         ob.nxt <= '0';
         ulpiClkTick;
         assert (ulpiTstIb.stp = '1') report "ulpiTstRegWait missing STP" severity failure;
      end if;
   end procedure ulpiTstRegWait;

   -- complete a register read transaction (on ulpi)
   procedure ulpiTstRegReadComplete(
      signal    ob : inout UlpiIbType;
      constant   d : in    std_logic_vector(7 downto 0) -- read data
   ) is
   begin
      ob.nxt <= '0';
      ob.dir <= '1';
      ulpiClkTick; -- turn-around
      ob.dat <= d;
      ulpiClkTick;
      ob.dir <= '0'; -- turn-around
      ulpiClkTick;
   end procedure ulpiTstRegReadComplete;

   procedure ulpiTstHandlePhyInit(
      signal    ob : inout UlpiIbType
   ) is
      variable regAddr        : natural;
      variable regIsRd        : boolean;
      variable regDat         : std_logic_vector(7 downto 0);
   begin

      ulpiTstRegWait(ob, regAddr, regIsRd, regDat);

      assert not regIsRd report "ulpiTstHandlePhyInit: Register write expected" severity failure;
      assert regAddr = to_integer(unsigned(ULPI_REG_OTG_CTL_C)) report "ulpiTstHandlePhyInit: unexpected register address (not OTGCTL)" severity failure;
      assert regDat  = x"00" report "ulpiTstHandlePhyInit: unexpected OTG register contents" severity failure;

      ulpiTstRegWait(ob, regAddr, regIsRd, regDat);

      assert not regIsRd report "ulpiTstHandlePhyInit: Register write expected" severity failure;
      assert regAddr = to_integer(unsigned(ULPI_REG_FUN_CTL_C)) report "ulpiTstHandlePhyInit: unexpected register address (not FUNCTL)" severity failure;
      assert regDat  = x"45" report "ulpiTstHandlePhyInit: unexpected FUN register contents" severity failure;

   end procedure ulpiTstHandlePhyInit;

end package body Usb2TstPkg;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2TstPkg.all;

entity Usb2TstPkgProcesses is
end entity Usb2TstPkgProcesses;

architecture Sim of Usb2TstPkgProcesses is
   constant PER_C : time := 1 sec / 60.0E6;
begin

   P_ULPI_DAT : process ( ulpiTstOb, ulpiDatIO ) is
   begin
      ulpiTstIb.dat <= ulpiDatIO;
      if ( ulpiTstOb.dir = '1' ) then
         ulpiDatIO <= ulpiTstOb.dat;
      else
         ulpiDatIO <= (others => 'Z');
      end if;
   end process P_ULPI_DAT;

   P_CLK : process is begin
      if ( ulpiTstRun ) then wait for 10 ns; ulpiTstClk <= not ulpiTstClk; else wait; end if;
   end process P_CLK;

end architecture Sim;
