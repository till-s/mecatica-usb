-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2EpGenericCtlPkg.all;


-- Example for how to extend EP0 functionality.
-- This module implements 'send-break' for CDC-ACM.

entity Usb2EpCDCACMCtl is
   generic (
      CTL_IFC_NUM_G   : natural;
      ASYNC_G         : boolean := false;
      -- whether to enable support for set/get line coding, set line-state
      -- if this is enabled then usb2Ep0ObExt/usb2EpIbExt must be connected!
      SUPPORT_LINE_G  : boolean := false;
      -- whether to enable support for send break
      SUPPORT_BREAK_G : boolean := true
   );
   port (
      usb2Clk         : in  std_logic;
      usb2Rst         : in  std_logic := '0';
      
      usb2SOF         : in  boolean;
      usb2Ep0ReqParam : in  Usb2CtlReqParamType;
      usb2Ep0CtlExt   : out Usb2CtlExtType;

      usb2Ep0IbExt    : in  Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;
      usb2Ep0ObExt    : out Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      -- these signals are in the usb2 clock domain; if you need them
      -- you need to synchronize your self (if ASYNC_G)
      rate            : out unsigned(31 downto 0) := (others => '0');
      stopBits        : out unsigned( 1 downto 0) := (others => '0');
      parity          : out unsigned( 2 downto 0) := (others => '0');
      dataBits        : out unsigned( 4 downto 0) := (others => '0');

      epClk           : in  std_logic := '0';

      lineBreak       : out std_logic;
      DTR             : out std_logic := '0';
      RTS             : out std_logic := '0'
   );
end entity Usb2EpCDCACMCtl;

