-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Control-interface endpoint for CDC NCM

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2EpGenericCtlPkg.all;

entity Usb2EpCDCNCMCtl is
   generic (
      CTL_IFC_NUM_G                     : natural;
      MAX_NTB_SIZE_INP_G                : natural;
      MAX_NTB_SIZE_OUT_G                : natural;
      MAX_DGRAMS_OUT_G                  : natural;
      SUPPORT_NET_ADDRESS_G             : boolean               := false;
      SUPPORT_SET_MC_FILT_G             : boolean               := false;
      MAC_ADDR_G                        : Usb2ByteArray(0 to 5) := (others => (others => '0'))
   );
   port (
      usb2Clk                           : in  std_logic;
      usb2Rst                           : in  std_logic := '0';
      
      usb2Ep0ReqParam                   : in  Usb2CtlReqParamType;
      usb2Ep0CtlExt                     : out Usb2CtlExtType;

      usb2Ep0IbExt                      : in  Usb2EndpPairObType := USB2_ENDP_PAIR_OB_INIT_C;
      usb2Ep0ObExt                      : out Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      -- these signals are in the usb2 clock domain; if you need them
      -- you need to synchronize your self (if ASYNC_G)
      maxNTBSizeInp                     : out unsigned(31 downto 0);
      -- network-byte order
      macAddress                        : out Usb2ByteArray(0 to 5 );
      packetFilter                      : out std_logic_vector(4 downto 0);
      -- set multicast filters request is streamed out here
      mcFilterDat                       : out Usb2ByteType := (others => '0');
      -- request is terminated by vld = '1', don = '1'. During this
      -- cycle the data are *not* valid (allows for clearing the filters
      -- with a single cycle (vld = don = '1'). 'lst' is asserted during
      -- the last data-valid cycle.
      -- There might be gaps with 'vld' deasserted. Receiver must wait for
      -- 'don' to terminate reception.
      mcFilterVld                       : out std_logic := '0';
      mcFilterLst                       : out std_logic := '0';
      mcFilterDon                       : out std_logic := '0'
   );
end entity Usb2EpCDCNCMCtl;

architecture Impl of Usb2EpCDCNCMCtl is

   constant CTL_IFC_NUM_C                     : Usb2InterfaceNumType     := toUsb2InterfaceNumType( CTL_IFC_NUM_G );

   constant MANDATORY_REQS_C                  : Usb2EpGenericReqDefArray := (
      usb2MkEpGenericReqDef(
         dev2Host => '1',
         request  =>  USB2_REQ_CLS_CDC_GET_NTB_PARAMETERS_C,
         dataSize => 28
      ),
      usb2MkEpGenericReqDef(
         dev2Host => '1',
         request  =>  USB2_REQ_CLS_CDC_GET_NTB_INPUT_SIZE_C,
         dataSize =>  4
      ),
      usb2MkEpGenericReqDef(
         dev2Host => '0',
         request  =>  USB2_REQ_CLS_CDC_SET_NTB_INPUT_SIZE_C,
         dataSize =>  4
      ),
      -- this is not mandatory but comes almost for free
      usb2MkEpGenericReqDef(
         dev2Host => '0',
         request  =>  USB2_REQ_CLS_CDC_SET_ETHERNET_PACKET_FILTER_C,
         dataSize =>  0
      )
   );

   constant NET_ADDR_REQS_C                   : Usb2EpGenericReqDefArray := (
      usb2MkEpGenericReqDef(
         dev2Host => '1',
         request  =>  USB2_REQ_CLS_CDC_GET_NET_ADDRESS_C,
         dataSize =>  6
      ),
      usb2MkEpGenericReqDef(
         dev2Host => '0',
         request  =>  USB2_REQ_CLS_CDC_SET_NET_ADDRESS_C,
         dataSize =>  6
      )
   );

   constant MC_FILTER_REQ_C                   : Usb2EpGenericReqDefArray := (
     0 => usb2MkEpGenericReqDef(
         dev2Host => '0',
         request  =>  USB2_REQ_CLS_CDC_SET_ETHERNET_MC_FILTERS_C,
         dataSize =>  0,
         stream   =>  true
      )
   );

   constant HANDLE_REQUESTS_C                 : Usb2EpGenericReqDefArray :=
      concat( MANDATORY_REQS_C,
         concat( ite( SUPPORT_NET_ADDRESS_G, NET_ADDR_REQS_C ),
                 ite( SUPPORT_SET_MC_FILT_G, MC_FILTER_REQ_C )
         )
      );

   type RegType is record
      maxNTBSizeInp  : unsigned(31 downto 0);
      macAddr        : Usb2ByteArray(0 to 5);
      packetFilter   : std_logic_vector(packetFilter'range);
   end record RegType;

   constant REG_INIT_C : RegType := (
      maxNTBSizeInp  =>  to_unsigned( MAX_NTB_SIZE_INP_G, 32 ),
      macAddr        =>  MAC_ADDR_G,
      packetFilter   => (others => '1')
   );

   signal r          : RegType := REG_INIT_C;
   signal rin        : RegType;

   signal ctlReqVld  : std_logic_vector( HANDLE_REQUESTS_C'range );
   signal ctlReqAck  : std_logic := '0';
   signal ctlReqErr  : std_logic := '1';
   signal parmsOb    : Usb2ByteArray( 0 to maxParamSize( HANDLE_REQUESTS_C ) - 1 );
   signal parmsIb    : Usb2ByteArray( 0 to maxParamSize( HANDLE_REQUESTS_C ) - 1 );

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

         paramIb                 => parmsIb,
         paramOb                 => parmsOb
      );

   P_COMB : process ( r, usb2Ep0ReqParam, ctlReqVld, parmsOb ) is
      variable v : RegType;
   begin
      v := r;

      ctlReqAck    <= '1';
      ctlReqErr    <= '1';
      mcFilterVld  <= '0';

      -- NTB parameters (default)
      parmsIb( 0)  <= x"1C"; -- struct size
      parmsIb( 1)  <= x"00";
      parmsIb( 2)  <= x"01"; -- 16-bit NTB only
      parmsIb( 3)  <= x"00";
      -- should we supply the 'live' size or our max. supported size?
      parmsIb( 4)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_INP_G, 32 )( 7 downto  0) );
      parmsIb( 5)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_INP_G, 32 )(15 downto  8) );
      parmsIb( 6)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_INP_G, 32 )(23 downto 16) );
      parmsIb( 7)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_INP_G, 32 )(31 downto 24) );
      parmsIb( 8)  <= x"01"; -- NDP IN divisor
      parmsIb( 9)  <= x"00";
      parmsIb(10)  <= x"00"; -- NDP IN remainder
      parmsIb(11)  <= x"00";
      parmsIb(12)  <= x"04"; -- NDP IN alignment
      parmsIb(13)  <= x"00";
      parmsIb(14)  <= x"00"; -- reserved
      parmsIb(15)  <= x"00";
      parmsIb(16)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_OUT_G, 32 )( 7 downto  0) );
      parmsIb(17)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_OUT_G, 32 )(15 downto  8) );
      parmsIb(18)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_OUT_G, 32 )(23 downto 16) );
      parmsIb(19)  <= Usb2ByteType( to_unsigned( MAX_NTB_SIZE_OUT_G, 32 )(31 downto 24) );
      parmsIb(20)  <= x"01"; -- NDP OUT divisor
      parmsIb(21)  <= x"00";
      parmsIb(22)  <= x"00"; -- NDP OUT remainder
      parmsIb(23)  <= x"00";
      parmsIb(24)  <= x"04"; -- NDP OUT alignment
      parmsIb(25)  <= x"00";
      parmsIb(26)  <= Usb2ByteType( to_unsigned( MAX_DGRAMS_OUT_G, 16   )( 7 downto  0) );
      parmsIb(27)  <= Usb2ByteType( to_unsigned( MAX_DGRAMS_OUT_G, 16   )(15 downto  8) );

      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_GET_NTB_PARAMETERS_C, HANDLE_REQUESTS_C ) ) then
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_GET_NET_ADDRESS_C   , HANDLE_REQUESTS_C ) ) then
         for i in r.macAddr'low to r.macAddr'high loop
            parmsIb(i) <= r.macAddr(i);
         end loop;
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_SET_NET_ADDRESS_C   , HANDLE_REQUESTS_C ) ) then
         for i in r.macAddr'low to r.macAddr'high loop
            v.macAddr(i) := parmsOb(i);
         end loop;
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_GET_NTB_INPUT_SIZE_C, HANDLE_REQUESTS_C ) ) then
         for i in 0 to 3 loop
            parmsIb(i) <= Usb2ByteType( r.maxNTBSizeInp(8*i + 7 downto 8*i) );
         end loop;
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_SET_NTB_INPUT_SIZE_C, HANDLE_REQUESTS_C ) ) then
         for i in 0 to 3 loop
            v.maxNTBSizeInp(8*i + 7 downto 8*i) := unsigned( parmsOb(i) );
         end loop;
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_SET_ETHERNET_PACKET_FILTER_C, HANDLE_REQUESTS_C ) ) then
         v.packetFilter := usb2Ep0ReqParam.value(v.packetFilter'range);
         ctlReqErr      <= '0';
      end if;
      if ( selected( ctlReqVld, USB2_REQ_CLS_CDC_SET_ETHERNET_MC_FILTERS_C, HANDLE_REQUESTS_C ) ) then
         mcFilterVld    <= '1';
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

   macAddress    <= r.macAddr;
   maxNTBSizeInp <= r.maxNTBSizeInp;
   packetFilter  <= r.packetFilter;

   G_MC_FILTER_STRM : if ( SUPPORT_SET_MC_FILT_G ) generate
      mcFilterDat   <= usb2EpGenericStrmDat( parmsOb );
      mcFilterLst   <= usb2EpGenericStrmLst( parmsOb );
      mcFilterDon   <= usb2EpGenericStrmDon( parmsOb );
   end generate G_MC_FILTER_STRM;

end architecture Impl;
