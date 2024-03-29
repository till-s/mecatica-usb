-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;

-- Module that handles the USB packet protocol layer,
-- i.e., converting a low-level stream received from ULPI
-- into a USB packet (extracting PID and handling checksums)

entity Usb2PktRx is
   generic (
      MARK_DEBUG_G   : boolean := true
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic := '0';
      ulpiRx         : in  UlpiRxType;
      usb2Rx         : out Usb2RxType
   );
end entity Usb2PktRx;

architecture Impl of Usb2PktRx is

   type StateType is (WAIT_FOR_START, WAIT_FOR_EOP, WAIT_FOR_PID, TOK1, TOK2, DAT);

   type RxBufType is record
      dat         : std_logic_vector(7 downto 0);
      nxt         : std_logic;
   end record RxBufType;

   type RxBufArray is array(natural range 1 downto 0) of RxBufType;

   type RegType   is record
      state       : StateType;
      pktHdr      : Usb2PktHdrType;
      crc         : std_logic_vector(USB2_CRC5_POLY_C'range);
      extraDat    : boolean;
      -- buffer 2 bytes to hold off until CRC is in
      datPipe     : RxBufArray;
      datDon      : std_logic;
      datErr      : std_logic;
      rxCmd       : Usb2ByteType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => WAIT_FOR_START,
      pktHdr      => USB2_PKT_HDR_INIT_C,
      crc         => (others => '0'),
      extraDat    => false,
      datPipe     => (others => ( dat => (others => '0'), nxt => '0' )),
      datDon      => '0',
      datErr      => '0',
      rxCmd       => (others => '0')
   );

   signal r             : RegType := REG_INIT_C;
   signal rin           : RegType;

   signal crcInp        : std_logic_vector( 7 downto 0 );
   signal crc5Out       : std_logic_vector(15 downto 0 );
   signal crc16Out      : std_logic_vector(15 downto 0 );

   attribute MARK_DEBUG of r : signal is toStr(MARK_DEBUG_G);

begin

   P_COMB : process ( r, ulpiRx, crc5Out, crc16Out ) is
      variable v        : RegType;
      variable rxAct    : std_logic;
      variable isRxCmd  : boolean;
   begin
      v              := r;
      v.pktHdr.sof   := false;
      if ( r.pktHdr.vld = '1' ) then
         v.pktHdr.vld := '0';
         v.pktHdr.pid := USB2_PID_SPC_NONE_C;
      end if;
      rxAct          := ulpiRxActive( ulpiRx );
      v.datDon       := '0';
      isRxCmd        := ulpiIsRxCmd( ulpiRx );

      if ( isRxCmd ) then
         v.rxCmd := ulpiRx.dat;
      end if;

      if ( ( rxAct = '0' ) and ( r.state /= WAIT_FOR_START ) ) then
         if ( r.state = WAIT_FOR_EOP ) then
            if ( ( usb2PidIsHsk( r.pktHdr.pid ) or usb2PidIsTok( r.pktHdr.pid ) ) and not r.extraDat ) then
               -- handshake and token are only valid if delimited by EOP
               v.pktHdr.vld := '1';
               v.pktHdr.sof := (r.pktHdr.pid = USB2_PID_TOK_SOF_C);
            else
               -- this includes the case of a corrupted PID (=> SPC_NONE)
            end if;
         else
         -- FIXME unexpected EOP
         end if;
         if ( r.state = DAT ) then
            v.datDon := '1';
            for i in r.datPipe'range loop
               v.datPipe(i).nxt := '0';
            end loop;
            if ( r.crc = USB2_CRC16_CHCK_C ) then
               v.datErr := '0';
            end if;
         end if;
         v.state := WAIT_FOR_START;
      else
      case ( r.state ) is

         when WAIT_FOR_START =>
            if ( rxAct = '1' ) then
               v.state := WAIT_FOR_PID;
            end if;

         when WAIT_FOR_EOP =>
            -- state changed when not rxActive
            if ( ulpiRx.nxt = '1' ) then
               v.extraDat := true;
            end if;

         when WAIT_FOR_PID =>
            if ( ulpiRx.nxt = '1' ) then
               -- got it
               if ( ( ulpiRx.dat(7 downto 4) xor ulpiRx.dat(3 downto 0) ) /= "1111" ) then
                  v.state      := WAIT_FOR_EOP;
                  v.pktHdr.pid := USB2_PID_SPC_NONE_C;
               else
                  v.pktHdr.pid := ulpiRx.dat(3 downto 0);

                  if ( usb2PidIsTok( v.pktHdr.pid ) ) then
                     v.state := TOK1;
                     v.crc   := USB2_CRC5_INIT_C;
                  else
                     case ( usb2PidGroup( v.pktHdr.pid ) ) is
                        when USB2_PID_GROUP_HSK_C =>
                           v.extraDat     := false;
                           v.state        := WAIT_FOR_EOP;
                        when USB2_PID_GROUP_DAT_C =>
                           v.crc          := USB2_CRC16_INIT_C;
                           v.datErr       := '1'; -- reset when OK checksum is in
                           v.pktHdr.vld   := '1';
                           v.state        := DAT;
                        when others =>
                           -- token is already caught above
                           v.state        := WAIT_FOR_EOP;
                     end case;
                  end if;
               end if;
            end if;

         when TOK1 =>
            if ( ulpiRx.nxt = '1' ) then
               v.pktHdr.tokDat(7 downto 0) := ulpiRx.dat;
               v.state                     := TOK2;
               v.crc                       := crc5Out;
            end if;

         when TOK2 =>
            if ( ulpiRx.nxt = '1' ) then
               v.pktHdr.tokDat(10 downto 8) := ulpiRx.dat(2 downto 0);
               v.extraDat                   := false;
               v.state                      := WAIT_FOR_EOP;
               if ( crc5Out(USB2_CRC5_CHCK_C'range) /= USB2_CRC5_CHCK_C ) then
                  v.extraDat := true; -- will cause the bad token to be rejected
               end if;
            end if;

         when DAT =>
            if ( ulpiRx.nxt = '1' ) then
               v.datPipe(0)     := r.datPipe(1);
               v.datPipe(1).dat := ulpiRx.dat;
               v.datPipe(1).nxt := '1';
               v.crc            := crc16Out xor (x"00" & r.crc(15 downto 8));
            end if;
      end case;
      end if;

      usb2Rx            <= USB2_RX_INIT_C;
      usb2Rx.pktHdr     <= r.pktHdr;
      usb2Rx.mst.dat    <= r.datPipe(0).dat;
      usb2Rx.mst.vld    <= r.datPipe(0).nxt and ulpiRx.nxt;
      usb2Rx.mst.don    <= r.datDon;
      usb2Rx.mst.err    <= r.datErr;
      usb2Rx.rxCmd      <= v.rxCmd;
      usb2Rx.isRxCmd    <= isRxCmd;
      usb2Rx.rxActive   <= ( rxAct = '1' );

      rin               <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   crcInp <= ulpiRx.dat xor r.crc(7 downto 0);

   U_CRC5 : entity work.UsbCrcTbl
      generic map (
         POLY_G => USB2_CRC5_POLY_C
      )
      port map (
         x   => crcInp,
         y   => crc5Out
      );

   U_CRC16 : entity work.UsbCrcTbl
      generic map (
         POLY_G => USB2_CRC16_POLY_C
      )
      port map (
         x   => crcInp,
         y   => crc16Out
      );

end architecture Impl;
