-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

entity I2SPlaybackTb is
end entity I2SPlaybackTb;

architecture sim of I2SPlaybackTb is

   constant SAMPLE_SIZE_C : natural   := 3;
   constant HI_SPEED_C    : boolean   := true;
   constant SLOTSZ_C      : natural   := 2*SAMPLE_SIZE_C;
   constant SPF_C         : natural   := 48; -- slots per frame
   constant SAMPLE_RATE_C : real      := real(SPF_C*1000);
   constant BITCLK_MULT_C : natural   := 64;
   constant BITCLK_RATE_C : real      := SAMPLE_RATE_C * real(BITCLK_MULT_C);
   -- first frame sent is used to synchronize receiver and
   -- will not appear on i2s
   constant NFRMS_EXP_C   : natural   := 3;

   signal usb2Clk         : std_logic := '0';
   signal bclk            : std_logic := '0';
   signal pblrc           : std_logic := '1';
   signal pbdat           : std_logic := '1';
   signal pblrclst        : std_logic := '1';

   signal usb2Rx          : Usb2RxType        := USB2_RX_INIT_C;
   signal usb2DevStatus   : Usb2DevStatusType := USB2_DEV_STATUS_INIT_C;

   signal resetting       : std_logic;

   signal clkCount        : natural := 0;

   signal epOb : usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;
   signal epIb : usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

   signal run  : boolean := true;

   function fillVec(constant l: in natural) return unsigned is
      variable v : unsigned(l - 1 downto 0);
   begin
      for i in 0 to l/8 - 1 loop
         v(8*i+7 downto 8*i) := to_unsigned(i,8);
      end loop;
      return v;
   end function fillVec;

   procedure tick is
   begin
      wait until rising_edge( usb2Clk );
   end procedure tick;

   procedure sendSOF(
      signal rx : inout Usb2RxType
   ) is
   begin
      rx <= rx;
      rx.pktHdr.vld <= '1';
      rx.pktHdr.sof <= true;
      tick;
      rx.pktHdr.vld <= '0';
      rx.pktHdr.sof <= false;
      tick;
   end procedure sendSOF;

   procedure sendFrame(
      signal ob : inout Usb2EndpPairObType
   ) is
      variable dat : unsigned(7 downto 0);
   begin
      tick;
      dat := (others => '0');
      ob.mstOut.vld <= '1';
      for i in 1 to SLOTSZ_C*48 loop
        ob.mstOut.dat <= std_logic_vector( dat );
        dat           := dat + 1;
        tick;
      end loop;
      ob.mstOut.vld <= '0';
      ob.mstOut.don <= '1';
      tick;
      ob.mstOut.don <= '0';
      tick;
   end procedure sendFrame;

   procedure getRate(
      signal ob : inout Usb2EndpPairObType
   ) is
      variable r : std_logic_vector(31 downto 0) := (others => '0');
      variable i : natural;
      variable g : real;
   begin
      ob.subInp.rdy <= '0';
      r             := (others => '0');
      i             := 0;
      while ( epIb.mstInp.vld = '0' ) loop
         tick;
      end loop;
      ob.subInp.rdy <= '1';
      tick;
      while ( epIb.mstInp.vld = '1' ) loop
         r(8*i+7 downto 8*i) := epIb.mstInp.dat;
         i := i + 1;
         tick;
      end loop;
      ob.subInp.rdy <= '0';
      tick;
      if ( usb2DevStatus.hiSpeed ) then
         assert i = 4 report "feedback response invalid (hispeed)" severity failure;
      else
         assert i = 3 report "feedback response invalid (hispeed)" severity failure;
      end if;
      g := real( to_integer( unsigned( r ) ) )/2.0**13;
      report "Rate: " & real'image(g);
      assert abs(48.0 - g) < 0.05 report "feedback freq offset too big" severity failure;
   end procedure getRate;

   procedure completeFrame(
      signal   rx : inout Usb2RxType;
      variable  l : inout natural
   ) is
      variable per : natural;
   begin
      if ( usb2DevStatus.hiSpeed ) then
         for i in 1 to 8 loop
            while ( clkCount - l < i*7500 ) loop
               tick;
            end loop;
            sendSOF(rx);
         end loop;
      else
         while ( clkCount - l < 60000 ) loop
            tick;
         end loop;
         sendSOF(rx);
      end if;
      l := clkCount;
   end procedure completeFrame;

