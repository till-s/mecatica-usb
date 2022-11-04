library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

package Usb2DescPkg is

   -- the actual descriptors are defined by the application
   -- which must supply the package body
   constant USB2_APP_CFG_DESCRIPTORS_C :  Usb2ByteArray;
   -- number of endpoints (including EP 0)
   constant USB2_APP_NUM_ENDPOINTS_C   :  positive;
   -- max. number of interfaces among all configurations
   -- e.g., if config 1 has 1 interface and config 2 has
   -- 2 interfaces then the max would be 2.  
   constant USB2_APP_MAX_INTERFACES_C  : natural;
   -- max. number of alt. settings of any interface of
   -- any configuration.
   -- e.g., if config 1 has 1 interface 3 alt-settings
   -- a second interface with 2 alt-settings and config 2
   -- has a single interface with 1 alt-settings then
   -- the max would be 3. Note that the number of alt-
   -- settings includes the default (0) setting.
   constant USB2_APP_MAX_ALTSETTINGS_C : positive;

   -- device desriptor
   constant USB2_APP_DEV_DESCRIPTOR_C  :  Usb2ByteArray;

   subtype  Usb2DescIdxType    is natural range 0 to USB2_APP_CFG_DESCRIPTORS_C'length - 1;

   -- indirect access to tables; allows for multiple levels
   -- of indirection.
   type Usb2TblPtrType is record
      -- offset into the next-level table
      off      : Usb2DescIdxType;
      -- # of elements of the next-level table
      len      : Usb2DescIdxType;
   end record Usb2TblPtrType;

   constant USB2_DESC_IDX_LENGTH_C                        : natural := 0;
   constant USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C             : natural := 7;

   constant USB2_CFG_DESC_IDX_NUM_INTERFACES_C            : natural := 4;
   constant USB2_CFG_DESC_IDX_CFG_VALUE_C                 : natural := 5;
   constant USB2_CFG_DESC_IDX_ATTRIBUTES_C                : natural := 7;

end package Usb2DescPkg;
