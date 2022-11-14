library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.UsbUtilPkg.all;
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
      -- add an output regster to the INP bound FIFO (to improve timing)
      OUT_REG_INP_G                : boolean  := false;
      -- add an output regster to the OUT bound FIFO (to improve timing)
      OUT_REG_OUT_G                : boolean  := false
   );
   port (
      clk                          : in  std_logic;

      rst                          : in  std_logic := '0';

      -- Endpoints are attached here (1 and up)
      usb2EpIb                     : out Usb2EndpPairIbType;
      usb2EpOb                     : in  Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;

      datInp                       : in  Usb2ByteType := (others => '0');
      wenInp                       : in  std_logic    := '0';
      filledInp                    : out unsigned(LD_FIFO_DEPTH_INP_G downto 0) := (others => '0');
      fullInp                      : out std_logic    := '1';
      -- accumulate 'minFillInp' items before passing to the endpoint
      minFillInp                   : in  unsigned(LD_FIFO_DEPTH_INP_G - 1 downto 0) := (others => '0');
      -- if more then 'timeFillInp' clock cycles expire since the last
      -- item was written the fifo contents are passed to USB (even
      -- if 'minFillInp' has not been reached). Similary to termios' 
      -- VMIN+VTIME.
      --  - All-ones waits indefinitely. 
      --  - Time may be reduced while a wait is in progress.
      timeFillInp                  : in  unsigned(TIMER_WIDTH_G - 1 downto 0) := (others => '0');

      datOut                       : out Usb2ByteType := (others => '0');
      renOut                       : in  std_logic    := '0';
      filledOut                    : out unsigned(LD_FIFO_DEPTH_OUT_G downto 0) := (others => '0');
      emptyOut                     : out std_logic    := '1';

      setHaltInp                   : in  std_logic    := '0';
      clrHaltInp                   : in  std_logic    := '0';
      setHaltOut                   : in  std_logic    := '0';
      clrHaltOut                   : in  std_logic    := '0'
   );
end entity Usb2FifoEp;

architecture Impl of Usb2FifoEp is

   function ite(constant c: boolean; constant a,b : natural) return natural is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;  

begin

   assert MAX_PKT_SIZE_INP_G = 0 or MAX_PKT_SIZE_INP_G <= 2**LD_FIFO_DEPTH_INP_G
      report "Inconsistent INP fifo depth"
      severity failure;

   assert MAX_PKT_SIZE_OUT_G = 0 or MAX_PKT_SIZE_OUT_G <= 2**LD_FIFO_DEPTH_OUT_G
      report "Inconsistent OUT fifo depth"
      severity failure;

   G_INP_FIFO : if ( MAX_PKT_SIZE_INP_G > 0 ) generate
      signal halted       : std_logic := '0';
      signal fifoWen      : std_logic;
      signal fifoFull     : std_logic;
      signal fifoRen      : std_logic;
      signal fifoEmpty    : std_logic;
   begin

      P_HALT : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               halted  <= '0';
            else
               if ( setHaltInp = '1' ) then
                  halted <= '1';
               end if;
               if ( clrHaltInp = '1' ) then
                  halted <= '0';
               end if;
            end if;
         end if;
      end process P_HALT;

      fifoWen             <= wenInp and not halted;
      fullInp             <= fifoFull or halted;

      fifoRen             <= usb2EpOb.subInp.rdy and not halted;
      usb2EpIb.mstInp.vld <= not fifoEmpty       and not halted;
      usb2EpIb.stalledInp <= halted;
      usb2EpIb.bFramedInp <= '1'; -- no framing
      usb2EpIb.mstInp.err <= '0';
      usb2EpIb.mstInp.don <= '0'; -- no framing

      U_FIFO : entity work.Usb2Fifo
         generic map (
            DATA_WIDTH_G => Usb2ByteType'length,
            LD_DEPTH_G   => LD_FIFO_DEPTH_INP_G,
            LD_TIMER_G   => TIMER_WIDTH_G,
            OUT_REG_G    => ite( OUT_REG_INP_G, 1, 0 )
         )
         port map (
            clk          => clk,
            rst          => rst,

            din          => datInp,
            wen          => fifoWen,
            full         => fifoFull,

            dou          => usb2EpIb.mstInp.dat,
            ren          => fifoRen,
            empty        => fifoEmpty,

            filled       => filledInp,
            minFill      => minFillInp,
            timer        => timeFillInp
         );

   end generate G_INP_FIFO;

   G_INP_NO_FIFO : if ( MAX_PKT_SIZE_INP_G = 0 ) generate
   begin
      usb2EpIb.mstInp     <= USB2_STRM_MST_INIT_C;
      usb2EpIb.stalledInp <= '1';
      usb2EpIb.bFramedInp <= '0';
   end generate G_INP_NO_FIFO;

   G_OUT_FIFO : if ( MAX_PKT_SIZE_OUT_G > 0 ) generate
      signal halted       : std_logic := '0';
      signal fifoWen      : std_logic;
      signal fifoRen      : std_logic;
      signal fifoEmpty    : std_logic;
      signal fifoFilled   : unsigned(LD_FIFO_DEPTH_OUT_G downto 0);
      signal fifoRdy      : std_logic := '0';
      signal lastWen      : std_logic := '0';
   begin

      P_HALT : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               halted  <= '0';
               fifoRdy <= '0';
               lastWen <= '0';
            else
               if ( setHaltOut = '1' ) then
                  halted <= '1';
               end if;
               if ( clrHaltOut = '1' ) then
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
      end process P_HALT;

      fifoWen             <= usb2EpOb.mstOut.vld and not halted;
      emptyOut            <= fifoEmpty or halted;
      fifoRen             <= renOut and not halted;
      usb2EpIb.subOut.rdy <= fifoRdy and not halted;

      usb2EpIb.stalledOut <= halted;
      filledOut           <= fifoFilled;

      U_FIFO : entity work.Usb2Fifo
         generic map (
            DATA_WIDTH_G => Usb2ByteType'length,
            LD_DEPTH_G   => LD_FIFO_DEPTH_OUT_G,
            LD_TIMER_G   => 1,
            OUT_REG_G    => ite( OUT_REG_OUT_G, 1, 0 )
         )
         port map (
            clk          => clk,
            rst          => rst,

            din          => usb2EpOb.mstOut.dat,
            wen          => fifoWen,
            full         => open,

            dou          => datOut,
            ren          => fifoRen,
            empty        => fifoEmpty,

            filled       => fifoFilled,
            minFill      => open,
            timer        => open
         );

   end generate G_OUT_FIFO;

   G_OUT_NO_FIFO : if ( MAX_PKT_SIZE_OUT_G = 0 ) generate
   begin
      usb2EpIb.subOut     <= USB2_STRM_SUB_INIT_C;
      usb2EpIb.stalledOut <= '1';
   end generate G_OUT_NO_FIFO;

end architecture Impl;
