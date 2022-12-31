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
        4 => x"00",
        5 => x"00",
        6 => x"00",
        7 => x"40",
        8 => x"23",
        9 => x"01",
       10 => x"cd",
       11 => x"ab",
       12 => x"00",
       13 => x"01",
       14 => x"00",
       15 => x"01",
       16 => x"00",
       17 => x"01",
      -- Usb2ConfigurationDesc
       18 => x"09",
       19 => x"02",
       20 => x"20",
       21 => x"00",
       22 => x"01",
       23 => x"01",
       24 => x"00",
       25 => x"80",
       26 => x"32",
      -- Usb2InterfaceDesc
       27 => x"09",
       28 => x"04",
       29 => x"00",
       30 => x"00",
       31 => x"02",
       32 => x"00",
       33 => x"00",
       34 => x"00",
       35 => x"00",
      -- Usb2EndpointDesc
       36 => x"07",
       37 => x"05",
       38 => x"81",
       39 => x"01",
       40 => x"08",
       41 => x"00",
       42 => x"00",
      -- Usb2EndpointDesc
       43 => x"07",
       44 => x"05",
       45 => x"01",
       46 => x"01",
       47 => x"08",
       48 => x"00",
       49 => x"00",
      -- Usb2Desc
       50 => x"04",
       51 => x"03",
       52 => x"09",
       53 => x"04",
      -- Usb2StringDesc
       54 => x"2e",
       55 => x"03",
       56 => x"54",
       57 => x"00",
       58 => x"69",
       59 => x"00",
       60 => x"6c",
       61 => x"00",
       62 => x"6c",
       63 => x"00",
       64 => x"27",
       65 => x"00",
       66 => x"73",
       67 => x"00",
       68 => x"20",
       69 => x"00",
       70 => x"55",
       71 => x"00",
       72 => x"4c",
       73 => x"00",
       74 => x"50",
       75 => x"00",
       76 => x"49",
       77 => x"00",
       78 => x"20",
       79 => x"00",
       80 => x"54",
       81 => x"00",
       82 => x"65",
       83 => x"00",
       84 => x"73",
       85 => x"00",
       86 => x"74",
       87 => x"00",
       88 => x"20",
       89 => x"00",
       90 => x"42",
       91 => x"00",
       92 => x"6f",
       93 => x"00",
       94 => x"61",
       95 => x"00",
       96 => x"72",
       97 => x"00",
       98 => x"64",
       99 => x"00",
      -- Usb2Desc
      100 => x"02",
      101 => x"ff"
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

entity Usb2IsoTb is
end entity Usb2IsoTb;

architecture sim of Usb2IsoTb is

   constant TST_EP_IDX_C           : natural := 1;
   constant TST_EP_C               : Usb2EndpIdxType := to_unsigned(TST_EP_IDX_C,Usb2EndpIdxType'length);

   constant DEV_ADDR_C             : Usb2DevAddrType := Usb2DevAddrType( to_unsigned(66, Usb2DevAddrType'length) );

   constant CONFIG_VALUE_C         : std_logic_vector(7 downto 0) := x"01";
   -- index is zero-based (?)
   constant CONFIG_INDEX_C         : std_logic_vector(7 downto 0) := x"00";

   constant NUM_ENDPOINTS_C        : natural                      := USB2_APP_NUM_ENDPOINTS_F(USB2_APP_DESCRIPTORS_C);

   constant ALT_C                  : std_logic_vector(15 downto 0) := x"0000";
   constant IFC_C                  : std_logic_vector(15 downto 0) := x"0000";
   
   signal epIb                     : Usb2EndpPairIbArray(1 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb                     : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_OB_INIT_C);

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

begin

   U_TST : entity work.Usb2TstPkgProcesses;

   P_TST : process is
      variable pid            : std_logic_vector(3 downto 0);
      variable reqval         : std_logic_vector(15 downto 0);
      variable reqidx         : std_logic_vector(15 downto 0);

      constant stridx         : natural                := USB2_APP_STRINGS_IDX_F(USB2_APP_DESCRIPTORS_C);
      constant devdsc         : Usb2ByteArray(0 to 17) := USB2_APP_DESCRIPTORS_C(0  to 17);
      constant cfgdsc         : Usb2ByteArray          := USB2_APP_DESCRIPTORS_C(18 to stridx - 1);
      constant strdsc         : Usb2ByteArray          := USB2_APP_DESCRIPTORS_C(stridx + 4 to stridx + 9);
      variable epCfg          : Usb2TstEpCfgArray      := (others => USB2_TST_EP_CFG_INIT_C);

      constant EP0_SZ_C       : Usb2ByteType           := USB2_APP_DESCRIPTORS_F(USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C); 
      constant EP1_SZ_C       : Usb2ByteType           := x"08"; -- must match value in descriptor

   begin
      epCfg( to_integer( USB2_ENDP_ZERO_C ) ).maxPktSizeInp := to_integer(unsigned(EP0_SZ_C));
      epCfg( to_integer( USB2_ENDP_ZERO_C ) ).maxPktSizeOut := to_integer(unsigned(EP0_SZ_C));
      epCfg( TST_EP_IDX_C                   ).maxPktSizeInp := to_integer(unsigned(EP1_SZ_C));
      epCfg( TST_EP_IDX_C                   ).maxPktSizeOut := to_integer(unsigned(EP1_SZ_C));

      ulpiTstHandlePhyInit( ulpiTstOb );

      usb2TstPkgConfig( epCfg );

      ulpiClkTick; ulpiClkTick;

report "SET_ADDRESS";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_ADDRESS_C, USB2_DEV_ADDR_DFLT_C, val => (x"00" & "0" & DEV_ADDR_C) );
report "SET_CONFIG";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_CONFIGURATION_C, DEV_ADDR_C, val => (x"00" & CONFIG_VALUE_C ) );
report "SET_INTERFACE";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_INTERFACE_C,     DEV_ADDR_C, val => ALT_C, idx => IFC_C );

      for i in 0 to 20 loop
         ulpiClkTick;
      end loop;

      ulpiTstRun <= false;
      report "TEST PASSED";
      wait;
   end process P_TST;

   U_DUT : entity work.Usb2Core
   generic map (
      SIMULATION_G                 => true,
      DESCRIPTORS_G                => USB2_APP_DESCRIPTORS_C
   )
   port map (
      clk                          => ulpiTstClk,

      ulpiRst                      => open,
      usb2Rst                      => open,

      ulpiIb                       => ulpiTstOb,
      ulpiOb                       => ulpiTstIb,

      usb2DevStatus                => open,
      usb2Rx                       => open,

      usb2Ep0ReqParam              => open,
      usb2Ep0CtlExt                => open,
      usb2Ep0CtlEpExt              => open,

      usb2EpIb                     => epIb,
      usb2EpOb                     => epOb
   );

end architecture sim;
