-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;

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
      constant c : Usb2ByteArray := (
      -- Usb2DeviceDesc
        0 => x"12",
        1 => x"01",
        2 => x"00",
        3 => x"00",
        4 => x"ef",
        5 => x"02",
        6 => x"01",
        7 => x"40",
        8 => x"23",
        9 => x"01",
       10 => x"cd",
       11 => x"ab",
       12 => x"00",
       13 => x"01",
       14 => x"00",
       15 => x"00",
       16 => x"00",
       17 => x"01",
      -- Usb2ConfigurationDesc
       18 => x"09",
       19 => x"02",
       20 => x"33",
       21 => x"00",
       22 => x"02",
       23 => x"01",
       24 => x"00",
       25 => x"80",
       26 => x"32",
      -- Usb2InterfaceAssociationDesc
       27 => x"08",
       28 => x"0b",
       29 => x"00",
       30 => x"02",
       31 => x"01",
       32 => x"22",
       33 => x"30",
       34 => x"00",
      -- Usb2InterfaceDesc
       35 => x"09",
       36 => x"04",
       37 => x"00",
       38 => x"00",
       39 => x"00",
       40 => x"01",
       41 => x"01",
       42 => x"30",
       43 => x"00",
      -- Usb2InterfaceDesc
       44 => x"09",
       45 => x"04",
       46 => x"01",
       47 => x"00",
       48 => x"00",
       49 => x"01",
       50 => x"02",
       51 => x"30",
       52 => x"00",
      -- Usb2InterfaceDesc
       53 => x"09",
       54 => x"04",
       55 => x"01",
       56 => x"01",
       57 => x"01",
       58 => x"01",
       59 => x"02",
       60 => x"30",
       61 => x"00",
      -- Usb2EndpointDesc
       62 => x"07",
       63 => x"05",
       64 => x"01",
       65 => x"0d",
       66 => x"20",
       67 => x"01",
       68 => x"04",
      -- Usb2Desc
       69 => x"02",
       70 => x"ff"
      );
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

entity Usb2EpBADDSpkrCtlTb is
end entity Usb2EpBADDSpkrCtlTb;

