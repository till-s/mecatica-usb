library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;
use     work.Usb2DescPkg.all;

package body Usb2DescPkg is

   function USB2_APP_CFG_DESCRIPTORS_F return Usb2ByteArray is
   constant c : Usb2ByteArray := (
       0 => x"09",                                    -- length
       1 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_CONFIGURATION_C), -- type
       2 => x"09", 3 => x"00",                        -- total length
       4 => x"00",                                    -- num interfaces
       5 => x"01",                                    -- config value
       6 => x"00",                                    -- description string
       7 => x"00",                                    -- attributes
       8 => x"ff"                                     -- power
   );
   begin
   return c;
   end function;

   constant USB2_APP_NUM_ENDPOINTS_C   : positive := 2;
   constant USB2_APP_MAX_INTERFACES_C  : natural  := 1;
   constant USB2_APP_MAX_ALTSETTINGS_C : positive := 1;

   function USB2_APP_DEV_DESCRIPTOR_F  return Usb2ByteArray is
   constant c : Usb2ByteArray := (
       0 => x"12",                                    -- length
       1 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_DEVICE_C),     -- type
       2 => x"00",  3 => x"02",                       -- USB version
       4 => x"FF",                                    -- dev class
       5 => x"FF",                                    -- dev subclass
       6 => x"00",                                    -- dev protocol
       7 => x"08",                                    -- max pkt size
       8 => x"23",  9 => x"01",                       -- vendor id
      10 => x"cd", 11 => x"ab",                       -- product id
      12 => x"01", 13 => x"00",                       -- device release
      14 => x"00",                                    -- man. string
      15 => x"00",                                    -- prod. string
      16 => x"00",                                    -- S/N string
      17 => x"01"                                     -- num configs
   );
   begin
   return c;
   end function;

end package body Usb2DescPkg;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;
use     work.Usb2DescPkg.all;

entity Usb2PktProcTb is
end entity Usb2PktProcTb;

