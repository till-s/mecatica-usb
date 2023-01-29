-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Top-level module for ZYNQ instantiating the example CDC ACM device.
-- It is assumed that the boot-loader or OS initializes the PS
-- to match the IP configuration.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.StdLogPkg.all;
use work.Ps7Pkg.all;
use work.UlpiPkg.all;
use work.Usb2Pkg.all;

entity ZynqTop is
   generic (
      -- ulpi 'INPUT clock mode is when the link generates the clock'
      -- NOTE: constraints matching the clock configuration have to be applied
      ULPI_CLK_MODE_INP_G : integer := 1
   );
   port (
      ethClk            : in    std_logic;
      DDR_addr          : inout STD_LOGIC_VECTOR ( 14 downto 0 );
      DDR_ba            : inout STD_LOGIC_VECTOR (  2 downto 0 );
      DDR_cas_n         : inout STD_LOGIC;
      DDR_ck_n          : inout STD_LOGIC;
      DDR_ck_p          : inout STD_LOGIC;
      DDR_cke           : inout STD_LOGIC;
      DDR_cs_n          : inout STD_LOGIC;
      DDR_dm            : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_dq            : inout STD_LOGIC_VECTOR ( 31 downto 0 );
      DDR_dqs_n         : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_dqs_p         : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_odt           : inout STD_LOGIC;
      DDR_ras_n         : inout STD_LOGIC;
      DDR_reset_n       : inout STD_LOGIC;
      DDR_we_n          : inout STD_LOGIC;
      FIXED_IO_ddr_vrn  : inout STD_LOGIC;
      FIXED_IO_ddr_vrp  : inout STD_LOGIC;
      FIXED_IO_mio      : inout STD_LOGIC_VECTOR ( 53 downto 0 );
      FIXED_IO_ps_clk   : inout STD_LOGIC;
      FIXED_IO_ps_porb  : inout STD_LOGIC;
      FIXED_IO_ps_srstb : inout STD_LOGIC;

      ulpiStp           : inout std_logic;
      ulpiRstb          : out   std_logic;
      ulpiDir           : in    std_logic;
      ulpiClk           : inout std_logic;
      ulpiNxt           : in    std_logic;
      ulpiDat           : inout std_logic_vector(7 downto 0);

      i2c0SDA           : inout std_logic;
      i2c0SCL           : inout std_logic;

      i2sBCLK           : in    std_logic;
      i2sPBLRC          : in    std_logic;
      i2sPBDAT          : out   std_logic;
      i2sMUTEb          : out   std_logic := '1';

      SW                : in    std_logic_vector(3 downto 0);

      LED               : out   std_logic_vector(3 downto 0) := (others => '0')
   );
end ZynqTop;

