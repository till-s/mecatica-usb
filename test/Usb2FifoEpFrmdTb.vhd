-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

package FifoEpFrmdTstParmPkg is
   constant IFC_NUM_C : natural := 0;
end package FifoEpFrmdTstParmPkg;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;
use     work.FifoEpFrmdTstParmPkg.all;

package body Usb2AppCfgPkg is

   procedure pr(constant x: Usb2ByteArray) is
      variable s : string(1 to 8);
   begin
      for i in x'range loop
         for j in x(i)'left downto x(i)'right loop
            s(8-j) := std_logic'image(x(i)(j))(2);
         end loop;
         report "D[" & integer'image(i) & "]  => " & s;
      end loop;
   end procedure pr;

   function USB2_APP_DESCRIPTORS_F return Usb2ByteArray is

   constant DEVDESC_C : Usb2ByteArray := (
       0 => x"12",                                    -- length
       1 => USB2_DESC_TYPE_DEVICE_C,                  -- type
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

   constant CONFDESC_C : Usb2ByteArray := (
       0 => x"09",                                    -- length
       1 => USB2_DESC_TYPE_CONFIGURATION_C,           -- type
       2 => x"3E", 3 => x"00",                        -- total length
       4 => x"01",                                    -- num interfaces
       5 => x"01",                                    -- config value
       6 => x"00",                                    -- description string
       7 => x"00",                                    -- attributes
       8 => x"ff",                                    -- power

       9 => x"04", -- a dummy 'unknown' descriptor
      10 => x"00", 
      11 => x"00",
      12 => x"00",

      13 => x"09",                                    -- length
      14 => USB2_DESC_TYPE_INTERFACE_C,               -- type
      15 => x"00",                                    -- interface number
      16 => x"00",                                    -- alt-setting
      17 => x"02",                                    -- num-endpoints
      18 => x"FF",                                    -- class
      19 => x"FF",                                    -- subclass
      20 => x"00",                                    -- protocol
      21 => x"00",                                    -- string desc

      22 => x"07", -- endpoint                           length
      23 => USB2_DESC_TYPE_ENDPOINT_C,                -- type
      24 => x"01",                                    -- address (OUT EP1)
      25 => "000000" & USB2_TT_BULK_C,                -- attributes
      26 => x"00", 27 => x"00",                       -- maxPktSize
      28 => x"00",                                    -- interval

      29 => x"03", -- a dummy 'unknown' descriptor
      30 => x"00", 
      31 => x"00",

      32 => x"07", -- endpoint                           length
      33 => USB2_DESC_TYPE_ENDPOINT_C,                -- type
      34 => x"81",                                    -- address (IN EP1)
      35 => "000000" & USB2_TT_BULK_C,                -- attributes
      36 => x"00", 37 => x"00",                       -- maxPktSize
      38 => x"00",                                    -- interval

      39 => x"09",                                    -- length
      40 => USB2_DESC_TYPE_INTERFACE_C,               -- type
      41 => std_logic_vector(to_unsigned(IFC_NUM_C,8)), -- interface number
      42 => x"01",                                    -- alt-setting
      43 => x"02",                                    -- num-endpoints
      44 => x"FF",                                    -- class
      45 => x"FF",                                    -- subclass
      46 => x"00",                                    -- protocol
      47 => x"00",                                    -- string desc

      48 => x"07", -- endpoint                           length
      49 => USB2_DESC_TYPE_ENDPOINT_C,                -- type
      50 => x"01",                                    -- address (OUT EP1)
      51 => "000000" & USB2_TT_BULK_C,                -- attributes
      52 => x"08", 53 => x"00",                       -- maxPktSize
      54 => x"00",                                    -- interval

      55 => x"07", -- endpoint                           length
      56 => USB2_DESC_TYPE_ENDPOINT_C,                -- type
      57 => x"81",                                    -- address (IN EP1)
      58 => "000000" & USB2_TT_BULK_C,                -- attributes
      59 => x"08", 60 => x"00",                       -- maxPktSize
      61 => x"00"                                     -- interval
   );

   constant STRS_C : Usb2ByteArray := (
       0 => x"04",                                    -- length
       1 => USB2_DESC_TYPE_STRING_C,                  -- type
       2 => USB2_LANGID_EN_US_C( 7 downto 0),
       3 => USB2_LANGID_EN_US_C(15 downto 8),

       4 => x"06",
       5 => USB2_DESC_TYPE_STRING_C,                  -- type
       6 => x"54",
       7 => x"00",
       8 => x"55",
       9 => x"00"
   );

   constant TAILDESC_C : Usb2ByteArray := (
      0  => x"02", -- End of table marker
      1  => x"ff"  --
   );

   constant l : natural :=  DEVDESC_C'length + CONFDESC_C'length + STRS_C'length + TAILDESC_C'length;
   constant c : Usb2ByteArray(0 to l-1) := (DEVDESC_C & CONFDESC_C & STRS_C & TAILDESC_C);
   begin
   return c;
   end function;

end package body Usb2AppCfgPkg;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2TstPkg.all;
use     work.Usb2AppCfgPkg.all;
use     work.Usb2DescPkg.all;
use     work.FifoEpFrmdTstParmPkg.all;

entity Usb2FifoEpFrmdTb is
   generic (DON_IS_LAST_G:boolean := false);
end entity Usb2FifoEpFrmdTb;

architecture sim of Usb2FifoEpFrmdTb is

   constant TST_EP_IDX_C           : natural := 1;
   constant TST_EP_C               : Usb2EndpIdxType := to_unsigned(TST_EP_IDX_C,Usb2EndpIdxType'length);

   -- don or last?
   constant DNL_C                  : boolean := not DON_IS_LAST_G;

   constant DEV_ADDR_C             : Usb2DevAddrType := Usb2DevAddrType( to_unsigned(66, Usb2DevAddrType'length) );

   constant CONFIG_VALUE_C         : std_logic_vector(7 downto 0) := x"01";
   -- index is zero-based (?)
   constant CONFIG_INDEX_C         : std_logic_vector(7 downto 0) := x"00";
   constant CONFIG_BAD_VALUE_C     : std_logic_vector(7 downto 0) := x"02";

   constant NUM_ENDPOINTS_C        : natural                      := USB2_APP_MAX_ENDPOINTS_F(USB2_APP_DESCRIPTORS_C);

   constant EP0_SZ_C               : Usb2ByteType           := USB2_APP_DESCRIPTORS_F(USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C); 
   constant EP1_SZ_C               : natural                := 8; -- must match value in descriptor
   constant EP1                    : Usb2EndpIdxType        := x"1";

   constant ALT_C                  : std_logic_vector(15 downto 0) := x"0001";
   constant IFC_C                  : std_logic_vector(15 downto 0) := x"0000";

   type SpeedCfgType is record
      pol : Usb2TstRetryPolicyType;
      hse : std_logic;
   end record SpeedCfgType;

   type SpeedCfgArray is array(natural range 0 to 1) of SpeedCfgType;

   type FifoInpType is record
      dat : Usb2ByteType;
      don : std_logic;
      wen : std_logic;
   end record FifoInpType;

   constant FIFO_INP_INIT_C : FifoInpType := (
      dat => (others => '0'),
      don => '0',
      wen => '0'
   );

   signal fifoInp : FifoInpType := FIFO_INP_INIT_C;

   signal speedCfg : SpeedCfgArray := (
      0 => ( hse => '0', pol => NAK  ),
      1 => ( hse => '1', pol => PING )
   );
   
   signal epIb                     : Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb                     : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_OB_INIT_C);

   signal devStatus                : Usb2DevStatusType;
   signal usb2Rx                   : Usb2RxType;

   signal ep0ReqParam              : Usb2CtlReqParamType;
   signal ep0CtlExt                : Usb2CtlExtType := USB2_CTL_EXT_NAK_C;

   signal epClk                    : std_logic    := '0';
   signal epRstOut                 : std_logic;
   signal epRun                    : boolean      := true;
   signal usb2Don                  : boolean      := false;
   signal epTglOut                 : boolean      := false;
   signal tstTglOut                : boolean      := false;
   signal epTglInp                 : boolean      := false;
   signal tstTglInp                : boolean      := false;
   signal startTstInp              : boolean      := false;

   signal fifoDatOut               : Usb2ByteType;
   signal fifoDonOut               : std_logic;
   signal fifoFullInp              : std_logic;
   signal fifoRenOut               : std_logic    := '0';
   signal fifoEmptyOut             : std_logic;

   constant d1 : Usb2ByteArray := ( x"01", x"02", x"03" );
   constant d2 : Usb2ByteArray := (
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

   procedure epTick is begin wait until rising_edge( epClk ); end procedure;

   constant  NXT_NULL_IDX_C : natural := 7;
   constant  TST_DONE_IDX_C : natural := 6;

   function nextIsNull(constant x : Usb2ByteType) return boolean is
   begin
      return x(NXT_NULL_IDX_C) = '1';
   end function nextIsNull;

   function testDone(constant x : Usb2ByteType) return boolean is
   begin
      return x(TST_DONE_IDX_C) = '1';
   end function testDone;

   function getLen(constant x : Usb2ByteType) return natural is
   begin
      return to_integer( unsigned( x(TST_DONE_IDX_C - 1 downto 0) ) );
   end function getLen;

   procedure sendD2(
      signal   ep     : inout UlpiIbType;
      signal   fc     : inout natural;
      constant len    : in    natural;
      constant nxtNul : in    boolean := false;
      constant tstDon : in    boolean := false;
      constant rtrPol : in    Usb2TstRetryPolicyType := NAK
   ) is
      variable d0     : Usb2ByteType;
      variable stl    : boolean;
   begin
      -- not supported ATM
      assert not (tstDon and len = 0) report "cannot send NUL packet as last" severity failure;
      assert not (nxtNul and len = 0) report "cannot send two consecutive NUL packets" severity failure;
      fc <= fc + 1;
      if ( len > 0 ) then
         d0 := Usb2ByteType( to_unsigned( len + 1, Usb2ByteType'length ) );
         if ( nxtNul ) then
            d0(NXT_NULL_IDX_C) := '1';
         end if;
         if ( tstDon ) then
            d0(TST_DONE_IDX_C) := '1';
         end if;
         ulpiTstSendDat(ep, d0 & d2(0 to len - 1), EP1, DEV_ADDR_C, fram => true, rtrPol => rtrPol);
      else
         ulpiTstSendDat(ep, d2(0 to - 1), EP1, DEV_ADDR_C, fram => true, rtrPol => rtrPol);
      end if;
      assert not stl report "Unexpected STALL" severity failure;
   end procedure sendD2;

   procedure fifoSend(
      signal   fio    : inout fifoInpType;
      constant dat    : in    Usb2ByteType;
      constant don    : in    std_logic := '0'
   ) is
   begin
      fio.don <= don;
      fio.dat <= dat;
      fio.wen <= '1';
      epTick;
      while ( fifoFullInp = '1' ) loop
         epTick;
      end loop;
      fio.wen <= '0';
   end procedure fifoSend;

   procedure fifoSendD2(
      signal   fio    : inout fifoInpType;
      signal   fc     : inout natural;
      constant len    : in    natural;
      constant nxtNul : in    boolean := false;
      constant tstDon : in    boolean := false
   ) is
      variable d0  : Usb2ByteType;
      variable dn  : std_logic;
   begin
      -- not supported ATM
      assert not (tstDon and len = 0) report "cannot send NUL packet as last" severity failure;
      assert not (nxtNul and len = 0) report "cannot send two consecutive NUL packets" severity failure;
      fc <= fc + 1;
      if ( len > 0 ) then
         d0 := Usb2ByteType( to_unsigned( len + 1, Usb2ByteType'length ) );
         if ( nxtNul ) then
            d0(NXT_NULL_IDX_C) := '1';
         end if;
         if ( tstDon ) then
            d0(TST_DONE_IDX_C) := '1';
         end if;
         fifoSend(fio, d0);
         for i in 0 to len - 1 loop
            dn := '0';
            if ( not DNL_C and ( i = (len - 1) ) ) then
               dn := '1';
            end if;
            fifoSend(fio, d2(i), don => dn );
         end loop;
      end if;
      if ( DNL_C ) then
         fifoSend(fio, x"00", don => '1');
      end if;
      epTick;
   end procedure fifoSendD2;


   signal nextNulOut                  : std_logic := '0';
   signal nextNulInp                  : std_logic := '0';
   signal fifoRdIdx                   : natural   := 0;
   signal fifoWrIdx                   : natural   := 0;
   signal frmsRcvdOut                 : natural   := 0;
   signal frmsSentOut                 : natural   := 0;
   signal frmsRcvdInp                 : natural   := 0;
   signal frmsSentInp                 : natural   := 0;

   signal hiSpeedEn                   : std_logic := '0';

   type PeriodArray is array (natural range <>) of time;

   constant EP_PERIODS_C : PeriodArray := (
      0 => 15.99 ns / 2.0E-3,
      1 => 15.99 ns / 2.0,
      2 => 16.77 ns / 2.0,
      3 => 15.99 ns * 1.0,
      4 => 15.99 ns * 1.0E-3
   );

   signal epPeriodSelInp : natural := 0;
   signal epPeriodSelOut : natural := 0;

begin

   U_TST : entity work.Usb2TstPkgProcesses;

   process is
   begin
      if ( not epRun ) then wait; end if;
      wait for EP_PERIODS_C(epPeriodSelInp + epPeriodSelOut);
      epClk <= not epClk;
   end process;

   P_TST_DRV : process is
      variable pol  : Usb2TstRetryPolicyType;
      variable eda  : Usb2ByteArray( 0 to d2'length );
      variable edal : natural;
   begin
      ulpiClkTick; ulpiClkTick;

      ulpiTstHandlePhyInit( ulpiTstOb );

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_ADDRESS_C, USB2_DEV_ADDR_DFLT_C, val => (x"00" & "0" & DEV_ADDR_C) );
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_CONFIGURATION_C, DEV_ADDR_C,     val => (x"00" & CONFIG_VALUE_C ) );

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_INTERFACE_C,     DEV_ADDR_C, val => ALT_C, idx => IFC_C );
      -- pass current configuration to test pkg
      usb2TstPkgConfig( epOb );

      ulpiClkTick;

      L_PERIODS_OUT : while ( true ) loop
         report "Testing OUT with clock period " & time'image( EP_PERIODS_C(epPeriodSelOut) ) & " (stay tuned...)";

         for l in speedCfg'range loop
            hiSpeedEn <= speedCfg(l).hse;
            pol       := speedCfg(l).pol;
            ulpiClkTick;

            sendD2( ulpiTstOb, frmsSentOut, 3,  nxtNul => DNL_C, rtrPol => pol );
            if ( DNL_C ) then
            sendD2( ulpiTstOb, frmsSentOut, 0,  nxtNul => false, rtrPol => pol );
            end if;
            sendD2( ulpiTstOb, frmsSentOut, 7,  nxtNul => false, rtrPol => pol );
            sendD2( ulpiTstOb, frmsSentOut, 15, nxtNul => DNL_C, rtrPol => pol );
            if ( DNL_C ) then
            sendD2( ulpiTstOb, frmsSentOut, 0,  nxtNul => false, rtrPol => pol );
            end if;
            sendD2( ulpiTstOb, frmsSentOut, 6,  nxtNul => false, rtrPol => pol, tstDon => true );

            while tstTglOut = epTglOut loop
               ulpiClkTick;
            end loop;
            tstTglOut <= not tstTglOut;
         end loop;

         if ( epPeriodSelOut = EP_PERIODS_C'high ) then
           exit L_PERIODS_OUT;
         else
           epPeriodSelOut <= epPeriodSelOut + 1;
           epTick;
           epTick;
           epTick;
           epTick;
         end if;
      end loop;
      epPeriodSelOut <= 0;
      epTick;

      -- these (precise) delays exercise a bug when the INP fifo 'don' readout was
      -- not qualified with 'not fifoEmpty'
      if ( true ) then
         for i in 1 to 10000 loop
            ulpiClkTick;
         end loop;

         epTick;
         startTstInp <= true;
         epTick;
      end if;

      L_PERIODS_INP : while ( true ) loop
         report "Testing INP with clock period " & time'image( EP_PERIODS_C(epPeriodSelInp) ) & " (stay tuned...)";

         -- for the INP direction there is no PING to be tested...
         ulpiTstRecvDat( ulpiTstOb, eda, edal, EP1, DEV_ADDR_C, rak => -1 );
         assert (nextNulInp = '1') = (edal = 0) report "Unexpected NUL or expected NUL but received data" & std_logic'image(nextNulInp) & " "&integer'image(edal) severity failure;
         if ( edal > 0 ) then
            assert getLen(eda(0)) = edal report "Unexpected length received " & integer'image(edal) severity failure;
            for i in 1 to edal - 1 loop
               assert eda(i) = d2(i-1) report "Unexpected data" severity failure;
            end loop;
            nextNulInp  <= eda(0)(NXT_NULL_IDX_C);
            if ( eda(0)(TST_DONE_IDX_C) = '1' ) then
               epTglInp <= not epTglInp;
               if ( epPeriodSelInp = EP_PERIODS_C'high ) then
                  exit L_PERIODS_INP;
               end if;
            end if;
         else
            assert nextNulInp = '1' report "Had expected a NUL packet" severity failure;
            nextNulInp <= '0';
         end if;
         frmsRcvdInp <= frmsRcvdInp + 1;
      end loop;

      ulpiClkTick;
      assert frmsRcvdInp + 1 = frmsSentInp
         report "Mismatching number of frames (RX " & integer'image( frmsRcvdInp ) & ", TX " & integer'image( frmsSentInp ) & ")"
         severity failure;


      for i in 0 to 20 loop
         ulpiClkTick;
      end loop;
      usb2Don <= true;
      wait;
   end process P_TST_DRV;

   P_END : process is
   begin
      wait until ( usb2Don );
      report "TEST PASSED (DON_IS_LAST_G : " & boolean'image(DON_IS_LAST_G) & ")";
      ulpiTstRun <= false;
      epRun      <= false;
      wait;
   end process P_END;

   P_EP_1_RD  : process ( epCLk ) is
      variable d0     : Usb2ByteType := (others => '0');
      variable expLen : natural := 0;
      variable x      : natural;
   begin
      if ( rising_edge( epClk ) ) then
         fifoRenOut <= '1';
         if ( ( not fifoEmptyOut and fifoRenOut ) = '1' and epRun ) then
            if ( fifoDonOut = '1' ) then
               x := 0;
               if ( not DNL_C ) then
                 x := 1;
                 assert d2(fifoRdIdx - 1) = fifoDatOut report "Data mismatch " severity failure;
               end if;
               assert fifoRdIdx + x = expLen report "Packet length mismatch" severity failure;
               fifoRdIdx <= 0;
               if ( fifoRdIdx = 0 ) then
                  assert (nextNulOut = '1') report "Expected a NULL packet" severity failure;
                  -- assume we never send two back-to-back NULLs
                  d0       := (others => '0');
               else
                  assert (nextNulOut = '0') report "Unexpected a NULL packet" severity failure;
               end if;
               if ( testDone( d0 ) ) then
                  epTglOut <= not epTglOut;
                  assert frmsRcvdOut + 1 = frmsSentOut report "Mismatch in number of frames!" severity failure;
               end if;
               frmsRcvdOut <= frmsRcvdOut + 1;
               expLen      := 0;
               nextNulOut  <= d0(NXT_NULL_IDX_C);
            else
               if ( fifoRdIdx = 0 ) then
                  d0      := fifoDatOut;
                  expLen  := getLen(fifoDatOut);
               else
                  assert d2(fifoRdIdx - 1) = fifoDatOut report "Data mismatch" severity failure;
               end if;
               fifoRdIdx <= fifoRdIdx + 1;
            end if;
         end if;
      end if;
   end process P_EP_1_RD;

   P_EP_1_WR  : process is
   begin
      epTick;
      while not startTstInp or epRstOut = '1' loop
         epTick;
      end loop;
      fifoSendD2( fifoInp, frmsSentInp, 3 );
      fifoSendD2( fifoInp, frmsSentInp, 3,  nxtNul => DNL_C );
      if ( DNL_C ) then
         fifoSendD2( fifoInp, frmsSentInp, 0 );
      end if;
      fifoSendD2( fifoInp, frmsSentInp, 7 );
      fifoSendD2( fifoInp, frmsSentInp, 15, nxtNul => DNL_C );
      if ( DNL_C ) then
         fifoSendD2( fifoInp, frmsSentInp, 0 );
      end if;
      fifoSendD2( fifoInp, frmsSentInp, 6, tstDon => true );

      while ( epTglInp = tstTglInp ) loop
         epTick;
      end loop;
      tstTglInp <= not tstTglInp;
      if ( epPeriodSelInp = EP_PERIODS_C'high ) then
         wait;
      else
         epPeriodSelInp <= epPeriodSelInp + 1;
         epTick;
      end if;
   end process P_EP_1_WR;



   U_CORE : entity work.Usb2Core
   generic map (
      SIMULATION_G                 => true,
      DESCRIPTORS_G                => USB2_APP_DESCRIPTORS_C
   )
   port map (
      ulpiClk                      => ulpiTstClk,

      ulpiRst                      => open,
      usb2Rst                      => open,

      ulpiIb                       => ulpiTstOb,
      ulpiOb                       => ulpiTstIb,

      usb2DevStatus                => devStatus,
      usb2Rx                       => usb2Rx,

      usb2Ep0ReqParam              => ep0ReqParam,
      usb2Ep0CtlExt                => ep0CtlExt,

      usb2HiSpeedEn                => hiSpeedEn,

      usb2EpIb                     => epIb,
      usb2EpOb                     => epOb
   );

   U_DUT : entity work.Usb2FifoEp
      generic map (
         LD_FIFO_DEPTH_INP_G       => (1 + ulpiTstNumBits( EP1_SZ_C - 1 )),
         -- for high-bandwidth throughput the fifo depth must be >= 2*MAX_PKT_SIZE_OUT_G
         -- because at the time a packet is released into the fifo there must already
         -- a decision be made if a second packet would fit.
         LD_FIFO_DEPTH_OUT_G       => (1 + ulpiTstNumBits( EP1_SZ_C - 1 )),
         TIMER_WIDTH_G             => 1,
         -- add an output register to the INP bound FIFO (to improve timing)
         OUT_REG_INP_G             => true,
         -- add an output register to the OUT bound FIFO (to improve timing)
         OUT_REG_OUT_G             => true,
         ASYNC_G                   => true,
         LD_MAX_FRAMES_INP_G       => 10,
         LD_MAX_FRAMES_OUT_G       => 10,
         DON_IS_LAST_G             => not DNL_C
      )
      port map (
         usb2Clk                   => ulpiTstClk,
         usb2Rst                   => open,

         minFillInp                => open,
         timeFillInp               => open,

         usb2EpOb                  => epIb(TST_EP_IDX_C),
         usb2EpIb                  => epOb(TST_EP_IDX_C),

         epClk                     => epClk,
         epRstOut                  => epRstOut,

         datInp                    => fifoInp.dat,
         donInp                    => fifoInp.don,
         wenInp                    => fifoInp.wen,
         filledInp                 => open,
         fullInp                   => fifoFullInp,

         datOut                    => fifoDatOut,
         donOut                    => fifoDonOut,
         renOut                    => fifoRenOut,
         filledOut                 => open,
         emptyOut                  => fifoEmptyOut
      );

end architecture sim;
