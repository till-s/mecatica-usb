library ieee;
use     ieee.std_logic_1164.all;

entity UlpiDev1Wrap is
   port (
      JB1_P :  out   std_logic;
      JB1_N :  in    std_logic;
      JB2_P :  out   std_logic;
      JB3_P :  in    std_logic;
      JB4_P :  in    std_logic;
      JC1_P :  inout std_logic;
      JC2_P :  inout std_logic;
      JC3_P :  inout std_logic;
      JC4_P :  inout std_logic;
      JD1_P :  inout std_logic;
      JD2_P :  inout std_logic;
      JD3_P :  inout std_logic;
      JD4_P :  inout std_logic;
      HDMI_CLK_P :  in    std_logic
   );
end entity UlpiDev1Wrap;

architecture Impl of UlpiDev1Wrap is
begin

   U_TOP : entity work.UlpiDev1Top
      port map (
         ref    => HDMI_CLK_P,
         clk    => JB1_P,
         rst    => JB1_N,
         stp    => JB2_P,
         dir    => JB3_P,
         nxt    => JB4_P,
         dat(0) => JC1_P,
         dat(1) => JC2_P,
         dat(2) => JC3_P,
         dat(3) => JC4_P,
         dat(4) => JD1_P,
         dat(5) => JD2_P,
         dat(6) => JD3_P,
         dat(7) => JD4_P
      );

end architecture Impl;
