-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2AppCfgPkg.all;

-- Utilities to handle descriptors

package Usb2DescPkg is

   subtype  Usb2DescIdxType    is natural range 0 to USB2_APP_DESCRIPTORS_C'length - 1;
   type Usb2DescIdxArray is array(natural range <>) of Usb2DescIdxType;

   constant USB2_DEV_CLASS_NONE_C                         : Usb2ByteType := x"00";
   constant USB2_DEV_CLASS_CDC_C                          : Usb2ByteType := x"02";

   constant USB2_IFC_CLASS_CDC_C                          : Usb2ByteType := x"02";
   constant USB2_IFC_CLASS_DAT_C                          : Usb2ByteType := x"0A";

   constant USB2_CDC_SUBCLASS_NONE_C                      : Usb2ByteType := x"00";
   constant USB2_CDC_SUBCLASS_ACM_C                       : Usb2ByteType := x"02";
   constant USB2_CDC_SUBCLASS_ECM_C                       : Usb2ByteType := x"06";
   constant USB2_CDC_SUBCLASS_NCM_C                       : Usb2ByteType := x"0D";

   constant USB2_DAT_SUB_CLASS_NONE_C                     : Usb2ByteType := x"00";

   constant USB2_CDC_PROTO_NONE_C                         : Usb2ByteType := x"00";
   constant USB2_DAT_PROTO_NONE_C                         : Usb2ByteType := x"00";

   constant USB2_DESC_IDX_LENGTH_C                        : natural := 0;
   constant USB2_DESC_IDX_TYPE_C                          : natural := 1;
   constant USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C             : natural := 7;
   constant USB2_DEV_DESC_IDX_NUM_CONFIGURATIONS_C        : natural := 17;

   constant USB2_CFG_DESC_IDX_TOTAL_LENGTH_C              : natural := 2;
   constant USB2_CFG_DESC_IDX_NUM_INTERFACES_C            : natural := 4;
   constant USB2_CFG_DESC_IDX_CFG_VALUE_C                 : natural := 5;
   constant USB2_CFG_DESC_IDX_ATTRIBUTES_C                : natural := 7;

   constant USB2_IFC_DESC_IDX_IFC_NUM_C                   : natural := 2;
   constant USB2_IFC_DESC_IDX_ALTSETTING_C                : natural := 3;
   constant USB2_IFC_DESC_IDX_NUM_ENDPOINTS_C             : natural := 4;

   constant USB2_EPT_DESC_IDX_ADDRESS_C                   : natural := 2;
   constant USB2_EPT_DESC_IDX_ATTRIBUTES_C                : natural := 3;
   constant USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C              : natural := 4;

   constant USB2_CS_DESC_IDX_SUBTYPE_C                    : natural := 2;

