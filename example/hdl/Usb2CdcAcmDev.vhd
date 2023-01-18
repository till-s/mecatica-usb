-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Instantiation of a CDC ACM Endpoint with a FIFO interface as well
-- as the necessary IO-Buffers

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library unisim;
use     unisim.vcomponents.all;

use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;
use     work.Usb2AppCfgPkg.all;
use     work.StdLogPkg.all;

entity Usb2CdcAcmDev is
   generic (
      SYS_CLK_PERIOD_NS_G  : real     := 20.0;
      ULPI_CLK_MODE_INP_G  : boolean  := true;

      -- ULPI INPUT CLOCK MODE PARAMETERS

      -- in ULPI INPUT clock mode the ULPI clock is generated from
      -- sysClk with an MMCM - depending on the system clock rate
      -- the CLK_MULT_F_G/CLK0_DIV_G/REF_CLK_DIV_G must be set to
      -- generate the 60MHz ULPI clock at CLKOUT0 of the MMCM
      REF_CLK_DIV_G        : positive := 1;
      CLK_MULT_F_G         : real     := 24.0;
      CLK0_DIV_G           : positive := 20;
      -- CLKOUT2 is not currently used by could be employed to
      -- generate 200MHz for an IDELAY control module
      CLK2_DIV_G           : positive := 6;
      -- CLKOUT1 is used to generate a phase-shifted clock that
      -- toggles the DDR which produces the ULPI clock. This phase
      -- shift helps with timing and *must* be at least slightly negative
      -- or the multicycle exception constraint must be removed!
      -- (use a negative phase-shift to compensate
      -- the significant delays in the clock path and the output delay of the ULPI
      -- transceiver).
      CLK1_INP_PHASE_G     : real     := -29.25;

      -- ULPI OUTPUT CLOCK MODE PARAMETERS

      -- in ULPI output clock mode the internal ULPI clock is phase-shifted
      -- by an MMCM to help timing
      -- phase must be a multiple of 45/CLK0_DIV = 3.0 (in output mode CLK0_DIV_G
      -- is not used!)
      -- Note that a small positive phase *must* be used -- otherwise the
      -- multicycle exception in the constraints must be removed!
      -- (delay the internal clock to compensate for the output delay of the
      -- ULPI transceiver)
      CLK0_OUT_PHASE_G     : real     := 15.0;

      NUM_I_REGS_G         : natural  := 2;
      NUM_O_REGS_G         : natural  := 2;
      MARK_DEBUG_G         : boolean  := false
   );
   port (
      refClkNb     : in    std_logic;

      -- connect to the device pin
      ulpiClk      : inout std_logic;
      -- reset the ulpi low-level interface; should not be necessary
      ulpiRst      : in    std_logic := '0';
      ulpiStp      : inout std_logic;
      ulpiDir      : in    std_logic;
      ulpiNxt      : in    std_logic;
      ulpiDat      : inout std_logic_vector(7 downto 0);

      ulpiClkOut   : out   std_logic;

      usb2Rst      : out   std_logic;

      refLocked    : out   std_logic;

      -- control vector
      -- iRegs(0)(10 downto 0) : min. fill level of the IN fifo until data are sent to USB
      -- iRegs(0)(27)          : enable 'blast' mode; OUT fifo is constantly drained; IN fifo
      --                         is blast with an incrementing 8-bit counter.
      -- iRegs(0)(28)          : disable 'loopback' mode; OUT fifo is fed into IN fifo; loopback
      --                         is *enabled* by default. Note: 'blast' overrides 'loopback'.
      -- iRegs(0)(29)          : assert forced ULPI STP (useful to bring the PHY to reason if it holds DIR)
      -- iRegs(0)(30)          : mask/disable IN/OUT fifo's write/read enable when set.
      -- iRegs(0)(31)          : USB remote wakeup

      -- iRegs(1)              : IN fifo fill timer (in ulpi CLK cycles)
      --                         fill-level and fill-timer work like termios VMIN/VTIME
      iRegs        : in    Slv32Array(0 to NUM_I_REGS_G - 1) := (others => (others => '0'));
      -- status vector
      -- oRegs(0)              : IN  fifo fill level
      -- oRegs(1)              : OUT fifo fill level
      oRegs        : out   Slv32Array(0 to NUM_O_REGS_G - 1);

      lineBreak    : out   std_logic := '0';

      regReq       : in    UlpiRegReqType;
      regRep       : out   UlpiRegRepType;

      fifoOutDat   : out   Usb2ByteType;
      fifoOutEmpty : out   std_logic;
      fifoOutFill  : out   unsigned(15 downto 0);
      fifoOutRen   : in    std_logic := '1';

      fifoInpDat   : in    Usb2ByteType := (others => '0');
      fifoInpFull  : out   std_logic;
      fifoInpFill  : out   unsigned(15 downto 0);
      fifoInpWen   : in    std_logic := '1';

      clk2Nb       : out   std_logic := '0';

      i2sBCLK      : in    std_logic;
      i2sPBLRC     : in    std_logic;
      i2sPBDAT     : out   std_logic
   );
