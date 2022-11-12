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

   signal ulpiRx          : UlpiRxType;
   signal ulpiTxReq       : UlpiTxReqType   := ULPI_TX_REQ_INIT_C;
   signal ulpiTxRep       : UlpiTxRepType;

   signal iidx            : integer         := 0;
   signal vidx            : natural         := 0;
   signal vend            : integer         := 0;

   signal epRst           : std_logic       := '0';

   type   EopWaitType     is (NONE, SE0, FSJ);
   signal eopWait         : EopWaitType     := NONE;

   -- empty
   constant d0 : Usb2ByteArray := USB2_TST_NULL_DATA_C;
   -- one
   constant d1 : Usb2ByteArray := ( 0 => x"01" );
   -- shorter than packet size
   constant d2 : Usb2ByteArray := ( x"01", x"02", x"03" );
   -- exact multiple of packet size
   constant d3 : Usb2ByteArray := (
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

      for a in -1 to 2 loop
         for w in 0 to 4 loop
            pid := USB2_PID_DAT_DATA0_C;
            ulpiTstWaitDatPkt( ulpiTstOb, pid , d0, w => w, nnak => true );

            pid := USB2_PID_DAT_DATA1_C;
            ulpiTstWaitDatPkt( ulpiTstOb, pid , d1, w => w, nnak => true );

            pid := USB2_PID_DAT_DATA0_C;
            ulpiTstWaitDatPkt( ulpiTstOb, pid , d2, w => w, nnak => true );

            pid := USB2_PID_DAT_DATA1_C;
            ulpiTstWaitDatPkt( ulpiTstOb, pid , d3, w => w, nnak => true, abrt => a );

            if ( a = -1 ) then
               pid := USB2_PID_DAT_DATA0_C;
               ulpiTstWaitDatPkt( ulpiTstOb, pid , d3(0 to d3'high-1), w => w, nnak => true );
            end if;
         end loop;
      end loop;

      for i in 0 to 200 loop
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

      ulpiRx                       => ulpiRx,
      ulpiTxReq                    => ulpiTxReq,
      ulpiTxRep                    => ulpiTxRep,

      regReq                       => open,
      regRep                       => open
   );

   P_EP_1_SEQ  : process ( ulpiTstClk ) is
   begin
      if ( rising_edge( ulpiTstClk ) ) then
         if ( ( txDataSub.rdy and txDataMst.vld ) = '1' ) then
            if ( iidx < vend ) then
               iidx <= iidx + 1;
            else
               txDataMst.vld <= '0';
               txDataMst.don <= '1';
            end if;
         end if;
         if ( ( txDataMst.don and txDataSub.don ) = '1' ) then
            txDataMst.don <= '0';
            iidx          <= 0;
            eopWait       <= SE0;
            if ( vidx = 4 ) then
               vidx <= 0;
            else
               vidx <= vidx + 1;
            end if;
         end if;
         if ( ( txDataMst.vld or txDataMst.don ) = '0' and ( eopWait = NONE ) ) then
            if ( iidx <= vend ) then
              txDataMst.vld <= '1';
            else
              -- zero pkt
              txDataMst.don <= '1';
            end if;
         end if;
         if ( ( ( txDataMst.vld or txDataMst.don ) and txDataSub.err and txDataSub.don ) = '1' ) then
            -- ABORT --
            txDataMst.vld <= '0';
            txDataMst.don <= '0';
            iidx <= 0;
            vidx <= 0;
         end if;
         case eopWait is
            when SE0 =>
              if ( ulpiIsRxCmd( ulpiRx ) and ulpiRx.dat(1 downto 0) = ULPI_RXCMD_LINE_STATE_SE0_C ) then
                 eopWait <= FSJ;
              end if;
            when FSJ =>
              if ( ulpiIsRxCmd( ulpiRx ) and ulpiRx.dat(1 downto 0) = ULPI_RXCMD_LINE_STATE_FS_J_C ) then
                 eopWait <= NONE;
              end if;
            when others =>
         end case;
      end if;
   end process P_EP_1_SEQ;

   P_EP_1_COMB  : process ( iidx, vidx ) is
   begin
      case vidx is
         when 1 =>
            txDataMst.dat <= d1(iidx);
            txDataMst.usr <= USB2_PID_DAT_DATA1_C;
            vend          <= d1'high;
         when 2 =>
            txDataMst.dat <= d2(iidx);
            vend          <= d2'high;
            txDataMst.usr <= USB2_PID_DAT_DATA0_C;
         when 3 =>
            txDataMst.dat <= d3(iidx);
            vend          <= d3'high;
            txDataMst.usr <= USB2_PID_DAT_DATA1_C;
         when 4 =>
            txDataMst.dat <= d3(iidx);
            txDataMst.usr <= USB2_PID_DAT_DATA0_C;
            vend          <= d3'high - 1;
         when others =>
            txDataMst.dat <= (others => 'U');
            txDataMst.usr <= USB2_PID_DAT_DATA0_C;
            vend          <= -1;
      end case;
   end process P_EP_1_COMB;

end architecture sim;