--   function USB2_APP_NUM_CONFIGURATIONS_F(constant d: Usb2ByteArray) return integer;

   function USB2_APP_MAX_ENDPOINTS_F(constant d: Usb2ByteArray) return positive;

   -- max. number of interfaces among all configurations
   -- e.g., if config 1 has 1 interface and config 2 has
   -- 2 interfaces then the max would be 2.  
   function USB2_APP_MAX_INTERFACES_F(constant d: Usb2ByteArray) return natural;
   -- max. number of alt. settings of any interface of
   -- any configuration.
   -- e.g., if config 1 has 1 interface 3 alt-settings
   -- a second interface with 2 alt-settings and config 2
   -- has a single interface with 1 alt-settings then
   -- the max would be 3. Note that the number of alt-
   -- settings includes the default (0) setting.
   function USB2_APP_MAX_ALTSETTINGS_F(constant d: Usb2ByteArray) return natural;

   -- A high-speed device is expected to follow the layout:
   --      FS-device descriptor
   --      FS-device qualifier
   --      FS-config
   --      FS-interfaces
   --      ...
   --      SENTINEL
   --      HS-device descriptor
   --      FS-device qualifier
   --      FS-config
   --      FS-interfaces
   --      string-descriptors
   --      SENTINEL
   --
   -- A full-speed only device follows the layout
   --      FS-device descriptor
   --      FS-config
   --      FS-interfaces
   --      string-descriptors
   --      SENTINEL
   -- it has a zero-length HS_CONFIG_IDX_TBL
   function USB2_APP_CONFIG_IDX_TBL_F(constant d: Usb2ByteArray; constant hs : boolean := false) return Usb2DescIdxArray;

   function USB2_APP_NUM_STRINGS_F(constant d: Usb2ByteArray) return natural;

   function USB2_APP_STRINGS_IDX_F(constant d: Usb2ByteArray) return Usb2DescIdxType;

   -- find next descriptor of a certain type starting at index s; returns -1 if none is found
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer;
      constant t: Usb2ByteType;
      constant a: boolean := false -- terminate at sentinel?
   ) return integer;

   -- find next descriptor of a certain class-specific subtype starting at index s; returns -1 if none found
   function usb2NextCsDescriptor(
      constant  d: Usb2ByteArray;
      constant  s: integer;
      constant st: Usb2ByteType;
      constant  e: boolean := false; -- class specific endpoint desciptor (not interface)
      constant  a: boolean := false  -- terminate at sentinel?
   ) return integer;

   -- skip to the next descriptor
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer;
      constant a: boolean := false -- terminate at sentinel?
   ) return integer;

   function usb2CountDescriptors(
      constant d : Usb2ByteArray;
      constant t : Usb2ByteType;
      constant a : boolean := false -- terminate at sentinel?
   ) return natural;


   -- Return the index of the 'n'th string
   -- descriptor (-1 if not found).
   --
   -- It is OK to pass -1 (NOP, returns -1)
   -- 
   -- n = 0 finds the languages
   function usb2NthStringDescriptor(
      constant d : Usb2ByteArray;
      constant n : integer
   ) return integer;

   -- Find the string descriptor index pointing to the MAC address
   -- of the first interface of desired subclass.
   -- Returns -1 if not found
   function usb2EthMacAddrStringDescriptor(
      constant d : Usb2ByteArray;
      -- must be one of USB2_CDC_SUBCLASS_ECM_C, USB2_CDC_SUBCLASS_NCM_C
      constant s : Usb2ByteType := USB2_CDC_SUBCLASS_NCM_C
   ) return integer;

end package Usb2DescPkg;

