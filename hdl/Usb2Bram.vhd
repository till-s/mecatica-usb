library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity Usb2Bram is
   generic (
      -- 9-bits into parity seems to work when using 
      -- the full depth; when using less then the 9-th
      -- bit goes into spare data...
      DATA_WIDTH_G   : natural       :=  9;
      ADDR_WIDTH_G   : natural       := 11;
      EN_REGA_G      : boolean       := false;
      EN_REGB_G      : boolean       := false
   );
   port (
      clk            : in  std_logic := '0';
      rst            : in  std_logic := '0';
      ena            : in  std_logic := '1';
      wea            : in  std_logic := '0';
      addra          : in  unsigned(ADDR_WIDTH_G - 1 downto 0)         := (others => '0');
      rdata          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      wdata          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0) := (others => '0');
      enb            : in  std_logic := '1';
      web            : in  std_logic := '0';
      addrb          : in  unsigned(ADDR_WIDTH_G - 1 downto 0)         := (others => '0');
      rdatb          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      wdatb          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0) := (others => '0')
   );
end entity Usb2Bram;

architecture Impl of Usb2Bram is
   subtype DataType is std_logic_vector(DATA_WIDTH_G - 1 downto 0);

   type    MemArray is array (natural range 0 to 2**ADDR_WIDTH_G - 1) of DataType;

   shared variable memory   : MemArray;

   signal  rdata_r  : std_logic_vector(wdata'range) := (others => '0');
   signal  rdatb_r  : std_logic_vector(wdata'range) := (others => '0');

   signal  rdata_o  : std_logic_vector(wdata'range) := (others => '0');
   signal  rdatb_o  : std_logic_vector(wdata'range) := (others => '0');
begin

   P_SEQA : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ena = '1' ) then
            rdata_o <= memory( to_integer( addra ) );
            rdata_r <= rdata_o;
            if ( wea = '1' ) then
               memory( to_integer( addra ) ) := wdata; 
            end if;
         end if;
      end if;
   end process P_SEQA;

   P_SEQB : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( enb = '1' ) then
            rdatb_o <= memory( to_integer( addrb ) );
            rdatb_r <= rdatb_o;
            if ( web = '1' ) then
               memory( to_integer( addrb ) ) := wdatb; 
            end if;
         end if;
      end if;
   end process P_SEQB;

   G_REGA    : if (     EN_REGA_G ) generate rdata <= rdata_r; end generate;
   G_NO_REGA : if ( not EN_REGA_G ) generate rdata <= rdata_o; end generate;
   G_REGB    : if (     EN_REGB_G ) generate rdatb <= rdatb_r; end generate;
   G_NO_REGB : if ( not EN_REGB_G ) generate rdatb <= rdatb_o; end generate;

end architecture Impl;
