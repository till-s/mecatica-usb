library ieee;
use     ieee.std_logic_1164.all;

package Usb2Pkg is

   subtype Usb2PidType      is std_logic_vector(3 downto 0);
   subtype Usb2PidGroupType is std_logic_vector(1 downto 0);

   function usb2PidIsTok(constant x : in Usb2PidType) return boolean;
   function usb2PidIsDat(constant x : in Usb2PidType) return boolean;
   function usb2PidIsHsk(constant x : in Usb2PidType) return boolean;
   function usb2PidIsSpc(constant x : in Usb2PidType) return boolean;

   function usb2PidGroup(constant x : in Usb2PidType) return Usb2PidGroupType;

   constant USB_PID_GROUP_TOK_C: Usb2PidGroupType := "01";
   constant USB_PID_GROUP_DAT_C: Usb2PidGroupType := "11";
   constant USB_PID_GROUP_HSK_C: Usb2PidGroupType := "10";
   constant USB_PID_GROUP_SPC_C: Usb2PidGroupType := "00";

   constant USB_PID_TOK_OUT_C  : Usb2PidType := x"1";
   constant USB_PID_TOK_SOF_C  : Usb2PidType := x"5";
   constant USB_PID_TOK_IN_C   : Usb2PidType := x"9";
   constant USB_PID_TOK_SETUP_C: Usb2PidType := x"D";

   constant USB_PID_DAT_DATA0_C: Usb2PidType := x"3";
   constant USB_PID_DAT_DATA2_C: Usb2PidType := x"7";
   constant USB_PID_DAT_DATA1_C: Usb2PidType := x"B";
   constant USB_PID_DAT_MDATA_C: Usb2PidType := x"F";

   constant USB_PID_HSK_ACK_C  : Usb2PidType := x"2";
   constant USB_PID_HSK_NYET_C : Usb2PidType := x"6";
   constant USB_PID_HSK_NAK_C  : Usb2PidType := x"A";
   constant USB_PID_HSK_STALL_C: Usb2PidType := x"E";

   constant USB_PID_SPC_PRE_C  : Usb2PidType := x"C";
   constant USB_PID_SPC_ERR_C  : Usb2PidType := x"C"; -- reused
   constant USB_PID_SPC_SPLIT_C: Usb2PidType := x"8";
   constant USB_PID_SPC_PING_C : Usb2PidType := x"4";

   constant USB_PID_SPC_NONE_C : Usb2PidType := x"0"; -- reserved

   type Usb2PktHdrType is record
      pid     : Usb2PidType;
      tokDat  : std_logic_vector(10 downto 0);
      valid   : std_logic; -- asserted for 1 cycle
   end record Usb2PktHdrType;

   constant USB2_PKT_HDR_INIT_C : Usb2PktHdrType := (
      pid     => USB_PID_SPC_NONE_C,
      tokDat  => (others => '0'),
      valid   => '0'
   );

   function usb2TokenPktAddr(constant x : in Usb2PktHdrType)
      return std_logic_vector;

   function usb2TokenPktEndp(constant x : in Usb2PktHdrType)
      return std_logic_vector;

   type Usb2StrmMstType is record
      dat   : std_logic_vector(7 downto 0);
      vld   : std_logic;
      don   : std_logic;
      err   : std_logic; -- when asserted with 'don' then there was e.g., a bad checksum
   end record Usb2StrmMstType;

   constant USB2_STRM_MST_INIT_C : Usb2StrmMstType := (
      dat   => (others => '0'),
      vld   => '0',
      don   => '0',
      err   => '0'
   );

   type Usb2StrmSubType is record
      rdy   : std_logic;
      -- if an error occurs then the stream is aborted (sender must stop)
      -- i.e., 'don' may be asserted before all the data are sent!
      err   : std_logic;
      don   : std_logic;
   end record Usb2StrmSubType;

   constant USB2_STRM_SUB_INIT_C : Usb2StrmSubType := (
      rdy   => '0',
      err   => '0',
      don   => '0'
   );

   constant USB2_CRC5_POLY_C  : std_logic_vector(15 downto 0) := x"0014";
   constant USB2_CRC5_CHCK_C  : std_logic_vector(15 downto 0) := x"0006";
   constant USB2_CRC5_INIT_C  : std_logic_vector(15 downto 0) := x"001F";

   constant USB2_CRC16_POLY_C : std_logic_vector(15 downto 0) := x"A001";
   constant USB2_CRC16_CHCK_C : std_logic_vector(15 downto 0) := x"B001";
   constant USB2_CRC16_INIT_C : std_logic_vector(15 downto 0) := x"FFFF";
 
end package Usb2Pkg;

package body Usb2Pkg is

   function usb2TokenPktAddr(constant x : in Usb2PktHdrType)
      return std_logic_vector is
   begin
      return x.tokDat(10 downto 4);
   end function usb2TokenPktAddr;

   function usb2TokenPktEndp(constant x : in Usb2PktHdrType)
      return std_logic_vector is
   begin
      return x.tokDat(10 downto 4);
   end function usb2TokenPktEndp;

   function usb2PidIsTok(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "01";
   end function usb2PidIsTok;

   function usb2PidIsDat(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "11";
   end function usb2PidIsDat;

   function usb2PidIsHsk(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "10";
   end function usb2PidIsHsk;

   function usb2PidIsSpc(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "00";
   end function usb2PidIsSpc;

   function usb2PidGroup(constant x : in Usb2PidType) return Usb2PidGroupType is
   begin
      return x(1 downto 0);
   end function usb2PidGroup;

end package body Usb2Pkg;