package body Usb2DescPkg is

   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer;
      constant a: boolean := false
   ) return integer is
      variable i : integer := s;
   begin
      if ( i < 0 ) then
         return i;
      end if;
      i := i + to_integer( unsigned( d(i + USB2_DESC_IDX_LENGTH_C) ) );
      if ( i >= d'high ) then
         return -1;
      end if;
      if ( a and usb2DescIsSentinel( d(i + USB2_DESC_IDX_TYPE_C) ) ) then
         return -1;
      end if;
      return i;
   end function usb2NextDescriptor;

   function toStr(constant x : std_logic_vector) return string is
      variable s : string(1 to x'length);
   begin
      for i in x'left downto x'right loop
         s(x'left - i + 1) := std_logic'image(x(i))(2);
      end loop;
      return s;
   end function toStr;

   -- find next descriptor of a certain type starting at index s; returns -1 if none is found
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant s: integer;
      constant t: Usb2ByteType;
      constant a: boolean := false
   ) return integer is
      variable i : integer := s;
   begin
report "i: " & integer'image(i) & " t " & toStr(std_logic_vector(t)) & " tbl " & toStr(d(i+USB2_DESC_IDX_TYPE_C));
      while ( i >= 0 and d(i + USB2_DESC_IDX_TYPE_C) /= Usb2ByteType(t) ) loop
         i := usb2NextDescriptor(d, i, a);
      end loop;
      return i;
   end function usb2NextDescriptor;

   -- find next descriptor of a certain class-specific subtype starting at index s; returns -1 if none found
   function usb2NextCsDescriptor(
      constant  d: Usb2ByteArray;
      constant  s: integer;
      constant st: Usb2ByteType;
      constant  e: boolean := false; -- class specific endpoint desciptor (not interface)
      constant  a: boolean := false  -- terminate at sentinel?
   ) return integer is
      constant dt : Usb2ByteType := ite(e, USB2_CS_DESC_TYPE_ENDPOINT_C, USB2_CS_DESC_TYPE_INTERFACE_C);
      variable  i : integer;
   begin
      i := usb2NextDescriptor(d, s, dt, a);
      while ( i >= 0 and d(i + USB2_CS_DESC_IDX_SUBTYPE_C) /= st ) loop
         i := usb2NextDescriptor(d, i, a );
         if ( i >= 0 ) then
            i := usb2NextDescriptor(d, i, dt, a);
         end if;
      end loop;
      return i;
   end function usb2NextCsDescriptor;

   function findMax(
      constant d : Usb2ByteArray;
      constant t : Usb2ByteType;
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

   function USB2_APP_MAX_ENDPOINTS_F(constant d: Usb2ByteArray)
   return positive is
      variable v : integer;
   begin
      v := findMax(d, USB2_DESC_TYPE_ENDPOINT_C, USB2_EPT_DESC_IDX_ADDRESS_C, 3);
      if ( v <= 0 ) then
         v := 1; -- EP 0 has no descriptor
      end if;
      report integer'image(v) & " endpoints";
      return v;
   end function USB2_APP_MAX_ENDPOINTS_F;

   function USB2_APP_MAX_INTERFACES_F(constant d: Usb2ByteArray)
   return natural is
      variable v : natural;
   begin
      v := findMax(d, USB2_DESC_TYPE_INTERFACE_C, USB2_IFC_DESC_IDX_IFC_NUM_C, 6);
      report integer'image(v) & " max IFs";
      return v;
   end function USB2_APP_MAX_INTERFACES_F;

   function USB2_APP_MAX_ALTSETTINGS_F(constant d: Usb2ByteArray)
   return natural is
      variable v : natural;
   begin
      v := findMax(d, USB2_DESC_TYPE_INTERFACE_C, USB2_IFC_DESC_IDX_ALTSETTING_C, 6);
      report integer'image(v) & " max ALTs";
      return v;
   end function USB2_APP_MAX_ALTSETTINGS_F;

   function usb2CountDescriptors(
      constant d : Usb2ByteArray;
      constant t : Usb2ByteType;
      constant a : boolean := false
   ) return natural is
      variable i  : integer := d'low;
      variable n  : natural := 0;
   begin
      while ( i >= 0 ) loop
         i  := usb2NextDescriptor(d, i, t, a);
         if ( i >= 0 ) then
            n := n + 1;
            i := usb2NextDescriptor(d, i, a);
         end if;
      end loop;
      return n;
   end function usb2CountDescriptors;
  
   function USB2_APP_NUM_CONFIGURATIONS_F(constant d: Usb2ByteArray; constant i: integer)
   return integer is
      variable nc : natural;
   begin
      if ( i < 0 ) then
         return -1;
      end if;
      nc := usb2CountDescriptors(d(i to d'high), USB2_DESC_TYPE_CONFIGURATION_C, true);
      assert nc > 0 report "No configurations?" severity failure;
      return nc;
   end function USB2_APP_NUM_CONFIGURATIONS_F;

   function deviceDescriptorIndex(constant d: Usb2ByteArray; constant hs : boolean)
   return integer is
      variable i : integer;
   begin
      i := usb2NextDescriptor(d, 0, USB2_DESC_TYPE_DEVICE_C);
      if ( hs ) then
         i := usb2NextDescriptor(d, usb2NextDescriptor( d, i ), USB2_DESC_TYPE_DEVICE_C);
      end if;
      return i;
   end function deviceDescriptorIndex;

   function USB2_APP_CONFIG_IDX_TBL_F(constant d: Usb2ByteArray; constant hs : boolean := false)
   return Usb2DescIdxArray is
      constant di  : integer  := deviceDescriptorIndex(d, hs);
      constant NC  : integer  := USB2_APP_NUM_CONFIGURATIONS_F(d, di);
      variable rv  : Usb2DescIdxArray(0 to NC);
      variable frm : natural;
   begin
      if ( NC < 0 ) then
         return rv;
      end if;
      rv(0) := usb2NextDescriptor(d, di, USB2_DESC_TYPE_DEVICE_C);
      frm   := rv(0);
      for i in 1 to NC loop
         rv(i) := usb2NextDescriptor(d, frm, USB2_DESC_TYPE_CONFIGURATION_C);
         frm   := usb2NextDescriptor(d, rv(i));
      end loop;
      return rv;
   end function USB2_APP_CONFIG_IDX_TBL_F;

   function USB2_APP_NUM_STRINGS_F(constant d: Usb2ByteArray)
   return natural is
   begin
      return usb2CountDescriptors(d, USB2_DESC_TYPE_STRING_C);
   end function USB2_APP_NUM_STRINGS_F;

   function USB2_APP_STRINGS_IDX_F(constant d: Usb2ByteArray)
   return Usb2DescIdxType is
      variable i : integer;
   begin
      i := usb2NextDescriptor(d, 0, USB2_DESC_TYPE_STRING_C);
      -- avoid out-of range result; user must check USB2_APP_NUM_STRINGS_C
      if ( i < 0 ) then
         i := 0;
      end if;
      return i;
   end function USB2_APP_STRINGS_IDX_F;

   function usb2NthStringDescriptor(
      constant d : Usb2ByteArray;
      constant n : integer
   ) return integer is
      variable i : integer;
      variable k : integer;
   begin
      k := n;
      if ( k < 0 ) then
         return -1;
      end if;
      i := usb2NextDescriptor(d, 0, USB2_DESC_TYPE_STRING_C);
      while ( k > 0 ) loop
         i := usb2NextDescriptor( d, i, a => true );
         assert i >= 0 report "Skipping string descriptor failed" severity warning;
         if ( i < 0 ) then
            return -1;
         end if;
         i := usb2NextDescriptor( d, i, USB2_DESC_TYPE_STRING_C, a => true );
         assert i >= 0 report "Locating next string descriptor failed" severity warning;
         if ( i < 0 ) then
            return -1;
         end if;
         k := k - 1;
      end loop;
      return i;
   end function usb2NthStringDescriptor;

   function usb2EthMacAddrStringDescriptor(
      constant d : Usb2ByteArray;
      -- must be one of USB2_CDC_SUBCLASS_ECM_C, USB2_CDC_SUBCLASS_NCM_C
      constant s : Usb2ByteType := USB2_CDC_SUBCLASS_NCM_C
   ) return integer is
      variable i                    : integer;
      variable si                   : integer;
      constant IDX_MAC_ADDR_SIDX_C  : natural      := 3;
      constant IDX_CLS_C            : natural      := 5;
      constant IDX_SUBCLS_C         : natural      := 6;
   begin

      i := 0;
      L_IFC : while true loop

         i := usb2NextDescriptor(d, i, USB2_DESC_TYPE_INTERFACE_C, a => true);
         if ( i < 0 ) then
            return -1;
         end if;

         if (     ( d( i + IDX_CLS_C    ) = USB2_IFC_CLASS_CDC_C )
              and ( d( i + IDX_SUBCLS_C ) = s                    ) ) then
            exit L_IFC;
         end if;

         i := usb2NextDescriptor( d, i, a => true );
         if ( i < 0 ) then
            return -1;
         end if;

      end loop;

      -- ECM and NCM both use this subtype of descriptor for the mac addres
      i  := usb2NextCsDescriptor( d, i, USB2_CS_DESC_SUBTYPE_CDC_ECM_C, a => true );
      assert i > 0 report " Ethernet functional descriptor not found" severity warning;
      if ( i < 0 ) then
         return -1;
      end if;

      si := to_integer( unsigned( d( i + IDX_MAC_ADDR_SIDX_C ) ) );
      assert si > 0 report "CDCECM invalid iMACAddr string index" severity warning;

      return usb2NthStringDescriptor( d, si );

   end function usb2EthMacAddrStringDescriptor;

end package body Usb2DescPkg;
