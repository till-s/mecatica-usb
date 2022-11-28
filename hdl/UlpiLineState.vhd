library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

-- NOTE: we currently don't support putting the phy into low-power mode as
--         - it is not clear how we could operate without the clock (assuming
--           the PHY drives the clock.
--         - power saving in the PHY compared to what an FPGA is eating is
--           very small.

entity UlpiLineState is
   generic (
      MARK_DEBUG_G   : boolean := false
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic := '0';

      -- ULPI
      ulpiRx         : in  UlpiRxType;

      -- ULPI register access
      ulpiRegReq     : out UlpiRegReqType;
      ulpiRegRep     : in  UlpiRegRepType;

      -- ULPI packet TX
      ulpiTxReq      : out UlpiTxReqType;
      ulpiTxRep      : in  UlpiTxRepType;

      hiSpeedEn      : in  std_logic := '0';

      -- generated control signals
      usb2Rst        : out std_logic;
      usb2Suspend    : out std_logic;
      -- usb2HiSpeed remains asserted while suspended
      usb2HiSpeed    : out std_logic;

      usb2RemWake    : in  std_logic := '0'
   );
end entity UlpiLineState;

architecture Impl of UlpiLineState is

-- Fig. C-2 timers
--                          min   max
--   TWTREV:            3000us   3125us
--   TWTRSTHS:           100us    875us  
--   TWTRSTFS:           2.5us   3000us  
--   TFILTSE0:           2.5us
-- Fig. C-3 timers
--   TUCH               1000us
--   TFILT               2.5us
--   TUCHEND                     7000us
--   TWTFS              1000us   2500us
-- 7.1.7.7
--   TWTRSM             5000us          bus must be idle
--                                      for this time before
--                                      device may remote-wakeup
--   TDRSMUP            1000us  15000us remote-wakeup hold resume signalling
--
-- How many timers do we need:
--   HS negotiation: TWFS > 6*TFILT;
--       if we make TFILT  = 120us then
--                  TUCH   = 1200us
--                  TWFS   = 1200us
--                  TWTREV = 3050us
--           T2 = T3 (1200us); TWTRSTFS = TWTRSTHS = TFILTSE0 = TFILT (120us)
--           TWTREV = IDLE (3060us)
--

   -- prescale time to 10us ticks
   constant PRESC_US_C              : natural := 10;
   constant PRESC_PERIOD_C          : natural := 60 * PRESC_US_C;
   constant LD_PRESC_C              : natural := 10;
   constant LD_TIME_120_C           : natural := 4;
   constant LD_TIME_1200_C          : natural := 7;
   constant LD_TIME_3060_C          : natural := 9;
   constant LD_TIME_5060_C          : natural := 9;
   constant PERIOD_120_C            : natural := 120  / PRESC_US_C;
   constant PERIOD_1200_C           : natural := 1200 / PRESC_US_C;
   constant PERIOD_3060_C           : natural := 3060 / PRESC_US_C;
   constant PERIOD_5060_C           : natural := 5060 / PRESC_US_C;

   constant ULPI_REG_FUN_CTL_C      : std_logic_vector(3 downto 0) := x"4";
   constant ULPI_REG_OTG_CTL_C      : std_logic_vector(3 downto 0) := x"A";

   -- disable D-/D+ pull-down resistors
   constant ULPI_OTG_CTL_INI_C      : std_logic_vector(7 downto 0) := x"00";

   -- transceiver control
   constant ULPI_FUN_CTL_X_MSK_C    : std_logic_vector(7 downto 0) := x"03";
   -- hi-speed
   constant ULPI_FUN_CTL_X_HS_C     : std_logic_vector(7 downto 0) := x"00";
   -- full-speed
   constant ULPI_FUN_CTL_X_FS_C     : std_logic_vector(7 downto 0) := x"01";
   -- term select
   constant ULPI_FUN_CTL_TERM_C     : std_logic_vector(7 downto 0) := x"04";

   constant ULPI_FUN_CTL_OP_MSK_C   : std_logic_vector(7 downto 0) := x"18";
   -- normal operation
   constant ULPI_FUN_CTL_OP_NRM_C   : std_logic_vector(7 downto 0) := x"00";
   -- disable bit-stuff and nrzi
   constant ULPI_FUN_CTL_OP_CHR_C   : std_logic_vector(7 downto 0) := x"10";
   constant ULPI_FUN_CTL_RST_C      : std_logic_vector(7 downto 0) := x"20";
   constant ULPI_FUN_CTL_SUSPEND_C  : std_logic_vector(7 downto 0) := x"40";

   constant ULPI_FUN_CTL_FS_C       : std_logic_vector(7 downto 0) :=
         ULPI_FUN_CTL_X_FS_C
      or ULPI_FUN_CTL_TERM_C
      or ULPI_FUN_CTL_OP_NRM_C;

   constant ULPI_FUN_CTL_HS_C       : std_logic_vector(7 downto 0) :=
         ULPI_FUN_CTL_X_HS_C
      or ULPI_FUN_CTL_OP_NRM_C;

   constant ULPI_FUN_CTL_CHIRP_C    : std_logic_vector(7 downto 0) :=
         ULPI_FUN_CTL_X_HS_C
      or ULPI_FUN_CTL_TERM_C
      or ULPI_FUN_CTL_OP_CHR_C;


   -- hopefully this can be used as a 'never seen a RXCMD' marker...
   constant ULPI_LINE_STATE_INI_C   : std_logic_vector(1 downto 0) := "11";

   type StateType is (INIT, INIT1, INIT2, FS_RUN, DRIVE_CHIRP, WAIT_FS, SUSPEND, WRITE_REG);

   type RegType   is record
      state       : StateType;
      nxtState    : StateType;
      txReq       : UlpiTxReqType;
      regReq      : UlpiRegReqType;
      lineState   : std_logic_vector(1 downto 0);
      usb2Rst     : std_logic;
      usb2Suspend : std_logic;
      usb2hiSpeed : std_logic;
      presc       : unsigned(    LD_PRESC_C downto 0);
      time120     : unsigned(LD_TIME_120_C  downto 0);
      time1200    : unsigned(LD_TIME_1200_C downto 0);
      time3060    : unsigned(LD_TIME_3060_C downto 0);
      time5060    : unsigned(LD_TIME_5060_C downto 0);
      count       : unsigned(             2 downto 0);
      se0Seen     : boolean;
      kSeen       : boolean;
      jSeen       : boolean;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => INIT,
      nxtState    => INIT,
      txReq       => ULPI_TX_REQ_INIT_C,
      regReq      => ULPI_REG_REQ_INIT_C,
      lineState   => ULPI_LINE_STATE_INI_C,
      usb2Rst     => '0',
      usb2Suspend => '0',
      usb2HiSpeed => '0',
      presc       => (others => '0'),
      time120     => (others => '0'),
      time1200    => (others => '0'),
      time3060    => (others => '0'),
      count       => (others => '0'),
      se0Seen     => false,
      kSeen       => false,
      jSeen       => false
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   attribute MARK_DEBUG of r : signal is toStr( MARK_DEBUG_G );

   procedure loadTimer(variable t: out unsigned; constant p : in natural) is
   begin
      -- timers always load the msbit = '1' follwed by the period. They
      -- count down until the msbit = '0', i.e. effectively counting down
      -- to '-1'; therefore we need to pre-decrement the period by 2
      -- (loading a timer with 0, i.e. '1' & "000" produces a period of 2)
      t := '1' & to_unsigned( p - 2, t'length - 1);
   end procedure loadTimer;

   procedure resetTimer(variable t: inout unsigned) is
   begin
      t := t;
      t(t'left) := '0';
   end procedure resetTimer;

   procedure decrTimer(variable t: inout unsigned) is
   begin
      t := t;
      if ( t(t'left) = '1' ) then
         t := t - 1;
      end if;
   end procedure decrTimer;

   function expiredTimer(constant t : in unsigned) return boolean is
   begin
      return t(t'left) = '0';
   end function expiredTimer;

   procedure writeReg(
      variable q : inout RegType;
      constant a : in    std_logic_vector(3 downto 0);
      constant v : in    std_logic_vector(7 downto 0)
   ) is
   begin
      q              := q;
      q.regReq.addr  := x"0" & a;
      q.regReq.wdat  := v;
      q.nxtState     := q.state;
      q.state        := WRITE_REG;
   end procedure writeReg;

begin

   P_COMB : process ( r, ulpiRx, ulpiTxRep, ulpiRegRep, usb2RemWake, hiSpeedEn ) is
      variable v : RegType;

      variable start120  : boolean;
      variable start1200 : boolean;
      variable start3060 : boolean;
   begin
      v            := r;

      start120     := false;
      start1200    := false;
      start3060    := false;

      -- get the line state
      if ( ulpiIsRxCmd( ulpiRx ) ) then
         v.lineState := ulpiRx.dat(1 downto 0);
      end if;

      if ( r.presc(r.presc'left) = '0' ) then
         loadTimer( v.presc, PRESC_PERIOD_C );
         -- run the timers
         decrTimer( v.time120  );
         decrTimer( v.time1200 );
         decrTimer( v.time3060 );
         decrTimer( v.time5060 );
      else
         v.presc := r.presc - 1;
      end if;

      -- remote wakeup
      if ( r.usb2Suspend = '0' ) then
         resetTimer( v.time5060 );
      elsif ( ( usb2RemWake = '1' ) and expiredTimer( v.time5060 ) ) then
         v.state := WAKEUP;
      end if;

      case ( r.state ) is
         when INIT  =>
            writeReg(v, ULPI_REG_OTG_CTL_C, ULPI_OTG_CTL_INI_C);
            v.nxtState := INIT1;

         when INIT1 =>
            writeReg(v, ULPI_REG_FUN_CTL_C, ULPI_FUN_CTL_FS_C );
            v.nxtState := INIT2;

         when INIT2 =>
            if ( v.lineState /= ULPI_LINE_STATE_INI_C ) then
               v.state   := FS_RUN;
            end if;

         when FS_RUN =>
            v.se0Seen := false;
            v.jSeen   := false;
            if    ( v.lineState = ULPI_RXCMD_LINE_STATE_SE0_C  ) then
               v.se0Seen := true;
               if ( r.se0Seen ) then
                  if ( expiredTimer( r.time1200 ) ) then
                     v.state   := DRIVE_CHIRP;
                     start1200 := true;
                  end if;
               else
                  start1200 := true;
                  resetTimer( v.time3060 );
               end if;
            elsif ( v.lineState = ULPI_RXCMD_LINE_STATE_FS_J_C  ) then
               v.jSeen := true;
               if ( r.jSeen ) then
                  if ( expiredTimer( r.time3060 ) ) then
                     v.state := SUSPEND;
                  end if;
               else
                  start3060 := true;
                  resetTimer( v.time1200 );
               end if;
            else
--  When we leave RUN_FS state then both timers are expired;
--  this is guaranteed by the above algorithm...
--               resetTimer( v.time1200 );
--               resetTimer( v.time3060 );
            end if;

         when DRIVE_CHIRP =>
            if ( hiSpeedEn = '1' and false ) then -- FIXME actually drive chirp
            end if;
            if ( expiredTimer( r.time1200 ) ) then
               v.state   := WAIT_FS;
            end if;

         when WAIT_FS =>
            if ( r.usb2Rst = '0' ) then
               v.usb2Rst := '1';
               start1200 := true;
            elsif ( expiredTimer( v.time1200 ) ) then
               v.usb2Rst     := '0';
               v.state       := INIT2; -- sample initial line state before going into FS_RUN
            end if;

         when SUSPEND =>
            v.se0Seen := false;
            v.kSeen   := false;
            if ( r.usb2Suspend = '0' ) then
               v.usb2Suspend := '1';
               loadTimer(v.time5060, PERIOD_5060_C);
            else
               if ( expiredTimer( r.time6000 ) then
                  -- no stable reset seen; keep trying
                  -- It is not quite clear what that means, though; the 
                  -- spec says that if this timer expires we go back to 'suspend'
                  -- but if SE0 keeps being flaky then we end up looping.
                  -- So I don't understand how this would be different to not using a T0
                  -- timer at all and simply waiting for a stable SE0
                  v.se0Seen := false;
                  resetTimer( v.time1200 );
               elsif ( expiredTimer( r.time1200 ) )
                  v.state       := RESET;
                  resetTimer( v.time6000 );
                  v.usb2Suspend := '0';
                  v.usb2Rst     := '1';
               end if;
               -- when we enter for the first time the 'seen' flags are reset
               -- due to the single cycle when usb2Suspend was not yet asserted
               if    ( v.lineState = ULPI_RXCMD_LINE_STATE_SE0_C  ) then
                  v.se0Seen := true;
                  if ( not r.se0Seen ) then
                     start6000 := true;
                     start1200 := true;
                  end if;
               elsif    ( v.lineState = ULPI_RXCMD_LINE_STATE_FS_K_C ) then
                  -- resume; we keep it simple go directly to run state
               else
                  start1200 := true;
               end if;

         when WRITE_REG =>
            if ( r.regReq.vld = '0' ) then
               v.regReq.vld   := '1';
               v.regReq.rdnwr := '0';
            elsif ( ulpiRegRep.ack = '1' ) then
               v.regReq.vld   := '0';
               v.state        := r.nxtState;
            end if;
      end case;

      if ( start120  ) then
         loadTimer( v.time120,  PERIOD_120_C  );
      end if;
      if ( start1200 ) then
         loadTimer( v.time1200, PERIOD_1200_C );
      end if;
      if ( start3060 ) then
         loadTimer( v.time3060, PERIOD_3060_C );
      end if;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   ulpiRegReq      <= r.regReq;
   ulpiTxReq       <= r.txReq;

   usb2Rst         <= r.usb2Rst;
   usb2Suspend     <= r.usb2Suspend;
   usb2hiSpeed     <= r.usb2hiSpeed;

end architecture Impl;
