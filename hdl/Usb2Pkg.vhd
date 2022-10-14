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
