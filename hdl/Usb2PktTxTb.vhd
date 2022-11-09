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

entity Usb2PktTxTb is
end entity Usb2PktTxTb;

architecture sim of Usb2PktTxTb is

   constant TST_EP_IDX_C           : natural := 1;
   constant TST_EP_C               : Usb2EndpIdxType := to_unsigned(TST_EP_IDX_C,Usb2EndpIdxType'length);

   signal txDataMst       : Usb2StrmMstType := USB2_STRM_MST_INIT_C;
   signal txDataSub       : Usb2StrmSubType := USB2_STRM_SUB_INIT_C;

   signal ulpiTxReq       : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRep       : UlpiTxRepType;

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

      variable epCfg          : Usb2TstEpCfgArray      := (others => USB2_TST_EP_CFG_INIT_C);

      constant EP1_SZ_C       : Usb2ByteType           := x"08";
   begin
      epCfg( TST_EP_IDX_C                   ).maxPktSizeInp := to_integer(unsigned(EP1_SZ_C));
      epCfg( TST_EP_IDX_C                   ).maxPktSizeOut := to_integer(unsigned(EP1_SZ_C));

      usb2TstPkgConfig( epCfg );

      ulpiClkTick; ulpiClkTick;

      for i in 0 to 20 loop
         ulpiClkTick;
      end loop;
      ulpiTstRun <= false;
      report "TEST PASSED";
      wait;
   end process P_TST;

   U_DUT : entity work.Usb2PktTx
   port map (
      clk                          => ulpiTstClk,
      rst                          => open,
      ulpiTxReq                    => ulpiTxReq,
      ulpiTxRep                    => ulpiTxRep,
      txDataMst                    => txDataMst,
      txDataSub                    => txDataSub
   );

   U_ULPI_IO : entity work.UlpiIO
   port map (
      clk                          => ulpiTstClk,
      rst                          => open,
      
      dir                          => ulpiTstOb.dir,
      stp                          => ulpiTstIb.stp,
      nxt                          => ulpiTstOb.nxt,
      dat                          => ulpiDatIO,

      ulpiRx                       => open,
      ulpiTxReq                    => ulpiTxReq,
      ulpiTxRep                    => ulpiTxRep,

      regReq                       => open,
      regRep                       => open
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
         if ( txDataSub.rdy = '1' ) then
            if ( txDataMst.vld = '1' ) then
               if ( iidx = d2'high ) then
                  txDataMst.vld <= '0';
                  iidx          :=  0 ;
                  txDataMst.don <= '1';
                  txDataMst.err <= '0';
               else
                  iidx          := iidx + 1;
               end if;
            elsif ( txDataMst.don = '1' ) then
               txDataMst.don <= '0';
               txDataMst.vld <= '1';
            end if;
         end if;
         txDataMst.dat <= d2(iidx);
      end if;
   end process P_EP_1;

end architecture sim;
