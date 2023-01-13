-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Example of an isochronous endpoint: SSI audio playback;
-- uses a XILINX FIFO for crossing from the USB into the
-- audio domain.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

library unisim;
use     unisim.vcomponents.all;

entity I2SPlayback is
   generic (
      SAMPLE_SIZE_G       : natural := 3;    -- audio samples in bytes
      NUM_CHANNELS_G      : natural := 2;    -- stereo/mono
      SAMPLING_FREQ_G     : natural := 48000;
      SI_FREQ_G           : natural := 1000; -- service intervals/s
      SYNCHRONOUS_G       : boolean := true  -- whether audio and USB clocks are synchronous
   );
   port (
      usb2Clk             : in  std_logic;
      usb2Rst             : in  std_logic;
      usb2Rx              : in  Usb2RxType;
      usb2EpIb            : in  Usb2EndpPairObType;

      i2sBCLK             : in  std_logic;
      i2sPBLRC            : in  std_logic;
      i2sPBDAT            : out std_logic
   );
end entity I2SPlayback;

architecture Impl of I2SPlayback is

   attribute ASYNC_REG    : string;

   constant FRMSZ_C       : natural := SAMPLE_SIZE_G * NUM_CHANNELS_G * SAMPLING_FREQ_G / SI_FREQ_G;

   -- for now we assume sample_size * num channels < 8
   constant COUNT_W_C     : natural := 3;

   subtype CountType      is unsigned(1 + COUNT_W_C + 8 - 1 downto 0);

   -- we count down to -1 and then reload with (N-2)
   constant COUNT_RELD_C  : CountType := to_unsigned(8*SAMPLE_SIZE_G * NUM_CHANNELS_G - 2, CountType'length);

   constant COUNT_INIT_C  : CountType := to_unsigned(4, CountType'length);

   -- since we don't know when exactly (within a service-interval) the next
   -- packet will arrive we must buffer at least 2 packets for the worst case
   -- of 1 packet arriving very early and the next very late

   constant MINFILL_C     : bit_vector(15 downto 0) := to_bitvector( std_logic_vector( to_unsigned( 2*FRMSZ_C, 16) ) );

   type StateType         is ( INIT, FILL, RUN );

   type RegType is record
      state   : StateType;
      cnt     : CountType;
      lst3    : std_logic;
      pblrlst : std_logic;
      sreg    : std_logic_vector(7 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state   => INIT,
      cnt     => COUNT_INIT_C,
      lst3    => '0',
      pblrlst => '0',
      sreg    => (others => '0')
   );

   signal r               : RegType := REG_INIT_C;
   signal rin             : RegType;

   signal u2sRstSync      : std_logic_vector(2 downto 0) := (others => '0');
   signal s2uRstSync      : std_logic_vector(1 downto 0) := (others => '0');

   attribute ASYNC_REG    of u2sRstSync : signal is "TRUE";
   attribute ASYNC_REG    of s2uRstSync : signal is "TRUE";

   signal u2sRstTgl       : std_logic := '1';
   signal s2uRstTgl       : std_logic := '0';
   signal usb2RstLst      : std_logic := '1'; -- initial reset

   signal rstCntBclk      : unsigned(3 downto 0) := "1100";

   signal fifoDin         : std_logic_vector(31 downto 0);
   signal fifoDou         : std_logic_vector(31 downto 0);
   signal fifoRen         : std_logic;
   signal fifoWen         : std_logic;
   signal fifoEmpty       : std_logic;
   signal fifoMinFill     : std_logic;
   signal fifoAlmostEmpty : std_logic;
   signal fifoRst         : std_logic := '0';

   signal usb2Resetting   : std_logic;
   signal waitForFrame    : std_logic := '1';
   
   signal rstSync         : std_logic_vector(2 downto 0) := (others => '0');
   attribute ASYNC_REG    of rstSync : signal is "TRUE";

begin

   i2sPBDAT <= r.sreg(0);

   assert SAMPLE_SIZE_G * NUM_CHANNELS_G <= 8 report "must increase counter width" severity failure;

   fifoMinFill <= not fifoAlmostEmpty;

   P_I2S_COMB : process (r, i2sPBLRC, fifoDou, fifoEmpty, fifoMinFill) is
      variable v : RegType;
   begin
      v             := r;
      fifoRen       <= '0';
      v.pblrlst     := i2sPBLRC;

      case ( r.state ) is
         when INIT =>
            -- must ensure RDEN is low for two cycles after reset is deasserted
            if ( r.cnt(r.cnt'left) = '1' ) then
               v.state := FILL;
            else
               v.cnt   := r.cnt - 1;
            end if;

         when FILL =>
            if ( (fifoMinFill = '1') and (i2sPBLRC = '0') and ( r.pblrlst = '1' ) ) then
               v.state := RUN;
               -- take first word
               fifoRen <= '1';
               v.sreg  := fifoDou(7 downto 0);
               v.cnt   := COUNT_RELD_C;
               v.lst3  := v.cnt(3);
            end if;

         when RUN =>
            -- compute next counter
            if ( r.cnt( r.cnt'left ) = '1' ) then
               -- done with one slot, reload
               v.cnt  := COUNT_RELD_C;
               v.lst3 := v.cnt(3);
            else
               -- count down and remember state of bit3
               v.cnt  := r.cnt - 1;
               v.lst3 := r.cnt(3);
            end if;
            if ( fifoEmpty = '1' ) then
               -- resync
               v.sreg(0) := '0'; -- audio off
               v.cnt     := COUNT_INIT_C;
               v.state   := FILL;
            elsif ( r.cnt(3) /= r.lst3 ) then
               -- reached a byte-boundary when counter bit3 toggles
               fifoRen   <= '1';
               v.sreg    := fifoDou(7 downto 0);
            else
               -- shift
               v.sreg    := '0' & r.sreg(r.sreg'left downto 1);
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
         u2sRstSync <= u2sRstTgl & u2sRstSync(u2sRstSync'left downto 1);
         if ( u2sRstSync(1) /= u2sRstSync(0) ) then
            -- new reset event; load counter
            rstCntBclk <= (others => '1');
         elsif ( rstCntBclk( rstCntBclk'left ) = '1' ) then
            -- delay
            rstCntBclk <= rstCntBclk - 1;
         else
            -- delay expired; propagate reset event back to USB
            s2uRstTgl  <= u2sRstSync(0);
         end if;
      end if;
   end process P_RST_I2S;

   usb2Resetting         <= usb2Rst or ( u2sRstTgl xor s2uRstSync(0) );

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
         s2uRstSync <= s2uRstTgl & s2uRstSync(s2uRstSync'left downto 1);

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

   fifoRst               <= rstCntBclk( rstCntBclk'left );

   U_FIFO : FIFO18E1
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
      ALMOSTFULL             => open,
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

end architecture Impl;