architecture sim of Usb2EpBADDSpkrCtlTb is

   constant DEV_ADDR_C             : Usb2DevAddrType := Usb2DevAddrType( to_unsigned(66, Usb2DevAddrType'length) );

   constant CONFIG_VALUE_C         : std_logic_vector(7 downto 0) := x"01";
   -- index is zero-based (?)
   constant CONFIG_INDEX_C         : std_logic_vector(7 downto 0) := x"00";

   constant NUM_ENDPOINTS_C        : natural                      := usb2AppGetMaxEndpointAddr(USB2_APP_DESCRIPTORS_C);

   signal epIb                     : Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb                     : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_OB_INIT_C);

   signal usb2Rx                   : Usb2RxType := USB2_RX_INIT_C;
   signal ep0ReqParam              : Usb2CtlReqParamType;
   signal ep0CtlExt                : Usb2CtlExtType;

   signal powerState               : unsigned(1 downto 0);
   signal volLeft                  : signed(15 downto 0);
   signal volRight                 : signed(15 downto 0);
   signal volMaster                : signed(15 downto 0);
   signal powerStateSL             : std_logic_vector(1 downto 0);
   signal volLeftSL                : std_logic_vector(15 downto 0);
   signal volRightSL               : std_logic_vector(15 downto 0);
   signal volMasterSL              : std_logic_vector(15 downto 0);
   signal muteLeft                 : std_logic_vector(0 downto 0);
   signal muteRight                : std_logic_vector(0 downto 0);
   signal muteMaster               : std_logic_vector(0 downto 0);

   constant IFN_C                  : std_logic_vector(7 downto 0) := x"00";

   constant CRT_CLS_IFC_RD_C       : std_logic_vector(7 downto 0) := "10100001";
   constant CRT_CLS_IFC_WR_C       : std_logic_vector(7 downto 0) := "00100001";
   constant AC_COD_CUR_C           : unsigned        (7 downto 0) := x"01";
   constant AC_COD_RNG_C           : unsigned        (7 downto 0) := x"02";

   -- feature unit
   constant FU_MUTE_C              : std_logic_vector(7 downto 0) := x"01";
   constant FU_VOL_C               : std_logic_vector(7 downto 0) := x"02";
   constant CK_FRQ_C               : std_logic_vector(7 downto 0) := x"01";
   constant AC_PDOM_C              : std_logic_vector(7 downto 0) := x"02";

   constant ID_FU_C                : std_logic_vector(7 downto 0) := x"02";
   constant ID_CK_C                : std_logic_vector(7 downto 0) := x"09";
   constant ID_PD_C                : std_logic_vector(7 downto 0) := x"0A";

   constant CH_M_C                 : std_logic_vector(7 downto 0) := x"00";
   constant CH_L_C                 : std_logic_vector(7 downto 0) := x"01";
   constant CH_R_C                 : std_logic_vector(7 downto 0) := x"02";

   function toBytes(constant x : in std_logic_vector) return Usb2ByteArray  is
      variable v : Usb2ByteArray(0 to (x'length + 7)/8 - 1);
      variable a : std_logic_vector(v'length * 8 - 1 downto 0);
      constant z : std_logic_vector(a'length - x'length - 1 downto 0) := (others => '0');
   begin
      a := z & x;
      for i in v'low to v'high loop
         v(i) := a(8*i + 7 downto 8*i);
      end loop;
      return v;
   end function toBytes;

   function toBytes(constant x : in unsigned) return Usb2ByteArray is
   begin
      return toBytes( std_logic_vector( x ) );
   end function toBytes;

   function toBytes(constant x : in signed) return Usb2ByteArray is
   begin
      return toBytes( std_logic_vector( x ) );
   end function toBytes;

   procedure checkParm(
      signal    ob         : inout UlpiIbType;
      constant  eid        : in std_logic_vector;
      constant  sel        : in std_logic_vector;
      constant  cod        : in unsigned;
      constant  chn        : in std_logic_vector;
      signal    cmp        : in std_logic_vector;
      constant  set        : in std_logic_vector;
      constant  ini        : in std_logic_vector
   ) is
   begin
      assert cmp = ini report "checkParm initial value mismatch" severity failure;

      ulpiTstSendCtlReq(ob,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_WR_C,
         cod   => cod,
         val   => (sel  & chn),
         idx   => (eid  & IFN_C ),
         eda   => toBytes( set ),
         timo  => 100
      );

      assert cmp = set report "checkParam: written value mismatch" severity failure;

      ulpiTstSendCtlReq(ob,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_RD_C,
         cod   => cod,
         val   => (sel  & chn),
         idx   => (eid  & IFN_C ),
         eda   => toBytes( set ),
         timo  => 100
      );

   end procedure checkParm;

begin

   U_TST : entity work.Usb2TstPkgProcesses;

   P_TST : process is

      constant stridx         : natural                := USB2_APP_STRINGS_IDX_F(USB2_APP_DESCRIPTORS_C);
      constant devdsc         : Usb2ByteArray(0 to 17) := USB2_APP_DESCRIPTORS_C(0  to 17);
      constant cfgdsc         : Usb2ByteArray          := USB2_APP_DESCRIPTORS_C(18 to stridx - 1);
      constant strdsc         : Usb2ByteArray          := USB2_APP_DESCRIPTORS_C(stridx + 4 to stridx + 9);

      constant EP0_SZ_C       : Usb2ByteType           := USB2_APP_DESCRIPTORS_F(USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C); 


   begin
      ulpiTstHandlePhyInit( ulpiTstOb );


      ulpiClkTick; ulpiClkTick;

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_ADDRESS_C, USB2_DEV_ADDR_DFLT_C, val => (x"00" & "0" & DEV_ADDR_C) );
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_CONFIGURATION_C, DEV_ADDR_C, val => (x"00" & CONFIG_VALUE_C ) );

      -- pass current configuration to test pkg
      usb2TstPkgConfig( epOb );

      ulpiTstSendCtlReq(ulpiTstOb,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_RD_C,
         cod   => AC_COD_CUR_C,
         val   => (CK_FRQ_C & CH_M_C),
         idx   => (ID_CK_C  & IFN_C ),
         eda   => (x"80", x"bb", x"00", x"00"),
         timo  => 100
      );
         
      ulpiTstSendCtlReq(ulpiTstOb,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_RD_C,
         cod   => AC_COD_RNG_C,
         val   => (CK_FRQ_C & CH_M_C),
         idx   => (ID_CK_C  & IFN_C ),
         eda   => (x"01", x"00", x"80", x"bb", x"00", x"00", x"80", x"bb", x"00", x"00", x"00", x"00", x"00", x"00"),
         timo  => 100
      );


      -- short read
      ulpiTstSendCtlReq(ulpiTstOb,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_RD_C,
         cod   => AC_COD_RNG_C,
         val   => (CK_FRQ_C & CH_M_C),
         idx   => (ID_CK_C  & IFN_C ),
         eda   => (x"01", x"00"),
         timo  => 100
      );


      checkParm( ulpiTstOb, ID_PD_C, AC_PDOM_C, AC_COD_CUR_C, CH_M_C, powerStateSL, "10", "01" );

      checkParm( ulpiTstOb, ID_FU_C, FU_VOL_C, AC_COD_CUR_C, CH_M_C, volMasterSL, x"0044", x"0000" );
      checkParm( ulpiTstOb, ID_FU_C, FU_VOL_C, AC_COD_CUR_C, CH_L_C, volLeftSL  , x"8055", x"0000" );
      checkParm( ulpiTstOb, ID_FU_C, FU_VOL_C, AC_COD_CUR_C, CH_R_C, volRightSL , x"009a", x"0000" );

      checkParm( ulpiTstOb, ID_FU_C, FU_MUTE_C, AC_COD_CUR_C, CH_M_C, muteMaster, "1", "0" );
      checkParm( ulpiTstOb, ID_FU_C, FU_MUTE_C, AC_COD_CUR_C, CH_L_C, muteLeft  , "1", "0" );
      checkParm( ulpiTstOb, ID_FU_C, FU_MUTE_C, AC_COD_CUR_C, CH_R_C, muteRight , "1", "0" );

      ulpiTstSendCtlReq(ulpiTstOb,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_RD_C,
         cod   => AC_COD_RNG_C,
         val   => (FU_VOL_C & CH_M_C),
         idx   => (ID_FU_C  & IFN_C ),
         eda   => (x"01", x"00", x"01", x"80", x"ff", x"7f", x"01", x"00"),
         timo  => 100
      );

      ulpiTstSendCtlReq(ulpiTstOb,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_RD_C,
         cod   => AC_COD_RNG_C,
         val   => (FU_VOL_C & CH_L_C),
         idx   => (ID_FU_C  & IFN_C ),
         eda   => (x"01", x"00", x"01", x"80", x"ff", x"7f", x"01", x"00"),
         timo  => 100
      );

      ulpiTstSendCtlReq(ulpiTstOb,
         dva   => DEV_ADDR_C,
         typ   => CRT_CLS_IFC_RD_C,
         cod   => AC_COD_RNG_C,
         val   => (FU_VOL_C & CH_R_C),
         idx   => (ID_FU_C  & IFN_C ),
         eda   => (x"01", x"00", x"01", x"80", x"ff", x"7f", x"01", x"00"),
         timo  => 100
      );

      for i in 0 to 20 loop
         ulpiClkTick;
      end loop;

      report "Test PASSED";

      ulpiTstRun <= false;
      wait;
   end process P_TST;

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

      usb2DevStatus                => open,
      usb2Rx                       => usb2Rx,

      usb2Ep0ReqParam              => ep0ReqParam,
      usb2Ep0CtlExt                => ep0CtlExt,

      usb2EpIb                     => epIb,
      usb2EpOb                     => epOb
   );

   U_DUT : entity work.Usb2EpBADDSpkrCtl
      generic map (
         VOL_RNG_MIN_G             => -32767,
         VOL_RNG_MAX_G             => +32767,
         VOL_RNG_RES_G             => 1,
         AC_IFC_NUM_G              => toUsb2InterfaceNumType(IFN_C)
      )
      port map (
         clk                       => ulpiTstClk,
         rst                       => open,

         usb2Ep0ReqParam           => ep0ReqParam,
         usb2Ep0CtlExt             => ep0CtlExt,
         usb2Ep0ObExt              => epIb(0),
         usb2Ep0IbExt              => epOb(0),

         volLeft                   => volLeft,
         volRight                  => volRight,
         volMaster                 => volMaster,
         muteLeft                  => muteLeft(0),
         muteRight                 => muteRight(0),
         muteMaster                => muteMaster(0),
         powerState                => powerState
      );

   powerStateSL     <= std_logic_vector(powerState);
   volLeftSL        <= std_logic_vector(volLeft);
   volRightSL       <= std_logic_vector(volRight);
   volMasterSL      <= std_logic_vector(volMaster);

end architecture sim;
