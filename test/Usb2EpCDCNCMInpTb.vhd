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

entity Usb2EpCDCNCMInpTb is
end entity Usb2EpCDCNCMInpTb;

architecture Sim of Usb2EpCDCNCMInpTb is
   constant LD_DEPTH_C      : natural   := 7;
   constant TMO_WIDTH_C     : natural   := 10;
   constant MAX_DGRAMS_C    : natural   := 2;
   constant MAX_NTB_SIZE_C  : natural   := 12 + 12 + 4*(MAX_DGRAMS_C) + 40;

   subtype  Slv9            is std_logic_vector(8 downto 0);
   type     Slv9Array       is array (natural range <>) of Slv9;

   signal   usb2Clk         : std_logic := '0';
   signal   usb2Rst         : std_logic := '0';
   signal   epClk           : std_logic := '0';
   signal   epRst           : std_logic := '0';
   signal   run             : boolean   := true;

   signal   epIb            : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal   epOb            : Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;
   signal   fifoDataInp     : Usb2ByteType       := ( others => '0');
   signal   fifoLastInp     : std_logic          := '0';
   signal   fifoWenaInp     : std_logic          := '0';
   signal   fifoWenaLoc     : std_logic          := '0';
   signal   fifoFullInp     : std_logic          := '0';
   signal   fifoBusyInp     : std_logic          := '0';
   signal   fifoAbrtInp     : std_logic          := '0';

   signal   timeout         : unsigned(TMO_WIDTH_C - 1 downto 0) := to_unsigned( 100, TMO_WIDTH_C );

   signal   ramRdPtrOb      : unsigned(LD_DEPTH_C downto 0);
   signal   ramRdPtrIb      : unsigned(LD_DEPTH_C downto 0);
   signal   ramWrPtrOb      : unsigned(LD_DEPTH_C downto 0);
   signal   ramWrPtrIb      : unsigned(LD_DEPTH_C downto 0);

   signal   cnt             : unsigned(7 downto 0) := (others => '0');

   type     DrvStateType    is (IDLE, DRV, DONE );

   signal   drvState        : DrvStateType := IDLE;
   signal   drvStateNext    : DrvStateType;

   signal   chopUsb2        : std_logic_vector( 10 downto 0 ) := ( 0 => '1', others => '0');
   signal   chopEp          : std_logic_vector( 10 downto 0 ) := ( 1 => '1', 7 => '1', others => '0');

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

   constant tstVec          : Slv9Array := frd( "NCMInpTst.txt" );
   signal   tstIdx          : natural   := tstVec'low;
   signal   tstIdxSav       : natural   := tstVec'low;
   signal   tstIdxAbr       : natural   := tstVec'low;

   procedure usb2Tick is
   begin
      wait until rising_edge( usb2Clk );
   end procedure usb2Tick;

begin

   P_CLK : process is
   begin
      wait for 8.333 ns;
      usb2Clk <= not usb2Clk;
      if ( not run ) then
         wait;
      end if;
   end process P_CLK;

   fifoDataInp <= tstVec( tstIdx )(7 downto 0);
   fifoLastInp <= tstVec( tstIdx )(8);

   fifoWenaInp <= chopEp(0) and fifoWenaLoc;

   P_DRV_SEQ : process ( epClk ) is
      variable dly : integer   := 120;
      variable ena : std_logic := '1';
   begin
      if ( rising_edge( epClk ) ) then
         chopEp         <= (chopEp(0) xor chopEp(2)) & chopEp(chopEp'left downto 1);
         fifoAbrtInp    <= '0';

         if ( tstIdx = tstVec'low ) then
            fifoWenaLoc    <= '1';
         end if;

         if ( (fifoWenaInp and not fifoBusyInp and not fifoFullInp and not fifoAbrtInp ) = '1' ) then
            if ( tstIdx = tstVec'high ) then
               fifoWenaLoc <= '0';
            else
               tstIdx      <= tstIdx + 1;
               if ( fifoLastInp = '1' ) then
                  tstIdxSav  <= tstIdx + 1;
               elsif ( tstIdx /= tstIdxAbr and tstIdx = tstIdxSav + 3 ) then
                  tstIdxAbr   <= tstIdx;
                  tstIdx      <= tstIdxSav;
                  fifoAbrtInp <= '1';
               end if;
            end if;
         end if;
      end if;
   end process P_DRV_SEQ;

   P_USB_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         chopUsb2 <= (chopUsb2(0) xor chopUsb2(2)) & chopUsb2(chopUsb2'left downto 1);
      end if;
   end process P_USB_SEQ;

   P_SAV : process is
      file f : text;
      variable l : line;
      variable b : bit_vector(7 downto 0);
      variable n : natural := 0;
   begin
      file_open( f, "NCMInpCmp.txt", write_mode );
      epOb.subInp.rdy <= chopUsb2(0);

      L_MAIN : while true loop

         while ( (epOb.subInp.rdy and epIb.mstInp.vld ) /= '1' ) loop
            if ( epIb.mstInp.vld = '0' ) then
               n := n + 1;
            end if;
            if ( n >= 200 ) then
               exit L_MAIN;
            end if;
            usb2Tick;
         end loop;
         n := 0;
         b := to_bitvector( epIb.mstInp.dat );
         write( l, b );
         writeline( f, l );
         usb2Tick;

      end loop;

      file_close( f );

      run <= false;
      wait;
   end process P_SAV;
 
   epClk           <= usb2Clk;
   epRst           <= usb2Rst;

   ramWrPtrIb      <= ramWrPtrOb;
   ramRdPtrIb      <= ramRdPtrOb;

   U_DUT : entity work.Usb2EpCDCNCMInp
      generic map (
         LD_RAM_DEPTH_G         => LD_DEPTH_C,
         EP_TIMER_WIDTH_G       => TMO_WIDTH_C,
         MAX_DGRAMS_G           => MAX_DGRAMS_C,
         MAX_NTB_SIZE_G         => MAX_NTB_SIZE_C
      )
      port map (
         usb2Clk                => usb2Clk,
         usb2Rst                => usb2Rst,

         usb2EpIb               => epOb,
         usb2EpOb               => epIb,

         ramRdPtrOb             => ramRdPtrOb,
         ramWrPtrIb             => ramWrPtrIb,

         epClk                  => epClk,
         epRst                  => epRst,

         ramWrPtrOb             => ramWrPtrOb,
         ramRdPtrIb             => ramRdPtrIb,

         maxNTBSize             => open,
         timeout                => timeout,

         fifoDataInp            => fifoDataInp,
         fifoLastInp            => fifoLastInp,
         fifoFullInp            => fifoFullInp,
         fifoWenaInp            => fifoWenaInp,
         fifoAbrtInp            => fifoAbrtInp,
         fifoBusyInp            => fifoBusyInp,
         fifoAvailInp           => open
      );

end architecture Sim;
