library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;
use     work.Usb2AppCfgPkg.all;

-- simple program to test function in Usb2DescPkg -- needs
-- an AppCfgPkgBody!

entity Usb2DescPkgTb is end entity Usb2DescPkgTb;

architecture sim of Usb2DescPkgTb is

   constant HAVE_UAC3_SPKR_C                        : integer :=
      usb2NextIfcAssocDescriptor(
         USB2_APP_DESCRIPTORS_C,
         0,
         USB2_IFC_CLASS_AUDIO_C,
         USB2_FCN_SUBCLASS_AUDIO_SPEAKER_C,
         USB2_IFC_SUBCLASS_AUDIO_PROTOCOL_UAC3_C
      );

   constant HAVE_UAC2_SPKR_C                        : integer :=
      usb2NextUAC2IfcAssocDescriptor(
         USB2_APP_DESCRIPTORS_C,
         0,
         USB2_CS_IFC_HDR_UAC2_CATEGORY_SPEAKER
      );

   constant HAVE_UAC2_MICR_C                        : integer :=
      usb2NextUAC2IfcAssocDescriptor(
         USB2_APP_DESCRIPTORS_C,
         0,
         USB2_CS_IFC_HDR_UAC2_CATEGORY_MICROPHONE
      );

begin
   process is
      variable i : integer := -1;
   begin
      report "UAC3 SPKR " & boolean'image(HAVE_UAC3_SPKR_C >= 0);
      -- cannot use UAC2 functions for UAC2
      report "UAC2 SPKR " & boolean'image(HAVE_UAC2_SPKR_C >= 0);
      if ( HAVE_UAC2_SPKR_C >= 0 ) then
         i := HAVE_UAC2_SPKR_C;
      end if;
      report "UAC2 MICR " & boolean'image(HAVE_UAC2_MICR_C >= 0);
      if ( HAVE_UAC2_MICR_C >= 0 ) then
         i := HAVE_UAC2_MICR_C;
      end if;
      if ( i >= 0 ) then
         report "SubSlot Size " & integer'image( usb2GetUAC2SubSlotSize( USB2_APP_DESCRIPTORS_C, i ) );
         report "# Channels   " & integer'image( usb2GetUAC2NumChannels( USB2_APP_DESCRIPTORS_C, i ) );
         report "Selector pins " & integer'image( usb2GetUAC2SelectorUnitPins( USB2_APP_DESCRIPTORS_C, i ) );
      end if;
      wait;
   end process;
end architecture sim;
