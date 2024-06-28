-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;

entity UlpiIOBufAltTb is
end entity UlpiIOBufAltTb;

architecture sim of UlpiIOBufAltTb is
   signal clk     : std_logic := '0';
   signal nxt0    : std_logic := '0';
   signal nxt1    : std_logic := '0';
   signal nxt2    : std_logic := '0';
   signal dir0    : std_logic := '0';
   signal dir1    : std_logic := '0';
   signal dir2    : std_logic := '0';
   signal dat1    : std_logic_vector(7 downto 0) := (others => '0');
   signal dat2    : std_logic_vector(7 downto 0) := (others => '0');
   signal stp     : std_logic := '0';
   signal dou     : std_logic_vector(7 downto 0);
   signal txVld   : std_logic := '0';
   signal txVld0  : std_logic := '0';
   signal txVld1  : std_logic := '0';
   signal txRdy   : std_logic := '0';
   signal txSta   : std_logic := '0';
   signal txDon   : std_logic := '0';
   signal txErr   : std_logic := '0';
   signal txDat0  : std_logic_vector(7 downto 0) := (others => '0');
   signal txDat1  : std_logic_vector(7 downto 0) := (others => '0');
   signal txDat   : std_logic_vector(7 downto 0) := (others => '0');
   signal txSync  : boolean   := false;
   signal txAck   : boolean   := false;

   signal cnt     : integer   := 1;
   signal cmp     : integer   := 1;
   signal run     : boolean   := true;
   signal ulpiIb  : UlpiIbType;
   signal ulpiOb  : UlpiObType;
   signal phase   : integer   := 0;

   signal txProcErr : std_logic := '0';
   signal txProcAck : std_logic := '0';
   signal txProcDly : integer   := 0;
   signal rxProcErr : std_logic := '0';
   signal rxProcAck : std_logic := '0';
   signal rxCmdAck  : std_logic := '0';
   signal rxCmdDly  : integer   := -1;

   signal txStarted : boolean   := false;
   signal aborted   : std_logic := '0';

   constant vc1 : Usb2ByteArray := (
      x"43",
      x"11",
      x"22",
      x"33"
   );

   procedure tick is
   begin
      wait until rising_edge(clk);
   end procedure tick;

   procedure sndVec(
      signal   dat : out std_logic_vector(7 downto 0);
      signal   vld : out std_logic;
      signal   sta : out std_logic;
      signal   sto : out std_logic;
      constant vec : in  Usb2ByteArray;
      constant sti : in  std_logic := '0'
   ) is
   begin
      sta <= sti;
      vld <= '1';
      sto <= '0';
      L_SND : for i in vec'low to vec'high loop
         dat <= vec(i);
         tick;
         if ( (txDon and txErr) = '1' ) then
            exit L_SND;
         end if;
         while ( (txVld and txRdy) = '0' ) loop
            tick;
            if ( (txDon and txErr) = '1' ) then
               exit L_SND;
            end if;
         end loop;
      end loop;
      vld <= '0';
      dat <= (others => 'X');
      while ( txDon = '0' ) loop
         tick;
      end loop;
      report "DON " & std_logic'image(txDon) & std_logic'image(txErr);
      sto <= txErr;
      tick;
   end procedure sndVec;

   procedure rcvVec(
      signal   nxt : out std_logic;
      constant vec : in  Usb2ByteArray;
      constant ste : in  Usb2ByteType
   ) is
      variable i : integer;
   begin
      while ( ulpiOb.dat = x"00" or ulpiIb.dir = '1' ) loop tick; end loop;
      nxt <= '1';
      tick;
      i   := vec'low;
      while ( ( ulpiOb.stp = '0' ) and ( aborted = '0' ) ) loop
         assert vec(i) = ulpiOb.dat report "RX data mismatch" severity failure;
 i := i + 1;
         tick;
      end loop;
      if ( aborted = '0' ) then
         assert i = vec'high + 1 report "RX mismatch of elms read" severity failure;
         assert ste = ulpiOb.dat report "RX status mismatch" severity failure;
      end if;
      nxt <= '0';
      tick;
   end procedure rcvVec;

      type RxCmdStateType is (RXCMD_IDLE, RXCMD_WAI, RXCMD_EXE);

      type RxCmdRegType is record
         state : RxCmdStateType;
         ack   : std_logic;
         idx   : integer;
      end record RxCmdRegType;

      constant RX_CMD_REG_INIT_C : RxCmdRegType := (
         state => RXCMD_IDLE,
         ack   => '0',
         idx   => 1
      );

      signal r  : RxCmdRegType := RX_CMD_REG_INIT_C;

   signal dbg : RxCmdRegType;

