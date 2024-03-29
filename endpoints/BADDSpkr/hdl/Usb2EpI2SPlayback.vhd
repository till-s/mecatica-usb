-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Example of an isochronous endpoint: SSI audio playback;
-- uses a Usb2Fifo for crossing from the USB into the
-- audio domain.
-- The feedback endpoint monitors the FIFO fill level and
-- reports the effective output sampling frequency based
-- on the fill level. A simple bang/bang scheme is used.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;

entity Usb2EpI2SPlayback is
   generic (
      -- audio sample size in byte (per channel)
      SAMPLE_SIZE_G       : natural range 1 to 4 := 2;
      -- stereo/mono
      NUM_CHANNELS_G      : natural range 1 to 2 := 2;
      -- bitclock multiplier, i.e., how many bit clocks
      -- per audio slot (must be >= SAMPLE_SIZE_G * NUM_CHANNELS_G * 8)
      BITCLK_MULT_G       : natural              := 64;
      SAMPLING_FREQ_G     : natural              := 48000;
      -- service interval (ms), for freq. measurement (1000ms per usb spec)
      SI_FREQ_G           : natural              := 1000;
      MARK_DEBUG_G        : boolean              := false;
      -- debug signals in BCLK domain
      MARK_DEBUG_BCLK_G   : boolean              := false
   );
   port (
      usb2Clk             : in  std_logic;
      usb2Rst             : in  std_logic;
      usb2RstBsy          : out std_logic;
      usb2Rx              : in  Usb2RxType;
      usb2EpIb            : in  Usb2EndpPairObType;
      usb2EpOb            : out Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
      usb2DevStatus       : in  Usb2DevStatusType;

      i2sBCLK             : in  std_logic;
      i2sPBLRC            : in  std_logic;
      i2sPBDAT            : out std_logic
   );

   constant MARK_DEBUG_C            : string  := toStr(MARK_DEBUG_G);
   constant MARK_DEBUG_BCLK_C       : string  := toStr(MARK_DEBUG_BCLK_G);

   attribute MARK_DEBUG of usb2EpOb : signal is MARK_DEBUG_C; 
   attribute MARK_DEBUG of usb2EpIb : signal is MARK_DEBUG_C; 

end entity Usb2EpI2SPlayback;

