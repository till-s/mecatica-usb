-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2UtilPkg.all;
use     work.UlpiPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2PrivPkg.all;
use     work.Usb2DescPkg.all;

-- Top-level USB module; ties lower-level modules together
-- and instantiates EP0.

entity Usb2Core is

   generic (
      -- with simulation enabled timing may be changed
      -- to speed things up
      SIMULATION_G                 : boolean         := false;
      MARK_DEBUG_ULPI_IO_G         : boolean         := false;
      MARK_DEBUG_ULPI_LINE_STATE_G : boolean         := false;
      MARK_DEBUG_PKT_RX_G          : boolean         := false;
      MARK_DEBUG_PKT_TX_G          : boolean         := false;
      MARK_DEBUG_PKT_PROC_G        : boolean         := false;
      MARK_DEBUG_EP0_G             : boolean         := false;
      ULPI_NXT_IOB_G               : boolean         := true;
      ULPI_DIR_IOB_G               : boolean         := true;
      ULPI_DIN_IOB_G               : boolean         := true;
      ULPI_STP_MODE_G              : UlpiStpModeType := NORMAL;
      -- ULPI emulation mode:
      --   NONE     => use regular ULPI transceiver
      --   FS_ONLY  => use serial (non-ULPI) full-speed transceiver
      --   LS_ONLY  => use serial (non-ULPI) low-speed transceiver
      -- Note: if the emulation mode is /= NONE then the serial
      --       signals are connected to fslsIb/fslsOb and ulpiIb/ulpiOb
      --       are unused.
      ULPI_EMU_MODE_G              : UlpiEmuModeType := NONE;
      DESCRIPTORS_G                : Usb2ByteArray;
      DESCRIPTOR_BRAM_G            : boolean         := false;
      -- automatically issue remote-wake if any inbound
      -- endpoint has data
      AUTO_REMWAKE_G               : boolean         := true;
      FSLS_INPUT_MODE_VPVM_G       : boolean         := true
   );

   port (
      -- sampling clock; required if ULPI_EMU_MODE_G /= NONE;
      -- used by a non-ulpi transceiver to sample the raw line
      -- signals. This clock must run at 4*ulpiClk and must be
      -- phase-locked to ulpiClk. The ulpiClk itself must run
      -- at the *bit rate* for serial/emulation modes.
      fslsSmplClk                  : in    std_logic := '0';
      fslsSmplRst                  : in    std_logic := '0';
      -- FS/LS serial interface (for ULPI emulation)
      fslsIb                       : in    FsLsIbType := FSLS_IB_INIT_C;
      fslsOb                       : out   FsLsObType := FSLS_OB_INIT_C;

      ulpiClk                      : in    std_logic;
      -- resets only the ULPI interface
      ulpiRst                      : in    std_logic := '0';
      -- resets packet engine, EP0, i.e., everything
      -- except for the ULPI interface which may still
      -- be needed to control reset/speed negotiation etc.
      usb2Rst                      : in    std_logic := '0';

      -- ULPI interface; connects directly to device
      -- pins (IOBs)
      ulpiIb                       : in    UlpiIbType := ULPI_IB_INIT_C;
      ulpiOb                       : out   UlpiObType := ULPI_OB_INIT_C;

      -- debugging and other special needs
      ulpiRx                       : out   UlpiRxType;

      ulpiForceStp                 : in    std_logic       := '0';

      -- access to registers in the ULPI PHY
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
      -- global device configuration (in most cases tied to a static value;
      -- should also match what the descriptors say)
      usb2HiSpeedEn                : in    std_logic          := '0';
      -- signal remote-wakeup (requires remote wakeup to be enabled by the host
      -- and in the currently active configuration descriptor)
      usb2RemoteWake               : in    std_logic          := '0';
      --    indicate whether the device is currently self-powered (for USB GET_STATUS req.)
      usb2SelfPowered              : in    std_logic          := '0';

      -- Endpoints are attached here (1 and up)
      usb2EpIb                     : in    Usb2EndpPairIbArray(0 to usb2AppGetMaxEndpointAddr(DESCRIPTORS_G) - 1)
                                           := ( others => USB2_ENDP_PAIR_IB_INIT_C );
      -- note EP0 output can be observed here; an external agent extending EP0 functionality
      -- needs to listen to usb2EpOb(0).
      usb2EpOb                     : out   Usb2EndpPairObArray(0 to usb2AppGetMaxEndpointAddr(DESCRIPTORS_G) - 1)
                                           := ( others => USB2_ENDP_PAIR_OB_INIT_C );

      -- access to descriptors in memory (only if DESCRIPTOR_BRAM_G is true)
      -- NOTE: when modifying contents be *very careful*! Nothing that
      --       alters the structure and layout of descriptors must be changed!
      --       This is only intended for tweaking contents such as a MAC
      --       address, for example.
      descRWClk                    : in  std_logic          := '0';
      descRWIb                     : in  Usb2DescRWIbType   := USB2_DESC_RW_IB_INIT_C;
      -- readout has a 1-cycle pipeline delay
      descRWOb                     : out Usb2DescRWObType   := USB2_DESC_RW_OB_INIT_C
   );


