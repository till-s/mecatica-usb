library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;

-- simple program to test functions in Usb2DescPkg; make sure
-- the example descriptors can be parsed!

package Usb2DescCfgPkgTest is
   function usb2AppGetDescriptors return Usb2ByteArray;
end package Usb2DescCfgPkgTest;

library ieee;
use     ieee.std_logic_1164.all;

use     work.Usb2Pkg.all;
use     work.Usb2DescCfgPkgTest.all;

entity Usb2DescPkgTb is end entity Usb2DescPkgTb;

architecture sim of Usb2DescPkgTb is


   constant DESCRIPTORS_C : Usb2ByteArray := usb2AppGetDescriptors;

   signal   usb2Clk       : std_logic     := '0';

begin
   P_TEST : process is
   begin
      report "Example Descriptors successfully instantiated";
      wait;
   end process P_TEST;

   U_DUT : entity work.Usb2ExampleDev
      generic map (
         DESCRIPTORS_G => DESCRIPTORS_C
      )
      port map (
         usb2Clk       => usb2Clk
      );

end architecture sim;