begin

   txDat0 <= std_logic_vector( to_unsigned( cnt mod 256, 8 ) );

   P_CLK : process is
   begin
      if ( not run ) then wait; end if;
      wait for 5 us;
      clk <= not clk;
   end process P_CLK;   

   P_DRV : process (clk) is
      variable s1 : positive := 345;
      variable s2 : positive := 666;
      variable rn : real;
   begin
      if ( rising_edge( clk ) and ( 0 = phase ) ) then

         if ( cnt = 1 ) then
            txVld0 <= '1';
         end if;

         if ( (txVld0 and txRdy) = '1' ) then
            cnt <= cnt + 1;
            if ( cnt = 100 ) then
               txVld0 <= '0';
            end if;
         end if;

         if ( dou /= x"00" ) then
            uniform(s1, s2 ,rn);
            if ( rn > 0.5 ) then
               nxt0 <= not nxt0;
            end if;
         end if;

         if ( nxt0 = '1' ) then
            assert to_integer( unsigned(dou) ) = cmp report "data mismatch" severity failure;
            if ( cmp = 100 ) then
               nxt0 <= '0';
            end if;
            cmp <= cmp + 1;
         end if;

         if ( stp = '1' ) then
            assert ( cmp = 101 ) report "end count mismatch" severity failure;
            phase  <= phase + 1;
            txVld0 <= '0';
            nxt0   <= '0';
            -- pulls txDat0 to all-zeros
            cnt    <= 0;
         end if;

      end if;
   end process P_DRV;

   P_SND : process is
   begin
      while not txSync loop tick; end loop;
      txProcAck <= '0';
      for i in 1 to txProcDly loop tick; end loop;
      sndVec(txDat1, txVld1, txSta, txProcErr, vc1);
      txProcAck <= '1';
      tick;
   end process P_SND;

   -- rxCmdDly < 0 disables this process
   P_RXCMD : process (r, clk, txSync, rxCmdDly, ulpiIb) is
      variable v  : RxCmdRegType := RX_CMD_REG_INIT_C;
   begin

      v    := r;
      dir1 <= '0';
      dat1 <= (others => 'X');

      case ( r.state ) is
         when RXCMD_IDLE =>
            if ( txSync and rxCmdDly >= 0 ) then
               v.ack   := '0';
               v.state := RXCMD_WAI;
               v.idx   := 1;
            end if;
         when RXCMD_WAI =>
            if ( r.idx < rxCmdDly ) then
               v.idx := r.idx + 1;
            else
               if ( ulpiIb.nxt = '0' ) then
                  dir1    <= '1';
                  v.state := RXCMD_EXE;
               else
                  -- TX already starting during this cycle
                  v.ack   := '1';
                  v.state := RXCMD_IDLE;
               end if;
            end if;
         when RXCMD_EXE =>
            dat1    <= x"4a";
            dir1    <= '1';
            v.ack   := '1';
            v.state := RXCMD_IDLE;
      end case;

      rxCmdAck <= v.ack;

      if ( rising_edge( clk ) ) then
         r <= v;
      end if;

      dbg <= r;

   end process P_RXCMD;

   P_MON : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         if ( txStarted and ulpiIb.dir = '1' ) then
            aborted   <= '1';
         end if;
         if ( ((ulpiIb.nxt and not ulpiIb.dir) = '1') and (ulpiOb.dat /= x"00") ) then
            txStarted <= true;
         end if;
         if ( ulpiOb.stp = '1' ) then
            txStarted <= false;
         end if;
         if ( txSync ) then
            txStarted <= false;
            aborted   <= '0';
         end if;
      end if;
   end process P_MON;
 
   P_RXCMD_TEST : process is
   begin
      while ( phase = 0 ) loop
         tick;
      end loop;
      tick;

      for dly in 10 downto -10 loop
         txSync    <= true;
         if dly >= 0 then
            rxCmdDly  <= 0;
            txProcDly <= dly;
         else
            rxCmdDly  <= -dly;
            txProcDly <= 0;
         end if;
         tick;
         txSync    <= false;
         tick;
         rcvVec( nxt1, vc1, x"00" );
         while ( (rxCmdAck and txProcAck ) = '0' ) loop
            tick;
         end loop;
         assert txProcErr = aborted report "incorrect collision handling" severity failure;
      end loop;

      -- test tx abort (before TX accepted first 'nxt')
      rxCmdDly <= -1;
      txProcDly <= 0;

      tick;

      for dly in 0 to 4 loop
         txSync <= true;
         tick;
         txSync <= false;
         -- txVld is asserted during this cycle
         for i in 1 to dly loop
            tick;
         end loop;
         -- signal starting of RX -> should abort TX!
         dir2   <= '1';
         nxt2   <= '1';
         tick;
         nxt2   <= '0';
         while ( txDon = '0' ) loop
            tick;
         end loop;
         assert ( txErr = '1' ) report "TX abort was not detected" severity failure;
         dir2   <= '0';
         tick;
      end loop;

      run <= false;
      report "TEST PASSED";
      wait;
   end process P_RXCMD_TEST;

   ulpiIb.nxt <= nxt0 or nxt1 or nxt2;
   ulpiIb.dir <= dir0 or dir1 or dir2;
   ulpiIb.dat <= dat1 or dat2;
   ulpiIb.stp <= ulpiOb.stp;
   stp        <= ulpiOb.stp;
   dou        <= ulpiOb.dat;

   txVld      <= txVld0 or txVld1;
   txDat      <= txDat0 when phase = 0 else txDat1;

   U_DUT : entity work.UlpiIOBuf
      port map (
         ulpiClk     => clk,
         genStp      => '1',
         regOpr      => '0',
         frcStp      => '0',
         waiNxt      => '0',
         txVld       => txVld,
         txRdy       => txRdy,
         txDat       => txDat,
         txErr       => txErr,
         txDon       => txDon,
         txSta       => txSta,
         ulpiRx      => open,
         ulpiIb      => ulpiIb,
         ulpiOb      => ulpiOb
      );

end architecture sim;
