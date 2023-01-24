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
      MAX_PKT_SIZE_INP_G           : natural  := 0; -- disabled when 0
      MAX_PKT_SIZE_OUT_G           : natural  := 0; -- disabled when 0
      LD_FIFO_DEPTH_INP_G          : natural  := 0;
      -- for high-bandwidth throughput the fifo depth must be >= 2*MAX_PKT_SIZE_OUT_G
      -- because at the time a packet is released into the fifo there must already
      -- a decision be made if a second packet would fit.
      LD_FIFO_DEPTH_OUT_G          : natural  := 0; -- must be >= MAX_PKT_SIZE_OUT_G
      TIMER_WIDTH_G                : positive := 1;
      -- add an output register to the INP bound FIFO (to improve timing)
      OUT_REG_INP_G                : boolean  := false;
      -- add an output register to the OUT bound FIFO (to improve timing)
      OUT_REG_OUT_G                : boolean  := false;
      -- whether usb2Clk and epClk are asynchronous
      ASYNC_G                      : boolean  := false
   );
   port (
      usb2Clk                      : in  std_logic;
      usb2Rst                      : in  std_logic := '0';

      -- Endpoint Interface
      usb2EpIb                     : out Usb2EndpPairIbType;
      usb2EpOb                     : in  Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;

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

      -- EP Halt (usb2Clk domain)
      selHaltInp                   : in  std_logic    := '0';
      selHaltOut                   : in  std_logic    := '0';
      setHalt                      : in  std_logic    := '0';
      clrHalt                      : in  std_logic    := '0';

      epClk                        : in  std_logic    := '0';
      epRst                        : in  std_logic    := '0';

      -- FIFO Interface IN (to USB); epClk domain

      datInp                       : in  Usb2ByteType := (others => '0');
      wenInp                       : in  std_logic    := '0';
      filledInp                    : out unsigned(LD_FIFO_DEPTH_INP_G downto 0) := (others => '0');
      fullInp                      : out std_logic    := '1';

      -- FIFO Interface OUT (from USB); epClk domain
      datOut                       : out Usb2ByteType := (others => '0');
      renOut                       : in  std_logic    := '0';
      filledOut                    : out unsigned(LD_FIFO_DEPTH_OUT_G downto 0) := (others => '0');
      emptyOut                     : out std_logic    := '1'
   );
end entity Usb2FifoEp;

architecture Impl of Usb2FifoEp is

   function ite(constant c: boolean; constant a,b : natural) return natural is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;  

   signal haltedInp             : std_logic := '1';
   signal haltedOut             : std_logic := '1';
   signal haltedInpEpClk        : std_logic := '1';
   signal haltedOutEpClk        : std_logic := '1';
   signal mstInpVld             : std_logic := '0';
   signal mstInpDon             : std_logic := '0';
   signal fifoDatInp            : std_logic_vector(7 downto 0) := (others => '0');
   signal bFramedInp            : std_logic := '0';
   signal subOutRdy             : std_logic := '0';

   signal epClkLoc              : std_logic;
   signal epRstLoc              : std_logic;

