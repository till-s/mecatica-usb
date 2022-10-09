library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;

entity UlpiIOTb is
end entity UlpiIOTb;

architecture Sim of UlpiIOTb is
   signal     regReq      : UlpiRegReqType := ULPI_REG_REQ_INIT_C;
   signal     regRep      : UlpiRegRepType;
   signal     clk         : std_logic := '0';
   signal     rst         : std_logic := '0';
   signal     stp         : std_logic := '0';
   signal     nxt         : std_logic := '0';
   signal     dir         : std_logic := '0';
   signal     dat         : std_logic_vector(7 downto 0) := (others => 'Z');
   signal     run         : boolean   := true;
   type   RegArray  is array ( natural range <> ) of std_logic_vector(7 downto 0);
   signal regs    : RegArray(0 to 16) := (others => (others => '0'));
   signal extRegs : RegArray(0 to 16) := (others => (others => '0'));
  
   signal adly            : natural   := 0;
   signal wdly            : natural   := 0;
   signal a2dly           : natural   := 0;
   signal regClr          : boolean   := false;

   type StateType is (RESET, IDLE, ADD, ADDLY, WR, RD, DONE);
   type RegType   is record
         state       : StateType;
         cnt         : natural;
         dir         : std_logic;
         nxt         : std_logic;
         dat         : std_logic_vector(7 downto 0);
         add         : natural;
         ext         : boolean;
         isRd        : boolean;
   end record RegType;

   signal dbg1 : RegType;

   procedure ad(
      signal   eo: inout UlpiRegReqType;
      constant a : in  natural
   ) is
   begin
      eo <= ULPI_REG_REQ_INIT_C;
      if ( a >= 64 ) then
         eo.extnd <= '1';
      end if;
      eo.addr  <= std_logic_vector( to_unsigned(a mod 64, 8) );
      eo.valid <= '1';
   end procedure ad;

   procedure wr(
      signal   eo: inout UlpiRegReqType;
      signal   ei: in    UlpiRegRepType;
      constant a : in  natural;
      constant v : in  std_logic_vector(7 downto 0);
      constant e : in  std_logic := '0'
   ) is
   begin
      ad(eo, a);
      eo.wdat  <= v;
      eo.rdnwr <= '0';
      while ( (eo.valid and ei.ack) = '0' ) loop
         wait until rising_edge( clk );
      end loop;
      assert ( ei.err = e ) report "Write Error";
      eo.valid <= '0';
      wait until rising_edge( clk );
   end procedure wr;

   procedure rd(
      signal   eo: inout UlpiRegReqType;
      signal   ei: in    UlpiRegRepType;
      constant a : in  natural;
      variable v : out std_logic_vector(7 downto 0);
      constant e : in  std_logic := '0'
   ) is
   begin
      ad(eo, a);
      eo.rdnwr <= '1';
      while ( (eo.valid and ei.ack) = '0' ) loop
         wait until rising_edge( clk );
      end loop;
      v := ei.rdat;
      assert ( ei.err = e ) report "Read Error";
      eo.valid <= '0';
      wait until rising_edge( clk );
   end procedure rd;