end entity Usb2Core;

architecture Impl of Usb2Core is

   constant NUM_ENDPOINTS_C : natural         := usb2AppGetMaxEndpointAddr(DESCRIPTORS_G);

   signal ulpiRxLoc         : UlpiRxType      := ULPI_RX_INIT_C;
   signal usb2RxLoc         : Usb2RxType      := USB2_RX_INIT_C;
   signal ulpiTxReq         : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiPktTxReq      : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiLineTxReq     : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRep         : UlpiTxRepType;

   signal regReq            : UlpiRegReqType  := ULPI_REG_REQ_INIT_C;
   signal regRep            : UlpiRegRepType  := ULPI_REG_REP_ERR_C;

   signal lineStateRegReq   : UlpiRegReqType;
   signal lineStateRegRep   : UlpiRegRepType  := ULPI_REG_REP_ERR_C;

   signal rstReq            : std_logic;
   signal suspend           : std_logic;
   signal isHiSpeed         : std_logic;
   signal isHiSpeedNego     : std_logic       := '0';

   signal txDataMst         : Usb2StrmMstType := USB2_STRM_MST_INIT_C;
   signal txDataSub         : Usb2PkTxSubType := USB2_PKTX_SUB_INIT_C;

   signal devStatus         : Usb2DevStatusType := USB2_DEV_STATUS_INIT_C;
   signal epConfig          : Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_CONFIG_INIT_C);

   signal epIb              : Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);
   signal epOb              : Usb2EndpPairObArray(0 to NUM_ENDPOINTS_C - 1) := (others => USB2_ENDP_PAIR_OB_INIT_C);

   type RegMuxState is (IDLE, LINESTATE, EXT);

   signal regMux            : RegMuxState := IDLE;
   signal regMuxIn          : RegMuxState;
   signal regWake           : std_logic   := '0';

--   attribute MARK_DEBUG    of regMux : signal is "TRUE";

