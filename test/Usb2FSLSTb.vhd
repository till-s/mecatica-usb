-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;

entity Usb2FSLSTb is
end entity Usb2FSLSTb;

architecture sim of Usb2FSLSTb is
   constant BITS_C : std_logic_vector := 
      x"01" & x"fb" & x"4c" & x"53" & x"54" & x"d1" & x"8a" & x"09" & x"b5" & x"09" & x"24" & x"0d" & x"c5" & x"85" & x"10" & x"e9" & x"36" & x"0f" & x"e3" & x"1c" & x"4d" & x"b9" & x"ff" & x"e4" & x"f3" & x"3c" & x"c8" & x"a5" & x"be" & x"c8" & x"da" & x"cd" & 
      x"3a" & x"9f" & x"84" & x"25" & x"ca" & x"68" & x"b1" & x"e3" & x"24" & x"33" & x"cc" & x"a7" & x"31" & x"39" & x"ea" & x"20" & x"42" & x"52" & x"25" & x"95" & x"7a" & x"73" & x"b4" & x"fb" & x"d6" & x"25" & x"cf" & x"2b" & x"a9" & x"5d" & x"20" & x"d1" & 
      x"e1" & x"8d" & x"8f" & x"58" & x"37" & x"48" & x"e9" & x"7a" & x"db" & x"37" & x"32" & x"d1" & x"57" & x"6b" & x"7c" & x"f1" & x"1b" & x"60" & x"c3" & x"39" & x"00" & x"6f" & x"dc" & x"7a" & x"12" & x"09" & x"bd" & x"3b" & x"17" & x"6c" & x"3f" & x"31" & 
      x"0b" & x"3a" & x"b8" & x"fe" & x"90" & x"54" & x"bc" & x"ba" & x"04" & x"da" & x"37" & x"4b" & x"e7" & x"3f" & x"46" & x"22" & x"1b" & x"31" & x"ab" & x"73" & x"06" & x"dd" & x"fc" & x"83" & x"a2" & x"c3" & x"b1" & x"9d" & x"14" & x"7a" & x"dd" & x"68" & 
      x"f4" & x"c9" & x"a6" & x"05" & x"3f" & x"3a" & x"6e" & x"c0" & x"4c" & x"bd" & x"c4" & x"5e" & x"7f" & x"c2" & x"2f" & x"03" & x"a4" & x"f6" & x"5b" & x"6f" & x"2f" & x"5d" & x"74" & x"02" & x"96" & x"b2" & x"35" & x"ef" & x"e2" & x"7e" & x"37" & x"e1" & 
      x"23" & x"ae" & x"e4" & x"ac" & x"fa" & x"20" & x"33" & x"12" & x"e1" & x"64" & x"5d" & x"aa" & x"a1" & x"cf" & x"46" & x"72" & x"7f" & x"4b" & x"ae" & x"38" & x"0c" & x"10" & x"d1" & x"76" & x"df" & x"27" & x"8d" & x"29" & x"fb" & x"1d" & x"08" & x"ca" & 
      x"ed" & x"c6" & x"20" & x"b2" & x"b5" & x"13" & x"3f" & x"86" & x"50" & x"bd" & x"d3" & x"d8" & x"1d" & x"2c" & x"f3" & x"3c" & x"8e" & x"df" & x"f5" & x"ea" & x"42" & x"68" & x"b7" & x"26" & x"2d" & x"01" & x"f2" & x"6c" & x"d9" & x"8c" & x"db" & x"2d" & 
      x"f2" & x"30" & x"f4" & x"16" & x"1f" & x"67" & x"e5" & x"08" & x"1e" & x"24" & x"81" & x"eb" & x"3d" & x"19" & x"1b" & x"37" & x"b8" & x"e3" & x"bd" & x"8c" & x"a9" & x"56" & x"6d" & x"ce" & x"01" & x"00" & x"6c" & x"16" & x"36" & x"13" & x"44" & x"e1" & 
      x"1e" & x"09" & x"71" & x"39" & x"43" & x"1b" & x"c5" & x"93" & x"23" & x"d0" & x"9c" & x"1c" & x"98" & x"89" & x"6b" & x"53" & x"d2" & x"85" & x"c6" & x"67" & x"62" & x"64" & x"a6" & x"2d" & x"91" & x"8e" & x"2f" & x"0f" & x"b5" & x"b1" & x"13" & x"08" & 
      x"e8" & x"e7" & x"05" & x"a6" & x"94" & x"3a" & x"a3" & x"d1" & x"46" & x"11" & x"6b" & x"47" & x"2a" & x"43" & x"ca" & x"bb" & x"cf" & x"ce" & x"ee" & x"da" & x"47" & x"9d" & x"89" & x"8f" & x"96" & x"33" & x"98" & x"76" & x"b1" & x"61" & x"ea" & x"60" & 
      x"92" & x"ea" & x"52" & x"ac" & x"71" & x"4b" & x"1e" & x"69" & x"49" & x"d8" & x"22" & x"1f" & x"7b" & x"e7" & x"42" & x"64" & x"6f" & x"c9" & x"1b" & x"1e" & x"33" & x"e4" & x"83" & x"84" & x"46" & x"0a" & x"57" & x"c9" & x"ed" & x"c1" & x"22" & x"65" & 
      x"0d" & x"56" & x"f2" & x"e2" & x"e0" & x"44" & x"ff" & x"12" & x"65" & x"1b" & x"88" & x"65" & x"e3" & x"7b" & x"89" & x"7b" & x"1e" & x"8c" & x"49" & x"95" & x"a9" & x"6d" & x"82" & x"dc" & x"14" & x"05" & x"a4" & x"d5" & x"b6" & x"72" & x"02" & x"79" & 
      x"6b" & x"d9" & x"2d" & x"6a" & x"d8" & x"2f" & x"15" & x"91" & x"4b" & x"68" & x"83" & x"14" & x"63" & x"db" & x"c0" & x"e9" & x"40" & x"62" & x"be" & x"01" & x"a9" & x"46" & x"9f" & x"d3" & x"37" & x"a1" & x"4b" & x"1e" & x"f5" & x"9c" & x"8c" & x"8d" & 
      x"1c" & x"8a" & x"d3" & x"e0" & x"9b" & x"bc" & x"55" & x"68" & x"ad" & x"ad" & x"f8" & x"40" & x"91" & x"10" & x"07" & x"8e" & x"ba" & x"00" & x"0b" & x"ba" & x"24" & x"12" & x"3f" & x"1b" & x"9b" & x"01" & x"7a" & x"c6" & x"1a" & x"0b" & x"41" & x"47" & 
      x"5a" & x"30" & x"1f" & x"9b" & x"72" & x"b2" & x"e4" & x"9b" & x"e8" & x"7e" & x"66" & x"b5" & x"1b" & x"20" & x"17" & x"ba" & x"b5" & x"00" & x"f6" & x"3b" & x"66" & x"44" & x"99" & x"9b" & x"90" & x"c7" & x"66" & x"b3" & x"ca" & x"75" & x"6d" & x"dd" & 
      x"a5" & x"e2" & x"f6" & x"9a" & x"45" & x"bd" & x"7a" & x"f4" & x"32" & x"9d" & x"93" & x"0b" & x"0b" & x"fc" & x"4c" & x"a1" & x"0b" & x"36" & x"cd" & x"81" & x"f5" & x"f9" & x"49" & x"5b" & x"3f" & x"8a" & x"ec" & x"16" & x"d1" & x"16" & x"1b" & x"60" & 
      x"3d" & x"83" & x"27" & x"16" & x"98" & x"86" & x"85" & x"52" & x"f5" & x"ed" & x"29" & x"52" & x"63" & x"5a" & x"ea" & x"db" & x"70" & x"f2" & x"e4" & x"eb" & x"ea" & x"e3" & x"d5" & x"fe" & x"ca" & x"85" & x"46" & x"86" & x"54" & x"61" & x"bb" & x"9f" & 
      x"e6" & x"6a" & x"b9" & x"fe" & x"33" & x"95" & x"52" & x"48" & x"14" & x"7c" & x"c1" & x"71" & x"21" & x"86" & x"58" & x"1e" & x"9c" & x"36" & x"27" & x"1a" & x"5b" & x"bb" & x"1b" & x"73" & x"6d" & x"9c" & x"e7" & x"0d" & x"d3" & x"68" & x"e5" & x"f2" & 
      x"ac" & x"06" & x"76" & x"d0" & x"4d" & x"19" & x"e0" & x"ca" & x"b7" & x"4d" & x"77" & x"2e" & x"29" & x"b1" & x"a9" & x"48" & x"80" & x"db" & x"c2" & x"4b" & x"29" & x"50" & x"32" & x"a9" & x"24" & x"ea" & x"1b" & x"99" & x"2f" & x"a9" & x"32" & x"ec" & 
      x"32" & x"6a" & x"c4" & x"dd" & x"70" & x"28" & x"bd" & x"89" & x"51" & x"80" & x"da" & x"31" & x"b7" & x"94" & x"5d" & x"83" & x"ba" & x"1f" & x"dd" & x"9e" & x"35" & x"26" & x"44" & x"c8" & x"5a" & x"c1" & x"14" & x"3c" & x"12" & x"87" & x"0b" & x"45" & 
      x"90" & x"af" & x"6e" & x"54" & x"40" & x"41" & x"b7" & x"5c" & x"f0" & x"0f" & x"5a" & x"37" & x"ad" & x"6e" & x"31" & x"7c" & x"b9" & x"c8" & x"9c" & x"00" & x"4b" & x"79" & x"24" & x"e1" & x"84" & x"11" & x"b2" & x"1e" & x"6b" & x"38" & x"7a" & x"dd" & 
      x"f7" & x"35" & x"0c" & x"c5" & x"d9" & x"56" & x"cc" & x"62" & x"bb" & x"0a" & x"e5" & x"8b" & x"59" & x"72" & x"5e" & x"8e" & x"96" & x"09" & x"a2" & x"e9" & x"d5" & x"1c" & x"9f" & x"b7" & x"64" & x"bb" & x"64" & x"48" & x"67" & x"e5" & x"f2" & x"ea" & 
      x"b0" & x"c9" & x"93" & x"e6" & x"4d" & x"ff" & x"1f" & x"12" & x"4d" & x"59" & x"fa" & x"c7" & x"51" & x"1d" & x"bb" & x"69" & x"f8" & x"ab" & x"f6" & x"28" & x"1f" & x"0e" & x"96" & x"7e" & x"71" & x"da" & x"e9" & x"fc" & x"30" & x"cd" & x"fb" & x"8b" & 
      x"c2" & x"75" & x"ea" & x"89" & x"43" & x"94" & x"28" & x"f8" & x"b1" & x"ce" & x"b5" & x"80" & x"5d" & x"2b" & x"90" & x"5e" & x"2c" & x"13" & x"91" & x"d7" & x"03" & x"6f" & x"8e" & x"27" & x"cc" & x"e1" & x"f2" & x"74" & x"d5" & x"14" & x"7d" & x"e1" & 
      x"67" & x"f5" & x"50" & x"bd" & x"80" & x"1c" & x"c5" & x"2d" & x"94" & x"7b" & x"08" & x"d5" & x"51" & x"5d" & x"15" & x"7f" & x"47" & x"96" & x"ac" & x"94" & x"44" & x"eb" & x"04" & x"7d" & x"52" & x"be" & x"b6" & x"10" & x"92" & x"11" & x"25" & x"72" & 
      x"50" & x"5c" & x"b1" & x"67" & x"f6" & x"76" & x"24" & x"8a" & x"35" & x"8f" & x"ca" & x"7c" & x"6c" & x"2c" & x"04" & x"09" & x"23" & x"fa" & x"1a" & x"bf" & x"1e" & x"d1" & x"9e" & x"bd" & x"69" & x"9a" & x"80" & x"b4" & x"17" & x"c4" & x"bc" & x"b6" & 
      x"dc" & x"b2" & x"0d" & x"b5" & x"fa" & x"d3" & x"f3" & x"db" & x"aa" & x"5d" & x"fd" & x"d4" & x"6a" & x"78" & x"54" & x"f4" & x"2b" & x"68" & x"3c" & x"0d" & x"60" & x"f5" & x"2e" & x"4c" & x"cd" & x"90" & x"65" & x"6e" & x"2f" & x"04" & x"19" & x"62" & 
      x"10" & x"cd" & x"11" & x"c0" & x"38" & x"f5" & x"2a" & x"7f" & x"68" & x"f3" & x"16" & x"1e" & x"d1" & x"65" & x"38" & x"83" & x"a8" & x"1b" & x"07" & x"a1" & x"4c" & x"22" & x"67" & x"34" & x"4c" & x"53" & x"93" & x"97" & x"a5" & x"67" & x"0f" & x"a0" & 
      x"fd" & x"13" & x"7d" & x"1f" & x"62" & x"62" & x"cd" & x"8c" & x"07" & x"4b" & x"7e" & x"ce" & x"93" & x"f7" & x"fe" & x"44" & x"69" & x"8a" & x"f4" & x"48" & x"47" & x"55" & x"25" & x"eb" & x"98" & x"07" & x"b2" & x"b8" & x"22" & x"9e" & x"eb" & x"68" & 
      x"d7" & x"6b" & x"e7" & x"64" & x"a2" & x"ab" & x"f4" & x"b0" & x"5e" & x"ba" & x"07" & x"f5" & x"3d" & x"9d" & x"03" & x"e7" & x"d2" & x"36" & x"36" & x"a7" & x"91" & x"9c" & x"5d" & x"18" & x"ef" & x"ef" & x"43" & x"5f" & x"fa" & x"59" & x"bf" & x"4a" & 
      x"4c" & x"cd" & x"fc" & x"03" & x"50" & x"f3" & x"ad" & x"cb" & x"17" & x"52" & x"e7" & x"d3" & x"dc" & x"ed" & x"20" & x"09" & x"cf" & x"2e" & x"ba" & x"2f" & x"59" & x"a2" & x"f6" & x"2d" & x"a9" & x"75" & x"af" & x"75" & x"f9" & x"4c" & x"db" & x"b7" & 
      x"40" & x"af" & x"d1" & x"9e" & x"30" & x"9d" & x"9a" & x"7a" & x"e1" & x"42" & x"77" & x"5b" & x"b7" & x"2c" & x"01" & x"6f" & x"a4" & x"11" & x"b7" & x"de" & x"62" & x"22" & x"3e" & x"8b" & x"23" & x"58" & x"5d" & x"6c" & x"68" & x"b8" & x"1c" & x"df" & 
      x"e7" & x"41" & x"71" & x"d3" & x"76" & x"57" & x"10" & x"b4" & x"02" & x"43" & x"18" & x"d6" & x"62" & x"67" & x"05" & x"c4" & x"f5" & x"41" & x"76" & x"96" & x"47" & x"31" & x"0f" & x"ce" & x"3f" & x"d0" & x"bf" & x"c3" & x"0f" & x"a6" & x"60" & x"4e" & 
      x"59" & x"26" & x"6e" & x"ee" & x"1b" & x"35" & x"98" & x"90" & x"5b" & x"1a" & x"f7" & x"b2" & x"e7" & x"bf" & x"ba" & x"55" & x"39" & x"57" & x"53" & x"dc" & x"ab" & x"65" & x"7c" & x"f6" & x"11" & x"5e" & x"e4" & x"fd" & x"28" & x"53" & x"3c" & x"2e" & 
      x"dc" & x"5e" & x"60" & x"68" & x"50" & x"60" & x"e3" & x"2d" & x"8a" & x"63" & x"4a" & x"33" & x"d6" & x"bb" & x"de" & x"61" & x"51" & x"b6" & x"f4" & x"45" & x"c5" & x"c4" & x"01" & x"b4" & x"4b" & x"ba" & x"71" & x"37" & x"46" & x"83" & x"69" & x"c7" & 
      x"3c" & x"2c" & x"a1" & x"f0" & x"ad" & x"75" & x"74" & x"28" & x"1f" & x"42" & x"7a" & x"89" & x"2d" & x"38" & x"1d" & x"60" & x"46" & x"7d" & x"b2" & x"c2" & x"e5" & x"37" & x"c6" & x"dd" & x"d1" & x"9c" & x"73" & x"08" & x"81" & x"8d" & x"09" & x"4c" & 
      x"4a" & x"fd" & x"c7" & x"9a" & x"d3" & x"3a" & x"41" & x"69" & x"d7" & x"75" & x"61" & x"78" & x"67" & x"03" & x"0a" & x"71" & x"90" & x"89" & x"31" & x"ae" & x"cb" & x"17" & x"71" & x"87" & x"52" & x"f6" & x"ad" & x"6f" & x"e7" & x"be" & x"68" & x"11" & 
      x"d3" & x"dc" & x"44" & x"fa" & x"8a" & x"6c" & x"c1" & x"2e" & x"45" & x"f5" & x"2b" & x"06" & x"f0" & x"cc" & x"42" & x"1c" & x"9d" & x"af" & x"19" & x"1b" & x"b0" & x"da" & x"0d" & x"f4" & x"99" & x"5e" & x"35" & x"0e" & x"8e" & x"b7" & x"9c" & x"5a" & 
      x"f6" & x"44" & x"48" & x"74" & x"a8" & x"d5" & x"cd" & x"d8" & x"22" & x"77" & x"a9" & x"ac" & x"5c" & x"9e" & x"c0" & x"91" & x"63" & x"32" & x"3a" & x"67" & x"1c" & x"3f" & x"8b" & x"99" & x"74" & x"bd" & x"dd" & x"5c" & x"10" & x"19" & x"c7" & x"8a" & 
      x"e1" & x"c0" & x"3e" & x"01" & x"0e" & x"37" & x"aa" & x"b0" & x"cd" & x"8a" & x"77" & x"bd" & x"29" & x"2b" & x"71" & x"00" & x"d7" & x"13" & x"09" & x"55" & x"d8" & x"cf" & x"64" & x"dc" & x"08" & x"ab" & x"1b" & x"f5" & x"e9" & x"f1" & x"2c" & x"b5" & 
      x"2b" & x"d8" & x"78" & x"a8" & x"64" & x"b3" & x"05" & x"3e" & x"72" & x"87" & x"54" & x"7e" & x"ce" & x"4e" & x"c3" & x"38" & x"bd" & x"66" & x"86" & x"91" & x"30" & x"89" & x"fe" & x"e2" & x"d8" & x"a6" & x"c3" & x"b5" & x"92" & x"e7" & x"c7" & x"3f" & 
      x"c4" & x"29" & x"e7" & x"e4" & x"79" & x"25" & x"ba" & x"86" & x"47" & x"c6" & x"11" & x"b1" & x"14" & x"79" & x"ab" & x"db" & x"b9" & x"d8" & x"64" & x"cf" & x"98" & x"f2" & x"9b" & x"bd" & x"bf" & x"65" & x"e5" & x"b0" & x"37" & x"b2" & x"03" & x"5d" & 
      x"97" & x"43" & x"0d" & x"f5" & x"99" & x"b3" & x"c2" & x"13" & x"7c" & x"f9" & x"12" & x"6b" & x"7d" & x"25" & x"55" & x"d0" & x"d3" & x"fb" & x"76" & x"80" & x"ec" & x"30" & x"ab" & x"d9" & x"1f" & x"c3" & x"a2" & x"a4" & x"29" & x"89" & x"d8" & x"b4" & 
      x"98" & x"e3" & x"7d" & x"df" & x"2b" & x"41" & x"ae" & x"50" & x"bd" & x"a0" & x"8a" & x"65" & x"6d" & x"ee" & x"a1" & x"e4" & x"10" & x"9e" & x"f9" & x"58" & x"4a" & x"ff" & x"5e" & x"1f" & x"4f" & x"0c" & x"f1" & x"9a" & x"14" & x"72" & x"a6" & x"67" & 
      x"5a" & x"10" & x"33" & x"de" & x"15" & x"bc" & x"a0" & x"10" & x"54" & x"61" & x"1c" & x"a6" & x"67" & x"3c" & x"fc" & x"46" & x"60" & x"f4" & x"87" & x"af" & x"bf" & x"ed" & x"47" & x"2d" & x"e5" & x"bc" & x"86" & x"83" & x"f4" & x"47" & x"8b" & x"9f" & 
      x"b1" & x"5c" & x"46" & x"f3" & x"19" & x"a7" & x"5d" & x"be" & x"70" & x"60" & x"34" & x"51" & x"8e" & x"04" & x"48" & x"eb" & x"6f" & x"ea" & x"04" & x"1b" & x"78" & x"a5" & x"61" & x"d2" & x"a9" & x"9d" & x"61" & x"aa" & x"e6" & x"c6" & x"cb" & x"e5" & 
      x"8c" & x"40" & x"d5" & x"79" & x"6b" & x"80" & x"53" & x"5e" & x"9c" & x"4a" & x"68" & x"2a" & x"da" & x"c5" & x"0f" & x"f3" & x"62" & x"f5" & x"22" & x"fa" & x"7a" & x"1e" & x"b5" & x"36" & x"93" & x"dc" & x"55" & x"7a" & x"63" & x"7a" & x"d9" & x"13" & 
      x"2d" & x"ed" & x"b0" & x"09" & x"a7" & x"b3" & x"97" & x"6b" & x"10" & x"f5" & x"d0" & x"44" & x"d7" & x"93" & x"b7" & x"d4" & x"ba" & x"9c" & x"5f" & x"55" & x"65" & x"cc" & x"6f" & x"0b" & x"11" & x"0e" & x"e1" & x"28" & x"66" & x"a2" & x"1e" & x"77";

   signal clk      : std_logic := '0';
   signal rxTstJ   : std_logic := '1';
   signal rxTstSE0 : std_logic := '0';
   signal rxCmdVld : std_logic;
   signal dir      : std_logic;
   signal dirLst   : std_logic := '0';
   signal j        : std_logic;
   signal se0      : std_logic;
   signal stuff    : natural   := 0;
   signal run      : boolean   := true;
   signal active   : std_logic;
   signal valid    : std_logic;
   signal dout     : std_logic_vector(7 downto 0);
   signal txData   : std_logic_vector(7 downto 0) := (others => '0');
   signal txStp    : std_logic := '0';
   signal txNxt    : std_logic;
   signal txJ      : std_logic;
   signal txSE0    : std_logic;
   signal txAct    : std_logic;
   signal monDon   : boolean   := false;

   constant PERF_C : time      := 19.95 ns;
   constant PERS_C : time      := 20.05 ns;
   constant NPHS_C : natural   := 7;

   signal clkPer   : time      := PERS_C;

   signal rxTstDon : boolean   := false;

   procedure TICK is
   begin
      wait until rising_edge( clk );
   end procedure TICK;

