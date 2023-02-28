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

entity Usb2EpCDCNCM is
   generic (
      -- interface number of control interface
      CTL_IFC_NUM_G              : natural;
      ASYNC_G                    : boolean   := false;
      -- FIFO parameters (ld_fifo_depth are the width of the internal
      -- address pointers, i.e., ceil( log2( depth - 1 ) )
      LD_FIFO_DEPTH_INP_G        : natural;
      -- for max. throughput the OUT fifo must be big enough
      -- to hold at least two maximally sized packets.
      LD_RAM_DEPTH_OUT_G         : natural;
      -- add an output register to the OUT FIFO (to help timing)
      FIFO_OUT_REG_OUT_G         : boolean   := false;
      -- width of the IN fifo timer (counts in 60MHz cycles)
      FIFO_TIMER_WIDTH_G         : positive  := 1;
      CARRIER_DFLT_G             : std_logic := '1';
      MARK_DEBUG_G               : boolean   := false
   );
   port (
      usb2Clk                    : in  std_logic;
      usb2Rst                    : in  std_logic;

      -- ********************************************
      -- signals below here are in the usb2Clk domain
      -- ********************************************

      -- EP0 interface
      usb2Ep0ReqParam            : in  Usb2CtlReqParamType := USB2_CTL_REQ_PARAM_INIT_C;
      usb2Ep0CtlExt              : out Usb2CtlExtType      := USB2_CTL_EXT_NAK_C;

      -- Data interface bulk endpoint pair
      usb2DataEpIb               : in  Usb2EndpPairObType;
      usb2DataEpOb               : out Usb2EndpPairIbType;

      -- Notification (interrupt) endpoint pair
      usb2NotifyEpIb             : in  Usb2EndpPairObType  := USB2_ENDP_PAIR_OB_INIT_C;
      usb2NotifyEpOb             : out Usb2EndpPairIbType  := USB2_ENDP_PAIR_IB_INIT_C;

      -- note that this is in the USB2 clock domain; if you really
      -- need this (and if ASYNC_G) you need to sync from the epClk 
      -- yourself...
      packetFilter               : out std_logic_vector(4 downto 0);

      speedInp                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );
      speedOut                   : in  unsigned(31 downto 0) := to_unsigned( 100000000, 32 );

      -- FIFO control (in usb2Clk domain!)
      --
      -- number of slots in the IN direction that need to be accumulated
      -- before USB is notified (improves throughput at the expense of latency)
      fifoMinFillInp             : in  unsigned(LD_FIFO_DEPTH_INP_G - 1 downto 0) := (others => '0');
      -- if more then 'timeFillInp' clock cycles expire since the last
      -- item was written to the IN fifo the contents are passed to USB (even
      -- if 'minFillInp' has not been reached). Similary to termios'
      -- VMIN+VTIME.
      --  - All-ones waits indefinitely.
      --  - Time may be reduced while the timer is running.
      fifoTimeFillInp            : in  unsigned(FIFO_TIMER_WIDTH_G - 1 downto 0)  := (others => '0');

      -- *******************************************************
      -- signals below here are in the epClk domain (if ASYNC_G)
      -- *******************************************************

      -- FIFO output clock (may be different from usb2Clk if ASYNC_G is true)
      epClk                      : in  std_logic;
      -- endpoint reset from USB
      epRstOut                   : out std_logic;

      -- FIFO Interface

      fifoDataInp                : in  Usb2ByteType;
      -- write-enable; data are *not* written while fifoFullInp is asserted.
      -- I.e., it is safe to hold fifoDataInp/fifoWenaInp steady until fifoFullInp
      -- is deasserted.
      fifoDonInp                 : in  std_logic;
      fifoWenaInp                : in  std_logic;
      fifoFullInp                : out std_logic;
      -- (approximate) fill level. The deassertion of fifoFullInp and the value of
      -- fifoFilledInp are delayed by several cycles of the slower clock if ASYNC_G.
      fifoFilledInp              : out unsigned(LD_FIFO_DEPTH_INP_G downto 0);

      fifoDataOut                : out Usb2ByteType;
      fifoDataLst                : out std_logic;
      -- read-enable; data are *not* read while fifoEmptyOut is asserted.
      -- I.e., it is safe to hold fifoRenaOut steady until fifoEmptyOut
      -- is deasserted.
      fifoRenaOut                : in  std_logic;
      fifoEmptyOut               : out std_logic;

      carrier                    : in  std_logic := CARRIER_DFLT_G
   );

   attribute MARK_DEBUG of usb2NotifyEpOb : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of packetFilter   : signal is toStr( MARK_DEBUG_G );
   attribute MARK_DEBUG of carrier        : signal is toStr( MARK_DEBUG_G );

