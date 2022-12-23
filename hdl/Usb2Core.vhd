library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2UtilPkg.all;
use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2DescPkg.all;

entity Usb2Core is

   generic (
      -- with simulation enabled timing may be changed
      -- to speed things up
      SIMULATION_G                 : boolean         := false;
      MARK_DEBUG_ULPI_IO_G         : boolean         := true;
      MARK_DEBUG_ULPI_LINE_STATE_G : boolean         := true;
      MARK_DEBUG_PKT_RX_G          : boolean         := true;
      MARK_DEBUG_PKT_TX_G          : boolean         := true;
      MARK_DEBUG_PKT_PROC_G        : boolean         := true;
      MARK_DEBUG_EP0_G             : boolean         := true;
      ULPI_NXT_IOB_G               : boolean         := true;
      ULPI_DIR_IOB_G               : boolean         := true;
      ULPI_DIN_IOB_G               : boolean         := true;
      ULPI_STP_MODE_G              : UlpiStpModeType := NORMAL;
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
      ulpiIb                       : in    UlpiIbType;
      ulpiOb                       : out   UlpiObType;

      ulpiForceStp                 : in    std_logic       := '0';

      ulpiRegReq                   : in    UlpiRegReqType  := ULPI_REG_REQ_INIT_C;
      ulpiRegRep                   : out   UlpiRegRepType;

      -- device state (ADDRESS->CONFIGURED) and other info
      usb2DevStatus                : out   Usb2DevStatusType;
      -- incoming packet headers; e.g., SOFs can be seen here
      usb2Rx                       : out   Usb2RxType;

      -- control ports for extending EP0 functionality (e.g., to handle
      -- class-specific requests). See Usb2StdCtlEp.vhd for more comments.
      usb2Ep0ReqParam              : out   Usb2CtlReqParamType;
      usb2Ep0CtlExt                : in    Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
      usb2Ep0CtlEpExt              : in    Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      usb2HiSpeedEn                : in    std_logic          := '0';
      usb2RemoteWake               : in    std_logic          := '0';

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

   signal ulpiRx            : UlpiRxType      := ULPI_RX_INIT_C;
   signal usb2RxLoc         : Usb2RxType      := USB2_RX_INIT_C;
   signal ulpiTxReq         : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiPktTxReq      : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiLineTxReq     : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRep         : UlpiTxRepType;

   signal regReq            : UlpiRegReqType  := ULPI_REG_REQ_INIT_C;
   signal regRep            : UlpiRegRepType;

   signal lineStateRegReq   : UlpiRegReqType;
   signal lineStateRegRep   : UlpiRegRepType  := ULPI_REG_REP_INIT_C;

   signal rstReq            : std_logic;
   signal suspend           : std_logic;
   signal isHiSpeed         : std_logic;

   signal txDataMst         : Usb2StrmMstType := USB2_STRM_MST_INIT_C;
   signal txDataSub         : Usb2StrmSubType := USB2_STRM_SUB_INIT_C;

   signal devStatus         : Usb2DevStatusType := USB2_DEV_STATUS_INIT_C;
   signal epConfig          : Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_C - 1);

   signal epIb              : Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb              : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_OB_INIT_C);

   type RegMuxState is (IDLE, LINESTATE, EXT);

   signal regMux            : RegMuxState := IDLE;
   signal regMuxIn          : RegMuxState;

   signal remWake           : std_logic;

--   attribute MARK_DEBUG    of regMux : signal is "TRUE";

