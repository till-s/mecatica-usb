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

   -- Python code to generate usb2AppGetDescriptors
   --
   -- import Usb2Desc
   -- 
   -- c = Usb2Desc.Usb2DescContext()
   -- d = c.Usb2DeviceDesc()
   -- d.iProduct("FOOBAR")
   -- d.bMaxPacketSize0(8)
   -- d = c.Usb2ConfigurationDesc()
   -- d.iConfiguration("C1")
   -- d = c.Usb2InterfaceDesc()
   -- d.iInterface("I0")
   -- d = c.Usb2Desc(2, c.Usb2Desc.clazz.DSC_TYPE_SENTINEL)
   -- d = c.Usb2DeviceDesc()
   -- d.bMaxPacketSize0(64)
   -- d = c.Usb2ConfigurationDesc()
   -- d.iConfiguration("C2")
   -- d = c.Usb2InterfaceDesc()
   -- d.iInterface("I1")
   -- d = c.Usb2ConfigurationDesc()
   -- d.iConfiguration("C3")
   -- d = c.Usb2InterfaceDesc()
   -- d.iInterface("I2")
   -- d = c.Usb2InterfaceDesc()
   -- d.bAlternateSetting( 1 )
   -- d = c.Usb2EndpointDesc()
   -- epAddr = 1
   -- d.bEndpointAddress( d.ENDPOINT_IN | (epAddr) )
   -- d.bmAttributes( d.ENDPOINT_TT_INTERRUPT )
   -- d.wMaxPacketSize( 16 )
   -- c.wrapup()
   -- c.vhdl()

   function usb2AppGetDescriptors return Usb2ByteArray is
   constant c : Usb2ByteArray := (
      -- Usb2DeviceDesc
        0 => x"12",  -- bLength
        1 => x"01",  -- bDescriptorType
        2 => x"00",  -- bcdUSB
        3 => x"02",
        4 => x"00",  -- bDeviceClass
        5 => x"00",  -- bDeviceSubClass
        6 => x"00",  -- bDeviceProtocol
        7 => x"08",  -- bMaxPacketSize0
        8 => x"00",  -- idVendor
        9 => x"00",
       10 => x"00",  -- idProduct
       11 => x"00",
       12 => x"00",  -- bcdDevice
       13 => x"02",
       14 => x"00",  -- iManufacturer
       15 => x"01",  -- iProduct
       16 => x"00",  -- iSerialNumber
       17 => x"01",  -- bNumConfigurations
      -- Usb2Device_QualifierDesc
       18 => x"0a",  -- bLength
       19 => x"06",  -- bDescriptorType
       20 => x"00",  -- bcdUSB
       21 => x"02",
       22 => x"00",  -- bDeviceClass
       23 => x"00",  -- bDeviceSubClass
       24 => x"00",  -- bDeviceProtocol
       25 => x"40",  -- bMaxPacketSize0
       26 => x"02",  -- bNumConfigurations
       27 => x"00",  -- bReserved
      -- Usb2ConfigurationDesc
       28 => x"09",  -- bLength
       29 => x"02",  -- bDescriptorType
       30 => x"12",  -- wTotalLength
       31 => x"00",
       32 => x"01",  -- bNumInterfaces
       33 => x"01",  -- bConfigurationValue
       34 => x"02",  -- iConfiguration
       35 => x"80",  -- bmAttributes
       36 => x"00",  -- bMaxPower
      -- Usb2InterfaceDesc
       37 => x"09",  -- bLength
       38 => x"04",  -- bDescriptorType
       39 => x"00",  -- bInterfaceNumber
       40 => x"00",  -- bAlternateSetting
       41 => x"00",  -- bNumEndpoints
       42 => x"00",  -- bInterfaceClass
       43 => x"00",  -- bInterfaceSubClass
       44 => x"00",  -- bInterfaceProtocol
       45 => x"03",  -- iInterface
      -- Usb2Desc
       46 => x"02",  -- bLength
       47 => x"ff",  -- bDescriptorType
      -- Usb2DeviceDesc
       48 => x"12",  -- bLength
       49 => x"01",  -- bDescriptorType
       50 => x"00",  -- bcdUSB
       51 => x"02",
       52 => x"00",  -- bDeviceClass
       53 => x"00",  -- bDeviceSubClass
       54 => x"00",  -- bDeviceProtocol
       55 => x"40",  -- bMaxPacketSize0
       56 => x"00",  -- idVendor
       57 => x"00",
       58 => x"00",  -- idProduct
       59 => x"00",
       60 => x"00",  -- bcdDevice
       61 => x"02",
       62 => x"00",  -- iManufacturer
       63 => x"00",  -- iProduct
       64 => x"00",  -- iSerialNumber
       65 => x"02",  -- bNumConfigurations
      -- Usb2Device_QualifierDesc
       66 => x"0a",  -- bLength
       67 => x"06",  -- bDescriptorType
       68 => x"00",  -- bcdUSB
       69 => x"02",
       70 => x"00",  -- bDeviceClass
       71 => x"00",  -- bDeviceSubClass
       72 => x"00",  -- bDeviceProtocol
       73 => x"08",  -- bMaxPacketSize0
       74 => x"01",  -- bNumConfigurations
       75 => x"00",  -- bReserved
      -- Usb2ConfigurationDesc
       76 => x"09",  -- bLength
       77 => x"02",  -- bDescriptorType
       78 => x"12",  -- wTotalLength
       79 => x"00",
       80 => x"01",  -- bNumInterfaces
       81 => x"01",  -- bConfigurationValue
       82 => x"04",  -- iConfiguration
       83 => x"80",  -- bmAttributes
       84 => x"00",  -- bMaxPower
      -- Usb2InterfaceDesc
       85 => x"09",  -- bLength
       86 => x"04",  -- bDescriptorType
       87 => x"00",  -- bInterfaceNumber
       88 => x"00",  -- bAlternateSetting
       89 => x"00",  -- bNumEndpoints
       90 => x"00",  -- bInterfaceClass
       91 => x"00",  -- bInterfaceSubClass
       92 => x"00",  -- bInterfaceProtocol
       93 => x"05",  -- iInterface
      -- Usb2ConfigurationDesc
       94 => x"09",  -- bLength
       95 => x"02",  -- bDescriptorType
       96 => x"22",  -- wTotalLength
       97 => x"00",
       98 => x"01",  -- bNumInterfaces
       99 => x"02",  -- bConfigurationValue
      100 => x"06",  -- iConfiguration
      101 => x"80",  -- bmAttributes
      102 => x"00",  -- bMaxPower
      -- Usb2InterfaceDesc
      103 => x"09",  -- bLength
      104 => x"04",  -- bDescriptorType
      105 => x"00",  -- bInterfaceNumber
      106 => x"00",  -- bAlternateSetting
      107 => x"00",  -- bNumEndpoints
      108 => x"00",  -- bInterfaceClass
      109 => x"00",  -- bInterfaceSubClass
      110 => x"00",  -- bInterfaceProtocol
      111 => x"07",  -- iInterface
      -- Usb2InterfaceDesc
      112 => x"09",  -- bLength
      113 => x"04",  -- bDescriptorType
      114 => x"00",  -- bInterfaceNumber
      115 => x"01",  -- bAlternateSetting
      116 => x"01",  -- bNumEndpoints
      117 => x"00",  -- bInterfaceClass
      118 => x"00",  -- bInterfaceSubClass
      119 => x"00",  -- bInterfaceProtocol
      120 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      121 => x"07",  -- bLength
      122 => x"05",  -- bDescriptorType
      123 => x"81",  -- bEndpointAddress
      124 => x"03",  -- bmAttributes
      125 => x"10",  -- wMaxPacketSize
      126 => x"00",
      127 => x"00",  -- bInterval
      -- Usb2Desc
      128 => x"04",  -- bLength
      129 => x"03",  -- bDescriptorType
      130 => x"09",
      131 => x"04",
      -- Usb2StringDesc
      132 => x"0e",  -- bLength
      133 => x"03",  -- bDescriptorType
      134 => x"46",
      135 => x"00",
      136 => x"4f",
      137 => x"00",
      138 => x"4f",
      139 => x"00",
      140 => x"42",
      141 => x"00",
      142 => x"41",
      143 => x"00",
      144 => x"52",
      145 => x"00",
      -- Usb2StringDesc
      146 => x"06",  -- bLength
      147 => x"03",  -- bDescriptorType
      148 => x"43",
      149 => x"00",
      150 => x"31",
      151 => x"00",
      -- Usb2StringDesc
      152 => x"06",  -- bLength
      153 => x"03",  -- bDescriptorType
      154 => x"49",
      155 => x"00",
      156 => x"30",
      157 => x"00",
      -- Usb2StringDesc
      158 => x"06",  -- bLength
      159 => x"03",  -- bDescriptorType
      160 => x"43",
      161 => x"00",
      162 => x"32",
      163 => x"00",
      -- Usb2StringDesc
      164 => x"06",  -- bLength
      165 => x"03",  -- bDescriptorType
      166 => x"49",
      167 => x"00",
      168 => x"31",
      169 => x"00",
      -- Usb2StringDesc
      170 => x"06",  -- bLength
      171 => x"03",  -- bDescriptorType
      172 => x"43",
      173 => x"00",
      174 => x"33",
      175 => x"00",
      -- Usb2StringDesc
      176 => x"06",  -- bLength
      177 => x"03",  -- bDescriptorType
      178 => x"49",
      179 => x"00",
      180 => x"32",
      181 => x"00",
      -- Usb2SentinelDesc
      182 => x"02",  -- bLength
      183 => x"ff"   -- bDescriptorType
   );
   begin
   return c;
   end function;

   constant USB2_APP_DESCRIPTORS_C : Usb2ByteArray := usb2AppGetDescriptors;

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

