-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

package FifoEpTstParmPkg is
   constant IFC_NUM_C : natural := 0;
end package FifoEpTstParmPkg;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;
use     work.FifoEpTstParmPkg.all;

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
      41 => std_logic_vector(to_unsigned(IFC_NUM_C,8)), -- interface number
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
      52 => x"08", 53 => x"00",                       -- maxPktSize
      54 => x"00",                                    -- interval

      55 => x"07", -- endpoint                           length
      56 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_ENDPOINT_C), -- type
      57 => x"81",                                    -- address (IN EP1)
      58 => "000000" & USB2_TT_BULK_C,                -- attributes
      59 => x"08", 60 => x"00",                       -- maxPktSize
      61 => x"00"                                     -- interval
   );

   constant STRS_C : Usb2ByteArray := (
       0 => x"04",                                    -- length
       1 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_STRING_C), -- type
       2 => USB2_LANGID_EN_US_C( 7 downto 0),
       3 => USB2_LANGID_EN_US_C(15 downto 8),

       4 => x"06",
       5 => std_logic_vector(x"0" & USB2_STD_DESC_TYPE_STRING_C), -- type
       6 => x"54",
       7 => x"00",
       8 => x"55",
       9 => x"00"
   );

   constant TAILDESC_C : Usb2ByteArray := (
      0  => x"02", -- End of table marker
      1  => x"ff"  --
   );

   constant l : natural :=  DEVDESC_C'length + CONFDESC_C'length + STRS_C'length + TAILDESC_C'length;
   constant c : Usb2ByteArray(0 to l-1) := (DEVDESC_C & CONFDESC_C & STRS_C & TAILDESC_C);
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
use     work.Usb2UtilPkg.all;
use     work.Usb2TstPkg.all;
use     work.Usb2AppCfgPkg.all;
use     work.Usb2DescPkg.all;
use     work.FifoEpTstParmPkg.all;

entity Usb2FifoEpTb is
end entity Usb2FifoEpTb;

