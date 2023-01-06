library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.Ps7Pkg.all;
use work.Axi4vPkg.all;
use work.UlpiPkg.all;
use work.Usb2Pkg.all;
use work.StdLogPkg.all;

entity ZyboTop is
   generic (
      -- ulpi 'INPUT clock mode is when the link generates the clock'
      ULPI_CLK_MODE_INP_G : boolean := true
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

      JB1_P             : out   std_logic;
      JB1_N             : out   std_logic;
      JB2_P             : in    std_logic;
      JB3_P             : inout std_logic;
      JB4_P             : in    std_logic;
      JC1_P             : inout std_logic;
      JC2_P             : inout std_logic;
      JC3_P             : inout std_logic;
      JC4_P             : inout std_logic;
      JD1_P             : inout std_logic;
      JD2_P             : inout std_logic;
      JD3_P             : inout std_logic;
      JD4_P             : inout std_logic;
      
      SW                : in    std_logic_vector(3 downto 0);

      LED               : out   std_logic_vector(3 downto 0) := (others => '0')
   );
end ZyboTop;

architecture top_level of ZyboTop is

   attribute IO_BUFFER_TYPE              : string;

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

   signal locBusMst                      : LocBusMstType;
   signal locBusSub                      : LocBusSubType   := LOC_BUS_SUB_INIT_C;

   signal regReq                         : UlpiRegReqType;
   signal regRep                         : UlpiRegRepType;

   signal cpuIrqs                        : std_logic_vector(15 downto 0) := (others => '0');

   signal ledLoc                         : std_logic_vector(3 downto 0) := (others => '0');
   signal ctl                            : std_logic_vector(7 downto 0) := (others => '0');

   signal lineBreak                      : std_logic;

   signal plClk                          : std_logic;
   signal sysClk                         : std_logic;
   signal sysRst, sysRstN                : std_logic;
   signal ulpiClk                        : std_logic;
   signal ulpiRst                        : std_logic := '0';
   signal refLocked                      : std_logic;

   signal axiClk                         : std_logic;
   signal axiRst                         : std_logic;
   
   signal roRegs                         : Slv32Array(0 to N_RO_REGS_C - 1) := ( others => (others => '0') );

   signal fifoOutDat                     : Usb2ByteType;
   signal fifoInpDat                     : Usb2ByteType;
   signal fifoOutEmpty                   : std_logic;
   signal fifoInpFull                    : std_logic;
   signal fifoOutRen                     : std_logic;
   signal fifoInpWen                     : std_logic;


