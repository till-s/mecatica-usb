library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;

entity Usb2PktRx is
   --generic (
   --);
   port (
      clk            : in  std_logic;
      rst            : in  std_logic := '0';
      ulpiRx         : in  UlpiRxType;
      pktHdr         : out Usb2PktHdrType
   );
end entity Usb2PktRx;

architecture Impl of Usb2PktRx is

   type StateType is (WAIT_FOR_START, WAIT_FOR_EOP, WAIT_FOR_PID, T1, T2, D1, D2, D3);

   constant RXCMD_RX_ACTIVE_BIT_C : natural := 4;

   function rxActive(constant x : in UlpiRxType) return boolean is
   begin
      if ( x.dir = '0' ) then
         return false;
      end if;
      if ( x.trn = '1' ) then
         -- turn-around cycle that may have aborted a reg-read
         return x.nxt = '1';
      end if;
      return ( x.nxt = '1' ) or ( x.dat(RXCMD_RX_ACTIVE_BIT_C) = '1' );
   end function rxActive;

   type RegType   is record
      state       : StateType;
      pktHdr      : Usb2PktHdrType;
      crc         : std_logic_vector(USB2_CRC5_POLY_C'range);
      extraDat    : boolean;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => WAIT_FOR_START,
      pktHdr      => USB2_PKT_HDR_INIT_C,
      crc         => (others => '1'),
      extraDat    => false
   );

   signal r             : RegType := REG_INIT_C;
   signal rin           : RegType;

   signal crc5Inp       : std_logic_vector( 7 downto 0 ); 
   signal crc5Out       : std_logic_vector(15 downto 0 );
begin

   P_COMB : process ( r, ulpiRx, crc5Out ) is
      variable v        : RegType;
      variable rxAct    : boolean;
   begin
      v              := r;
      if ( r.pktHdr.valid = '1' ) then
         v.pktHdr.valid := '0';
         v.pktHdr.pid   := USB_PID_SPC_NONE;
      end if;
      rxAct          := rxActive( ulpiRx );

      if ( not rxAct and r.state /= WAIT_FOR_START ) then
         if ( r.state = WAIT_FOR_EOP ) then
            if ( usb2PidIsHsk( r.pktHdr.pid ) and not r.extraDat ) then
               -- handshake is only valid if delimited by EOP
               v.pktHdr.valid := '1'; 
            end if;
         else
         -- FIXME unexpected EOP
         end if;
         v.state := WAIT_FOR_START;
      else
      case ( r.state ) is

         when WAIT_FOR_START =>
            if ( rxAct ) then
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
                  v.state := WAIT_FOR_EOP;
                  -- FIXME ERROR
               else
                  v.pktHdr.pid := ulpiRx.dat(7 downto 4);
                  case ( usb2PidGroup( v.pktHdr.pid ) ) is
                     when USB_PID_GROUP_TOK =>
                        -- TOKEN PID
                        v.state := T1;
                        v.crc   := USB2_CRC5_INIT_C;
                     when USB_PID_GROUP_HSK =>
                        v.extraDat := false;
                        v.state    := WAIT_FOR_EOP;
                     when USB_PID_GROUP_DAT =>
                        v.state := D1;
                        v.crc   := USB2_CRC16_INIT_C;
                     when others =>
                        -- FIXME not implemented
                        v.state := WAIT_FOR_EOP;
                  end case;
               end if;
            end if;

         when T1 =>
            if ( ulpiRx.nxt = '1' ) then
               v.pktHdr.tokDat(7 downto 0) := ulpiRx.dat;
               v.state                     := T2;
               v.crc                       := crc5Out;
            end if;

         when T2 =>
            if ( ulpiRx.nxt = '1' ) then
               v.pktHdr.tokDat(10 downto 8) := ulpiRx.dat(2 downto 0);
               v.state                      := WAIT_FOR_EOP;
               if ( crc5Out(USB2_CRC5_CHCK_C'range) = USB2_CRC5_CHCK_C ) then
                  v.pktHdr.valid := '1';
               end if;
            end if;

         when D1 | D2 | D3 =>
                
      end case;
      end if;

      rin <= v;
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

   crc5Inp <= ulpiRx.dat xor r.crc(7 downto 0);

   U_CRC5 : entity work.UsbCrcTbl
      generic map (
         POLY_G => USB2_CRC5_POLY_C
      )
      port map (
         x   => crc5Inp,
         y   => crc5Out
      );

   pktHdr <= r.pktHdr;

end architecture Impl;
