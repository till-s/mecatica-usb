library ieee;
use     ieee.std_logic_1164.all;

package Usb2Pkg is

   type Usb2TokenType is (TOK_OUT, TOK_SOF, TOK_IN, TOK_SETUP);

   type Usb2TokenPktType is record
      token   : Usb2TokenType;
      data    : std_logic_vector(10 downto 0);
      valid   : std_logic; -- asserted for 1 cycle
   end record Usb2TokenPktType;

   constant USB2_TOKEN_PKT_INIT_C : Usb2TokenPktType := (
      token   => TOK_SETUP,
      data    => (others => '0'),
      valid   => '0'
   );

   function usb2TokenPktAddr(constant x : in Usb2TokenPktType)
      return std_logic_vector;

   function usb2TokenPktEndp(constant x : in Usb2TokenPktType)
      return std_logic_vector;

   type Usb2StrmMstType is record
      dat   : std_logic_vector(7 downto 0);
      vld   : std_logic;
      lst   : std_logic;
   end record Usb2StrmMstType;

   constant USB2_STRM_MST_INIT_C : Usb2StrmMstType := (
      dat   => (others => '0'),
      vld   => '0',
      lst   => '0'
   );

   type Usb2StrmSubType is record
      rdy   : std_logic;
      err   : std_logic;
   end record Usb2StrmSubType;

   constant USB2_STRM_SUB_INIT_C : Usb2StrmSubType := (
      rdy   => '0',
      err   => '0'
   );
 
end package Usb2Pkg;

package body Usb2Pkg is

   function usb2TokenPktAddr(constant x : in Usb2TokenPktType)
      return std_logic_vector is
   begin
      return x.data(10 downto 4);
   end function usb2TokenPktAddr;

   function usb2TokenPktEndp(constant x : in Usb2TokenPktType)
      return std_logic_vector is
   begin
      return x.data(10 downto 4);
   end function usb2TokenPktEndp;

end package body Usb2Pkg;
