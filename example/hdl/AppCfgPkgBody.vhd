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
        0 => x"12",  -- bLength
        1 => x"01",  -- bDescriptorType
        2 => x"00",  -- bcdUSB
        3 => x"02",
        4 => x"ef",  -- bDeviceClass
        5 => x"02",  -- bDeviceSubClass
        6 => x"01",  -- bDeviceProtocol
        7 => x"40",  -- bMaxPacketSize0
        8 => x"23",  -- idVendor
        9 => x"01",
       10 => x"cd",  -- idProduct
       11 => x"ab",
       12 => x"00",  -- bcdDevice
       13 => x"01",
       14 => x"00",  -- iManufacturer
       15 => x"01",  -- iProduct
       16 => x"00",  -- iSerialNumber
       17 => x"01",  -- bNumConfigurations
      -- Usb2Device_QualifierDesc
       18 => x"0a",  -- bLength
       19 => x"06",  -- bDescriptorType
       20 => x"00",  -- bcdUSB
       21 => x"02",
       22 => x"ef",  -- bDeviceClass
       23 => x"02",  -- bDeviceSubClass
       24 => x"01",  -- bDeviceProtocol
       25 => x"40",  -- bMaxPacketSize0
       26 => x"01",  -- bNumConfigurations
       27 => x"00",  -- bReserved
      -- Usb2ConfigurationDesc
       28 => x"09",  -- bLength
       29 => x"02",  -- bDescriptorType
       30 => x"c2",  -- wTotalLength
       31 => x"00",
       32 => x"06",  -- bNumInterfaces
       33 => x"01",  -- bConfigurationValue
       34 => x"00",  -- iConfiguration
       35 => x"a0",  -- bmAttributes
       36 => x"32",  -- bMaxPower
      -- Usb2InterfaceAssociationDesc
       37 => x"08",  -- bLength
       38 => x"0b",  -- bDescriptorType
       39 => x"00",  -- bFirstInterface
       40 => x"02",  -- bInterfaceCount
       41 => x"02",  -- bFunctionClass
       42 => x"02",  -- bFunctionSubClass
       43 => x"00",  -- bFunctionProtocol
       44 => x"00",  -- iFunction
      -- Usb2InterfaceDesc
       45 => x"09",  -- bLength
       46 => x"04",  -- bDescriptorType
       47 => x"00",  -- bInterfaceNumber
       48 => x"00",  -- bAlternateSetting
       49 => x"01",  -- bNumEndpoints
       50 => x"02",  -- bInterfaceClass
       51 => x"02",  -- bInterfaceSubClass
       52 => x"00",  -- bInterfaceProtocol
       53 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
       54 => x"05",  -- bLength
       55 => x"24",  -- bDescriptorType
       56 => x"00",  -- bDescriptorSubtype
       57 => x"20",  -- bcdCDC
       58 => x"01",
      -- Usb2CDCFuncCallManagementDesc
       59 => x"05",  -- bLength
       60 => x"24",  -- bDescriptorType
       61 => x"01",  -- bDescriptorSubtype
       62 => x"00",  -- bmCapabilities
       63 => x"01",  -- bDataInterface
      -- Usb2CDCFuncACMDesc
       64 => x"04",  -- bLength
       65 => x"24",  -- bDescriptorType
       66 => x"02",  -- bDescriptorSubtype
       67 => x"06",  -- bmCapabilities
      -- Usb2CDCFuncUnionDesc
       68 => x"05",  -- bLength
       69 => x"24",  -- bDescriptorType
       70 => x"06",  -- bDescriptorSubtype
       71 => x"00",  -- bControlInterface
       72 => x"01",
      -- Usb2EndpointDesc
       73 => x"07",  -- bLength
       74 => x"05",  -- bDescriptorType
       75 => x"82",  -- bEndpointAddress
       76 => x"03",  -- bmAttributes
       77 => x"08",  -- wMaxPacketSize
       78 => x"00",
       79 => x"ff",  -- bInterval
      -- Usb2InterfaceDesc
       80 => x"09",  -- bLength
       81 => x"04",  -- bDescriptorType
       82 => x"01",  -- bInterfaceNumber
       83 => x"00",  -- bAlternateSetting
       84 => x"02",  -- bNumEndpoints
       85 => x"0a",  -- bInterfaceClass
       86 => x"00",  -- bInterfaceSubClass
       87 => x"00",  -- bInterfaceProtocol
       88 => x"00",  -- iInterface
      -- Usb2EndpointDesc
       89 => x"07",  -- bLength
       90 => x"05",  -- bDescriptorType
       91 => x"81",  -- bEndpointAddress
       92 => x"02",  -- bmAttributes
       93 => x"40",  -- wMaxPacketSize
       94 => x"00",
       95 => x"00",  -- bInterval
      -- Usb2EndpointDesc
       96 => x"07",  -- bLength
       97 => x"05",  -- bDescriptorType
       98 => x"01",  -- bEndpointAddress
       99 => x"02",  -- bmAttributes
      100 => x"40",  -- wMaxPacketSize
      101 => x"00",
      102 => x"00",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      103 => x"08",  -- bLength
      104 => x"0b",  -- bDescriptorType
      105 => x"02",  -- bFirstInterface
      106 => x"02",  -- bInterfaceCount
      107 => x"01",  -- bFunctionClass
      108 => x"22",  -- bFunctionSubClass
      109 => x"30",  -- bFunctionProtocol
      110 => x"00",  -- iFunction
      -- Usb2InterfaceDesc
      111 => x"09",  -- bLength
      112 => x"04",  -- bDescriptorType
      113 => x"02",  -- bInterfaceNumber
      114 => x"00",  -- bAlternateSetting
      115 => x"00",  -- bNumEndpoints
      116 => x"01",  -- bInterfaceClass
      117 => x"01",  -- bInterfaceSubClass
      118 => x"30",  -- bInterfaceProtocol
      119 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      120 => x"09",  -- bLength
      121 => x"04",  -- bDescriptorType
      122 => x"03",  -- bInterfaceNumber
      123 => x"00",  -- bAlternateSetting
      124 => x"00",  -- bNumEndpoints
      125 => x"01",  -- bInterfaceClass
      126 => x"02",  -- bInterfaceSubClass
      127 => x"30",  -- bInterfaceProtocol
      128 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      129 => x"09",  -- bLength
      130 => x"04",  -- bDescriptorType
      131 => x"03",  -- bInterfaceNumber
      132 => x"01",  -- bAlternateSetting
      133 => x"02",  -- bNumEndpoints
      134 => x"01",  -- bInterfaceClass
      135 => x"02",  -- bInterfaceSubClass
      136 => x"30",  -- bInterfaceProtocol
      137 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      138 => x"07",  -- bLength
      139 => x"05",  -- bDescriptorType
      140 => x"03",  -- bEndpointAddress
      141 => x"05",  -- bmAttributes
      142 => x"c4",  -- wMaxPacketSize
      143 => x"00",
      144 => x"01",  -- bInterval
      -- Usb2EndpointDesc
      145 => x"07",  -- bLength
      146 => x"05",  -- bDescriptorType
      147 => x"83",  -- bEndpointAddress
      148 => x"11",  -- bmAttributes
      149 => x"03",  -- wMaxPacketSize
      150 => x"00",
      151 => x"01",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      152 => x"08",  -- bLength
      153 => x"0b",  -- bDescriptorType
      154 => x"04",  -- bFirstInterface
      155 => x"02",  -- bInterfaceCount
      156 => x"02",  -- bFunctionClass
      157 => x"06",  -- bFunctionSubClass
      158 => x"00",  -- bFunctionProtocol
      159 => x"00",  -- iFunction
      -- Usb2InterfaceDesc
      160 => x"09",  -- bLength
      161 => x"04",  -- bDescriptorType
      162 => x"04",  -- bInterfaceNumber
      163 => x"00",  -- bAlternateSetting
      164 => x"01",  -- bNumEndpoints
      165 => x"02",  -- bInterfaceClass
      166 => x"06",  -- bInterfaceSubClass
      167 => x"00",  -- bInterfaceProtocol
      168 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      169 => x"05",  -- bLength
      170 => x"24",  -- bDescriptorType
      171 => x"00",  -- bDescriptorSubtype
      172 => x"20",  -- bcdCDC
      173 => x"01",
      -- Usb2CDCFuncUnionDesc
      174 => x"05",  -- bLength
      175 => x"24",  -- bDescriptorType
      176 => x"06",  -- bDescriptorSubtype
      177 => x"04",  -- bControlInterface
      178 => x"05",
      -- Usb2CDCFuncEthernetDesc
      179 => x"0d",  -- bLength
      180 => x"24",  -- bDescriptorType
      181 => x"0f",  -- bDescriptorSubtype
      182 => x"02",  -- iMACAddress
      183 => x"00",  -- bmEthernetStatistics
      184 => x"00",
      185 => x"00",
      186 => x"00",
      187 => x"ea",  -- wMaxSegmentSize
      188 => x"05",
      189 => x"00",  -- wNumberMCFilters
      190 => x"80",
      191 => x"00",  -- bNumberPowerFilters
      -- Usb2EndpointDesc
      192 => x"07",  -- bLength
      193 => x"05",  -- bDescriptorType
      194 => x"85",  -- bEndpointAddress
      195 => x"03",  -- bmAttributes
      196 => x"10",  -- wMaxPacketSize
      197 => x"00",
      198 => x"10",  -- bInterval
      -- Usb2InterfaceDesc
      199 => x"09",  -- bLength
      200 => x"04",  -- bDescriptorType
      201 => x"05",  -- bInterfaceNumber
      202 => x"00",  -- bAlternateSetting
      203 => x"02",  -- bNumEndpoints
      204 => x"0a",  -- bInterfaceClass
      205 => x"00",  -- bInterfaceSubClass
      206 => x"00",  -- bInterfaceProtocol
      207 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      208 => x"07",  -- bLength
      209 => x"05",  -- bDescriptorType
      210 => x"84",  -- bEndpointAddress
      211 => x"02",  -- bmAttributes
      212 => x"40",  -- wMaxPacketSize
      213 => x"00",
      214 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      215 => x"07",  -- bLength
      216 => x"05",  -- bDescriptorType
      217 => x"04",  -- bEndpointAddress
      218 => x"02",  -- bmAttributes
      219 => x"40",  -- wMaxPacketSize
      220 => x"00",
      221 => x"00",  -- bInterval
      -- Usb2SentinelDesc
      222 => x"02",  -- bLength
      223 => x"ff",  -- bDescriptorType
      -- Usb2DeviceDesc
      224 => x"12",  -- bLength
      225 => x"01",  -- bDescriptorType
      226 => x"00",  -- bcdUSB
      227 => x"02",
      228 => x"ef",  -- bDeviceClass
      229 => x"02",  -- bDeviceSubClass
      230 => x"01",  -- bDeviceProtocol
      231 => x"40",  -- bMaxPacketSize0
      232 => x"23",  -- idVendor
      233 => x"01",
      234 => x"cd",  -- idProduct
      235 => x"ab",
      236 => x"00",  -- bcdDevice
      237 => x"01",
      238 => x"00",  -- iManufacturer
      239 => x"01",  -- iProduct
      240 => x"00",  -- iSerialNumber
      241 => x"01",  -- bNumConfigurations
      -- Usb2Device_QualifierDesc
      242 => x"0a",  -- bLength
      243 => x"06",  -- bDescriptorType
      244 => x"00",  -- bcdUSB
      245 => x"02",
      246 => x"ef",  -- bDeviceClass
      247 => x"02",  -- bDeviceSubClass
      248 => x"01",  -- bDeviceProtocol
      249 => x"40",  -- bMaxPacketSize0
      250 => x"01",  -- bNumConfigurations
      251 => x"00",  -- bReserved
      -- Usb2ConfigurationDesc
      252 => x"09",  -- bLength
      253 => x"02",  -- bDescriptorType
      254 => x"c2",  -- wTotalLength
      255 => x"00",
      256 => x"06",  -- bNumInterfaces
      257 => x"01",  -- bConfigurationValue
      258 => x"00",  -- iConfiguration
      259 => x"a0",  -- bmAttributes
      260 => x"32",  -- bMaxPower
      -- Usb2InterfaceAssociationDesc
      261 => x"08",  -- bLength
      262 => x"0b",  -- bDescriptorType
      263 => x"00",  -- bFirstInterface
      264 => x"02",  -- bInterfaceCount
      265 => x"02",  -- bFunctionClass
      266 => x"02",  -- bFunctionSubClass
      267 => x"00",  -- bFunctionProtocol
      268 => x"00",  -- iFunction
      -- Usb2InterfaceDesc
      269 => x"09",  -- bLength
      270 => x"04",  -- bDescriptorType
      271 => x"00",  -- bInterfaceNumber
      272 => x"00",  -- bAlternateSetting
      273 => x"01",  -- bNumEndpoints
      274 => x"02",  -- bInterfaceClass
      275 => x"02",  -- bInterfaceSubClass
      276 => x"00",  -- bInterfaceProtocol
      277 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      278 => x"05",  -- bLength
      279 => x"24",  -- bDescriptorType
      280 => x"00",  -- bDescriptorSubtype
      281 => x"20",  -- bcdCDC
      282 => x"01",
      -- Usb2CDCFuncCallManagementDesc
      283 => x"05",  -- bLength
      284 => x"24",  -- bDescriptorType
      285 => x"01",  -- bDescriptorSubtype
      286 => x"00",  -- bmCapabilities
      287 => x"01",  -- bDataInterface
      -- Usb2CDCFuncACMDesc
      288 => x"04",  -- bLength
      289 => x"24",  -- bDescriptorType
      290 => x"02",  -- bDescriptorSubtype
      291 => x"06",  -- bmCapabilities
      -- Usb2CDCFuncUnionDesc
      292 => x"05",  -- bLength
      293 => x"24",  -- bDescriptorType
      294 => x"06",  -- bDescriptorSubtype
      295 => x"00",  -- bControlInterface
      296 => x"01",
      -- Usb2EndpointDesc
      297 => x"07",  -- bLength
      298 => x"05",  -- bDescriptorType
      299 => x"82",  -- bEndpointAddress
      300 => x"03",  -- bmAttributes
      301 => x"08",  -- wMaxPacketSize
      302 => x"00",
      303 => x"10",  -- bInterval
      -- Usb2InterfaceDesc
      304 => x"09",  -- bLength
      305 => x"04",  -- bDescriptorType
      306 => x"01",  -- bInterfaceNumber
      307 => x"00",  -- bAlternateSetting
      308 => x"02",  -- bNumEndpoints
      309 => x"0a",  -- bInterfaceClass
      310 => x"00",  -- bInterfaceSubClass
      311 => x"00",  -- bInterfaceProtocol
      312 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      313 => x"07",  -- bLength
      314 => x"05",  -- bDescriptorType
      315 => x"81",  -- bEndpointAddress
      316 => x"02",  -- bmAttributes
      317 => x"00",  -- wMaxPacketSize
      318 => x"02",
      319 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      320 => x"07",  -- bLength
      321 => x"05",  -- bDescriptorType
      322 => x"01",  -- bEndpointAddress
      323 => x"02",  -- bmAttributes
      324 => x"00",  -- wMaxPacketSize
      325 => x"02",
      326 => x"00",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      327 => x"08",  -- bLength
      328 => x"0b",  -- bDescriptorType
      329 => x"02",  -- bFirstInterface
      330 => x"02",  -- bInterfaceCount
      331 => x"01",  -- bFunctionClass
      332 => x"22",  -- bFunctionSubClass
      333 => x"30",  -- bFunctionProtocol
      334 => x"00",  -- iFunction
      -- Usb2InterfaceDesc
      335 => x"09",  -- bLength
      336 => x"04",  -- bDescriptorType
      337 => x"02",  -- bInterfaceNumber
      338 => x"00",  -- bAlternateSetting
      339 => x"00",  -- bNumEndpoints
      340 => x"01",  -- bInterfaceClass
      341 => x"01",  -- bInterfaceSubClass
      342 => x"30",  -- bInterfaceProtocol
      343 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      344 => x"09",  -- bLength
      345 => x"04",  -- bDescriptorType
      346 => x"03",  -- bInterfaceNumber
      347 => x"00",  -- bAlternateSetting
      348 => x"00",  -- bNumEndpoints
      349 => x"01",  -- bInterfaceClass
      350 => x"02",  -- bInterfaceSubClass
      351 => x"30",  -- bInterfaceProtocol
      352 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      353 => x"09",  -- bLength
      354 => x"04",  -- bDescriptorType
      355 => x"03",  -- bInterfaceNumber
      356 => x"01",  -- bAlternateSetting
      357 => x"02",  -- bNumEndpoints
      358 => x"01",  -- bInterfaceClass
      359 => x"02",  -- bInterfaceSubClass
      360 => x"30",  -- bInterfaceProtocol
      361 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      362 => x"07",  -- bLength
      363 => x"05",  -- bDescriptorType
      364 => x"03",  -- bEndpointAddress
      365 => x"05",  -- bmAttributes
      366 => x"c4",  -- wMaxPacketSize
      367 => x"00",
      368 => x"04",  -- bInterval
      -- Usb2EndpointDesc
      369 => x"07",  -- bLength
      370 => x"05",  -- bDescriptorType
      371 => x"83",  -- bEndpointAddress
      372 => x"11",  -- bmAttributes
      373 => x"04",  -- wMaxPacketSize
      374 => x"00",
      375 => x"04",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      376 => x"08",  -- bLength
      377 => x"0b",  -- bDescriptorType
      378 => x"04",  -- bFirstInterface
      379 => x"02",  -- bInterfaceCount
      380 => x"02",  -- bFunctionClass
      381 => x"06",  -- bFunctionSubClass
      382 => x"00",  -- bFunctionProtocol
      383 => x"00",  -- iFunction
      -- Usb2InterfaceDesc
      384 => x"09",  -- bLength
      385 => x"04",  -- bDescriptorType
      386 => x"04",  -- bInterfaceNumber
      387 => x"00",  -- bAlternateSetting
      388 => x"01",  -- bNumEndpoints
      389 => x"02",  -- bInterfaceClass
      390 => x"06",  -- bInterfaceSubClass
      391 => x"00",  -- bInterfaceProtocol
      392 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      393 => x"05",  -- bLength
      394 => x"24",  -- bDescriptorType
      395 => x"00",  -- bDescriptorSubtype
      396 => x"20",  -- bcdCDC
      397 => x"01",
      -- Usb2CDCFuncUnionDesc
      398 => x"05",  -- bLength
      399 => x"24",  -- bDescriptorType
      400 => x"06",  -- bDescriptorSubtype
      401 => x"04",  -- bControlInterface
      402 => x"05",
      -- Usb2CDCFuncEthernetDesc
      403 => x"0d",  -- bLength
      404 => x"24",  -- bDescriptorType
      405 => x"0f",  -- bDescriptorSubtype
      406 => x"02",  -- iMACAddress
      407 => x"00",  -- bmEthernetStatistics
      408 => x"00",
      409 => x"00",
      410 => x"00",
      411 => x"ea",  -- wMaxSegmentSize
      412 => x"05",
      413 => x"00",  -- wNumberMCFilters
      414 => x"80",
      415 => x"00",  -- bNumberPowerFilters
      -- Usb2EndpointDesc
      416 => x"07",  -- bLength
      417 => x"05",  -- bDescriptorType
      418 => x"85",  -- bEndpointAddress
      419 => x"03",  -- bmAttributes
      420 => x"10",  -- wMaxPacketSize
      421 => x"00",
      422 => x"08",  -- bInterval
      -- Usb2InterfaceDesc
      423 => x"09",  -- bLength
      424 => x"04",  -- bDescriptorType
      425 => x"05",  -- bInterfaceNumber
      426 => x"00",  -- bAlternateSetting
      427 => x"02",  -- bNumEndpoints
      428 => x"0a",  -- bInterfaceClass
      429 => x"00",  -- bInterfaceSubClass
      430 => x"00",  -- bInterfaceProtocol
      431 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      432 => x"07",  -- bLength
      433 => x"05",  -- bDescriptorType
      434 => x"84",  -- bEndpointAddress
      435 => x"02",  -- bmAttributes
      436 => x"00",  -- wMaxPacketSize
      437 => x"02",
      438 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      439 => x"07",  -- bLength
      440 => x"05",  -- bDescriptorType
      441 => x"04",  -- bEndpointAddress
      442 => x"02",  -- bmAttributes
      443 => x"00",  -- wMaxPacketSize
      444 => x"02",
      445 => x"00",  -- bInterval
      -- Usb2Desc
      446 => x"04",  -- bLength
      447 => x"03",  -- bDescriptorType
      448 => x"09",
      449 => x"04",
      -- Usb2StringDesc
      450 => x"38",  -- bLength
      451 => x"03",  -- bDescriptorType
      452 => x"54",
      453 => x"00",
      454 => x"69",
      455 => x"00",
      456 => x"6c",
      457 => x"00",
      458 => x"6c",
      459 => x"00",
      460 => x"27",
      461 => x"00",
      462 => x"73",
      463 => x"00",
      464 => x"20",
      465 => x"00",
      466 => x"5a",
      467 => x"00",
      468 => x"79",
      469 => x"00",
      470 => x"6e",
      471 => x"00",
      472 => x"71",
      473 => x"00",
      474 => x"20",
      475 => x"00",
      476 => x"55",
      477 => x"00",
      478 => x"4c",
      479 => x"00",
      480 => x"50",
      481 => x"00",
      482 => x"49",
      483 => x"00",
      484 => x"20",
      485 => x"00",
      486 => x"54",
      487 => x"00",
      488 => x"65",
      489 => x"00",
      490 => x"73",
      491 => x"00",
      492 => x"74",
      493 => x"00",
      494 => x"20",
      495 => x"00",
      496 => x"42",
      497 => x"00",
      498 => x"6f",
      499 => x"00",
      500 => x"61",
      501 => x"00",
      502 => x"72",
      503 => x"00",
      504 => x"64",
      505 => x"00",
      -- Usb2StringDesc
      506 => x"1a",  -- bLength
      507 => x"03",  -- bDescriptorType
      508 => x"30",
      509 => x"00",
      510 => x"32",
      511 => x"00",
      512 => x"44",
      513 => x"00",
      514 => x"45",
      515 => x"00",
      516 => x"41",
      517 => x"00",
      518 => x"44",
      519 => x"00",
      520 => x"42",
      521 => x"00",
      522 => x"45",
      523 => x"00",
      524 => x"45",
      525 => x"00",
      526 => x"46",
      527 => x"00",
      528 => x"33",
      529 => x"00",
      530 => x"34",
      531 => x"00",
      -- Usb2SentinelDesc
      532 => x"02",  -- bLength
      533 => x"ff"   -- bDescriptorType

      );
   begin
      return c;
   end function USB2_APP_DESCRIPTORS_F;
end package body Usb2AppCfgPkg;