architecture sim of Usb2PktProcTb is

   constant TST_EP_IDX_C : natural := 1;
   constant TST_EP_C     : std_logic_vector(3 downto 0) := std_logic_vector(to_unsigned(TST_EP_IDX_C,4));
   
   constant EP0_C        : std_logic_vector(3 downto 0) := x"0";

   constant ENDPOINTS_C   : Usb2EndpPairConfigArray := (
      0         => (
               transferTypeInp => USB2_TT_CONTROL_C,
               maxPktSizeInp   => to_unsigned( 8, Usb2PktSizeType'length),
               transferTypeOut => USB2_TT_CONTROL_C,
               maxPktSizeOut   => to_unsigned( 8, Usb2PktSizeType'length),
               hasHaltInp      => false,
               hasHaltOut      => false
           ),
      TST_EP_IDX_C => (
               transferTypeInp => USB2_TT_BULK_C,
               maxPktSizeInp   => to_unsigned( 8, Usb2PktSizeType'length),
               transferTypeOut => USB2_TT_BULK_C,
               maxPktSizeOut   => to_unsigned( 8, Usb2PktSizeType'length),
               hasHaltInp      => false,
               hasHaltOut      => false
           )
   );

   signal devStatus       : Usb2DevStatusType := USB2_DEV_STATUS_INIT_C;
   signal epIb            : Usb2EndpPairIbArray(ENDPOINTS_C'range) := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb            : Usb2EndpPairObArray(ENDPOINTS_C'range) := (others => USB2_ENDP_PAIR_OB_INIT_C);

   signal txDataMst       : Usb2StrmMstType := USB2_STRM_MST_INIT_C;
   signal txDataSub       : Usb2StrmSubType := USB2_STRM_SUB_INIT_C;
   signal rxDataMst       : Usb2StrmMstType := USB2_STRM_MST_INIT_C;
   signal clk             : std_logic := '0';

   signal rxPktHdr        : Usb2PktHdrType;

   signal ulpiRx          : UlpiRxType      := ULPI_RX_INIT_C;
   signal ulpiTxReq       : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRep       : UlpiTxRepType;

   shared variable dtglInp : std_logic_vector(ENDPOINTS_C'range) := (others => '0');
   shared variable dtglOut : std_logic_vector(ENDPOINTS_C'range) := (others => '0');

   type UlpiObType is record
      dir  : std_logic;
      nxt  : std_logic;
      dat  : std_logic_vector(7 downto 0);
   end record UlpiObType;

   constant ULPI_OB_INIT_C : UlpiObType := (
      dir  => '0',
      nxt  => '0',
      dat  => (others => '0')
   );

   type UlpiIbType is record
      stp  : std_logic;
      dat  : std_logic_vector(7 downto 0);
   end record UlpiIbType;

   type   DataArray is array (natural range <>) of std_logic_vector(7 downto 0);

   signal ulpiOb : ulpiObType := ULPI_OB_INIT_C;
   signal ulpiIb : ulpiIbType;

   signal dat_i  : std_logic_vector(7 downto 0);

   signal run    : boolean := true;

   constant NULL_DATA : DataArray(0 to -1) := ( others => (others => '0') );

   constant d1 : DataArray := ( x"01", x"02", x"03" );
   constant d2 : DataArray := (
      x"c7",
      x"3d",
      x"25",
      x"93",
      x"ba",
      x"bb",
      x"b3",
      x"5e",
      x"54",
      x"5a",
      x"ac",
      x"5a",
      x"6c",
      x"ee",
      x"00",
      x"ab"
   );

   procedure tick is begin wait until rising_edge(clk); end procedure tick;

   procedure sendVec(
      signal   ob : inout UlpiObType;
      constant vc : in    DataArray;
      constant e  : in    boolean := true;
      constant w  : in    integer := 0
   ) is
      constant RXCMD_C : std_logic_vector(7 downto 0) := (
         ULPI_RXCMD_RX_ACTIVE_BIT_C => '1',
         others                => '0'
      );
   begin
      if ( ob.dir = '0' ) then
         ob.dir <= '1';
         ob.nxt <= '1';
         ob.dat <= (others => 'Z');
         tick;
         -- turn
      end if;
      for i in vc'range loop
         ob.dat <= vc(i);
         for j in 0 to w - 1 loop
            ob.nxt <= '0';
            ob.dat <= RXCMD_C;
            tick;
            ob.dat <= vc(i);
            ob.nxt <= '1';
         end loop;
         tick;
      end loop;
      if ( e ) then
         ob.nxt <= '0';
         ob.dir <= '0';
         tick;
         -- turn
      end if;
   end procedure sendVec;

   procedure crcbf (
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
   end procedure crcbf;

   procedure sendTok(
      signal   ob : inout UlpiObType;
      constant t  : in  std_logic_vector;
      constant e  : in  std_logic_vector(3 downto 0);
      constant a  : in  std_logic_vector(6 downto 0) := (others => '0')
   ) is
      variable v : DataArray(0 to 2);
      variable x : std_logic_vector(10 downto 0);
      variable c : std_logic_vector( 4 downto 0);
   begin
      if ( t'length = 2 ) then
         v(0) := not t & "10" & t & "01";
      else
         v(0) := not t & t;
      end if;
      x    := e & a;
      c    := USB2_CRC5_INIT_C(c'range);
      crcbf( c, USB2_CRC5_POLY_C(c'range), x );
      v(1) := x(7 downto 0);
      v(2) := not c & x(10 downto 8);
      sendVec( ob, v );
      if ( v(0)(3 downto 0) = USB2_PID_TOK_SETUP_C ) then
         dtglInp( to_integer( unsigned( e ) ) ) := '0';
         dtglOut( to_integer( unsigned( e ) ) ) := '0';
      end if;
   end procedure sendTok;

   procedure sendHsk(
      signal   ob : inout UlpiObType;
      constant t  : in  std_logic_vector(3 downto 0)
   ) is
      constant c : DataArray := ( 0 => (not t & t ) );
   begin
      sendVec( ob, c );
   end procedure sendHsk;

   procedure waitPid (
      signal   ob  : inout UlpiObType;
      variable pid : out   std_logic_vector(3 downto 0);
      constant tim : in    natural := 30
   ) is
      variable cnt : natural := tim;
   begin
      while ulpiIb.dat = x"00" loop
         tick;
         if ( cnt = 0 ) then
            pid := USB2_PID_HSK_NAK_C;
            return;
         else
            cnt := cnt - 1;
         end if;
      end loop;
      assert ulpiIb.dat(7 downto 4) = "0100" report "not a TXCMD" severity failure;
      ob.nxt <= '1';
      tick;
      assert ulpiIb.dat(7 downto 4) = "0100" report "not a TXCMD" severity failure;
      pid := ulpiIb.dat(3 downto 0);
   end procedure waitPid;

   procedure waitHsk (
      signal   ob  : inout UlpiObType;
      variable pid : inout std_logic_vector(3 downto 0);
      constant timo: in    natural                      := 30;
      constant st  : in    std_logic_vector(7 downto 0) := x"00"
   ) is
   begin
       waitPid(ob, pid, timo);
       ob.nxt <= '0';
       assert ulpiIb.stp = '0' report "unexpected STP" severity failure;
       tick;
       assert ( ulpiIb.stp = '1' )                       report "HSK not stopped"     severity failure;
       assert ( ulpiIb.dat = st  )                       report "HSK status mismatch" severity failure;
       assert ( pid(1 downto 0) = USB2_PID_GROUP_HSK_C ) report "PID not a HSK" severity failure;
   end procedure waitHsk;


   procedure sendDatPkt(
      signal   ob  : inout UlpiObType;
      constant pid : in    std_logic_vector(3 downto 0);
      constant v   : in    DataArray;
      constant w   : in    natural := 0
   ) is
      variable crc : std_logic_vector(15 downto 0);
      constant h   : DataArray := ( 0 => ( not pid & pid ) );
      variable t   : DataArray(0 to 1);
      variable x   : std_logic;
   begin
      sendVec( ob, h, false, w );
      sendVec( ob, v, false, w );
      crc := USB2_CRC16_INIT_C;
      for i in v'range loop
         crcbf( crc, USB2_CRC16_POLY_C, v(i) );
      end loop;
      t(0) := not crc( 7 downto 0);
      t(1) := not crc(15 downto 8);
      sendVec( ob, t, true, w );
   end procedure sendDatPkt;

   procedure sendDat(
      signal   ob  : inout UlpiObType;
      constant v   : in    DataArray;
      constant epo : in    std_logic_vector(3 downto 0);
      constant stup: in    boolean := false;
      constant rtr : in    natural := 0;
      constant w   : in    natural := 0;
      constant timo: in    natural := 30
   ) is
      variable idx : natural;
      constant epou: natural := to_integer( unsigned( epo ) );
      constant MSZ : natural := to_integer( ENDPOINTS_C( epou ).maxPktSizeOut );
      variable cln : natural := MSZ;
      variable pid : std_logic_vector(3 downto 0);
   begin
      if ( stup ) then
         assert v'length <= MSZ report "excessive setup data (test prog error)" severity failure;
      end if;
      idx := v'low;
      L_FRAG : while true loop
         cln := v'high + 1 - idx;
         if ( cln > MSZ ) then
            cln := MSZ;
         end if;
         for rr in 0 to rtr loop
            if ( stup ) then
               sendTok(ob, USB2_PID_TOK_SETUP_C, epo);
            else
               sendTok(ob, USB2_PID_TOK_OUT_C, epo);
            end if;
            tick;

            if ( dtglOut( epou ) = '0' ) then
               sendDatPkt(ob, USB2_PID_DAT_DATA0_C, v(idx to idx + cln - 1), w);
            else
               sendDatPkt(ob, USB2_PID_DAT_DATA1_C, v(idx to idx + cln - 1), w);
            end if;

            tick;
            waitHsk(ob, pid, timo);
            assert pid = USB2_PID_HSK_ACK_C report "data not ACKed" severity failure;
            if ( rr = rtr ) then
               -- accept the last one
               dtglOut( epou ) := not dtglOut( epou );
               -- setup initializes in/out toggles to '1'
               if ( stup ) then
                  dtglInp( epou ) := '1';
               end if;
            end if;
            tick;
         end loop;
         idx := idx + cln;
         if ( cln < MSZ or stup ) then
            -- SETUP does not need a zero-length terminator!
            exit L_FRAG;
         end if;
      end loop;
   end procedure sendDat;

   procedure waitDatPkt (
      signal   ob  : inout UlpiObType;
      constant epi : in    std_logic_vector(3 downto 0);
      constant eda : in    DataArray;
      constant w   : in    natural := 0;
      constant timo: in    natural                      := 30
   ) is
      variable pid : std_logic_vector( 3 downto 0);
      variable crc : std_logic_vector(15 downto 0);
   begin
      waitPid(ob, pid, timo);
      assert ulpiIb.stp = '0' report "unexpected STP" severity failure;
      assert pid        = epi report "unexpected PID" severity failure;
      crc := USB2_CRC16_INIT_C;
      for i in eda'low to eda'high + 2 loop
         for j in 0 to w - 1 loop
            ob.nxt <= '0';
            tick;
         end loop;
         ob.nxt <= '1';
         tick;
         assert (ulpiIb.stp = '0'   )  report "unexpected STP" severity failure;
         if ( i <= eda'high ) then
            assert (ulpiIb.dat = eda(i))  report "unexpected data & " & integer'image(i) severity warning;
         end if;
         crcbf( crc, USB2_CRC16_POLY_C, ulpiIb.dat );
      end loop;
      tick;
      assert crc = USB2_CRC16_CHCK_C report "data crc mismatch" severity failure;
      assert (ulpiIb.stp = '1'   )  report "unexpected STP" severity failure;
      ob.nxt <= '0';
      tick;
   end procedure waitDatPkt;

   procedure waitDat(
      signal   ob  : inout UlpiObType;
      constant eda : in    DataArray;
      constant epi : in    std_logic_vector(3 downto 0);
      constant rtr : in    natural                      := 0;
      constant w   : in    natural                      := 0;
      constant timo: in    natural                      := 30
   ) is
      variable idx : natural;
      constant epin: natural := to_integer( unsigned( epi ) );
      constant MSZ : natural := to_integer( ENDPOINTS_C( epin ).maxPktSizeInp );
      variable cln : natural := MSZ;
   begin
      idx := eda'low;
      L_FRAG : while true loop
         cln := eda'high + 1 - idx;
         if ( cln > MSZ ) then
            cln := MSZ;
         end if;
         for rr in 0 to rtr loop
            sendTok(ob, USB2_PID_TOK_IN_C, epi);
            tick;
            if ( dtglInp( epin ) = '0' ) then
               waitDatPkt(ob, USB2_PID_DAT_DATA0_C, eda(idx to idx + cln - 1), w, timo);
            else
               waitDatPkt(ob, USB2_PID_DAT_DATA1_C, eda(idx to idx + cln - 1), w, timo);
            end if;
            tick;
            if ( rr = rtr ) then
               sendHsk(ob, USB2_PID_HSK_ACK_C);
               dtglInp( epin ) := not dtglInp( epin );
               idx := idx + cln;
            else
               sendHsk(ob, USB2_PID_HSK_NAK_C);
            end if;
            tick;
         end loop;
         if ( cln < MSZ ) then
            exit L_FRAG;
         end if;
      end loop;
   end procedure waitDat;

   procedure sendCtlReq(
      signal   ob  : inout UlpiObType;
      constant cod : in    Usb2StdRequestCodeType;
      constant rtr : in    natural := 0;
      constant w   : in    natural := 0;
      constant timo: in    natural := 30
   ) is
      constant TYP_I_C   : natural := 0;
      constant LEN_I_H_C : natural := 6;
      constant LEN_I_L_C : natural := 7;
      variable v         : DataArray(0 to 7);
      variable eda       : DataArray(0 to 15);
      variable edal      : natural := 0;
   begin
      v    := (others => (others => '0'));
      v(1) := x"0" & std_logic_vector(cod);
      case ( cod ) is
         when USB2_REQ_STD_GET_CONFIGURATION_C =>
            v(TYP_I_C)(7) := '1';
            v(LEN_I_L_C)  := x"01";
            eda(0)        := x"00";
            edal          := 1;

         when USB2_REQ_STD_GET_INTERFACE_C =>
            v(TYP_I_C)(7) := '1';
            v(LEN_I_L_C)  := x"01";
            eda(0)        := x"00";
            edal          := 1;
          
         when others =>
            assert false report "Unsupported request code" severity failure;
      end case;
      sendDat( ob, v, EP0_C, true, rtr, w, timo );
      tick;
      if ( v(TYP_I_C)(7) = '1' ) then
         waitDat(ob, eda(0 to edal - 1), EP0_C, rtr, w, timo);
         tick;
         -- STATUS
         sendDat(ob, NULL_DATA, EP0_C, false, rtr, w, timo);
      end if;
    end procedure sendCtlReq;

begin

   P_ULPI_DAT : process ( ulpiOb, dat_i ) is
   begin
      ulpiIb.dat <= dat_i;
      if ( ulpiOb.dir = '1' ) then
         dat_i <= ulpiOb.dat;
      else
         dat_i <= (others => 'Z');
      end if;
   end process P_ULPI_DAT;

   P_CLK : process is begin
      if ( run ) then wait for 10 ns; clk <= not clk; else wait; end if;
   end process P_CLK;

   P_TST : process is
      variable pid : std_logic_vector(3 downto 0);
   begin
      tick; tick;

      sendCtlReq(ulpiOb, USB2_REQ_STD_GET_CONFIGURATION_C);

      sendCtlReq(ulpiOb, USB2_REQ_STD_GET_INTERFACE_C);

      tick;


      sendDat(ulpiOb, d2, TST_EP_C);

      sendDat(ulpiOb, d2, TST_EP_C, rtr=>2 );

      sendDat(ulpiOb, d2, TST_EP_C, rtr=>2, w => 2 );

      -- read fragmented data
      waitDat(ulpiOb, d2, TST_EP_C );
      tick;

      -- read fragmented with retries
      waitDat(ulpiOb, d2, TST_EP_C, 2 );
      tick;

      -- read fragmented with retries and wait cycles
      waitDat(ulpiOb, d2, TST_EP_C, 2, 2 );
      tick;

      for i in 0 to 20 loop
         tick;
      end loop;
      run <= false;
      wait;
   end process P_TST;

   U_DUT : entity work.Usb2PktProc
   generic map (
      NUM_ENDPOINTS_G => ENDPOINTS_C'length
   )
   port map (
      clk             => clk,
      rst             => open,
      devStatus       => devStatus,
      epConfig        => ENDPOINTS_C,
      epIb            => epIb,
      epOb            => epOb,

      txDataMst       => txDataMst,
      txDataSub       => txDataSub,
      rxPktHdr        => rxPktHdr,
      rxDataMst       => rxDataMst
   );

   U_DUT_CTL : entity work.Usb2StdCtlEp
   generic map (
      NUM_ENDPOINTS_G     => USB2_APP_NUM_ENDPOINTS_C,
      MAX_INTERFACES_G    => USB2_APP_MAX_INTERFACES_C,
      MAX_ALTSETTINGS_G   => USB2_APP_MAX_ALTSETTINGS_C,
      CFG_DESCRIPTORS_G   => USB2_APP_CFG_DESCRIPTORS_C,
      DEV_DESCRIPTOR_G    => USB2_APP_DEV_DESCRIPTOR_C
   )
   port map (
      clk             => clk,
      rst             => open,
      epIb            => epOb(0),
      epOb            => epIb(0),
      usrEpIb         => epIb(1 to epIb'high),

      param           => open,
      ctlExt          => open,
      ctlEpExt        => open,

      devStatus       => devStatus
  );

   U_RX : entity work.Usb2PktRx
   port map (
      clk             => clk,
      ulpiRx          => ulpiRx,
      pktHdr          => rxPktHdr,
      rxData          => rxDataMst
   );

   U_TX : entity work.Usb2PktTx
   port map (
      clk             => clk,
      ulpiTxReq       => ulpiTxReq,
      ulpiTxRep       => ulpiTxRep,
      txDataMst       => txDataMst,
      txDataSub       => txDataSub
   );

   U_IO : entity work.UlpiIO
   port map (
      clk             => clk,

      dir             => ulpiOb.dir,
      stp             => ulpiIb.stp,
      nxt             => ulpiOb.nxt,
      dat             => dat_i,

      ulpiRx          => ulpiRx,
      ulpiTxReq       => ulpiTxReq,
      ulpiTxRep       => ulpiTxRep
   );


   P_EP_0  : process ( clk ) is
      function ini return Usb2EndpPairIbType is
         variable v : Usb2EndpPairIbType;
      begin
         v            := USB2_ENDP_PAIR_IB_INIT_C;
         v.mstInp.vld := '1';
         v.subOut.rdy := '1';
         return v;
      end function ini;

      variable iidx : integer            := 0;
      variable oidx : integer            := 0;
      variable ep   : Usb2EndpPairIbType := ini;
   begin
      if ( rising_edge( clk ) ) then
         ep.subOut.don := '0';
         if ( ep.mstInp.vld = '1' ) then
            if ( epOb(TST_EP_IDX_C).subInp.rdy = '1' ) then
               assert epOb(TST_EP_IDX_C).subInp.err = '0' report "INP 0 endpoint error" severity failure;
               if ( iidx = d2'high ) then
                  ep.mstInp.vld := '0';
                  iidx          :=  0 ;
                  ep.mstInp.don := '1';
                  ep.mstInp.err := '0';
               else
                  iidx          := iidx + 1;
               end if;
            end if;
         else
            if ( epOb(TST_EP_IDX_C).subInp.don = '1' ) then
               ep.mstInp.don := '0';
               ep.mstInp.vld := '1';
            end if;
         end if;
         if ( epOb(TST_EP_IDX_C).mstOut.vld = '1' ) then
            assert epOb(TST_EP_IDX_C).mstOut.dat = d2(oidx) report "OUT 0 endpoint data mismatch" severity failure;
            oidx := oidx + 1;
         elsif ( epOb(TST_EP_IDX_C).mstOut.don = '1' ) then
            oidx          := 0;
            ep.subOut.don := '1';
         end if;
         epIb(TST_EP_IDX_C)            <= ep;
         epIb(TST_EP_IDX_C).mstInp.dat <= d2(iidx);
      end if;
   end process P_EP_0;

end architecture sim;
