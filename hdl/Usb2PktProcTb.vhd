library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;
use     work.Usb2DescPkg.all;

package body Usb2AppCfgPkg is

   procedure pr(constant x: Usb2ByteArray) is
      variable s : string(1 to 8);
   begin
      for i in x'range loop
         for j in x(i)'left downto x(i)'right loop
            s(8-j) := std_logic'image(x(i)(j))(2);
         end loop;
         report "D[" & integer'image(i) & "]  => " & s;
      end loop;
   end procedure pr;

   function USB2_APP_DESCRIPTORS_F return Usb2ByteArray is

   constant DEVDESC_C : Usb2ByteArray := (
       0 => x"12",                                    -- length
       1 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_DEVICE_C),     -- type
       2 => x"00",  3 => x"02",                       -- USB version
       4 => x"FF",                                    -- dev class
       5 => x"FF",                                    -- dev subclass
       6 => x"00",                                    -- dev protocol
       7 => x"08",                                    -- max pkt size
       8 => x"23",  9 => x"01",                       -- vendor id
      10 => x"cd", 11 => x"ab",                       -- product id
      12 => x"01", 13 => x"00",                       -- device release
      14 => x"00",                                    -- man. string
      15 => x"00",                                    -- prod. string
      16 => x"00",                                    -- S/N string
      17 => x"01"                                     -- num configs
   );

   constant CONFDESC_C : Usb2ByteArray := (
       0 => x"09",                                    -- length
       1 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_CONFIGURATION_C), -- type
       2 => x"3E", 3 => x"00",                        -- total length
       4 => x"01",                                    -- num interfaces
       5 => x"01",                                    -- config value
       6 => x"00",                                    -- description string
       7 => x"00",                                    -- attributes
       8 => x"ff",                                    -- power

       9 => x"04", -- a dummy 'unknown' descriptor
      10 => x"00", 
      11 => x"00",
      12 => x"00",

      13 => x"09",                                    -- length
      14 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_INTERFACE_C), -- type
      15 => x"00",                                    -- interface number
      16 => x"00",                                    -- alt-setting
      17 => x"02",                                    -- num-endpoints
      18 => x"FF",                                    -- class
      19 => x"FF",                                    -- subclass
      20 => x"00",                                    -- protocol
      21 => x"00",                                    -- string desc

      22 => x"07", -- endpoint                           length
      23 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_ENDPOINT_C), -- type
      24 => x"01",                                    -- address (OUT EP1)
      25 => "000000" & USB2_TT_BULK_C,                -- attributes
      26 => x"00", 27 => x"00",                       -- maxPktSize
      28 => x"00",                                    -- interval

      29 => x"03", -- a dummy 'unknown' descriptor
      30 => x"00", 
      31 => x"00",

      32 => x"07", -- endpoint                           length
      33 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_ENDPOINT_C), -- type
      34 => x"81",                                    -- address (IN EP1)
      35 => "000000" & USB2_TT_BULK_C,                -- attributes
      36 => x"00", 37 => x"00",                       -- maxPktSize
      38 => x"00",                                    -- interval

      39 => x"09",                                    -- length
      40 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_INTERFACE_C), -- type
      41 => x"00",                                    -- interface number
      42 => x"01",                                    -- alt-setting
      43 => x"02",                                    -- num-endpoints
      44 => x"FF",                                    -- class
      45 => x"FF",                                    -- subclass
      46 => x"00",                                    -- protocol
      47 => x"00",                                    -- string desc

      48 => x"07", -- endpoint                           length
      49 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_ENDPOINT_C), -- type
      50 => x"01",                                    -- address (OUT EP1)
      51 => "000000" & USB2_TT_BULK_C,                -- attributes
      52 => x"08", 53 => x"00",                       -- maxPktSize *must match epCfg value below*
      54 => x"00",                                    -- interval

      55 => x"07", -- endpoint                           length
      56 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_ENDPOINT_C), -- type
      57 => x"81",                                    -- address (IN EP1)
      58 => "000000" & USB2_TT_BULK_C,                -- attributes
      59 => x"08", 60 => x"00",                       -- maxPktSize *must match epCfg value below*
      61 => x"00"                                     -- interval
   );


   constant TAILDESC_C : Usb2ByteArray := (
      0  => x"02", -- End of table marker
      1  => x"ff"  --
   );

   constant l : natural :=  DEVDESC_C'length + CONFDESC_C'length + TAILDESC_C'length;
   constant c : Usb2ByteArray(0 to l-1) := (DEVDESC_C & CONFDESC_C & TAILDESC_C);
   begin
   return c;
   end function;

