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
      -- register ulpi 'nxt' and use a local buffer; we don't
      -- want to propagate a combinatorial 'nxt' out of this module
      nxtr        : std_logic;
      ulpiReq     : UlpiTxReqType;
      crc         : std_logic_vector(USB2_CRC16_POLY_C'range);
      don         : std_logic;
      err         : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      nxtr        => '0',
      ulpiReq     => ULPI_TX_REQ_INIT_C,
      crc         => (others => '0'),
      don         => '0',
      err         => '0'
   );

   signal r            : RegType := REG_INIT_C;
   signal rin          : RegType;

   signal crcInp       : std_logic_vector(7 downto 0);
   signal crcOut       : std_logic_vector(USB2_CRC16_POLY_C'range);

   signal ulpiTxReqLoc : UlpiTxReqType;

   attribute MARK_DEBUG of r            : signal is toStr(MARK_DEBUG_G);
   attribute MARK_DEBUG of ulpiTxReqLoc : signal is toStr(MARK_DEBUG_G);

begin

   P_COMB : process ( r, ulpiTxRep, txDataMst, crcOut ) is
      variable v : RegType;
   begin
      v             := r;
      v.don         := '0';

      txDataSub.rdy <= '0';

      if ( r.state = RUN ) then
         txDataSub.rdy <= r.nxtr;
      end if;

      v.nxtr           := ulpiTxRep.nxt;

      case ( r.state ) is
         when IDLE =>
            v.nxtr := '0';
            if ( ( txDataMst.vld or txDataMst.don ) = '1' ) then
               -- buffer the PID
               v.ulpiReq.dat    := ULPI_TXCMD_TX_C & txDataMst.usr(3 downto 0);
               v.err            := '0';
               -- the PID byte / TXCMD is not covered by the checksum
               v.crc            := USB2_CRC16_INIT_C;
               -- a zero length packet is signalled by a single cycle
               -- with 'don' = '1' and 'vld' = '0'
               if ( txDataMst.don = '0' ) then
                  v.state       := RUN;
               else
                  v.state       := CHK1;
               end if;
            end if;

-- pipeline for sending status
--  nxt   nxtr   stat   dout  dreg    val  stp    sending
--   0     1     CHK2   cshi           1            cshi
--         0     WAI    stat  cshi     1            cshi
--         0     WAI    stat  cshi     1            cshi
--   1     0     WAI    stat  cshi     1            cshi
--         1     WAI    stat           0    1       stat
--
--  nxt   nxtr   stat   dout  dreg    val  stp
--   1     1     CHK2   cshi           1            cshi
--         1     WAI    stat  cshi     0    1       stat
--
--   0     1     CHK2   cshi           1            cshi
--   1     0     WAI    stat  cshi     1            cshi
--         1     WAI    stat  cshi     0    1       stat
--
        when RUN | CHK1 | CHK2 =>

           v.ulpiReq.vld        := '1';

           if ( ulpiTxRep.don = '1' ) then
              -- aborted by PHY
              v.don             := '1';
              v.err             := '1';
              v.ulpiReq.vld     := '0';
              v.ulpiReq.dat     := (others => '0');
              v.nxtr            := '0';
              v.state           := DONE;
           elsif ( txDataMst.vld = '0'  or  r.state /= RUN ) then
              -- we can end up here with 'vld=1' if there was a vld=0
              -- cycle that caused us to send corrupted crc and abort
              if ( txDataMst.don /= '1' and r.state = RUN ) then
                 -- underrun
                 v.err          := '1';
                 v.state        := CHK1;
                 v.crc          := not r.crc;
                 -- if r.nxtr = '1' we would normally latch into
                 -- ulpiReq.dat but since we are aborting we don't
                 -- care what we send...
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
                 -- vld has just been deasserted but ULPI has
                 -- not yet fetchd the last data which are in ulpiReq.dat
                 -- append the crc as soon as they are ready
                 v.state := CHK1;
              end if;
           else
              if ( txDataMst.err = '1' ) then
                 -- remember error status
                 v.err          := '1';
              end if;
              if ( r.nxtr = '1' ) then
                 -- store input data in our local register and run crc
                 v.ulpiReq.dat  := txDataMst.dat;
                 v.crc          := crcOut xor ( x"00" & r.crc(15 downto 8 ) );
              end if;
           end if;

        when WAI =>
           if ( r.nxtr = '1' ) then
              -- send status during this cycle
              v.ulpiReq.vld     := '0';
              v.ulpiReq.dat     := (others => '0'); -- drive the bus idle
           end if;
           if ( v.ulpiReq.vld = '0' ) then
              -- make sure the data mux drives the registered all-zero
              -- byte on the bus
              v.nxtr := '0';
           end if;
           if ( ulpiTxRep.don = '1' ) then
              v.don             := '1';
              v.ulpiReq.dat     := (others => '0'); -- drive the bus idle
              v.nxtr            := '0';
              if ( v.ulpiReq.vld = '1' ) then
                 -- aborted before sending the last byte!
                 v.ulpiReq.vld  := '0';
                 v.err          := '1';
              end if;
              v.state           := DONE;
           end if;

        when DONE => -- allow 'don' flag to reset
           v.nxtr  := '0';
           v.state := IDLE;
      end case;

      -- need the pre-computed (v) 'vld' flag
      -- for correct timing of the status byte
      ulpiTxReqLoc.vld <= v.ulpiReq.vld;

      rin <= v;
   end process P_COMB;

   P_MUX : process ( r, txDataMst, ulpiTxReqLoc.vld ) is
   begin
      if ( r.nxtr = '1' ) then
         if ( ulpiTxReqLoc.vld = '0' ) then
            -- valid was just turned off -- send status
            ulpiTxReqLoc.dat <= (others => r.err);
         elsif ( r.state = CHK2 ) then
            ulpiTxReqLoc.dat <= not r.crc(15 downto 8);
         elsif ( txDataMst.vld = '0' ) then
            ulpiTxReqLoc.dat <= not r.crc( 7 downto 0);
         else
            ulpiTxReqLoc.dat <= txDataMst.dat;
         end if;
      else
         ulpiTxReqLoc.dat <= r.ulpiReq.dat;
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

   txDataSub.don <= r.don;
   txDataSub.err <= r.err;

   ulpiTxReq     <= ulpiTxReqLoc;

end architecture Impl;