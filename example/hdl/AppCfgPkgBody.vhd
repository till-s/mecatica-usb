-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- THIS FILE WAS AUTOMATICALLY GENERATED (genAppCfgPkgBody.py); DO NOT EDIT!

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;

package body Usb2AppCfgPkg is
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
       20 => x"43",
       21 => x"00",
       22 => x"02",
       23 => x"01",
       24 => x"00",
       25 => x"a0",
       26 => x"32",
      -- Usb2InterfaceDesc
       27 => x"09",
       28 => x"04",
       29 => x"00",
       30 => x"00",
       31 => x"01",
       32 => x"02",
       33 => x"02",
       34 => x"00",
       35 => x"00",
      -- Usb2CDCFuncHeaderDesc
       36 => x"05",
       37 => x"24",
       38 => x"00",
       39 => x"20",
       40 => x"01",
      -- Usb2CDCFuncCallManagementDesc
       41 => x"05",
       42 => x"24",
       43 => x"01",
       44 => x"00",
       45 => x"01",
      -- Usb2CDCFuncACMDesc
       46 => x"04",
       47 => x"24",
       48 => x"02",
       49 => x"04",
      -- Usb2CDCFuncUnionDesc
       50 => x"05",
       51 => x"24",
       52 => x"06",
       53 => x"00",
       54 => x"01",
      -- Usb2EndpointDesc
       55 => x"07",
       56 => x"05",
       57 => x"82",
       58 => x"03",
       59 => x"08",
       60 => x"00",
       61 => x"ff",
      -- Usb2InterfaceDesc
       62 => x"09",
       63 => x"04",
       64 => x"01",
       65 => x"00",
       66 => x"02",
       67 => x"0a",
       68 => x"00",
       69 => x"00",
       70 => x"00",
      -- Usb2EndpointDesc
       71 => x"07",
       72 => x"05",
       73 => x"81",
       74 => x"02",
       75 => x"00",
       76 => x"02",
       77 => x"00",
      -- Usb2EndpointDesc
       78 => x"07",
       79 => x"05",
       80 => x"01",
       81 => x"02",
       82 => x"00",
       83 => x"02",
       84 => x"00",
      -- Usb2Desc
       85 => x"04",
       86 => x"03",
       87 => x"09",
       88 => x"04",
      -- Usb2StringDesc
       89 => x"38",
       90 => x"03",
       91 => x"54",
       92 => x"00",
       93 => x"69",
       94 => x"00",
       95 => x"6c",
       96 => x"00",
       97 => x"6c",
       98 => x"00",
       99 => x"27",
      100 => x"00",
      101 => x"73",
      102 => x"00",
      103 => x"20",
      104 => x"00",
      105 => x"5a",
      106 => x"00",
      107 => x"79",
      108 => x"00",
      109 => x"6e",
      110 => x"00",
      111 => x"71",
      112 => x"00",
      113 => x"20",
      114 => x"00",
      115 => x"55",
      116 => x"00",
      117 => x"4c",
      118 => x"00",
      119 => x"50",
      120 => x"00",
      121 => x"49",
      122 => x"00",
      123 => x"20",
      124 => x"00",
      125 => x"54",
      126 => x"00",
      127 => x"65",
      128 => x"00",
      129 => x"73",
      130 => x"00",
      131 => x"74",
      132 => x"00",
      133 => x"20",
      134 => x"00",
      135 => x"42",
      136 => x"00",
      137 => x"6f",
      138 => x"00",
      139 => x"61",
      140 => x"00",
      141 => x"72",
      142 => x"00",
      143 => x"64",
      144 => x"00",
      -- Usb2Desc
      145 => x"02",
      146 => x"ff"
      );
   begin
      return c;
   end function USB2_APP_DESCRIPTORS_F;
end package body Usb2AppCfgPkg;
