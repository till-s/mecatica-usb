-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Isochronous INP stream into a FIFO.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

entity Usb2EpAudioInpStrm is
   generic (
      -- Interface number of control interface
      AC_IFC_NUM_G        : Usb2InterfaceNumType;
      -- volume range and resolution
      VOL_RNG_MIN_G       : integer range -32767 to 32767 := -32767; -- -128 + 1/156 db
      VOL_RNG_MAX_G       : integer range -32767 to 32767 := +32767; -- +128 - 1/156 db
      VOL_RNG_RES_G       : integer range      1 to 32767 := 256;    --    1         db
      SEL_RNG_MAX_G       : integer range      0 to 255   :=   0;
      -- audio sample size in byte (per channel)
      SAMPLE_SIZE_G       : natural range 1 to 4 := 3;
      -- stereo/mono
      NUM_CHANNELS_G      : natural range 1 to 2 := 2;
      AUDIO_FREQ_G        : natural              := 48000;
      -- FIFO clock domain is asynchronous to usb2Clk
      ASYNC_G             : boolean              := false;
      LD_FIFO_DEPTH_INP_G : natural              := 8;
      -- Debugging
      MARK_DEBUG_G        : boolean              := false
   );
   port (
      -- usb2 CLK Domain
      usb2Clk             : in  std_logic;
      usb2Rst             : in  std_logic;
      -- reset is busy while the (slow) BCLK side of the
      -- fifo is resetting.
      usb2RstBsy          : out std_logic;

      -- EP0 control (handle BADD Device Requests via EP0)
      usb2Ep0ReqParam     : in  Usb2CtlReqParamType;
      usb2Ep0CtlExt       : out Usb2CtlExtType;
      usb2Ep0ObExt        : out Usb2EndpPairIbType;
      usb2Ep0IbExt        : in  Usb2EndpPairObType;

      -- USB Core interface
      usb2Rx              : in  Usb2RxType;
      usb2EpIb            : in  Usb2EndpPairObType;
      usb2EpOb            : out Usb2EndpPairIbType;
      usb2DevStatus       : in  Usb2DevStatusType;

      -- Volume control
      volMaster           : out signed(15 downto 0);
      volLeft             : out signed(15 downto 0);
      volRight            : out signed(15 downto 0);
      muteMaster          : out std_logic;
      muteLeft            : out std_logic;
      muteRight           : out std_logic;
      powerState          : out unsigned(1 downto 0);
      selectorSel         : out unsigned(7 downto 0);

      -- Endpoint clock must be >= audio clock * SAMPLE_SIZE_G * NUM_CHANNELS_G but synchronous
      -- to the audio clock.
      epClk               : in  std_logic := '0';
      -- endpoint reset from USB
      epRstOut            : out std_logic := '0';

      -- one slot (little-endian, lowest channel index -> lowest vector idx)
      epData              : in  std_logic_vector(Usb2ByteType'length * NUM_CHANNELS_G * SAMPLE_SIZE_G - 1 downto 0) := (others => '0');
      -- handshake
      epDataVld           : in  std_logic := '0'
   );
end entity Usb2EpAudioInpStrm;

architecture Impl of Usb2EpAudioInpStrm is
   signal fifoDatOut     : std_logic_vector(epData'range);
   signal fifoWen        : std_logic       := '0';
   signal fifoRen        : std_logic       := '0';
   signal fifoFull       : std_logic       := '0';
   signal fifoEmpty      : std_logic       := '0';
   signal epRstLoc       : std_logic;

   signal haltedInp      : std_logic       := '1';
   signal haltedInpEpClk : std_logic       := '1';

   signal mstInpVld      : std_logic       := '0';
   signal mstInpDat      : std_logic_vector(7 downto 0) := (others => '0');

   type   RegType        is record
      delay              : std_logic_vector(NUM_CHANNELS_G*SAMPLE_SIZE_G - 1 downto 0);
      shiftReg           : std_logic_vector(epData'range);
   end record RegType;

   constant REG_INIT_C   : RegType := (
      delay              => (others => '0'),
      shiftReg           => (others => '0')
   );

   signal r              : RegType := REG_INIT_C;
   signal rin            : RegType;

begin

   G_NO_SHIFTER : if ( epData'length <= Usb2ByteType'length ) generate
      mstInpDat <= std_logic_vector(resize( unsigned(epData), mstInpDat'length ));
      mstInpVld <= epDataVld;
   end generate G_NO_SHIFTER;

   G_SHIFTER : if ( epData'length > Usb2ByteType'length ) generate

      -- See Frmts20:
      -- Audio frames must not be fragmented across VFP (virtual frame packets
      -- which are packets except for high-speed, high-bandwidth transactions
      -- with multiple transactions per microframe).
      -- Thus, we ship frames through the Usb2Fifo (see below) and make
      -- sure we have an entire frame before handing to the packet engine.

      P_COMB : process ( r, usb2EpIb, fifoEmpty, fifoDatOut, mstInpVld ) is
         variable v : RegType;
      begin
         v := r;

         fifoRen <= '0';

         if ( ( mstInpVld and usb2EpIb.subInp.rdy ) = '1' ) then
            -- shift the delay line and data
            v.delay    := std_logic_vector(shift_right(unsigned(r.delay   ), 1));
            v.shiftReg := std_logic_vector(shift_right(unsigned(r.shiftReg), 8));
            -- if shiftReg is about to become empty try to load the next word
            -- from the fifo
            if ( (r.delay(1) = '0') and (fifoEmpty = '0') ) then
               fifoRen    <= '1';
               v.shiftReg := fifoDatOut;
               v.delay    := (others => '1');
            end if;
         end if;

         if ( (mstInpVld = '0') and (fifoEmpty = '0') ) then
            fifoRen    <= '1';
            v.shiftReg := fifoDatOut;
            v.delay    := (others => '1');
         end if;

         rin <= v;
      end process P_COMB;

      P_SEQ : process ( usb2Clk ) is
      begin
         if ( rising_edge( usb2Clk ) ) then
            if ( usb2Rst = '1' ) then
               r <= REG_INIT_C;
	    else
               r <= rin;
            end if;
         end if;
      end process P_SEQ;

      mstInpVld <= r.delay(r.delay'right);
      mstInpDat <= r.shiftReg(mstInpDat'range);

   end generate G_SHIFTER;

   U_BADD_CTL : entity work.Usb2EpAudioCtl
      generic map (
         VOL_RNG_MIN_G       => VOL_RNG_MIN_G,
         VOL_RNG_MAX_G       => VOL_RNG_MAX_G,
         VOL_RNG_RES_G       => VOL_RNG_RES_G,
         SEL_RNG_MAX_G       => SEL_RNG_MAX_G,
         AC_IFC_NUM_G        => AC_IFC_NUM_G,
	 AUDIO_FREQ_G        => AUDIO_FREQ_G
      )
      port map (
         clk                 => usb2Clk,
         rst                 => usb2Rst,

         usb2Ep0ReqParam     => usb2Ep0ReqParam,
         usb2Ep0CtlExt       => usb2Ep0CtlExt,
         usb2Ep0ObExt        => usb2Ep0ObExt,
         usb2Ep0IbExt        => usb2Ep0IbExt,
         volMaster           => volMaster,
         volLeft             => volLeft,
         volRight            => volRight,
         muteMaster          => muteMaster,
         muteLeft            => muteLeft,
         muteRight           => muteRight,
         powerState          => powerState,
         selectorSel         => selectorSel
      );

   U_FIFO : entity work.Usb2Fifo
      generic map (
         DATA_WIDTH_G                 => epData'length,
         LD_DEPTH_G                   => LD_FIFO_DEPTH_INP_G,
         ASYNC_G                      => ASYNC_G,
         LD_TIMER_G                   => 1
      )
      port map (
         wrClk                        => epCLk,
         -- reset received from USB or endpoint not active in current alt-setting
         wrRstOut                     => epRstLoc,

         din                          => epData,
         wen                          => fifoWen,

         full                         => fifoFull,

         rdClk                        => usb2Clk,
         rdRst                        => usb2Rst,

         dou                          => fifoDatOut,
         ren                          => fifoRen,
         empty                        => fifoEmpty
      );

   epRstOut   <= epRstLoc;

   haltedInp  <= usb2EpIb.haltedInp;
   fifoWen    <= epDataVld and not haltedInpEpClk and not fifoFull;

   G_SYNC : if ( not ASYNC_G ) generate
   begin
      haltedInpEpClk <= haltedInp;
   end generate G_SYNC;

   G_ASYNC : if ( ASYNC_G ) generate 
   begin
      U_SYNC_HALT_INP : entity work.Usb2CCSync 
         port map (             
            clk => epClk,       
            d   => haltedInp,   
            q   => haltedInpEpClk 
         );
   end generate G_ASYNC;


   P_ASSGN : process ( mstInpVld, haltedInp, mstInpDat ) is
   begin
      usb2EpOb            <= USB2_ENDP_PAIR_IB_INIT_C;
      usb2EpOb.mstInp.vld <= mstInpVld;
      usb2EpOb.stalledInp <= haltedInp;
      usb2EpOb.bFramedInp <= '1';
      usb2EpOb.mstInp.err <= '0';
      usb2EpOb.mstInp.don <= '0';
      usb2EpOb.mstInp.dat <= mstInpDat;
   end process P_ASSGN;
   
end architecture Impl;
