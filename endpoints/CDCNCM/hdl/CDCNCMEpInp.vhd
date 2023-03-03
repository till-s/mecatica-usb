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

entity CDCNCMEpInp is
   generic (
      -- RAM parameters (ld_ram_depth are the width of the internal
      -- address pointers, i.e., ceil( log2( depth - 1 ) )
      -- for max. throughput the OUT ram must be big enough
      -- to hold at least two maximally sized packets.
      LD_RAM_DEPTH_G             : natural;
      -- only support a static maximum of datagrams
      MAX_DGRAMS_G               : natural;
      MAX_NTB_SIZE_G             : natural;
      EP_TIMER_WIDTH_G           : natural
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
      ramRdPtrOb                 : out unsigned(LD_RAM_DEPTH_G downto 0);
      ramWrPtrIb                 : in  unsigned(LD_RAM_DEPTH_G downto 0);

      -- *******************************************************
      -- signals below here are in the epClk domain (if ASYNC_G)
      -- *******************************************************

      -- FIFO output clock (may be different from usb2Clk if ASYNC_G is true)
      epClk                      : in  std_logic;
      -- endpoint reset
      epRst                      : in  std_logic;

      -- write/read pointers in the epClk clock domain
      -- (synchronizers to be instantiated outside of this module)
      ramWrPtrOb                 : out unsigned(LD_RAM_DEPTH_G downto 0);
      ramRdPtrIb                 : in  unsigned(LD_RAM_DEPTH_G downto 0);

      -- NTB Parameters
      maxNTBSize                 : in  unsigned(LD_RAM_DEPTH_G downto 0);
      -- actual timeout is 1 'timeout + 1' EP clock cycles
      timeout                    : in  unsigned(EP_TIMER_WIDTH_G - 1 downto 0);

      -- FIFO Interface

      fifoDataInp                : in  Usb2ByteType;
      fifoLastInp                : in  std_logic;
      -- write-enable; data are *not* read while fifoEmptyOut is asserted.
      -- I.e., it is safe to hold fifoRenaOut steady until fifoEmptyOut
      -- is deasserted.
      fifoWenaInp                : in  std_logic;
      fifoFullInp                : out std_logic;
      -- nothing is written while the fifo is busy
      fifoBusyInp                : out std_logic;
      -- approximate number of available slots (reports 1 less than is
      -- actually available) < 0 means the fifo is full.
      fifoAvailInp               : out signed(LD_RAM_DEPTH_G downto 0)
   );
end entity CDCNCMEpInp;

architecture Impl of CDCNCMEpInp is

   subtype  RamIdxType   is unsigned( LD_RAM_DEPTH_G downto 0);

   constant NTH_OFF_LEN_C : RamIdxType := to_unsigned( 8, RamIdxType'length );
   constant NTH_OFF_NDP_C : RamIdxType := to_unsigned(10, RamIdxType'length );

   constant NDP_OFF_SIG_C : RamIdxType := to_unsigned( 3, RamIdxType'length );
   constant NDP_OFF_NXT_C : RamIdxType := to_unsigned( 6, RamIdxType'length );
   constant NDP_OFF_PTR_C : RamIdxType := to_unsigned( 8, RamIdxType'length );

   constant NTH_SIZE_C    : natural    := 12;
   constant NDH_SIZE_C    : natural    :=  8;
   constant NDP_SIZE_C    : natural    := NDH_SIZE_C + 4 * (MAX_DGRAMS_G + 1); -- count end marker
   constant NDP_ALGN_C    : natural    := 4;

   -- every datagram is prepended with a 2-byte header for storing
   -- the final NTP length (which we don't know until the end but must
   -- communicate as a header to the read-size).
   -- We must reserve this for *every* datagram since we might hit the
   -- max NTB size in the middle of a datagram and cannot move the already
   -- written part.
   constant HDR_SPACE_C   : RamIdxType := to_unsigned( 2, RamIdxType'length );

   constant RAM_SIZE_C    : RamIdxType := to_unsigned( 2**LD_RAM_DEPTH_G, RamIdxType'length );

   type WrStateType is ( IDLE, WRITE, WRITE_H1, WRITE_H2 );

   type WrRegType is record
      state          : WrStateType;
      wrPtr          : RamIdxType;
      hdPtr          : RamIdxType;
      wrTail         : RamIdxType;
      nDgram         : natural range 0 to MAX_DGRAMS_G;
      -- sign bit is used to signal the timeout
      timer          : signed(EP_TIMER_WIDTH_G downto 0);
   end record WrRegType;

   constant WR_REG_INIT_C : WrRegType := (
      state          => IDLE,
      wrPtr          => HDR_SPACE_C,
      hdPtr          => (others => '0'),
      wrTail         => (others => '0'),
      nDgram         => 0,
      timer          => (others => '0')
   );

   type RdStateType is ( IDLE, GETL1, GETL2, NTH, PLD, NDP_HDR, NDP_PTRS );

   type U16Array    is array ( natural range <> ) of unsigned(15 downto 0);

   type RdRegType is record
      state          : RdStateType;
      rdPtr          : RamIdxType;
      ndpIdx         : unsigned(15 downto 0);
      seqNo          : unsigned(15 downto 0);
      dgramPtrs      : U16Array( 0 to MAX_DGRAMS_G);
      dgramIdx       : integer range -1 to MAX_DGRAMS_G;
      lastPtr        : unsigned(15 downto 0);
      cnt            : integer range -1 to NTH_SIZE_C - 1;
      vld            : std_logic;
      idx            : unsigned(15 downto 0);
      lst            : std_logic_vector(1 downto 0);
      hiByte         : boolean;
      sendLen        : boolean;
   end record RdRegType;

   constant RD_REG_INIT_C : RdRegType := (
      state          => IDLE,
      rdPtr          => (others => '0'),
      seqNo          => (others => '0'),
      ndpIdx         => (others => '0'),
      dgramPtrs      => (others => (others => '0')),
      dgramIdx       => 0,
      lastPtr        => (others => '0'),
      cnt            => 0,
      vld            => '0',
      idx            => (others => '0'),
      lst            => (others => '0'),
      hiByte         => false,
      sendLen        => false
   );

   signal rWr        : WrRegType := WR_REG_INIT_C;
   signal rInWr      : WrRegType := WR_REG_INIT_C;

   signal rRd        : RdRegType := RD_REG_INIT_C;
   signal rInRd      : RdRegType := RD_REG_INIT_C;

   signal rdData     : std_logic_vector(8 downto 0);
   signal wrData     : std_logic_vector(8 downto 0);

   signal rdAddr     : RamIdxType := (others => '0');
   signal empty      : std_logic;
   signal avail      : signed(RamIdxType'range);
   signal full       : std_logic;

   signal wrAddr     : RamIdxType;

   signal ramRen     : std_logic;
   signal ramWen     : std_logic;

   signal vldInp     : std_logic  := '0';

   function toRamIdxType(constant a, b : Usb2ByteType) return RamIdxType is
      variable v : RamIdxType;
      constant x : unsigned(15 downto 0) := unsigned(a) & unsigned(b);
   begin
      v := resize( x, v'length );
      return v;
   end function toRamIdxType;

   function maxPayload(constant mxSz : RamIdxType)
   return RamIdxType is
      variable v : RamIdxType;
   begin
      v :=  mxSz;
      -- subtract NTH and NDP reserving extra bytes since we must dword align the NDP
      v := v - to_unsigned( NTH_SIZE_C + NDP_SIZE_C + NDP_ALGN_C - 1, v'length );
      -- subtract 4 bytes per datagram
      v := v - shift_left( to_unsigned( MAX_DGRAMS_G, v'length ), 2 );
      return v;
   end function maxPayload;

   function timedout(constant x : WrRegType)
   return boolean is
   begin
      return x.timer( x.timer'left ) = '1';
   end function timedout;

   function ndpIdx(constant x : RdRegType)
   return unsigned is
      variable v : unsigned(15 downto 0);
   begin
      v := x.ndpIdx  + NTH_SIZE_C + NDP_ALGN_C - 1;
      v(1 downto 0) := "00";
      return v;
   end function ndpIdx;

   function blkSiz(constant x : RdRegType)
   return unsigned is
   begin
      return x.ndpIdx + NDP_SIZE_C;
   end function blkSiz;

begin

   empty                  <= toSl( ramWrPtrIb = rdAddr ); 

   -- report avail slots - 1; so the 'full' flag is just the sign
   avail                  <= signed(RAM_SIZE_C - 1 - (rWr.wrPtr - ramRdPtrIb));
   full                   <= avail( avail'left );

   -- read NTB from RAM and feed to usb2EpOb

   P_RD_COMB : process ( rRd, empty, rdData, usb2EpIb ) is
      variable v : RdRegType;
   begin
      v                   := rRd;

      usb2EpOb            <= USB2_ENDP_PAIR_IB_INIT_C;
      -- we always set a block size in NTH and thus do not frame IN transfers
      usb2EpOb.bFramedInp <= '1';
      usb2EpOb.mstInp.dat <= rdData(7 downto 0);
      usb2EpOb.mstInp.vld <= rRd.vld;
      usb2EpOb.mstInp.don <= '0';
      usb2EpOb.mstInp.err <= '0';
      ramRen              <= '0';

      case ( rRd.state ) is
         when IDLE =>
            ramRen <= '1';
            if ( empty = '0' ) then
               v.rdPtr := rRd.rdPtr + 1;
               v.state := GETL1;
            end if;
            v.dgramIdx := rRd.dgramPtrs'high;
            v.idx      := (others => '0');
            v.lst      := (others => '0');

         when GETL1 =>
            ramRen  <= '1';
            -- get payload size (LSB)
            v.ndpIdx( 7 downto 0) := unsigned( rdData( 7 downto 0 ) );
            v.rdPtr := rRd.rdPtr + 1;
            v.state := GETL1;

         when GETL2 =>
            ramRen  <= '1';
            -- get payload size (MSB)
            v.ndpIdx(15 downto 8) := unsigned( rdData( 7 downto 0 ) );
            v.rdPtr := rRd.rdPtr    + 1;
            v.cnt   := NTH_SIZE_C - 1;
            v.vld   := '1';
            v.seqNo := rRd.seqNo  + 1;

         when NTH =>
            if ( usb2EpIb.subInp.rdy = '1' ) then
               v.cnt := rRd.cnt - 1;
               v.idx := rRd.idx + 1;
               if ( v.cnt < 0 ) then
                  ramRen   <= '1';
                  v.rdPtr  := rRd.rdPtr + 1;
                  v.state  := PLD;
                  -- align payload size to NDP index
                  v.ndpIdx := ndpIdx( rRd );
               end if;
            end if;
            
            case ( rRd.cnt ) is
               -- signature
               when 11     => usb2EpOb.mstInp.dat <= x"4E";
               when 10     => usb2EpOb.mstInp.dat <= x"43";
               when  9     => usb2EpOb.mstInp.dat <= x"4D";
               when  8     => usb2EpOb.mstInp.dat <= x"48";
               -- header length
               when  7     => usb2EpOb.mstInp.dat <= x"0C";
               when  6     => usb2EpOb.mstInp.dat <= x"00";
               -- sequence number
               when  5     => usb2EpOb.mstInp.dat <= Usb2ByteType( rRd.seqNo(  7 downto 0 ) );
               when  4     => usb2EpOb.mstInp.dat <= Usb2ByteType( rRd.seqNo( 15 downto 8 ) );
               -- block size
               when  3     => usb2EpOb.mstInp.dat <= Usb2ByteType( blkSiz(rRd)(  7 downto 0 ) );
               when  2     => usb2EpOb.mstInp.dat <= Usb2ByteType( blkSiz(rRd)( 15 downto 8 ) );
               -- NDP index 
               when  1     => usb2EpOb.mstInp.dat <= Usb2ByteType( rRd.ndpIdx(  7 downto 0 ) );
               when others => usb2EpOb.mstInp.dat <= Usb2ByteType( rRd.ndpIdx( 15 downto 8 ) );
             
            end case;

         when PLD =>
            if ( usb2EpIb.subInp.rdy = '1' ) then
               -- latch and delay the 'lst' flag
               v.lst   := rRd.lst(rRd.lst'left - 1 downto 0) & rdData(8);
               ramRen  <= '1';
               v.rdPtr := rRd.rdPtr + 1;
               v.idx   := rRd.idx   + 1;
               if ( rRd.ndpIdx = rRd.idx ) then
                  -- end of datagrams reached
                  ramRen     <= '0';
                  v.state    := NDP_HDR;
                  v.idx      := to_unsigned( NDH_SIZE_C, v.idx'length ) - 1;
               elsif ( rRd.lst(0) = '1' ) then
                  -- record datagram start position
                  v.dgramPtrs( rRd.dgramIdx ) := rRd.idx;
                  v.dgramIdx                  := rRd.dgramIdx - 1;
               end if;
            end if;

         when NDP_HDR =>
            if ( usb2EpIb.subInp.rdy = '1' ) then
               v.cnt := rRd.cnt - 1;
               if ( v.cnt < 0 ) then
                  v.state    := NDP_PTRS;
                  v.dgramIdx := rRd.dgramPtrs'high;
                  v.lastPtr  := to_unsigned( NTH_SIZE_C, v.lastPtr'length ) + resize( HDR_SPACE_C, v.lastPtr'length );
               end if;
            end if;
            case ( rRd.cnt ) is
               -- signature
               when  7     => usb2EpOb.mstInp.dat <= x"4E";
               when  6     => usb2EpOb.mstInp.dat <= x"43";
               when  5     => usb2EpOb.mstInp.dat <= x"4D";
               when  4     => usb2EpOb.mstInp.dat <= x"30";
               -- header length
               when  3     => usb2EpOb.mstInp.dat <= Usb2ByteType( to_unsigned( NDP_SIZE_C, Usb2ByteType'length ) );
               when others => usb2EpOb.mstInp.dat <= x"00"; -- incudes next NDP pointer
            end case;

         when NDP_PTRS =>
            if ( usb2EpIb.subInp.rdy = '1' ) then
               v.hiByte   := not rRd.hiByte;
               if ( rRd.hiByte ) then
                  v.sendLen := not rRd.sendLen;
                  if ( not rRd.sendLen ) then
                     if ( rRd.dgramPtrs( rRd.dgramIdx ) /= 0 ) then
                        -- save this index
                        v.lastPtr                   := rRd.dgramPtrs( rRd.dgramIdx ) + resize( HDR_SPACE_C, v.lastPtr'length );
                        v.dgramPtrs( rRd.dgramIdx ) := rRd.dgramPtrs( rRd.dgramIdx ) - rRd.lastPtr;
                     end if;
                  else
                     v.dgramIdx                  := rRd.dgramIdx - 1;
                     if ( v.dgramIdx < 0 ) then
                        v.state := IDLE;
                        v.vld   := '0';
                     end if;
                  end if;
               end if;
            end if;
            if ( rRd.hiByte ) then
               usb2EpOb.mstInp.dat <= Usb2ByteType( rRd.dgramPtrs( rRd.dgramIdx )(15 downto 8) );
            else
               usb2EpOb.mstInp.dat <= Usb2ByteType( rRd.dgramPtrs( rRd.dgramIdx )( 7 downto 0) );
            end if;
      end case;

      rdAddr <= rRd.rdPtr;
      rInRd  <= v;
   end process P_RD_COMB;

   P_RD_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
         if ( usb2Rst = '1' ) then
            rRd <= RD_REG_INIT_C;
         else
            rRd <= rInRd;
         end if;
      end if;
   end process P_RD_SEQ; 

   -- read stream from fifo interface and store in RAM prepending a 
   -- 2-byte header to every datagram. This header is only required
   -- for storing the entire payload length of the NTB. Since we
   -- don't know how many datagrams will fit into one NTB we must
   -- reserve the header space for every datagram even when it turns
   -- out to be unused:
   --
   --
   --
   -- Here we see three datagrams (time starts at bottom) stored
   -- into RAM. Each has a [...] header reserved. At time '**'
   -- dat0, dat1 of the third dgram are already stored (dat2, dat3 not
   -- yet). If we find at time '**' that the third datagram doesn't fit
   -- and we dont' want to move ram contents around then we must
   -- reserve at every packet boundary because every packet could
   -- potentially be the first one of a new NTB
   --
   --      (dat3)
   --      (dat2)
   --       dat1   **   <= if, when 
   --       dat0
   --     [ .... ]  <--- will be the header of next NTB
   --       dat1    <--------------- last byte of first NTB
   --       dat0
   --     [ .... ]
   --       dat2
   --       dat1
   --       dat0
   --     [ .... ] <------ first byte of first NTB
   --
   -- once it has been decided that dgrams 1 + 2 fit (but 3 does
   -- not) the total length of 1 + 2 is stored in the header area
   -- of the first NTB for the reader to pick up (it must compute
   -- the index of the NDP and the total NTB length from this value)
   -- The reader
   --  1. fetches the payload length (dgrams 1 + 2) from the header
   --  2. computes NDP index (align NTH + dgrams 1 + 2 to 4-byte
   --     boundary) and NTB size ( = NDP index + NDP size)
   --  3. reader streams NTH to endpoint
   --  4. reader streams data (dgrams 1+2 including all the [dummy]
   --     headers to the endpoint.
   --  5. reader appends an aligned NDP; index pointers and dgram
   --     lengths are computed by the reader using end-of-frame
   --     markers (bit 8 in the fifo data) left by the writer.

   P_WR_COMB : process (
      rWr,
      full,
      fifoDataInp, fifoLastInp, fifoWenaInp,
      timeout, maxNTBSize
   ) is
      variable v     : WrRegType;
      variable size  : unsigned(15 downto 0);
   begin
      v           := rWr;
      fifoBusyInp <= '0';
      ramWen      <= '0';
      wrData      <= fifoLastInp & fifoDataInp;
      wrAddr      <= rWr.wrPtr;

      -- size of all the datagrams
      size        := resize( rWr.hdPtr - rWr.wrTail, size'length );

      case ( rWr.state ) is

         when IDLE | WRITE =>
            -- see if we can write
            if ( ( not full and fifoWenaInp ) = '1' ) then
               ramWen  <= '1';
               v.wrPtr := rWr.wrPtr + 1;
               if ( fifoLastInp = '1' ) then
                  -- end of datagram, this is safely part of the current NTB
                  v.nDgram := rWr.nDgram + 1;
                  v.hdPtr  := v.wrPtr;
                  v.wrPtr  := v.wrPtr + HDR_SPACE_C; -- reserve space for the next header
               end if;
               v.state := WRITE; -- not idle anymore after receiving something
            end if;
            if    (   ( v.wrPtr - rWr.wrTail >= maxPayload( maxNTBSize ) )
                   or ( v.nDgram             >= MAX_DGRAMS_G             )
                   or ( ( v.nDgram  >  0 ) and timedout( rWr ) )         ) then
               -- all reasons for terminating an NTB
               v.state := WRITE_H1;   
            elsif ( rWr.state = IDLE ) then
               -- nothing received yet, reset timer
               v.timer := resize( signed( timeout ), v.timer'length );
            else
               v.timer := rWr.timer - 1;
            end if;

         when WRITE_H1 =>
            fifoBusyInp <= '1'; -- hold off the source
            ramWen      <= '1';
            wrAddr      <= rWr.wrTail;
            wrData      <= '0' & Usb2ByteType( size(  7 downto 0 ) );
            v.state     := WRITE_H2;

         when WRITE_H2 =>
            fifoBusyInp <= '1'; -- hold off the source
            ramWen      <= '1';
            wrAddr      <= rWr.wrTail + 1;
            wrData      <= '0' & Usb2ByteType( size( 15 downto 8 ) );
            v.nDgram    := 0;
            -- yield to the reader
            v.wrTail    := rWr.hdPtr;
            v.state     := IDLE;

      end case;

      rInWr       <= v;
   end process P_WR_COMB;

   P_WR_SEQ : process ( epClk ) is
   begin
      if ( rising_edge( epClk ) ) then
         if ( epRst = '1' ) then
            rWr <= WR_REG_INIT_C;
         else
            rWr <= rInWr;
         end if;
      end if;
   end process P_WR_SEQ; 

   U_BRAM : entity work.Usb2Bram
      generic map (
         DATA_WIDTH_G => 9,
         ADDR_WIDTH_G => LD_RAM_DEPTH_G
      )
      port map (
         clka         => usb2Clk,
         ena          => ramRen,
         addra        => rdAddr(LD_RAM_DEPTH_G - 1 downto 0),
         rdata        => rdData,

         clkb         => epClk,
         enb          => ramWen,
         web          => ramWen,
         addrb        => wrAddr(LD_RAM_DEPTH_G - 1 downto 0),
         wdatb        => wrData
      );

   fifoAvailInp <= avail;
   fifoFullInp  <= full;
   ramWrPtrOb   <= rWr.wrTail;
   ramRdPtrOb   <= rdAddr;

end architecture Impl;
