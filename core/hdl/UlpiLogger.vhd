-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;

-- Log ULPI activity to memory

entity UlpiLogger is
   generic (
      LD_MEM_DEPTH_G : natural := 12;
      MARK_DEBUG_G   : boolean := true;
      DROP_SOF_G     : boolean := true
   );
   port (
      ulpiClk        : in  std_logic;
      ulpiRx         : in  UlpiRxType;
      -- assert for 1 cycle to halt logging
      -- memory contents are then streamed out;
      -- once that is complete the logging resumes
      halt           : in  std_logic;
      -- pause writing (completes logging ongoing transfer)
      pause          : in  std_logic := '0';
      -- data(lsb) and flags(msb) are streamed in little-endian
      -- byte order
      datOut         : out std_logic_vector(7 downto 0);
      -- the usual valid/ready/last handshake also used
      -- by axi streams
      datVld         : out std_logic;
      datLst         : out std_logic;
      datRdy         : in  std_logic
   );
end entity UlpiLogger;

architecture rtl of UlpiLogger is

   -- async not implemented yet
   constant ASYNC_READ_G : boolean := false;

   constant MARK_DEBUG_C : string  := ite( MARK_DEBUG_G, "TRUE", "FALSE" );

   type WrStateType is ( IDLE, LOG_RX, LOG_TX, LOG_RD );

   constant MEM_WIDTH_C  : natural := 9;

   subtype MemWord  is std_logic_vector( MEM_WIDTH_C - 1 downto 0 );
   type    MemArray is array(0 to 2**LD_MEM_DEPTH_G - 1) of MemWord;

   type WrRegType is record
      state       : WrStateType;
      haveRx      : boolean;
      wptr        : unsigned(LD_MEM_DEPTH_G - 1 downto 0);
      reqTgl      : std_logic;
      lstHalt     : std_logic;
      isSOF       : boolean;
      isPID       : boolean;
   end record WrRegType;

   constant WR_REG_INIT_C : WrRegType := (
      state       => IDLE,
      haveRx      => false,
      wptr        => (others => '0'),
      reqTgl      => '0',
      lstHalt     => '0',
      isSOF       => false,
      isPID       => true
   );

   type RdRegType is record
      rptr        : unsigned(LD_MEM_DEPTH_G - 1 downto 0);
      even        : std_logic;
      vld         : std_logic;
      repTgl      : std_logic;
      hiByte      : std_logic_vector(7 downto 0);
   end record RdRegType;

   constant RD_REG_INIT_C : RdRegType := (
      rptr        => (others => '0'),
      even        => '1',
      vld         => '0',
      repTgl      => '0',
      hiByte      => (others => '0')
   );

   signal memory : MemArray  := (others => (others => '0'));

   signal rdDat  : MemWord   := (others => '0');
   signal wrPtr  : unsigned(LD_MEM_DEPTH_G - 1 downto 0);
   signal rdClk  : std_logic;
   signal wrDat  : MemWord;
   signal memWen : std_logic := '1';

   signal reqTgl : std_logic;
   signal repTgl : std_logic;

   signal rWr    : WrRegType   := WR_REG_INIT_C;
   signal rWrIn  : WrRegType   := WR_REG_INIT_C;
   signal rRd    : RdRegType   := RD_REG_INIT_C;
   signal rRdIn  : RdRegType   := RD_REG_INIT_C;

   attribute MARK_DEBUG of rWr    : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of memWen : signal is MARK_DEBUG_C;
   attribute MARK_DEBUG of wrDat  : signal is MARK_DEBUG_C;

