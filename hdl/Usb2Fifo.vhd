-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Bram based FIFO

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2UtilPkg.all;

entity Usb2Fifo is
   generic (
      DATA_WIDTH_G : natural;
      LD_DEPTH_G   : natural;
      LD_TIMER_G   : positive := 24;   -- at least one bit is required for internal reasons
      OUT_REG_G    : natural range 0 to 1 := 0;
      EXACT_THR_G  : boolean  := false;
      ASYNC_G      : boolean  := false;
      -- extra (user) bits synchronized from the write -> read side
      XTRA_W2R_G   : natural  := 0;
      -- extra (user) bits synchronized from the read  -> write side
      XTRA_R2W_G   : natural  := 0;
      -- observe framing by the 'don' flag which signals the end
      -- of the incoming frame (din is not stored during the 'don'
      -- cycle) and prepend a 2-byte header representing the frame
      -- size (LSB first) on the output. 'sof' is asserted when
      -- transmitting the first header byte.
      FRAMED_G     : boolean  := false
   );
   port (
      wrClk        : in  std_logic;
      wrRst        : in  std_logic := '0';
      wrRstOut     : out std_logic;
      wrXtraInp    : in  std_logic_vector(XTRA_W2R_G - 1 downto 0) := (others => '0');
      wrXtraOut    : out std_logic_vector(XTRA_R2W_G - 1 downto 0);

      din          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      don          : in  std_logic := '0';
      wen          : in  std_logic;
      full         : out std_logic;
      -- fill level as seen by the write clock
      wrFilled     : out unsigned(LD_DEPTH_G downto 0);

      rdClk        : in  std_logic;
      rdRst        : in  std_logic := '0';
      rdRstOut     : out std_logic;
      rdXtraInp    : in  std_logic_vector(XTRA_R2W_G - 1 downto 0) := (others => '0');
      rdXtraOut    : out std_logic_vector(XTRA_W2R_G - 1 downto 0);
      dou          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      sof          : out std_logic := '0';
      ren          : in  std_logic;
      empty        : out std_logic;

      -- fill level as seen by the read clock
      rdFilled     : out unsigned(LD_DEPTH_G downto 0);

      -- at least ( minFill + 1 ) elements must be stored before reading may
      -- start
      minFill      : in  unsigned(LD_DEPTH_G - 1 downto 0) := (others => '0');
      -- if filled to less than 'minFill' then readout is started 'timer' (read) clock
      -- ticks after the last item was written; all-ones waits forever
      timer        : in  unsigned(LD_TIMER_G - 1 downto 0) := (others => '0')
   );
end entity Usb2Fifo;

architecture Impl of Usb2Fifo is

   -- extra bit
   subtype IdxType is unsigned(LD_DEPTH_G downto 0);

   constant FULL_C    : IdxType                           := to_unsigned(2**(LD_DEPTH_G), LD_DEPTH_G + 1);
   constant FOREVER_C : unsigned(LD_TIMER_G - 1 downto 0) := (others => '1');
   constant HSZ_C     : natural                           := 2;
   constant DWIDTH_C  : natural                           := DATA_WIDTH_G + ite( FRAMED_G, 1, 0 );

   type RdRegType is record
      rdPtr     : IdxType;
      vld       : std_logic_vector( OUT_REG_G + 1 - 1 downto 0);
      timer     : unsigned(LD_TIMER_G - 1 downto 0);
      delayRd   : std_logic;
   end record RdRegType;

   constant RD_REG_INIT_C : RdRegType := (
      rdPtr     => ( others => '0' ),
      vld       => ( others => '0' ),
      timer     => ( others => '0' ),
      delayRd   => '1'
   );

   type WrState is ( FWD, H2 );

   function wrPtrSet(
      constant h : IdxType := (others => '0')
   ) return IdxType is
   begin
      if ( FRAMED_G ) then
         return h + HSZ_C;
      else
         return h;
      end if;
   end function wrPtrSet;


   type WrRegType is record
      state     : WrState;
      wrPtr     : IdxType;
      hdPtr     : IdxType;
      len       : IdxType;
   end record WrRegType;

   constant WR_REG_INIT_C : WrRegType := (
      state     => FWD,
      wrPtr     => wrPtrSet,
      hdPtr     => ( others => '0' ),
      len       => ( others => '0' )
   );

   signal wrPtrOut              : IdxType := (others => '0');
   signal rdPtrOut              : IdxType := (others => '0');

   function occupied(constant x : in RdRegType; constant wp : in IdxType) return IdxType is
   begin
      return wp - x.rdPtr;
   end function occupied;

   function occupied(constant x : in WrRegType; constant rp : in IdxType) return IdxType is
   begin
      return x.wrPtr - rp;
   end function occupied;

   function isFull(constant x : in WrRegType; constant rp : in IdxType) return std_logic is
   begin
      if ( occupied(x, rp) >= FULL_C ) then
         return '1';
      else
         return '0';
      end if;
   end function isFull;

   function isEmpty(constant x : in RdRegType; constant wp : in IdxType) return std_logic is
   begin
      if ( wp = x.rdPtr ) then
         return '1';
      else
         return '0';
      end if;
   end function isEmpty;

   signal rRd               : RdRegType := RD_REG_INIT_C;
   signal rinRd             : RdRegType;

   signal rWr               : WrRegType := WR_REG_INIT_C;
   signal rinWr             : WrRegType;

   signal fifoEmpty         : std_logic;
   signal fifoFull          : std_logic;
   signal fifoWen           : std_logic;
   signal fifoDin           : std_logic_vector(DWIDTH_C - 1 downto 0);
   signal fifoDou           : std_logic_vector(DWIDTH_C - 1 downto 0);
   signal fifoDinLoc        : std_logic_vector(DWIDTH_C - 1 downto 0);
   signal fifoRen           : std_logic;
   signal fifoWrAddr        : unsigned(LD_DEPTH_G - 1 downto 0);
   signal advanceReg        : std_logic;
   signal advanceMem        : std_logic;
   signal fifoWBsy          : std_logic := '0';

   signal timerStrobe       : std_logic := '0';

   signal fillOff           : IdxType   := (others => '0');

   signal wrRstLoc          : std_logic;
   signal rdRstLoc          : std_logic;