begin

   process is
   begin
      if ( not run ) then
         wait;
      else
         wait for 16.666 ns / 2.0;
         usb2Clk <= not usb2Clk;
      end if;
   end process;

   process is
   begin
      if ( not run ) then
         wait;
      else
         wait for 1000.0 ms / BITCLK_RATE_C / 2.0;
         bclk <= not bclk;
      end if;
   end process;

   process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         clkCount <= clkCount + 1;
      end if;
   end process;

   P_TEST : process is
      variable lst : natural;
   begin
      usb2DevStatus.hiSpeed <= HI_SPEED_C;
      tick;
      while ( resetting = '1' ) loop
         tick;
      end loop;
      tick;
      sendSOF(usb2Rx);
      lst := clkCount;
      sendFrame( epOb ); completeFrame( usb2Rx, lst );
      sendFrame( epOb ); completeFrame( usb2Rx, lst );
      sendFrame( epOb ); getRate(epOb); completeFrame( usb2Rx, lst );
      sendFrame( epOb ); getRate(epOb); completeFrame( usb2Rx, lst );
      wait;
   end process P_TEST;

   P_RCV : process ( bclk ) is
      variable sreg  : std_logic_vector(8*SAMPLE_SIZE_C - 1 downto 0) := (others => '0');
      constant zro   : std_logic_vector(sreg'range)                   := (others => '0');
      variable cmp   : unsigned(8*SAMPLE_SIZE_C - 1 downto 0)         := fillVec(8*SAMPLE_SIZE_C);
      variable smpls : natural := 0;
      variable frms  : natural := 0;
      variable bcnt  : natural := 0;
   begin
      if ( rising_edge( bclk ) ) then
         pblrclst <= pblrc;
         if ( bcnt > 0 ) then
            sreg := sreg(sreg'left - 1 downto 0) & pbdat;
            bcnt := bcnt - 1;
         end if;
         if ( pblrc /= pblrclst ) then
            bcnt := 8*SAMPLE_SIZE_C;
            if ( sreg /= zro ) then
               if ( unsigned(sreg) /= cmp ) then
                  for i in sreg'length/8 - 1 downto 0 loop
                     report "sreg[" & integer'image(i) & "] " & integer'image(to_integer(unsigned(sreg(8*i+7 downto 8*i))));
                     report "cmp [" & integer'image(i) & "] " & integer'image(to_integer(unsigned(cmp(8*i+7 downto 8*i))));
                  end loop;
                  report "smpls" & integer'image(smpls);
                  report "frms " & integer'image(frms);
               end if;
               assert unsigned(sreg) = cmp report "unexpected data received" severity failure;
               smpls := smpls + 1;
               for i in 0 to cmp'length/8 - 1 loop
                  cmp(8*i + 7 downto 8*i) := cmp(8*i + 7 downto 8*i) + to_unsigned(SAMPLE_SIZE_C, 8);
               end loop;

               if ( smpls = 2*SPF_C ) then
                  cmp   := fillVec(cmp'length);
                  smpls := 0;
                  frms  := frms + 1;
               end if;

               if ( frms = NFRMS_EXP_C ) then
                  assert frms = NFRMS_EXP_C report "missing frames?" severity failure;
                  report "TEST PASSED";
                  run <= false;
               end if;
            end if;
         end if;
      end if;
   end process P_RCV;

   process (bclk) is
      variable cnt : natural :=0;
   begin
      if ( rising_edge( bclk ) ) then
         if ( cnt = 0 ) then
            pblrc <= not pblrc;
            cnt   := SAMPLE_SIZE_C*8 - 1;
         else
            cnt   := cnt - 1;
         end if;
      end if;
   end process;

   U_DUT : entity work.I2SPlayback
      generic map (
         SAMPLE_SIZE_G   => SAMPLE_SIZE_C,
         BITCLK_MULT_G   => BITCLK_MULT_C
      )
      port map (
         usb2Clk         => usb2Clk,
         usb2Rst         => '0',
         usb2RstBsy      => resetting,
         usb2Rx          => usb2Rx,
         usb2DevStatus   => usb2DevStatus,
         usb2EpIb        => epOb,
         usb2EpOb        => epIb,
 
         i2sBCLK         => bclk,
         i2sPBLRC        => pblrc,
         i2sPBDAT        => pbdat
      );
end architecture sim;
