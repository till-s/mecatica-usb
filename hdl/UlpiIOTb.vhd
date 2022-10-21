library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;

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
   signal jam             : integer   := -1;

   signal jamdir          : std_logic := '0';

   signal ulpiRx          : UlpiRxType;
   signal ulpiTxReq       : UlpiTxReqType := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRep       : UlpiTxRepType;
   signal pktHdr          : Usb2PktHdrType;
   signal rxData          : Usb2StrmMstType;

   signal checkRx         : natural   := 0;
   signal startTx         : integer   := -1;
   signal startTxBB       : integer   := -1;
   signal tokSeen         : natural   := 0;

   type Slv9Array         is array ( natural range <> ) of std_logic_vector(8 downto 0);

   type StateType is (RESET, IDLE, ADD, ADDLY, WR, RD, JAMMED, RXCMD, TX, RX);

   type RegType   is record
         state       : StateType;
         cnt         : natural;
         dly         : natural;
         dir         : std_logic;
         nxt         : std_logic;
         dat         : std_logic_vector(7 downto 0);
         add         : natural;
         jam         : integer;
         ext         : boolean;
         isRd        : boolean;
         txIdx       : natural;
         rxIdx       : natural;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state => RESET,
      cnt   => 10,
      dly   =>  0,
      dir   => '1',
      nxt   => '0',
      dat   => (others => '0'),
      add   => 0,
      jam   => -1,
      ext   => false,
      isRd  => true,
      txIdx => 0,
      rxIdx => 0
   );

   constant DATA0_START_IDX_C : natural := 6;

   constant txVec : Slv9Array := (
      '0' & not USB_PID_TOK_SOF_C & USB_PID_TOK_SOF_C,
      '0' & x"bf",
      '1' & x"bb",
      '0' & not USB_PID_TOK_OUT_C & USB_PID_TOK_OUT_C,
      '0' & x"c9",
      '1' & x"fd",
      '0' & not USB_PID_DAT_DATA0_C & USB_PID_DAT_DATA0_C,
      '0' & x"c7",
      '0' & x"3d",
      '0' & x"25",
      '0' & x"93",
      '0' & x"ba",
      '0' & x"bb",
      '0' & x"b3",
      '0' & x"5e",
      '0' & x"54",
      '0' & x"5a",
      '0' & x"ac",
      '0' & x"5a",
      '0' & x"6c",
      '0' & x"ee",
      '0' & x"00",
      '0' & x"ab",
      '0' & x"a2", --checksum: crc16 (poly 0xa001, seed 0xffff, one's complement of crc attached here)
      '1' & x"c1"
   );

   constant rxVec : Slv9Array := (
      '0' & x"44",
      '0' & x"a1",
      '1' & x"ff",
      '0' & x"00"
   );

   signal sndIdx : natural := 0;

   procedure tick is
   begin
      wait until rising_edge( clk );
   end procedure tick;

   procedure sndPkt(
     signal idx : inout natural;
     signal req : inout ulpiTxReqType
   ) is
   begin
      req.vld <= '1';
      req.dat <= rxVec( idx )(7 downto 0);
      idx     <= idx + 1;
      tick;
      while ( ulpiTxRep.don = '0' ) loop
         if ( ulpiTxRep.nxt = '1' ) then
            if ( req.vld = '1' ) then
              idx     <= idx + 1;
              req.dat <= rxVec( idx )(7 downto 0);
              req.vld <= not rxVec( idx )(8);
            else
              req.dat <= (others => '0');
            end if;
         end if;
         tick;
      end loop;
   end procedure sndPkt;

   function toSl(constant x : in boolean) return std_logic is
   begin
      if ( x ) then return '1'; else return '0'; end if;
   end function toSl;

   signal dbg1 : RegType := REG_INIT_C;

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
         tick;
      end loop;
      assert ( ei.err = e ) report "Write Error" severity failure;
      eo.valid <= '0';
      tick;
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
         tick;
      end loop;
      v := ei.rdat;
      assert ( ei.err = e ) report "Read Error" severity failure;
      eo.valid <= '0';
      tick;
   end procedure rd;

begin

   P_CLK : process is
   begin
      if ( run ) then wait for 10 ns; clk <= not clk; else wait; end if;
   end process P_CLK;

   P_TST : process is
      variable res    : std_logic_vector(7 downto 0);
      variable passed : natural := 0;
   begin
      for i    in 0 to 2 loop
      for j    in 0 to 2 loop
      for k    in 0 to 2 loop
         regClr  <= true;
         adly    <= i;
         a2dly   <= j;
         wdly    <= k;
         tick;
         regClr  <= false;

         wr(regReq, regRep, 12, x"ab");  passed := passed + 1;
         wr(regReq, regRep, 65, x"43");  passed := passed + 1;
         rd(regReq, regRep, 12, res );   passed := passed + 1;
         assert res = x"ab" report "Readback mismatch" severity failure;
         passed := passed + 1;
         rd(regReq, regRep,  1, res );
         passed := passed + 1;
         assert res = x"00" report "Readback not zero" severity failure;
         passed := passed + 1;
         rd(regReq, regRep, 65, res );
         passed := passed + 1;
         assert res = x"43" report "Extended Readback mismatch" severity failure;
         passed := passed + 1;
         rd(regReq, regRep, 64, res );
         passed := passed + 1;
         assert res = x"00" report "Extended Readback not zero" severity failure;
         passed := passed + 1;
         tick;
         tick;
      end loop;
      end loop;
      end loop;

      for i in 0 to 5 loop
      for j in 0 to 2 loop
      for k in 0 to 2 loop
      for l in 0 to 2 loop
         jam   <= i;
         adly  <= j;
         a2dly <= k;
         wdly  <= l;
         tick;
         wr(regReq, regRep, 12, x"ab", toSl(jam < 3 + adly +         wdly));
         passed := passed + 1;
         wr(regReq, regRep, 65, x"ab", toSl(jam < 4 + adly + a2dly + wdly));
         passed := passed + 1;
         rd(regReq, regRep, 12, res  , toSl(jam < 4 + adly               ));
         passed := passed + 1;
         rd(regReq, regRep, 65, res  , toSl(jam < 5 + adly + a2dly       ));
         passed := passed + 1;
      end loop;
      end loop;
      end loop;
      end loop;
      jam   <= -1;
      adly  <= 0;
      a2dly <= 0;
      wdly  <= 0;
      tick;

      startTx <= 0;
      checkRx <= checkRx + 1;
      tick;
      startTx <= -1;
      for i in 0 to 8 loop
         tick;
      end loop;
      -- start a back-to-back read/TX operation
      startTxBB <= 3;
      checkRx   <= checkRx + 1;
      rd(regReq, regRep, 0, res);
      startTxBB <= -1;
      for i in 0 to 10 loop
         tick;
      end loop;

      -- DATA0 transaction (crc16 verification)
      startTx <= DATA0_START_IDX_C;
      checkRx <= checkRx + 1;
      tick;
      startTx <= -1;
      for i in 0 to 30 loop
         tick;
      end loop;

      assert checkRx = tokSeen report "Token count mismatch" severity warning;
      passed := passed + checkRx;

      sndPkt( sndIdx, ulpiTxReq );

      run <= false;

      report integer'image(passed) & " TESTS PASSED" severity note;
      wait;
   end process P_TST;

   U_DUT : entity work.UlpiIO
      generic map (
         GEN_ILA_G   => false
      )
      port map (
         rst         => rst,
         clk         => clk,
         stp         => stp,
         dir         => dir,
         nxt         => nxt,
         dat         => dat,
         regReq      => regReq,
         regRep      => regRep,
         ulpiRx      => ulpiRx,
         ulpiTxReq   => ulpiTxReq,
         ulpiTxRep   => ulpiTxRep
      );

   U_PKTDUT : entity work.Usb2PktRx
      port map (
         clk         => clk,
         rst         => rst,
         ulpiRx      => ulpiRx,
         pktHdr      => pktHdr,
         rxData      => rxData
      );

   P_FAKE : process ( clk ) is
      procedure PROCJAM(variable v : inout RegType) is
      begin
         v       := v;
         if ( v.jam > 0 ) then
            if ( v.jam = 1 ) then
               v.dir   := '1';
               v.nxt   := '1';
               v.state := JAMMED;
            end if;
            v.jam := v.jam - 1;
         end if;
      end procedure PROCJAM;

      procedure doStartTx(variable v : inout RegType) is
      begin
         v       := v;
         v.dir   := '1';
         v.nxt   := '1';
         v.state := RXCMD;
         v.txIdx := startTx;
         v.dat   := (others => 'Z');
      end procedure doStartTx;

      variable v : RegType;
   begin
      v := dbg1;
      if ( rising_edge( clk ) ) then
         v.nxt := '0';
         if ( regClr ) then
            regs    <= (others => (others => '0'));
            extRegs <= (others => (others => '0'));
         end if;

         PROCJAM(v);

         case ( v.state ) is
            when RESET =>
               if ( v.cnt = 0 ) then
                  v.cnt   := 3;
                  v.state := IDLE;
                  v.dir   := '0';
               else
                  v.cnt   := v.cnt - 1;
               end if;

            when JAMMED =>
               v.dir := '1';
               v.nxt := '1';
               if ( ( regReq.valid and regRep.ack ) = '1' ) then
                  v.dir   := '0';
                  v.nxt   := '0';
                  v.state := IDLE;
                  v.jam   := 0;
               end if;
              
            when IDLE  =>
               if ( startTx >= 0 ) then
                  doStartTx( v );
               elsif ( dat(7) = '1' ) then
                  v.add   := to_integer( unsigned( dat(5 downto 0) ) );
                  v.ext   := (dat(5 downto 0) = "101111");
                  v.isRd  := (dat(6) = '1');
                  v.cnt   := adly;
                  v.jam   := jam;
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
                  PROCJAM(v);
               elsif ( dat(6) = '1' ) then
                  -- TXCMD
                  v.nxt   := '1';
                  v.state := RX;
                  v.dly   := 0;
                  v.cnt   := v.dly;
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
                  v.jam   := 0;
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
                  v.jam   := 0;
               else
                  if ( v.cnt = 1 ) then
                     v.dat   := (others => 'Z');
                     if ( startTxBB >= 0 ) then
                        -- a fake back-to-back read/TX; in reality TX and register access should be driven
                        -- by parallel processes but we use just one (legacy reasons, the test bed was augmented
                        -- post factum...
                        v.dat   := x"11";
                        v.state := RXCMD;
                        v.txIdx := startTxBB;
                     end if;
                  end if;
                  v.cnt   := v.cnt - 1;
               end if;

            when RXCMD =>
               if ( v.nxt = '1' ) then
                  v.nxt   := '0';
                  v.dat   := x"11"; -- rxActive and bogus line state
               else
                  v.nxt   := '1';
                  v.dat   := txVec( v.txIdx )(7 downto 0);
                  v.state := TX;
               end if;

            when TX =>
               if ( txVec( v.txIdx )(8) = '1' ) then
                  v.nxt   := '0';
                  v.state := IDLE;
                  v.dir   := '0';
                  v.dat   := (others => 'Z');
               else
                  v.nxt   := '1';
                  v.txIdx := v.txIdx + 1;
                  v.dat   := txVec(v.txIdx)(7 downto 0);
               end if;

            when RX =>
               if ( v.cnt = 0 ) then
                  v.nxt   := '1';
                  v.cnt   := v.dly;
               else
                  v.cnt   := v.cnt - 1;
               end if;
               if ( (nxt or stp) = '1' ) then
                  assert dat = rxVec(v.rxIdx)(7 downto 0) report "TXCMD mismatch" severity failure;
                  v.rxIdx := v.rxIdx + 1;
               end if;
               if ( stp = '1' ) then
                  v.state := IDLE;
                  v.nxt   := '0';
               end if;
         
         end case;
         dbg1 <= v;
      end if;
   end process P_FAKE;

   P_JAM : process ( dbg1, jam, dat, clk ) is
   begin
      if ( dbg1.state = IDLE and jam = 0 ) then
         if ( jamdir = '0' and dat(7) = '1' ) then
            jamdir <= '1';
         end if;
      else
         jamdir <= '0';
      end if;
      if ( rising_edge( clk ) ) then
         jamdir <= '0';
      end if;
   end process P_JAM;

   dir <= dbg1.dir or jamdir;
   nxt <= dbg1.nxt or jamdir;

   P_DAT : process ( dbg1 ) is
   begin
      if ( dbg1.dir = '1' ) then
         dat <= dbg1.dat;
      else
         dat <= (others => 'Z');
      end if;
   end process P_DAT;

   P_RX : process ( clk ) is
      constant CMP1_C  : std_logic_vector := txVec(2)(2 downto 0) & txVec(1)(7 downto 0);
      constant CMP2_C  : std_logic_vector := txVec(5)(2 downto 0) & txVec(4)(7 downto 0);
      variable dataIdx : integer          := -1;
   begin
      if ( rising_edge( clk ) ) then
         if ( checkRx = 0 ) then
            assert pktHdr.valid = '0' report "Unexpectedly valid token" severity failure;
         else
            if ( pktHdr.valid = '1' ) then
               tokSeen <= tokSeen + 1;
               if ( checkRx = 1 ) then
                  assert pktHdr.pid = USB_PID_TOK_SOF_C report "unexpected token1"      severity failure;
                  assert pktHdr.tokDat = CMP1_C report "unexpected token1 data" severity failure;
               elsif ( checkRx = 2 ) then
                  assert pktHdr.pid = USB_PID_TOK_OUT_C report "unexpected token2"      severity failure;
                  assert pktHdr.tokDat = CMP2_C report "unexpected token2 data" severity failure;
               elsif ( checkRx = 3 ) then
                  assert pktHdr.pid = USB_PID_DAT_DATA0_C report "unexpected pid /= DATA0"      severity failure;
                  dataIdx := DATA0_START_IDX_C + 1;
               end if;
            end if;
            if ( dataIdx >= 0 ) then
               if ( rxData.don = '1' ) then
                  assert rxData.err = '0' report "DATA0 reception error" severity failure;
                  dataIdx := -1;
               elsif ( rxData.vld = '1' ) then
                  assert txVec(dataIdx)(7 downto 0) = rxData.dat report "DATA0 reception mismatch" severity failure;
                  dataIdx := dataIdx + 1;
               end if;
            else
               assert rxData.vld = '0' report "rxData unexpectedly valid" severity failure;
            end if;
         end if;
      end if;
   end process P_RX;

end architecture Sim;
