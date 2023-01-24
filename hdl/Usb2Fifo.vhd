-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

-- Bram based FIFO

entity Usb2Fifo is
   generic (
      DATA_WIDTH_G : natural;
      LD_DEPTH_G   : natural;
      LD_TIMER_G   : positive := 24;   -- at least one bit is required for internal reasons
      OUT_REG_G    : natural range 0 to 1 := 0;
      EXACT_THR_G  : boolean  := false;
      ASYNC_G      : boolean  := false
   );
   port (
      wrClk        : in  std_logic;
      wrRst        : in  std_logic := '0';
      wrRstOut     : out std_logic;

      din          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      wen          : in  std_logic;
      full         : out std_logic;
      -- fill level as seen by the write clock
      wrFilled     : out unsigned(LD_DEPTH_G downto 0);

      rdClk        : in  std_logic;
      rdRst        : in  std_logic := '0';
      rdRstOut     : out std_logic;
      dou          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
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

   type WrRegType is record
      wrPtr     : IdxType;
   end record WrRegType;

   constant WR_REG_INIT_C : WrRegType := (
      wrPtr     => ( others => '0' )
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
      if ( occupied(x, rp) = FULL_C ) then
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
   signal fifoRen           : std_logic;
   signal advanceReg        : std_logic;
   signal advanceMem        : std_logic;

   signal timerStrobe       : std_logic := '0';

   signal fillOff           : IdxType   := (others => '0');

   signal wrRstLoc          : std_logic;
   signal rdRstLoc          : std_logic;

begin

   assert not ( EXACT_THR_G and ASYNC_G ) report "Cannot compute exact level in ASYNC mode" severity failure;

   G_SYNC : if ( not ASYNC_G ) generate
      wrPtrOut    <= rWr.wrPtr;
      rdPtrOut    <= rRd.rdPtr;
      timerStrobe <= fifoWen;
      wrRstLoc    <= wrRst or rdRst;
      rdRstLoc    <= wrRst or rdRst;
   end generate G_SYNC;

   G_ASYNC : if ( ASYNC_G ) generate
      constant A_W_C          : natural := IdxType'length + 2;
      constant B_W_C          : natural := IdxType'length + 2;
      signal cenA             : std_logic;
      signal cenB             : std_logic;
      signal dinA             : std_logic_vector(A_W_C - 1 downto 0);
      signal douA             : std_logic_vector(B_W_C - 1 downto 0);
 
      signal dinB             : std_logic_vector(B_W_C - 1 downto 0);
      signal douB             : std_logic_vector(A_W_C - 1 downto 0);

      signal resettingA       : std_logic := '0'; -- hold reset state triggered by reset on A side
      signal resettingB       : std_logic := '0'; -- hold reset state triggered by reset on B side

      signal rstAFeedback     : std_logic;        -- resettingA did a full round trip
      signal rstASeenAtB      : std_logic;        -- resettingA output on B side

      signal rstBFeedback     : std_logic;        -- resettingB did a full round trip
      signal rstBSeenAtA      : std_logic;        -- resettingB output on A side
   begin

      dinA         <= rstBSeenAtA & resettingA & std_logic_vector( rWr.wrPtr );
      dinB         <= rstASeenAtB & resettingB & std_logic_vector( rRd.rdPtr );

      rdPtrOut     <= IdxType( douA( rdPtrOut'range ) );
      rstBSeenAtA  <= douA( Idxtype'length + 0 );
      rstAFeedback <= douA( IdxType'length + 1 );

      wrPtrOut     <= IdxType( douB( wrPtrOut'range ) );
      rstASeenAtB  <= douB( Idxtype'length + 0 );
      rstBFeedback <= douB( IdxType'length + 1 );

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

   fifoFull   <= isFull( rWr, rdPtrOut );
   fifoWen    <= not isFull( rWr, rdPtrOut ) and wen;
   fifoEmpty  <= not rRd.vld(0) or rinRd.delayRd;

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

   P_WR_COMB : process ( rWr, fifoWen ) is
      variable v : WrRegType;
   begin
      v := rWr;

      if ( fifoWen = '1' ) then
         v.wrPtr    := rWr.wrPtr + 1;
      end if;

      rinWr <= v;
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
         DATA_WIDTH_G => DATA_WIDTH_G,
         ADDR_WIDTH_G => LD_DEPTH_G,
         EN_REGB_G    => (OUT_REG_G > 0)
      )
      port map (
         clka         => wrClk,
         ena          => open,
         wea          => fifoWen,
         addra        => rWr.wrPtr(rWr.wrPtr'left - 1 downto 0),
         rdata        => open,
         wdata        => din,

         clkb         => rdClk,
         enb          => advanceMem,
         ceb          => advanceReg,
         web          => open,
         addrb        => rRd.rdPtr(rRd.rdPtr'left - 1 downto 0),
         rdatb        => dou,
         wdatb        => open
      );

   empty    <= fifoEmpty;
   full     <= fifoFull;
   rdFilled <= occupied( rRd, wrPtrOut );
   wrFilled <= occupied( rWr, rdPtrOut );
   wrRstOut <= wrRstLoc;
   rdRstOut <= rdRstLoc;

end architecture Impl;
