library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;

entity Usb2PktTx is
   generic (
      MARK_DEBUG_G   : boolean := true
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic := '0';
      ulpiTxReq      : out UlpiTxReqType;
      ulpiTxRep      : in  UlpiTxRepType;
      txDataMst      : in  Usb2StrmMstType;
      txDataSub      : out Usb2StrmSubType
   );
end entity Usb2PktTx;

architecture Impl of Usb2PktTx is

   type StateType is (IDLE, RUN, CHK1, CHK2, WAI, DONE);

   type RegType   is record
      state       : StateType;
      ulpiReq     : UlpiTxReqType;
      crc         : std_logic_vector(USB2_CRC16_POLY_C'range);
      nxtr        : std_logic;
      don         : std_logic;
      err         : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      ulpiReq     => ULPI_TX_REQ_INIT_C,
      crc         => (others => '0'),
      nxtr        => '0',
      don         => '0',
      err         => '0'
   );

   signal r      : RegType := REG_INIT_C;
   signal rin    : RegType;

   signal crcInp : std_logic_vector(7 downto 0);
   signal crcOut : std_logic_vector(USB2_CRC16_POLY_C'range);
begin

   P_COMB : process ( r, ulpiTxRep, txDataMst, crcOut ) is
      variable v : RegType;
   begin
      v             := r;
      v.don         := '0';

      txDataSub.rdy <= '0';

      -- register ulpi 'nxt' and use a local buffer; we don't
      -- want to propagate a combinatorial 'nxt' out of this module
      v.nxtr        := ulpiTxRep.nxt;

      case ( r.state ) is
         when IDLE =>
            if ( txDataMst.vld = '1' ) then
               -- buffer the first item
               txDataSub.rdy    <= '1';
               v.ulpiReq.dat    := txDataMst.dat;
               v.ulpiReq.vld    := '1';
               v.state          := RUN;
               v.err            := '0';
               -- the PID byte is not covered by the checksum
               v.crc            := USB2_CRC16_INIT_C;
            end if;

        when RUN | CHK1 | CHK2 =>

           if ( r.state = RUN ) then
              txDataSub.rdy        <= r.nxtr;
           end if;

           if ( ulpiTxRep.don = '1' ) then
              v.don             := '1';
              v.err             := '1';
              v.ulpiReq.vld     := '0';
              v.state           := DONE;
           elsif ( txDataMst.vld = '0' ) then
              if ( txDataMst.don /= '1' and r.state = RUN ) then
                 -- underrun
                 v.err          := '1';
                 v.don          := '1';
                 v.state        := DONE;
              elsif ( r.nxtr = '1' ) then
                 if    ( r.state = CHK2 ) then
                    v.state       := WAI;
                    v.ulpiReq.dat := not r.crc(15 downto 8);
                 else
                    -- if we're still in RUN state then we must present
                    -- the 1st checksum byte still in this state!
                    v.state       := CHK2;
                    -- register in case
                    v.ulpiReq.dat := not r.crc(7  downto 0);
                 end if;
              elsif ( r.state = RUN ) then
                 v.state := CHK1;
              end if;
           else
              if ( txDataMst.err = '1' ) then
                 -- remember error status
                 v.err          := '1';
              end if;
              if ( r.nxtr = '1' ) then
                 -- store input data in our local register
                 v.ulpiReq.dat  := txDataMst.dat;
                 v.crc          := crcOut xor ( x"00" & r.crc(15 downto 8 ) );
              end if;
           end if;

        when WAI =>
           if ( ulpiTxRep.don = '1' ) then
              v.don             := '1';
              v.ulpiReq.vld     := '0';
              v.state           := DONE;
           end if;

        when DONE => -- allow 'don' flag to reset
           v.state := IDLE;
      end case;

      rin <= v;
   end process P_COMB;

   P_MUX : process ( r, txDataMst ) is
   begin
      if ( r.nxtr = '1' ) then
         if ( r.state = CHK2 ) then
            ulpiTxReq.dat <= not r.crc(15 downto 8);
         elsif ( txDataMst.vld = '0' ) then
            ulpiTxReq.dat <= not r.crc( 7 downto 0);
         else
            ulpiTxReq.dat <= txDataMst.dat;
         end if;
      else
         ulpiTxReq.dat <= r.ulpiReq.dat;
      end if;
   end process P_MUX;

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

   crcInp <= txDataMst.dat xor r.crc(7 downto 0);

   -- the first idea to share CRC computation with the RX path
   -- (via readback register) does not work -- we cannot tolerate
   -- the 2-cycle delay because there is no way to throttle the
   -- UPLI transmitter :-(
   U_CRC16 : entity work.UsbCrcTbl
      generic map (
         POLY_G => USB2_CRC16_POLY_C
      )
      port map (
         x      => crcInp,
         y      => crcOut
      );

   ulpiTxReq.vld <= r.ulpiReq.vld;

   txDataSub.don <= r.don;
   txDataSub.err <= r.err;

end architecture Impl;
