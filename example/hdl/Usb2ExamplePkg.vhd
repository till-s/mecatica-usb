-- Copyright Till Straumann, 2026. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Instantiation of a multiple functions.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;

package Usb2ExamplePkg is

   type Usb2MultiAcmCfgType is record
      ldFifoDepthInp        : natural;
      ldFifoDepthOut        : natural;
      clkAsync              : boolean;
   end record Usb2MultiAcmCfgType;      

   constant USB2_MULTI_ACM_CFG_DFLT_C : Usb2MultiAcmCfgType := (
      ldFifoDepthInp        => 10,
      ldFifoDepthOut        => 10,
      clkAsync              => false
   );

   type Usb2MultiAcmCfgArray is array (natural range <>) of Usb2MultiAcmCfgType;

   type Usb2AcmFifoObType   is record
      rst                   : std_logic;
      outDat                : Usb2ByteType;
      outEmpty              : std_logic;
      outFill               : unsigned(15 downto 0);
      inpFull               : std_logic;
      inpFill               : unsigned(15 downto 0);
      -- only supported if respective capabilities are enabled
      -- in the descriptors.
      lineBreak             : std_logic;
      DTR                   : std_logic;
      RTS                   : std_logic;
      -- extra control bits
      -- ** ALWAYS in USB2 CLOCK DOMAIN **
      -- ** user's responsibility to synchronize if
      -- ** fifo clock is asynchronous (AcmCfg.clkAsync = true)
      bitRate               : unsigned(31 downto 0);
      stopBits              : unsigned( 1 downto 0);
      parity                : unsigned( 2 downto 0);
      dataBits              : unsigned( 4 downto 0);
   end record Usb2AcmFifoObType;

   type Usb2AcmFifoObArray is array (natural range <>) of Usb2AcmFifoObType;

   type Usb2AcmFifoIbType   is record
      outRen                : std_logic;
      inpDat                : Usb2ByteType;
      inpWen                : std_logic;
      -- functionality of the ACM interface; Fifo interface
      -- to this entity is only active if this input is de-asserted.
      -- Otherwise 'blast' or 'loopback' mode are active.
      loopback              : std_logic;
      -- only supported if respective capabilities are enabled
      -- in the descriptors.
      DCD                   : std_logic;
      DSR                   : std_logic;
      overRun               : std_logic;
      parityError           : std_logic;
      framingError          : std_logic;
      ringDetect            : std_logic;
      breakState            : std_logic;
   end record Usb2AcmFifoIbType;

   constant USB2_ACM_FIFO_IB_INIT_C : Usb2AcmFifoIbType := (
      outRen                => '1',
      inpDat                => (others => '0'),
      inpWen                => '0',
      loopback              => '0',
      DCD                   => '0',
      DSR                   => '0',
      overRun               => '0',
      parityError           => '0',
      framingError          => '0',
      ringDetect            => '0',
      breakState            => '0'
   );

   type Usb2AcmFifoIbArray is array (natural range <>) of Usb2AcmFifoIbType;

   -- rarely used extra signals (can be tied to defaults)
   type Usb2AcmFifoIbExtraType  is record
      inpMinFill            : unsigned(23 downto 0);
      inpTimer              : unsigned(31 downto 0);
   end record Usb2AcmFifoIbExtraType;

   constant USB2_ACM_FIFO_IB_EXTRA_INIT_C : Usb2AcmFifoIbExtraType := (
      inpMinFill            => (others => '0'),
      inpTimer              => (others => '0')
   );

   type Usb2AcmFifoIbExtraArray is array (natural range <>) of Usb2AcmFifoIbExtraType;

   -- find all ACM interface association descriptors
   function usb2GetCdcAcmIfcAssocDescriptors(
      constant d : Usb2ByteArray;
      constant i : integer := 0
   ) return Usb2DescIdxArray;

end package Usb2ExamplePkg;

package body Usb2ExamplePkg is

   function usb2GetCdcAcmIfcAssocDescriptors(
      constant d : Usb2ByteArray;
      constant i : integer := 0
   ) return Usb2DescIdxArray is
   begin
      return usb2GetIfcAssocDescriptors(
         d,
         i,
         USB2_IFC_CLASS_CDC_C,
         USB2_IFC_SUBCLASS_CDC_ACM_C,
         USB2_IFC_PROTOCOL_NONE_C
      );
   end function usb2GetCdcAcmIfcAssocDescriptors;

end package body Usb2ExamplePkg;