architecture top_level of ZynqTop is

   attribute IO_BUFFER_TYPE              : string;
   attribute ASYNC_REG                   : string;

   function  ite(constant c: boolean; constant a,b: integer) return integer is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;

   function  ite(constant c: boolean; constant a,b: real   ) return real    is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;

   constant  GEN_ULPI_C                  : boolean := true;

   constant  USE_ETH_CLK_C               : boolean := false;

   constant  ULPI_CLK_MODE_INP_C         : boolean := (ULPI_CLK_MODE_INP_G /= 0);

   -- must cover all registers
   constant  ADDR_WIDTH_C                : natural := 8;

   constant SYS_CLK_PERIOD_NS_C          : real     := ite( USE_ETH_CLK_C,  8.0 , 10.0);
   constant CLK_MULT_F_C                 : real     := ite( USE_ETH_CLK_C, 48.0 , 12.0);
   constant CLK0_DIV_C                   : positive := ite( USE_ETH_CLK_C, 20   , 20  );
   constant CLK2_DIV_C                   : positive := ite( USE_ETH_CLK_C,  6   ,  6  );
   constant REF_CLK_DIV_C                : positive := ite( USE_ETH_CLK_C,  5   ,  1  );

   constant N_RO_REGS_C                  : natural := 2;
   constant N_RW_REGS_C                  : natural := 4;

   signal axiReadMst                     : AxiReadMstType;
   signal axiReadSub                     : AxiReadSubType  := AXI_READ_SUB_FORCE_C;
   signal axiWriteMst                    : AxiWriteMstType;
   signal axiWriteSub                    : AxiWriteSubType := AXI_WRITE_SUB_FORCE_C;

   signal axilReadMst                    : AxiReadMstType;
   signal axilReadSub                    : AxiReadSubType  := AXI_READ_SUB_FORCE_C;
   signal axilWriteMst                   : AxiWriteMstType;
   signal axilWriteSub                   : AxiWriteSubType := AXI_WRITE_SUB_FORCE_C;

   signal regReq                         : UlpiRegReqType;
   signal regRep                         : UlpiRegRepType;

   signal cpuIrqs                        : std_logic_vector(15 downto 0) := (others => '0');

   signal ledLoc                         : std_logic_vector(3 downto 0) := (others => '0');
   signal ctl                            : std_logic_vector(7 downto 0) := (others => '0');

   signal lineBreak                      : std_logic;

   signal plClk                          : std_logic;
   signal sysRst, sysRstN                : std_logic;
   signal ulpiClkLoc                     : std_logic;
   signal ulpiRst                        : std_logic := '1';
   signal refLocked                      : std_logic;
   signal refLockedSync                  : std_logic_vector(1 downto 0) := (others => '0');
   attribute ASYNC_REG of refLockedSync  : signal is "TRUE";

   signal axiClk                         : std_logic;
   signal axiRst                         : std_logic;

   signal roRegs                         : Slv32Array(0 to N_RO_REGS_C - 1) := ( others => (others => '0') );

   signal fifoOutDat                     : Usb2ByteType;
   signal fifoInpDat                     : Usb2ByteType;
   signal fifoOutEmpty                   : std_logic;
   signal fifoInpFull                    : std_logic;
   signal fifoOutRen                     : std_logic;
   signal fifoInpWen                     : std_logic;

   -- USB3340 requires reset to be asserted for min. 1us; UlpiLineState subsequently waits until DIR is deasserted
   signal ulpiRstCnt                     : unsigned(7 downto 0) := (others => '1');

   signal i2c0Sda_i                      : std_logic;
   signal i2c0Sda_o                      : std_logic;
   signal i2c0Sda_t                      : std_logic;
   signal i2c0Scl_i                      : std_logic;
   signal i2c0Scl_o                      : std_logic;
   signal i2c0Scl_t                      : std_logic;

   signal refClkNb                       : std_logic;

   signal i2sBCLKLoc                     : std_logic;
   signal i2sBlinkCnt                    : unsigned(24 downto 0) := (others => '0');
   signal i2sBlink                       : std_logic := '1';
   signal acmIrq                         : std_logic;