entity OthSpeedCfgTb is
end entity OthSpeedCfgTb;

architecture sim of OthSpeedCfgTb is

   constant DEV_ADDR_C             : Usb2DevAddrType := Usb2DevAddrType( to_unsigned(66, Usb2DevAddrType'length) );

   constant CONFIG_VALUE_C         : std_logic_vector(7 downto 0) := x"01";
   -- index is zero-based (?)
   constant CONFIG_INDEX_C         : std_logic_vector(7 downto 0) := x"00";
   constant CONFIG_BAD_VALUE_C     : std_logic_vector(7 downto 0) := x"02";

   constant NUM_ENDPOINTS_C        : natural                      := usb2AppGetMaxEndpointAddr(USB2_APP_DESCRIPTORS_C);

   constant EP0_SZ_C               : Usb2ByteType           := usb2AppGetDescriptors(USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C); 

   constant IFC_C                  : std_logic_vector(15 downto 0) := x"0000";
   constant ALT0_C                 : std_logic_vector(15 downto 0) := x"0000";
   constant ALT1_C                 : std_logic_vector(15 downto 0) := x"0001";
   
   signal epIb                     : Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb                     : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_OB_INIT_C);

   signal devStatus                : Usb2DevStatusType;
   signal usb2Rx                   : Usb2RxType;

   signal hiSpeed                  : std_logic := '0';

   signal ep0ReqParam              : Usb2CtlReqParamType;

begin

   U_TST : entity work.Usb2TstPkgProcesses;

   P_TST : process is
      variable idx            : integer;
      variable reqval         : std_logic_vector(15 downto 0);
      variable othConf        : Usb2ByteArray(USB2_APP_DESCRIPTORS_C'range) := USB2_APP_DESCRIPTORS_C;
   begin

      -- replace descriptor type CONF -> OTHER_SPEED_CONF
      idx := 0;
      while ( idx >= 0 ) loop
         idx := usb2NextDescriptor(othConf, idx, USB2_DESC_TYPE_CONFIGURATION_C);
         if ( idx >= 0 ) then
            othConf(idx + USB2_DESC_IDX_TYPE_C) := USB2_DESC_TYPE_OTHER_SPEED_CONF_C;
         end if;
      end loop;

      ulpiClkTick; ulpiClkTick;

      ulpiTstHandlePhyInit( ulpiTstOb );

      -- pass current configuration to test package
      usb2TstPkgConfig( epOb, hiSpeed = '1' );

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_ADDRESS_C, USB2_DEV_ADDR_DFLT_C, val => (x"00" & "0" & DEV_ADDR_C) );

      reqval := USB2_DESC_TYPE_DEVICE_C & x"00";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => USB2_APP_DESCRIPTORS_C(0 to 17));

      reqval := USB2_DESC_TYPE_DEVICE_QUALIFIER_C & x"00";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => USB2_APP_DESCRIPTORS_C(18 to 27));

      reqval := USB2_DESC_TYPE_OTHER_SPEED_CONF_C & x"01";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => othConf(94 to 127));
      -- switch speed, delay until visible
      hiSpeed <= '1';
      while not devStatus.hiSpeed loop
        ulpiClkTick;
      end loop;
      ulpiClkTick; -- delay until transferred into epOb.epConfig
      -- reconfigure test package for possibly different EP0 packet size
      usb2TstPkgConfig( epOb, hiSpeed = '1' );

      reqval := USB2_DESC_TYPE_DEVICE_C & x"00";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => USB2_APP_DESCRIPTORS_C(48 to 65));

      reqval := USB2_DESC_TYPE_DEVICE_QUALIFIER_C & x"00";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => USB2_APP_DESCRIPTORS_C(66 to 75));

      reqval := USB2_DESC_TYPE_OTHER_SPEED_CONF_C & x"01";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, epid => USB2_PID_HSK_STALL_C );

      reqval := USB2_DESC_TYPE_OTHER_SPEED_CONF_C & x"00";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => othConf(28 to 45));

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_CONFIGURATION_C, DEV_ADDR_C,     val => (x"00" & CONFIG_VALUE_C ) );
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_INTERFACE_C,     DEV_ADDR_C, val => ALT0_C, idx => IFC_C );

      assert epInpRunning( epOb(1) ) = '0' report "altsetting 0 and EP running?" severity failure;

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_INTERFACE_C,     DEV_ADDR_C, val => ALT1_C, idx => IFC_C );

      assert epInpRunning( epOb(1) ) = '1' report "altsetting 1 and EP not running?" severity failure;

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_INTERFACE_C,     DEV_ADDR_C, val => ALT0_C, idx => IFC_C );

      assert epInpRunning( epOb(1) ) = '0' report "altsetting 0; EP deactivation failed" severity failure;

      for i in 0 to 20 loop
         ulpiClkTick;
      end loop;
      ulpiTstRun <= false;
      report "TEST PASSED";
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

      ulpiIb                       => ulpiTstIO,
      ulpiOb                       => ulpiTstIb,

      usb2DevStatus                => devStatus,
      usb2Rx                       => usb2Rx,

      usb2HiSpeedEn                => hiSpeed,

      usb2Ep0ReqParam              => ep0ReqParam,
      usb2Ep0CtlExt                => open,

      usb2EpIb                     => epIb,
      usb2EpOb                     => epOb
   );

end architecture sim;