end entity Usb2CdcAcmDev;

architecture Impl of Usb2CdcAcmDev is
   attribute MARK_DEBUG                        : string;

   constant USE_MMCM_C                         : boolean := true;

   constant N_EP_C                             : natural := USB2_APP_NUM_ENDPOINTS_F(USB2_APP_DESCRIPTORS_C);

   constant CDC_BULK_EP_IDX_C                  : natural := 1;
   constant BADD_ISO_EP_IDX_C                  : natural := 3;
   constant CDC_IF_NUM_C                       : natural := 0;
   constant BADD_IF_NUM_C                      : natural := 2;

   constant MAX_PKT_SIZE_INP_C                 : natural := 512;
   constant MAX_PKT_SIZE_OUT_C                 : natural := 512;
   constant LD_FIFO_DEPTH_INP_C                : natural := 10;
   constant LD_FIFO_DEPTH_OUT_C                : natural := 10;

   signal fifoTimer                            : unsigned(31 downto 0) := (others => '0');
   signal fifoMinFill                          : unsigned(LD_FIFO_DEPTH_INP_C - 1 downto 0) := (others => '0');
   signal ulpiClkLoc                           : std_logic;
   signal ulpiClkLocNb                         : std_logic;

   signal usb2RstLoc                           : std_logic;

   signal ulpiIb                               : UlpiIbType;
   signal ulpiOb                               : UlpiObType;

   type   MuxSelType                           is ( NONE, CDC, BADD );

   signal usb2Ep0ReqParam                      : Usb2CtlReqParamType;
   signal usb2Ep0CDCCtlExt                     : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
   signal usb2Ep0BADDCtlExt                    : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
   signal usb2Ep0CtlExt                        : Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
   signal usb2Ep0BADDCtlEpExt                  : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal usb2Ep0CtlEpExt                      : Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;
   signal usb2DevStatus                        : Usb2DevStatusType;

   signal muxSel                               : MuxSelType         := NONE;
   signal muxSelIn                             : MuxSelType         := NONE;

   signal gnd                                  : std_logic := '0';

   signal usb2Rx                               : Usb2RxType;

   signal usb2EpIb                             : Usb2EndpPairIbArray(1 to N_EP_C - 1) := ( others => USB2_ENDP_PAIR_IB_INIT_C );

   -- note EP0 output can be observed here; an external agent extending EP0 functionality
   -- needs to listen to this.
   signal usb2EpOb                             : Usb2EndpPairObArray(0 to N_EP_C - 1) := ( others => USB2_ENDP_PAIR_OB_INIT_C );

   signal fInp                                 : unsigned(LD_FIFO_DEPTH_INP_C downto 0) := (others => '0');
   signal fOut                                 : unsigned(LD_FIFO_DEPTH_OUT_C downto 0) := (others => '0');

   attribute MARK_DEBUG                        of usb2Ep0ReqParam   : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG                        of usb2Ep0CtlExt     : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG                        of usb2Ep0CtlEpExt   : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG                        of muxSel            : signal is toStr(MARK_DEBUG_G);