begin

   G_SYNC : if ( not ASYNC_READ_G ) generate
   begin
      rdClk  <= ulpiClk;
      reqTgl <= rWr.reqTgl;
      wrPtr  <= rWr.wptr;
      repTgl <= rRd.repTgl;
   end generate G_SYNC;

   U_MEM : entity work.Usb2Bram
      generic map (
         DATA_WIDTH_G => MEM_WIDTH_C,
         ADDR_WIDTH_G => LD_MEM_DEPTH_G
      )
      port map (
         clka         => ulpiClk,
         ena          => '1',
         cea          => '1',
         wea          => memWen,
         addra        => rWr.wptr,
         rdata        => open,
         wdata        => wrDat,

         clkb         => rdClk,
         enb          => '1',
         ceb          => '1',
         web          => '0',
         addrb        => rRd.rptr,
         rdatb        => rdDat,
         wdatb        => open
      );


   P_WR_COMB : process ( rWr, ulpiRx, halt, repTgl, pause ) is
      variable v   : WrRegType;
      variable wen : std_logic;
   begin
      v         := rWr;

      v.lstHalt := halt;
      wen       := '0';
      wrDat     <= ulpiRx.dir & ulpiRx.dat;

      if ( repTgl /= rWr.reqTgl ) then
         -- readout active
      else
         case ( rWr.state ) is

            when IDLE   =>
               v.haveRx := false;
               v.isPID  := true;
               v.isSOF  := false;

               if ( pause = '0' ) then
                  if    ( ( ulpiRx.dir and ulpiRx.trn ) = '1' ) then
                     v.state  := LOG_RX;
                  elsif ( ( ulpiRx.dir = '0' ) and ( ulpiRx.dat /= x"00" ) ) then
                     v.state := LOG_TX;
                     -- nxt is not asserted during this cycle; don't write
                  end if;
               end if;

            when LOG_RX =>
               if ( ulpiRxActive( ulpiRx ) = '0' ) then
                  v.state  := IDLE;
                  -- don't log single RXCMD
                  if ( rWr.haveRx ) then
                    -- write end marker
                    wen   := '1';
                    wrDat <=  (others => '0');
                  end if;
               elsif ( ulpiRx.nxt = '1' ) then
                  wen      := '1';
                  v.haveRx := true;
                  v.isPID  := false;
                  if ( rWr.isPID ) then
                     -- first byte;
                     if ( DROP_SOF_G and ( ulpiRx.dat(3 downto 0) = USB2_PID_TOK_SOF_C ) ) then
                        v.isSOF := true;
                     end if;
                  end if;
                  if ( v.isSOF ) then
                     wen      := '0';
                     v.haveRx := false;
                  end if;
               end if;

            when LOG_TX =>
               if ( ( ulpiRx.nxt or ulpiRx.stp ) = '1' ) then
                  wen    := '1';
                  if ( ulpiRx.stp = '1' ) then
                     -- mark this as EOP by flipping preserving the status
                     wrDat(8) <= '1';
                  end if;
               end if;
               if ( ulpiRx.stp = '1' ) then
                  v.state := IDLE;
               end if;
               if ( ulpiRx.dir = '1' ) then
                  -- register read (nxt = '0') or register op abort

                  -- mark end of TX
                  wrDat    <= (others => '0');
                  wrDat(8) <= '1';
                  wen      := '1';
                  if ( ulpiRx.nxt = '1' ) then
                     -- register abort by RX
                     v.state := LOG_RX;
                  else
                     v.state := LOG_RD;
                  end if;
               end if;

            when LOG_RD =>
               wen := '1';
               if ( not rWr.haveRx ) then
                 -- log read reply
                 v.haveRx := true;
               else
                 -- read done; end marker
                 wrDat    <= (others => '0');
                 wen      := '1';
                 v.haveRx := false;
                 if ( ulpiRx.dir = '0' ) then
                    v.state := IDLE;
                    -- read done normally
                 else
                    -- back-to-back RX
                    v.state := LOG_RX;
                 end if;
               end if;
         end case;
         if ( ( halt and not rWr.lstHalt ) = '1' ) then
            v        := rWr;
            wen      := '0';
            -- activate readout mode
            v.reqTgl := not rWr.reqTgl;
            v.state  := IDLE;
            -- prevent separator at next head
         end if;
         if ( wen = '1' ) then
            v.wptr := rWr.wptr + 1;
         end if;
      end if;

      memWen <= wen;
      rWrIn  <= v;
   end process P_WR_COMB;

   P_WR_SEQ : process ( ulpiClk ) is
   begin
      if ( rising_edge( ulpiClk ) ) then
         rWr <= rWrIn;
      end if;
   end process P_WR_SEQ;


   P_RD_COMB : process ( rRd, reqTgl, wrPtr, rdDat, datRdy )
      variable v : RdRegType;
   begin
      v     := rRd;
      if ( rRd.even = '1' ) then
         datOut <= rdDat(7 downto 0);
      else
         datOut <= rRd.hiByte;
      end if;
      datLst <= '0';
      if ( rRd.vld = '0' ) then
         if ( reqTgl /= rRd.repTgl ) then
            v.even := not rRd.even;
            if ( rRd.even = '1' ) then
               v.rptr := wrPtr;
            else
               v.vld  := '1';
            end if;
         end if;
      else
         if ( datRdy = '1' ) then
            v.even := not rRd.even;
            if ( rRd.even = '1' ) then
               v.hiByte(0) := rdDat(8);
               v.rptr      := rRd.rptr + 1;
            else
               if ( rRd.rptr = wrPtr ) then
                  datLst   <= '1';
                  v.vld    := '0';
                  v.repTgl := not rRd.repTgl;
               end if;
            end if;
         end if;
      end if;
      rRdIn  <= v;
      datVld <= rRd.vld;
   end process P_RD_COMB;

   P_RD_SEQ : process ( rdClk ) is
   begin
      if ( rising_edge( rdClk ) ) then
         rRd <= rRdIn;
      end if;
   end process P_RD_SEQ;

end architecture rtl;
