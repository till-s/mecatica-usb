-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.Usb2PrivPkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2TstPkg.all;

entity Usb2PktProcFSLSTb is
end entity Usb2PktProcFSLSTb;

architecture sim of Usb2PktProcFSLSTb is

   signal epConfig : Usb2EndpPairConfigArray(0 to 0) := (
      0 => USB2_ENDP_PAIR_CONFIG_INIT_C
   );

   signal epIb     : Usb2EndpPairIbArray(0 to 0) := (
      0 => USB2_ENDP_PAIR_IB_INIT_C
   );

   signal epOb     : Usb2EndpPairObArray(0 to 0) := (
      0 => USB2_ENDP_PAIR_OB_INIT_C
   );

   signal usb2DevStatus   : Usb2DevStatusType := USB2_DEV_STATUS_INIT_C;

   signal usb2Rx          : Usb2RxType;
   signal txDataMst       : Usb2StrmMstType;
   signal txDataSub       : Usb2PkTxSubType;
   signal ulpiRx          : UlpiRxType;
   signal ulpiTxReq       : UlpiTxReqType;
   signal ulpiTxRep       : UlpiTxRepType;
   signal ulpiRxHst       : UlpiRxType;
   signal ulpiTxReqHst    : UlpiTxReqType := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRepHst    : UlpiTxRepType;

   signal usb2Clk         : std_logic := '0';
   signal usb2Rst         : std_logic := '0';
   signal smplClk         : std_logic := '0';
   signal smplRst         : std_logic := '0';

   signal usb2HstClk      : std_logic;
   signal usb2HstRst      : std_logic := '0';
   signal smplHstClk      : std_logic;
   signal smplHstRst      : std_logic := '0';

   signal fslsIb          : FsLsIbType;
   signal fslsIbHst       : FsLsIbType;
   signal fslsOb          : FsLsObType;
   signal fslsObHst       : FsLsObType;

   signal run             : boolean   := true;
   signal epGo            : integer   := 0;

   procedure TICK is
   begin
      wait until rising_edge( usb2HstClk );
   end procedure TICK;

   constant DAT_C : Usb2ByteArray := (
      x"1A",
      x"2B",
      x"3C"
   );


