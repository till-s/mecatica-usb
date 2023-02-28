-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- CDC NCM Endpoint with a FIFO interface. It also demonstrates
-- the implementation of a control interface via device requests (EP0).
-- Asynchronous clock domains are supported.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     std.textio.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

entity Usb2EpCDCNCMTb is
end entity Usb2EpCDCNCMTb;

architecture sim of Usb2EpCDCNCMTb is

   constant LD_DEPTH_C      : natural   := 7;

   subtype  Slv9            is std_logic_vector(8 downto 0);
   type     Slv9Array       is array (natural range <>) of Slv9;

   impure function flen(constant n : string) return natural is
      variable v : natural := 0;
      file     f : text;
      variable l : line;
   begin
      file_open( f, n, read_mode );
      while not endfile( f ) loop
         v := v + 1;
         readline( f, l );
      end loop;
      file_close( f );
      return v;
   end function flen;

   impure function frd(constant n: string) return Slv9Array is
      variable v : Slv9Array(1 to flen(n));
      file     f : text;
      variable l : line;
      variable b : bit_vector(v(0)'range);
   begin
      file_open( f, n, read_mode );
      for i in v'range loop
         readline( f, l );
         read(l, b);
         v(i) := to_stdlogicvector( b );
      end loop;
      file_close( f );
      return v;
   end function frd;

   constant tstVec          : Slv9Array := frd( "NCMOutTst.txt" );
   constant cmpVec          : Slv9Array := frd( "NCMOutCmp.txt" );

   signal   usb2Clk         : std_logic := '0';
   signal   usb2Rst         : std_logic := '0';
   signal   epClk           : std_logic := '0';
   signal   run             : boolean   := true;

   signal   epIb            : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal   epOb            : Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;

   signal   fifoDataInp     : Usb2ByteType       := ( others => '0');
   signal   fifoLastInp     : std_logic          := '0';
   signal   fifoWenaInp     : std_logic          := '0';
   signal   fifoFullInp     : std_logic          := '0';

   signal   fifoDataOut     : Usb2ByteType       := ( others => '0');
   signal   fifoLastOut     : std_logic          := '0';
   signal   fifoRenaOut     : std_logic          := '0';
   signal   fifoRenaOutLoc  : std_logic          := '0';
   signal   fifoEmptyOut    : std_logic          := '0';

   signal   tstIdx          : natural            := tstVec'low;
   signal   cmpIdx          : natural            := cmpVec'low;

   -- modulate the in-stream  'vld/don' with an LFSR
   signal   chopUsb2        : std_logic_vector( 10 downto 0 ) := ( 0 => '1', others => '0');
   signal   chopEp          : std_logic_vector( 10 downto 0 ) := ( 1 => '1', 7 => '1', others => '0');

 begin

   P_CLK : process is
   begin
      wait for 8.333 ns;
      usb2Clk <= not usb2Clk;
      if ( not run ) then
         wait;
      end if;
   end process P_CLK;
   
   epClk           <= usb2Clk;

   epOb.mstOut.dat <= tstVec(tstIdx)(7 downto 0);
   epOb.mstOut.don <= tstVec(tstIdx)(8)     and chopUsb2(0);
   epOb.mstOut.vld <= not tstVec(tstIdx)(8) and chopUsb2(0);

   P_DRV : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
	     chopUsb2 <= (chopUsb2(0) xor chopUsb2(2)) & chopUsb2(chopUsb2'left downto 1);
		 if ( ( (epOb.mstOut.vld or epOb.mstOut.don) and epIb.subOut.rdy ) = '1' ) then
		    if ( tstIdx /= tstVec'high ) then
			   tstIdx <= tstIdx + 1;
			end if;
		 end if;
      end if;
   end process P_DRV;

   fifoRenaOut <= fifoRenaOutLoc and chopEp(0);

   P_CMP : process ( epClk ) is
   begin
      if ( rising_edge( epClk ) ) then
	     chopEp         <= (chopEp(0) xor chopEp(2)) & chopEp(chopEp'left downto 1);
	     fifoRenaOutLoc <= '1';
	     if ( (fifoRenaOut and not fifoEmptyOut) =  '1' ) then
		    assert cmpVec(cmpIdx) = fifoLastOut & fifoDataOut report "output data mismatch" severity failure;
			if ( cmpIdx = cmpVec'high ) then
			   fifoRenaOutLoc <= '0';
			   run         <= false;
			   report "Test PASSED";
			else
			   cmpIdx <= cmpIdx + 1;
			end if;
         end if;
      end if;
   end process P_CMP;


   U_DUT : entity work.Usb2EpCDCNCM
      generic map (
         CTL_IFC_NUM_G           => 1,
         ASYNC_G                 => false,
         LD_RAM_DEPTH_INP_G      => LD_DEPTH_C,
         LD_RAM_DEPTH_OUT_G      => LD_DEPTH_C
      )
      port map (
         usb2Clk                 => usb2Clk,
         usb2Rst                 => usb2Rst,

         usb2DataEpIb            => epOb,
         usb2DataEpOb            => epIb,

         epClk                   => epClk,
         epRstOut                => open,

         fifoDataInp             => fifoDataInp,
         fifoLastInp             => fifoLastInp,
         fifoWenaInp             => fifoWenaInp,
         fifoFullInp             => fifoFullInp,

         fifoDataOut             => fifoDataOut,
         fifoLastOut             => fifoLastOut,
         fifoRenaOut             => fifoRenaOut,
         fifoEmptyOut            => fifoEmptyOut
      );

end architecture sim;