end entity Usb2EpCDCNCM;

architecture Impl of Usb2EpCDCNCM is

begin

   B_OUT : block is

      subtype RamIdxType is unsigned( LD_RAM_DEPTH_OUT_G downto 0);

      constant NTH_OFF_LEN_C : RamIdxType := to_unsigned(10, RamIdxType'length );
      constant NTH_OFF_NDP_C : RamIdxType := to_unsigned(12, RamIdxType'length );

      constant NDP_OFF_SIG_C : RamIdxType := to_unsigned( 3, RamIdxType'length );
      constant NDP_OFF_NXT_C : RamIdxType := to_unsigned( 6, RamIdxType'length );
      constant NDP_OFF_PTR_C : RamIdxType := to_unsigned( 8, RamIdxType'length );


      type RdStateType is ( IDLE, READ_SDP_SIG, READ_SDP, READ_DGRAM_IDX, READ_DGRAM_LEN, READ_NXT, READ_DGRAM );

      type RdRegType is record
         state          : RdStateType;
         rdPtr          : RamIdxType;
         sdpOff         : RamIdxType;
         sdpIdx         : RamIdxType;
         rdOff          : RamIdxType;
         dgramLen       : RamIdxType;
         tmpLo          : Usb2ByteType;
         dataHi         : boolean;
         haveCrc        : boolean;
      end record RdRegType;

      constant RD_REG_INIT_C : RdRegType := (
         state          => IDLE,
         rdPtr          => (others => '0'),
         sdpOff         => (others => '0'),
         sdpIdx         => (others => '0'),
         rdOff          => NTH_OFF_NDP_C,
         dgramLen       => (others => '0'),
         tmpLo          => (others => '0'),
         dataHi         => false,
         haveCrc        => false
      );

      type WrStateType is ( HDR, LEN, FILL );

      type WrRegType is record
         state          : WrStateType;
         wrPtr          : RamIdxType;
         wrTail         : RamIdxType;
         wrCnt          : RamIdxType;
         isFramed       : boolean;
      end record WrRegType;

      constant WR_REG_INIT_C : WrRegType := (
         state          => HDR,
         wrPtr          => (others => '0'),
         wrTail         => (others => '0'),
         wrCnt          => NTH_OFF_LEN_C - 1,
         isFramed       => false
      );

      signal rRd    : RdRegType := RD_REG_INIT_C;
      signal rInRd  : RdRegType := RD_REG_INIT_C;
      signal rWr    : WrRegType := WR_REG_INIT_C;
      signal rInWr  : WrRegType := WR_REG_INIT_C;

      signal rdData : Usb2ByteType;

      signal rdAddr : RamIdxType;

      signal wrPtr  : RamIdxType := (others => '0');
      signal rdPtr  : RamIdxType := (others => '0');

      signal ramRen : std_logic;
      signal ramWen : std_logic;

      function toRamIdxType(constant a, b : Usb2ByteType) return RamIdxType is
         variable v : RamIdxType;
      begin
         v(15 downto 8) := unsigned( a );
         v( 7 downto 0) := unsigned( b );
         return v;
      end function toRamIdxType;

   begin

      P_OUT_RD_COMB : process ( rRd, wrPtr, rdData, fifoRenaOut ) is
         variable v : RdRegType;
      begin
         v            := rRd;

         rdAddr       <= rRd.rdPtr + rRd.rdOff;
         ramRen       <= '1';

         fifoEmptyOut <= '1';

         case ( rRd.state ) is
            when IDLE =>
               if ( wrPtr /= rRd.rdPtr ) then
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
               v.haveCrc     := (rdData(0) = '1');
               rdAddr        <= rRd.rdPtr  + rRd.sdpOff + rRd.sdpIdx;
               v.sdpIdx      := rRd.sdpIdx + 1;
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
                  if ( rRd.haveCrc ) then
                     v.dgramLen := v.dgramLen - 4;
                  end if;
                  if ( v.dgramLen(v.dgramLen'left) = '1' ) then -- end of table
                     rdAddr   <= rRd.rdPtr + rRd.sdpOff + NDP_OFF_NXT_C;
                     v.rdOff  := rRd.sdpOff + NDP_OFF_NXT_C + 1;
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
                  v.dgramLen   := rRd.dgramLen - 1;
                  v.rdOff      := rRd.rdOff    + 1;
                  if ( v.dgramLen( v.dgramLen'left ) = '1' ) then
                     rdAddr    <= rRd.rdPtr + rRd.sdpOff + rRd.sdpIdx;
                     v.sdpIdx  := rRd.sdpIdx + 1;
                     v.state   := READ_DGRAM_IDX;
                  end if;
               end if;
         end case;

         fifoDataOut <= rdData(7 downto 0);
         fifoDataLst <= v.dgramLen( v.dgramLen'left );

         rInRd <= v;
      end process P_OUT_RD_COMB;

      P_OUT_WR_COMB : process ( rWr, rdPtr, usb2DataEpIb ) is
         variable wen : std_logic;
         variable rdy : std_logic;
         variable v   : WrRegType;
      begin
         v       := rWr;
         v.wrPtr := rWr.wrPtr + 1;
         wen     := usb2DataEpIb.mstOut.vld;
         rdy     := '1';
         if ( v.wrPtr = rdPtr ) then
            -- full
            wen     := '0';
            rdy     := '0';
            v.wrPtr := rWr.wrPtr;
         end if;

         case ( rWr.state ) is
            when HDR =>
               if ( wen = '1' ) then
                  if ( rWr.wrCnt( rWr.wrCnt'left ) = '1' ) then
                     v.state             := LEN;
                     v.wrCnt(7 downto 0) := unsigned( usb2DataEpIb.mstOut.dat );
                  else
                     v.wrCnt             := rWr.wrCnt - 1;
                  end if;
               end if;

            when LEN =>
               if ( wen = '1' ) then
                  v.wrCnt(15 downto 8)   := unsigned( usb2DataEpIb.mstOut.dat );
                  v.wrCnt                := v.wrCnt - NTH_OFF_LEN_C - 2;
                  v.isFramed             := ( v.wrCnt( v.wrCnt'left ) = '1' );
                  v.state                := FILL;
               end if;

            when FILL =>
               if ( rWr.isFramed ) then
                  if ( ( usb2DataEpIb.mstOut.don and rdy ) = '1' ) then
                     v.state  := HDR;
                  end if;
               elsif ( wen = '1' ) then
                  v.wrCnt := rWr.wrCnt - 1;
                  if ( v.wrCnt( v.wrCnt'left ) = '1' ) then
                     v.state := HDR;
                  end if;
               end if;
               if ( v.state = HDR ) then
                  v.wrCnt  := NTH_OFF_LEN_C - 1;
                  v.wrTail := rWr.wrPtr;
               end if;

         end case;

         usb2DataEpOb.subOut.rdy <= rdy;
         ramWen                  <= wen;

         rInWr                   <= v;
      end process P_OUT_WR_COMB;

   end block B_OUT;
   

end architecture Impl;
