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
        3 => x"02",
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
      -- Usb2Device_QualifierDesc
       18 => x"0a",
       19 => x"06",
       20 => x"00",
       21 => x"02",
       22 => x"ef",
       23 => x"02",
       24 => x"01",
       25 => x"40",
       26 => x"01",
       27 => x"00",
      -- Usb2ConfigurationDesc
       28 => x"09",
       29 => x"02",
       30 => x"c2",
       31 => x"00",
       32 => x"06",
       33 => x"01",
       34 => x"00",
       35 => x"a0",
       36 => x"32",
      -- Usb2InterfaceAssociationDesc
       37 => x"08",
       38 => x"0b",
       39 => x"00",
       40 => x"02",
       41 => x"02",
       42 => x"02",
       43 => x"00",
       44 => x"00",
      -- Usb2InterfaceDesc
       45 => x"09",
       46 => x"04",
       47 => x"00",
       48 => x"00",
       49 => x"01",
       50 => x"02",
       51 => x"02",
       52 => x"00",
       53 => x"00",
      -- Usb2CDCFuncHeaderDesc
       54 => x"05",
       55 => x"24",
       56 => x"00",
       57 => x"20",
       58 => x"01",
      -- Usb2CDCFuncCallManagementDesc
       59 => x"05",
       60 => x"24",
       61 => x"01",
       62 => x"00",
       63 => x"01",
      -- Usb2CDCFuncACMDesc
       64 => x"04",
       65 => x"24",
       66 => x"02",
       67 => x"04",
      -- Usb2CDCFuncUnionDesc
       68 => x"05",
       69 => x"24",
       70 => x"06",
       71 => x"00",
       72 => x"01",
      -- Usb2EndpointDesc
       73 => x"07",
       74 => x"05",
       75 => x"82",
       76 => x"03",
       77 => x"08",
       78 => x"00",
       79 => x"ff",
      -- Usb2InterfaceDesc
       80 => x"09",
       81 => x"04",
       82 => x"01",
       83 => x"00",
       84 => x"02",
       85 => x"0a",
       86 => x"00",
       87 => x"00",
       88 => x"00",
      -- Usb2EndpointDesc
       89 => x"07",
       90 => x"05",
       91 => x"81",
       92 => x"02",
       93 => x"40",
       94 => x"00",
       95 => x"00",
      -- Usb2EndpointDesc
       96 => x"07",
       97 => x"05",
       98 => x"01",
       99 => x"02",
      100 => x"40",
      101 => x"00",
      102 => x"00",
      -- Usb2InterfaceAssociationDesc
      103 => x"08",
      104 => x"0b",
      105 => x"02",
      106 => x"02",
      107 => x"01",
      108 => x"22",
      109 => x"30",
      110 => x"00",
      -- Usb2InterfaceDesc
      111 => x"09",
      112 => x"04",
      113 => x"02",
      114 => x"00",
      115 => x"00",
      116 => x"01",
      117 => x"01",
      118 => x"30",
      119 => x"00",
      -- Usb2InterfaceDesc
      120 => x"09",
      121 => x"04",
      122 => x"03",
      123 => x"00",
      124 => x"00",
      125 => x"01",
      126 => x"02",
      127 => x"30",
      128 => x"00",
      -- Usb2InterfaceDesc
      129 => x"09",
      130 => x"04",
      131 => x"03",
      132 => x"01",
      133 => x"02",
      134 => x"01",
      135 => x"02",
      136 => x"30",
      137 => x"00",
      -- Usb2EndpointDesc
      138 => x"07",
      139 => x"05",
      140 => x"03",
      141 => x"05",
      142 => x"c4",
      143 => x"00",
      144 => x"01",
      -- Usb2EndpointDesc
      145 => x"07",
      146 => x"05",
      147 => x"83",
      148 => x"11",
      149 => x"03",
      150 => x"00",
      151 => x"01",
      -- Usb2InterfaceAssociationDesc
      152 => x"08",
      153 => x"0b",
      154 => x"04",
      155 => x"02",
      156 => x"02",
      157 => x"06",
      158 => x"00",
      159 => x"00",
      -- Usb2InterfaceDesc
      160 => x"09",
      161 => x"04",
      162 => x"04",
      163 => x"00",
      164 => x"01",
      165 => x"02",
      166 => x"06",
      167 => x"00",
      168 => x"00",
      -- Usb2CDCFuncHeaderDesc
      169 => x"05",
      170 => x"24",
      171 => x"00",
      172 => x"20",
      173 => x"01",
      -- Usb2CDCFuncUnionDesc
      174 => x"05",
      175 => x"24",
      176 => x"06",
      177 => x"04",
      178 => x"05",
      -- Usb2CDCFuncEthernetDesc
      179 => x"0d",
      180 => x"24",
      181 => x"0f",
      182 => x"02",
      183 => x"00",
      184 => x"00",
      185 => x"00",
      186 => x"00",
      187 => x"ea",
      188 => x"05",
      189 => x"00",
      190 => x"80",
      191 => x"00",
      -- Usb2EndpointDesc
      192 => x"07",
      193 => x"05",
      194 => x"85",
      195 => x"03",
      196 => x"10",
      197 => x"00",
      198 => x"10",
      -- Usb2InterfaceDesc
      199 => x"09",
      200 => x"04",
      201 => x"05",
      202 => x"00",
      203 => x"02",
      204 => x"0a",
      205 => x"00",
      206 => x"00",
      207 => x"00",
      -- Usb2EndpointDesc
      208 => x"07",
      209 => x"05",
      210 => x"84",
      211 => x"02",
      212 => x"40",
      213 => x"00",
      214 => x"00",
      -- Usb2EndpointDesc
      215 => x"07",
      216 => x"05",
      217 => x"04",
      218 => x"02",
      219 => x"40",
      220 => x"00",
      221 => x"00",
      -- Usb2SentinelDesc
      222 => x"02",
      223 => x"ff",
      -- Usb2DeviceDesc
      224 => x"12",
      225 => x"01",
      226 => x"00",
      227 => x"02",
      228 => x"ef",
      229 => x"02",
      230 => x"01",
      231 => x"40",
      232 => x"23",
      233 => x"01",
      234 => x"cd",
      235 => x"ab",
      236 => x"00",
      237 => x"01",
      238 => x"00",
      239 => x"01",
      240 => x"00",
      241 => x"01",
      -- Usb2Device_QualifierDesc
      242 => x"0a",
      243 => x"06",
      244 => x"00",
      245 => x"02",
      246 => x"ef",
      247 => x"02",
      248 => x"01",
      249 => x"40",
      250 => x"01",
      251 => x"00",
      -- Usb2ConfigurationDesc
      252 => x"09",
      253 => x"02",
      254 => x"c2",
      255 => x"00",
      256 => x"06",
      257 => x"01",
      258 => x"00",
      259 => x"a0",
      260 => x"32",
      -- Usb2InterfaceAssociationDesc
      261 => x"08",
      262 => x"0b",
      263 => x"00",
      264 => x"02",
      265 => x"02",
      266 => x"02",
      267 => x"00",
      268 => x"00",
      -- Usb2InterfaceDesc
      269 => x"09",
      270 => x"04",
      271 => x"00",
      272 => x"00",
      273 => x"01",
      274 => x"02",
      275 => x"02",
      276 => x"00",
      277 => x"00",
      -- Usb2CDCFuncHeaderDesc
      278 => x"05",
      279 => x"24",
      280 => x"00",
      281 => x"20",
      282 => x"01",
      -- Usb2CDCFuncCallManagementDesc
      283 => x"05",
      284 => x"24",
      285 => x"01",
      286 => x"00",
      287 => x"01",
      -- Usb2CDCFuncACMDesc
      288 => x"04",
      289 => x"24",
      290 => x"02",
      291 => x"04",
      -- Usb2CDCFuncUnionDesc
      292 => x"05",
      293 => x"24",
      294 => x"06",
      295 => x"00",
      296 => x"01",
      -- Usb2EndpointDesc
      297 => x"07",
      298 => x"05",
      299 => x"82",
      300 => x"03",
      301 => x"08",
      302 => x"00",
      303 => x"10",
      -- Usb2InterfaceDesc
      304 => x"09",
      305 => x"04",
      306 => x"01",
      307 => x"00",
      308 => x"02",
      309 => x"0a",
      310 => x"00",
      311 => x"00",
      312 => x"00",
      -- Usb2EndpointDesc
      313 => x"07",
      314 => x"05",
      315 => x"81",
      316 => x"02",
      317 => x"00",
      318 => x"02",
      319 => x"00",
      -- Usb2EndpointDesc
      320 => x"07",
      321 => x"05",
      322 => x"01",
      323 => x"02",
      324 => x"00",
      325 => x"02",
      326 => x"00",
      -- Usb2InterfaceAssociationDesc
      327 => x"08",
      328 => x"0b",
      329 => x"02",
      330 => x"02",
      331 => x"01",
      332 => x"22",
      333 => x"30",
      334 => x"00",
      -- Usb2InterfaceDesc
      335 => x"09",
      336 => x"04",
      337 => x"02",
      338 => x"00",
      339 => x"00",
      340 => x"01",
      341 => x"01",
      342 => x"30",
      343 => x"00",
      -- Usb2InterfaceDesc
      344 => x"09",
      345 => x"04",
      346 => x"03",
      347 => x"00",
      348 => x"00",
      349 => x"01",
      350 => x"02",
      351 => x"30",
      352 => x"00",
      -- Usb2InterfaceDesc
      353 => x"09",
      354 => x"04",
      355 => x"03",
      356 => x"01",
      357 => x"02",
      358 => x"01",
      359 => x"02",
      360 => x"30",
      361 => x"00",
      -- Usb2EndpointDesc
      362 => x"07",
      363 => x"05",
      364 => x"03",
      365 => x"05",
      366 => x"c4",
      367 => x"00",
      368 => x"04",
      -- Usb2EndpointDesc
      369 => x"07",
      370 => x"05",
      371 => x"83",
      372 => x"11",
      373 => x"04",
      374 => x"00",
      375 => x"04",
      -- Usb2InterfaceAssociationDesc
      376 => x"08",
      377 => x"0b",
      378 => x"04",
      379 => x"02",
      380 => x"02",
      381 => x"06",
      382 => x"00",
      383 => x"00",
      -- Usb2InterfaceDesc
      384 => x"09",
      385 => x"04",
      386 => x"04",
      387 => x"00",
      388 => x"01",
      389 => x"02",
      390 => x"06",
      391 => x"00",
      392 => x"00",
      -- Usb2CDCFuncHeaderDesc
      393 => x"05",
      394 => x"24",
      395 => x"00",
      396 => x"20",
      397 => x"01",
      -- Usb2CDCFuncUnionDesc
      398 => x"05",
      399 => x"24",
      400 => x"06",
      401 => x"04",
      402 => x"05",
      -- Usb2CDCFuncEthernetDesc
      403 => x"0d",
      404 => x"24",
      405 => x"0f",
      406 => x"02",
      407 => x"00",
      408 => x"00",
      409 => x"00",
      410 => x"00",
      411 => x"ea",
      412 => x"05",
      413 => x"00",
      414 => x"80",
      415 => x"00",
      -- Usb2EndpointDesc
      416 => x"07",
      417 => x"05",
      418 => x"85",
      419 => x"03",
      420 => x"10",
      421 => x"00",
      422 => x"08",
      -- Usb2InterfaceDesc
      423 => x"09",
      424 => x"04",
      425 => x"05",
      426 => x"00",
      427 => x"02",
      428 => x"0a",
      429 => x"00",
      430 => x"00",
      431 => x"00",
      -- Usb2EndpointDesc
      432 => x"07",
      433 => x"05",
      434 => x"84",
      435 => x"02",
      436 => x"00",
      437 => x"02",
      438 => x"00",
      -- Usb2EndpointDesc
      439 => x"07",
      440 => x"05",
      441 => x"04",
      442 => x"02",
      443 => x"00",
      444 => x"02",
      445 => x"00",
      -- Usb2Desc
      446 => x"04",
      447 => x"03",
      448 => x"09",
      449 => x"04",
      -- Usb2StringDesc
      450 => x"38",
      451 => x"03",
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
      506 => x"1a",
      507 => x"03",
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
      532 => x"02",
      533 => x"ff"

      );
   begin
      return c;
   end function USB2_APP_DESCRIPTORS_F;
end package body Usb2AppCfgPkg;
