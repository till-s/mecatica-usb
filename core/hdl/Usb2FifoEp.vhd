-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2DescPkg.all;

-- Endpoint pair with FIFO buffers, e.g., for implementing a CDC-ACM
-- endpoint.

entity Usb2FifoEp is
   generic (
      -- LD_FIFO_DEPTH = width of the address; i.e., ceil( log2( depth - 1 ) )
      LD_FIFO_DEPTH_INP_G          : natural  := 0; -- disabled when 0
      -- for high-bandwidth throughput the output fifo depth must be >= 2*maxPktSize
      -- because at the time a packet is released into the fifo there must already
      -- a decision be made if a second packet would fit.
      -- maxPktSize is the current configuration's maxPktSize as conveyed by
      -- the 'usb2EpIb.config' input signal.
      LD_FIFO_DEPTH_OUT_G          : natural  := 0; -- disabled when 0
      TIMER_WIDTH_G                : positive := 1;
      -- add an output register to the INP bound FIFO (to improve timing)
      OUT_REG_INP_G                : boolean  := false;
      -- add an output register to the OUT bound FIFO (to improve timing)
      OUT_REG_OUT_G                : boolean  := false;
      -- whether usb2Clk and epClk are asynchronous
      ASYNC_G                      : boolean  := false;
      -- whether to use 'don' framing (see Usb2Pkg.vhd); at least one complete
      -- frame must reside in the IN fifo before sending it can be started.
      -- LD_MAX_FRAMES_INP/OUT_G determines how many frames can maximally be stored
      -- (e.g., for ethernet this would be the size of the fifo divided by the
      -- minimal frame size of 64).
      -- If set to 0 then 'don' framing is disabled and data are not framed
      -- at all.
      -- This is the number of bits required to hold the max number of frames
      -- floor( log2( maxN ) ) + 1
      LD_MAX_FRAMES_INP_G          : natural  := 0;
      LD_MAX_FRAMES_OUT_G          : natural  := 0
   );
   port (
      usb2Clk                      : in  std_logic;
      usb2Rst                      : in  std_logic := '0';
      usb2RstOut                   : out std_logic;

      -- Endpoint Interface
      usb2EpOb                     : out Usb2EndpPairIbType;
      usb2EpIb                     : in  Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;

      -- Controls (usb2Clk domain)
      -- accumulate 'minFillInp' items before passing to the endpoint
      minFillInp                   : in  unsigned(LD_FIFO_DEPTH_INP_G - 1 downto 0) := (others => '0');
      -- if more then 'timeFillInp' clock cycles expire since the last
      -- item was written the fifo contents are passed to USB (even
      -- if 'minFillInp' has not been reached). Similary to termios'
      -- VMIN+VTIME.
      --  - All-ones waits indefinitely.
      --  - Time may be reduced while a wait is in progress.
      timeFillInp                  : in  unsigned(TIMER_WIDTH_G - 1 downto 0) := (others => '0');

      epClk                        : in  std_logic    := '0';
      -- reset received from USB or endpoint not active in current alt-setting
      epRstOut                     : out std_logic;

      -- FIFO Interface IN (to USB); epClk domain

      datInp                       : in  Usb2ByteType := (others => '0');
      -- End of frame ('don'); data shipped during the cycle when EOF is
      -- asserted are ignored (i.e., not forwarded to USB)!
      -- Note: a single cycle with 'eofInp' asserted (w/o preceding data
      -- cycles) is sent as a zero-length frame!
      -- This is only relevant if framing is enabled (LD_MAX_NUM_FRAMES_G > 0).
      donInp                       : in  std_logic    := '0';
      wenInp                       : in  std_logic    := '0';
      filledInp                    : out unsigned(LD_FIFO_DEPTH_INP_G downto 0) := (others => '0');
      fullInp                      : out std_logic    := '1';

      -- FIFO Interface OUT (from USB); epClk domain
      datOut                       : out Usb2ByteType := (others => '0');
      -- End of frame ('don'); data shipped during the cycle when EOF is
      -- asserted are invalid (it is possible to support zero-length frames).
      -- This is only relevant if framing is enabled (LD_MAX_FRAMES_OUT_G > 0).
      donOut                       : out std_logic    := '0';
      renOut                       : in  std_logic    := '0';
      filledOut                    : out unsigned(LD_FIFO_DEPTH_OUT_G downto 0) := (others => '0');
      -- frames currently in the OUT fifo (only if 'don' framing enabled)
      framesOut                    : out unsigned(LD_MAX_FRAMES_OUT_G downto 0) := (others => '0');
      emptyOut                     : out std_logic    := '1'
   );
end entity Usb2FifoEp;

