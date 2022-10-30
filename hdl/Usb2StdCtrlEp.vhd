library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

entity Usb2StdCtlEp is
   generic (
      MARK_DEBUG_G    : boolean := true;
      ENDPOINTS_G     : Usb2EndpPairPropertyArray
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';

      -- connection to the packet engine
      epIb            : in  Usb2EndpPairObType;
      epOb            : out Usb2EndpPairIbType;

      param           : out Usb2CtlReqParamType;
      -- an external agent may take over the
      -- data phase and execution of the control
      -- transaction. It must monitor the 'epIb'
      -- stream(s) and store any data needed.
      -- Once the param.vld is asserted '1' the
      -- external agent needs to 'ack' with the 'err' and 'don'
      -- flags clear.
      -- Once the transaction is processed the
      -- external agent asserts 'don' and conveys status
      -- in 'ack' and 'err'.
      ctlExt          : in  Usb2CtlExtType     := USB2_CTL_EXT_INIT_C;
      epExt           : in  Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      devStatus       : out Usb2DevStatusType
   );
end entity Usb2StdCtlEp;