begin

   P_MUX : process ( muxSel, usb2Ep0ReqParam, usb2Ep0CDCCtlExt, usb2Ep0BADDCtlExt, usb2Ep0BADDCtlEpExt ) is
      variable v : MuxSelType;
   begin

      v := muxSel;

      usb2Ep0CtlExt   <= USB2_CTL_EXT_NAK_C;
      usb2Ep0CtlEpExt <= USB2_ENDP_PAIR_IB_INIT_C;

      if ( usb2Ep0ReqParam.vld = '1' ) then
         -- new mux setting
         v := NONE;
         if ( usb2Ep0ReqParam.reqType = USB2_REQ_TYP_TYPE_CLASS_C ) then
            if    ( usb2CtlReqDstInterface( usb2Ep0ReqParam, toUsb2InterfaceNumType( CDC_IF_NUM_C ) ) ) then
               v := CDC;
            elsif ( usb2CtlReqDstInterface( usb2Ep0ReqParam, toUsb2InterfaceNumType( BADD_IF_NUM_C ) ) ) then
               v := BADD;
            end if;
         end if;
         -- blank the 'ack' flag during this cycle
         usb2Ep0CtlExt   <= USB2_CTL_EXT_INIT_C;
      end if;

      -- must switch the mux on the same cycle we see 'vld' because that's
      -- when '
      if    ( muxSel = CDC  ) then
         usb2Ep0CtlExt   <= usb2Ep0CDCCtlExt;
      elsif ( muxSel = BADD ) then
         usb2Ep0CtlExt   <= usb2Ep0BADDCtlExt;
         usb2Ep0CtlEpExt <= usb2Ep0BADDCtlEpExt;
      end if;

      muxSelIn <= v;
   end process P_MUX;

   P_SEL : process( ulpiClkLoc ) is
   begin
      if ( rising_edge( ulpiClkLoc ) ) then
         if ( usb2RstLoc = '1' ) then
            muxSel <= NONE;
         else
            muxSel <= muxSelIn;
         end if;
      end if;
   end process P_SEL;

   B_FIFO : block is
      signal fifoDat  : Usb2ByteType;
      signal iWen     : std_logic := '0';
      signal oRen     : std_logic := '0';
      signal iFull    : std_logic := '0';
      signal oEmpty   : std_logic := '0';
      signal cnt      : unsigned(7 downto 0)         := (others => '0');
      signal blast    : std_logic := '0';
      signal loopback : std_logic := '0';
      signal iDat     : std_logic_vector(7 downto 0) := (others => '0');
   begin

      fifoMinFill <= unsigned(iRegs(0)(fifoMinFill'range));
      fifoTimer   <= unsigned(iRegs(1)(fifoTimer'range));

      U_BRK : entity work.CDCACMSendBreak
         generic map (
            CDC_IFC_NUM_G               => toUsb2InterfaceNumType( CDC_IF_NUM_C )
         )
         port map (
            clk                         => ulpiClkLoc,
            rst                         => usb2RstLoc,
            usb2SOF                     => usb2Rx.pktHdr.sof,
            usb2Ep0ReqParam             => usb2Ep0ReqParam,
            usb2Ep0CtlExt               => usb2Ep0CDCCtlExt,
            lineBreak                   => lineBreak
         );

      U_FIFO_EP : entity work.Usb2FifoEp
         generic map (
            MAX_PKT_SIZE_INP_G          => MAX_PKT_SIZE_INP_C,
            MAX_PKT_SIZE_OUT_G          => MAX_PKT_SIZE_OUT_C,
            LD_FIFO_DEPTH_INP_G         => LD_FIFO_DEPTH_INP_C,
            LD_FIFO_DEPTH_OUT_G         => LD_FIFO_DEPTH_OUT_C,
            TIMER_WIDTH_G               => fifoTimer'length
         )
         port map (
            clk                         => ulpiClkLoc,
            rst                         => usb2RstLoc,
            usb2EpIb                    => usb2EpIb(CDC_BULK_EP_IDX_C),
            usb2EpOb                    => usb2EpOb(CDC_BULK_EP_IDX_C),

            datInp                      => iDat,
            wenInp                      => iWen,
            filledInp                   => fInp,
            fullInp                     => iFull,
            minFillInp                  => fifoMinFill,
            timeFillInp                 => fifoTimer,

            datOut                      => fifoDat,
            renOut                      => oRen,
            filledOut                   => fOut,
            emptyOut                    => oEmpty,

            selHaltInp                  => usb2DevStatus.selHaltInp(1),
            selHaltOut                  => usb2DevStatus.selHaltOut(1),
            setHalt                     => usb2DevStatus.setHalt,
            clrHalt                     => usb2DevStatus.clrHalt
         );

      P_CNT : process ( ulpiClkLoc ) is
      begin
         if ( rising_edge( ulpiClkLoc ) ) then

            if ( (blast and iWen) = '1' ) then
               cnt <= cnt + 1;
            end if;
         end if;
      end process P_CNT;


      P_COMB : process ( fifoInpDat, fifoDat, blast, loopback, cnt, iRegs(0), iFull, oEmpty, fifoInpWen, fifoOutRen ) is
         variable wen : std_logic;
         variable ren : std_logic;
      begin
         fifoOutEmpty <= '1';
         fifoInpFull  <= '1';
         wen          := not iFull  and not iRegs(0)(30);
         ren          := not oEmpty and not iRegs(0)(30);
         if    ( blast = '1' ) then
            iDat         <= std_logic_vector( cnt );
            wen          := wen and '1';
            ren          := ren and '1';
         elsif ( loopback = '1' ) then
            iDat         <= fifoDat;
            wen          := wen and not oEmpty;
            ren          := ren and not iFull;
         else
            fifoOutEmpty <= oEmpty;
            fifoInpFull  <= iFull;
            iDat         <= fifoInpDat;
            wen          := wen and fifoInpWen;
            ren          := ren and fifoOutRen;
         end if;
         iWen <= wen;
         oRen <= ren;
      end process P_COMB;

      blast        <= iRegs(0)(27);
      loopback     <= not iRegs(0)(28);

      fifoOutDat   <= fifoDat;
      fifoOutFill  <= resize( fOut, fifoOutFill'length );

      fifoInpFill  <= resize( fInp, fifoInpFill'length );
   end block B_FIFO;

   B_ISO : block is
   begin
      U_BADD_CTL : entity work.BADDSpkrCtl
         generic map (
            AC_IFC_NUM_G              => toUsb2InterfaceNumType(BADD_IF_NUM_C)
         )
         port map (
            clk                       => ulpiClkLoc,
            rst                       => usb2RstLoc,

            usb2Ep0ReqParam           => usb2Ep0ReqParam,
            usb2Ep0CtlExt             => usb2Ep0BADDCtlExt,
            usb2Ep0ObExt              => usb2Ep0BADDCtlEpExt,
            usb2Ep0IbExt              => usb2EpOb(0),

            volLeft                   => open,
            volRight                  => open,
            volMaster                 => open,
            muteLeft                  => open,
            muteRight                 => open,
            muteMaster                => open,
            powerState                => open
         );

      U_BADD_PB : entity work.I2SPlayback
         generic map (
            SAMPLE_SIZE_G             => 2,
            MARK_DEBUG_G              => true
         )
         port map (
            usb2Clk                   => ulpiClkLoc,
            usb2Rst                   => usb2RstLoc,
            usb2Rx                    => usb2Rx,
            usb2DevStatus             => usb2DevStatus,
            usb2EpIb                  => usb2EpOb(BADD_ISO_EP_IDX_C),
            usb2EpOb                  => usb2EpIb(BADD_ISO_EP_IDX_C),

            i2sBCLK                   => i2sBCLK,
            i2sPBLRC                  => i2sPBLRC,
            i2sPBDAT                  => i2sPBDAT
         );

   end block B_ISO;

   G_MMCM : if ( ULPI_CLK_MODE_INP_G or USE_MMCM_C ) generate

      signal clkFbI, clkFbO    : std_logic;
      signal refClkLoc         : std_logic;

      function ite(constant x : boolean; constant a,b : real) return real is
      begin if x then return a; else return b; end if; end function ite;

      function ite(constant x : boolean; constant a,b : natural) return natural is
      begin if x then return a; else return b; end if; end function ite;

      constant CLK_MULT_F_C    : real    := ite( ULPI_CLK_MODE_INP_G, CLK_MULT_F_G,        15.000 );
      constant REF_PERIOD_C    : real    := ite( ULPI_CLK_MODE_INP_G, SYS_CLK_PERIOD_NS_G, 16.667 );
      constant CLK0_DIV_C      : natural := ite( ULPI_CLK_MODE_INP_G, CLK0_DIV_G,          15     );
      constant CLK2_DIV_C      : natural := ite( ULPI_CLK_MODE_INP_G, CLK2_DIV_G,          15     );
      constant REF_CLK_DIV_C   : natural := ite( ULPI_CLK_MODE_INP_G, REF_CLK_DIV_G,        1     );
      -- phase must be a multiple of 45/CLK0_DIV_G
      constant CLKOUT0_PHASE_C : real    := ite( ULPI_CLK_MODE_INP_G, 0.00,                CLK0_OUT_PHASE_G);

      signal ulpiClkRegLoc     : std_logic := '0';
      signal ulpiClkRegNb      : std_logic;

   begin

      G_REFCLK_ULPI : if ( not ULPI_CLK_MODE_INP_G ) generate
         U_BUF : IBUF
            port map (
               I => ulpiClk,
               O => refClkLoc
            );
      end generate G_REFCLK_ULPI;

      G_REF_SYS : if ( ULPI_CLK_MODE_INP_G ) generate
         refClkLoc <= refClkNb;
      end generate G_REF_SYS;

      U_MMCM : MMCME2_BASE
         generic map (
            BANDWIDTH => "OPTIMIZED",  -- Jitter programming (OPTIMIZED, HIGH, LOW)
            CLKFBOUT_MULT_F => CLK_MULT_F_C,    -- Multiply value for all CLKOUT (2.000-64.000).
            CLKFBOUT_PHASE => 0.0,     -- Phase offset in degrees of CLKFB (-360.000-360.000).
            CLKIN1_PERIOD => REF_PERIOD_C,      -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
            -- CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
            CLKOUT1_DIVIDE => CLK0_DIV_C,
            CLKOUT2_DIVIDE => CLK2_DIV_C,
            CLKOUT3_DIVIDE => CLK0_DIV_C,
            CLKOUT4_DIVIDE => CLK0_DIV_C,
            CLKOUT5_DIVIDE => CLK0_DIV_C,
            CLKOUT6_DIVIDE => CLK0_DIV_C,
            CLKOUT0_DIVIDE_F => real(CLK0_DIV_C),   -- Divide amount for CLKOUT0 (1.000-128.000).
            -- CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
            CLKOUT0_DUTY_CYCLE => 0.5,
            CLKOUT1_DUTY_CYCLE => 0.5,
            CLKOUT2_DUTY_CYCLE => 0.5,
            CLKOUT3_DUTY_CYCLE => 0.5,
            CLKOUT4_DUTY_CYCLE => 0.5,
            CLKOUT5_DUTY_CYCLE => 0.5,
            CLKOUT6_DUTY_CYCLE => 0.5,
            -- CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
            CLKOUT0_PHASE => CLKOUT0_PHASE_C,
            CLKOUT1_PHASE => CLK1_INP_PHASE_G,
            CLKOUT2_PHASE => 0.0,
            CLKOUT3_PHASE => 0.0,
            CLKOUT4_PHASE => 0.0,
            CLKOUT5_PHASE => 0.0,
            CLKOUT6_PHASE => 0.0,
            CLKOUT4_CASCADE => FALSE,  -- Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
            DIVCLK_DIVIDE => REF_CLK_DIV_C, -- Master division value (1-106)
            REF_JITTER1 => 0.0,        -- Reference input jitter in UI (0.000-0.999).
            STARTUP_WAIT => FALSE      -- Delays DONE until MMCM is locked (FALSE, TRUE)
         )
         port map (
            -- Clock Outputs: 1-bit (each) output: User configurable clock outputs
            CLKOUT0 => ulpiClkLocNb,     -- 1-bit output: CLKOUT0
            CLKOUT0B => open,   -- 1-bit output: Inverted CLKOUT0
            CLKOUT1 => ulpiClkRegNb,     -- 1-bit output: CLKOUT1
            CLKOUT1B => open,   -- 1-bit output: Inverted CLKOUT1
            CLKOUT2 => clk2Nb,     -- 1-bit output: CLKOUT2
            CLKOUT2B => open,   -- 1-bit output: Inverted CLKOUT2
            CLKOUT3 => open,     -- 1-bit output: CLKOUT3
            CLKOUT3B => open,   -- 1-bit output: Inverted CLKOUT3
            CLKOUT4 => open,     -- 1-bit output: CLKOUT4
            CLKOUT5 => open,     -- 1-bit output: CLKOUT5
            CLKOUT6 => open,     -- 1-bit output: CLKOUT6
            -- Feedback Clocks: 1-bit (each) output: Clock feedback ports
            CLKFBOUT => clkFbO,   -- 1-bit output: Feedback clock
            CLKFBOUTB => open, -- 1-bit output: Inverted CLKFBOUT
            -- Status Ports: 1-bit (each) output: MMCM status ports
            LOCKED => refLocked, -- 1-bit output: LOCK
            -- Clock Inputs: 1-bit (each) input: Clock input
            CLKIN1 => refClkLoc,       -- 1-bit input: Clock
            -- Control Ports: 1-bit (each) input: MMCM control ports
            PWRDWN => '0',       -- 1-bit input: Power-down
            RST => '0',             -- 1-bit input: Reset
            -- Feedback Clocks: 1-bit (each) input: Clock feedback ports
            CLKFBIN => clkFbI      -- 1-bit input: Feedback clock
         );

      B_FB     : BUFG port map ( I => clkFbO, O => clkFbI );

      G_CLKDDR : if ( ULPI_CLK_MODE_INP_G ) generate
         U_BUF : BUFG
            port map (
               I => ulpiClkRegNb,
               O => ulpiClkRegLoc
            );

         U_DDR : ODDR
            generic map (
               DDR_CLK_EDGE => "SAME_EDGE"
            )
            port map (
               C    => ulpiClkRegLoc,
               CE   => '1',
               D1   => '1',
               D2   => '0',
               R    => '0',
               S    => '0',
               Q    => ulpiClk
            );
      end generate G_CLKDDR;

   end generate G_MMCM;

   G_NO_MMCM : if ( not ULPI_CLK_MODE_INP_G and not USE_MMCM_C ) generate
      ulpiClkLocNb    <= ulpiClk;
   end generate G_NO_MMCM;

   G_NO_CLKDDR : if ( not ULPI_CLK_MODE_INP_G ) generate
      ulpiClk         <= 'Z';
   end generate G_NO_CLKDDR;

   U_REFBUF :  BUFG port map ( I => ulpiClkLocNb,    O => ulpiClkLoc );

   usb2RstLoc <= usb2DevStatus.usb2Rst or ulpiRst;

   B_BUF : block is
      signal   ulpiDirNDly : std_logic;
      signal   ulpiNxtNDly : std_logic;
   begin

      ulpiIb.dir <= ulpiDirNDly;
      ulpiIb.nxt <= ulpiNxtNDly;

      U_DIR_IBUF : IBUF port map ( I => ulpiDir   , O => ulpiDirNDly );
      U_NXT_IBUF : IBUF port map ( I => ulpiNxt   , O => ulpiNxtNDly );

      U_STP_BUF  : IOBUF
         port map (
            IO => ulpiStp,
            I  => ulpiOb.stp,
            O  => ulpiIb.stp,
            T  => '0'
         );

      G_DAT_BUF : for i in ulpiIb.dat'range generate
         signal ulpiDatNDly : std_logic;
      begin

         ulpiIb.dat(i) <= ulpiDatNDly;

         U_BUF : IOBUF
            port map (
               IO => ulpiDat(i),
               I  => ulpiOb.dat(i),
               O  => ulpiDatNDly,
               T  => ulpiDirNDly
           );
      end generate G_DAT_BUF;

   end block B_BUF;

   U_DUT : entity work.Usb2Core
      generic map (
         MARK_DEBUG_ULPI_IO_G         => true,
         MARK_DEBUG_ULPI_LINE_STATE_G => true,
         MARK_DEBUG_PKT_RX_G          => true,
         MARK_DEBUG_PKT_TX_G          => false,
         MARK_DEBUG_PKT_PROC_G        => true,
         MARK_DEBUG_EP0_G             => false,
         ULPI_NXT_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_DIR_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_DIN_IOB_G               => not ULPI_CLK_MODE_INP_G,
         ULPI_STP_MODE_G              => NORMAL,
         DESCRIPTORS_G                => USB2_APP_DESCRIPTORS_C
      )
      port map (
         clk                          => ulpiClkLoc,

         ulpiRst                      => ulpiRst,
         usb2Rst                      => usb2RstLoc,

         ulpiIb                       => ulpiIb,
         ulpiOb                       => ulpiOb,

         ulpiRegReq                   => regReq,
         ulpiRegRep                   => regRep,

         ulpiForceStp                 => iRegs(0)(29),

         usb2DevStatus                => usb2DevStatus,

         usb2Rx                       => usb2Rx,

         usb2Ep0ReqParam              => usb2Ep0ReqParam,
         usb2Ep0CtlExt                => usb2Ep0CtlExt,
         usb2Ep0CtlEpExt              => usb2Ep0CtlEpExt,

         usb2HiSpeedEn                => '1',
         usb2RemoteWake               => iRegs(0)(31),

         usb2EpIb                     => usb2EpIb,
         usb2EpOb                     => usb2EpOb
      );

   P_RG : process ( fInp, fOut ) is
   begin
      oRegs <= (others => (others => '0'));
      oRegs(0)(fInp'range) <= std_logic_vector(fInp);
      oRegs(1)(fOut'range) <= std_logic_vector(fOut);
   end process P_RG;


   ulpiClkOut <= ulpiClkLoc;
   usb2Rst    <= usb2RstLoc;

end architecture Impl;