end package body Usb2AppCfgPkg;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;
use     work.Usb2TstPkg.all;
use     work.Usb2AppCfgPkg.all;
use     work.Usb2DescPkg.all;

entity Usb2PktProcTb is
end entity Usb2PktProcTb;

architecture sim of Usb2PktProcTb is

   constant TST_EP_IDX_C           : natural := 1;
   constant TST_EP_C               : Usb2EndpIdxType := to_unsigned(TST_EP_IDX_C,Usb2EndpIdxType'length);

   constant DEV_ADDR_C             : Usb2DevAddrType := Usb2DevAddrType( to_unsigned(66, Usb2DevAddrType'length) );

   constant CONFIG_VALUE_C         : std_logic_vector(7 downto 0) := x"01";
   -- index is zero-based (?)
   constant CONFIG_INDEX_C         : std_logic_vector(7 downto 0) := x"00";
   constant CONFIG_BAD_VALUE_C     : std_logic_vector(7 downto 0) := x"02";

   constant NUM_ENDPOINTS_C        : natural                      := USB2_APP_NUM_ENDPOINTS_F(USB2_APP_DESCRIPTORS_C);

   constant ALT_C                  : std_logic_vector(15 downto 0) := x"0001";
   constant IFC_C                  : std_logic_vector(15 downto 0) := x"0000";
   
   signal epIb            : Usb2EndpPairIbArray(1 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb            : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_OB_INIT_C);

   signal txDataMst       : Usb2StrmMstType := USB2_STRM_MST_INIT_C;
   signal txDataSub       : Usb2StrmSubType := USB2_STRM_SUB_INIT_C;
   signal rxDataMst       : Usb2StrmMstType := USB2_STRM_MST_INIT_C;

   constant d1 : Usb2ByteArray := ( x"01", x"02", x"03" );
   constant d2 : Usb2ByteArray := (
      x"c7",
      x"3d",
      x"25",
      x"93",
      x"ba",
      x"bb",
      x"b3",
      x"5e",
      x"54",
      x"5a",
      x"ac",
      x"5a",
      x"6c",
      x"ee",
      x"00",
      x"ab"
   );

begin

   U_TST : entity work.Usb2TstPkgProcesses;

   P_TST : process is
      variable pid            : std_logic_vector(3 downto 0);
      variable reqval         : std_logic_vector(15 downto 0);
      variable reqidx         : std_logic_vector(15 downto 0);

      constant devdsc         : Usb2ByteArray(0 to 17) := USB2_APP_DESCRIPTORS_C(0  to 17);
      constant cfgdsc         : Usb2ByteArray          := USB2_APP_DESCRIPTORS_C(18 to USB2_APP_DESCRIPTORS_C'high - 2);
      variable epCfg          : Usb2TstEpCfgArray      := (others => USB2_TST_EP_CFG_INIT_C);

      constant EP0_SZ_C       : Usb2ByteType           := USB2_APP_DESCRIPTORS_F(USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C); 
      constant EP1_SZ_C       : Usb2ByteType           := x"08"; -- must match value in descriptor
   begin
      epCfg( to_integer( USB2_ENDP_ZERO_C ) ).maxPktSizeInp := to_integer(unsigned(EP0_SZ_C));
      epCfg( to_integer( USB2_ENDP_ZERO_C ) ).maxPktSizeOut := to_integer(unsigned(EP0_SZ_C));
      epCfg( TST_EP_IDX_C                   ).maxPktSizeInp := to_integer(unsigned(EP1_SZ_C));
      epCfg( TST_EP_IDX_C                   ).maxPktSizeOut := to_integer(unsigned(EP1_SZ_C));

      usb2TstPkgConfig( epCfg );

      ulpiClkTick; ulpiClkTick;

report "GET_CONFIG";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_CONFIGURATION_C, USB2_DEV_ADDR_DFLT_C, eda => (0=>x"00"));

report "GET_INTERFACE";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_INTERFACE_C, USB2_DEV_ADDR_DFLT_C, eda => (0=>x"00"), epid => USB2_PID_HSK_STALL_C);

report "SET_ADDRESS";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_ADDRESS_C, USB2_DEV_ADDR_DFLT_C, val => (x"00" & "0" & DEV_ADDR_C) );
report "SET_BAD_CONFIG";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_CONFIGURATION_C, DEV_ADDR_C, val => (x"00" & CONFIG_BAD_VALUE_C ), epid => USB2_PID_HSK_STALL_C);
report "SET_CONFIG";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_CONFIGURATION_C, DEV_ADDR_C, val => (x"00" & CONFIG_VALUE_C ) );
report "SET_INTERFACE";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_INTERFACE_C,     DEV_ADDR_C, val => ALT_C, idx => IFC_C );