begin

   usb2Rx               <= usb2RxLoc;
   ulpiRx               <= ulpiRxLoc;
   usb2EpOb             <= epOb;
   epIb(1 to epIb'high) <= usb2EpIb(1 to usb2EpIb'high);

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
      regMux,
      regWake,
      epIb
   ) is
      variable v           : RegMuxState;
      variable selExt      : boolean;
      variable autoWakeReq : std_logic;
   begin
      v                          := regMux;
      usb2DevStatus              <= devStatus;
      usb2DevStatus.usb2Rst      <= rstReq;
      autoWakeReq                := '0';
      if ( AUTO_REMWAKE_G and ( suspend = '1' ) ) then
         for i in epIb'range loop
            autoWakeReq := autoWakeReq or epIb(i).mstInp.vld;
         end loop;
      end if;
      -- is remote wakeup enabled?
      if ( not devStatus.remWakeup ) then
         regWake <= '0';
      else
         regWake <= usb2RemoteWake or autoWakeReq;
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

   P_REG_MUX : process ( ulpiClk ) is
   begin
      if ( rising_edge( ulpiClk ) ) then
         if ( ulpiRst = '1' ) then
            regMux <= IDLE;
         else
            regMux <= regMuxIn;
         end if;
      end if;
   end process P_REG_MUX;

   G_ULPI : if ( ULPI_EMU_MODE_G = NONE ) generate

   U_ULPI_IO : entity work.UlpiIO
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_ULPI_IO_G,
      ULPI_NXT_IOB_G  => ULPI_NXT_IOB_G,
      ULPI_DIR_IOB_G  => ULPI_DIR_IOB_G,
      ULPI_DIN_IOB_G  => ULPI_DIN_IOB_G,
      ULPI_STP_MODE_G => ULPI_STP_MODE_G
   )
   port map (
      ulpiClk         => ulpiClk,
      ulpiRst         => ulpiRst,

      ulpiIb          => ulpiIb,
      ulpiOb          => ulpiOb,

      forceStp        => ulpiForceStp,

      ulpiRx          => ulpiRxLoc,
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
         clk          => ulpiClk,
         rst          => ulpiRst,

         ulpiRx       => ulpiRxLoc,

         ulpiRegReq   => lineStateRegReq,
         ulpiRegRep   => lineStateRegRep,

         ulpiTxReq    => ulpiLineTxReq,
         ulpiTxRep    => ulpiTxRep,

         usb2HiSpeedEn=> usb2HiSpeedEn,

         usb2Rst      => rstReq,
         usb2Suspend  => suspend,
         usb2HiSpeed  => isHiSpeedNego,

         usb2RemWake  => regWake
      );

   end generate G_ULPI;

   G_FSLS : if ( ULPI_EMU_MODE_G /= NONE ) generate
      U_FSLS : entity work.UlpiFSLSEmul
         generic map (
            IS_FS_G            => (ULPI_EMU_MODE_G /= LS_ONLY),
            INPUT_MODE_VPVM_G  => FSLS_INPUT_MODE_VPVM_G
         )
         port map (
            smplClk            => fslsSmplClk,
            smplRst            => fslsSmplRst,
            fslsIb             => fslsIb,
            fslsOb             => fslsOb,

            ulpiClk            => ulpiClk,
            ulpiRst            => ulpiRst,

            ulpiRx             => ulpiRxLoc,
            ulpiTxReq          => ulpiTxReq,
            ulpiTxRep          => ulpiTxRep,

            usb2RemWake        => regWake,
            usb2Rst            => rstReq,
            usb2Suspend        => suspend
         );
      ulpiLineTxReq <= ulpiPktTxReq;
   end generate G_FSLS;

   U_PKT_RX : entity work.Usb2PktRx
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_PKT_RX_G
   )
   port map (
      clk             => ulpiClk,
      rst             => usb2Rst,
      ulpiRx          => ulpiRxLoc,
      usb2Rx          => usb2RxLoc
   );

   -- in simulation mode we bypass the speed negotiation
   P_HS_SIM : process ( isHiSpeedNego, usb2HiSpeedEn ) is
   begin
      if ( SIMULATION_G ) then
         isHiSpeed <= usb2HiSpeedEn;
      else
         isHiSpeed <= isHiSpeedNego;
      end if;
   end process P_HS_SIM;

   U_TX : entity work.Usb2PktTx
   generic map (
      MARK_DEBUG_G    => MARK_DEBUG_PKT_TX_G
   )
   port map (
      clk             => ulpiClk,
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
      ULPI_EMU_MODE_G => ULPI_EMU_MODE_G,
      MARK_DEBUG_G    => MARK_DEBUG_PKT_PROC_G,
      NUM_ENDPOINTS_G => NUM_ENDPOINTS_C
   )
   port map (
      clk             => ulpiClk,
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
      DESCRIPTORS_G   => DESCRIPTORS_G,
      DESCRIPTOR_BRAM_G => DESCRIPTOR_BRAM_G
   )
   port map (
      clk             => ulpiClk,
      rst             => usb2Rst,
      epIb            => epOb(0),
      epOb            => epIb(0),
      usrEpIb         => epIb(1 to epIb'high),

      param           => usb2Ep0ReqParam,
      pktHdr          => usb2RxLoc.pktHdr,
      ctlExt          => usb2Ep0CtlExt,
      ctlEpExt        => usb2EpIb(0),

      suspend         => suspend,
      hiSpeed         => isHiSpeed,
      selfPowered     => usb2SelfPowered,

      devStatus       => devStatus,
      epConfig        => epConfig,

      descRWClk       => descRWClk,
      descRWIb        => descRWIb,
      descRWOb        => descRWOb
  );

end architecture Impl;