architecture Impl of Usb2EpCDCACMCtl is

   constant LCODING_SZ_C                      : natural := 7;

   constant CTL_IFC_NUM_C                     : Usb2InterfaceNumType := toUsb2InterfaceNumType( CTL_IFC_NUM_G );

   constant REQS_BREAK_C                      : Usb2EpGenericReqDefArray := (
      0 => usb2MkEpGenericReqDef (
      dev2Host  => '0',
      request   => USB2_REQ_CLS_CDC_SEND_BREAK_C,
      dataSize  => 0
      )
   );

   constant REQS_LINE_C                       : Usb2EpGenericReqDefArray := (
      usb2MkEpGenericReqDef (
      dev2Host  => '0',
      request   => USB2_REQ_CLS_CDC_SET_CONTROL_LINE_STATE_C,
      dataSize  => 0
      ),
      usb2MkEpGenericReqDef (
      dev2Host  => '0',
      request   => USB2_REQ_CLS_CDC_SET_LINE_CODING_C,
      dataSize  => LCODING_SZ_C
      ),
      usb2MkEpGenericReqDef (
      dev2Host  => '1',
      request   => USB2_REQ_CLS_CDC_GET_LINE_CODING_C,
      dataSize  => LCODING_SZ_C
      )
   );

   constant HANDLE_REQUESTS_C : Usb2EpGenericReqDefArray := concat( ite( SUPPORT_BREAK_G, REQS_BREAK_C ), ite( SUPPORT_LINE_G, REQS_LINE_C ) );

   type RegType is record
      timer     : unsigned(16 downto 0);
      indef     : boolean;
      DTR       : std_logic;
      RTS       : std_logic;
      buf       : Usb2ByteArray(0 to LCODING_SZ_C - 1);
   end record RegType;

   constant REG_INIT_C : RegType := (
      timer    => (others => '0'),
      indef    => false,
      DTR      => '0',
      RTS      => '0',
      buf      => (others => (others => '0'))
   );

   signal r          : RegType := REG_INIT_C;
   signal rin        : RegType;

   signal ctlReqVld  : std_logic_vector( HANDLE_REQUESTS_C'range );
   signal ctlReqAck  : std_logic := '0';
   signal ctlReqErr  : std_logic := '1';
   signal parmsOb    : Usb2ByteArray( 0 to LCODING_SZ_C - 1 );

begin

   -- assume at least one of SUPPORT_BREAK_G or SUPPORT_LINE_G is enabled
   U_CTL : entity work.Usb2EpGenericCtl
      generic map (
         CTL_IFC_NUM_G           => CTL_IFC_NUM_G,
         HANDLE_REQUESTS_G       => HANDLE_REQUESTS_C
      )
      port map (
         usb2Clk                 => usb2Clk,
         usb2Rst                 => usb2Rst,

         usb2CtlReqParam         => usb2Ep0ReqParam,
         usb2CtlExt              => usb2Ep0CtlExt,

         usb2EpIb                => usb2Ep0IbExt,
         usb2EpOb                => usb2Ep0ObExt,

         ctlReqVld               => ctlReqVld,
         ctlReqAck               => ctlReqAck,
         ctlReqErr               => ctlReqErr,

         paramIb                 => r.buf,
         paramOb                 => parmsOb
      );

   P_COMB : process ( r, usb2Ep0ReqParam, ctlReqVld, parmsOb, usb2SOF ) is
      variable v : RegType;
   begin
      v := r;

      ctlReqAck <= '1';
      ctlReqErr <= '1';

      if ( usb2SOF and ( r.timer(r.timer'left) = '1' ) and not r.indef ) then
         v.timer := r.timer - 1;
      end if;

      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_SEND_BREAK_C, HANDLE_REQUESTS_C ) ) then
         v.timer(15 downto 0) := unsigned(usb2Ep0ReqParam.value);
         v.timer(16)          := '1';
         if    ( usb2Ep0ReqParam.value = x"0000" ) then
            v.indef     := false;
            v.timer(16) := '0';
         elsif ( usb2Ep0ReqParam.value = x"ffff" ) then
            v.indef     := true;
         end if;
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_SET_CONTROL_LINE_STATE_C, HANDLE_REQUESTS_C ) ) then
         v.DTR          := usb2Ep0ReqParam.value(0);
         v.RTS          := usb2Ep0ReqParam.value(1);
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_SET_LINE_CODING_C, HANDLE_REQUESTS_C ) ) then
         v.buf          := parmsOb;
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_GET_LINE_CODING_C, HANDLE_REQUESTS_C ) ) then
         ctlReqErr      <= '0';
      end if;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( usb2Rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;


   G_BREAK_SUP : if ( SUPPORT_BREAK_G ) generate

      G_BRK_ASYNC : if ( ASYNC_G ) generate
         U_SYNC : entity work.Usb2CCSync
            port map (
               clk => epClk,
               d   => r.timer(r.timer'left),
               q   => lineBreak
            );
      end generate G_BRK_ASYNC;

      G_BRK_SYNC : if ( not ASYNC_G ) generate
         lineBreak     <= r.timer(r.timer'left);
      end generate G_BRK_SYNC;

   end generate G_BREAK_SUP;

   G_LINE_SUP : if ( SUPPORT_LINE_G ) generate
      function toUnsigned(constant x : Usb2ByteArray) return unsigned is
         variable v : unsigned(8*x'length - 1 downto 0) := (others => '0');
      begin
         for i in x'high downto x'low loop
            v := resize( v & unsigned(x(i)), v'length );
         end loop;
         return v;
      end function;
   begin

      G_MDM_ASYNC : if ( ASYNC_G ) generate
         U_SYNC_RTS : entity work.Usb2CCSync
            port map (
               clk => epClk,
               d   => r.DTR,
               q   => DTR
            );
         U_SYNC_DTR : entity work.Usb2CCSync
            port map (
               clk => epClk,
               d   => r.RTS,
               q   => RTS
            );
      end generate G_MDM_ASYNC;

      G_MDM_SYNC : if ( not ASYNC_G ) generate
         DTR  <= r.DTR;
         RTS  <= r.RTS;
      end generate G_MDM_SYNC;

      rate          <= toUnsigned( r.buf(0 to 3) );
      stopBits      <= unsigned( r.buf(4)(stopBits'range) );
      parity        <= unsigned( r.buf(5)(parity'range)   );
      dataBits      <= unsigned( r.buf(6)(dataBits'range) );
   end generate G_LINE_SUP;

end architecture Impl;
