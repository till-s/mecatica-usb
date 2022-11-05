library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;
use     work.Usb2AppCfgPkg.all;

package Usb2DescPkg is

   subtype  Usb2DescIdxType    is natural range 0 to USB2_APP_CFG_DESCRIPTORS_C'length - 1;
   type Usb2DescIdxArray is array(natural range <>) of Usb2DescIdxType;

   function USB2_APP_NUM_CONFIGURATIONS_F(constant d: Usb2ByteArray) return positive;
   constant USB2_APP_NUM_CONFIGURATIONS_C :  positive := USB2_APP_NUM_CONFIGURATIONS_F(USB2_APP_CFG_DESCRIPTORS_C);

   function USB2_APP_NUM_ENDPOINTS_F(constant d: Usb2ByteArray) return positive;

   constant USB2_APP_NUM_ENDPOINTS_C      :  positive := USB2_APP_NUM_ENDPOINTS_F(USB2_APP_CFG_DESCRIPTORS_C);
   -- max. number of interfaces among all configurations
   -- e.g., if config 1 has 1 interface and config 2 has
   -- 2 interfaces then the max would be 2.  
   function USB2_APP_MAX_INTERFACES_F(constant d: Usb2ByteArray) return natural;
   constant USB2_APP_MAX_INTERFACES_C     : natural   := USB2_APP_MAX_INTERFACES_F(USB2_APP_CFG_DESCRIPTORS_C);
   -- max. number of alt. settings of any interface of
   -- any configuration.
   -- e.g., if config 1 has 1 interface 3 alt-settings
   -- a second interface with 2 alt-settings and config 2
   -- has a single interface with 1 alt-settings then
   -- the max would be 3. Note that the number of alt-
   -- settings includes the default (0) setting.
   function USB2_APP_MAX_ALTSETTINGS_F(constant d: Usb2ByteArray) return natural;
   constant USB2_APP_MAX_ALTSETTINGS_C    : natural := USB2_APP_MAX_ALTSETTINGS_F(USB2_APP_CFG_DESCRIPTORS_C);

   function USB2_APP_CONFIG_IDX_TBL_F(constant d: Usb2ByteArray) return Usb2DescIdxArray;
   constant USB2_APP_CONFIG_IDX_TBL_C     : Usb2DescIdxArray := USB2_APP_CONFIG_IDX_TBL_F(USB2_APP_CFG_DESCRIPTORS_C);

   -- find next descriptor of a certain type starting at index s; returns -1 if none is found
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer;
      constant t: Usb2StdDescriptorTypeType
   ) return integer;

   -- skip to the next descriptor
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer
   ) return integer;

   constant USB2_DESC_IDX_LENGTH_C                        : natural := 0;
   constant USB2_DESC_IDX_TYPE_C                          : natural := 1;
   constant USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C             : natural := 7;
   constant USB2_DEV_DESC_IDX_NUM_CONFIGURATIONS_C        : natural := 17;

   constant USB2_CFG_DESC_IDX_NUM_INTERFACES_C            : natural := 4;
   constant USB2_CFG_DESC_IDX_CFG_VALUE_C                 : natural := 5;
   constant USB2_CFG_DESC_IDX_ATTRIBUTES_C                : natural := 7;

   constant USB2_IFC_DESC_IDX_IFC_NUM_C                   : natural := 2;
   constant USB2_IFC_DESC_IDX_ALTSETTING_C                : natural := 3;
   constant USB2_IFC_DESC_IDX_NUM_ENDPOINTS_C             : natural := 4;

   constant USB2_EPT_DESC_IDX_ADDRESS_C                   : natural := 2;
   constant USB2_EPT_DESC_IDX_ATTRIBUTES_C                : natural := 3;
   constant USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C              : natural := 4;

end package Usb2DescPkg;