report "GET_INTERFACE";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_INTERFACE_C, DEV_ADDR_C, idx => IFC_C, eda => (0 => x"01"));

report "GET_DESCRIPTOR(DEV)";
      reqval := "0000" & std_logic_vector(USB2_STD_DESC_TYPE_DEVICE_C) & x"00";
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => devdsc);

report "GET_DESCRIPTOR(CFG)";
      reqval := "0000" & std_logic_vector(USB2_STD_DESC_TYPE_CONFIGURATION_C) & CONFIG_INDEX_C;
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_GET_DESCRIPTOR_C, DEV_ADDR_C, val => reqval, eda => cfgdsc);
      ulpiClkTick;


      ulpiTstSendDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C);

      ulpiTstSendDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C, rtr=>2 );

      ulpiTstSendDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C, rtr=>2, w => 2 );

      -- read fragmented data
      ulpiTstWaitDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C );
      ulpiClkTick;

      -- read fragmented with retries
      ulpiTstWaitDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C, 2 );
      ulpiClkTick;

      -- read fragmented with retries and wait cycles
      ulpiTstWaitDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C, 2, 2 );
      ulpiClkTick;

      -- this happens to abort just after a complete frame is received
      ulpiTstWaitDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C, abrt => 4);
      ulpiClkTick;

      -- make sure ACK times out
      for i in 1 to 40 loop
         ulpiClkTick;
      end loop;

      ulpiTstWaitDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C );
      ulpiClkTick;

      ulpiTstWaitDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C, abrt => 1);
      ulpiClkTick;

      -- make sure ACK times out
      for i in 1 to 40 loop
         ulpiClkTick;
      end loop;

      ulpiTstWaitDat(ulpiTstOb, d2, TST_EP_C, DEV_ADDR_C );


      for i in 0 to 20 loop
         ulpiClkTick;
      end loop;
      ulpiTstRun <= false;
      report "TEST PASSED";
      wait;
   end process P_TST;

   U_DUT : entity work.Usb2Core
   generic map (
      SIMULATION_G                 => true,
      DESCRIPTORS_G                => USB2_APP_DESCRIPTORS_C
   )
   port map (
      clk                          => ulpiTstClk,

      ulpiRst                      => open,
      usb2Rst                      => open,

      ulpiDir                      => ulpiTstOb.dir,
      ulpiStp                      => ulpiTstIb.stp,
      ulpiNxt                      => ulpiTstOb.nxt,
      ulpiDat                      => ulpiDatIO,

      usb2DevStatus                => open,
      usb2PktHdr                   => open,

      usb2Ep0ReqParam              => open,
      usb2Ep0CtlExt                => open,
      usb2Ep0CtlEpExt              => open,

      usb2EpIb                     => epIb,
      usb2EpOb                     => epOb
   );

   P_EP_1  : process ( ulpiTstClk ) is
      function ini return Usb2EndpPairIbType is
         variable v : Usb2EndpPairIbType;
      begin
         v            := USB2_ENDP_PAIR_IB_INIT_C;
         v.mstInp.vld := '1';
         v.subOut.rdy := '1';
         return v;
      end function ini;

      variable iidx : integer            := 0;
      variable oidx : integer            := 0;
      variable ep   : Usb2EndpPairIbType := ini;
   begin
      if ( rising_edge( ulpiTstClk ) ) then
         if ( epOb(TST_EP_IDX_C).subInp.rdy = '1' ) then
            if ( ep.mstInp.vld = '1' ) then
               if ( iidx = d2'high ) then
                  ep.mstInp.vld := '0';
                  iidx          :=  0 ;
                  ep.mstInp.don := '1';
                  ep.mstInp.err := '0';
               else
                  iidx          := iidx + 1;
               end if;
            elsif ( ep.mstInp.don = '1' ) then
               ep.mstInp.don := '0';
               ep.mstInp.vld := '1';
            end if;
         end if;
         if ( epOb(TST_EP_IDX_C).mstOut.vld = '1' ) then
            assert epOb(TST_EP_IDX_C).mstOut.dat = d2(oidx) report "OUT 0 endpoint data mismatch" severity failure;
            oidx := oidx + 1;
         elsif ( epOb(TST_EP_IDX_C).mstOut.don = '1' ) then
            oidx          := 0;
         end if;
         epIb(TST_EP_IDX_C)            <= ep;
         epIb(TST_EP_IDX_C).mstInp.dat <= d2(iidx);
      end if;
   end process P_EP_1;

end architecture sim;
