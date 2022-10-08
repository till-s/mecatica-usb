library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library unisim;
use     unisim.vcomponents.all;

use     work.UlpiPkg.all;

entity UlpiIO is
   port (
      rst   :  in    std_logic := '0';
      clk   :  in    std_logic;
      stp   :  out   std_logic := '0';
      dir   :  in    std_logic;
      nxt   :  in    std_logic;
      dat   :  inout std_logic_vector(7 downto 0)
   );
end entity UlpiIO;

architecture Impl of UlpiIO is

   attribute IOB      : string;
   attribute IOBDELAY : string;

   signal dat_i   : std_logic_vector(dat'range);
   signal din_r   : std_logic_vector(dat'range);
   signal dou_r   : std_logic_vector(dat'range);
   signal nxt_r   : std_logic;
   signal dat_o   : std_logic_vector(dat'range) := (others => '0');
   signal dat_t   : std_logic_vector(dat'range);

   signal dirCtl  : std_logic;
   signal dir_r   : std_logic := '1';

   attribute IOB of dir_r : signal is "TRUE";
   attribute IOB of din_r   : signal is "TRUE";
   attribute IOBDELAY of din_r   : signal is "NONE";
   attribute IOB of dou_r   : signal is "TRUE";
   attribute IOB of nxt_r   : signal is "TRUE";

   signal cnt_r   : unsigned(dat'range) := (others => '0');

   signal txData     : std_logic_vector(7 downto 0);
   signal txDataRst  : std_logic;

   signal douRst  : std_logic;
   signal douCen  : std_logic;

begin

   dirCtl <= dir or dir_r;

   dat_o  <= dou_r;

   P_DOU  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
      end if;
   end if;

   P_DIR  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            dir_r   <= '1';
            din_r   <= (others => '0');
            dou_r   <= (others => '0');
            nxt_r   <= '0';
            cnt_r   <= (others => '0');
         else
            dir_r   <= dir;
            din_r   <= dat_i;
            nxt_r   <= nxt;
            cnt_r   <= cnt_r + 1;
            dou_r   <= std_logic_vector(cnt_r) xor din_r;
         end if;
      end if;
   end process P_DIR;

   G_DATB :  for i in dat'range generate
      U_BUF : IOBUF port map ( IO => dat(i), I => dat_o(i), T => dirCtl, O => dat_i(i) );
   end generate G_DATB;

end architecture Impl;