begin

   B_BUF_BCLK : BUFG port map ( I => i2sBCLK, O => i2sBCLKLoc );

   P_BLNK : process ( i2sBCLKLoc ) is
   begin
      if ( rising_edge( i2sBCLKLoc ) ) then
         if ( i2sBlinkCnt(i2sBlinkCnt'left) = '1' ) then
            i2sBlink    <= not i2sBlink;
            i2sBlinkCnt <= to_unsigned( 48000*48 / 2, i2sBlinkCnt'length ) - 1;
         else
            i2sBlinkCnt <= i2sBlinkCnt - 1;
         end if;
      end if;
   end process P_BLNK;

   G_ETH_CLK: if ( USE_ETH_CLK_C ) generate
      signal initCnt : unsigned (10 downto 0) := (others => '1');
      signal sysClk  : std_logic;
   begin

      refClkNb <= ethClk;

      U_ETH_BUFG : component BUFG
         port map (
            I => ethClk,
            O => sysClk
         );

      P_RST : process ( sysClk ) is
      begin
         if ( rising_edge( sysClk ) ) then
            if ( sysRst = '1' ) then
               initCnt <= initCnt - 1;
            end if;
         end if;
      end process P_RST;

      sysRst <= initCnt(initCnt'left);
   end generate G_ETH_CLK;

   G_FPGA_CLK: if ( not USE_ETH_CLK_C ) generate
      sysRst   <= not sysRstN;
      refClkNb <= plClk;
   end generate G_FPGA_CLK;

   U_Sys : component processing_system7_0
      port map (
         DDR_Addr(14 downto 0)         => DDR_addr(14 downto 0),
         DDR_BankAddr(2 downto 0)      => DDR_ba(2 downto 0),
         DDR_CAS_n                     => DDR_cas_n,
         DDR_CKE                       => DDR_cke,
         DDR_CS_n                      => DDR_cs_n,
         DDR_Clk                       => DDR_ck_p,
         DDR_Clk_n                     => DDR_ck_n,
         DDR_DM(3 downto 0)            => DDR_dm(3 downto 0),
         DDR_DQ(31 downto 0)           => DDR_dq(31 downto 0),
         DDR_DQS(3 downto 0)           => DDR_dqs_p(3 downto 0),
         DDR_DQS_n(3 downto 0)         => DDR_dqs_n(3 downto 0),
         DDR_DRSTB                     => DDR_reset_n,
         DDR_ODT                       => DDR_odt,
         DDR_RAS_n                     => DDR_ras_n,
         DDR_VRN                       => FIXED_IO_ddr_vrn,
         DDR_VRP                       => FIXED_IO_ddr_vrp,
         DDR_WEB                       => DDR_we_n,
         FCLK_CLK0                     => plClk,
         FCLK_RESET0_N                 => sysRstN,
         IRQ_F2P                       => cpuIrqs,
         MIO(53 downto 0)              => FIXED_IO_mio,
         M_AXI_GP0_ACLK                => axiClk,
         M_AXI_GP0_ARADDR(31 downto 0) => axiReadMst.araddr(31 downto 0),
         M_AXI_GP0_ARBURST(1 downto 0) => axiReadMst.arburst,
         M_AXI_GP0_ARCACHE(3 downto 0) => axiReadMst.arcache,
         M_AXI_GP0_ARID(11 downto 0)   => axiReadMst.arid(11 downto 0),
         M_AXI_GP0_ARLEN(3 downto 0)   => axiReadMst.arlen(3 downto 0),
         M_AXI_GP0_ARLOCK(1 downto 0)  => axiReadMst.arlock,
         M_AXI_GP0_ARPROT(2 downto 0)  => axiReadMst.arprot,
         M_AXI_GP0_ARQOS(3 downto 0)   => axiReadMst.arqos,
         M_AXI_GP0_ARREADY             => axiReadSub.arready,
         M_AXI_GP0_ARSIZE(2 downto 0)  => axiReadMst.arsize,
         M_AXI_GP0_ARVALID             => axiReadMst.arvalid,
         M_AXI_GP0_AWADDR(31 downto 0) => axiWriteMst.awaddr(31 downto 0),
         M_AXI_GP0_AWBURST(1 downto 0) => axiWriteMst.awburst,
         M_AXI_GP0_AWCACHE(3 downto 0) => axiWriteMst.awcache,
         M_AXI_GP0_AWID(11 downto 0)   => axiWriteMst.awid(11 downto 0),
         M_AXI_GP0_AWLEN(3 downto 0)   => axiWriteMst.awlen(3 downto 0),
         M_AXI_GP0_AWLOCK(1 downto 0)  => axiWriteMst.awlock,
         M_AXI_GP0_AWPROT(2 downto 0)  => axiWriteMst.awprot,
         M_AXI_GP0_AWQOS(3 downto 0)   => axiWriteMst.awqos,
         M_AXI_GP0_AWREADY             => axiWriteSub.awready,
         M_AXI_GP0_AWSIZE(2 downto 0)  => axiWriteMst.awsize,
         M_AXI_GP0_AWVALID             => axiWriteMst.awvalid,
         M_AXI_GP0_BID(11 downto 0)    => axiWriteSub.bid(11 downto 0),
         M_AXI_GP0_BREADY              => axiWriteMst.bready,
         M_AXI_GP0_BRESP(1 downto 0)   => axiWriteSub.bresp,
         M_AXI_GP0_BVALID              => axiWriteSub.bvalid,
         M_AXI_GP0_RDATA(31 downto 0)  => axiReadSub.rdata(31 downto 0),
         M_AXI_GP0_RID(11 downto 0)    => axiReadSub.rid(11 downto 0),
         M_AXI_GP0_RLAST               => axiReadSub.rlast,
         M_AXI_GP0_RREADY              => axiReadMst.rready,
         M_AXI_GP0_RRESP(1 downto 0)   => axiReadSub.rresp,
         M_AXI_GP0_RVALID              => axiReadSub.rvalid,
         M_AXI_GP0_WDATA(31 downto 0)  => axiWriteMst.wdata(31 downto 0),
         M_AXI_GP0_WID(11 downto 0)    => axiWriteMst.wid(11 downto 0),
         M_AXI_GP0_WLAST               => axiWriteMst.wlast,
         M_AXI_GP0_WREADY              => axiWriteSub.wready,
         M_AXI_GP0_WSTRB(3 downto 0)   => axiWriteMst.wstrb(3 downto 0),
         M_AXI_GP0_WVALID              => axiWriteMst.wvalid,
         PS_CLK                        => FIXED_IO_ps_clk,
         PS_PORB                       => FIXED_IO_ps_porb,
         PS_SRSTB                      => FIXED_IO_ps_srstb,
         USB0_PORT_INDCTL              => open,
         USB0_VBUS_PWRFAULT            => '0',
         USB0_VBUS_PWRSELECT           => open,
         I2C0_SDA_I                    => i2c0Sda_o,
         I2C0_SDA_O                    => i2c0Sda_i,
         I2C0_SDA_T                    => i2c0Sda_t,
         I2C0_SCL_I                    => i2c0Scl_o,
         I2C0_SCL_O                    => i2c0Scl_i,
         I2C0_SCL_T                    => i2c0Scl_t
      );

   U_BUF_SCK : component IOBUF
      port map (
         IO => i2c0Scl,
         I  => i2c0Scl_i,
         O  => i2c0Scl_o,
         T  => i2c0Scl_t
      );

   U_BUF_SDA : component IOBUF
      port map (
         IO => i2c0Sda,
         I  => i2c0Sda_i,
         O  => i2c0Sda_o,
         T  => i2c0Sda_t
      );

   axiClk <= ulpiClkLoc;
   axiRst <= ulpiRst;

   U_AXI2AXIL : component axi2axil_converter_0
      port map (
         aclk                        => axiClk,
         aresetn                     => '1',
         s_axi_awid                  => axiWriteMst.awid,
         s_axi_awaddr                => axiWriteMst.awaddr,
         s_axi_awlen                 => axiWriteMst.awlen,
         s_axi_awsize                => axiWriteMst.awsize,
         s_axi_awburst               => axiWriteMst.awburst,
         s_axi_awlock                => axiWriteMst.awlock,
         s_axi_awcache               => axiWriteMst.awcache,
         s_axi_awprot                => axiWriteMst.awprot,
         s_axi_awqos                 => axiWriteMst.awqos,
         s_axi_awvalid               => axiWriteMst.awvalid,
         s_axi_awready               => axiWriteSub.awready,
         s_axi_wid                   => axiWriteMst.wid,
         s_axi_wdata                 => axiWriteMst.wdata,
         s_axi_wstrb                 => axiWriteMst.wstrb,
         s_axi_wlast                 => axiWriteMst.wlast,
         s_axi_wvalid                => axiWriteMst.wvalid,
         s_axi_wready                => axiWriteSub.wready,
         s_axi_bid                   => axiWriteSub.bid,
         s_axi_bresp                 => axiWriteSub.bresp,
         s_axi_bvalid                => axiWriteSub.bvalid,
         s_axi_bready                => axiWriteMst.bready,
         s_axi_arid                  => axiReadMst.arid,
         s_axi_araddr                => axiReadMst.araddr,
         s_axi_arlen                 => axiReadMst.arlen,
         s_axi_arsize                => axiReadMst.arsize,
         s_axi_arburst               => axiReadMst.arburst,
         s_axi_arlock                => axiReadMst.arlock,
         s_axi_arcache               => axiReadMst.arcache,
         s_axi_arprot                => axiReadMst.arprot,
         s_axi_arqos                 => axiReadMst.arqos,
         s_axi_arvalid               => axiReadMst.arvalid,
         s_axi_arready               => axiReadSub.arready,
         s_axi_rid                   => axiReadSub.rid,
         s_axi_rdata                 => axiReadSub.rdata,
         s_axi_rresp                 => axiReadSub.rresp,
         s_axi_rlast                 => axiReadSub.rlast,
         s_axi_rvalid                => axiReadSub.rvalid,
         s_axi_rready                => axiReadMst.rready,
         m_axi_awaddr                => axilWriteMst.awaddr,
         m_axi_awprot                => axilWriteMst.awprot,
         m_axi_awvalid               => axilWriteMst.awvalid,
         m_axi_awready               => axilWriteSub.awready,
         m_axi_wdata                 => axilWriteMst.wdata,
         m_axi_wstrb                 => axilWriteMst.wstrb,
         m_axi_wvalid                => axilWriteMst.wvalid,
         m_axi_wready                => axilWriteSub.wready,
         m_axi_bresp                 => axilWriteSub.bresp,
         m_axi_bvalid                => axilWriteSub.bvalid,
         m_axi_bready                => axilWriteMst.bready,
         m_axi_araddr                => axilReadMst.araddr,
         m_axi_arprot                => axilReadMst.arprot,
         m_axi_arvalid               => axilReadMst.arvalid,
         m_axi_arready               => axilReadSub.arready,
         m_axi_rdata                 => axilReadSub.rdata,
         m_axi_rresp                 => axilReadSub.rresp,
         m_axi_rvalid                => axilReadSub.rvalid,
         m_axi_rready                => axilReadMst.rready
      );

   B_ULPI_REG : block is
      type StateType is ( IDLE, WAI, DON );
      type RegType   is record
         state       :  StateType;
         rsub        :  AxiReadSubType;
         wsub        :  AxiWriteSubType;
         req         :  UlpiRegReqType;
         rwRegs      :  Slv32Array(0 to N_RW_REGS_C - 1);
         fifoWen     :  std_logic;
         fifoRen     :  std_logic;
         lineBreak   :  std_logic;
      end record RegType;
      constant REG_INIT_C : RegType := (
         state       => IDLE,
         rsub        => AXI_READ_SUB_INIT_C,
         wsub        => AXI_WRITE_SUB_INIT_C,
         req         => ULPI_REG_REQ_INIT_C,
         rwRegs      => (others => (others => '0')),
         fifoWen     => '0',
         fifoRen     => '0',
         lineBreak   => '0'
      );
      signal r       : RegType := REG_INIT_C;
      signal rin     : RegType;
   begin

   G_EXT_RST : if ( ULPI_CLK_MODE_INP_G /= 0 ) generate
      ulpiRstb <= not ulpiRst; -- RSTb
   end generate G_EXT_RST;

   G_NO_EXT_RST : if ( ULPI_CLK_MODE_INP_G = 0 ) generate
      -- asserting reset will stop the clock
      ulpiRstb <= '1';
   end generate G_NO_EXT_RST;

      U_ULPI_TOP : entity work.Usb2CdcAcmDev
         generic map (
            SYS_CLK_PERIOD_NS_G  => SYS_CLK_PERIOD_NS_C,
            ULPI_CLK_MODE_INP_G  => ULPI_CLK_MODE_INP_C,
            REF_CLK_DIV_G        => REF_CLK_DIV_C,
            CLK_MULT_F_G         => CLK_MULT_F_C,
            CLK0_DIV_G           => CLK0_DIV_C,
            CLK2_DIV_G           => CLK2_DIV_C,
            CLK1_INP_PHASE_G     => -58.5,
            NUM_I_REGS_G         => r.rwRegs'length,
            NUM_O_REGS_G         => roRegs'length
         )
         port map (
            refClkNb      => refClkNb,

            ulpiClkOut    => ulpiClkLoc,

            ulpiClk       => ulpiClk,
            ulpiRst       => ulpiRst,
            ulpiStp       => ulpiStp,
            ulpiDir       => ulpiDir,
            ulpiNxt       => ulpiNxt,
            ulpiDat       => ulpiDat,

            usb2Rst       => open,
            refLocked     => refLocked,
            lineBreak     => lineBreak,

            iRegs         => r.rwRegs,
            oRegs         => roRegs,

            regReq        => regReq,
            regRep        => regRep,

            fifoOutDat    => fifoOutDat,
            fifoOutEmpty  => fifoOutEmpty,
            fifoOutFill   => open,
            fifoOutRen    => fifoOutRen,

            fifoInpDat    => fifoInpDat,
            fifoInpFull   => fifoInpFull,
            fifoInpFill   => open,
            fifoInpWen    => fifoInpWen,

            clk2Nb        => open,

            i2sBCLK       => i2sBCLKLoc,
            i2sPBLRC      => i2sPBLRC,
            i2sPBDAT      => i2sPBDAT
         );

      fifoInpDat <= axilWriteMst.wdata(7 downto 0);

      acmIrq     <= not fifoOutEmpty or lineBreak;

      cpuIrqs    <= ( 1 => acmIrq, others => '0' );

      P_COMB : process ( r, axilReadMst, axilWriteMst, regRep, roRegs, fifoOutEmpty, fifoInpFull, fifoOutDat, lineBreak ) is
         variable v : RegType;
      begin
         v := r;

         v.req.extnd    := '0';
         v.rsub.arready := '0';
         v.wsub.awready := '0';
         v.wsub.wready  := '0';
         v.fifoRen      := '0';
         v.fifoWen      := '0';
         if ( lineBreak = '1' ) then
            v.lineBreak := '1';
         end if;

         case ( r.state ) is
            when IDLE =>
               v.rsub.rresp := (others => '0');
               v.wsub.bresp := (others => '0');
               if    ( ( axilReadMst.arvalid = '1' ) and ( axilReadMst.araddr(23 downto 12) = x"C01" ) ) then
                  v.req.rdnwr     := '1';
                  v.rsub.rresp    := "11"; -- decerr
                  v.state         := DON;
                  v.rsub.arready  := '1';
                  v.rsub.rvalid   := '1';
                  case ( axilReadMst.araddr( 7 downto 6 ) ) is
                  when "00" =>
                     if ( axilReadMst.araddr(5 downto 0) /= "101111" ) then
                        v.req.addr    := "00" & axilReadMst.araddr(5 downto 0);
                        v.req.vld     := '1';
                        v.state       := WAI;
                        v.rsub.rvalid := '0';
                     end if;
                  when "01" =>
                     if ( unsigned(axilReadMst.araddr(5 downto 2)) < N_RO_REGS_C ) then
                        v.rsub.rdata := roRegs( to_integer(unsigned(axilReadMst.araddr(5 downto 2))) );
                        v.rsub.rresp := "00";
                     end if;
                  when "10" =>
                     if ( unsigned(axilReadMst.araddr(5 downto 2)) < N_RW_REGS_C ) then
                        v.rsub.rdata := r.rwRegs( to_integer(unsigned(axilReadMst.araddr(5 downto 2))) );
                        v.rsub.rresp := "00";
                     end if;
                  when others =>
                     v.rsub.rdata(31 downto 10) := ( others => '0');
                     v.rsub.rdata(           9) := v.lineBreak;
                     v.lineBreak                := '0';
                     v.rsub.rdata(           8) := fifoOutEmpty;
                     v.rsub.rdata( 7 downto  0) := fifoOutDat;
                     v.fifoRen                  := not fifoOutEmpty;
                     v.rsub.rresp               := "00";
                  end case;
               elsif ( ( ( axilWriteMst.awvalid and axilWriteMst.wvalid ) = '1' ) and ( axilWriteMst.awaddr(23 downto 12) = x"C01" ) ) then
                  v.req.rdnwr    := '0';
                  v.wsub.bresp   := "11"; -- decerr
                  v.wsub.awready := '1';
                  v.wsub.wready  := '1';
                  v.wsub.bvalid  := '1';
                  v.state        := DON;
                  case ( axilWriteMst.awaddr( 7 downto 6 ) ) is
                  when "00" =>
                     if ( axilWriteMst.awaddr(5 downto 0) /= "101111" ) then
                        v.req.vld     := '1';
                        v.req.addr(7 downto 2) := "00" & axilWriteMst.awaddr(5 downto 2);
                        v.state       := WAI;
                        v.wsub.bvalid := '0';
                        if    ( axilWriteMst.wstrb = "0001" ) then
                           v.req.addr(1 downto 0) := "00";
                           v.req.wdat             := axilWriteMst.wdata( 7 downto  0);
                        elsif ( axilWriteMst.wstrb = "0010" ) then
                           v.req.addr(1 downto 0) := "01";
                           v.req.wdat             := axilWriteMst.wdata(15 downto  8);
                        elsif ( axilWriteMst.wstrb = "0100" ) then
                           v.req.addr(1 downto 0) := "10";
                           v.req.wdat             := axilWriteMst.wdata(23 downto 16);
                        elsif ( axilWriteMst.wstrb = "1000" ) then
                           v.req.addr(1 downto 0) := "11";
                           v.req.wdat             := axilWriteMst.wdata(31 downto 24);
                        else
                           v.wsub.bresp  := "10"; -- slverr
                           v.wsub.bvalid := '1';
                           v.req.vld     := '0';
                           v.state       := DON;
                        end if;
                     end if;
                  when "10" =>
                     if ( unsigned(axilWriteMst.awaddr(5 downto 2)) < N_RW_REGS_C ) then
                        for i in axilWriteMst.wstrb'range loop
                           if ( axilWriteMst.wstrb(i) = '1' ) then
                               v.rwRegs( to_integer(unsigned(axilWriteMst.awaddr(5 downto 2))) )(8*i+7 downto 8*i) := axilWriteMst.wdata(8*i + 7 downto 8*i);
                           end if;
                        end loop;
                        v.wsub.bresp := "00";
                     end if;
                  when others =>
                     if ( axilWriteMst.wstrb(0) = '1' ) then
                        v.fifoWen    := not fifoInpFull;
                        v.wsub.bresp := fifoInpFull & '0';
                     end if;
                  end case;
               end if;

            when WAI =>
               if ( regRep.ack = '1' ) then
                  v.req.vld := '0';
                  if ( r.req.rdnwr = '1' ) then
                     v.rsub.rdata  := regRep.rdat & regRep.rdat & regRep.rdat & regRep.rdat;
                     v.rsub.rresp  := regRep.err & '0';
                     v.rsub.rvalid := '1';
                  else
                     v.wsub.bresp  := regRep.err & '0';
                     v.wsub.bvalid := '1';
                  end if;
                  v.state := DON;
               end if;

            when DON =>
               if ( (r.rsub.rvalid and axilReadMst.rready) = '1' ) then
                  v.rsub.rvalid := '0';
                  v.state       := IDLE;
               end if;
               if ( (r.wsub.bvalid and axilWriteMst.bready) = '1' ) then
                  v.wsub.bvalid := '0';
                  v.state       := IDLE;
               end if;
         end case;

         rin <= v;
      end process P_COMB;

      P_SEQ : process ( ulpiClkLoc ) is
      begin
         if ( rising_edge( ulpiClkLoc ) ) then
            if ( ulpiRst = '1' ) then
               r <= REG_INIT_C;
            else
               r <= rin;
            end if;
         end if;
      end process P_SEQ;

      fifoInpWen     <= r.fifoWen;
      fifoOutRen     <= r.fifoRen;

      axilReadSub    <= r.rsub;
      axilWriteSub   <= r.wsub;
      regReq         <= r.req;
   end block B_ULPI_REG;

   P_RST : process ( ulpiClkLoc ) is
   begin
      if ( rising_edge( ulpiClkLoc ) ) then
         refLockedSync <= refLocked & refLockedSync(refLockedSync'left downto 1);
         if ( ( refLockedSync(0) and ulpiRstCnt(ulpiRstCnt'left) ) = '1' ) then
            ulpiRstCnt <= ulpiRstCnt - 1;
         end if;
      end if;
   end process P_RST;

   ulpiRst <= ulpiRstCnt(ulpiRstCnt'left);

  -- P_LED : process ( refLocked, lineBreak, i2sBlink ) is
  -- begin
  --    ledLoc    <= (others => '0');
  --    ledLoc(2) <= i2sBlink;
  --    ledLoc(1) <= lineBreak;
  --    ledLoc(0) <= refLocked;
  -- end process P_LED;

   B_XX : block is
    signal xxxClk : std_logic;
   begin

   U_SYSCB : BUFG port map (I => plClk, O => xxxClk);


   U_SYNC : entity work.Usb2MboxSync
   generic map (
      DWIDTH_A2B_G => 1,
      DWIDTH_B2A_G => 1,
      OUTREG_A2B_G => true,
      OUTREG_B2A_G => true
   )
   port map (
      clka         => xxxClk,
      dinA         => SW(1 downto 1),
      douA         => ledLoc(1 downto 1),

      clkb         => ulpiClkLoc,
      dinB         => SW(0 downto 0),
      douB         => ledLoc(0 downto 0)
   );

   end block;

   LED <= ledLoc;

end top_level;
