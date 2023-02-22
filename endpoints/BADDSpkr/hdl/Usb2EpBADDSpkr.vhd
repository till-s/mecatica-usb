-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- BADD Sound/Speaker playback endpoint.
-- Example for an isochronous use case. Sound is played in i2s format
-- to any compatible chip. Most of these need additional setup via i2c
-- (not to be confused: i2s - sound samples, i2c slow controls).

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

entity Usb2EpBADDSpkr is
   generic (
      -- Interface number of control interface
      AC_IFC_NUM_G        : Usb2InterfaceNumType;
      -- volume range and resolution
      VOL_RNG_MIN_G       : integer range -32767 to 32767 := -32767; -- -128 + 1/156 db
      VOL_RNG_MAX_G       : integer range -32767 to 32767 := +32767; -- +128 - 1/156 db
      VOL_RNG_RES_G       : integer range      1 to 32767 := 256;    --    1         db
      -- audio sample size in byte (per channel)
      SAMPLE_SIZE_G       : natural range 1 to 4 := 3;
      -- stereo/mono
      NUM_CHANNELS_G      : natural range 1 to 2 := 2;
      -- bitclock multiplier, i.e., how many bit clocks
      -- per audio slot (must be >= SAMPLE_SIZE_G * NUM_CHANNELS_G * 8)
      BITCLK_MULT_G       : natural              := 64;
      SAMPLING_FREQ_G     : natural              := 48000;
      -- service interval (ms), for freq. measurement (1000ms per usb spec)
      SI_FREQ_G           : natural              := 1000;
      -- Debugging
      MARK_DEBUG_G        : boolean              := false;
      MARK_DEBUG_BCLK_G   : boolean              := false
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

      -- i2s BCLK domain
      i2sBCLK             : in  std_logic;
      i2sPBLRC            : in  std_logic;
      i2sPBDAT            : out std_logic
   );
end entity Usb2EpBADDSpkr;

architecture Impl of Usb2EpBADDSpkr is
begin

   U_BADD_CTL : entity work.BADDSpkrCtl
      generic map (
         VOL_RNG_MIN_G       => VOL_RNG_MIN_G,
         VOL_RNG_MAX_G       => VOL_RNG_MAX_G,
         VOL_RNG_RES_G       => VOL_RNG_RES_G,
         AC_IFC_NUM_G        => AC_IFC_NUM_G
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
         powerState          => powerState
      );

   U_I2S_PLAYBACK : entity work.I2SPlayback
      generic map (
         SAMPLE_SIZE_G       => SAMPLE_SIZE_G,
         NUM_CHANNELS_G      => NUM_CHANNELS_G,
         BITCLK_MULT_G       => BITCLK_MULT_G,
         SAMPLING_FREQ_G     => SAMPLING_FREQ_G,
         SI_FREQ_G           => SI_FREQ_G,
         MARK_DEBUG_G        => MARK_DEBUG_G,
         MARK_DEBUG_BCLK_G   => MARK_DEBUG_BCLK_G
      )
      port map (
         usb2Clk             => usb2Clk,
         usb2Rst             => usb2Rst,
         usb2RstBsy          => usb2RstBsy,
         usb2Rx              => usb2Rx,
         usb2EpIb            => usb2EpIb,
         usb2EpOb            => usb2EpOb,
         usb2DevStatus       => usb2DevStatus,

         i2sBCLK             => i2sBCLK,
         i2sPBLRC            => i2sPBLRC,
         i2sPBDAT            => i2sPBDAT
      );
   
end architecture Impl;