begin

   assert MAX_PKT_SIZE_INP_G = 0 or MAX_PKT_SIZE_INP_G <= 2**LD_FIFO_DEPTH_INP_G
      report "Inconsistent INP fifo depth"
      severity failure;

   assert MAX_PKT_SIZE_OUT_G = 0 or MAX_PKT_SIZE_OUT_G <= 2**LD_FIFO_DEPTH_OUT_G
      report "Inconsistent OUT fifo depth"
      severity failure;

   G_SYNC : if ( not ASYNC_G ) generate
   begin
      epClkLoc       <= usb2Clk;
      epRstLoc       <= usb2Rst;
      haltedInpEpClk <= haltedInp;
      haltedOutEpClk <= haltedOut;
   end generate G_SYNC;

   G_Usb2FifoAsyncCC : if ( ASYNC_G ) generate
   begin

      epClkLoc <= epClk;
      epRstLoc <= epRst;

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

   G_INP_FIFO : if ( MAX_PKT_SIZE_INP_G > 0 ) generate
      signal halted       : std_logic := '0';
      signal haltedEpClk  : std_logic;
      signal fifoWen      : std_logic;
      signal fifoFull     : std_logic;
      signal fifoRen      : std_logic;
      signal fifoEmpty    : std_logic;
   begin

      P_HALT : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( usb2Rst = '1' ) then
               halted  <= '0';
            else
               if ( (setHalt and selHaltInp) = '1' ) then
                  halted <= '1';
               end if;
               if ( (clrHalt and selHaltInp) = '1' ) then
                  halted <= '0';
               end if;
            end if;
         end if;
      end process P_HALT;

      haltedInp           <= halted;
      fifoWen             <= wenInp and not haltedInpEpClk;
      fullInp             <= fifoFull or haltedInpEpClk;
      mstInpVld           <= not fifoEmpty;
      bFramedInp          <= '1'; -- no framing
      mstInpDon           <= '0'; -- no framing

      -- only freeze user-access in halted state; EP interaction with the packet
      -- engine proceeds
      fifoRen             <= usb2EpOb.subInp.rdy;

      U_FIFO : entity work.Usb2Fifo
         generic map (
            DATA_WIDTH_G => Usb2ByteType'length,
            LD_DEPTH_G   => LD_FIFO_DEPTH_INP_G,
            LD_TIMER_G   => TIMER_WIDTH_G,
            OUT_REG_G    => ite( OUT_REG_INP_G, 1, 0 ),
            ASYNC_G      => ASYNC_G
         )
         port map (
            wrClk        => epClkLoc,
            wrRst        => epRstLoc,

            din          => datInp,
            wen          => fifoWen,
            full         => fifoFull,
            wrFilled     => filledInp,

            rdClk        => usb2Clk,
            rdRst        => usb2Rst,

            dou          => fifoDatInp,
            ren          => fifoRen,
            empty        => fifoEmpty,
            rdFilled     => open,

            minFill      => minFillInp,
            timer        => timeFillInp
         );

   end generate G_INP_FIFO;

   G_OUT_FIFO : if ( MAX_PKT_SIZE_OUT_G > 0 ) generate
      signal halted       : std_logic := '0';
      signal fifoWen      : std_logic;
      signal fifoRen      : std_logic;
      signal fifoEmpty    : std_logic;
      signal fifoFilled   : unsigned(LD_FIFO_DEPTH_OUT_G downto 0);
      signal fifoRdy      : std_logic := '0';
      signal lastWen      : std_logic := '0';
   begin

      P_SEQ : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( usb2Rst = '1' ) then
               halted    <= '0';
               fifoRdy   <= '0';
               lastWen   <= '0';
            else
               if ( (setHalt and selHaltOut) = '1' ) then
                  halted <= '1';
               end if;
               if ( (clrHalt and selHaltOut) = '1' ) then
                  halted <= '0';
               end if;
               lastWen <= fifoWen;
               if ( ( fifoRdy or fifoWen ) = '0' ) then
                  if ( fifoFilled <= 2**LD_FIFO_DEPTH_OUT_G - MAX_PKT_SIZE_OUT_G ) then
                     fifoRdy <= '1';
                  end if;
               else
                  if ( fifoWen = '1' and lastWen = '0' ) then
                     -- first packet can be accepted and starts being transferred
                     if (     ( 2**LD_FIFO_DEPTH_OUT_G < 2*MAX_PKT_SIZE_OUT_G              )
                          or  ( 2**LD_FIFO_DEPTH_OUT_G - 2*MAX_PKT_SIZE_OUT_G < fifoFilled ) ) then
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
      haltedOut           <= halted;
      fifoWen             <= usb2EpOb.mstOut.vld;
      subOutRdy           <= fifoRdy;
      emptyOut            <= fifoEmpty or haltedOut;
      fifoRen             <= renOut and not haltedOut;

      U_FIFO : entity work.Usb2Fifo
         generic map (
            DATA_WIDTH_G => Usb2ByteType'length,
            LD_DEPTH_G   => LD_FIFO_DEPTH_OUT_G,
            LD_TIMER_G   => 1,
            OUT_REG_G    => ite( OUT_REG_OUT_G, 1, 0 ),
            ASYNC_G      => ASYNC_G
         )
         port map (
            wrClk        => usb2Clk,
            wrRst        => usb2Rst,

            din          => usb2EpOb.mstOut.dat,
            wen          => fifoWen,
            full         => open,
            wrFilled     => fifoFilled,

            rdClk        => epClkLoc,
            rdRst        => epRstLoc,
            dou          => datOut,
            ren          => fifoRen,
            empty        => fifoEmpty,
            rdFilled     => filledOut,

            minFill      => open,
            timer        => open
         );

   end generate G_OUT_FIFO;

   P_COMB : process ( mstInpVld, haltedInp, fifoDatInp, bFramedInp, mstInpDon, haltedOut, subOutRdy ) is
   begin
      usb2EpIb            <= USB2_ENDP_PAIR_IB_INIT_C;
      usb2EpIb.mstInp.vld <= mstInpVld;
      usb2EpIb.stalledInp <= haltedInp;
      usb2EpIb.bFramedInp <= bFramedInp;
      usb2EpIb.mstInp.err <= '0';
      usb2EpIb.mstInp.don <= mstInpDon;
      usb2EpIb.mstInp.dat <= fifoDatInp;
      usb2EpIb.stalledOut <= haltedOut;
      usb2EpIb.subOut.rdy <= subOutRdy;
   end process P_COMB;

end architecture Impl;
