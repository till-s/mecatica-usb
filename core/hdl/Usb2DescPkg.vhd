-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

-- Utilities to handle descriptors

package Usb2DescPkg is

   subtype  Usb2DescIdxType is natural;

   type Usb2DescIdxArray is array(natural range <>) of Usb2DescIdxType;

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
   constant USB2_IFC_DESC_IFC_CLASS_C                     : natural := 5;
   constant USB2_IFC_DESC_IFC_SUBCLASS_C                  : natural := 6;
   constant USB2_IFC_DESC_IFC_PROTOCOL_C                  : natural := 7;

   constant USB2_EPT_DESC_IDX_ADDRESS_C                   : natural := 2;
   constant USB2_EPT_DESC_IDX_ATTRIBUTES_C                : natural := 3;
   constant USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C              : natural := 4;

   constant USB2_CS_DESC_IDX_SUBTYPE_C                    : natural := 2;

--   function Usb2AppGetNumConfigurations(constant d: Usb2ByteArray) return integer;

   function usb2AppGetMaxEndpointAddr(constant d: Usb2ByteArray) return positive;

   -- max. number of interfaces among all configurations
   -- e.g., if config 1 has 1 interface and config 2 has
   -- 2 interfaces then the max would be 2.
   function usb2AppGetMaxInterfaces(constant d: Usb2ByteArray) return natural;
   -- max. number of alt. settings of any interface of
   -- any configuration.
   -- e.g., if config 1 has 1 interface 3 alt-settings
   -- a second interface with 2 alt-settings and config 2
   -- has a single interface with 1 alt-settings then
   -- the max would be 3. Note that the number of alt-
   -- settings includes the default (0) setting.
   function usb2AppGetMaxAltsettings(constant d: Usb2ByteArray) return natural;

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
   function usb2AppGetConfigIdxTbl(constant d: Usb2ByteArray; constant hs : boolean := false) return Usb2DescIdxArray;

   function usb2AppGetNumStrings  (constant d: Usb2ByteArray) return natural;

   -- find next descriptor of a certain type starting at index i; returns -1 if none is found
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant i: integer;
      constant t: Usb2ByteType;
      constant a: boolean := false -- terminate at sentinel?
   ) return integer;

   -- finds next interface descriptor of given class/subclass;
   -- returns -1 if none found.
   function usb2NextIfcDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant c : Usb2ByteType;
      constant s : Usb2ByteType
   ) return integer;


   -- find next descriptor of a certain class-specific subtype starting at index i; returns -1 if none found
   -- s must point at the interface or endpoint descriptor for which the
   ---class-specific subtype is searched.
   function usb2NextCsDescriptor(
      constant  d: Usb2ByteArray;
      constant  i: integer;
      constant st: Usb2ByteType;
      constant  e: boolean := false; -- class specific endpoint desciptor (not interface)
      constant  a: boolean := false  -- terminate at sentinel?
   ) return integer;

   -- skip to the next descriptor
   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant i: integer;
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

   -- find ethernet functional descriptor associated with interface of
   -- subclass 's'.

   function usb2EthNetworkingDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return integer;


   -- Find the string descriptor index pointing to the MAC address
   -- of the first interface of desired subclass.
   -- Returns -1 if not found
   function usb2EthMacAddrStringDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return integer;

   -- convert a sequence of ascii characters into binary.
   -- i.e., the character string "42ABCD" (represented
   -- by the byte array ( x"34", x"00", x"32", x"00", x"41", x"00", x"42", x"00", x"43", x"00", x"44", x"00" )
   -- (string encoded as unicode!)
   -- is converted into (x"42", x"AB", x"CD")
   -- The constant 'd' must span an even number of bytes!
   function usb2HexStrToBin(
      constant d : Usb2ByteArray
   ) return Usb2ByteArray;

   -- find ECM or NCM MAC address and convert to 'binary'
   -- Usb2ByteArray of length 6 or 0 (if address is not found).
   function usb2GetECMMacAddr(
      constant d : Usb2ByteArray;
      constant i : integer
   ) return Usb2ByteArray;

   function usb2GetNCMMacAddr(
      constant d : Usb2ByteArray;
      constant i : integer
   ) return Usb2ByteArray;

   -- fetch bmNetworkCapabilities from NCM functional descriptor
   function usb2GetNCMNetworkCapabilities(
      constant d : Usb2ByteArray;
      constant i : integer
   ) return std_logic_vector;

   function usb2GetNumMCFilters(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return integer;

   function usb2GetMCFilterPerfect(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return boolean;

   function usb2NextIfcAssocDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant c : Usb2ByteType;
      constant s : Usb2ByteType;
      constant p : Usb2ByteType := (others => 'X');
      constant a : boolean      := true
   ) return integer;

   function usb2NextCsUAC2(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant t : Usb2ByteType;
      constant s : boolean;
      constant a : boolean      := true
   ) return integer;

   function usb2NextCsUAC2HeaderCategory(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant c : Usb2ByteType;
      constant a : boolean      := true
   ) return integer;

   -- read the number of audio channels;
   -- i must point to the first ifc association desc.
   -- of the audio IFC
   function usb2GetUAC2NumChannels(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant a : boolean      := true
   ) return integer;

   -- read the audio sub-slot size (bytes);
   -- i must point to the first ifc association desc.
   -- of the audio IFC
   function usb2GetUAC2SubSlotSize(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant a : boolean      := true
   ) return integer;

end package Usb2DescPkg;

package body Usb2DescPkg is

   function usb2NextDescriptor(
      constant d: Usb2ByteArray;
      constant i: integer;
      constant a: boolean := false
   ) return integer is
      variable x : integer;
   begin
      x := i;
      if ( x < 0 ) then
         return x;
      end if;
      x := x + to_integer( unsigned( d(x + USB2_DESC_IDX_LENGTH_C) ) );
      if ( x >= d'high ) then
         return -1;
      end if;
      if ( a and usb2DescIsSentinel( d(x + USB2_DESC_IDX_TYPE_C) ) ) then
         return -1;
      end if;
      return x;
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
      constant i: integer;
      constant t: Usb2ByteType;
      constant a: boolean := false
   ) return integer is
      variable x : integer;
   begin
      x := i;
report "i: " & integer'image(x) & " t " & toStr(std_logic_vector(t)) & " tbl " & toStr(d(x+USB2_DESC_IDX_TYPE_C));
      while ( x >= 0 and d(x + USB2_DESC_IDX_TYPE_C) /= Usb2ByteType(t) ) loop
         x := usb2NextDescriptor(d, x, a);
      end loop;
      return x;
   end function usb2NextDescriptor;

   -- find next descriptor of a certain class-specific subtype starting at index s; returns -1 if none found
   function usb2NextCsDescriptor(
      constant  d: Usb2ByteArray;
      constant  i: integer;
      constant st: Usb2ByteType;
      constant  e: boolean := false; -- class specific endpoint desciptor (not interface)
      constant  a: boolean := false  -- terminate at sentinel?
   ) return integer is
      constant dt : Usb2ByteType := ite(e, USB2_CS_DESC_TYPE_ENDPOINT_C, USB2_CS_DESC_TYPE_INTERFACE_C);
      constant pt : Usb2ByteType := ite(e, USB2_DESC_TYPE_ENDPOINT_C, USB2_DESC_TYPE_INTERFACE_C);
      variable  x : integer;
   begin
      x := i;
      assert d(x + USB2_DESC_IDX_TYPE_C) = pt report "usb2CsNextCsDescriptor() must start searching at an Interface/Endpoint descriptor." severity failure;
      x := usb2NextDescriptor(d, x, a);
      while ( x >= 0 ) loop
         if ( d(x + USB2_DESC_IDX_TYPE_C) = USB2_DESC_TYPE_ENDPOINT_C ) then
            -- next endpoint; there was not CS-specific descriptor in between
            return -1;
         end if;
         if ( d(x + USB2_DESC_IDX_TYPE_C) = USB2_DESC_TYPE_INTERFACE_C ) then
            -- next endpoint; there was not CS-specific descriptor in between
            return -1;
         end if;
         if ( d(x + USB2_DESC_IDX_TYPE_C) = dt and d(x + USB2_CS_DESC_IDX_SUBTYPE_C) = st ) then
            return x; -- FOUND
         end if;
         x := usb2NextDescriptor(d, x, a );
      end loop;
      return x;
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
      return highest;
   end function findMax;

   function usb2AppGetMaxEndpointAddr(constant d: Usb2ByteArray)
   return positive is
      variable v : integer;
   begin
      v := findMax(d, USB2_DESC_TYPE_ENDPOINT_C, USB2_EPT_DESC_IDX_ADDRESS_C, 3);
      if ( v < 0 ) then
         v := 0; -- EP 0 has no descriptor
      end if;
      v := v + 1; -- num endpoints = max addr + 1
      report integer'image(v) & " endpoints";
      return v;
   end function usb2AppGetMaxEndpointAddr;

   function usb2AppGetMaxInterfaces(constant d: Usb2ByteArray)
   return natural is
      variable v : natural;
   begin
      v := findMax(d, USB2_DESC_TYPE_INTERFACE_C, USB2_IFC_DESC_IDX_IFC_NUM_C, 6);
      v := v + 1; -- number of ifc = max index + 1
      report integer'image(v) & " max IFs";
      return v;
   end function usb2AppGetMaxInterfaces;

   function usb2AppGetMaxAltsettings(constant d: Usb2ByteArray)
   return natural is
      variable v : natural;
   begin
      v := findMax(d, USB2_DESC_TYPE_INTERFACE_C, USB2_IFC_DESC_IDX_ALTSETTING_C, 6);
      v := v + 1; -- number of alts = max index + 1
      report integer'image(v) & " max ALTs";
      return v;
   end function usb2AppGetMaxAltsettings;

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

   -- count number of configurations; if
   -- a => false then both speeds are counted
   function Usb2AppGetNumConfigurations(
      constant d: Usb2ByteArray;
      constant i: integer;
      constant a: boolean := true
   )
   return integer is
      variable nc : natural;
   begin
      if ( i < 0 ) then
         return -1;
      end if;
      nc := usb2CountDescriptors(d(i to d'high), USB2_DESC_TYPE_CONFIGURATION_C, a => a);
      assert nc > 0 report "No configurations?" severity failure;
      return nc;
   end function Usb2AppGetNumConfigurations;

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

   function usb2AppGetConfigIdxTbl(constant d: Usb2ByteArray; constant hs : boolean := false)
   return Usb2DescIdxArray is
      constant di  : integer  := deviceDescriptorIndex(d, hs);
      constant NC  : integer  := Usb2AppGetNumConfigurations(d, di);
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
   end function usb2AppGetConfigIdxTbl;

   function usb2AppGetNumStrings(constant d: Usb2ByteArray)
   return natural is
   begin
      return usb2CountDescriptors(d, USB2_DESC_TYPE_STRING_C);
   end function usb2AppGetNumStrings;

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

   function usb2NextIfcDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant c : Usb2ByteType;
      constant s : Usb2ByteType
   ) return integer is
      variable x : integer;
   begin
      x := i;
      L_IFC : while true loop

         x := usb2NextDescriptor(d, x, USB2_DESC_TYPE_INTERFACE_C, a => true);
         if ( x < 0 ) then
            return -1;
         end if;

         if (     ( d( x + USB2_IFC_DESC_IFC_CLASS_C    ) = c )
              and ( d( x + USB2_IFC_DESC_IFC_SUBCLASS_C ) = s ) ) then
            exit L_IFC;
         end if;

         x := usb2NextDescriptor( d, x, a => true );
         if ( x < 0 ) then
            return -1;
         end if;
      end loop;
      return x;
   end function usb2NextIfcDescriptor;

   function usb2EthNetworkingDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return integer is
      variable x : integer;
   begin
      x := i;
      x := usb2NextIfcDescriptor( d, x, USB2_IFC_CLASS_CDC_C, s );
      if ( x < 0 ) then
         return -1;
      end if;

      -- ECM and NCM both use this subtype of descriptor
      x  := usb2NextCsDescriptor( d, x, USB2_CS_DESC_SUBTYPE_CDC_ECM_C, a => true );
      assert x > 0 report " Ethernet functional descriptor not found" severity warning;
      if ( x < 0 ) then
         return -1;
      end if;
      return x;
   end function usb2EthNetworkingDescriptor;

   function usb2EthMacAddrStringDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return integer is
      variable x                    : integer;
      variable si                   : integer;
      constant IDX_MAC_ADDR_SIDX_C  : natural      := 3;
   begin
      x := i;
      x := usb2EthNetworkingDescriptor( d, x, s );
      if ( x < 0 ) then
         return -1;
      end if;

      si := to_integer( unsigned( d( x + IDX_MAC_ADDR_SIDX_C ) ) );
      assert si > 0 report "CDCECM invalid iMACAddr string index" severity warning;

      return usb2NthStringDescriptor( d, si );

   end function usb2EthMacAddrStringDescriptor;

   function usb2NextIfcAssocDescriptor(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant c : Usb2ByteType;
      constant s : Usb2ByteType;
      constant p : Usb2ByteType := (others => 'X');
      constant a : boolean      := true
   ) return integer is
      variable x              : integer;
      constant IDX_FCN_CLSS_C : natural := 4;
      constant IDX_FCN_SUBC_C : natural := 5;
      constant IDX_FCN_PROT_C : natural := 6;
      constant X_C            : Usb2ByteType := (others => 'X');
   begin
      x := usb2NextDescriptor(d, i, USB2_DESC_TYPE_INTERFACE_ASSOCIATION_C, a);
      while ( x >= 0 ) loop
         if (     (   d(x + IDX_FCN_CLSS_C) = c )
              and (   d(x + IDX_FCN_SUBC_C) = s )
              and ( ( d(x + IDX_FCN_PROT_C) = p ) or ( p = X_C ) ) ) then
            return x;
         end if;
         -- skip this one
         x := usb2NextDescriptor(d, x, a );
         if ( x >= 0 ) then
            -- look for the next association desc
            x := usb2NextDescriptor(d, x, USB2_DESC_TYPE_INTERFACE_ASSOCIATION_C, a);
         end if;
      end loop;
      return x;
   end function usb2NextIfcAssocDescriptor;

   -- unicode!
   function usb2HexStrToBin(
      constant d : Usb2ByteArray
   ) return Usb2ByteArray is
      variable v     : Usb2ByteArray(0 to d'length/4 - 1);
      variable nibhi : unsigned(3 downto 0);
      variable niblo : unsigned(3 downto 0);
      constant A_C   : std_logic_vector := x"41";
   begin
      for i in v'range loop
         nibhi := unsigned(d(d'low + 4*i + 0)(3 downto 0));
         -- note that this hack also works for lower-case 0x61 since
         -- we just looked at the nibble...
         if ( unsigned(d(d'low + 4*i + 0)) >= unsigned(A_C) ) then
            nibhi := nibhi + 9;
         end if;
         niblo := unsigned(d(d'low + 4*i + 2)(3 downto 0));
         if ( unsigned(d(d'low + 4*i + 2)) >= unsigned(A_C) ) then
            niblo := niblo + 9;
         end if;
         v(i) := std_logic_vector(nibhi & niblo);
       end loop;
       return v;
   end function usb2HexStrToBin;

   function getMacAddr(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant w : boolean
   ) return Usb2ByteArray is
      constant NOTFOUND_C : Usb2ByteArray(0 to -1) := (others => (others => '0'));
      variable idx        : integer;
   begin
      if ( w ) then
         idx := usb2EthMacAddrStringDescriptor( d, i, USB2_IFC_SUBCLASS_CDC_NCM_C );
      else
         idx := usb2EthMacAddrStringDescriptor( d, i, USB2_IFC_SUBCLASS_CDC_ECM_C );
      end if;
      if ( idx < 0 ) then
         return NOTFOUND_C;
      end if;
      return usb2HexStrToBin( d(idx + 2 to idx + 2 + 24 - 1 ) );
   end function getMacAddr;

   function usb2GetECMMacAddr(
      constant d : Usb2ByteArray;
      constant i : integer
   ) return Usb2ByteArray is
   begin
      return getMacAddr( d, i, false );
   end function usb2GetECMMacAddr;

   function usb2GetNCMMacAddr(
      constant d : Usb2ByteArray;
      constant i : integer
   ) return Usb2ByteArray is
   begin
      return getMacAddr( d, i, true );
   end function usb2GetNCMMacAddr;

   function usb2GetNCMNetworkCapabilities(
      constant d : Usb2ByteArray;
      constant i : integer
   ) return std_logic_vector is
      constant NCM_IFC_IDX_C  : integer :=
         usb2NextIfcDescriptor(d, i, USB2_IFC_CLASS_CDC_C, USB2_IFC_SUBCLASS_CDC_NCM_C);
      constant NCM_CS_IDX_C   : integer :=
         ite( NCM_IFC_IDX_C > 0,
              usb2NextCsDescriptor(d, NCM_IFC_IDX_C, USB2_CS_DESC_SUBTYPE_CDC_NCM_C, a =>true ),
              -1 );
      constant NOT_FOUND_C    : std_logic_vector( -1 downto 0 ) := (others => '0');
   begin
      return ite( NCM_CS_IDX_C  > 0, std_logic_vector( d(NCM_CS_IDX_C + 5) ), NOT_FOUND_C );
   end function usb2GetNCMNetworkCapabilities;

   function usb2GetNumMCFilters(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return integer is
      variable x : integer;
      variable v : integer;
   begin
      x := i;
      x := usb2EthNetworkingDescriptor(d, x, s);
      assert (x >= 0) report "Ethernet Networking Functional Desciptor not found" severity failure;
      v := to_integer(unsigned(d(x + 10)));
      v := v + 256*to_integer(unsigned(d(x+11)(6 downto 0)));
      return v;
   end function usb2GetNumMCFilters;

   function usb2GetMCFilterPerfect(
      constant d : Usb2ByteArray;
      constant i : integer;
      -- must be one of USB2_IFC_SUBCLASS_CDC_ECM_C, USB2_IFC_SUBCLASS_CDC_NCM_C
      constant s : Usb2ByteType := USB2_IFC_SUBCLASS_CDC_NCM_C
   ) return boolean is
      variable x : integer;
   begin
      x := i;
      x := usb2EthNetworkingDescriptor(d, x, s);
      assert (x >= 0) report "Ethernet Networking Functional Desciptor not found" severity failure;
      return d(x+11)(7) = '0';
   end function usb2GetMCFilterPerfect;

   function usb2NextCsUAC2(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant t : Usb2ByteType;
      constant s : boolean;
      constant a : boolean      := true
   ) return integer is
      variable x : integer;
      variable n : integer;
      constant scl : Usb2ByteType := ite(s, USB2_IFC_SUBCLASS_AUDIO_STREAMING_C, USB2_IFC_SUBCLASS_AUDIO_CONTROL_C);
   begin
      x := i;
      L_FIND_IFC : loop
         x := usb2NextIfcDescriptor(d, x, USB2_IFC_CLASS_AUDIO_C, scl);
         if ( x < 0 ) then
            return x;
         end if;
         n := usb2NextDescriptor(d, x, a);
         -- if there is no next descriptor there can be no next CS descriptor
         if ( n < 0 ) then
            return n;
         end if;
         if ( d( x + USB2_IFC_DESC_IFC_PROTOCOL_C ) = USB2_IFC_SUBCLASS_AUDIO_PROTOCOL_UAC2_C  ) then
            -- streaming interface has a default altsetting (empty)
            if ( d(n + USB2_DESC_IDX_TYPE_C) /= USB2_DESC_TYPE_INTERFACE_C ) then
               exit L_FIND_IFC;
            end if;
         end if;
         x := n;
      end loop;
      x := usb2NextCsDescriptor(
              d,
              x,
              t,
              false,
              a);
      return x;
   end function usb2NextCsUAC2;

   function usb2NextCsUAC2HeaderCategory(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant c : Usb2ByteType;
      constant a : boolean      := true
   ) return integer is
      variable x : integer;
      constant IDX_CATEGORY_C  : natural := 5;
      constant STREAMING_IFC_C : boolean := true;
   begin
      x := i;
      x := usb2NextCsUAC2(d, x, USB2_CS_DESC_SUBTYPE_AUDIO_HEADER_C, not STREAMING_IFC_C, a);
      if ( x < 0 ) then
         return x;
      end if;
      if ( d(x + IDX_CATEGORY_C) /= c ) then
         return -1;
      end if;
      return x;
   end function usb2NextCsUAC2HeaderCategory;

   function usb2GetUAC2NumChannels(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant a : boolean      := true
   ) return integer is
      variable x : integer;
      constant STREAMING_IFC_C : boolean := true;
      constant IDX_NUM_CHNS_C  : natural := 10;
   begin
      x := i;
      x := usb2NextCsUAC2(d, x, USB2_CS_DESC_SUBTYPE_AUDIO_GENERAL_C, STREAMING_IFC_C, a);
      assert x >= 0 report "No audio class-specific interface general descriptor found" severity failure;
      
      return to_integer( unsigned( d(x + IDX_NUM_CHNS_C) ) );
   end function usb2GetUAC2NumChannels;

   function usb2GetUAC2SubSlotSize(
      constant d : Usb2ByteArray;
      constant i : integer;
      constant a : boolean      := true
   ) return integer is
      variable x : integer;
      constant STREAMING_IFC_C : boolean := true;
      constant IDX_SUBSLOTSZ_C : natural := 4;
   begin
      x := i;
      x := usb2NextCsUAC2(d, x, USB2_CS_DESC_SUBTYPE_AUDIO_FORMAT_C, STREAMING_IFC_C, a);
      assert x >= 0 report "No audio class-specific interface format descriptor found" severity failure;
      
      return to_integer( unsigned( d(x + IDX_SUBSLOTSZ_C) ) );
   end function usb2GetUAC2SubSlotSize;

end package body Usb2DescPkg;