begin

   epConfig(0).transferTypeInp <= USB2_TT_BULK_C;
   epConfig(0).maxPktSizeInp   <= to_unsigned(64, epConfig(0).maxPktSizeInp'length);
   epConfig(0).transferTypeOut <= USB2_TT_BULK_C;
   epConfig(0).maxPktSizeOut   <= to_unsigned(64, epConfig(0).maxPktSizeInp'length);

   P_EP  : process is
      procedure EPSND(constant v : Usb2ByteArray) is
      begin
         for i in v'low to v'high loop
            epIb(0).mstInp.vld <= '1';
            epIb(0).mstInp.don <= '0';
            epIb(0).mstInp.dat <= v(i);
            TICK;
            while ( epOb(0).subInp.rdy = '0' ) loop
               TICK;
            end loop;
         end loop;
         epIb(0).mstInp.vld <= '0';
         epIb(0).mstInp.don <= '1';
         TICK;
         while ( epOb(0).subInp.rdy = '0' ) loop
            TICK;
         end loop;
         epIb(0).mstInp.don <= '0';
         TICK;
      end procedure EPSND;

      variable epAck : integer := 0;
   begin
      while ( epAck = epGo ) loop
         TICK;
      end loop;
      EPSND( DAT_C );
      wait;
   end process P_EP;

   P_DRV : process is
      procedure SND(constant v : Usb2ByteArray) is
      begin
         ulpiTxReqHst.err <= '0';
         ulpiTxReqHst.vld <= '1';
         for i in v'low to v'high loop
            ulpiTxReqHst.dat <= v(i);
            TICK;
            while ( ulpiTxRepHst.nxt = '0' ) loop
              TICK;
            end loop;
         end loop;
         ulpiTxReqHst.vld <= '0';
         while (ulpiTxRepHst.don = '0') loop
            TICK;
         end loop;
      end procedure SND;

      constant TOK_IN_PKT_C : Usb2ByteArray := ulpiTstMkTokCmd( USB2_PID_TOK_IN_C, x"0", "0000000" );

   begin
      for i in 1 to 10 loop TICK; end loop;
      SND( TOK_IN_PKT_C );
      TICK;
      for i in 1 to 40 loop TICK; end loop;
      epGo <= epGo + 1;
      for i in 1 to 40 loop TICK; end loop;
      SND( TOK_IN_PKT_C );
      TICK;
      wait;
   end process P_DRV;

   P_MON : process ( usb2HstClk ) is
      constant NPHAS_C  : integer := 2;
      variable phas     : integer := 0;
      variable idx      : integer;
      variable crc      : std_logic_vector(15 downto 0);
   begin
      if ( rising_edge( usb2HstClk ) ) then
         if ( ( ulpiRxHst.dir and ulpiRxHst.nxt and not ulpiRxHst.trn ) = '1' ) then
            if ( phas = 0 ) then
               assert ulpiRxHst.dat = x"5A" report "NAK expected" severity failure;
               phas := phas + 1;
               idx  := -1;
            elsif ( phas = 1 ) then
               if (idx < 0 ) then
                  assert ulpiRxHst.dat = x"C3" report "DATA0 expected" severity failure;
                  crc := USB2_CRC16_INIT_C;
               elsif ( idx <=  DAT_C'high ) then
                  assert ulpiRxHst.dat = DAT_C(idx) report "IN data mismatch" severity failure;
                  ulpiTstCrc( crc, USB2_CRC16_POLY_C(crc'range), DAT_C(idx) );
               elsif ( idx <= DAT_C'high + 2 ) then
                  ulpiTstCrc( crc, USB2_CRC16_POLY_C(crc'range), ulpiRxHst.dat );
                  if ( idx = DAT_C'high + 2 ) then
                     assert crc = USB2_CRC16_CHCK_C report "IN data CRC mismatch" severity failure;
                     idx  := -2;
                     phas := phas + 1;
                  end if;
               end if;
               idx := idx + 1;
            end if;
         end if;
         if ( phas = NPHAS_C ) then
            report "Test PASSED";
            run <= false;
         end if;
      end if;
   end process P_MON;

   P_CLK : process is
   begin
      for i in 1 to 4 loop
         wait for 10 ns; smplClk <= not smplClk;
      end loop;
         usb2Clk <= not usb2Clk;
      if (not run) then wait; end if;
   end process P_CLK;

   usb2HstClk <= usb2Clk;
   smplHstClk <= smplClk;

--   P_BUS : process (fslsObHst, fslsOb) is
--   begin
--      if fslsOb.oe = '1' then
--         if ( fslsObHst.oe = '1' ) then
--            fslsIb.vp <= 'U';
--            fslsIb.vm <= 'U';
--         else
--            fslsIb.vp <= fslsOb.vp;
--            fslsIb.vm <= fslsOb.vm;
--         end if;
--      elsif ( fslsObHst.oe = '1' ) then
            fslsIb.vp    <= fslsObHst.vp;
            fslsIb.vm    <= fslsObHst.vm;
            fslsIbHst.vp <= fslsOb.vp;
            fslsIbHst.vm <= fslsOb.vm;
--      else
--            fslsIb.vp <= 'H';
--            fslsIb.vm <= 'L';
--      end if;
--   end process P_BUS;

   U_HST : entity work.UlpiFSLSEmul
      generic map (
         SYNC_STAGES_G        => 0
      )
      port map (
         -- 4 * clock rate, 48MHz for FS, 6MHz for LS;
         -- phase-locked to ulpiClk!
         smplClk              => smplHstClk,
         smplRst              => smplHstRst,

         -- transceiver interface
         fslsIb               => fslsIbHst,
         fslsOb               => fslsObHst,

         ulpiClk              => usb2HstClk,
         ulpiRst              => usb2HstRst,

         ulpiRx               => ulpiRxHst,
         ulpiTxReq            => ulpiTxReqHst,
         ulpiTxRep            => ulpiTxRepHst,

         -- USB device state interface
         usb2RemWake          => open,
         usb2Rst              => open,
         usb2Suspend          => open
      );


   U_DUT : entity work.UlpiFSLSEmul
      port map (
         -- 4 * clock rate, 48MHz for FS, 6MHz for LS;
         -- phase-locked to ulpiClk!
         smplClk              => smplClk,
         smplRst              => smplRst,

         -- transceiver interface
         fslsIb               => fslsIb,
         fslsOb               => fslsOb,

         ulpiClk              => usb2Clk,
         ulpiRst              => usb2Rst,

         ulpiRx               => ulpiRx,
         ulpiTxReq            => ulpiTxReq,
         ulpiTxRep            => ulpiTxRep,

         -- USB device state interface
         usb2RemWake          => open,
         usb2Rst              => open,
         usb2Suspend          => open
      );

   U_RX  : entity work.Usb2PktRx
      port map (
         clk             => usb2Clk,
         rst             => usb2Rst,
         ulpiRx          => ulpiRx,
         usb2Rx          => usb2Rx
      );

   U_TX  : entity work.Usb2PktTx
      port map (
         clk             => usb2Clk,
         rst             => usb2Rst,
         ulpiTxReq       => ulpiTxReq,
         ulpiTxRep       => ulpiTxRep,
         txDataMst       => txDataMst,
         txDataSub       => txDataSub,
         hiSpeed         => '0'
      );

   U_PKT : entity work.Usb2PktProc
      generic map (
         NUM_ENDPOINTS_G => epConfig'length,
         ULPI_EMU_MODE_G => FS_ONLY
      )
      port map (
         clk             => usb2Clk,
         rst             => usb2Rst,
         devStatus       => usb2DevStatus,
         epConfig        => epConfig,
         epIb            => epIb,
         epOb            => epOb,

         usb2Rx          => usb2Rx,

         txDataMst       => txDataMst,
         txDataSub       => txDataSub
      );

end architecture sim;