begin

   P_CLK : process is
   begin
      if ( run ) then wait for 10 ns; clk <= not clk; else wait; end if;
   end process P_CLK;

   P_TST : process is
      variable res : std_logic_vector(7 downto 0);
   begin
      for i    in 0 to 2 loop
      for j    in 0 to 2 loop
      for k    in 0 to 2 loop
         regClr  <= true;
         adly    <= i;
         a2dly   <= j;
         wdly    <= k;
         wait until rising_edge( clk );
         regClr  <= false;

         wr(regReq, regRep, 12, x"ab"); 
         wr(regReq, regRep, 65, x"43"); 
         rd(regReq, regRep, 12, res );
         assert res = x"ab" report "Readback mismatch";
         rd(regReq, regRep,  1, res );
         assert res = x"00" report "Readback not zero";
         rd(regReq, regRep, 65, res );
         assert res = x"43" report "Extended Readback mismatch";
         rd(regReq, regRep, 64, res );
         assert res = x"00" report "Extended Readback not zero";
         wait until rising_edge( clk );
         wait until rising_edge( clk );
      end loop;
      end loop;
      end loop;
      run <= false;
      wait;
   end process P_TST;

   U_DUT : entity work.UlpiIO
      port map (
         rst         => rst,
         clk         => clk,
         stp         => stp,
         dir         => dir,
         nxt         => nxt,
         dat         => dat,
         regReq      => regReq,
         regRep      => regRep
      );

   P_FAKE : process ( clk ) is
      variable v : RegType;
   begin
      v := dbg1;
      if ( rising_edge( clk ) ) then
         v.nxt := '0';
         if ( regClr ) then
            regs    <= (others => (others => '0'));
            extRegs <= (others => (others => '0'));
         end if;
         case ( v.state ) is
            when RESET =>
               if ( v.cnt = 0 ) then
                  v.cnt   := 3;
                  v.state := IDLE;
                  v.dir   := '0';
               else
                  v.cnt   := v.cnt - 1;
               end if;
              
            when IDLE  =>
               if ( dat(7) = '1' ) then
                  v.add   := to_integer( unsigned( dat(5 downto 0) ) );
                  v.ext   := (dat(5 downto 0) = "101111");
                  v.isRd  := (dat(6) = '1');
                  v.cnt   := adly;
                  if ( v.cnt = 0 ) then
                     v.nxt   := '1';
                     v.state := ADD;
                     if ( v.ext ) then
                        v.cnt := a2dly + 1;
                     end if;
                  else
                     v.state := ADDLY;
                     v.cnt   := v.cnt - 1;
                  end if;
               end if;

            when ADDLY =>
               if ( v.cnt = 0 ) then
                  v.nxt   := '1';
                  v.state := ADD;
                  if ( v.ext ) then
                     v.cnt := a2dly + 1;
                  end if;
               else
                  v.cnt := v.cnt - 1;
               end if;

            when ADD =>
               if ( v.cnt = 1 ) then
                  v.nxt := '1';
               end if;
               if ( v.cnt = 0 ) then
                  if ( v.ext ) then
                     v.add := to_integer( unsigned( dat ) );
                  end if;
                  if ( v.isRd ) then
                     v.state := RD;
                     v.dir   := '1';
                     v.cnt   := 2;
                  else
                     v.cnt   := wdly;
                     if ( v.cnt = 0 ) then
                        v.nxt   := '1';
                     end if;
                     v.state := WR;
                  end if;
               else
                  v.cnt := v.cnt - 1;
               end if;

            when WR =>
               if ( v.cnt = 1 ) then
                  v.nxt := '1';
               end if;
               if ( v.cnt = 0 ) then
                  if ( v.ext ) then
                     extRegs( v.add ) <= dat;
                  else
                     regs   ( v.add ) <= dat;
                  end if;
                  v.state := IDLE;
               else
                  v.cnt   := v.cnt - 1;
               end if;

            when RD =>
               if ( v.ext ) then
                  v.dat := extRegs( v.add );
               else
                  v.dat := regs   ( v.add );
               end if;
               if ( v.cnt = 0 ) then
                  v.dir   := '0';
                  v.state := IDLE;
               else
                  v.cnt   := v.cnt - 1;
               end if;
         
            when DONE  =>
         end case;
         dbg1 <= v;
      end if;
   end process P_FAKE;

   dir <= dbg1.dir;
   nxt <= dbg1.nxt;

   P_DAT : process ( dbg1 ) is
   begin
      if ( dbg1.dir = '1' ) then
         dat <= dbg1.dat;
      else
         dat <= (others => 'Z');
      end if;
   end process P_DAT;

end architecture Sim;