begin

   G_ETH_CLK: if ( USE_ETH_CLK_C ) generate
      signal initCnt : unsigned (10 downto 0) := (others => '1');
   begin
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
      sysRst  <= not sysRstN;
      sysClk  <= plClk;
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
         USB0_VBUS_PWRSELECT           => open
      );

   axiClk <= ulpiClk;
   axiRst <= ulpiRst;
      
   U_AXI : entity work.Axi4lsWrapper
      generic map (
         ADDR_WIDTH_G                  => ADDR_WIDTH_C,
         ASYNC_STAGES_G                => 2
      )
      port map (
         axiClk                        => axiClk,
         axiRst                        => axiRst,
         axiWriteMst                   => axiWriteMst,
         axiWriteSub                   => axiWriteSub,
         axiReadMst                    => axiReadMst,
         axiReadSub                    => axiReadSub,

         locBusClk                     => ulpiClk,
         locBusRst                     => ulpiRst,

         locBusMst                     => locBusMst,
         locBusSub                     => locBusSub
      );

   B_ULPI_REG : block is
      type StateType is ( IDLE, WAI, DON );
      type RegType   is record
         state       :  StateType;
         sub         :  LocBusSubType;
         req         :  UlpiRegReqType;
         rwRegs      :  Slv32Array(0 to N_RW_REGS_C - 1);
      end record RegType;
      constant REG_INIT_C : RegType := (
         state       => IDLE,
         sub         => LOC_BUS_SUB_INIT_C,
         req         => ULPI_REG_REQ_INIT_C,
         rwRegs      => (others => (others => '0'))
      );
      signal r       : RegType := REG_INIT_C;
      signal rin     : RegType;
   begin

      JB1_N <= not ulpiRst; -- RSTb

      U_ULPI_TOP : entity work.Usb2CdcAcmDev
         generic map (
            SYS_CLK_PERIOD_NS_G  => SYS_CLK_PERIOD_NS_C,
            ULPI_CLK_MODE_INP_G  => ULPI_CLK_MODE_INP_G,
            REF_CLK_DIV_G        => REF_CLK_DIV_C,
            CLK_MULT_F_G         => CLK_MULT_F_C,
            CLK0_DIV_G           => CLK0_DIV_C,
            CLK2_DIV_G           => CLK2_DIV_C,
            NUM_I_REGS_G         => r.rwRegs'length,
            NUM_O_REGS_G         => roRegs'length
         )
         port map (
            sysClk        => sysClk,

            ulpiClkOut    => ulpiClk,

            ulpiClk       => JB3_P,
            ulpiRst       => open,
            ulpiStp       => JB1_P, -- IO0
            ulpiDir       => JB2_P, -- IO2
            ulpiNxt       => JB4_P, -- IO3
            ulpiDat(0)    => JC1_P, -- IO4
            ulpiDat(1)    => JC3_P, -- IO5
            ulpiDat(2)    => JC2_P, -- IO6
            ulpiDat(3)    => JC4_P, -- IO7
            ulpiDat(4)    => JD3_P, -- IO8
            ulpiDat(5)    => JD1_P, -- IO9
            ulpiDat(6)    => JD4_P, -- IO10
            ulpiDat(7)    => JD2_P, -- IO11

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
            fifoInpWen    => fifoInpWen
         );

      -- Loopback
      fifoInpDat <= fifoOutDat;
      fifoInpWen <= not fifoOutEmpty;
      fifoOutRen <= not fifoInpFull;

      P_COMB : process ( r, locBusMst, regRep, roRegs ) is
         variable v : RegType;
      begin
         v := r;

         v.sub.rvalid := '0';
         v.sub.wready := '0';

         v.req.extnd  := '0';

         case ( r.state ) is
            when IDLE =>
               v.sub.rerr := '0';
               v.sub.werr := '0';
               if    ( locBusMst.rs = '1' ) then
                  v.req.rdnwr     := '1';
                  v.sub.rerr      := '1';
                  v.state         := DON;
                  case ( locBusMst.raddr( 7 downto 6 ) ) is
                  when "00" =>
                     if ( locBusMst.raddr(5 downto 0) /= "101111" ) then
                        v.req.addr   := "00" & locBusMst.raddr(5 downto 0);
                        v.req.vld    := '1';
                        v.state      := WAI;
                     end if;
                  when "01" =>
                     if ( unsigned(locBusMst.raddr(5 downto 2)) < N_RO_REGS_C ) then
                        v.sub.rdata := roRegs( to_integer(unsigned(locBusMst.raddr(5 downto 2))) );
                        v.sub.rerr  := '0';
                     end if;
                  when "10" =>
                     if ( unsigned(locBusMst.raddr(5 downto 2)) < N_RW_REGS_C ) then
                        v.sub.rdata := r.rwRegs( to_integer(unsigned(locBusMst.raddr(5 downto 2))) );
                        v.sub.rerr  := '0';
                     end if;
                  when others =>
                  end case;
               elsif ( locBusMst.ws = '1' ) then
                  v.req.rdnwr  := '0';
                  v.sub.werr   := '1';
                  v.state      := DON;
                  case ( locBusMst.raddr( 7 downto 6 ) ) is
                  when "00" =>
                     if ( locBusMst.waddr(5 downto 0) /= "101111" ) then
                        v.req.vld    := '1';
                        v.req.addr(7 downto 2) := "00" & locBusMst.waddr(5 downto 2);
                        v.state      := WAI;
                        if    ( locBusMst.wstrb = "0001" ) then
                           v.req.addr(1 downto 0) := "00";
                           v.req.wdat             := locBusMst.wdata( 7 downto  0);
                        elsif ( locBusMst.wstrb = "0010" ) then
                           v.req.addr(1 downto 0) := "01";
                           v.req.wdat             := locBusMst.wdata(15 downto  8);
                        elsif ( locBusMst.wstrb = "0100" ) then
                           v.req.addr(1 downto 0) := "10";
                           v.req.wdat             := locBusMst.wdata(23 downto 16);
                        elsif ( locBusMst.wstrb = "1000" ) then
                           v.req.addr(1 downto 0) := "11";
                           v.req.wdat             := locBusMst.wdata(31 downto 24);
                        else
                           v.sub.werr  := '1';
                           v.req.vld   := '0';
                           v.state     := DON;
                        end if;
                     end if;
                  when "10" =>
                     if ( unsigned(locBusMst.waddr(5 downto 2)) < N_RW_REGS_C ) then
                        for i in locBusMst.wstrb'range loop
                           if ( locBusMst.wstrb(i) = '1' ) then
                               v.rwRegs( to_integer(unsigned(locBusMst.waddr(5 downto 2))) )(8*i+7 downto 8*i) := locBusMst.wdata(8*i + 7 downto 8*i);
                           end if;
                        end loop;
                        v.sub.werr := '0';
                     end if;
                  when others =>
                  end case;
               end if;

            when WAI =>
               if ( regRep.ack = '1' ) then
                  v.req.vld := '0';
                  if ( r.req.rdnwr = '1' ) then
                     v.sub.rdata  := regRep.rdat & regRep.rdat & regRep.rdat & regRep.rdat;
                     v.sub.rerr   := regRep.err;
                     v.sub.rvalid := '1';
                  else
                     v.sub.werr   := regRep.err;
                     v.sub.wready := '1';
                  end if;
                  v.state := DON;
               end if;

            when DON =>
               if ( r.req.rdnwr = '1' ) then
                  if ( r.sub.rvalid = '1' ) then
                     v.state := IDLE;
                  else
                     v.sub.rvalid := '1';
                  end if;
               else
                  if ( r.sub.wready = '1' ) then
                     v.state := IDLE;
                  else
                     v.sub.wready := '1';
                  end if;
               end if;
         end case;

         rin <= v;
      end process P_COMB;

      P_SEQ : process ( ulpiClk ) is
      begin
         if ( rising_edge( ulpiClk ) ) then 
            if ( ulpiRst = '1' ) then
               r <= REG_INIT_C;
            else
               r <= rin;
            end if;
         end if;
      end process P_SEQ;

      locBusSub <= r.sub;
      regReq    <= r.req;
   end block B_ULPI_REG;

   P_LED : process ( refLocked, lineBreak ) is
   begin
      ledLoc    <= (others => '0');
      ledLoc(1) <= lineBreak;
      ledLoc(0) <= refLocked;
   end process P_LED;

   LED <= ledLoc;

end top_level;