architecture sim of Usb2FifoEpTb is

   constant TST_EP_IDX_C           : natural := 1;
   constant TST_EP_C               : Usb2EndpIdxType := to_unsigned(TST_EP_IDX_C,Usb2EndpIdxType'length);

   constant DEV_ADDR_C             : Usb2DevAddrType := Usb2DevAddrType( to_unsigned(66, Usb2DevAddrType'length) );

   constant CONFIG_VALUE_C         : std_logic_vector(7 downto 0) := x"01";
   -- index is zero-based (?)
   constant CONFIG_INDEX_C         : std_logic_vector(7 downto 0) := x"00";
   constant CONFIG_BAD_VALUE_C     : std_logic_vector(7 downto 0) := x"02";

   constant NUM_ENDPOINTS_C        : natural                      := USB2_APP_NUM_ENDPOINTS_F(USB2_APP_DESCRIPTORS_C);

   constant EP0_SZ_C               : Usb2ByteType           := USB2_APP_DESCRIPTORS_F(USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C); 
   constant EP1_SZ_C               : natural                := 8; -- must match value in descriptor
   constant EP1                    : Usb2EndpIdxType        := x"1";

   constant ALT_C                  : std_logic_vector(15 downto 0) := x"0001";
   constant IFC_C                  : std_logic_vector(15 downto 0) := x"0000";
   
   signal epIb                     : Usb2EndpPairIbArray(1 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb                     : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1)     := (others => USB2_ENDP_PAIR_OB_INIT_C);

   signal devStatus                : Usb2DevStatusType;
   signal usb2Rx                   : Usb2RxType;
   signal lineBreak                : std_logic;
   signal DTR                      : std_logic := '0';
   signal RTS                      : std_logic := '0';
   signal rate                     : unsigned(31 downto 0) := (others => '0');
   signal stopBits                 : unsigned( 1 downto 0) := (others => '0');
   signal parity                   : unsigned( 2 downto 0) := (others => '0');
   signal dataBits                 : unsigned( 4 downto 0) := (others => '0');


   signal ep0ReqParam              : Usb2CtlReqParamType;
   signal ep0CtlExt                : Usb2CtlExtType;
   signal cdcacmCtlEpIb            : Usb2EndpPairIbType;

   signal fifoDatInp               : Usb2ByteType := (others => 'U');
   signal fifoDatOut               : Usb2ByteType;
   signal fifoWenInp               : std_logic    := '0';
   signal fifoFullInp              : std_logic;
   signal fifoRenOut               : std_logic    := '0';
   signal fifoEmptyOut             : std_logic;

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

   constant REQ_TYP_CLS_IFC_R_C : Usb2ByteType := x"a1";
   constant REQ_TYP_CLS_IFC_W_C : Usb2ByteType := x"21";

begin

   U_TST : entity work.Usb2TstPkgProcesses;

   P_TST : process is
      variable idx            : natural;
   begin

      ulpiClkTick; ulpiClkTick;

      ulpiTstHandlePhyInit( ulpiTstOb );

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_ADDRESS_C, USB2_DEV_ADDR_DFLT_C, val => (x"00" & "0" & DEV_ADDR_C) );
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_CONFIGURATION_C, DEV_ADDR_C,     val => (x"00" & CONFIG_VALUE_C ) );
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_STD_SET_INTERFACE_C,     DEV_ADDR_C, val => ALT_C, idx => IFC_C );
      -- pass current configuration to test package
      usb2TstPkgConfig( epOb );

      ulpiTstSendDat(ulpiTstOb, d2, EP1, DEV_ADDR_C, fram => false);
      ulpiTstSendDat(ulpiTstOb, d2(0 to 0), EP1, DEV_ADDR_C, fram => false, epid => USB2_PID_HSK_NAK_C);

      idx := 0;
      fifoRenOut <= '1';
      ulpiClkTick;
      while ( fifoEmptyOut = '0' ) loop
         assert d2(idx) = fifoDatOut report "OUT fifo mismatch" severity failure;
         idx := idx + 1; 
         ulpiClkTick;
      end loop;
      fifoRenOut <= '0';
      ulpiClkTick;
      assert idx = d2'length report "OUT fifo - not all elements read" severity failure;

      -- must resend NAKed data!
      ulpiTstSendDat(ulpiTstOb, d2(0 to 0), EP1, DEV_ADDR_C, fram => false);
      ulpiTstSendDat(ulpiTstOb, d2(1 to 12), EP1, DEV_ADDR_C, fram => false);

      ulpiClkTick;

      idx := 0;
      while ( fifoFullInp = '0' ) loop
         fifoRenOut <= '1';
         ulpiClkTick;
         fifoDatInp <= fifoDatOut;
         fifoWenInp <= '1';
         fifoRenOut <= '0';
         idx := idx + 1;
         ulpiClkTick;
         fifoWenInp <= '0';
         ulpiClkTick;
      end loop;
      ulpiClkTick;

      ulpiTstWaitDat(ulpiTstOb, d2(0 to 9), EP1, DEV_ADDR_C, nofr => true);

      L_CPY : while ( (fifoEmptyOut or fifoFullInp) = '0' ) loop
         fifoRenOut <= '1';
         ulpiClkTick;
         fifoDatInp <= fifoDatOut;
         fifoWenInp <= '1';
         fifoRenOut <= '0';
         idx := idx + 1;
         ulpiClkTick;
         fifoWenInp <= '0';
         ulpiClkTick;
      end loop;
      ulpiClkTick;

      ulpiTstWaitDat(ulpiTstOb, d2(10 to 12), EP1, DEV_ADDR_C, nofr => true);

      assert lineBreak = '0' report "line-break initially not 0" severity failure;
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_CLS_CDC_SEND_BREAK_C, DEV_ADDR_C, typ => REQ_TYP_CLS_IFC_W_C, val => x"ffff");
      assert lineBreak = '1' report "line-break not 1" severity failure;
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_CLS_CDC_SEND_BREAK_C, DEV_ADDR_C, typ => REQ_TYP_CLS_IFC_W_C, val => x"0000");
      assert lineBreak = '0' report "line-break not reset to 0" severity failure;
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_CLS_CDC_SEND_BREAK_C, DEV_ADDR_C, typ => REQ_TYP_CLS_IFC_W_C, val => x"0001");
      assert lineBreak = '1' report "line-break not 1 (2nd time)" severity failure;
      ulpiTstSendTok(ulpiTstOb, USB2_PID_TOK_SOF_C, "0000", "0000000" );
      -- 1 frame time = 'at least' 1 frame...
      ulpiTstSendTok(ulpiTstOb, USB2_PID_TOK_SOF_C, "0000", "0000000" );

      for i in 0 to 10 loop
         ulpiClkTick;
      end loop;
      assert lineBreak = '0' report "line-break not 0 (2nd time)" severity failure;

      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_CLS_CDC_SET_CONTROL_LINE_STATE_C, DEV_ADDR_C, typ => REQ_TYP_CLS_IFC_W_C, val => x"0001");
      ulpiClkTick;
      assert RTS = '0' and DTR = '1' report "Expected DTR (only) asserted" severity failure;
      ulpiTstSendCtlReq(ulpiTstOb, USB2_REQ_CLS_CDC_SET_CONTROL_LINE_STATE_C, DEV_ADDR_C, typ => REQ_TYP_CLS_IFC_W_C, val => x"0002");
      ulpiClkTick;
      assert RTS = '1' and DTR = '0' report "Expected RTS (only) asserted" severity failure;

      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_CLS_CDC_SET_LINE_CODING_C,
         DEV_ADDR_C,
         typ  => REQ_TYP_CLS_IFC_W_C,
         eda  => (x"aa",x"bb",x"cc",x"dd",x"01",x"02",x"03"),
         timo => 100
      );

      ulpiClkTick;

      assert rate       = x"ddccbbaa" report "Unexpected line rate" severity failure;
      assert stopBits   = "01"        report "Unexpected stop bits" severity failure;
      assert parity     = "010"       report "Unexpected parity"    severity failure;
      assert dataBits   = "00011"     report "Unexpected data bits" severity failure;

      ulpiClkTick;

      ulpiTstSendCtlReq(
         ulpiTstOb,
         USB2_REQ_CLS_CDC_GET_LINE_CODING_C,
         DEV_ADDR_C,
         typ  => REQ_TYP_CLS_IFC_R_C,
         eda  => (x"aa",x"bb",x"cc",x"dd",x"01",x"02",x"03"),
         timo => 100
      );


      for i in 0 to 20 loop
         ulpiClkTick;
      end loop;
      ulpiTstRun <= false;
      report "TEST PASSED";
      wait;
   end process P_TST;

   U_CORE : entity work.Usb2Core
   generic map (
      SIMULATION_G                 => true,
      DESCRIPTORS_G                => USB2_APP_DESCRIPTORS_C
   )
   port map (
      clk                          => ulpiTstClk,

      ulpiRst                      => open,
      usb2Rst                      => open,

      ulpiIb                       => ulpiTstOb,
      ulpiOb                       => ulpiTstIb,

      usb2DevStatus                => devStatus,
      usb2Rx                       => usb2Rx,

      usb2Ep0ReqParam              => ep0ReqParam,
      usb2Ep0CtlExt                => ep0CtlExt,
      usb2Ep0CtlEpIbExt            => cdcacmCtlEpIb,

      usb2EpIb                     => epIb,
      usb2EpOb                     => epOb
   );

   U_DUT : entity work.Usb2FifoEp
      generic map (
         LD_FIFO_DEPTH_INP_G       => ulpiTstNumBits( EP1_SZ_C - 1 ),
         -- for high-bandwidth throughput the fifo depth must be >= 2*MAX_PKT_SIZE_OUT_G
         -- because at the time a packet is released into the fifo there must already
         -- a decision be made if a second packet would fit.
         LD_FIFO_DEPTH_OUT_G       => (1 + ulpiTstNumBits( EP1_SZ_C - 1 )),
         TIMER_WIDTH_G             => 1,
         -- add an output register to the INP bound FIFO (to improve timing)
         OUT_REG_INP_G             => true,
         -- add an output register to the OUT bound FIFO (to improve timing)
         OUT_REG_OUT_G             => true
      )
      port map (
         usb2Clk                   => ulpiTstClk,
         usb2Rst                   => open,

         minFillInp                => open,
         timeFillInp               => open,

         usb2EpOb                  => epIb(TST_EP_IDX_C),
         usb2EpIb                  => epOb(TST_EP_IDX_C),

         epClk                     => ulpiTstClk,
         epRstOut                  => open,

         datInp                    => fifoDatInp,
         wenInp                    => fifoWenInp,
         filledInp                 => open,
         fullInp                   => fifoFullInp,

         datOut                    => fifoDatOut,
         renOut                    => fifoRenOut,
         filledOut                 => open,
         emptyOut                  => fifoEmptyOut
      );

   U_BRK : entity work.CDCACMCtl
      generic map (
         CDC_IFC_NUM_G  => toUsb2InterfaceNumType(IFC_NUM_C),
         SUPPORT_LINE_G => true
      )
      port map (
         clk                       => ulpiTstClk,
         rst                       => open,

         usb2SOF                   => usb2rx.pktHdr.sof,
         usb2Ep0ReqParam           => ep0ReqParam,
         usb2Ep0CtlExt             => ep0CtlExt,
         usb2Ep0ObExt              => cdcacmCtlEpIb,
         usb2Ep0IbExt              => epOb(0),
         lineBreak                 => lineBreak,
         DTR                       => DTR,
         RTS                       => RTS,
         rate                      => rate,
         stopBits                  => stopBits,
         parity                    => parity,
         dataBits                  => dataBits

      );

end architecture sim;
