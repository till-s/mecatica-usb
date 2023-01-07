-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
-- Date        : Wed Sep  7 10:37:08 2022
-- Host        : running 64-bit Ubuntu 20.04.5 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               sources_1/ip/processing_system7_0/processing_system7_0_stub.vhdl
-- Design      : processing_system7_0, axi_protocol_converter
-- Purpose     : Stub declaration of top-level module interface
-- Device      : zynq7000
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package Ps7Pkg is

   COMPONENT processing_system7_0
      PORT (
         ENET0_PTP_DELAY_REQ_RX : OUT STD_LOGIC;
         ENET0_PTP_DELAY_REQ_TX : OUT STD_LOGIC;
         ENET0_PTP_PDELAY_REQ_RX : OUT STD_LOGIC;
         ENET0_PTP_PDELAY_REQ_TX : OUT STD_LOGIC;
         ENET0_PTP_PDELAY_RESP_RX : OUT STD_LOGIC;
         ENET0_PTP_PDELAY_RESP_TX : OUT STD_LOGIC;
         ENET0_PTP_SYNC_FRAME_RX : OUT STD_LOGIC;
         ENET0_PTP_SYNC_FRAME_TX : OUT STD_LOGIC;
         ENET0_SOF_RX : OUT STD_LOGIC;
         ENET0_SOF_TX : OUT STD_LOGIC;
         GPIO_I : IN STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
         GPIO_O : OUT STD_LOGIC_VECTOR(31 downto 0);
         GPIO_T : OUT STD_LOGIC_VECTOR(31 downto 0);
         I2C0_SDA_I : IN STD_LOGIC := '0';
         I2C0_SDA_O : OUT STD_LOGIC;
         I2C0_SDA_T : OUT STD_LOGIC;
         I2C0_SCL_I : IN STD_LOGIC := '0';
         I2C0_SCL_O : OUT STD_LOGIC;
         I2C0_SCL_T : OUT STD_LOGIC;
         SDIO0_WP : IN STD_LOGIC := '0';
         USB0_PORT_INDCTL : OUT STD_LOGIC_VECTOR(1 downto 0);
         USB0_VBUS_PWRSELECT : OUT STD_LOGIC;
         USB0_VBUS_PWRFAULT : IN STD_LOGIC := '0';
         M_AXI_GP0_ARVALID : OUT STD_LOGIC;
         M_AXI_GP0_AWVALID : OUT STD_LOGIC;
         M_AXI_GP0_BREADY : OUT STD_LOGIC;
         M_AXI_GP0_RREADY : OUT STD_LOGIC;
         M_AXI_GP0_WLAST : OUT STD_LOGIC;
         M_AXI_GP0_WVALID : OUT STD_LOGIC;
         M_AXI_GP0_ARID : OUT STD_LOGIC_VECTOR(11 downto 0);
         M_AXI_GP0_AWID : OUT STD_LOGIC_VECTOR(11 downto 0);
         M_AXI_GP0_WID : OUT STD_LOGIC_VECTOR(11 downto 0);
         M_AXI_GP0_ARBURST : OUT STD_LOGIC_VECTOR(1 downto 0);
         M_AXI_GP0_ARLOCK : OUT STD_LOGIC_VECTOR(1 downto 0);
         M_AXI_GP0_ARSIZE : OUT STD_LOGIC_VECTOR(2 downto 0);
         M_AXI_GP0_AWBURST : OUT STD_LOGIC_VECTOR(1 downto 0);
         M_AXI_GP0_AWLOCK : OUT STD_LOGIC_VECTOR(1 downto 0);
         M_AXI_GP0_AWSIZE : OUT STD_LOGIC_VECTOR(2 downto 0);
         M_AXI_GP0_ARPROT : OUT STD_LOGIC_VECTOR(2 downto 0);
         M_AXI_GP0_AWPROT : OUT STD_LOGIC_VECTOR(2 downto 0);
         M_AXI_GP0_ARADDR : OUT STD_LOGIC_VECTOR(31 downto 0);
         M_AXI_GP0_AWADDR : OUT STD_LOGIC_VECTOR(31 downto 0);
         M_AXI_GP0_WDATA : OUT STD_LOGIC_VECTOR(31 downto 0);
         M_AXI_GP0_ARCACHE : OUT STD_LOGIC_VECTOR(3 downto 0);
         M_AXI_GP0_ARLEN : OUT STD_LOGIC_VECTOR(3 downto 0);
         M_AXI_GP0_ARQOS : OUT STD_LOGIC_VECTOR(3 downto 0);
         M_AXI_GP0_AWCACHE : OUT STD_LOGIC_VECTOR(3 downto 0);
         M_AXI_GP0_AWLEN : OUT STD_LOGIC_VECTOR(3 downto 0);
         M_AXI_GP0_AWQOS : OUT STD_LOGIC_VECTOR(3 downto 0);
         M_AXI_GP0_WSTRB : OUT STD_LOGIC_VECTOR(3 downto 0);
         M_AXI_GP0_ACLK : IN STD_LOGIC;
         M_AXI_GP0_ARREADY : IN STD_LOGIC;
         M_AXI_GP0_AWREADY : IN STD_LOGIC;
         M_AXI_GP0_BVALID : IN STD_LOGIC;
         M_AXI_GP0_RLAST : IN STD_LOGIC;
         M_AXI_GP0_RVALID : IN STD_LOGIC;
         M_AXI_GP0_WREADY : IN STD_LOGIC;
         M_AXI_GP0_BID : IN STD_LOGIC_VECTOR(11 downto 0);
         M_AXI_GP0_RID : IN STD_LOGIC_VECTOR(11 downto 0);
         M_AXI_GP0_BRESP : IN STD_LOGIC_VECTOR(1 downto 0);
         M_AXI_GP0_RRESP : IN STD_LOGIC_VECTOR(1 downto 0);
         M_AXI_GP0_RDATA : IN STD_LOGIC_VECTOR(31 downto 0);
         IRQ_F2P : IN STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
         FCLK_CLK0 : OUT STD_LOGIC;
         FCLK_RESET0_N : OUT STD_LOGIC;
         MIO : INOUT STD_LOGIC_VECTOR(53 downto 0);
         DDR_CAS_n : INOUT STD_LOGIC;
         DDR_CKE : INOUT STD_LOGIC;
         DDR_Clk_n : INOUT STD_LOGIC;
         DDR_Clk : INOUT STD_LOGIC;
         DDR_CS_n : INOUT STD_LOGIC;
         DDR_DRSTB : INOUT STD_LOGIC;
         DDR_ODT : INOUT STD_LOGIC;
         DDR_RAS_n : INOUT STD_LOGIC;
         DDR_WEB : INOUT STD_LOGIC;
         DDR_BankAddr : INOUT STD_LOGIC_VECTOR(2 downto 0);
         DDR_Addr : INOUT STD_LOGIC_VECTOR(14 downto 0);
         DDR_VRN : INOUT STD_LOGIC;
         DDR_VRP : INOUT STD_LOGIC;
         DDR_DM : INOUT STD_LOGIC_VECTOR(3 downto 0);
         DDR_DQ : INOUT STD_LOGIC_VECTOR(31 downto 0);
         DDR_DQS_n : INOUT STD_LOGIC_VECTOR(3 downto 0);
         DDR_DQS : INOUT STD_LOGIC_VECTOR(3 downto 0);
         PS_SRSTB : INOUT STD_LOGIC;
         PS_CLK : INOUT STD_LOGIC;
         PS_PORB : INOUT STD_LOGIC
      );
   END COMPONENT processing_system7_0;

   COMPONENT axi2axil_converter_0
      PORT (
         aclk : IN STD_LOGIC;
         aresetn : IN STD_LOGIC;
         s_axi_awid : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
         s_axi_awaddr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
         s_axi_awlen : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
         s_axi_awsize : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
         s_axi_awburst : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
         s_axi_awlock : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
         s_axi_awcache : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
         s_axi_awprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
         s_axi_awqos : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
         s_axi_awvalid : IN STD_LOGIC;
         s_axi_awready : OUT STD_LOGIC;
         s_axi_wid : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
         s_axi_wdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
         s_axi_wstrb : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
         s_axi_wlast : IN STD_LOGIC;
         s_axi_wvalid : IN STD_LOGIC;
         s_axi_wready : OUT STD_LOGIC;
         s_axi_bid : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
         s_axi_bresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
         s_axi_bvalid : OUT STD_LOGIC;
         s_axi_bready : IN STD_LOGIC;
         s_axi_arid : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
         s_axi_araddr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
         s_axi_arlen : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
         s_axi_arsize : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
         s_axi_arburst : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
         s_axi_arlock : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
         s_axi_arcache : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
         s_axi_arprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
         s_axi_arqos : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
         s_axi_arvalid : IN STD_LOGIC;
         s_axi_arready : OUT STD_LOGIC;
         s_axi_rid : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
         s_axi_rdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
         s_axi_rresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
         s_axi_rlast : OUT STD_LOGIC;
         s_axi_rvalid : OUT STD_LOGIC;
         s_axi_rready : IN STD_LOGIC;
         m_axi_awaddr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
         m_axi_awprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
         m_axi_awvalid : OUT STD_LOGIC;
         m_axi_awready : IN STD_LOGIC;
         m_axi_wdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
         m_axi_wstrb : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
         m_axi_wvalid : OUT STD_LOGIC;
         m_axi_wready : IN STD_LOGIC;
         m_axi_bresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
         m_axi_bvalid : IN STD_LOGIC;
         m_axi_bready : OUT STD_LOGIC;
         m_axi_araddr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
         m_axi_arprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
         m_axi_arvalid : OUT STD_LOGIC;
         m_axi_arready : IN STD_LOGIC;
         m_axi_rdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
         m_axi_rresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
         m_axi_rvalid : IN STD_LOGIC;
         m_axi_rready : OUT STD_LOGIC
      );
   END COMPONENT;

   -- Note: PS7 has a AXI3 interface, apparently

   type AxiReadMstType is record
      araddr   : std_logic_vector(31 downto 0);
      arburst  : std_logic_vector( 1 downto 0);
      arcache  : std_logic_vector( 3 downto 0);
      arid     : std_logic_vector(11 downto 0);
      arlen    : std_logic_vector( 3 downto 0);
      arlock   : std_logic_vector( 1 downto 0);
      arprot   : std_logic_vector( 2 downto 0);
      arqos    : std_logic_vector( 3 downto 0);
      arsize   : std_logic_vector( 2 downto 0);
      arvalid  : std_logic;
      rready   : std_logic;
   end record AxiReadMstType;

   type AxiReadSubType is record
      arready  : std_logic;
      rdata    : std_logic_vector(31 downto 0);
      rid      : std_logic_vector(11 downto 0);
      rresp    : std_logic_vector( 1 downto 0);
      rlast    : std_logic;
      rvalid   : std_logic;
   end record AxiReadSubType;

   constant AXI_READ_SUB_INIT_C : AxiReadSubType := (
      arready  => '0',
      rdata    => (others => '0'),
      rid      => (others => '0'),
      rresp    => (others => '0'),
      rlast    => '0',
      rvalid   => '0'
   );

   constant AXI_READ_SUB_FORCE_C : AxiReadSubType := (
      arready  => '1',
      rdata    => (others => '0'),
      rid      => (others => '0'),
      rresp    => (others => '1'),
      rlast    => '1',
      rvalid   => '1'
   );

   type AxiWriteMstType is record
      awaddr   : std_logic_vector(31 downto 0);
      awburst  : std_logic_vector( 1 downto 0);
      awcache  : std_logic_vector( 3 downto 0);
      awid     : std_logic_vector(11 downto 0);
      awlen    : std_logic_vector( 3 downto 0);
      awlock   : std_logic_vector( 1 downto 0);
      awprot   : std_logic_vector( 2 downto 0);
      awqos    : std_logic_vector( 3 downto 0);
      awsize   : std_logic_vector( 2 downto 0);
      awvalid  : std_logic;

      wdata    : std_logic_vector(31 downto 0);
      wid      : std_logic_vector(11 downto 0);
      wstrb    : std_logic_vector( 3 downto 0);
      wlast    : std_logic;
      wvalid   : std_logic;
      
      bready   : std_logic;
   end record AxiWriteMstType;

   type AxiWriteSubType is record
      awready  : std_logic;
      wready   : std_logic;
      bready   : std_logic;
      bid      : std_logic_vector(11 downto 0);
      bresp    : std_logic_vector( 1 downto 0);
      bvalid   : std_logic;
   end record AxiWriteSubType;

   constant AXI_WRITE_SUB_INIT_C : AxiWriteSubType := (
      awready  => '0',
      wready   => '0',
      bready   => '0',
      bid      => (others => '0'),
      bresp    => (others => '0'),
      bvalid   => '0'
   );

   constant AXI_WRITE_SUB_FORCE_C : AxiWriteSubType := (
      awready  => '1',
      wready   => '1',
      bready   => '1',
      bid      => (others => '0'),
      bresp    => (others => '1'),
      bvalid   => '1'
   );

end package Ps7Pkg;
