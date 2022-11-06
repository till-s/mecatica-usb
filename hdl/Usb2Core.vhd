library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.UsbUtilPkg.all;
use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2DescPkg.all;

entity Usb2Core is

   generic (
      MARK_DEBUG_ULPI_IO_G         : boolean := true;
      MARK_DEBUG_PKT_RX_G          : boolean := true;
      MARK_DEBUG_PKT_TX_G          : boolean := true;
      MARK_DEBUG_PKT_PROC_G        : boolean := true;
      MARK_DEBUG_EP0_G             : boolean := true;
      DESCRIPTORS_G                : Usb2ByteArray
   );

   port (
      clk                          : in    std_logic;

      -- resets only the ULPI interface
      ulpiRst                      : in    std_logic := '0';
      -- resets packet engine, EP0, i.e., everything
      -- except for the ULPI interface which may still
      -- be needed to control reset/speed negotiation etc.
      usb2Rst                      : in    std_logic := '0';

      -- ULPI interface; connects directly to device
      -- pins (IOBs)
      ulpiDir                      : in    std_logic;
      ulpiNxt                      : in    std_logic;
      ulpiStp                      : out   std_logic;
      ulpiDat                      : inout std_logic_vector(7 downto 0);

      -- device state (ADDRESS->CONFIGURED) and other info
      usb2DevStatus                : out   Usb2DevStatusType;
      -- incoming packet headers; e.g., SOFs can be seen here
      usb2PktHdr                   : out   Usb2PktHdrType;

      -- control ports for extending EP0 functionality (e.g., to handle
      -- class-specific requests). See Usb2StdCtlEp.vhd for more comments.
      usb2Ep0ReqParam              : out   Usb2CtlReqParamType;
      usb2Ep0CtlExt                : in    Usb2CtlExtType     := USB2_CTL_EXT_INIT_C;
      usb2Ep0CtlEpExt              : in    Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      -- Endpoints are attached here (1 and up)
      usb2EpIb                     : in    Usb2EndpPairIbArray(1 to USB2_APP_NUM_ENDPOINTS_F(DESCRIPTORS_G) - 1)
                                           := ( others => USB2_ENDP_PAIR_IB_INIT_C );
      -- note EP0 output can be observed here; an external agent extending EP0 functionality
      -- needs to listen to this.
      usb2EpOb                     : out   Usb2EndpPairObArray(0 to USB2_APP_NUM_ENDPOINTS_F(DESCRIPTORS_G) - 1)
                                           := ( others => USB2_ENDP_PAIR_OB_INIT_C )
   );


end entity Usb2Core;

architecture Impl of Usb2Core is

   constant NUM_ENDPOINTS_C : natural         := USB2_APP_NUM_ENDPOINTS_F(DESCRIPTORS_G);

   signal ulpiRegReq        : UlpiRegReqType  := ULPI_REG_REQ_INIT_C;
   signal ulpiRegRep        : UlpiRegRepType;

   signal ulpiRx            : UlpiRxType      := ULPI_RX_INIT_C;
   signal ulpiTxReq         : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRep         : UlpiTxRepType;

   signal txDataMst         : Usb2StrmMstType := USB2_STRM_MST_INIT_C;
   signal txDataSub         : Usb2StrmSubType := USB2_STRM_SUB_INIT_C;
   signal rxDataMst         : Usb2StrmMstType := USB2_STRM_MST_INIT_C;

   signal devStatus         : Usb2DevStatusType := USB2_DEV_STATUS_INIT_C;
   signal epConfig          : Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_C - 1);

   signal rxPktHdr          : Usb2PktHdrType;

   signal epIb              : Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb              : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_OB_INIT_C);

begin

   usb2DevStatus        <= devStatus;
   usb2PktHdr           <= rxPktHdr;
   usb2EpOb             <= epOb;
   epIb(1 to epIb'high) <= usb2EpIb;

   U_ULPI_IO : entity work.UlpiIO
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_ULPI_IO_G
   )
   port map (
      clk             => clk,
      rst             => ulpiRst,

      dir             => ulpiDir,
      stp             => ulpiStp,
      nxt             => ulpiNxt,
      dat             => ulpiDat,

      ulpiRx          => ulpiRx,
      ulpiTxReq       => ulpiTxReq,
      ulpiTxRep       => ulpiTxRep,

      regReq          => ulpiRegReq,
      regRep          => ulpiRegRep
   );

   U_PKT_RX : entity work.Usb2PktRx
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_PKT_RX_G
   )
   port map (
      clk             => clk,
      rst             => usb2Rst,
      ulpiRx          => ulpiRx,
      pktHdr          => rxPktHdr,
      rxData          => rxDataMst
   );

   U_TX : entity work.Usb2PktTx
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_PKT_TX_G
   )
   port map (
      clk             => clk,
      rst             => usb2Rst,
      ulpiTxReq       => ulpiTxReq,
      ulpiTxRep       => ulpiTxRep,
      txDataMst       => txDataMst,
      txDataSub       => txDataSub
   );

   U_PKT_PROCESSOR : entity work.Usb2PktProc
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_PKT_PROC_G,
      NUM_ENDPOINTS_G => NUM_ENDPOINTS_C
   )
   port map (
      clk             => clk,
      rst             => usb2Rst,
      devStatus       => devStatus,
      epConfig        => epConfig,
      epIb            => epIb,
      epOb            => epOb,

      txDataMst       => txDataMst,
      txDataSub       => txDataSub,
      rxPktHdr        => rxPktHdr,
      rxDataMst       => rxDataMst
   );

   U_DUT_CTL : entity work.Usb2StdCtlEp
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_EP0_G,
      NUM_ENDPOINTS_G => NUM_ENDPOINTS_C,
      DESCRIPTORS_G   => DESCRIPTORS_G
   )
   port map (
      clk             => clk,
      rst             => usb2Rst,
      epIb            => epOb(0),
      epOb            => epIb(0),
      usrEpIb         => epIb(1 to epIb'high),

      param           => usb2Ep0ReqParam,
      ctlExt          => usb2Ep0CtlExt,
      ctlEpExt        => usb2Ep0CtlEpExt,

      devStatus       => devStatus,
      epConfig        => epConfig
  );

end architecture Impl;
