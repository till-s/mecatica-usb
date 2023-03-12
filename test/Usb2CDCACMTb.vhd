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

-- Testbed to exercise the CDCACM function; not much is done here
-- since its components are tested individually. We can use this
-- to simulate future problems, however.

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
        8 => x"09",  -- idVendor
        9 => x"12",
       10 => x"01",  -- idProduct
       11 => x"00",
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
       30 => x"7e",  -- wTotalLength
       31 => x"01",
       32 => x"08",  -- bNumInterfaces
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
       44 => x"02",  -- iFunction
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
       79 => x"10",  -- bInterval
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
      108 => x"00",  -- bFunctionSubClass
      109 => x"20",  -- bFunctionProtocol
      110 => x"03",  -- iFunction
      -- Usb2InterfaceDesc
      111 => x"09",  -- bLength
      112 => x"04",  -- bDescriptorType
      113 => x"02",  -- bInterfaceNumber
      114 => x"00",  -- bAlternateSetting
      115 => x"00",  -- bNumEndpoints
      116 => x"01",  -- bInterfaceClass
      117 => x"01",  -- bInterfaceSubClass
      118 => x"20",  -- bInterfaceProtocol
      119 => x"00",  -- iInterface
      -- Usb2UAC2FuncHeaderDesc
      120 => x"09",  -- bLength
      121 => x"24",  -- bDescriptorType
      122 => x"01",  -- bDescriptorSubtype
      123 => x"00",  -- bcdADC
      124 => x"02",
      125 => x"01",  -- bCategory
      126 => x"40",  -- wTotalLength
      127 => x"00",
      128 => x"00",  -- bmControls
      -- Usb2UAC2ClockSourceDesc
      129 => x"08",  -- bLength
      130 => x"24",  -- bDescriptorType
      131 => x"0a",  -- bDescriptorSubtype
      132 => x"09",  -- bClockID
      133 => x"00",  -- bmAttributes
      134 => x"01",  -- bmControls
      135 => x"00",  -- bAssocTerminal
      136 => x"00",  -- iClockSource
      -- Usb2UAC2InputTerminalDesc
      137 => x"11",  -- bLength
      138 => x"24",  -- bDescriptorType
      139 => x"02",  -- bDescriptorSubtype
      140 => x"01",  -- bTerminalID
      141 => x"01",  -- wTerminalType
      142 => x"01",
      143 => x"00",  -- bAssocTerminal
      144 => x"09",  -- bCSourceID
      145 => x"02",  -- bNrChannels
      146 => x"03",  -- bmChannelConfig
      147 => x"00",
      148 => x"00",
      149 => x"00",
      150 => x"00",  -- iChannelNames
      151 => x"00",  -- bmControls
      152 => x"00",
      153 => x"00",  -- iTerminal
      -- Usb2UAC2StereoFeatureUnitDesc
      154 => x"12",  -- bLength
      155 => x"24",  -- bDescriptorType
      156 => x"06",  -- bDescriptorSubtype
      157 => x"02",  -- bUnitID
      158 => x"01",  -- bSourceID
      159 => x"0f",  -- bmaControls0
      160 => x"00",
      161 => x"00",
      162 => x"00",
      163 => x"0f",  -- bmaControls1
      164 => x"00",
      165 => x"00",
      166 => x"00",
      167 => x"0f",  -- bmaControls2
      168 => x"00",
      169 => x"00",
      170 => x"00",
      171 => x"00",  -- iFeature
      -- Usb2UAC2OutputTerminalDesc
      172 => x"0c",  -- bLength
      173 => x"24",  -- bDescriptorType
      174 => x"03",  -- bDescriptorSubtype
      175 => x"03",  -- bTerminalID
      176 => x"01",  -- wTerminalType
      177 => x"03",
      178 => x"00",  -- bAssocTerminal
      179 => x"02",  -- bSourceID
      180 => x"09",  -- bCSourceID
      181 => x"00",  -- bmControls
      182 => x"00",
      183 => x"00",  -- iTerminal
      -- Usb2InterfaceDesc
      184 => x"09",  -- bLength
      185 => x"04",  -- bDescriptorType
      186 => x"03",  -- bInterfaceNumber
      187 => x"00",  -- bAlternateSetting
      188 => x"00",  -- bNumEndpoints
      189 => x"01",  -- bInterfaceClass
      190 => x"02",  -- bInterfaceSubClass
      191 => x"20",  -- bInterfaceProtocol
      192 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      193 => x"09",  -- bLength
      194 => x"04",  -- bDescriptorType
      195 => x"03",  -- bInterfaceNumber
      196 => x"01",  -- bAlternateSetting
      197 => x"02",  -- bNumEndpoints
      198 => x"01",  -- bInterfaceClass
      199 => x"02",  -- bInterfaceSubClass
      200 => x"20",  -- bInterfaceProtocol
      201 => x"00",  -- iInterface
      -- Usb2UAC2ClassSpecificASInterfaceDesc
      202 => x"10",  -- bLength
      203 => x"24",  -- bDescriptorType
      204 => x"01",  -- bDescriptorSubtype
      205 => x"01",  -- bTerminalLink
      206 => x"00",  -- bmControls
      207 => x"01",  -- bFormatType
      208 => x"01",  -- bmFormats
      209 => x"00",
      210 => x"00",
      211 => x"00",
      212 => x"02",  -- bNrChannels
      213 => x"03",  -- bmChannelConfig
      214 => x"00",
      215 => x"00",
      216 => x"00",
      217 => x"00",  -- iChannelNames
      -- Usb2UAC2FormatType1Desc
      218 => x"06",  -- bLength
      219 => x"24",  -- bDescriptorType
      220 => x"02",  -- bDescriptorSubtype
      221 => x"01",  -- bFormatType
      222 => x"03",  -- bSubslotSize
      223 => x"18",  -- bBitResolution
      -- Usb2EndpointDesc
      224 => x"07",  -- bLength
      225 => x"05",  -- bDescriptorType
      226 => x"03",  -- bEndpointAddress
      227 => x"05",  -- bmAttributes
      228 => x"26",  -- wMaxPacketSize
      229 => x"01",
      230 => x"01",  -- bInterval
      -- Usb2UAC2ASISOEndpointDesc
      231 => x"08",  -- bLength
      232 => x"25",  -- bDescriptorType
      233 => x"01",  -- bDescriptorSubtype
      234 => x"00",  -- bmAttributes
      235 => x"00",  -- bmControls
      236 => x"00",  -- bLockDelayUnits
      237 => x"00",  -- wLockDelay
      238 => x"00",
      -- Usb2EndpointDesc
      239 => x"07",  -- bLength
      240 => x"05",  -- bDescriptorType
      241 => x"83",  -- bEndpointAddress
      242 => x"11",  -- bmAttributes
      243 => x"03",  -- wMaxPacketSize
      244 => x"00",
      245 => x"01",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      246 => x"08",  -- bLength
      247 => x"0b",  -- bDescriptorType
      248 => x"04",  -- bFirstInterface
      249 => x"02",  -- bInterfaceCount
      250 => x"02",  -- bFunctionClass
      251 => x"06",  -- bFunctionSubClass
      252 => x"00",  -- bFunctionProtocol
      253 => x"04",  -- iFunction
      -- Usb2InterfaceDesc
      254 => x"09",  -- bLength
      255 => x"04",  -- bDescriptorType
      256 => x"04",  -- bInterfaceNumber
      257 => x"00",  -- bAlternateSetting
      258 => x"01",  -- bNumEndpoints
      259 => x"02",  -- bInterfaceClass
      260 => x"06",  -- bInterfaceSubClass
      261 => x"00",  -- bInterfaceProtocol
      262 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      263 => x"05",  -- bLength
      264 => x"24",  -- bDescriptorType
      265 => x"00",  -- bDescriptorSubtype
      266 => x"20",  -- bcdCDC
      267 => x"01",
      -- Usb2CDCFuncUnionDesc
      268 => x"05",  -- bLength
      269 => x"24",  -- bDescriptorType
      270 => x"06",  -- bDescriptorSubtype
      271 => x"04",  -- bControlInterface
      272 => x"05",
      -- Usb2CDCFuncEthernetDesc
      273 => x"0d",  -- bLength
      274 => x"24",  -- bDescriptorType
      275 => x"0f",  -- bDescriptorSubtype
      276 => x"05",  -- iMACAddress
      277 => x"00",  -- bmEthernetStatistics
      278 => x"00",
      279 => x"00",
      280 => x"00",
      281 => x"ea",  -- wMaxSegmentSize
      282 => x"05",
      283 => x"00",  -- wNumberMCFilters
      284 => x"80",
      285 => x"00",  -- bNumberPowerFilters
      -- Usb2EndpointDesc
      286 => x"07",  -- bLength
      287 => x"05",  -- bDescriptorType
      288 => x"85",  -- bEndpointAddress
      289 => x"03",  -- bmAttributes
      290 => x"10",  -- wMaxPacketSize
      291 => x"00",
      292 => x"10",  -- bInterval
      -- Usb2InterfaceDesc
      293 => x"09",  -- bLength
      294 => x"04",  -- bDescriptorType
      295 => x"05",  -- bInterfaceNumber
      296 => x"00",  -- bAlternateSetting
      297 => x"00",  -- bNumEndpoints
      298 => x"0a",  -- bInterfaceClass
      299 => x"00",  -- bInterfaceSubClass
      300 => x"00",  -- bInterfaceProtocol
      301 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      302 => x"09",  -- bLength
      303 => x"04",  -- bDescriptorType
      304 => x"05",  -- bInterfaceNumber
      305 => x"01",  -- bAlternateSetting
      306 => x"02",  -- bNumEndpoints
      307 => x"0a",  -- bInterfaceClass
      308 => x"00",  -- bInterfaceSubClass
      309 => x"00",  -- bInterfaceProtocol
      310 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      311 => x"07",  -- bLength
      312 => x"05",  -- bDescriptorType
      313 => x"84",  -- bEndpointAddress
      314 => x"02",  -- bmAttributes
      315 => x"40",  -- wMaxPacketSize
      316 => x"00",
      317 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      318 => x"07",  -- bLength
      319 => x"05",  -- bDescriptorType
      320 => x"04",  -- bEndpointAddress
      321 => x"02",  -- bmAttributes
      322 => x"40",  -- wMaxPacketSize
      323 => x"00",
      324 => x"00",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      325 => x"08",  -- bLength
      326 => x"0b",  -- bDescriptorType
      327 => x"06",  -- bFirstInterface
      328 => x"02",  -- bInterfaceCount
      329 => x"02",  -- bFunctionClass
      330 => x"0d",  -- bFunctionSubClass
      331 => x"00",  -- bFunctionProtocol
      332 => x"06",  -- iFunction
      -- Usb2InterfaceDesc
      333 => x"09",  -- bLength
      334 => x"04",  -- bDescriptorType
      335 => x"06",  -- bInterfaceNumber
      336 => x"00",  -- bAlternateSetting
      337 => x"01",  -- bNumEndpoints
      338 => x"02",  -- bInterfaceClass
      339 => x"0d",  -- bInterfaceSubClass
      340 => x"00",  -- bInterfaceProtocol
      341 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      342 => x"05",  -- bLength
      343 => x"24",  -- bDescriptorType
      344 => x"00",  -- bDescriptorSubtype
      345 => x"20",  -- bcdCDC
      346 => x"01",
      -- Usb2CDCFuncUnionDesc
      347 => x"05",  -- bLength
      348 => x"24",  -- bDescriptorType
      349 => x"06",  -- bDescriptorSubtype
      350 => x"06",  -- bControlInterface
      351 => x"07",
      -- Usb2CDCFuncEthernetDesc
      352 => x"0d",  -- bLength
      353 => x"24",  -- bDescriptorType
      354 => x"0f",  -- bDescriptorSubtype
      355 => x"07",  -- iMACAddress
      356 => x"00",  -- bmEthernetStatistics
      357 => x"00",
      358 => x"00",
      359 => x"00",
      360 => x"ea",  -- wMaxSegmentSize
      361 => x"05",
      362 => x"00",  -- wNumberMCFilters
      363 => x"80",
      364 => x"00",  -- bNumberPowerFilters
      -- Usb2CDCFuncNCMDesc
      365 => x"06",  -- bLength
      366 => x"24",  -- bDescriptorType
      367 => x"1a",  -- bDescriptorSubtype
      368 => x"00",  -- bcdNcmVersion
      369 => x"01",
      370 => x"00",  -- bmNetworkCapabilities
      -- Usb2EndpointDesc
      371 => x"07",  -- bLength
      372 => x"05",  -- bDescriptorType
      373 => x"87",  -- bEndpointAddress
      374 => x"03",  -- bmAttributes
      375 => x"10",  -- wMaxPacketSize
      376 => x"00",
      377 => x"10",  -- bInterval
      -- Usb2InterfaceDesc
      378 => x"09",  -- bLength
      379 => x"04",  -- bDescriptorType
      380 => x"07",  -- bInterfaceNumber
      381 => x"00",  -- bAlternateSetting
      382 => x"00",  -- bNumEndpoints
      383 => x"0a",  -- bInterfaceClass
      384 => x"00",  -- bInterfaceSubClass
      385 => x"01",  -- bInterfaceProtocol
      386 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      387 => x"09",  -- bLength
      388 => x"04",  -- bDescriptorType
      389 => x"07",  -- bInterfaceNumber
      390 => x"01",  -- bAlternateSetting
      391 => x"02",  -- bNumEndpoints
      392 => x"0a",  -- bInterfaceClass
      393 => x"00",  -- bInterfaceSubClass
      394 => x"01",  -- bInterfaceProtocol
      395 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      396 => x"07",  -- bLength
      397 => x"05",  -- bDescriptorType
      398 => x"86",  -- bEndpointAddress
      399 => x"02",  -- bmAttributes
      400 => x"40",  -- wMaxPacketSize
      401 => x"00",
      402 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      403 => x"07",  -- bLength
      404 => x"05",  -- bDescriptorType
      405 => x"06",  -- bEndpointAddress
      406 => x"02",  -- bmAttributes
      407 => x"40",  -- wMaxPacketSize
      408 => x"00",
      409 => x"00",  -- bInterval
      -- Usb2SentinelDesc
      410 => x"02",  -- bLength
      411 => x"ff",  -- bDescriptorType
      -- Usb2DeviceDesc
      412 => x"12",  -- bLength
      413 => x"01",  -- bDescriptorType
      414 => x"00",  -- bcdUSB
      415 => x"02",
      416 => x"ef",  -- bDeviceClass
      417 => x"02",  -- bDeviceSubClass
      418 => x"01",  -- bDeviceProtocol
      419 => x"40",  -- bMaxPacketSize0
      420 => x"09",  -- idVendor
      421 => x"12",
      422 => x"01",  -- idProduct
      423 => x"00",
      424 => x"00",  -- bcdDevice
      425 => x"01",
      426 => x"00",  -- iManufacturer
      427 => x"01",  -- iProduct
      428 => x"00",  -- iSerialNumber
      429 => x"01",  -- bNumConfigurations
      -- Usb2Device_QualifierDesc
      430 => x"0a",  -- bLength
      431 => x"06",  -- bDescriptorType
      432 => x"00",  -- bcdUSB
      433 => x"02",
      434 => x"ef",  -- bDeviceClass
      435 => x"02",  -- bDeviceSubClass
      436 => x"01",  -- bDeviceProtocol
      437 => x"40",  -- bMaxPacketSize0
      438 => x"01",  -- bNumConfigurations
      439 => x"00",  -- bReserved
      -- Usb2ConfigurationDesc
      440 => x"09",  -- bLength
      441 => x"02",  -- bDescriptorType
      442 => x"7e",  -- wTotalLength
      443 => x"01",
      444 => x"08",  -- bNumInterfaces
      445 => x"01",  -- bConfigurationValue
      446 => x"00",  -- iConfiguration
      447 => x"a0",  -- bmAttributes
      448 => x"32",  -- bMaxPower
      -- Usb2InterfaceAssociationDesc
      449 => x"08",  -- bLength
      450 => x"0b",  -- bDescriptorType
      451 => x"00",  -- bFirstInterface
      452 => x"02",  -- bInterfaceCount
      453 => x"02",  -- bFunctionClass
      454 => x"02",  -- bFunctionSubClass
      455 => x"00",  -- bFunctionProtocol
      456 => x"02",  -- iFunction
      -- Usb2InterfaceDesc
      457 => x"09",  -- bLength
      458 => x"04",  -- bDescriptorType
      459 => x"00",  -- bInterfaceNumber
      460 => x"00",  -- bAlternateSetting
      461 => x"01",  -- bNumEndpoints
      462 => x"02",  -- bInterfaceClass
      463 => x"02",  -- bInterfaceSubClass
      464 => x"00",  -- bInterfaceProtocol
      465 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      466 => x"05",  -- bLength
      467 => x"24",  -- bDescriptorType
      468 => x"00",  -- bDescriptorSubtype
      469 => x"20",  -- bcdCDC
      470 => x"01",
      -- Usb2CDCFuncCallManagementDesc
      471 => x"05",  -- bLength
      472 => x"24",  -- bDescriptorType
      473 => x"01",  -- bDescriptorSubtype
      474 => x"00",  -- bmCapabilities
      475 => x"01",  -- bDataInterface
      -- Usb2CDCFuncACMDesc
      476 => x"04",  -- bLength
      477 => x"24",  -- bDescriptorType
      478 => x"02",  -- bDescriptorSubtype
      479 => x"06",  -- bmCapabilities
      -- Usb2CDCFuncUnionDesc
      480 => x"05",  -- bLength
      481 => x"24",  -- bDescriptorType
      482 => x"06",  -- bDescriptorSubtype
      483 => x"00",  -- bControlInterface
      484 => x"01",
      -- Usb2EndpointDesc
      485 => x"07",  -- bLength
      486 => x"05",  -- bDescriptorType
      487 => x"82",  -- bEndpointAddress
      488 => x"03",  -- bmAttributes
      489 => x"08",  -- wMaxPacketSize
      490 => x"00",
      491 => x"08",  -- bInterval
      -- Usb2InterfaceDesc
      492 => x"09",  -- bLength
      493 => x"04",  -- bDescriptorType
      494 => x"01",  -- bInterfaceNumber
      495 => x"00",  -- bAlternateSetting
      496 => x"02",  -- bNumEndpoints
      497 => x"0a",  -- bInterfaceClass
      498 => x"00",  -- bInterfaceSubClass
      499 => x"00",  -- bInterfaceProtocol
      500 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      501 => x"07",  -- bLength
      502 => x"05",  -- bDescriptorType
      503 => x"81",  -- bEndpointAddress
      504 => x"02",  -- bmAttributes
      505 => x"00",  -- wMaxPacketSize
      506 => x"02",
      507 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      508 => x"07",  -- bLength
      509 => x"05",  -- bDescriptorType
      510 => x"01",  -- bEndpointAddress
      511 => x"02",  -- bmAttributes
      512 => x"00",  -- wMaxPacketSize
      513 => x"02",
      514 => x"00",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      515 => x"08",  -- bLength
      516 => x"0b",  -- bDescriptorType
      517 => x"02",  -- bFirstInterface
      518 => x"02",  -- bInterfaceCount
      519 => x"01",  -- bFunctionClass
      520 => x"00",  -- bFunctionSubClass
      521 => x"20",  -- bFunctionProtocol
      522 => x"03",  -- iFunction
      -- Usb2InterfaceDesc
      523 => x"09",  -- bLength
      524 => x"04",  -- bDescriptorType
      525 => x"02",  -- bInterfaceNumber
      526 => x"00",  -- bAlternateSetting
      527 => x"00",  -- bNumEndpoints
      528 => x"01",  -- bInterfaceClass
      529 => x"01",  -- bInterfaceSubClass
      530 => x"20",  -- bInterfaceProtocol
      531 => x"00",  -- iInterface
      -- Usb2UAC2FuncHeaderDesc
      532 => x"09",  -- bLength
      533 => x"24",  -- bDescriptorType
      534 => x"01",  -- bDescriptorSubtype
      535 => x"00",  -- bcdADC
      536 => x"02",
      537 => x"01",  -- bCategory
      538 => x"40",  -- wTotalLength
      539 => x"00",
      540 => x"00",  -- bmControls
      -- Usb2UAC2ClockSourceDesc
      541 => x"08",  -- bLength
      542 => x"24",  -- bDescriptorType
      543 => x"0a",  -- bDescriptorSubtype
      544 => x"09",  -- bClockID
      545 => x"00",  -- bmAttributes
      546 => x"01",  -- bmControls
      547 => x"00",  -- bAssocTerminal
      548 => x"00",  -- iClockSource
      -- Usb2UAC2InputTerminalDesc
      549 => x"11",  -- bLength
      550 => x"24",  -- bDescriptorType
      551 => x"02",  -- bDescriptorSubtype
      552 => x"01",  -- bTerminalID
      553 => x"01",  -- wTerminalType
      554 => x"01",
      555 => x"00",  -- bAssocTerminal
      556 => x"09",  -- bCSourceID
      557 => x"02",  -- bNrChannels
      558 => x"03",  -- bmChannelConfig
      559 => x"00",
      560 => x"00",
      561 => x"00",
      562 => x"00",  -- iChannelNames
      563 => x"00",  -- bmControls
      564 => x"00",
      565 => x"00",  -- iTerminal
      -- Usb2UAC2StereoFeatureUnitDesc
      566 => x"12",  -- bLength
      567 => x"24",  -- bDescriptorType
      568 => x"06",  -- bDescriptorSubtype
      569 => x"02",  -- bUnitID
      570 => x"01",  -- bSourceID
      571 => x"0f",  -- bmaControls0
      572 => x"00",
      573 => x"00",
      574 => x"00",
      575 => x"0f",  -- bmaControls1
      576 => x"00",
      577 => x"00",
      578 => x"00",
      579 => x"0f",  -- bmaControls2
      580 => x"00",
      581 => x"00",
      582 => x"00",
      583 => x"00",  -- iFeature
      -- Usb2UAC2OutputTerminalDesc
      584 => x"0c",  -- bLength
      585 => x"24",  -- bDescriptorType
      586 => x"03",  -- bDescriptorSubtype
      587 => x"03",  -- bTerminalID
      588 => x"01",  -- wTerminalType
      589 => x"03",
      590 => x"00",  -- bAssocTerminal
      591 => x"02",  -- bSourceID
      592 => x"09",  -- bCSourceID
      593 => x"00",  -- bmControls
      594 => x"00",
      595 => x"00",  -- iTerminal
      -- Usb2InterfaceDesc
      596 => x"09",  -- bLength
      597 => x"04",  -- bDescriptorType
      598 => x"03",  -- bInterfaceNumber
      599 => x"00",  -- bAlternateSetting
      600 => x"00",  -- bNumEndpoints
      601 => x"01",  -- bInterfaceClass
      602 => x"02",  -- bInterfaceSubClass
      603 => x"20",  -- bInterfaceProtocol
      604 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      605 => x"09",  -- bLength
      606 => x"04",  -- bDescriptorType
      607 => x"03",  -- bInterfaceNumber
      608 => x"01",  -- bAlternateSetting
      609 => x"02",  -- bNumEndpoints
      610 => x"01",  -- bInterfaceClass
      611 => x"02",  -- bInterfaceSubClass
      612 => x"20",  -- bInterfaceProtocol
      613 => x"00",  -- iInterface
      -- Usb2UAC2ClassSpecificASInterfaceDesc
      614 => x"10",  -- bLength
      615 => x"24",  -- bDescriptorType
      616 => x"01",  -- bDescriptorSubtype
      617 => x"01",  -- bTerminalLink
      618 => x"00",  -- bmControls
      619 => x"01",  -- bFormatType
      620 => x"01",  -- bmFormats
      621 => x"00",
      622 => x"00",
      623 => x"00",
      624 => x"02",  -- bNrChannels
      625 => x"03",  -- bmChannelConfig
      626 => x"00",
      627 => x"00",
      628 => x"00",
      629 => x"00",  -- iChannelNames
      -- Usb2UAC2FormatType1Desc
      630 => x"06",  -- bLength
      631 => x"24",  -- bDescriptorType
      632 => x"02",  -- bDescriptorSubtype
      633 => x"01",  -- bFormatType
      634 => x"03",  -- bSubslotSize
      635 => x"18",  -- bBitResolution
      -- Usb2EndpointDesc
      636 => x"07",  -- bLength
      637 => x"05",  -- bDescriptorType
      638 => x"03",  -- bEndpointAddress
      639 => x"05",  -- bmAttributes
      640 => x"26",  -- wMaxPacketSize
      641 => x"01",
      642 => x"04",  -- bInterval
      -- Usb2UAC2ASISOEndpointDesc
      643 => x"08",  -- bLength
      644 => x"25",  -- bDescriptorType
      645 => x"01",  -- bDescriptorSubtype
      646 => x"00",  -- bmAttributes
      647 => x"00",  -- bmControls
      648 => x"00",  -- bLockDelayUnits
      649 => x"00",  -- wLockDelay
      650 => x"00",
      -- Usb2EndpointDesc
      651 => x"07",  -- bLength
      652 => x"05",  -- bDescriptorType
      653 => x"83",  -- bEndpointAddress
      654 => x"11",  -- bmAttributes
      655 => x"04",  -- wMaxPacketSize
      656 => x"00",
      657 => x"04",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      658 => x"08",  -- bLength
      659 => x"0b",  -- bDescriptorType
      660 => x"04",  -- bFirstInterface
      661 => x"02",  -- bInterfaceCount
      662 => x"02",  -- bFunctionClass
      663 => x"06",  -- bFunctionSubClass
      664 => x"00",  -- bFunctionProtocol
      665 => x"04",  -- iFunction
      -- Usb2InterfaceDesc
      666 => x"09",  -- bLength
      667 => x"04",  -- bDescriptorType
      668 => x"04",  -- bInterfaceNumber
      669 => x"00",  -- bAlternateSetting
      670 => x"01",  -- bNumEndpoints
      671 => x"02",  -- bInterfaceClass
      672 => x"06",  -- bInterfaceSubClass
      673 => x"00",  -- bInterfaceProtocol
      674 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      675 => x"05",  -- bLength
      676 => x"24",  -- bDescriptorType
      677 => x"00",  -- bDescriptorSubtype
      678 => x"20",  -- bcdCDC
      679 => x"01",
      -- Usb2CDCFuncUnionDesc
      680 => x"05",  -- bLength
      681 => x"24",  -- bDescriptorType
      682 => x"06",  -- bDescriptorSubtype
      683 => x"04",  -- bControlInterface
      684 => x"05",
      -- Usb2CDCFuncEthernetDesc
      685 => x"0d",  -- bLength
      686 => x"24",  -- bDescriptorType
      687 => x"0f",  -- bDescriptorSubtype
      688 => x"05",  -- iMACAddress
      689 => x"00",  -- bmEthernetStatistics
      690 => x"00",
      691 => x"00",
      692 => x"00",
      693 => x"ea",  -- wMaxSegmentSize
      694 => x"05",
      695 => x"00",  -- wNumberMCFilters
      696 => x"80",
      697 => x"00",  -- bNumberPowerFilters
      -- Usb2EndpointDesc
      698 => x"07",  -- bLength
      699 => x"05",  -- bDescriptorType
      700 => x"85",  -- bEndpointAddress
      701 => x"03",  -- bmAttributes
      702 => x"10",  -- wMaxPacketSize
      703 => x"00",
      704 => x"08",  -- bInterval
      -- Usb2InterfaceDesc
      705 => x"09",  -- bLength
      706 => x"04",  -- bDescriptorType
      707 => x"05",  -- bInterfaceNumber
      708 => x"00",  -- bAlternateSetting
      709 => x"00",  -- bNumEndpoints
      710 => x"0a",  -- bInterfaceClass
      711 => x"00",  -- bInterfaceSubClass
      712 => x"00",  -- bInterfaceProtocol
      713 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      714 => x"09",  -- bLength
      715 => x"04",  -- bDescriptorType
      716 => x"05",  -- bInterfaceNumber
      717 => x"01",  -- bAlternateSetting
      718 => x"02",  -- bNumEndpoints
      719 => x"0a",  -- bInterfaceClass
      720 => x"00",  -- bInterfaceSubClass
      721 => x"00",  -- bInterfaceProtocol
      722 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      723 => x"07",  -- bLength
      724 => x"05",  -- bDescriptorType
      725 => x"84",  -- bEndpointAddress
      726 => x"02",  -- bmAttributes
      727 => x"00",  -- wMaxPacketSize
      728 => x"02",
      729 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      730 => x"07",  -- bLength
      731 => x"05",  -- bDescriptorType
      732 => x"04",  -- bEndpointAddress
      733 => x"02",  -- bmAttributes
      734 => x"00",  -- wMaxPacketSize
      735 => x"02",
      736 => x"00",  -- bInterval
      -- Usb2InterfaceAssociationDesc
      737 => x"08",  -- bLength
      738 => x"0b",  -- bDescriptorType
      739 => x"06",  -- bFirstInterface
      740 => x"02",  -- bInterfaceCount
      741 => x"02",  -- bFunctionClass
      742 => x"0d",  -- bFunctionSubClass
      743 => x"00",  -- bFunctionProtocol
      744 => x"06",  -- iFunction
      -- Usb2InterfaceDesc
      745 => x"09",  -- bLength
      746 => x"04",  -- bDescriptorType
      747 => x"06",  -- bInterfaceNumber
      748 => x"00",  -- bAlternateSetting
      749 => x"01",  -- bNumEndpoints
      750 => x"02",  -- bInterfaceClass
      751 => x"0d",  -- bInterfaceSubClass
      752 => x"00",  -- bInterfaceProtocol
      753 => x"00",  -- iInterface
      -- Usb2CDCFuncHeaderDesc
      754 => x"05",  -- bLength
      755 => x"24",  -- bDescriptorType
      756 => x"00",  -- bDescriptorSubtype
      757 => x"20",  -- bcdCDC
      758 => x"01",
      -- Usb2CDCFuncUnionDesc
      759 => x"05",  -- bLength
      760 => x"24",  -- bDescriptorType
      761 => x"06",  -- bDescriptorSubtype
      762 => x"06",  -- bControlInterface
      763 => x"07",
      -- Usb2CDCFuncEthernetDesc
      764 => x"0d",  -- bLength
      765 => x"24",  -- bDescriptorType
      766 => x"0f",  -- bDescriptorSubtype
      767 => x"07",  -- iMACAddress
      768 => x"00",  -- bmEthernetStatistics
      769 => x"00",
      770 => x"00",
      771 => x"00",
      772 => x"ea",  -- wMaxSegmentSize
      773 => x"05",
      774 => x"00",  -- wNumberMCFilters
      775 => x"80",
      776 => x"00",  -- bNumberPowerFilters
      -- Usb2CDCFuncNCMDesc
      777 => x"06",  -- bLength
      778 => x"24",  -- bDescriptorType
      779 => x"1a",  -- bDescriptorSubtype
      780 => x"00",  -- bcdNcmVersion
      781 => x"01",
      782 => x"00",  -- bmNetworkCapabilities
      -- Usb2EndpointDesc
      783 => x"07",  -- bLength
      784 => x"05",  -- bDescriptorType
      785 => x"87",  -- bEndpointAddress
      786 => x"03",  -- bmAttributes
      787 => x"10",  -- wMaxPacketSize
      788 => x"00",
      789 => x"08",  -- bInterval
      -- Usb2InterfaceDesc
      790 => x"09",  -- bLength
      791 => x"04",  -- bDescriptorType
      792 => x"07",  -- bInterfaceNumber
      793 => x"00",  -- bAlternateSetting
      794 => x"00",  -- bNumEndpoints
      795 => x"0a",  -- bInterfaceClass
      796 => x"00",  -- bInterfaceSubClass
      797 => x"01",  -- bInterfaceProtocol
      798 => x"00",  -- iInterface
      -- Usb2InterfaceDesc
      799 => x"09",  -- bLength
      800 => x"04",  -- bDescriptorType
      801 => x"07",  -- bInterfaceNumber
      802 => x"01",  -- bAlternateSetting
      803 => x"02",  -- bNumEndpoints
      804 => x"0a",  -- bInterfaceClass
      805 => x"00",  -- bInterfaceSubClass
      806 => x"01",  -- bInterfaceProtocol
      807 => x"00",  -- iInterface
      -- Usb2EndpointDesc
      808 => x"07",  -- bLength
      809 => x"05",  -- bDescriptorType
      810 => x"86",  -- bEndpointAddress
      811 => x"02",  -- bmAttributes
      812 => x"00",  -- wMaxPacketSize
      813 => x"02",
      814 => x"00",  -- bInterval
      -- Usb2EndpointDesc
      815 => x"07",  -- bLength
      816 => x"05",  -- bDescriptorType
      817 => x"06",  -- bEndpointAddress
      818 => x"02",  -- bmAttributes
      819 => x"00",  -- wMaxPacketSize
      820 => x"02",
      821 => x"00",  -- bInterval
      -- Usb2Desc
      822 => x"04",  -- bLength
      823 => x"03",  -- bDescriptorType
      824 => x"09",
      825 => x"04",
      -- Usb2StringDesc
      826 => x"46",  -- bLength
      827 => x"03",  -- bDescriptorType
      828 => x"54",
      829 => x"00",
      830 => x"69",
      831 => x"00",
      832 => x"6c",
      833 => x"00",
      834 => x"6c",
      835 => x"00",
      836 => x"27",
      837 => x"00",
      838 => x"73",
      839 => x"00",
      840 => x"20",
      841 => x"00",
      842 => x"4d",
      843 => x"00",
      844 => x"65",
      845 => x"00",
      846 => x"63",
      847 => x"00",
      848 => x"61",
      849 => x"00",
      850 => x"74",
      851 => x"00",
      852 => x"69",
      853 => x"00",
      854 => x"63",
      855 => x"00",
      856 => x"61",
      857 => x"00",
      858 => x"20",
      859 => x"00",
      860 => x"55",
      861 => x"00",
      862 => x"53",
      863 => x"00",
      864 => x"42",
      865 => x"00",
      866 => x"20",
      867 => x"00",
      868 => x"45",
      869 => x"00",
      870 => x"78",
      871 => x"00",
      872 => x"61",
      873 => x"00",
      874 => x"6d",
      875 => x"00",
      876 => x"70",
      877 => x"00",
      878 => x"6c",
      879 => x"00",
      880 => x"65",
      881 => x"00",
      882 => x"20",
      883 => x"00",
      884 => x"44",
      885 => x"00",
      886 => x"65",
      887 => x"00",
      888 => x"76",
      889 => x"00",
      890 => x"69",
      891 => x"00",
      892 => x"63",
      893 => x"00",
      894 => x"65",
      895 => x"00",
      -- Usb2StringDesc
      896 => x"1a",  -- bLength
      897 => x"03",  -- bDescriptorType
      898 => x"4d",
      899 => x"00",
      900 => x"65",
      901 => x"00",
      902 => x"63",
      903 => x"00",
      904 => x"61",
      905 => x"00",
      906 => x"74",
      907 => x"00",
      908 => x"69",
      909 => x"00",
      910 => x"63",
      911 => x"00",
      912 => x"61",
      913 => x"00",
      914 => x"20",
      915 => x"00",
      916 => x"41",
      917 => x"00",
      918 => x"43",
      919 => x"00",
      920 => x"4d",
      921 => x"00",
      -- Usb2StringDesc
      922 => x"2c",  -- bLength
      923 => x"03",  -- bDescriptorType
      924 => x"4d",
      925 => x"00",
      926 => x"65",
      927 => x"00",
      928 => x"63",
      929 => x"00",
      930 => x"61",
      931 => x"00",
      932 => x"74",
      933 => x"00",
      934 => x"69",
      935 => x"00",
      936 => x"63",
      937 => x"00",
      938 => x"61",
      939 => x"00",
      940 => x"20",
      941 => x"00",
      942 => x"55",
      943 => x"00",
      944 => x"41",
      945 => x"00",
      946 => x"43",
      947 => x"00",
      948 => x"32",
      949 => x"00",
      950 => x"20",
      951 => x"00",
      952 => x"53",
      953 => x"00",
      954 => x"70",
      955 => x"00",
      956 => x"65",
      957 => x"00",
      958 => x"61",
      959 => x"00",
      960 => x"6b",
      961 => x"00",
      962 => x"65",
      963 => x"00",
      964 => x"72",
      965 => x"00",
      -- Usb2StringDesc
      966 => x"1a",  -- bLength
      967 => x"03",  -- bDescriptorType
      968 => x"4d",
      969 => x"00",
      970 => x"65",
      971 => x"00",
      972 => x"63",
      973 => x"00",
      974 => x"61",
      975 => x"00",
      976 => x"74",
      977 => x"00",
      978 => x"69",
      979 => x"00",
      980 => x"63",
      981 => x"00",
      982 => x"61",
      983 => x"00",
      984 => x"20",
      985 => x"00",
      986 => x"45",
      987 => x"00",
      988 => x"43",
      989 => x"00",
      990 => x"4d",
      991 => x"00",
      -- Usb2StringDesc
      992 => x"1a",  -- bLength
      993 => x"03",  -- bDescriptorType
      994 => x"30",
      995 => x"00",
      996 => x"32",
      997 => x"00",
      998 => x"44",
      999 => x"00",
      1000 => x"45",
      1001 => x"00",
      1002 => x"41",
      1003 => x"00",
      1004 => x"44",
      1005 => x"00",
      1006 => x"42",
      1007 => x"00",
      1008 => x"45",
      1009 => x"00",
      1010 => x"45",
      1011 => x"00",
      1012 => x"46",
      1013 => x"00",
      1014 => x"33",
      1015 => x"00",
      1016 => x"34",
      1017 => x"00",
      -- Usb2StringDesc
      1018 => x"1a",  -- bLength
      1019 => x"03",  -- bDescriptorType
      1020 => x"4d",
      1021 => x"00",
      1022 => x"65",
      1023 => x"00",
      1024 => x"63",
      1025 => x"00",
      1026 => x"61",
      1027 => x"00",
      1028 => x"74",
      1029 => x"00",
      1030 => x"69",
      1031 => x"00",
      1032 => x"63",
      1033 => x"00",
      1034 => x"61",
      1035 => x"00",
      1036 => x"20",
      1037 => x"00",
      1038 => x"4e",
      1039 => x"00",
      1040 => x"43",
      1041 => x"00",
      1042 => x"4d",
      1043 => x"00",
      -- Usb2StringDesc
      1044 => x"1a",  -- bLength
      1045 => x"03",  -- bDescriptorType
      1046 => x"30",
      1047 => x"00",
      1048 => x"32",
      1049 => x"00",
      1050 => x"44",
      1051 => x"00",
      1052 => x"45",
      1053 => x"00",
      1054 => x"41",
      1055 => x"00",
      1056 => x"44",
      1057 => x"00",
      1058 => x"42",
      1059 => x"00",
      1060 => x"45",
      1061 => x"00",
      1062 => x"45",
      1063 => x"00",
      1064 => x"46",
      1065 => x"00",
      1066 => x"33",
      1067 => x"00",
      1068 => x"31",
      1069 => x"00",
      -- Usb2SentinelDesc
      1070 => x"02",  -- bLength
      1071 => x"ff"   -- bDescriptorType
      );
   begin
      return c;
   end function USB2_APP_DESCRIPTORS_F;
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