package body Usb2DescPkg is

   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer
   ) return integer is
      variable i : integer := s;
   begin
      i := i + to_integer( unsigned( d(i + USB2_DESC_IDX_LENGTH_C) ) );
      if ( i >= d'length ) then
         return -1;
      end if;
      return i;
   end function usb2NextDescriptor;

   -- find next descriptor of a certain type starting at index s; returns -1 if none is found
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer;
      constant t: Usb2StdDescriptorTypeType
   ) return integer is
      variable i : integer := s;
   begin
      while ( i >= 0 and Usb2StdDescriptorTypeType(d(i + USB2_DESC_IDX_TYPE_C)(3 downto 0)) /= t ) loop
         i := usb2NextDescriptor(d, i);
      end loop;
      return i;
   end function usb2NextDescriptor;

   function findMax(
      constant d : Usb2ByteArray;
      constant t : Usb2StdDescriptorTypeType;
      constant o : natural;
      constant b : natural
   ) return natural is
      variable highest   : integer := -1;
      variable i         : integer := 0;
      variable thisone   : natural;
   begin
      i := usb2NextDescriptor(d, i, t);
      while ( i >= 0 ) loop
         thisone := to_integer( unsigned( d(i + o)(b downto 0) ) );
         if ( thisone > highest ) then
            highest := thisone;
         end if;
         -- skip the one we just examined
         i := usb2NextDescriptor(d, i);
         -- and look for the next match
         i := usb2NextDescriptor(d, i, t);
      end loop;
      return highest + 1;
   end function findMax;

   function USB2_APP_NUM_ENDPOINTS_F(constant d: Usb2ByteArray)
   return positive is
      variable v : integer;
   begin
      v := findMax(d, USB2_STD_DESC_TYPE_ENDPOINT_C, USB2_EPT_DESC_IDX_ADDRESS_C, 3);
      if ( v < 0 ) then
         v := 1; -- EP 0 has no descriptor
      end if;
      report integer'image(v) & " endpoints";
      return v;
   end function USB2_APP_NUM_ENDPOINTS_F;

   function USB2_APP_MAX_INTERFACES_F(constant d: Usb2ByteArray)
   return natural is
      variable v : positive;
   begin
      v := findMax(d, USB2_STD_DESC_TYPE_INTERFACE_C, USB2_IFC_DESC_IDX_IFC_NUM_C, 6);
      report integer'image(v) & " max IFs";
      return v;
   end function USB2_APP_MAX_INTERFACES_F;

   function USB2_APP_MAX_ALTSETTINGS_F(constant d: Usb2ByteArray)
   return natural is
      variable v : positive;
   begin
      v := findMax(d, USB2_STD_DESC_TYPE_INTERFACE_C, USB2_IFC_DESC_IDX_ALTSETTING_C, 6);
      report integer'image(v) & " max ALTs";
      return v;
   end function USB2_APP_MAX_ALTSETTINGS_F;

   function USB2_APP_NUM_CONFIGURATIONS_F(constant d: Usb2ByteArray)
   return positive is
      variable i  : integer := 0;
      variable nc : natural := 0;
   begin
      while ( i >= 0 ) loop
         i  := usb2NextDescriptor(d, i, USB2_STD_DESC_TYPE_CONFIGURATION_C);
         if ( i >= 0 ) then
            nc := nc + 1;
            i  := usb2NextDescriptor(d, i);
         end if;
      end loop;
      assert nc > 0 report "No configurations?" severity failure;
      return nc;
   end function USB2_APP_NUM_CONFIGURATIONS_F;

   function USB2_APP_CONFIG_IDX_TBL_F(constant d: Usb2ByteArray)
   return Usb2DescIdxArray is
      constant NC : positive := USB2_APP_NUM_CONFIGURATIONS_F(d);
      variable rv : Usb2DescIdxArray(0 to NC);
   begin
      rv(0) := 0; -- dummy
      for i in 1 to NC loop
         rv(i) := usb2NextDescriptor(d, rv(i-1), USB2_STD_DESC_TYPE_CONFIGURATION_C);
         report "Config addr " & integer'image(rv(i));
      end loop;
      return rv;
   end function USB2_APP_CONFIG_IDX_TBL_F;

end package body Usb2DescPkg;

