-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- CDC NCM Endpoint with a FIFO interface. It also demonstrates
-- the implementation of a control interface via device requests (EP0).
-- Asynchronous clock domains are supported.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

-- CDC-NCM Endpoint

-- PACKET-SIZE NOTE: the OUT endpoint must be able handle the case when
--                   the NTH does *not* contain a block length (block length == 0).
--                   In this case the block is framed by the USB short-packet
--                   mechanism. HOWEVER, (table 3-1, 3.2.1), if the block size
--                   is and exact multiple of the maxPacketSize then *no* zero-
--                   length packet shall be sent!
--                   WE DO NOT HANDLE THIS CORNER CASE!! Thus, you must avoid
--                   that this may happen by setting the max. block size
--                   dwNtbOutMaxSize to a number that is not a multiple of
--                   the max. packet size

entity Usb2EpCDCNCMOut is
   generic (
      -- RAM parameters (ld_ram_depth are the width of the internal
      -- address pointers, i.e., ceil( log2( depth - 1 ) )
      -- for max. throughput the OUT ram must be big enough
      -- to hold at least two maximally sized packets.
      LD_RAM_DEPTH_G             : natural
   );
   port (
      usb2Clk                    : in  std_logic;
      usb2Rst                    : in  std_logic;

      -- ********************************************
      -- signals below here are in the usb2Clk domain
      -- ********************************************

      -- Data interface bulk endpoint pair
      usb2EpIb                   : in  Usb2EndpPairObType;
      usb2EpOb                   : out Usb2EndpPairIbType;

      -- write/read pointers in the usb2 clock domain
      -- (synchronizers to be instantiated outside of this module)
      ramWrPtrOb                 : out unsigned(LD_RAM_DEPTH_G downto 0);
      ramRdPtrIb                 : in  unsigned(LD_RAM_DEPTH_G downto 0);

      -- *******************************************************
      -- signals below here are in the epClk domain (if ASYNC_G)
      -- *******************************************************

      -- FIFO output clock (may be different from usb2Clk if ASYNC_G is true)
      epClk                      : in  std_logic;
      -- endpoint reset
      epRst                      : in  std_logic;

      -- write/read pointers in the epClk clock domain
      -- (synchronizers to be instantiated outside of this module)
      ramRdPtrOb                 : out unsigned(LD_RAM_DEPTH_G downto 0);
      ramWrPtrIb                 : in  unsigned(LD_RAM_DEPTH_G downto 0);

      -- FIFO Interface

      fifoDataOut                : out Usb2ByteType;
      -- when set then the transmitter must pad to min-length and append a CRC
      fifoCrcOut                 : out std_logic;
      fifoLastOut                : out std_logic;
      -- abort output (e.g., due to collision)
      fifoAbrtOut                : in  std_logic := '0';
      -- read-enable; data are *not* read while fifoEmptyOut is asserted.
      -- I.e., it is safe to hold fifoRenaOut steady until fifoEmptyOut
      -- is deasserted.
      fifoRenaOut                : in  std_logic;
      fifoEmptyOut               : out std_logic
   );
end entity Usb2EpCDCNCMOut;

architecture Impl of Usb2EpCDCNCMOut is

   subtype  RamIdxType   is unsigned( LD_RAM_DEPTH_G downto 0);

   constant NTH_OFF_LEN_C : RamIdxType := to_unsigned( 8, RamIdxType'length );
   constant NTH_OFF_NDP_C : RamIdxType := to_unsigned(10, RamIdxType'length );

   constant NDP_OFF_SIG_C : RamIdxType := to_unsigned( 3, RamIdxType'length );
   constant NDP_OFF_NXT_C : RamIdxType := to_unsigned( 6, RamIdxType'length );
   constant NDP_OFF_PTR_C : RamIdxType := to_unsigned( 8, RamIdxType'length );

   constant RAM_SIZE_C    : RamIdxType := to_unsigned( 2**LD_RAM_DEPTH_G, RamIdxType'length );

   type RdStateType is ( IDLE, READ_SDP_SIG, READ_SDP, READ_DGRAM_IDX, READ_DGRAM_LEN, READ_NXT, READ_DGRAM, ABORT );

   type RdRegType is record
      state          : RdStateType;
      rdPtr          : RamIdxType;
      sdpOff         : RamIdxType;
      sdpIdx         : RamIdxType;
      sdpIdxSaved    : RamIdxType;
      rdOff          : RamIdxType;
      dgramLen       : RamIdxType;
      tmpLo          : Usb2ByteType;
      dataHi         : boolean;
      needCrc        : std_logic;
   end record RdRegType;

   constant RD_REG_INIT_C : RdRegType := (
      state          => IDLE,
      rdPtr          => (others => '0'),
      sdpOff         => (others => '0'),
      sdpIdx         => (others => '0'),
      sdpIdxSaved    => (others => '0'),
      rdOff          => NTH_OFF_NDP_C,
      dgramLen       => (others => '0'),
      tmpLo          => (others => '0'),
      dataHi         => false,
      needCrc        => '0'
   );

   type WrStateType is ( HDR, LEN, FILL, WRITE_LEN_1, DONE );

   type WrRegType is record
      state          : WrStateType;
      wrPtr          : RamIdxType;
      wrTail         : RamIdxType;
      wrCnt          : RamIdxType;
      isFramed       : boolean;
      rdy            : std_logic;
      wasActive      : boolean;
   end record WrRegType;

   constant WR_REG_INIT_C : WrRegType := (
      state          => HDR,
      wrPtr          => (others => '0'),
      wrTail         => (others => '0'),
      wrCnt          => NTH_OFF_LEN_C - 1,
      isFramed       => false,
      rdy            => '0',
      wasActive      => false
   );

   signal rRd        : RdRegType := RD_REG_INIT_C;
   signal rInRd      : RdRegType := RD_REG_INIT_C;
   signal rWr        : WrRegType := WR_REG_INIT_C;
   signal rInWr      : WrRegType := WR_REG_INIT_C;

   signal rdData     : Usb2ByteType;
   signal wrData     : Usb2ByteType;

   signal rdAddr     : RamIdxType;
   signal wrAddr     : RamIdxType;

   signal ramRen     : std_logic;
   signal ramWen     : std_logic;

   signal onePktSz   : RamIdxType;
   signal twoPktSz   : RamIdxType;
   signal oneFits    : boolean;
   signal twoFit     : boolean;

   function toRamIdxType(constant a, b : Usb2ByteType) return RamIdxType is
      variable v : RamIdxType;
      constant x : unsigned(15 downto 0) := unsigned(a) & unsigned(b);
   begin
      v := resize( x, v'length );
      return v;
   end function toRamIdxType;

begin

   P_RD_COMB : process ( rRd, ramWrPtrIb, rdData, fifoRenaOut, fifoAbrtOut ) is
      variable v         : RdRegType;
      variable lenMinus1 : RamIdxType;
   begin
      v            := rRd;

      rdAddr       <= rRd.rdPtr + rRd.rdOff;
      ramRen       <= '1';
      fifoEmptyOut <= '1';
      lenMinus1    := rRd.dgramLen - 1;

      case ( rRd.state ) is
         when IDLE =>
            if ( ramWrPtrIb /= rRd.rdPtr ) then
               v.state  := READ_SDP;
               v.sdpIdx := NDP_OFF_PTR_C;
               v.dataHi := false;
               v.rdOff  := rRd.rdOff + 1;
            end if;

         when READ_NXT =>
            v.dataHi := not rRd.dataHi;
            if ( not rRd.dataHi ) then
               v.tmpLo := rdData;
            else
               v.rdPtr := rRd.rdPtr + toRamIdxType( rdData , rRd.tmpLo );
               v.rdOff := NTH_OFF_NDP_C;
               v.state := IDLE;
            end if;

         when READ_SDP =>
            v.dataHi := not rRd.dataHi;
            if ( not rRd.dataHi ) then
               v.tmpLo  := rdData;
            else
               v.sdpOff := toRamIdxType( rdData , rRd.tmpLo );
               if ( v.sdpOff = 0 ) then
                  rdAddr   <= rRd.rdPtr + NTH_OFF_LEN_C;
                  v.rdOff  := NTH_OFF_LEN_C + 1;
                  v.state  := READ_NXT;
               else
                  rdAddr   <= rRd.rdPtr + v.sdpOff + NDP_OFF_SIG_C;
                  v.state  := READ_SDP_SIG;
               end if;
            end if;

         when READ_SDP_SIG =>
            v.needCrc     := rdData(0);
            rdAddr        <= rRd.rdPtr  + rRd.sdpOff + rRd.sdpIdx;
            v.sdpIdx      := rRd.sdpIdx + 1;
            v.sdpIdxSaved := rRd.sdpIdx;
            v.state       := READ_DGRAM_IDX;

         when READ_DGRAM_IDX =>
            v.dataHi := not rRd.dataHi;
            if ( not rRd.dataHi ) then
               v.tmpLo  := rdData;
               rdAddr   <= rRd.rdPtr  + rRd.sdpOff + rRd.sdpIdx;
               v.sdpIdx := rRd.sdpIdx + 1;
            else
               v.rdOff := toRamIdxType( rdData , rRd.tmpLo );
               if ( v.rdOff = 0 ) then -- end of table
                  rdAddr   <= rRd.rdPtr + rRd.sdpOff + NDP_OFF_NXT_C;
                  v.rdOff  := rRd.sdpOff + NDP_OFF_NXT_C + 1;
                  v.sdpIdx := NDP_OFF_PTR_C;
                  v.state  := READ_SDP;
               else
                  rdAddr   <= rRd.rdPtr + rRd.sdpOff + rRd.sdpIdx;
                  v.state  := READ_DGRAM_LEN;
                  v.sdpIdx := rRd.sdpIdx + 1;
               end if;
            end if;

         when READ_DGRAM_LEN =>
            v.dataHi   := not rRd.dataHi; 
            if ( not rRd.dataHi ) then
               v.tmpLo  := rdData;
               rdAddr   <= rRd.rdPtr  + rRd.sdpOff + rRd.sdpIdx;
               v.sdpIdx := rRd.sdpIdx + 1;
            else
               v.dgramLen := toRamIdxType( rdData , rRd.tmpLo ) - 1;
               if ( v.dgramLen(v.dgramLen'left) = '1' ) then -- end of table
                  rdAddr   <= rRd.rdPtr + rRd.sdpOff + NDP_OFF_NXT_C;
                  v.rdOff  := rRd.sdpOff + NDP_OFF_NXT_C + 1;
                  v.sdpIdx := NDP_OFF_PTR_C;
                  v.state  := READ_SDP;
               else
                  v.state  := READ_DGRAM;
                  v.rdOff  := rRd.rdOff + 1;
               end if;
            end if;

         when READ_DGRAM =>
            fifoEmptyOut <= '0';
            ramRen       <= fifoRenaOut;
            if ( fifoRenaOut = '1' ) then
               v.dgramLen   := lenMinus1;
               v.rdOff      := rRd.rdOff    + 1;
               if ( lenMinus1( lenMinus1'left ) = '1' ) then
                  rdAddr        <= rRd.rdPtr + rRd.sdpOff + rRd.sdpIdx;
                  v.sdpIdx      := rRd.sdpIdx + 1;
                  v.sdpIdxSaved := rRd.sdpIdx;
                  v.state       := READ_DGRAM_IDX;
               end if;
            end if;
            if ( fifoAbrtOut = '1' ) then
               -- rdOff and dgramLen are reloaded by READ_DGRAM_IDX, READ_DGRAM_LEN
               v.sdpIdx      := rRd.sdpIdxSaved;
               v.sdpIdxSaved := rRd.sdpIdxSaved;
               v.state       := ABORT;
            end if;

         when ABORT =>
            rdAddr <= rRd.rdPtr + rRd.sdpOff + rRd.sdpIdx;
            if ( fifoAbrtOut <= '0' ) then
               v.sdpIdx := rRd.sdpIdx + 1;
               -- sdpIdxSaved is already = sdpIdx
               v.state  := READ_DGRAM_IDX;
            end if;
       
      end case;

      fifoDataOut <= rdData(7 downto 0);
      fifoLastOut <= lenMinus1( lenMinus1'left );

      rInRd <= v;
   end process P_RD_COMB;

   onePktSz <= resize( usb2EpIb.config.maxPktSizeOut, onePktSz'length );
   twoPktSz <= shift_left( onePktSz, 1 );

   oneFits <= ( RAM_SIZE_C - (rWr.wrPtr - ramRdPtrIb) >= onePktSz );
   twoFit  <= ( RAM_SIZE_C - (rWr.wrPtr - ramRdPtrIb) >= twoPktSz );

   -- We do flow control so that a max-packet always fits; thus, the ram
   -- can never be over-filled (assuming the Usb2Core follows protocol).

   -- Also: the core only starts sending (mstOut.vld) once we have signalled
   -- 'rdy'. So they won't start 'on their own'!
   --
   --  1) wait until we can accommodate at least one packet
   --  2) assert 'rdy'
   --  3) during the first beat they are sending (vld or don) = '1'
   --     check if we could accommodate a second packet:
   --     deassert rdy if we don't have the necessary space.
   --  4) if 'rdy' was deasserted wait for the current packet
   --     to be sent, then goto 1)

   P_WR_COMB : process ( rWr, oneFits, twoFit, usb2EpIb ) is
      variable wen    : std_logic;
      variable v      : WrRegType;
      variable sz     : unsigned(15 downto 0);
      variable active : boolean;
   begin
      v           := rWr;

      -- by default we store an item
      -- we revert that if necessary
      wen         := usb2EpIb.mstOut.vld;
      wrAddr      <= rWr.wrPtr;
      wrData      <= usb2EpIb.mstOut.dat;

      if ( wen = '1' ) then
         v.wrPtr  := rWr.wrPtr + 1;
         v.wrCnt  := rWr.wrCnt - 1;
      end if;

      -- size of the entire NTH
      sz          := resize( rWr.wrPtr, sz'length ) - resize( rWr.wrTail, sz'length );

      -- handshake
      active      := ( ( usb2EpIb.mstOut.vld or usb2EpIb.mstOut.don ) = '1' );
      v.wasActive := active;

      if ( ( rWr.rdy = '0' ) and not active ) then
         -- last transmission ended; check if we have space
         if ( oneFits ) then
            v.rdy := '1';
         end if;
      elsif ( active and not rWr.wasActive ) then
         -- first beat of a new packet; check if we could handle two
         if ( not twoFit ) then
            v.rdy := '0';
         end if;
      end if;

      case ( rWr.state ) is
         when HDR =>
            if ( wen = '1' ) then
               if ( rWr.wrCnt( rWr.wrCnt'left ) = '1' ) then
                  v.state             := LEN;
                  v.wrCnt(7 downto 0) := unsigned( usb2EpIb.mstOut.dat );
               end if;
            end if;

         when LEN =>
            if ( wen = '1' ) then
               v.wrCnt    := resize( unsigned( usb2EpIb.mstOut.dat ) & rWr.wrCnt(7 downto 0), v.wrCnt'length );
               v.wrCnt    := v.wrCnt - NTH_OFF_LEN_C - 2 - 1;
               v.isFramed := ( v.wrCnt( v.wrCnt'left ) = '1' );
               v.state    := FILL;
            end if;

         when WRITE_LEN_1 =>
            wrAddr   <= rWr.wrTail + NTH_OFF_LEN_C + 1;
            wrData   <= std_logic_vector(sz(15 downto 8));
            wen      := '1';
            v.state  := DONE;
            -- suppress normal writing
            v.wrPtr  := rWr.wrPtr;
            v.wrCnt  := NTH_OFF_LEN_C - 1;

         when FILL =>
            if ( rWr.isFramed ) then
               -- we dont' care about wrCnt here
               if ( usb2EpIb.mstOut.don = '1' ) then
                  -- store the block length for the read-side to pick up
                  wrAddr   <= rWr.wrTail + NTH_OFF_LEN_C;
                  wrData   <= std_logic_vector( sz(7 downto 0) );
                  v.state  := WRITE_LEN_1;
                  -- wrPtr is not advanced during this cycle
                  -- because due to don = '1' -> vld = '0'
                  wen      := '1';
                  -- make sure we don't accept anything from the core;
                  -- this probably could never happen because a packet
                  -- just ended and I don't see how the USB could receive
                  -- two packets back-to-back with no pause.
                  -- In any case we'l re-evaluate the space during the
                  -- next cycle and probably be back in business...
                  v.rdy    := '0';
               end if;
            elsif ( wen = '1' ) then
               if ( v.wrCnt( v.wrCnt'left ) = '1' ) then
                  v.state := DONE;
                  v.wrCnt := NTH_OFF_LEN_C - 1;
               end if;
            end if;

         when DONE =>
            v.wrTail := rWr.wrPtr;
            v.state  := HDR;

      end case;

      usb2EpOb.subOut.rdy <= rWr.rdy;
      ramWen                  <= wen;

      rInWr                   <= v;
   end process P_WR_COMB;

   P_RD_SEQ : process ( epClk ) is
   begin
      if ( rising_edge( epClk ) ) then
         if ( epRst = '1' ) then
            rRd <= RD_REG_INIT_C;
         else
            rRd <= rInRd;
         end if;
      end if;
   end process P_RD_SEQ; 

   P_WR_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( usb2Rst = '1' ) then
            rWr <= WR_REG_INIT_C;
         else
            rWr <= rInWr;
         end if;
      end if;
   end process P_WR_SEQ; 

   U_BRAM : entity work.Usb2Bram
      generic map (
         DATA_WIDTH_G => 8,
         ADDR_WIDTH_G => LD_RAM_DEPTH_G
      )
      port map (
         clka         => epClk,
         ena          => ramRen,
         addra        => rdAddr(LD_RAM_DEPTH_G - 1 downto 0),
         rdata        => rdData,

         clkb         => usb2Clk,
         enb          => ramWen,
         web          => ramWen,
         addrb        => wrAddr(LD_RAM_DEPTH_G - 1 downto 0),
         wdatb        => wrData
      );

   ramWrPtrOb <= rWr.wrTail;
   ramRdPtrOb <= rRd.rdPtr;

   fifoCrcOut <= rRd.needCrc;

end architecture Impl;
