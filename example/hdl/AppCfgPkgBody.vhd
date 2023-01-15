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
       15 => x"01",
       16 => x"00",
       17 => x"01",
      -- Usb2ConfigurationDesc
       18 => x"09",
       19 => x"02",
       20 => x"7c",
       21 => x"00",
       22 => x"04",
       23 => x"01",
       24 => x"00",
       25 => x"a0",
       26 => x"32",
      -- Usb2InterfaceAssociationDesc
       27 => x"08",
       28 => x"0b",
       29 => x"00",
       30 => x"02",
       31 => x"02",
       32 => x"02",
       33 => x"00",
       34 => x"00",
      -- Usb2InterfaceDesc
       35 => x"09",
       36 => x"04",
       37 => x"00",
       38 => x"00",
       39 => x"01",
       40 => x"02",
       41 => x"02",
       42 => x"00",
       43 => x"00",
      -- Usb2CDCFuncHeaderDesc
       44 => x"05",
       45 => x"24",
       46 => x"00",
       47 => x"20",
       48 => x"01",
      -- Usb2CDCFuncCallManagementDesc
       49 => x"05",
       50 => x"24",
       51 => x"01",
       52 => x"00",
       53 => x"01",
      -- Usb2CDCFuncACMDesc
       54 => x"04",
       55 => x"24",
       56 => x"02",
       57 => x"04",
      -- Usb2CDCFuncUnionDesc
       58 => x"05",
       59 => x"24",
       60 => x"06",
       61 => x"00",
       62 => x"01",
      -- Usb2EndpointDesc
       63 => x"07",
       64 => x"05",
       65 => x"82",
       66 => x"03",
       67 => x"08",
       68 => x"00",
       69 => x"10",
      -- Usb2InterfaceDesc
       70 => x"09",
       71 => x"04",
       72 => x"01",
       73 => x"00",
       74 => x"02",
       75 => x"0a",
       76 => x"00",
       77 => x"00",
       78 => x"00",
      -- Usb2EndpointDesc
       79 => x"07",
       80 => x"05",
       81 => x"81",
       82 => x"02",
       83 => x"00",
       84 => x"02",
       85 => x"00",
      -- Usb2EndpointDesc
       86 => x"07",
       87 => x"05",
       88 => x"01",
       89 => x"02",
       90 => x"00",
       91 => x"02",
       92 => x"00",
      -- Usb2InterfaceAssociationDesc
       93 => x"08",
       94 => x"0b",
       95 => x"02",
       96 => x"02",
       97 => x"01",
       98 => x"22",
       99 => x"30",
      100 => x"00",
      -- Usb2InterfaceDesc
      101 => x"09",
      102 => x"04",
      103 => x"02",
      104 => x"00",
      105 => x"00",
      106 => x"01",
      107 => x"01",
      108 => x"30",
      109 => x"00",
      -- Usb2InterfaceDesc
      110 => x"09",
      111 => x"04",
      112 => x"03",
      113 => x"00",
      114 => x"00",
      115 => x"01",
      116 => x"02",
      117 => x"30",
      118 => x"00",
      -- Usb2InterfaceDesc
      119 => x"09",
      120 => x"04",
      121 => x"03",
      122 => x"01",
      123 => x"02",
      124 => x"01",
      125 => x"02",
      126 => x"30",
      127 => x"00",
      -- Usb2EndpointDesc
      128 => x"07",
      129 => x"05",
      130 => x"03",
      131 => x"05",
      132 => x"20",
      133 => x"01",
      134 => x"04",
      -- Usb2EndpointDesc
      135 => x"07",
      136 => x"05",
      137 => x"83",
      138 => x"11",
      139 => x"04",
      140 => x"00",
      141 => x"04",
      -- Usb2Desc
      142 => x"04",
      143 => x"03",
      144 => x"09",
      145 => x"04",
      -- Usb2StringDesc
      146 => x"38",
      147 => x"03",
      148 => x"54",
      149 => x"00",
      150 => x"69",
      151 => x"00",
      152 => x"6c",
      153 => x"00",
      154 => x"6c",
      155 => x"00",
      156 => x"27",
      157 => x"00",
      158 => x"73",
      159 => x"00",
      160 => x"20",
      161 => x"00",
      162 => x"5a",
      163 => x"00",
      164 => x"79",
      165 => x"00",
      166 => x"6e",
      167 => x"00",
      168 => x"71",
      169 => x"00",
      170 => x"20",
      171 => x"00",
      172 => x"55",
      173 => x"00",
      174 => x"4c",
      175 => x"00",
      176 => x"50",
      177 => x"00",
      178 => x"49",
      179 => x"00",
      180 => x"20",
      181 => x"00",
      182 => x"54",
      183 => x"00",
      184 => x"65",
      185 => x"00",
      186 => x"73",
      187 => x"00",
      188 => x"74",
      189 => x"00",
      190 => x"20",
      191 => x"00",
      192 => x"42",
      193 => x"00",
      194 => x"6f",
      195 => x"00",
      196 => x"61",
      197 => x"00",
      198 => x"72",
      199 => x"00",
      200 => x"64",
      201 => x"00",
      -- Usb2Desc
      202 => x"02",
      203 => x"ff"
      );
   begin
      return c;
   end function USB2_APP_DESCRIPTORS_F;
end package body Usb2AppCfgPkg;