architecture Impl of Usb2FifoEp is

   signal haltedInp             : std_logic := '1';
   signal haltedOut             : std_logic := '1';
   signal haltedInpEpClk        : std_logic := '1';
   signal haltedOutEpClk        : std_logic := '1';
   signal mstInpVld             : std_logic := '0';
   signal mstInpDon             : std_logic := '0';
   signal mstInpDat             : std_logic_vector(7 downto 0) := (others => '0');
   signal bFramedInp            : std_logic := '0';
   signal subOutRdy             : std_logic := '0';
   signal epRstOutLoc           : std_logic := '0';
   signal epClkLoc              : std_logic;
   signal obFifoRstUsbClk       : std_logic := '0';
   signal ibFifoRstUsbClk       : std_logic := '0';
   signal obFifoRstEpClk        : std_logic := '0';
   signal ibFifoRstEpClk        : std_logic := '0';

   type EpDirType is ( DIR_INP, DIR_OUT );

   function FIFO_WIDTH_F(constant x : in EpDirType) return natural is
      variable rv : natural;
   begin
      rv := Usb2ByteType'length;
      if ( (x = DIR_INP and LD_MAX_FRAMES_INP_G > 0) or (x = DIR_OUT and LD_MAX_FRAMES_OUT_G > 0) ) then
         rv := rv + 1;
      end if;
      return rv;
   end function FIFO_WIDTH_F;

