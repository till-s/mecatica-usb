-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

-- RAM ram module (written so that vivado may infer block ram)

entity Usb2Bram is
   generic (
      -- 9-bits into parity seems to work when using 
      -- the full depth; when using less then the 9-th
      -- bit goes into spare data...
      DATA_WIDTH_G   : natural          :=  9;
      ADDR_WIDTH_G   : natural          := 11;
      EN_REGA_G      : boolean          := false;
      EN_REGB_G      : boolean          := false;
      INIT_G         : std_logic_vector := "";
      INIT_DFLT_G    : std_logic        := '0'
   );
   port (
      clka           : in  std_logic := '0';
      ena            : in  std_logic := '1'; -- readout CE
      cea            : in  std_logic := '1'; -- output register CE
      wea            : in  std_logic := '0'; -- write-enable
      addra          : in  unsigned(ADDR_WIDTH_G - 1 downto 0)         := (others => '0');
      rdata          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      wdata          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0) := (others => '0');

      clkb           : in  std_logic := '0';
      enb            : in  std_logic := '1';
      ceb            : in  std_logic := '1';
      web            : in  std_logic := '0';
      addrb          : in  unsigned(ADDR_WIDTH_G - 1 downto 0)         := (others => '0');
      rdatb          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      wdatb          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0) := (others => '0')
   );
end entity Usb2Bram;

architecture Impl of Usb2Bram is

   subtype DataType is std_logic_vector(DATA_WIDTH_G - 1 downto 0);

   type    MemArray is array (natural range 0 to 2**ADDR_WIDTH_G - 1) of DataType;

   function memInit return MemArray is
      variable v : MemArray := (others => (others => INIT_DFLT_G));
   begin
      for i in INIT_G'range loop
         v( i / DATA_WIDTH_G ) ( i mod DATA_WIDTH_G ) := INIT_G(i);
      end loop;
      return v;
   end function memInit;

   -- note for the record: an attempt to force vivado 2022.1 to use block ram
   -- (RAM_STYLE "BLOCK", ROM_STYLE "BLOCK") for an instantiation where
   -- only one read port of this entity was used (ROM) the attribute was
   -- ignored and the rom implemented in fabric no matter what I tried!
   shared variable memory   : MemArray := memInit;

   signal  rdata_r  : std_logic_vector(wdata'range) := (others => '0');
   signal  rdatb_r  : std_logic_vector(wdata'range) := (others => '0');

   signal  rdata_o  : std_logic_vector(wdata'range) := (others => '0');
   signal  rdatb_o  : std_logic_vector(wdata'range) := (others => '0');
begin

   P_SEQA : process ( clka ) is
   begin
      if ( rising_edge( clka ) ) then
         if ( ena = '1' ) then
            rdata_o <= memory( to_integer( addra ) );
            if ( wea = '1' ) then
               memory( to_integer( addra ) ) := wdata; 
            end if;
         end if;
         if ( cea = '1' ) then
            rdata_r <= rdata_o;
         end if;
      end if;
   end process P_SEQA;

   P_SEQB : process ( clkb ) is
   begin
      if ( rising_edge( clkb ) ) then
         if ( enb = '1' ) then
            rdatb_o <= memory( to_integer( addrb ) );
            if ( web = '1' ) then
               memory( to_integer( addrb ) ) := wdatb; 
            end if;
         end if;
         if ( ceb = '1' ) then
            rdatb_r <= rdatb_o;
         end if;
      end if;
   end process P_SEQB;

   G_REGA    : if (     EN_REGA_G ) generate rdata <= rdata_r; end generate;
   G_NO_REGA : if ( not EN_REGA_G ) generate rdata <= rdata_o; end generate;
   G_REGB    : if (     EN_REGB_G ) generate rdatb <= rdatb_r; end generate;
   G_NO_REGB : if ( not EN_REGB_G ) generate rdatb <= rdatb_o; end generate;

end architecture Impl;