begin

   usb2Rx               <= usb2RxLoc;
   usb2EpOb             <= epOb;
   epIb(1 to epIb'high) <= usb2EpIb;

   P_COMB : process (
      devStatus,
      usb2RemoteWake,
      rstReq,
      suspend,
      ulpiPktTxReq,
      ulpiLineTxReq,
      lineStateRegReq,
      ulpiRegReq,
      regRep,
      regMux
   ) is 
      variable v      : RegMuxState;
      variable selExt : boolean;
   begin
      v                          := regMux;
      usb2DevStatus              <= devStatus;
      usb2DevStatus.usb2Rst      <= rstReq;
      -- is remote wakeup enabled?
      if ( not devStatus.remWakeup ) then
         remWake <= '0';
      else
         remWake <= usb2RemoteWake;
      end if;
      ulpiTxReq <= ulpiPktTxReq;
      if ( ( rstReq or suspend ) = '1' ) then
         ulpiTxReq <= ulpiLineTxReq;
      end if;
      -- default
      ulpiRegRep      <= ULPI_REG_REP_INIT_C;
      regReq          <= lineStateRegReq;
      lineStateRegRep <= regRep;
      selExt          := (regMux = EXT);
      case ( regMux ) is
         when IDLE =>
            if ( lineStateRegReq.vld = '1' ) then
               v      := LINESTATE;
            elsif ( ulpiRegReq.vld = '1' ) then
               v      := EXT;
               selExt := true;
            end if;
         when others =>
            if ( regRep.ack = '1' ) then
               v := IDLE;
            end if;
      end case;
      if ( selExt ) then
         lineStateRegRep <= ULPI_REG_REP_INIT_C;
         regReq          <= ulpiRegReq;
         ulpiRegRep      <= regRep;
      end if;
      regMuxIn <= v;
   end process P_COMB;

   P_REG_MUX : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ulpiRst = '1' ) then
            regMux <= IDLE;
         else
            regMux <= regMuxIn;
         end if;
      end if;
   end process P_REG_MUX;

   U_ULPI_IO : entity work.UlpiIO
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_ULPI_IO_G,
      ULPI_NXT_IOB_G  => ULPI_NXT_IOB_G,
      ULPI_DIR_IOB_G  => ULPI_DIR_IOB_G,
      ULPI_DIN_IOB_G  => ULPI_DIN_IOB_G,
      ULPI_STP_MODE_G => ULPI_STP_MODE_G
   )
   port map (
      ulpiClk         => clk,
      rst             => ulpiRst,

      ulpiIb          => ulpiIb,
      ulpiOb          => ulpiOb,

      forceStp        => ulpiForceStp,

      ulpiRx          => ulpiRx,
      ulpiTxReq       => ulpiTxReq,
      ulpiTxRep       => ulpiTxRep,

      regReq          => regReq,
      regRep          => regRep
   );

   U_LINE_STATE : entity work.UlpiLineState
      generic map (
         MARK_DEBUG_G => MARK_DEBUG_ULPI_LINE_STATE_G
      )
      port map (
         clk          => clk,
         rst          => ulpiRst,

         ulpiRx       => ulpiRx,

         ulpiRegReq   => lineStateRegReq,
         ulpiRegRep   => lineStateRegRep,

         ulpiTxReq    => ulpiLineTxReq,
         ulpiTxRep    => ulpiTxRep,

         usb2HiSpeedEn=> usb2HiSpeedEn,

         usb2Rst      => rstReq,
         usb2Suspend  => suspend,
         usb2HiSpeed  => isHiSpeed,

         usb2RemWake  => remWake
      );

   U_PKT_RX : entity work.Usb2PktRx
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_PKT_RX_G
   )
   port map (
      clk             => clk,
      rst             => usb2Rst,
      ulpiRx          => ulpiRx,
      usb2Rx          => usb2RxLoc
   );

   U_TX : entity work.Usb2PktTx
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_PKT_TX_G
   )
   port map (
      clk             => clk,
      rst             => usb2Rst,
      ulpiTxReq       => ulpiPktTxReq,
      ulpiTxRep       => ulpiTxRep,
      txDataMst       => txDataMst,
      txDataSub       => txDataSub,
      hiSpeed         => isHiSpeed
   );

   U_PKT_PROCESSOR : entity work.Usb2PktProc
   generic map (
      SIMULATION_G    => SIMULATION_G,
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

      usb2Rx          => usb2RxLoc,

      txDataMst       => txDataMst,
      txDataSub       => txDataSub
   );

   U_CTL_EP0 : entity work.Usb2StdCtlEp
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
      pktHdr          => usb2RxLoc.pktHdr,
      ctlExt          => usb2Ep0CtlExt,
      ctlEpExt        => usb2Ep0CtlEpExt,

      suspend         => suspend,
      hiSpeed         => isHiSpeed,

      devStatus       => devStatus,
      epConfig        => epConfig
  );

end architecture Impl;