begin

   epRstOutLoc <= obFifoRstEpClk or ibFifoRstEpCLk;
   epRstOut    <= epRstOutLoc;

   usb2RstOut  <= obFifoRstUsbClk or ibFifoRstUsbClk;

   G_SYNC : if ( not ASYNC_G ) generate
   begin
      epClkLoc       <= usb2Clk;
      haltedInpEpClk <= haltedInp;
      haltedOutEpClk <= haltedOut;
   end generate G_SYNC;

   G_Usb2FifoAsyncCC : if ( ASYNC_G ) generate
   begin

      epClkLoc    <= epClk;

      U_SYNC_HALT_INP : entity work.Usb2CCSync
         port map (
            clk => epClkLoc,
            d   => haltedInp,
            q   => haltedInpEpClk
         );

      U_SYNC_HALT_OUT : entity work.Usb2CCSync
         port map (
            clk => epClkLoc,
            d   => haltedOut,
            q   => haltedOutEpClk
         );

   end generate G_Usb2FifoAsyncCC;

   G_INP_FIFO : if ( LD_FIFO_DEPTH_INP_G > 0 ) generate
      signal haltedEpClk  : std_logic;
      signal fifoWen      : std_logic;
      signal fifoFull     : std_logic;
      signal fifoRen      : std_logic;
      signal fifoEmpty    : std_logic;
      signal fifoDin      : std_logic_vector(FIFO_WIDTH_F(DIR_INP) - 1 downto 0);
      signal fifoDou      : std_logic_vector(FIFO_WIDTH_F(DIR_INP) - 1 downto 0);
      signal numFramesInp : unsigned(LD_MAX_FRAMES_INP_G downto 0) := (others => '0');
      signal xtraInp      : std_logic_vector(LD_MAX_FRAMES_INP_G downto 0);
      signal numFramesOut : unsigned(LD_MAX_FRAMES_INP_G downto 0) := (others => '0');
      signal xtraOut      : std_logic_vector(LD_MAX_FRAMES_INP_G downto 0);
      signal haveAFrame   : std_logic := '1';
      signal usb2RstLoc   : std_logic;
      signal epRunning    : std_logic;
   begin

      epRunning  <= epInpRunning( usb2EpIb );

      usb2RstLoc <= usb2Rst or not epRunning;

      -- usb2 clock domain
      haltedInp           <= usb2EpIb.haltedInp;
      mstInpVld           <= not fifoEmpty and haveAFrame and not mstInpDon;

      -- only freeze user-access in halted state; EP interaction with the packet
      -- engine proceeds
      fifoRen             <= usb2EpIb.subInp.rdy and haveAFrame and not fifoEmpty;
      mstInpDat           <= fifoDou( mstInpDat'range );

      -- EP clock domain
      fullInp             <= fifoFull or haltedInpEpClk;
      fifoWen             <= wenInp and not haltedInpEpClk and not fifoFull;

      G_WITH_DON : if ( LD_MAX_FRAMES_INP_G > 0 ) generate
         fifoDin    <= donInp & datInp;
         mstInpDon  <= fifoDou( datInp'length ) and not fifoEmpty;
         bFramedInp <= '0'; -- support framing

         -- maintain frame counters
         P_WR_FRAMES : process ( epClk ) is
         begin
            if ( rising_edge( epClk ) ) then
               if ( epRstOutLoc = '1' ) then
                  numFramesInp <= (others => '0');
               else
                  if ( (donInp and fifoWen) = '1' ) then
                     numFramesInp <= numFramesInp + 1;
                  end if;
               end if;
            end if;
         end process P_WR_FRAMES;


         -- the xtra vector conveys the synchronized frame count we
         -- received from the writing end
         xtraInp    <= std_logic_vector( numFramesInp );
         haveAFrame <= toSl( numFramesOut /= unsigned( xtraOut ) );

         P_RD_FRAMES : process ( usb2Clk ) is
         begin
            if ( rising_edge( usb2Clk ) ) then
               if ( usb2RstLoc = '1' ) then
                  numFramesOut <= (others => '0');
               else
                  if ( ( fifoRen and mstInpDon ) = '1' ) then
                     numFramesOut <= numFramesOut + 1;
                  end if;
               end if;
            end if;
         end process P_RD_FRAMES;

      end generate G_WITH_DON;

      G_NO_DON : if ( LD_MAX_FRAMES_INP_G = 0 ) generate
         fifoDin    <= datInp;
         mstInpDon  <= '0'; -- no framing
         bFramedInp <= '1'; -- no framing
         haveAFrame <= '1';
      end generate G_NO_DON;

      U_FIFO : entity work.Usb2Fifo
         generic map (
            DATA_WIDTH_G => FIFO_WIDTH_F(DIR_INP),
            LD_DEPTH_G   => LD_FIFO_DEPTH_INP_G,
            LD_TIMER_G   => TIMER_WIDTH_G,
            OUT_REG_G    => ite( OUT_REG_INP_G, 1, 0 ),
            ASYNC_G      => ASYNC_G,
            XTRA_W2R_G   => xtraInp'length
         )
         port map (
            wrClk        => epClkLoc,
            wrRst        => open, -- only allow to be reset from USB
            wrRstOut     => ibFifoRstEpClk,

            din          => fifoDin,
            wen          => fifoWen,
            full         => fifoFull,
            wrFilled     => filledInp,
            wrXtraInp    => xtraInp,

            rdClk        => usb2Clk,
            rdRst        => usb2RstLoc,
            rdRstOut     => ibFifoRstUsbClk,

            dou          => fifoDou,
            ren          => fifoRen,
            empty        => fifoEmpty,
            rdFilled     => open,
            rdXtraOut    => xtraOut,

            minFill      => minFillInp,
            timer        => timeFillInp
         );

   end generate G_INP_FIFO;

   G_OUT_FIFO : if ( LD_FIFO_DEPTH_OUT_G > 0 ) generate
      signal fifoWen      : std_logic;
      signal fifoRen      : std_logic;
      signal fifoFull     : std_logic;
      signal fifoEmpty    : std_logic;
      signal fifoFilled   : unsigned(LD_FIFO_DEPTH_OUT_G downto 0);
      signal fifoRdy      : std_logic := '0';
      signal lastWen      : std_logic := '0';
      signal fifoDin      : std_logic_vector(FIFO_WIDTH_F(DIR_OUT) - 1 downto 0);
      signal fifoDou      : std_logic_vector(FIFO_WIDTH_F(DIR_OUT) - 1 downto 0);
      signal fifoDon      : std_logic := '0';
      signal maxPktSz     : Usb2PktSizeType;
      signal numFramesInp : unsigned(LD_MAX_FRAMES_OUT_G downto 0) := (others => '0');
      signal xtraInp      : std_logic_vector(LD_MAX_FRAMES_OUT_G downto 0);
      signal numFramesOut : unsigned(LD_MAX_FRAMES_OUT_G downto 0) := (others => '0');
      signal xtraOut      : std_logic_vector(LD_MAX_FRAMES_OUT_G downto 0);
      signal epRunning    : std_logic;
      signal usb2RstLoc   : std_logic;
   begin

      -- reduce typing
      maxPktSz   <= usb2EpIb.config.maxPktSizeOut;
      epRunning  <= epOutRunning( usb2EpIb );
      usb2RstLoc <= usb2Rst or not epRunning;

      datOut     <= fifoDou( datOut'range );

      G_WITH_DON : if ( LD_MAX_FRAMES_OUT_G > 0 ) generate
      begin
         fifoDin <= usb2EpIb.mstOut.don & usb2EpIb.mstOut.dat;
         fifoWen <= (usb2EpIb.mstOut.vld or usb2EpIb.mstOut.don) and not fifoFull;
         fifoDon <= fifoDou( datOut'length );
         donOut  <= fifoDon;

         -- maintain frame counters
         P_WR_FRAMES : process ( usb2Clk ) is
         begin
            if ( rising_edge( usb2Clk ) ) then
               if ( usb2RstLoc = '1' ) then
                  numFramesInp <= (others => '0');
               else
                  if ( (usb2EpIb.mstOut.don and fifoWen) = '1' ) then
                     numFramesInp <= numFramesInp + 1;
                  end if;
               end if;
            end if;
         end process P_WR_FRAMES;

         -- the xtra vector conveys the synchronized frame count we
         -- received from the writing end
         xtraInp    <= std_logic_vector( numFramesInp );
         framesOut  <= unsigned( xtraOut ) - numFramesOut;

         P_RD_FRAMES : process ( epClk ) is
         begin
            if ( rising_edge( epClk ) ) then
               if ( epRstOutLoc = '1' ) then
                  numFramesOut <= (others => '0');
               else
                  if ( ( fifoRen and fifoDon ) = '1' ) then
                     numFramesOut <= numFramesOut + 1;
                  end if;
               end if;
            end if;
         end process P_RD_FRAMES;

      end generate G_WITH_DON;

      G_NO_DON : if ( LD_MAX_FRAMES_OUT_G = 0 ) generate
         fifoDin <= usb2EpIb.mstOut.dat;
         fifoWen <= usb2EpIb.mstOut.vld and not fifoFull;
      end generate G_NO_DON;

      P_SEQ : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( usb2RstLoc = '1' ) then
               fifoRdy   <= '0';
               lastWen   <= '0';
            else
               lastWen <= fifoWen;
               if ( ( fifoRdy or fifoWen ) = '0' ) then
                  if ( fifoFilled <= 2**LD_FIFO_DEPTH_OUT_G - maxPktSz ) then
                     fifoRdy <= '1';
                  end if;
               else
                  if ( fifoWen = '1' and lastWen = '0' ) then
                     -- first packet can be accepted and starts being transferred
                     -- check if we could accept a second packet
                     if (     ( 2**LD_FIFO_DEPTH_OUT_G < shift_left( maxPktSz, 1 ) )
                          or  ( 2**LD_FIFO_DEPTH_OUT_G - shift_left( maxPktSz, 1 ) < fifoFilled ) ) then
                        -- we cannot accept a second packet; turn fifoRdy off
                        fifoRdy <= '0';
                     end if;
                  end if;
               end if;
            end if;
         end if;
      end process P_SEQ;

      -- only freeze user-access in halted state; EP interaction with the packet
      -- engine proceeds

      -- usb2 clock domain
      haltedOut           <= usb2EpIb.haltedOut;
      subOutRdy           <= fifoRdy and not fifoFull;

      -- EP clock domain
      emptyOut            <= fifoEmpty or haltedOutEpClk;
      fifoRen             <= renOut and not haltedOutEpClk and not fifoEmpty;

      U_FIFO : entity work.Usb2Fifo
         generic map (
            DATA_WIDTH_G => FIFO_WIDTH_F(DIR_OUT),
            LD_DEPTH_G   => LD_FIFO_DEPTH_OUT_G,
            LD_TIMER_G   => 1,
            OUT_REG_G    => ite( OUT_REG_OUT_G, 1, 0 ),
            ASYNC_G      => ASYNC_G,
            XTRA_W2R_G   => xtraInp'length
         )
         port map (
            wrClk        => usb2Clk,
            wrRst        => usb2RstLoc,
            wrRstOut     => obFifoRstUsbClk,

            din          => fifoDin,
            wen          => fifoWen,
            full         => fifoFull,
            wrFilled     => fifoFilled,
            wrXtraInp    => xtraInp,

            rdClk        => epClkLoc,
            rdRst        => open, -- only allow to be reset from USB
            rdRstOut     => obFifoRstEpClk,
            dou          => fifoDou,
            ren          => fifoRen,
            empty        => fifoEmpty,
            rdFilled     => filledOut,
            rdXtraOut    => xtraOut,

            minFill      => open,
            timer        => open
         );

   end generate G_OUT_FIFO;

   P_COMB : process ( mstInpVld, haltedInp, mstInpDat, bFramedInp, mstInpDon, haltedOut, subOutRdy ) is
   begin
      usb2EpOb            <= USB2_ENDP_PAIR_IB_INIT_C;
      usb2EpOb.mstInp.vld <= mstInpVld;
      usb2EpOb.stalledInp <= haltedInp;
      usb2EpOb.bFramedInp <= bFramedInp;
      usb2EpOb.mstInp.err <= '0';
      usb2EpOb.mstInp.don <= mstInpDon;
      usb2EpOb.mstInp.dat <= mstInpDat;
      usb2EpOb.stalledOut <= haltedOut;
      usb2EpOb.subOut.rdy <= subOutRdy;
   end process P_COMB;

end architecture Impl;
