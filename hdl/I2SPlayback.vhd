-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Example of an isochronous endpoint: SSI audio playback;
-- uses a XILINX FIFO for crossing from the USB into the
-- audio domain.
library ieee;
use     ieee.std_logic_1164.all;

entity I2S_CC_Sync is
   generic (
      STAGES_G : natural := 2
   );
   port (
      clk      : in  std_logic;
      d        : in  std_logic;
      tgl      : out std_logic;
      o        : out std_logic
   );
end entity I2S_CC_Sync;

architecture Impl of I2S_CC_Sync is

   attribute ASYNC_REG  : string;

   signal ccSync        : std_logic_vector(STAGES_G - 1 downto 0) := (others => '0');

   attribute ASYNC_REG  of ccSync : signal is "TRUE";

begin
   P_SYNC : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         ccSync <= ccSync(ccSync'left - 1 downto 0) & d;
      end if;
   end process P_SYNC;

   G_TGL : if ( STAGES_G > 2 ) generate
      tgl <= ccSync(ccSync'left) xor ccSync(ccSync'left - 1);
   end generate G_TGL;

   G_ERR : if ( STAGES_G <= 2 ) generate
      tgl <= '0';
   end generate;

   o <= ccSync(ccSync'left);
end architecture Impl;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;

library unisim;
use     unisim.vcomponents.all;

entity I2SPlayback is
   generic (
      -- audio sample size in byte (per channel)
      SAMPLE_SIZE_G       : natural range 1 to 4 := 3;
      -- stereo/mono
      NUM_CHANNELS_G      : natural range 1 to 2 := 2;
      -- bitclock multiplier, i.e., how many bit clocks
      -- per audio slot (must be >= SAMPLE_SIZE_G * NUM_CHANNELS_G * 8)
      BITCLK_MULT_G       : natural              := 64;
      SAMPLING_FREQ_G     : natural              := 48000;
      -- service interval (ms) for freq. measurement (1000ms per usb spec)
      SI_FREQ_G           : natural              := 1000;
      -- polling interval (ms) for freq. feedback (
      FB_FREQ_G           : natural              := 1000;
      MARK_DEBUG_G        : boolean              := false
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
end entity I2SPlayback;

architecture Impl of I2SPlayback is

   attribute ASYNC_REG    : string;
   attribute MARK_DEBUG   : string;

   constant MARK_DEBUG_C  : string  := toStr(MARK_DEBUG_G);

   constant BYTESpSMP_C   : natural := SAMPLE_SIZE_G * NUM_CHANNELS_G;

   constant FRMSZ_C       : natural := BYTESpSMP_C * SAMPLING_FREQ_G / SI_FREQ_G;

   -- Feedback: we must report our sample rate / service interval.
   -- We count bit-clocks and device by the oversampling rate
   -- Decompose the oversampling into A*2**P where A is odd.
   function extract2(constant x : in natural) return natural is
      variable v : natural;
   begin
      v := x;
      while ( v mod 2 = 0 ) loop
         v := v/2;
      end loop;
      return v;
   end function extract2;

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

   function ite(
      constant hs : in std_logic;
      constant a,b : in integer
   ) return integer is
   begin
      if ( hs = '1' ) then return a; else return b; end if;
   end function ite;

   constant LD_SOF_CNT_FS_C       : natural := 0;
   constant LD_SOF_CNT_HS_C       : natural := 3;

   constant SOF_CNT_FS_C          : natural := 2**LD_SOF_CNT_FS_C;
   constant SOF_CNT_HS_C          : natural := 2**LD_SOF_CNT_HS_C;

   constant LD_SOF_CNT_MAX_C      : natural := max( LD_SOF_CNT_FS_C, LD_SOF_CNT_HS_C );

   constant FODD_C        : natural := extract2( BITCLK_MULT_G );
   constant LD_FODD_C     : natural := nbits( FODD_C );
   -- by setting this to 'nbits' which is actually incorrect if the oversampling
   -- rate is an exact power (e.g., nbits(64) = 7) of two we correct for another
   -- special case (see below) which causes the counter to over-count the rate
   -- by a factor of two in the special case of over-sampling by a power of two.
   -- Together these cancel in LD_SCL_xx_C so that the algorithm still works
   -- for all oversampling rates.
   constant LD_OVRSMP_C   : natural := nbits( BITCLK_MULT_G );

   -- accommodate 12 bits for HS and all oversampling 
   constant LD_RATE_C     : natural := 12 + LD_SOF_CNT_MAX_C + LD_OVRSMP_C + LD_FODD_C;

   -- When measuring the sampling rate we count the bit-clock between SOF events.
   -- At the end we have to divide by the bits/sample. For powers of two this is easy
   -- but the odd factor needs attention (if we want to avoid a divider).
   -- The count can be decomposed into  N = p * F_ODD_C + q   (q = N mod F_ODD_C)
   -- and thus N/F_ODD_C becomes  p + q/F_ODD_C
   -- 'p' can be counted by skipping F_ODD_C - 1 out of F_ODD_C pulses; the modulus 'q'
   -- is also easy to count.
   -- This is not the end of the story, however, since the result is shifted by a scale
   -- factor into 10.12 / 16.16 format (full and hi-speed, respectively).
   -- We need to also compute:
   --   R = (2**SCALE * q) / F_ODD_C
   -- If we widen to the next power of two that holds F_ODD_C then
   --
   --   N = 2**(SCALE + EXTRA) * p + 2**SCALE (2**EXTRA * q / F_ODD_C)
   --   N = 2**(SCALE) * ( 2**EXTRA * p +  A * q + B * q / F_ODD_C )
   --
   -- with A = F_ODD_C = 1   B = (2**EXTRA - F_ODD_C)
   -- After FODD increments we obtain
   --
   --    A*FODD + B * FODD / FODD = FODD + 2**EXTRA - FODD = 2**EXTRA,
   --
   -- i.e., p is automatically incremented:
   --
   --   N := N + 1
   --   b := b + B
   --   if b >= F_ODD then
   --      N := N + 1
   --      b := b - F_ODD
   --   end if;
   --
   -- we can combine this into a single accumulator adding 'EXTRA' bits:
   -- with E = 2**EXTRA
   --
   --   if ( b >= F_ODD - B ):
   --      N := N + 2*E
   --      b := b + B - F_ODD
   --   else
   --      N := N + E
   --      b := b + B
   -- in the first branch: since B >= F_ODD we can at once increment N and subtract - F_ODD
   --
   -- if ( b >= F_ODD - B ) then
   --   N : b += E + E + B - F_ODD = E + 2*B
   -- else
   --   N : b += E + B

   constant FODD_CMPL_C : natural := 2**LD_FODD_C - FODD_C;

   -- must divide by the oversampling rate and the extra 2**LD_FODD_C introduced by extending
   -- the counter
   constant LD_SCL_FS_C           : integer := 13 - LD_SOF_CNT_FS_C - LD_OVRSMP_C - LD_FODD_C;
   constant LD_SCL_HS_C           : integer := 16 - LD_SOF_CNT_HS_C - LD_OVRSMP_C - LD_FODD_C;

   -- this is correct for hi and full speed; samples / frame (fs) vs samples/uframe (hs)
   -- but the HS format is 16.16 (vs full-speed 10.13), i.e., the 3-bit left shift due
   -- to formatting cancels the division by 8 due to the higher ref. frequency.
   constant RATE_INIT_C           : std_logic_vector(31 downto 0) := 
      std_logic_vector( to_unsigned( SAMPLING_FREQ_G * 2**13 / 1000, 32 ) );

   function scale(
      constant x  : in unsigned;
      constant hs : in std_logic
   ) return std_logic_vector is
      variable v : unsigned(31 downto 0);
   begin
      if ( hs = '1' ) then
         if ( LD_SCL_HS_C >= 0 ) then
            v := shift_left( resize( x, v'length ), LD_SCL_HS_C );
         else
            v := resize( shift_right( x, -LD_SCL_HS_C ), v'length );
         end if;
      else
         if ( LD_SCL_FS_C >= 0 ) then
            v := shift_left( resize( x, v'length ), LD_SCL_FS_C );
         else
            v := resize( shift_right( x, -LD_SCL_FS_C ), v'length );
         end if;
      end if;
      return std_logic_vector( v );
   end function scale;

   -- for now we assume sample_size < 8
   constant COUNT_W_C     : natural := 3;

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
   -- of 1 packet arriving very early and the next very late

   constant MINFILL_C     : bit_vector(15 downto 0) := to_bitvector( std_logic_vector( to_unsigned( 2*FRMSZ_C, 16) ) );

   type StateType         is ( INIT, FILL, RUN );

   type RegType is record
      state   : StateType;
      bitCnt  : BitCountType;
      bytCnt  : BytCountType;
      pblrlst : std_logic;
      swpr    : std_logic_vector(8*SAMPLE_SIZE_G - 1 downto 0);
      sreg    : std_logic_vector(8*SAMPLE_SIZE_G - 1 downto 0);
      sofcnt  : signed(LD_SOF_CNT_MAX_C downto 0);
      rate    : unsigned(LD_RATE_C - 1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state   => INIT,
      -- must ensure RDEN is low for two cycles after reset is deasserted
      -- use the bit-counter for this
      bitCnt  => to_signed( 3, BitCountType'length ),
      bytCnt  => BYTCNT_F,
      pblrlst => '0',
      swpr    => (others => '0'),
      sreg    => (others => '0'),
      sofcnt  => (others => '1'),
      rate    => (others => '0')
   );

   signal r               : RegType := REG_INIT_C;
   signal rin             : RegType;

   type   Usb2StateType   is ( IDLE, X0, X1, X2, X3, DON );

   type Usb2RegType is record
      state : Usb2StateType;
      -- keep a copy so that we are guaranteed to have a consistent
      -- value while transmitting.
      rate  : std_logic_vector(31 downto 8);
   end record Usb2RegType;

   constant USB2_REG_INIT_C : Usb2RegType := (
      state => IDLE,
      rate  => RATE_INIT_C(31 downto 8)
   );

   signal rusb2           : Usb2RegType := USB2_REG_INIT_C;
   signal rinusb2         : Usb2RegType;

   signal u2sRstTgl       : std_logic := '1';
   signal u2sRstTglOut    : std_logic;
   signal u2sRstOut       : std_logic;

   signal u2sSpdInp       : std_logic;
   signal u2sSpdOut       : std_logic;

   signal u2sSOFTgl       : std_logic := '0';
   signal u2sSOFTglOut    : std_logic;
   signal u2sSOFSync      : std_logic_vector(2 downto 0) := (others => '0');

   signal s2uRstTgl       : std_logic := '0';
   signal s2uRstOut       : std_logic;

   signal s2uUpdTgl       : std_logic := '0';
   signal s2uUpdTglOut    : std_logic;

   signal usb2RstLst      : std_logic := '1'; -- initial reset
   signal rxVldLst        : std_logic := '0';

   signal hiSpeed         : std_logic;
   signal sofFlag         : std_logic;

   signal rstCntBclk      : unsigned(3 downto 0) := "1100";

   signal fifoDin         : std_logic_vector(31 downto 0);
   signal fifoDou         : std_logic_vector(31 downto 0);
   signal fifoRen         : std_logic;
   signal fifoWen         : std_logic;
   signal fifoEmpty       : std_logic;
   signal fifoMinFill     : std_logic;
   signal fifoFull        : std_logic;
   signal fifoAlmostEmpty : std_logic;
   signal fifoRst         : std_logic := '0';

   signal rateUpdate      : std_logic := '0';

   signal usb2Resetting   : std_logic;
   signal waitForFrame    : std_logic := '1';
   
   -- this is updated synchronously with SOF from the BCLK domain; it is safe
   -- to be read by usb2Clk when handling an INP 
   signal rateMeasBclk    : std_logic_vector(31 downto 0) := RATE_INIT_C;
   signal rateUpdateTgl   : std_logic := '0';
   signal rateMeasUsb2_i  : std_logic_vector(31 downto 0);

   attribute MARK_DEBUG of r                           : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoRen                     : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoEmpty                   : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoAlmostEmpty             : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoFull                    : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of fifoRst                     : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of sofFlag                     : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of rateUpdate                  : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of rateMeasBclk                : signal is MARK_DEBUG_C;

begin

   assert SAMPLE_SIZE_G * NUM_CHANNELS_G <= 8 report "must increase counter width" severity failure;
   assert FB_FREQ_G <= SI_FREQ_G report "feedback interval should be >= service interval" severity failure;

   B_I2S_SYNCHRONIZERS : block is
      signal rateMeasUsb2 : std_logic_vector(31 downto 0) := RATE_INIT_C;
   begin
      U_U2S_RST_SYNC : entity work.I2S_CC_Sync
         generic map ( STAGES_G => 3 )
         port map (
            clk => i2sBCLK,
            d   => u2sRstTgl,
            tgl => u2sRstTglOut,
            o   => u2sRstOut
         );
      U_U2S_SPD_SYNC : entity work.I2S_CC_Sync
         port map (
            clk => i2sBCLK,
            d   => u2sSpdInp,
            tgl => open,
            o   => u2sSpdOut
         );
      U_U2S_SOF_SYNC : entity work.I2S_CC_Sync
         generic map ( STAGES_G => 3 )
         port map (
            clk => i2sBCLK,
            d   => u2sSOFTgl,
            tgl => u2sSOFTglOut,
            o   => open
         );

      U_S2U_RST_SYNC : entity work.I2S_CC_Sync
         generic map ( STAGES_G => 3 )
         port map (
            clk => usb2Clk,
            d   => s2uRstTgl,
            tgl => open,
            o   => s2uRstOut
         );
      U_S2U_UPD_SYNC : entity work.I2S_CC_Sync
         generic map ( STAGES_G => 3 )
         port map (
            clk => usb2Clk,
            d   => rateUpdateTgl,
            tgl => s2uUpdTglOut,
            o   => open
         );

      -- keep rateMeasUsb2 register in this block to help
      -- writing constraints

      P_MEAS_USB : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( usb2Resetting = '1' ) then
               rateMeasUsb2 <= RATE_INIT_C;
            elsif ( s2uUpdTglOut = '1' ) then
               rateMeasUsb2 <= rateMeasBclk;
            end if;
         end if;
      end process P_MEAS_USB;

      rateMeasUsb2_i <= rateMeasUsb2;

   end block B_I2S_SYNCHRONIZERS;

   i2sPBDAT    <= r.sreg(r.sreg'left);
   fifoMinFill <= not fifoAlmostEmpty;

   P_I2S_COMB : process (r, i2sPBLRC, fifoDou, fifoEmpty, fifoMinFill, sofFlag, hiSpeed) is
      variable v : RegType;
   begin
      v             := r;
      fifoRen       <= '0';
      v.pblrlst     := i2sPBLRC;
      rateUpdate    <= '0';

      -- shift
      v.sreg := r.sreg(r.sreg'left - 1 downto 0) & '0';

      -- rate counter
      if ( r.rate(LD_FODD_C - 1 downto 0) >= FODD_C - FODD_CMPL_C ) then
         v.rate    := r.rate + to_unsigned(2**LD_FODD_C + 2*FODD_CMPL_C, r.rate'length);
      else
         v.rate    := r.rate + to_unsigned(2**LD_FODD_C + 1*FODD_CMPL_C, r.rate'length);
      end if;

      if ( sofFlag = '1' ) then
         if ( r.sofcnt(r.sofcnt'left) = '1' or r.state = INIT ) then
            if ( hiSpeed = '1' ) then
               v.sofcnt := to_signed(SOF_CNT_HS_C - 2, r.sofcnt'length);
            else
               v.sofcnt := to_signed(SOF_CNT_FS_C - 2, r.sofcnt'length);
            end if;
            -- pre-load with the first count; in the special case (FODD_C = FODD_CMPL_C,
            -- i.e., the oversampling rate is a precise power of two) we must be careful
            -- (see also the commend about LD_OVRSMPL_C)
            if ( FODD_C = FODD_CMPL_C ) then
               v.rate := to_unsigned(2**LD_FODD_C + 2*FODD_CMPL_C, r.rate'length);
            else
               v.rate := to_unsigned(2**LD_FODD_C + 1*FODD_CMPL_C, r.rate'length);
            end if;
         else
            v.sofcnt := r.sofcnt - 1;
         end if;
         if ( r.state /= INIT and r.sofcnt(r.sofcnt'left) = '1' ) then
            rateUpdate <= '1';
         end if;
      end if;

      case ( r.state ) is
         when INIT =>
            -- must ensure RDEN is low for two cycles after reset is deasserted
            if ( expired( r.bitCnt ) ) then
               if ( sofFlag = '1' ) then
                  v.state := FILL;
               end if;
            else
               v.bitCnt := r.bitCnt - 1;
            end if;

         when FILL =>
            v.bitCnt := BITCNT_F;
            v.bytCnt := BYTCNT_F;
            if ( ( fifoMinFill = '1' ) and ( i2sPBLRC = '1' ) and ( r.pblrlst = '0' ) ) then
               v.state  := RUN;
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
         if ( fifoRst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_I2S_SEQ;

   P_RST_I2S : process ( i2sBCLK ) is
   begin
      if ( rising_edge( i2sBCLK ) ) then
         if ( u2sRstTglOut = '1' ) then
            -- new reset event; load counter
            rstCntBclk <= (others => '1');
         elsif ( rstCntBclk( rstCntBclk'left ) = '1' ) then
            -- delay
            rstCntBclk <= rstCntBclk - 1;
         else
            -- delay expired; propagate reset event back to USB
            s2uRstTgl  <= u2sRstOut;
         end if;
         if    ( fifoRst = '1' ) then
            rateMeasBclk  <= RATE_INIT_C;
         elsif ( rateUpdate = '1' ) then
            rateUpdateTgl <= not rateUpdateTgl;
            rateMeasBclk  <= scale( r.rate, hiSpeed );
         end if;
      end if;
   end process P_RST_I2S;

   hiSpeed               <= u2sSpdOut;
   sofFlag               <= u2sSOFTglOut;

   usb2Resetting         <= usb2Rst or ( u2sRstTgl xor s2uRstOut );

   fifoWen               <= not waitForFrame and usb2EpIb.mstOut.vld;
   fifoDin( 7 downto 0)  <= usb2EpIb.mstOut.dat;
   fifoDin(31 downto 8)  <= (others => '0');

   P_RST_USB : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         usb2RstLst <= usb2Rst;
         if ( (usb2Rst & usb2RstLst) = unsigned'("10") ) then
            u2sRstTgl <= not u2sRstTgl;
         end if;

         if ( usb2Resetting = '1' ) then
            waitForFrame <= '1';
         elsif ( waitForFrame = '1' ) then
            -- sync to the next frame
            if ( usb2EpIb.mstOut.don = '1' ) then
               waitForFrame <= '0';
            end if;
         end if;

         if ( usb2Resetting = '1' ) then
            rxVldLst     <= '1';
         else
            rxVldLst <= usb2Rx.pktHdr.vld;
            if ( (not rxVldLst and usb2Rx.pktHdr.vld) = '1' and usb2Rx.pktHdr.sof ) then
               u2sSOFTgl <= not u2sSOFTgl;
            end if;
         end if;

         if ( usb2DevStatus.hiSpeed ) then
            u2sSpdInp <= '1';
         else
            u2sSpdInp <= '0';
         end if;
      end if;
   end process P_RST_USB;

   fifoRst               <= rstCntBclk( rstCntBclk'left );

   P_USB_COMB : process ( rusb2, usb2DevStatus, usb2EpIb, rateMeasUsb2_i ) is
      variable v : Usb2RegType;
   begin
      v                   := rusb2;
      usb2EpOb            <= USB2_ENDP_PAIR_IB_INIT_C;
      usb2EpOb.mstInp.don <= '0';
      usb2EpOb.mstInp.vld <= '1';
      usb2EpOb.mstInp.usr <= "0000"; -- only one microframe
      usb2EpOb.bFramedInp <= '1';    -- dont' use DON for framing

      case ( rusb2.state ) is
         when IDLE =>
            v.state             := X0;
            usb2EpOb.mstInp.vld <= '0';

         when X0   =>
            usb2EpOb.mstInp.dat <= rateMeasUsb2_i(7 downto 0);
            -- latch the rest to ensure we send consistent data
            v.rate := rateMeasUsb2_i(31 downto 8);
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

   U_I2S_PLAYBACK_FIFO : FIFO18E1
   generic map (
      ALMOST_EMPTY_OFFSET     => MINFILL_C,   -- Sets the almost empty threshold
      ALMOST_FULL_OFFSET      => X"0080",     -- Sets almost full threshold
      DATA_WIDTH              => 9,           -- Sets data width to 4-36
      DO_REG                  => 1,           -- Enable output register (1-0) Must be 1 if EN_SYN = FALSE
      EN_SYN                  => FALSE,       -- Specifies FIFO as dual-clock (FALSE) or Synchronous (TRUE)
      FIFO_MODE               => "FIFO18",    -- Sets mode to FIFO18 or FIFO18_36
      FIRST_WORD_FALL_THROUGH => TRUE,         -- Sets the FIFO FWFT to FALSE, TRUE
      INIT                    => X"000000000", -- Initial values on output port
      SIM_DEVICE              => "7SERIES",    -- Must be set to "7SERIES" for simulation behavior
      SRVAL                   => X"000000000"  -- Set/Reset value for output port
   )
   port map (
      DO                     => fifoDou,
      DOP                    => open,

      ALMOSTEMPTY            => fifoAlmostEmpty,
      ALMOSTFULL             => fifoFull,
      EMPTY                  => fifoEmpty,
      FULL                   => open,
      RDCOUNT                => open,
      RDERR                  => open,
      WRCOUNT                => open,
      WRERR                  => open,

      RDCLK                  => i2sBCLK,
      RDEN                   => fifoRen,
      REGCE                  => '0',
      -- async reset; must be asserted for 5 read or write cycles
      RST                    => fifoRst,
      RSTREG                 => '0',

      WRCLK                  => usb2Clk,
      WREN                   => fifoWen,
      DI                     => fifoDin,
      DIP                    => x"0"
   );

   usb2RstBsy <= usb2Resetting;

end architecture Impl;