begin

   P_FEED : process is
      procedure FTICK is
      begin
         wait for 20 ns;
      end procedure FTICK;

      procedure SEND_EOP is
      begin
         rxTstSE0 <= '1';
         rxTstJ   <= '1';
         stuff    <= 0;
         FTICK;
         FTICK;
         rxTstSE0 <= '0';
         FTICK;
      end procedure SEND_EOP;

      procedure SEND_BIT(constant b: in std_logic) is
      begin
         if ( stuff = 5 ) then
            rxTstJ <= not rxTstJ;
            stuff  <= 0;
            FTICK;
         end if;
         if ( b = '0' ) then
            rxTstJ <= not rxTstJ;
            stuff  <= 0;
         else
            stuff <= stuff + 1;
         end if;
         FTICK;
      end procedure SEND_BIT;

      procedure SEND_BYTE(constant b: in std_logic_vector(7 downto 0)) is
      begin
         for i in b'right to b'left loop
            SEND_BIT( b(i) );
         end loop;
      end procedure SEND_BYTE;

      constant SYNC_C : std_logic_vector := x"80";

   begin
      FTICK;
      for phs in 1 to 2 loop
         report "Testing clock period " & time'image(clkPer);
         for i in BITS_C'left to BITS_C'right loop
            SEND_BIT( BITS_C(i) );
         end loop;
         SEND_EOP;
         clkPer <= PERF_C;
         FTICK;
      end loop;

      -- send with a dribble bit
      SEND_BYTE( SYNC_C );
      SEND_BYTE( x"f0"  );
      SEND_BIT( '0' );
      SEND_EOP;
      FTICK;
      FTICK;
      -- send with a dribble bit
      SEND_BYTE( SYNC_C );
      SEND_BYTE( x"f0"  );
      SEND_BIT( '1' );
      SEND_EOP;
      FTICK;
      FTICK;

      -- send with a un-stuffed dribble bit
      SEND_BYTE( SYNC_C );
      for i in 1 to 3 loop
         SEND_BIT( '0' );
      end loop;
      for i in 1 to 6 loop
         stuff <= 0;
         wait for 0 ns;
         SEND_BIT( '1' );
      end loop;
      SEND_EOP;
      FTICK;
      FTICK;

      wait for 20 ns; 

      rxTstDon <= true;

      wait;
   end process P_FEED;

   P_CLK : process is
   begin
      if ( not run ) then wait; end if;
      wait for clkPer / 2.0 / 4; clk <= not clk;
   end process P_CLK;

   P_ACT : process ( clk ) is
      variable a   : std_logic := '0';
      variable phs : natural := 0;
   begin
      if ( rising_edge( clk ) ) then
         if ( ( not active and a ) = '1' ) then
            phs := phs + 1;
         end if;
         a := active;
         if ( monDon ) then
            assert phs = NPHS_C report "mismatch in RX phases" severity failure;
            run <= false;
            report "Test PASSED";
         end if;
      end if;
   end process P_ACT;

   dir <= rxCmdVld or active;

   P_MON : process ( clk ) is
      variable idx : integer := 1;
      variable cmp : std_logic_vector(0 to 7);
      variable phs : natural := 0;
      variable trn : boolean;
      variable tst : boolean := false;
   begin
      if ( rising_edge( clk ) ) then
         dirLst <= dir;
         trn    := (dir /= dirLst);
         if ( phs < 2 ) then
            for i in 0 to 7 loop
               cmp(i) := dout(i);
            end loop;
            if ( valid = '1' and not trn ) then
               assert BITS_C(idx*8 to idx*8 + 7) = cmp
                  report "Mismatch at index " & integer'image(idx) &
                         " Expected: " & integer'image( to_integer(unsigned(BITS_C(idx*8 to idx*8 + 7 ))) ) &
                         " Got (rev):" & integer'image( to_integer(unsigned(cmp)) )
                  severity failure;
               idx := idx + 1;
               if ( idx*8 >= BITS_C'length ) then
                  idx := 1;
                  phs := phs + 1;
               end if;
            end if;
         elsif ( phs = 2 or phs = 3 ) then
            if ( valid = '1' and not trn ) then
               assert dout = x"f0" report "Dribble test mismatch" severity failure;
               report "Testing dribble bit passed";
               phs := phs + 1;
            end if;
         elsif ( phs = 4 ) then
            if ( valid = '1' and not trn ) then
               assert dout = x"f8" report "Dribble test (unstuffed) mismatch" severity failure;
               report "Testing unstuffed dribble bit passed";
               phs := phs + 1;
               idx := -1;
            end if;
         elsif ( phs = 5 ) then
            if ( valid = '1' and not trn ) then
               if ( idx < 0 ) then
                  cmp := x"5A";
               else
                  cmp := BITS_C(idx*8 to idx*8 + 7);
               end if;
               assert  cmp = dout
                  report "TX test mismatch @idx " & integer'image(idx)
                  severity failure;
               idx := idx + 1;
            end if;
            if ( idx*8 >= BITS_C'length ) then
               phs := phs + 1;
               idx := -1;
               tst := false;
            end if;
         elsif ( phs = 6 ) then
            if ( valid = '1' and not trn ) then
               if ( idx < 0 ) then
                  cmp := x"5A";
               else
                  cmp := x"00";
               end if;
               assert  cmp = dout
                  report "TX test mismatch @idx " & integer'image(idx)
                  severity failure;
               idx := idx + 1;
            end if;
            if ( ( (active and not valid) or rxCmdVld ) = '1' ) then
               if ( ( dout(ULPI_RXCMD_RX_ERROR_BIT_C) = '1' ) and ( idx >= 0 ) ) then
                  tst := true;
               end if;
               if ( ( dout(ULPI_RXCMD_RX_ACTIVE_BIT_C) = '0' ) and ( idx > 0 ) ) then
                  assert tst report "bit stuff error missed" severity failure;
                  phs := phs + 1;
                  idx := -1;
               end if;
            end if;
         elsif ( phs < NPHS_C ) then
            assert false report "Internal error -- unmonitored test phase" severity failure;
         else
            monDon <= true;
         end if;
      end if;
   end process P_MON;

   P_FEED_TX : process is
      procedure SEND(constant x : std_logic_vector; constant sta : std_logic := '0') is
         variable idx : natural := 0;
      begin
         TICK;
         txData <= x"4A";
         L_TX : while (true) loop
            TICK;
            while ( txNxt = '0' ) loop
               TICK;
            end loop;
            if ( idx < x'length/8 ) then
               txData <= x(8*idx to 8*idx + 7);
               idx    := idx + 1;
            else
               txData <= (others => sta);
               txStp  <= '1';
               exit L_TX;
            end if;
         end loop;
         TICK;
         txStp <= '0';
         TICK;
      end procedure SEND;
   begin
      wait until rxTstDon;
      report "Testing transmitter";
      SEND( BITS_C );
      -- send with error condition
      SEND( x"00", sta => '1' );
      wait;

   end process P_FEED_TX;

   j   <= rxTstJ   and txJ;
   se0 <= rxTstSE0 or  txSE0;

   U_DUT_RX : entity work.Usb2FSLSRx
      port map (
         clk          => clk,
         rst          => '0',
         j            => j,
         se0          => se0,
         valid        => valid,
         active       => active,
         data         => dout,
         rxCmdVld     => rxCmdVld,
         txActive     => '0' -- DONT blank reception for this test
      );

   U_DUT_TX : entity work.Usb2FSLSTx
      port map (
         clk          => clk,
         rst          => '0',
         data         => txData,
         stp          => txStp,
         nxt          => txNxt,
         j            => txJ,
         se0          => txSE0,
         active       => txAct
      );
 
end architecture sim;
