library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

-- NOTE: we currently don't support putting the phy into low-power mode as
--         - it is not clear how we could operate without the clock (assuming
--           the PHY drives the fpga clock.
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

      usb2HiSpeedEn  : in  std_logic := '0';

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
-- 7.1.7.6
--   T2SUSP                     10000us (min seems to be 3ms)
-- 7.1.7.7
--   TWTRSM             5000us          bus must be idle
--                                      for this time before
--                                      device may remote-wakeup
--   TDRSMUP            1000us  15000us remote-wakeup hold resume signalling
-- Tbl 7-13
--   TDCHBIT              40us     60us (one chirp bit sent by host)
--
-- How many timers do we need:
--   HS negotiation: TWFS > 6*TFILT;  TFILT < TDCHBIT => tfilt < 40us
--       if we make TFILT  = 20us then
--                  TUCH   = 1200us
--                  TWFS   = 1200us
--                  TWTREV = 3050us
--      20us: TFILT = TFILTSE0
--     120us: TWTRSTHS
--    1200us: TUCH = TWTRSTFS = TWTFS = TDRSMUP
--    3060us: TWTREV = IDLE (T2SUSP) = (TUCH + TWTFS) 
--    5060us: TWTRSM = TUCHEND - TUCH
--

   -- prescale time to 10us ticks
   constant PRESC_US_C              : natural := 10;
   constant PRESC_PERIOD_C          : natural := 60 * PRESC_US_C;
   constant LD_PRESC_C              : natural := 10;
   constant LD_TIME_120_C           : natural := 4;
   constant LD_TIME_1200_C          : natural := 7;
   constant LD_TIME_3060_C          : natural := 9;
   constant LD_TIME_5060_C          : natural := 9;
   constant PERIOD_20_C             : natural := 20   / PRESC_US_C;
   constant PERIOD_120_C            : natural := 120  / PRESC_US_C;
   constant PERIOD_1200_C           : natural := 1200 / PRESC_US_C;
   constant PERIOD_3060_C           : natural := 3060 / PRESC_US_C;
   constant PERIOD_5060_C           : natural := 5060 / PRESC_US_C;

   constant ULPI_FUN_CTL_FS_C       : std_logic_vector(7 downto 0) :=
         ULPI_FUN_CTL_X_FS_C
      or ULPI_FUN_CTL_TERM_C
      or ULPI_FUN_CTL_OP_NRM_C
      or ULPI_FUN_CTL_SUSPENDM_C;

   constant ULPI_FUN_CTL_HS_C       : std_logic_vector(7 downto 0) :=
         ULPI_FUN_CTL_X_HS_C
      or ULPI_FUN_CTL_OP_NRM_C
      or ULPI_FUN_CTL_SUSPENDM_C;

   constant ULPI_FUN_CTL_CHIRP_C    : std_logic_vector(7 downto 0) :=
         ULPI_FUN_CTL_X_HS_C
      or ULPI_FUN_CTL_TERM_C
      or ULPI_FUN_CTL_OP_CHR_C
      or ULPI_FUN_CTL_SUSPENDM_C;

   constant ULPI_FUN_CTL_WKUP_K_C   : std_logic_vector(7 downto 0) :=
         ULPI_FUN_CTL_X_FS_C
      or ULPI_FUN_CTL_TERM_C
      or ULPI_FUN_CTL_OP_CHR_C
      or ULPI_FUN_CTL_SUSPENDM_C;

   -- hopefully this can be used as a 'never seen a RXCMD' marker...
   constant ULPI_LINE_STATE_INI_C   : std_logic_vector(1 downto 0) := "11";

   type StateType is (
      INIT,
      INIT1,
      INIT2,
      FS_RUN,
      HS_RUN,
      HS_INIT,
      HS_INIT1,
      INIT_CHIRP,
      DRIVE_CHIRP,
      DETECT_CHIRP,
      HOST_CHIRP,
      WAIT_FS,
      WAITRSTHS_START,
      WAITRSTHS,
      SUSPEND,
      DEBOUNCE_SE0,
      RESUME,
      WAKEUP,
      DRIVE_K,
      WRITE_REG
   );

   type RegType   is record
      state       : StateType;
      nxtState    : StateType;
      txReq       : UlpiTxReqType;
      regReq      : UlpiRegReqType;
      lineState   : std_logic_vector(1 downto 0);
      lineWanted  : std_logic_vector(1 downto 0);
      usb2Rst     : std_logic;
      usb2Suspend : std_logic;
      usb2hiSpeed : std_logic;
      presc       : unsigned(    LD_PRESC_C downto 0);
      timeSmall   : unsigned(LD_TIME_120_C  downto 0);
      time1200    : unsigned(LD_TIME_1200_C downto 0);
      time3060    : unsigned(LD_TIME_3060_C downto 0);
      time5060    : unsigned(LD_TIME_5060_C downto 0);
      count       : unsigned(             3 downto 0);
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
      lineWanted  => ULPI_LINE_STATE_INI_C,
      usb2Rst     => '0',
      usb2Suspend => '0',
      usb2HiSpeed => '0',
      presc       => (others => '0'),
      timeSmall   => (others => '0'),
      time1200    => (others => '0'),
      time3060    => (others => '0'),
      time5060    => (others => '0'),
      count       => (others => '0'),
      se0Seen     => false,
      kSeen       => false,
      jSeen       => false
   );

   signal r                  : RegType := REG_INIT_C;
   signal rin                : RegType;

   signal remWakeDbg         : std_logic;
   signal hiSpeedEnDbg       : std_logic;

   attribute MARK_DEBUG of r            : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of remWakeDbg   : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of hiSpeedEnDbg : signal is toStr( MARK_DEBUG_G );

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

   remWakeDbg   <= usb2RemWake;
   hiSpeedEnDbg <= usb2HiSpeedEn;

   P_COMB : process ( r, ulpiRx, ulpiTxRep, ulpiRegRep, usb2RemWake, usb2HiSpeedEn ) is
      variable v : RegType;

      variable start20   : boolean;
      variable start120  : boolean;
      variable start1200 : boolean;
      variable start3060 : boolean;
      variable start5060 : boolean;
   begin
      v            := r;

      start20      := false;
      start120     := false;
      start1200    := false;
      start3060    := false;
      start5060    := false;

      -- get the line state
      if ( ulpiIsRxCmd( ulpiRx ) ) then
         v.lineState := ulpiRx.dat(1 downto 0);
      end if;

      if ( r.presc(r.presc'left) = '0' ) then
         loadTimer( v.presc, PRESC_PERIOD_C );
         -- run the timers
         decrTimer( v.timeSmall );
         decrTimer( v.time1200  );
         decrTimer( v.time3060  );
         decrTimer( v.time5060  );
      else
         v.presc := r.presc - 1;
      end if;

      -- drive K as soon as the NOPID command byte has been
      -- has been consumed
      if ( ulpiTxRep.nxt = '1' ) then
         v.txReq.dat := (others => '0');
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
               v.state       := FS_RUN;
               v.se0Seen     := false;
               v.jSeen       := false;
               v.usb2Rst     := '0';
               v.usb2Suspend := '0';
            end if;

         when FS_RUN =>
            v.se0Seen := false;
            v.jSeen   := false;
            if    ( v.lineState = ULPI_RXCMD_LINE_STATE_SE0_C  ) then
               v.se0Seen := true;
               if ( r.se0Seen ) then
                  if ( expiredTimer( r.time1200 ) ) then
                     v.state   := INIT_CHIRP;
                  end if;
               else
                  -- TWTRSTFS
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
                  -- T2SUSP
                  start3060 := true;
                  resetTimer( v.time1200 );
               end if;
            else
--  When we leave RUN_FS state then both timers are expired;
--  this is guaranteed by the above algorithm...
--               resetTimer( v.time1200 );
--               resetTimer( v.time3060 );
            end if;

         when HS_INIT =>
            writeReg(v, ULPI_REG_FUN_CTL_C, ULPI_FUN_CTL_HS_C );
            v.nxtState := HS_INIT1;

         when HS_INIT1 =>
            -- TWTREV
            start3060     := true;
            v.usb2Rst     := '0';
            v.usb2HiSpeed := '1';
            v.usb2Suspend := '0';
            v.state       := HS_RUN;

         when HS_RUN =>
            if ( expiredTimer( r.time3060 ) ) then
               writeReg(v, ULPI_REG_FUN_CTL_C, ULPI_FUN_CTL_FS_C );
               v.nxtState := WAITRSTHS_START;
            elsif ( v.lineState /= ULPI_RXCMD_LINE_STATE_SE0_C ) then
               -- TWTREV
               start3060  := true;
            end if;

         when WAITRSTHS_START =>
            -- TWTRSTHS
            start120 := true;
            v.state  := WAITRSTHS;

         when WAITRSTHS =>
            if ( expiredTimer( r.timeSmall ) ) then
               if ( v.lineState = ULPI_RXCMD_LINE_STATE_SE0_C ) then
                  v.state := INIT_CHIRP;
               else
                  v.state := SUSPEND;
               end if;
            end if;

         when INIT_CHIRP =>
            if ( usb2HiSpeedEn = '1' ) then
               writeReg(v, ULPI_REG_FUN_CTL_C, ULPI_FUN_CTL_CHIRP_C );
               v.nxtState    := DRIVE_CHIRP;
            else
               -- TUCH + TWTFS >= 2000, <= 3500
               start3060     := true ;
               v.state       := WAIT_FS;
            end if;
            v.usb2Rst     := '1';
            v.usb2HiSpeed := '0';

         when DRIVE_CHIRP =>
            v.nxtState := DETECT_CHIRP;
            v.state    := DRIVE_K;

         when DETECT_CHIRP =>
            -- TWTFS
            start1200    := true;
            -- 'count' is not formally a timer but uses the same algorithm
            loadTimer( v.count, 6 );
            v.lineWanted := ULPI_RXCMD_LINE_STATE_FS_K_C;
            v.state      := HOST_CHIRP;
            -- TFILT
            start20      := true;

         when HOST_CHIRP =>
            if ( expiredTimer( r.timeSmall ) ) then
               -- again: 'count' is not a timer but uses the same semantics
               if ( expiredTimer( r.count ) ) then
                  v.state := HS_INIT;
               else
                  -- TFILT
                  start20      := true;
                  v.lineWanted := not r.lineWanted; -- J <=> K
                  v.count      := r.count - 1;
               end if;
            elsif ( v.lineState /= r.lineWanted ) then
               -- TFILT
               start20 := true;
            end if;
            if ( expiredTimer( r.time1200 ) ) then
               v.state := INIT1;
            end if;

         when WAIT_FS =>
            if ( expiredTimer( r.time3060 ) ) then
               -- ensure OP_MODE is correct
               v.state       := INIT1;
            end if;

         when SUSPEND =>
            if ( r.usb2Suspend = '0' ) then
               v.usb2Suspend   := '1';
               -- The 5060 timer serves two purposes: 
               --  - while in SUSPEND state it times TWTRSM, the time we must wait
               --    until honoring a remote-wakeup.
               --  - when in DEBOUNCE_SE0 state it times TUCHEND - TUCH, the time
               --    when we must return to SUSPEND>
               -- TWTRSM
               start5060       := true;
            else
               if    ( v.lineState = ULPI_RXCMD_LINE_STATE_SE0_C  ) then
                  -- TUCHEND - TUCH
                  start5060   := true;
                  -- TFILTSE0
                  start20     := true;
                  v.state     := DEBOUNCE_SE0;
               elsif    ( v.lineState = ULPI_RXCMD_LINE_STATE_FS_K_C ) then
                  v.state     := RESUME;
               -- TWTRSM expired?
               elsif ( ( usb2RemWake = '1' ) and expiredTimer( v.time5060 ) ) then
                  -- remote wakeup
                  writeReg(v, ULPI_REG_FUN_CTL_C, ULPI_FUN_CTL_WKUP_K_C);
                  v.nxtState  := WAKEUP;
               end if;
            end if;

         when DEBOUNCE_SE0 =>
            -- TUCHEND - TUCH expired?
            if ( expiredTimer( r.time5060 ) ) then
               -- no stable reset seen; keep trying
               -- It is not quite clear what that means, though; the 
               -- spec says that if this timer expires we go back to 'suspend'
               -- but if SE0 keeps being flaky then we end up looping.
               -- So I don't understand how this would be different to not using a T0
               -- timer at all and simply waiting for a stable SE0.
               -- One difference: the machine checks for 'K' only in SUSPEND state.

               -- TWTRSM (see comment above)
               start5060     := true;
               v.state       := SUSPEND;
            elsif ( expiredTimer( r.timeSmall ) ) then
               v.state       := INIT_CHIRP;
            elsif    ( v.lineState /= ULPI_RXCMD_LINE_STATE_SE0_C  ) then
               -- TFILTSE0
               start20       := true;
            end if;

         when RESUME =>
            -- FIXME: should we have a timeout here?
            if ( (usb2HiSpeedEn and r.usb2HiSpeed) = '1' ) then
               if ( v.lineState = ULPI_RXCMD_LINE_STATE_SE0_C  ) then
                  v.state := HS_INIT;
               end if;
            else
               if ( v.lineState = ULPI_RXCMD_LINE_STATE_FS_J_C  ) then
                  -- ensure OP_MODE normal
                  v.state := INIT1;
               end if;
            end if;

         when WAKEUP =>
            v.nxtState := RESUME;
            v.state    := DRIVE_K;

         -- driving remote wakeup and hi-speed chirp requires the
         -- same timing and txReq signal
         when DRIVE_K =>
            if ( r.txReq.vld = '0' ) then
               v.txReq.vld := '1';
               v.txReq.dat := ULPI_TXCMD_TX_C & x"0"; -- NOPID
               -- TUCH / TDRSMUP
               start1200   := true;
            elsif ( expiredTimer( r.time1200 ) ) then
               if ( ulpiTxRep.nxt = '1' ) then
                  v.txReq.vld := '0';
                  v.state     := r.nxtState;
               end if;
            end if;

         when WRITE_REG =>
            if ( r.regReq.vld = '0' ) then
               v.regReq.vld   := '1';
               v.regReq.rdnwr := '0';
            elsif ( (ulpiRegRep.ack = '1') and (ulpiRegRep.err = '0') ) then
               -- if there is an error (aborted by PHY) we keep retrying
               v.regReq.vld   := '0';
               v.state        := r.nxtState;
            end if;
      end case;

      if ( start120  ) then
         loadTimer( v.timeSmall,  PERIOD_120_C  );
      end if;
      if ( start20  ) then
         loadTimer( v.timeSmall,  PERIOD_20_C );
      end if;
      if ( start1200 ) then
         loadTimer( v.time1200, PERIOD_1200_C );
      end if;
      if ( start3060 ) then
         loadTimer( v.time3060, PERIOD_3060_C );
      end if;
      if ( start5060 ) then
         loadTimer( v.time5060, PERIOD_5060_C );
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
