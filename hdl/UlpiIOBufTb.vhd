library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity UlpiIOBufTb is
end entity UlpiIOBufTb;

use work.UlpiPkg.all;

architecture sim of UlpiIOBufTb is
   signal clk : std_logic := '0';
   signal dat : std_logic_vector(7 downto 0) := (others => 'X');
   signal dou : std_logic_vector(7 downto 0) := (others => 'X');
   signal vld : std_logic := '0';
   signal nxt : std_logic := '0';
   signal stp : std_logic;
   signal rdy : std_logic;
   signal run : boolean   := true;
   signal rx  : UlpiRxType;
   signal ui  : UlpiIbType;
   signal uo  : UlpiObType;
   signal pass: natural   := 0;
 
   procedure tick is begin wait until rising_edge(clk); end procedure tick;

   procedure snd(
      signal   d : inout std_logic_vector;
      signal   v : out   std_logic;
      constant l : in    natural
   ) is
      variable o : unsigned(d'range);
      variable i : natural;
   begin
      o := to_unsigned(1, o'length);
      v <= '1';
      d <= std_logic_vector(o);
      tick;
      i := 1;
      while ( i <= l ) loop
         if ( rdy = '1' ) then
            if ( i = l ) then
               v <= '0';
               d <= (others => 'X');
            else
               o := o + 1;
               d <= std_logic_vector(o);
            end if;
            i := i + 1;
         end if;
         tick;
      end loop;
      while ( stp = '0' ) loop
         tick;
      end loop;
   end procedure snd;

   procedure rcv (
      signal    n : inout std_logic;
      constant  w : in    natural;
      signal    p : inout natural
   ) is
     variable exp : natural;
   begin
     p <= p;
     while ( dou = x"00" ) loop
        tick;
     end loop;
     exp := 1;
     while ( stp = '0' ) loop
       for i in 0 to w loop
          n <= '0';
          if ( i = w ) then
             n <= '1';
          end if;
          tick;
          if ( n = '1' ) then
             if ( stp = '1' ) then
                exp := 0;
             end if;
             assert exp = to_integer( unsigned( dou ) ) report "unexpected data" severity failure;
             exp := exp + 1;
             p   <= p + 1;
          end if;
       end loop;
     end loop;
     n <= '0';
     tick;
   end procedure rcv;

begin

   process is begin if run then wait for 10 ns; clk <= not clk; else wait; end if; end process;

   P_DRV : process is
   begin
      tick;
      tick;
      tick;
      snd(dat, vld, 1);
      tick;
      snd(dat, vld, 4);
      tick;
      snd(dat, vld, 4);
      tick;
      snd(dat, vld, 4);
      wait;
   end process P_DRV;

   P_RCV : process is
   begin
      tick;
      rcv(nxt, 0, pass);
      tick;
      rcv(nxt, 0, pass);
      tick;
      rcv(nxt, 1, pass);
      tick;
      rcv(nxt, 2, pass);
      tick;
      -- includes comparison of data during STP
      assert pass = 2 + 3*5 report "missed some test" severity failure;
      report "TEST PASSED";
      run <= false;
      wait;
   end process P_RCV;

   ui.dir <= '0';
   ui.nxt <= nxt;
   ui.dat <= (others => 'X');

   stp    <= uo.stp;
   dou    <= uo.dat;

   U_DUT : entity work.UlpiIOBuf
      generic map (
         MUST_MASK_STP_G => true
      )
      port map (
         ulpiClk    => clk,

         genStp     => '1',
         waiNxt     => '1',
         frcStp     => '0',
 
         txVld      => vld,
         txDat      => dat,
         txRdy      => rdy,
         txSta      => '0',
         txDon      => open,
         txErr      => open,

         ulpiRx     => rx,

         ulpiIb     => ui,
         ulpiOb     => uo
      );

end architecture sim;
