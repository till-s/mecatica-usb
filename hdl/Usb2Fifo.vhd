library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity Usb2Fifo is
   generic (
      DATA_WIDTH_G : natural;
      LD_DEPTH_G   : natural;
      LD_TIMER_G   : positive := 24;   -- at least one bit is required for internal reasons
      OUT_REG_G    : natural range 0 to 1 := 0;
      EXACT_THR_G  : boolean  := false
   );
   port (
      clk          : in  std_logic;
      rst          : in  std_logic := '0';

      din          : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      wen          : in  std_logic;
      full         : out std_logic;

      dou          : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
      ren          : in  std_logic;
      empty        : out std_logic;

      filled       : out unsigned(LD_DEPTH_G downto 0);

      -- at least ( minFill + 1 ) elements must be stored before reading may
      -- start
      minFill      : in  unsigned(LD_DEPTH_G - 1 downto 0) := (others => '0');
      -- if filled to less than 'minFill' then readout is started 'timer' clock
      -- ticks after the last item was written; all-ones waits forever 
      timer        : in  unsigned(LD_TIMER_G - 1 downto 0) := (others => '0')
   );
end entity Usb2Fifo;

architecture Impl of Usb2Fifo is

   -- extra bit
   subtype IdxType is unsigned(LD_DEPTH_G downto 0);

   constant FULL_C    : IdxType                           := to_unsigned(2**(LD_DEPTH_G), LD_DEPTH_G + 1);
   constant FOREVER_C : unsigned(LD_TIMER_G - 1 downto 0) := (others => '1');

   type RegType is record
      rdPtr     : IdxType;
      wrPtr     : IdxType;
      vld       : std_logic_vector( OUT_REG_G + 1 - 1 downto 0);
      timer     : unsigned(LD_TIMER_G - 1 downto 0);
      delayRd   : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      rdPtr     => ( others => '0' ),
      wrPtr     => ( others => '0' ),
      vld       => ( others => '0' ),
      timer     => ( others => '0' ),
      delayRd   => '1'
   );

   function occupied(constant x : in RegType) return IdxType is
   begin
      return x.wrPtr - x.rdPtr;
   end function occupied;

   function isFull(constant x : in RegType) return std_logic is
   begin
      if ( occupied(x) = FULL_C ) then
         return '1';
      else
         return '0';
      end if;
   end function isFull;

   function isEmpty(constant x : in RegType) return std_logic is
   begin
      if ( x.wrPtr = x.rdPtr ) then
         return '1';
      else
         return '0';
      end if;
   end function isEmpty;

   signal r     : RegType := REG_INIT_C;
   signal rin   : RegType;

   signal fifoEmpty : std_logic;
   signal fifoFull  : std_logic;
   signal fifoWen   : std_logic;
   signal fifoRen   : std_logic;
   signal advance   : std_logic;

   signal fillOff   : IdxType := (others => '0');

begin

   fifoFull  <= isFull( r );
   fifoWen   <= not isFull( r ) and wen;
   fifoEmpty <= not r.vld(0) or rin.delayRd;

   advance   <= not r.vld(0) or (ren and not rin.delayRd);

   G_THR_EXACT : if ( EXACT_THR_G ) generate
      P_FILL_OFF : process ( r ) is
         variable v : IdxType;
      begin
         v := (others => '0');
         for i in r.vld'range loop
            if ( r.vld(i) = '1' ) then
               v := v + 1;
            end if;
         end loop;
         fillOff <= v;
      end process P_FILL_OFF;
   end generate G_THR_EXACT;

   P_COMB : process ( r, wen, ren, minFill, fillOff, timer, fifoWen, advance ) is
      variable v : RegType;
   begin
      v := r;

      if ( r.timer /= 0 ) then
         if ( timer < r.timer ) then
            -- allow reducing on the fly
            v.timer    := timer;
         elsif ( r.timer /= FOREVER_C ) then
            v.timer := r.timer - 1;
         end if;
      end if;

      if ( r.delayRd = '1' ) then
         if ( occupied(r) + fillOff > minFill or ( ( r.timer = 0 ) and ( r.vld(0) = '1' ) ) ) then
            v.delayRd := '0';
         end if;
      else
         v.delayRd := not r.vld(0);
      end if;

      if ( advance = '1' ) then
         -- advance register pipeline while there is space (r.vld(0) = '0') or
         -- the last entry is popped (r.vld(0) = '1' and ren = '1')
         v.vld := not isEmpty(r) & r.vld(r.vld'left - 1 downto 0);
         if ( isEmpty(r) = '0' ) then
            v.rdPtr := r.rdPtr + 1;
         end if;
      end if;

      if ( fifoWen = '1' ) then
         v.wrPtr    := r.wrPtr + 1;
         -- min. timer is 1 in order to fill pipeline in "FILL" state
         v.timer    := timer;
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

   U_BRAM : entity work.Usb2Bram
      generic map (
         DATA_WIDTH_G => DATA_WIDTH_G,
         ADDR_WIDTH_G => LD_DEPTH_G,
         EN_REGB_G    => (OUT_REG_G > 0)
      )
      port map (
         clk          => clk,
         rst          => rst,

         ena          => open,
         wea          => fifoWen,
         addra        => r.wrPtr(r.wrPtr'left - 1 downto 0),
         rdata        => open,
         wdata        => din,

         enb          => advance,
         ceb          => advance,
         web          => open,
         addrb        => r.rdPtr(r.rdPtr'left - 1 downto 0),
         rdatb        => dou,
         wdatb        => open
      );

   empty  <= fifoEmpty;
   full   <= fifoFull;
   filled <= occupied(r);

end architecture Impl;