entity Usb2CDCACMTb is
end entity Usb2CDCACMTb;

architecture sim of Usb2CDCACMTb is

   constant DEV_ADDR_C             : Usb2DevAddrType := Usb2DevAddrType( to_unsigned(66, Usb2DevAddrType'length) );

   constant CONFIG_VALUE_C         : std_logic_vector(7 downto 0) := x"01";
   -- index is zero-based (?)
   constant CONFIG_INDEX_C         : std_logic_vector(7 downto 0) := x"00";

   constant CTL_IFC_IDX_C          : natural                      := 0;
   constant DATA_EP_IDX_C          : natural                      := 1;
   constant NOTE_EP_IDX_C          : natural                      := 2;

   constant NUM_ENDPOINTS_C        : natural                      := usb2AppGetMaxEndpointAddr(USB2_APP_DESCRIPTORS_C);
   constant NUM_STRINGS_C          : natural                      := USB2_APP_NUM_STRINGS_F  (USB2_APP_DESCRIPTORS_C);

   signal epIb                     : Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb                     : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_OB_INIT_C);

   signal usb2Rx                   : Usb2RxType   := USB2_RX_INIT_C;
   signal ep0ReqParam              : Usb2CtlReqParamType;

   signal fifoDataInp              : Usb2ByteType := (others => '0');
   signal fifoWenaInp              : std_logic    := '0';
   signal fifoFullInp              : std_logic;

   signal fifoDataOut              : Usb2ByteType  := (others => '0');
   signal fifoRenaOut              : std_logic     := '0';
   signal fifoEmptyOut             : std_logic;

   constant tstVecOut              : Usb2ByteArray := (
      x"ac",
      x"01",
      x"58"
   );

   signal tstOutIdx                : integer       := tstVecOut'low;

begin

   U_TST : entity work.Usb2TstPkgProcesses;

   P_TST : process is

   begin
      ulpiTstHandlePhyInit( ulpiTstOb );


      ulpiClkTick; ulpiClkTick;

      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_ADDRESS_C,
         USB2_DEV_ADDR_DFLT_C,
         val => (x"00" & "0" & DEV_ADDR_C)
      );

      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_CONFIGURATION_C,
         DEV_ADDR_C,
         val => (x"00" & CONFIG_VALUE_C )
      );

      -- ACM - ctl
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0000", -- ifc
         val => x"0000"  -- alt
      );

      -- ACM - strm
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0001", -- ifc
         val => x"0000"  -- alt
      );

      -- SND - ctl
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0002", -- ifc
         val => x"0000"  -- alt
      );

      -- SND - strm
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0003", -- ifc
         val => x"0001"  -- alt
      );

      -- ECM - ctl
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0004", -- ifc
         val => x"0000"  -- alt
      );

      -- ECM - strm
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0005", -- ifc
         val => x"0001"  -- alt
      );

      -- NCM - ctl
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0006", -- ifc
         val => x"0000"  -- alt
      );

      -- NCM - strm
      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_STD_SET_INTERFACE_C,
         DEV_ADDR_C,
         idx => x"0007", -- ifc
         val => x"0001"  -- alt
      );



      assert epOb(1).config.maxPktSizeInp = 512 report "EP1 IN  unexpected packet size!" severity failure;
      assert epOb(1).config.maxPktSizeOut = 512 report "EP1 OUT unexpected packet size!" severity failure;
      assert epOb(2).config.maxPktSizeInp =   8 report "EP2 IN  unexpected packet size!" severity failure;
      assert epOb(2).config.maxPktSizeOut =   0 report "EP2 OUT unexpected packet size!" severity failure;
      assert epOb(3).config.maxPktSizeInp =   4 report "EP3 IN  unexpected packet size!" severity failure;
      assert epOb(3).config.maxPktSizeOut = 294 report "EP3 OUT unexpected packet size!" severity failure;
      assert epOb(4).config.maxPktSizeInp = 512 report "EP4 IN  unexpected packet size!" severity failure;
      assert epOb(4).config.maxPktSizeOut = 512 report "EP4 OUT unexpected packet size!" severity failure;
      assert epOb(5).config.maxPktSizeInp =  16 report "EP5 IN  unexpected packet size!" severity failure;
      assert epOb(5).config.maxPktSizeOut =   0 report "EP5 OUT unexpected packet size!" severity failure;
      assert epOb(6).config.maxPktSizeInp = 512 report "EP6 IN  unexpected packet size!" severity failure;
      assert epOb(6).config.maxPktSizeOut = 512 report "EP6 OUT unexpected packet size!" severity failure;
      assert epOb(7).config.maxPktSizeInp =  16 report "EP7 IN  unexpected packet size!" severity failure;
      assert epOb(7).config.maxPktSizeOut =   0 report "EP7 OUT unexpected packet size!" severity failure;

      -- pass current configuration to test pkg
      usb2TstPkgConfig( epOb );

      ulpiClkTick;

      ulpiTstSendDat(
         ulpiTstOb,
         tstVecOut,
         to_unsigned( DATA_EP_IDX_C, Usb2EndpIdxType'length ),
         DEV_ADDR_C
      );

      while ( true ) loop
         ulpiClkTick;
      end loop;

   end process P_TST;

   P_RCV : process ( ulpiTstClk ) is
   begin
      if ( rising_edge( ulpiTstClk ) ) then
         if ( tstOutIdx = tstVecOut'low ) then
            fifoRenaOut <= '1';
         end if;
         if ( ( fifoRenaOut and not fifoEmptyOut ) = '1' ) then
            assert fifoDataOut = tstVecOut(tstOutIdx) report "OUT data mismatch" severity failure;
            if ( tstOutIdx = tstVecOut'high ) then
               report "Test PASSED";
               ulpiTstRun  <= false;
               fifoRenaOut <= '0';
            else
               tstOutIdx   <= tstOutIdx + 1;
            end if;
         end if;
      end if;
   end process;

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
      usb2Ep0CtlExt                => open,

      usb2HiSpeedEn                => '1',

      usb2EpIb                     => epIb,
      usb2EpOb                     => epOb
   );

   U_DUT : entity work.Usb2EpCDCACM
      generic map (
         CTL_IFC_NUM_G             => CTL_IFC_IDX_C,
         ENBL_LINE_BREAK_G         => false,
         ENBL_LINE_STATE_G         => false,
         LD_FIFO_DEPTH_INP_G       => 4,
         LD_FIFO_DEPTH_OUT_G       => 4
      )
      port map (
         usb2Clk                   => ulpiTstClk,
         usb2Rst                   => '0',

         usb2Rx                    => usb2Rx,
         usb2Ep0ReqParam           => ep0ReqParam,
         usb2Ep0CtlExt             => open,
         usb2Ep0ObExt              => open,
         usb2Ep0IbExt              => open,

         usb2DataEpIb              => epOb( DATA_EP_IDX_C ),
         usb2DataEpOb              => epIb( DATA_EP_IDX_C ),
         usb2NotifyEpIb            => epOb( NOTE_EP_IDX_C ),
         usb2NotifyEpOb            => epIb( NOTE_EP_IDX_C ),

         epClk                     => ulpiTstClk,
         epRstOut                  => open,

         fifoDataInp               => fifoDataInp,
         fifoWenaInp               => fifoWenaInp,
         fifoFullInp               => fifoFullInp,
         fifoFilledInp             => open,

         fifoDataOut               => fifoDataOut,
         fifoRenaOut               => fifoRenaOut,
         fifoEmptyOut              => fifoEmptyOut,
         fifoFilledOut             => open
      );

end architecture sim;
