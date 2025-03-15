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

      -- Speaker control
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
      epDataVld           : in  std_logic := '0';
      epDataRdy           : out std_logic := '1'
   );
end entity Usb2EpAudioInpStrm;

architecture Impl of Usb2EpAudioInpStrm is
   signal fifoDat        : Usb2ByteType    := (others => '0');
   signal fifoWen        : std_logic       := '0';
   signal fifoFull       : std_logic       := '0';
   signal epRstLoc       : std_logic;

   type   RegType        is record
      delay              : std_logic_vector(NUM_CHANNELS_G*SAMPLE_SIZE_G - 1 downto 0);
      shiftReg           : std_logic_vector(epData'range);
      rdy                : std_logic;
      wen                : std_logic;
   end record RegType;

   constant REG_INIT_C   : RegType := (
      delay              => (others => '0'),
      shiftReg           => (others => '0'),
      rdy                => '1',
      wen                => '0'
   );

   signal r              : RegType := REG_INIT_C;
   signal rin            : RegType;

begin

   G_NO_SHIFTER : if ( epData'length <= Usb2ByteType'length ) generate
      fifoDat   <= std_logic_vector(resize( unsigned(epData), fifoDat'length ));
      epDataRdy <= not fifoFull;
      fifoWen   <= epDataVld;
   end generate G_NO_SHIFTER;

   G_SHIFTER : if ( epData'length > Usb2ByteType'length ) generate

      P_COMB : process ( r, epData, epDataVld ) is
         variable v : RegType;
      begin
         v := r;

         -- shift the delay line and data
         v.delay    := std_logic_vector(shift_right(unsigned(r.delay   ), 1));
         v.shiftReg := std_logic_vector(shift_right(unsigned(r.shiftReg), 8));

         -- if the last byte is being written we become ready
         if ( r.delay(1) = '1' ) then
            v.rdy := '1';
         end if;
         if ( r.delay(0) = '1' ) then
            v.wen := '0';
         end if;

         -- consume the next sample set if possible
         if ( (epDataVld and r.rdy) = '1' ) then
            v.delay(v.delay'left) := '1';
            v.rdy                 := '0';
            v.wen                 := '1';
            v.shiftReg            := epData;
         end if;

         rin <= v;
      end process P_COMB;

      P_SEQ : process ( epClk ) is
      begin
         if ( rising_edge( epClk ) ) then
            if ( epRstLoc = '1' ) then
               r <= REG_INIT_C;
	    else
               r <= rin;
            end if;
         end if;
      end process P_SEQ;

      fifoDat   <= r.shiftReg(fifoDat'range);
      fifoWen   <= r.wen;
      epDataRdy <= r.rdy;
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

   U_FIFO : entity work.Usb2FifoEp
      generic map (
         LD_FIFO_DEPTH_INP_G          => LD_FIFO_DEPTH_INP_G,
         LD_FIFO_DEPTH_OUT_G          => 0,
         ASYNC_G                      => ASYNC_G
      )
      port map (
         usb2Clk                      => usb2Clk,
         usb2Rst                      => usb2Rst,
         usb2RstOut                   => open,
   
         -- Endpoint Interface
         usb2EpOb                     => usb2EpOb,
         usb2EpIb                     => usb2EpIb,
   
         minFillInp                   => open,
         timeFillInp                  => open,
   
         epClk                        => epClk,
         -- reset received from USB or endpoint not active in current alt-setting
         epRstOut                     => epRstLoc,
   
         -- FIFO Interface IN (to USB); epClk domain
   
         datInp                       => fifoDat,
         -- End of frame ('don'); data shipped during the cycle when EOF is
         -- asserted are ignored (i.e., not forwarded to USB)!
         -- Note: a single cycle with 'eofInp' asserted (w/o preceding data
         -- cycles) is sent as a zero-length frame!
         -- This is only relevant if framing is enabled (LD_MAX_NUM_FRAMES_G > 0).
         donInp                       => open,
         wenInp                       => fifoWen,
         filledInp                    => open,
         fullInp                      => fifoFull,
   
         -- FIFO Interface OUT (from USB); UNUSED/DISABLED
         datOut                       => open,
         donOut                       => open,
         renOut                       => open,
         filledOut                    => open,
         framesOut                    => open,
         emptyOut                     => open
      );

   epRstOut <= epRstLoc;
   
end architecture Impl;
