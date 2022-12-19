library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity iotsttb is
end entity iotsttb;

architecture sim of iotsttb is
   signal clk : std_logic := '0';
   signal dat : std_logic_vector(7 downto 0) := (others => 'X');
   signal dou : std_logic_vector(7 downto 0) := (others => 'X');
   signal vld : std_logic := '0';
   signal nxt : std_logic := '0';
   signal stp : std_logic;
   signal rdy : std_logic;
   signal run : boolean   := true;
 
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
      constant  w : in  natural
   ) is
   begin
     while ( dou = x"00" ) loop
        tick;
     end loop;
     while ( stp = '0' ) loop
       for i in 0 to w loop
          n <= '0';
          if ( i = w ) then
             n <= '1';
          end if;
          tick;
          if ( n = '1' ) then
             report integer'image( to_integer( unsigned( dou ) ) );
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
      rcv(nxt, 0);
      tick;
      rcv(nxt, 0);
      tick;
      rcv(nxt, 1);
      tick;
      rcv(nxt, 2);
      run <= false;
      wait;
   end process P_RCV;

   U_DUT : entity work.iotst
      port map (
         clk    => clk,
         din    => dat,
         vld    => vld,
         nxt    => nxt,
         dir    => '0',
         genStp => '1',
         dou    => dou,
         stp    => stp,
         rdy    => rdy
      );

end architecture sim;