begin

   assert not ( EXACT_THR_G and ASYNC_G ) report "Cannot compute exact level in ASYNC mode" severity failure;

   assert not FRAMED_G or DATA_WIDTH_G >= 8 report "FRAMED_G needs DATA_WIDTH_G >= 8" severity failure;

   G_SYNC : if ( not ASYNC_G ) generate

      G_FRMD : if ( FRAMED_G ) generate
         wrPtrOut    <= rWr.hdPtr;
      end generate G_FRMD;
      G_NFRMD : if ( not FRAMED_G ) generate
         wrPtrOut    <= rWr.wrPtr;
      end generate G_NFRMD;

      rdPtrOut    <= rRd.rdPtr;
      timerStrobe <= fifoWen;
      wrRstLoc    <= wrRst or rdRst;
      rdRstLoc    <= wrRst or rdRst;
      wrXtraOut   <= rdXtraInp;
      rdXtraOut   <= wrXtraInp;
   end generate G_SYNC;

   G_ASYNC : if ( ASYNC_G ) generate
      constant A_W_C          : natural := IdxType'length + 2 + XTRA_W2R_G;
      constant B_W_C          : natural := IdxType'length + 2 + XTRA_R2W_G;
      signal cenA             : std_logic;
      signal cenB             : std_logic;
      signal dinA             : std_logic_vector(A_W_C - 1 downto 0);
      signal douA             : std_logic_vector(B_W_C - 1 downto 0) := (others => '0');

      signal dinB             : std_logic_vector(B_W_C - 1 downto 0);
      signal douB             : std_logic_vector(A_W_C - 1 downto 0) := (others => '0');
      signal wrPtrInp         : IdxType := (others => '0');

      -- signal an initial reset to make sure any side waits for the other one
      signal resettingA       : std_logic := '1'; -- hold reset state triggered by reset on A side
      signal resettingB       : std_logic := '1'; -- hold reset state triggered by reset on B side

      signal rstAFeedback     : std_logic;        -- resettingA did a full round trip
      signal rstASeenAtB      : std_logic;        -- resettingA output on B side

      signal rstBFeedback     : std_logic;        -- resettingB did a full round trip
      signal rstBSeenAtA      : std_logic;        -- resettingB output on A side
   begin

      G_FRMD : if ( FRAMED_G ) generate
         wrPtrInp <= rWr.hdPtr;
      end generate G_FRMD;
      G_NFRMD : if ( not FRAMED_G ) generate
         wrPtrInp <= rWr.wrPtr;
      end generate G_NFRMD;

      dinA         <= wrXtraInp & rstBSeenAtA & resettingA & std_logic_vector( wrPtrInp  );
      dinB         <= rdXtraInp & rstASeenAtB & resettingB & std_logic_vector( rRd.rdPtr );

      rdPtrOut     <= IdxType( douA( rdPtrOut'range ) );
      rstBSeenAtA  <= douA( Idxtype'length + 0 );
      rstAFeedback <= douA( IdxType'length + 1 );
      wrXtraOut    <= douA( IdxType'length + 2 + wrXtraOut'length - 1 downto IdxType'length + 2 );

      wrPtrOut     <= IdxType( douB( wrPtrOut'range ) );
      rstASeenAtB  <= douB( Idxtype'length + 0 );
      rstBFeedback <= douB( IdxType'length + 1 );
      rdXtraOut    <= douB( IdxType'length + 2 + rdXtraOut'length - 1 downto IdxType'length + 2 );

      rdRstLoc     <= rdRst or resettingB or rstASeenAtB;
      wrRstLoc     <= wrRst or resettingA or rstBSeenAtA;

      U_CC_SYNC : entity work.Usb2MboxSync
         generic map (
            STAGES_A2B_G => 3,
            STAGES_B2A_G => 3,
            DWIDTH_A2B_G => dinA'length,
            DWIDTH_B2A_G => dinB'length,
            OUTREG_A2B_G => true,
            OUTREG_B2A_G => true
         )
         port map (
            clkA         => wrClk,
            cenA         => cenA,
            dinA         => dinA,
            douA         => douA,

            clkB         => rdClk,
            cenB         => cenB,
            dinB         => dinB,
            douB         => douB
         );

      P_A2B : process ( rdClk ) is
      begin
        if ( rising_edge( rdClk ) ) then
           if ( rdRst = '1' ) then
              resettingB <= '1';
           elsif ( rstBFeedback = '1' ) then
              -- reset has done one round trip
              resettingB <= '0';
           end if;
        end if;
      end process P_A2B;

      P_B2A : process ( wrClk ) is
      begin
        if ( rising_edge( wrClk ) ) then
           if ( wrRst = '1' ) then
              resettingA <= '1';
           elsif ( rstAFeedback = '1' ) then
              -- reset has done one round trip
              resettingA <= '0';
           end if;
        end if;
      end process P_B2A;


   end generate G_ASYNC;

   -- in H2 state when the second part of the header is written we cannot
   -- accept data; when 'don' is asserted (first part of header being written)
   -- input data are ignored anyways.
   fifoFull   <= isFull( rWr, rdPtrOut ) or wrRstLoc or toSl( rWr.state = H2 );
   fifoEmpty  <= not rRd.vld(0) or rinRd.delayRd or rdRstLoc;

   advanceReg <= not rRd.vld(0) or (ren and not rinRd.delayRd);
   -- if there is no register then advanceMem == advanceReg
   advanceMem <= not rRd.vld(rRd.vld'left) or advanceReg;

   G_THR_EXACT : if ( EXACT_THR_G ) generate
      P_FILL_OFF : process ( rRd ) is
         variable v : IdxType;
      begin
         v := (others => '0');
         for i in rRd.vld'range loop
            if ( rRd.vld(i) = '1' ) then
               v := v + 1;
            end if;
         end loop;
         fillOff <= v;
      end process P_FILL_OFF;
   end generate G_THR_EXACT;

   P_RD_COMB : process ( rRd, minFill, fillOff, timer, advanceReg, advanceMem, wrPtrOut, timerStrobe ) is
      variable v : RdRegType;
   begin
      v := rRd;

      if ( rRd.timer /= 0 ) then
         if ( timer < rRd.timer ) then
            -- allow reducing on the fly
            v.timer    := timer;
         elsif ( rRd.timer /= FOREVER_C ) then
            v.timer := rRd.timer - 1;
         end if;
      end if;

      if ( rRd.delayRd = '1' ) then
         if ( occupied( rRd, wrPtrOut ) + fillOff > minFill or ( ( rRd.timer = 0 ) and ( rRd.vld(0) = '1' ) ) ) then
            v.delayRd := '0';
         end if;
      else
         v.delayRd := not rRd.vld(0);
      end if;

      -- advance register pipeline while there is space (rRd.vld(0) = '0') or
      -- the last entry is popped (rRd.vld(0) = '1' and ren = '1')

      if ( advanceMem = '1' ) then
         v.vld(v.vld'left) := not isEmpty( rRd, wrPtrOut );
         if ( isEmpty( rRd, wrPtrOut ) = '0' ) then
            v.rdPtr := rRd.rdPtr + 1;
         end if;
      end if;
      if ( advanceReg = '1' ) then
         v.vld := v.vld(v.vld'left) & rRd.vld(rRd.vld'left downto 1);
      end if;

      if ( timerStrobe = '1' ) then
         -- min. timer is 1 in order to fill pipeline in "FILL" state
         v.timer    := timer;
      end if;

      rinRd <= v;
   end process P_RD_COMB;

   P_WR_COMB : process ( rWr, rdPtrOut, fifoDinLoc, wen, din, don ) is
      variable v  : WrRegType;
      variable wr : std_logic;
      variable l  : unsigned(15 downto 0);
   begin
      v := rWr;

      fifoDin    <= fifoDinLoc;
      wr         := not isFull( rWr, rdPtrOut ) and wen;
      fifoWrAddr <= rWr.wrPtr( fifoWrAddr'range );

      if ( wr = '1' ) then
         v.len      := rWr.len   + 1;
      end if;

      l := resize( rWr.len, l'length );

      if ( FRAMED_G ) then
         case ( rWr.state ) is
            when FWD =>
               if ( ( not isFull( rWr, rdPtrOut ) and don ) = '1' ) then
                  if DATA_WIDTH_G >= 16 then
                     fifoDin    <= '1' & std_logic_vector( resize(l, DATA_WIDTH_G ) );
                     v.len      := (others => '0');
                     v.hdPtr    := rWr.wrPtr;
                  else
                     fifoDin    <= '1' & std_logic_vector( resize(l(7 downto 0), DATA_WIDTH_G ) );
                     v.len      := rWr.len;
                     v.hdPtr    := rWr.hdPtr + 1;
                     v.state    := H2;
                  end if;
                  wr         := '1';
                  fifoWrAddr <= rWr.hdPtr(fifoWrAddr'range);
               end if;
            when H2 =>
               fifoDin       <= '0' & std_logic_vector( resize(l(15 downto 8), DATA_WIDTH_G ) );
               wr            := '1';
               v.len         := (others => '0');
               fifoWrAddr    <= rWr.hdPtr(fifoWrAddr'range);
               v.hdPtr       := rWr.wrPtr - 1;
               v.state       := FWD;
         end case;
      end if;

      if ( wr = '1' ) then
         v.wrPtr    := rWr.wrPtr + 1;
      end if;

      fifoWen  <= wr;
      rinWr    <= v;
   end process P_WR_COMB;


   P_RD_SEQ : process ( rdClk ) is
   begin
      if ( rising_edge( rdClk ) ) then
         if ( rdRstLoc = '1' ) then
            rRd <= RD_REG_INIT_C;
         else
            rRd <= rinRd;
         end if;
      end if;
   end process P_RD_SEQ;

   P_WR_SEQ : process ( wrClk ) is
   begin
      if ( rising_edge( wrClk ) ) then
         if ( wrRstLoc = '1' ) then
            rWr <= WR_REG_INIT_C;
         else
            rWr <= rinWr;
         end if;
      end if;
   end process P_WR_SEQ;

   U_BRAM : entity work.Usb2Bram
      generic map (
         DATA_WIDTH_G => DWIDTH_C,
         ADDR_WIDTH_G => LD_DEPTH_G,
         EN_REGB_G    => (OUT_REG_G > 0)
      )
      port map (
         clka         => wrClk,
         ena          => open,
         wea          => fifoWen,
         addra        => fifoWrAddr,
         rdata        => open,
         wdata        => fifoDin,

         clkb         => rdClk,
         enb          => advanceMem,
         ceb          => advanceReg,
         web          => open,
         addrb        => rRd.rdPtr(rRd.rdPtr'left - 1 downto 0),
         rdatb        => fifoDou,
         wdatb        => open
      );

   fifoDinLoc(din'range) <= din;

   G_FRMD_DIO : if ( FRAMED_G ) generate
      fifoDinLoc(fifoDinLoc'left) <= '0';
      sof                         <= fifoDou(fifoDou'left);
   end generate G_FRMD_DIO;


   dou      <= fifoDou(dou'range);
   empty    <= fifoEmpty;
   full     <= fifoFull;
   rdFilled <= occupied( rRd, wrPtrOut );
   wrFilled <= occupied( rWr, rdPtrOut );
   wrRstOut <= wrRstLoc;
   rdRstOut <= rdRstLoc;

end architecture Impl;