architecture Impl of Usb2EpI2SPlayback is

   constant BYTESpSMP_C            : natural := SAMPLE_SIZE_G * NUM_CHANNELS_G;

   constant FRMSZ_C                : natural := BYTESpSMP_C * SAMPLING_FREQ_G / SI_FREQ_G;

   constant LD_FIFO_DEPTH_C        : natural := 11;

   function max(constant a, b: integer) return integer is
   begin
      if ( a > b ) then return a; else return b; end if;
   end function max;

   function nbits(constant x : in integer) return integer is
      variable v : integer;
      variable s : integer;
   begin
      s := 2;
      v := 1;
      while x >= s loop
         v := v + 1;
         s := s * 2;
      end loop;
      return v;
   end function nbits;

   constant LD_SOF_CNT_FS_C       : natural := 0;
   constant LD_SOF_CNT_HS_C       : natural := 3;

   constant SOF_CNT_FS_C          : natural := 2**LD_SOF_CNT_FS_C;
   constant SOF_CNT_HS_C          : natural := 2**LD_SOF_CNT_HS_C;

   constant LD_SOF_CNT_MAX_C      : natural := max( LD_SOF_CNT_FS_C, LD_SOF_CNT_HS_C );

   -- this is correct for hi and full speed; samples / frame (fs) vs samples/uframe (hs)
   -- but the HS format is 16.16 (vs full-speed 10.13), i.e., the 3-bit left shift due
   -- to formatting cancels the division by 8 due to the higher ref. frequency.
   constant RATE_INIT_C           : std_logic_vector(31 downto 0) :=
      std_logic_vector( to_unsigned( SAMPLING_FREQ_G * 2**13 / SI_FREQ_G, 32 ) );

   -- for now we assume sample_size < 8
   constant COUNT_W_C             : natural := 3;

   subtype  BitCountType  is signed(1 + COUNT_W_C + 3 - 1 downto 0);
   subtype  BytCountType  is signed(1 + COUNT_W_C     - 1 downto 0);

   -- we count down to -1 with all states active and thus subtract 2
   function BITCNT_F return BitCountType is
   begin
      return to_signed( 8*SAMPLE_SIZE_G - 2, BitCountType'length);
   end function BITCNT_F;

   function BYTCNT_F return BytCountType is
   begin
      return to_signed( SAMPLE_SIZE_G - 1, BytCountType'length);
   end function BYTCNT_F;

   function expired(constant x : signed) return boolean is
   begin
      return x(x'left) = '1';
   end function expired;

   -- since we don't know when exactly (within a service-interval) the next
   -- packet will arrive we must buffer at least 2 packets for the worst case
   -- of 1 packet arriving very early and the next very late. Use the feed-back
   -- endpoint to keep the fifo level between MINFILL_C and MAX_FILL_C.

   constant MINFILL_C     : unsigned(LD_FIFO_DEPTH_C downto 0) :=
      to_unsigned( 2**(LD_FIFO_DEPTH_C - 1) - FRMSZ_C, LD_FIFO_DEPTH_C + 1);

   constant MAXFILL_C     : unsigned(LD_FIFO_DEPTH_C downto 0) :=
      to_unsigned( 2**(LD_FIFO_DEPTH_C - 1) + FRMSZ_C, LD_FIFO_DEPTH_C + 1);

   function freq(constant f : in real) return std_logic_vector is
      variable v : std_logic_vector(31 downto 0);
      variable i : integer;
   begin
      i := integer( round( f * 2.0**13 ) );
      v := std_logic_vector( to_unsigned( i, v'length ) );
      return v;
   end function freq;

   function freq(constant f : in natural) return std_logic_vector is
      variable v : unsigned(31 downto 0);
   begin
      v := shift_left( to_unsigned( f, v'length ), 13 );
      return std_logic_vector( v );
   end function freq;

   constant MAXFREQ_C     : std_logic_vector(31 downto 0) := freq( real(SAMPLING_FREQ_G/SI_FREQ_G)*1.001 );
   constant NOMFREQ_C     : std_logic_vector(31 downto 0) := freq( SAMPLING_FREQ_G/SI_FREQ_G );
   constant MINFREQ_C     : std_logic_vector(31 downto 0) := freq( real(SAMPLING_FREQ_G/SI_FREQ_G)*0.999 );

   type StateType         is ( INIT, FILL, RUN );

   type RegType is record
      state               : StateType;
      bitCnt              : BitCountType;
      bytCnt              : BytCountType;
      pblrlst             : std_logic;
      newFrame            : std_logic;
      swpr                : std_logic_vector(8*SAMPLE_SIZE_G - 1 downto 0);
      sreg                : std_logic_vector(8*SAMPLE_SIZE_G - 1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state               => INIT,
      -- must ensure RDEN is low for two cycles after reset is deasserted
      -- use the bit-counter for this
      bitCnt              => to_signed( 3, BitCountType'length ),
      bytCnt              => BYTCNT_F,
      pblrlst             => '0',
      newFrame            => '0',
      swpr                => (others => '0'),
      sreg                => (others => '0')
   );

   signal r               : RegType := REG_INIT_C;
   signal rin             : RegType;

   type   Usb2StateType   is ( IDLE, X0, X1, X2, X3, DON );

   type Usb2RegType is record
      state               : Usb2StateType;
      -- keep a copy so that we are guaranteed to have a consistent
      -- value while transmitting.
      loWater             : std_logic;
      hiWater             : std_logic;
      rate                : std_logic_vector(31 downto 8);
      sofCnt              : signed(LD_SOF_CNT_MAX_C downto 0);
      fifoFill            : unsigned(LD_FIFO_DEPTH_C - 1 downto 0);
      newFrame            : std_logic;
   end record Usb2RegType;

   constant USB2_REG_INIT_C : Usb2RegType := (
      state               => IDLE,
      loWater             => '0',
      hiWater             => '0',
      rate                => RATE_INIT_C(31 downto 8),
      sofCnt              => (others => '1'),
      fifoFill            => (others => '0'),
      newFrame            => '0'
   );

   signal rusb2           : Usb2RegType := USB2_REG_INIT_C;
   signal rinusb2         : Usb2RegType;

   signal u2sUpdTgl       : std_logic := '0';
   signal u2sUpdTglOut    : std_logic;

   signal s2uRenTgl       : std_logic := '0';
   signal s2uRenTglOut    : std_logic;

   signal fifoDin         : std_logic_vector( 8 downto 0);
   signal fifoDou         : std_logic_vector( 8 downto 0);
   signal fifoRen         : std_logic;
   signal fifoWen         : std_logic;
   signal fifoEmpty       : std_logic;
   signal fifoMinFill     : std_logic;
   signal fifoMinFillUsb2 : std_logic;
   signal fifoFull        : std_logic;
   signal fifoAlmostEmpty : std_logic;
   signal fifoAlmostFull  : std_logic;
   signal fifoResetting   : std_logic := '0';
   signal rdFilled        : unsigned(LD_FIFO_DEPTH_C downto 0);
   signal wrFilled        : unsigned(LD_FIFO_DEPTH_C downto 0);

   signal usb2Resetting   : std_logic;
   signal waitForFrame    : std_logic := '1';

   attribute MARK_DEBUG of r                           : signal is MARK_DEBUG_BCLK_C;
   attribute MARK_DEBUG of fifoRen                     : signal is MARK_DEBUG_BCLK_C;
   attribute MARK_DEBUG of fifoEmpty                   : signal is MARK_DEBUG_BCLK_C;
   attribute MARK_DEBUG of fifoAlmostEmpty             : signal is MARK_DEBUG_BCLK_C;
   attribute MARK_DEBUG of fifoResetting               : signal is MARK_DEBUG_BCLK_C;

   attribute MARK_DEBUG of rusb2                       : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoAlmostFull              : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoMinFillUsb2             : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoFull                    : signal is MARK_DEBUG_C;

begin

   B_I2S_SYNCHRONIZERS : block is
   begin
      U_S2U_FIL_SYNC : entity work.Usb2CCSync
         port map (
            clk => usb2Clk,
            d   => fifoMinFill,
            tgl => open,
            q   => fifoMinFillUsb2
         );

      U_S2U_REN_SYNC : entity work.Usb2CCSync
         generic map ( STAGES_G => 3 )
         port map (
            clk => usb2Clk,
            d   => s2uRenTgl,
            tgl => s2uRenTglOut,
            q   => open
         );
   end block B_I2S_SYNCHRONIZERS;

   i2sPBDAT    <= r.sreg(r.sreg'left);
   fifoMinFill <= not fifoAlmostEmpty;

   P_I2S_COMB : process (r, i2sPBLRC, fifoDou, fifoEmpty, fifoMinFill) is
      variable v : RegType;
   begin
      v             := r;
      fifoRen       <= '0';
      v.pblrlst     := i2sPBLRC;

      -- shift
      v.sreg := r.sreg(r.sreg'left - 1 downto 0) & '0';

      case ( r.state ) is
         when INIT =>
            -- must ensure RDEN is low for two cycles after reset is deasserted
            if ( expired( r.bitCnt ) ) then
               v.state  := FILL;
            else
               v.bitCnt := r.bitCnt - 1;
            end if;

         when FILL =>
            v.bitCnt := BITCNT_F;
            v.bytCnt := BYTCNT_F;
            if ( fifoMinFill = '1' ) then
               if ( r.newFrame = '0' ) then
                  -- first-word fall through mode enables us to see the first
                  -- word without popping it; we'll leave it to be picked up in
                  -- RUN state.
                  v.newFrame := fifoDou(8);
               end if;
               if ( v.newFrame = '1' ) then
                  -- we are synced to the first left-channel sample; now wait for pblrc
                  -- to go high (that's right: we'll read the first LCH sample from the fifo
                  -- while an all-zero one is being shifted).
                  if ( ( i2sPBLRC = '1' ) and ( r.pblrlst = '0' ) ) then
                     v.state    := RUN;
                     v.newFrame := '0';
                  end if;
               else
                  -- pop data until we are synchronized to a frame
                  fifoRen <= '1';
               end if;
            end if;

         when RUN =>
            -- fetch the next sample and swap
            if ( not expired( r.bytCnt ) ) then
               if ( fifoEmpty = '1' ) then
                  v.state  := FILL;
               else
                  fifoRen  <= '1';
                  v.swpr   := fifoDou(7 downto 0) & r.swpr(r.swpr'left downto 8);
                  v.bytCnt := r.bytCnt - 1;
                  -- if we see the start of a new check if we are still synchronized
                  if ( fifoDou(8) = '1' ) then
                     -- remember: we read LHC while shifting RHC
                     if ( i2sPBLRC = '0' or r.bytCnt /= BYTCNT_F ) then
                        -- resync!
                        v.state := FILL;
                     end if;
                  end if;
               end if;
            end if;

            if ( expired( r.bitCnt ) ) then
               -- wait for the next LRCLK
               if ( i2sPBLRC /= r.pblrlst ) then
                  v.sreg   := r.swpr;
                  v.bitCnt := BITCNT_F;
                  v.bytCnt := BYTCNT_F;
               end if;
            else
               v.bitCnt := r.bitCnt - 1;
            end if;
      end case;

      rin <= v;
   end process P_I2S_COMB;

   P_I2S_SEQ : process ( i2sBCLK ) is
   begin
      if ( rising_edge( i2sBCLK ) ) then
         if ( fifoResetting = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
         if ( fifoRen = '1' ) then
            s2uRenTgl <= not s2uRenTgl;
         end if;
      end if;
   end process P_I2S_SEQ;

   fifoWen               <= not waitForFrame and usb2EpIb.mstOut.vld;
   fifoDin( 7 downto 0)  <= usb2EpIb.mstOut.dat;
   -- allow reader to synchronize with a frame so that the byte-
   -- alignment remains correct even if we occasionally run full or empty
   fifoDin( 8 )          <= rusb2.newFrame;

   P_RST_USB : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( usb2Resetting = '1' ) then
            waitForFrame <= '1';
         elsif ( waitForFrame = '1' ) then
            -- sync to the next frame
            if ( usb2EpIb.mstOut.don = '1' ) then
               waitForFrame <= '0';
            end if;
         end if;
      end if;
   end process P_RST_USB;

   P_USB_COMB : process (
      rusb2,
      usb2Rx,
      usb2DevStatus,
      usb2EpIb,
      fifoMinFillUsb2,
      fifoAlmostFull,
      s2uRenTglOut,
      fifoWen
   ) is
      variable v   : Usb2RegType;
      variable f   : std_logic_vector(31 downto 0);
      variable tst : std_logic_vector( 1 downto 0);
   begin
      v                   := rusb2;
      usb2EpOb            <= USB2_ENDP_PAIR_IB_INIT_C;
      usb2EpOb.mstInp.don <= '0';
      usb2EpOb.mstInp.vld <= '1';
      usb2EpOb.mstInp.usr <= "0000"; -- only one microframe
      usb2EpOb.bFramedInp <= '1';    -- dont' use DON for framing

      tst                 := fifoWen & s2uRenTglOut;
      case ( tst ) is
         when "10" => v.fifoFill := rusb2.fifoFill + 1;
         when "01" => v.fifoFill := rusb2.fifoFill - 1;
         when others =>
      end case;

      if ( fifoWen = '1' ) then
         v.newFrame := '0';
      end if;

      if ( usb2EpIb.mstOut.don = '1' ) then
         v.newFrame := '1';
      end if;

      if ( ( usb2Rx.pktHdr.vld = '1' ) and usb2Rx.pktHdr.sof ) then
         -- register fifo levels at SOF time
         if ( rusb2.sofCnt( rusb2.sofCnt'left ) = '1' ) then
            v.loWater := fifoMinFillUsb2;
            v.hiWater := fifoAlmostFull;
            if ( usb2DevStatus.hiSpeed ) then
               v.sofCnt := to_signed( SOF_CNT_HS_C - 2, rusb2.sofCnt'length );
            else
               v.sofCnt := to_signed( SOF_CNT_FS_C - 2, rusb2.sofCnt'length );
            end if;
          else
            v.sofCnt := rusb2.sofCnt - 1;
          end if;
      end if;

      f := NOMFREQ_C;
      if    ( rusb2.loWater = '0' ) then
         f := MAXFREQ_C;
      elsif ( rusb2.hiWater = '1' ) then
         f := MINFREQ_C;
      end if;

      case ( rusb2.state ) is
         when IDLE =>
            v.state             := X0;
            usb2EpOb.mstInp.vld <= '0';

         when X0   =>
            usb2EpOb.mstInp.dat <= f(7 downto 0);

            -- latch the rest to ensure we send consistent data
            v.rate := f(31 downto 8);
            if ( usb2EpIb.subInp.rdy = '1' ) then
               v.state := X1;
            end if;
         when X1 =>
            usb2EpOb.mstInp.dat <= rusb2.rate(15 downto 8);
            if ( usb2EpIb.subInp.rdy = '1' ) then
               v.state := X2;
            end if;
         when X2 =>
            usb2EpOb.mstInp.dat <= rusb2.rate(23 downto 16);
            if ( usb2EpIb.subInp.rdy = '1' ) then
               if ( usb2DevStatus.hiSpeed ) then
                  v.state := X3;
               else
                  v.state := DON;
               end if;
            end if;
         when X3 =>
            usb2EpOb.mstInp.dat <= rusb2.rate(31 downto 24);
            if ( usb2EpIb.subInp.rdy = '1' ) then
               v.state := DON;
            end if;
         when DON =>
            -- deassert 'vld' for one cycle
            usb2EpOb.mstInp.vld <= '0';
            v.state             := X0;
      end case;

      rinusb2 <= v;
   end process P_USB_COMB;

   P_USB_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( usb2Resetting = '1' ) then
            rusb2 <= USB2_REG_INIT_C;
         else
            rusb2 <= rinusb2;
         end if;
      end if;
   end process P_USB_SEQ;

   U_I2S_PLAYBACK_FIFO : entity work.Usb2Fifo
      generic map (
         DATA_WIDTH_G => 9,
         LD_DEPTH_G   => LD_FIFO_DEPTH_C,
         LD_TIMER_G   => 1,
         OUT_REG_G    => 0,
         ASYNC_G      => true
      )
      port map (
         wrClk        => usb2Clk,
         wrRst        => usb2Rst,
         wrRstOut     => usb2Resetting,

         din          => fifoDin,
         wen          => fifoWen,
         full         => fifoFull,
         wrFilled     => wrFilled,

         rdClk        => i2sBCLK,
         rdRst        => open,
         rdRstOut     => fifoResetting,
         dou          => fifoDou,
         ren          => fifoRen,
         empty        => fifoEmpty,
         rdFilled     => rdFilled
      );

   P_FILL_LEVEL : process ( rdFilled, wrFilled ) is
      variable dr : unsigned(rdFilled'range);
      variable dw : unsigned(wrFilled'range);
   begin
      dr := rdFilled  - MINFILL_C;
      fifoAlmostEmpty <= dr(dr'left);
      dw := MAXFILL_C - wrFilled;
      fifoAlmostFull  <= dw(dw'left);
   end process P_FILL_LEVEL;

   usb2RstBsy <= usb2Resetting;

end architecture Impl;
