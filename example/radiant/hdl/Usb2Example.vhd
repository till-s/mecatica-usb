library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2AppCfgPkg.all;
use     work.UlpiPkg.all;

entity Usb2Example is
   generic (
      NUM_LEDS_G : natural := 14;
      NUM_BUTS_G : natural :=  2;
      CNT_LEN_G  : natural := 22
   );
   port (
      ulpiClk : in     std_logic;
      ulpiNxt : in     std_logic;
      ulpiDir : in     std_logic;
      ulpiStp : out    std_logic;
      ulpiDat : inout  std_logic_vector(7 downto 0);
      LED     : out    std_logic_vector(NUM_LEDS_G - 1 downto 0);
      BUTTON  : in     std_logic_vector(NUM_BUTS_G - 1 downto 0)
   );
end entity Usb2Example;

architecture rtl of Usb2Example is
   constant USE_PLL_C : boolean := true;

   signal cnt : unsigned(CNT_LEN_G - 1 downto 0) := (others => '0');

   component UlpiPLL is
      port (
         clki_i     : in  std_logic;
         rstn_i     : in  std_logic;
         clkop_o    : out std_logic;
         clkos_o    : out std_logic;
         lock_o     : out std_logic
      );
   end component UlpiPLL;

   component IB is
      port (
        I : in  std_logic;
        O : out std_logic
      );
   end component IB;

   component BB is
      port (
        B : inout std_logic;
        T : in    std_logic;
        I : in    std_logic;
        O : out   std_logic
      );
   end component BB;

   signal ulpiClkBuffered : std_logic;
   signal ulpiClkLoc      : std_logic;

   signal ulpiIb          : UlpiIbType;
   signal ulpiOb          : UlpiObType;

   signal ulpiRst         : std_logic;
   signal usb2Rst         : std_logic;
   signal ulpiForceStp    : std_logic;

   signal ulpiPllLocked   : std_logic;
   signal ledLoc          : std_logic_vector(NUM_LEDS_G - 1 downto 0);

   signal acmLineBreak    : std_logic;
   signal acmDCD          : std_logic;

   signal ecmFifoOutDat   : Usb2ByteType;
   signal ecmFifoOutLast  : std_logic;
   signal ecmFifoOutEmpty : std_logic;
   signal ecmFifoOutRen   : std_logic;

   signal ecmFifoInpDat   : Usb2ByteType;
   signal ecmFifoInpLast  : std_logic;
   signal ecmFifoInpFull  : std_logic;
   signal ecmFifoInpWen   : std_logic;

   signal ecmCarrier      : std_logic;

   signal ncmFifoOutDat   : Usb2ByteType;
   signal ncmFifoOutLast  : std_logic;
   signal ncmFifoOutEmpty : std_logic;
   signal ncmFifoOutRen   : std_logic;

   signal ncmFifoInpDat   : Usb2ByteType;
   signal ncmFifoInpLast  : std_logic;
   signal ncmFifoInpBusy  : std_logic;
   signal ncmFifoInpFull  : std_logic;
   signal ncmFifoInpWen   : std_logic;

   signal ncmCarrier      : std_logic;

   type   ProgArray is array(natural range <>) of std_logic_vector(14 downto 0);
  

   constant prog          : ProgArray := (
      ("1" & "00" & "0000" & x"00"),
      ("1" & "00" & "0001" & x"00"),
      ("1" & "00" & "0010" & x"00"),
      ("1" & "00" & "0011" & x"00"),

      ("0" & "01" & "0000" & x"01"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"02"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"04"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"08"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"10"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"20"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"40"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"80"),
      ("1" & "01" & "0000" & x"00"),
      ("0" & "01" & "0000" & x"00"),
      ("1" & "01" & "0000" & x"00"),

      ("1" & "00" & "0100" & x"00"),
      ("1" & "00" & "0111" & x"00")
   );

   type StateType is (IDLE, WAI, DEBOUNCE);

   type RegType is record
      pc       : natural range prog'low to prog'high;
      req      : std_logic;
      debcnt   : unsigned(20 downto 0);
      state    : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      pc       => prog'low,
      req      => '0',
      debcnt   => (others => '0'),
      state    => IDLE
   );

   signal r          : RegType;
   signal rin        : RegType;

   signal ulpiRegReq : UlpiRegReqType;
   signal ulpiRegRep : UlpiRegRepType;

begin

   ulpiStp               <= ulpiOb.stp;

   ulpiIb.dir            <= ulpiDir;
   ulpiIb.nxt            <= ulpiNxt;
   ulpiIb.stp            <= '0';

   G_ULPI_BUF : for i in ulpiDat'range generate
      U_ULPI_BUF : component BB
         port map (
	    B => ulpiDat(i),
	    T => ulpiDir,
	    O => ulpiIb.dat(i),
	    I => ulpiOb.dat(i)
	 );
   end generate G_ULPI_BUF;

   U_CLK_BUF : component IB
      port map (
         I => ulpiClk,
	 O => ulpiClkBuffered
      );

   G_PLL : if (USE_PLL_C) generate

   U_PLL : component UlpiPLL
      port map (
         clki_i     => ulpiClkBuffered,
         rstn_i     => '1',
         clkop_o    => open,
         clkos_o    => ulpiClkLoc,
         lock_o     => ulpiPllLocked
      );

   end generate G_PLL;

   G_NO_PLL : if (not USE_PLL_C) generate
      ulpiClkLoc <= ulpiClkBuffered;
   end generate G_NO_PLL;

   U_USB2_DEV : entity work.Usb2ExampleDev
      generic map (
         DESCRIPTORS_G       => USB2_APP_DESCRIPTORS_C
      )
      port map (
         usb2Clk             => ulpiClkLoc,
         usb2Rst             => usb2Rst,
         ulpiRst             => ulpiRst,
	 ulpiIb              => ulpiIb,
	 ulpiOb              => ulpiOb,
	 ulpiForceStp        => ulpiForceStp,

         ulpiRegReq          => ulpiRegReq,
         ulpiRegRep          => ulpiRegRep,

	 acmFifoClk          => ulpiClkLoc,
	 acmLineBreak        => acmLineBreak,
	 acmDCD              => acmDCD,

         ecmFifoClk          => ulpiClkLoc,

         ecmFifoOutDat       => ecmFifoOutDat,
         ecmFifoOutLast      => ecmFifoOutLast,
         ecmFifoOutEmpty     => ecmFifoOutEmpty,
         ecmFifoOutRen       => ecmFifoOutRen,

         ecmFifoInpDat       => ecmFifoInpDat,
         ecmFifoInpLast      => ecmFifoInpLast,
         ecmFifoInpFull      => ecmFifoInpFull,
         ecmFifoInpWen       => ecmFifoInpWen,

         ecmCarrier          => ecmCarrier,

         ncmFifoClk          => ulpiClkLoc,

         ncmFifoOutDat       => ncmFifoOutDat,
         ncmFifoOutLast      => ncmFifoOutLast,
         ncmFifoOutEmpty     => ncmFifoOutEmpty,
         ncmFifoOutRen       => ncmFifoOutRen,

         ncmFifoInpDat       => ncmFifoInpDat,
         ncmFifoInpLast      => ncmFifoInpLast,
         ncmFifoInpBusy      => ncmFifoInpBusy,
         ncmFifoInpFull      => ncmFifoInpFull,
         ncmFifoInpWen       => ncmFifoInpWen,

         ncmCarrier          => ncmCarrier

      );

   ecmFifoInpDat       <= ncmFifoOutDat;
   ecmFifoInpLast      <= ncmFifoOutLast;

   ecmFifoInpWen       <= not ncmFifoOutEmpty;
   ncmFifoOutRen       <= not ecmFifoInpFull;

   ecmCarrier          <= '1';

   ncmFifoInpDat       <= ecmFifoOutDat;
   ncmFifoInpLast      <= ecmFifoOutLast;
   ecmFifoOutRen       <= not ncmFifoInpBusy and not ncmFifoInpFull;
   ncmFifoInpWen       <= not ecmFifoOutEmpty;

   ncmCarrier          <= '1';

   P_RST : process ( ulpiClkLoc ) is
   begin
      if ( rising_edge( ulpiClkLoc ) ) then
	 if ( cnt(cnt'left) = '0' ) then
            cnt     <= cnt +1;
	    if ( cnt < 1000000 ) then
               ulpiRst      <= '1';
	       ulpiForceStp <= '1';
	    else
               ulpiRst <= '0';
            end if;
         else
            ulpiForceStp <= '0';
         end if;
      end if;
   end process P_RST;

   usb2Rst <= ulpiRst;

   P_LED : process (ulpiPllLocked, cnt, acmLineBreak) is
   begin
      ledLoc     <= (others => '0');
      ledLoc(0)  <= ulpiPllLocked;
      ledLoc(1)  <= acmLineBreak;
      ledLoc(2)  <= cnt(cnt'left);
   end process P_LED;

   acmDCD <= BUTTON(0);

   ulpiRegReq.addr  <= "00" & prog(r.pc)(13 downto 8);
   ulpiRegReq.wdat  <=        prog(r.pc)( 7 downto 0);
   ulpiRegReq.extnd <= '0';
   ulpiRegReq.vld   <= r.req;
   ulpiRegReq.rdnwr <=        prog(r.pc)(14);

   P_COMB : process (r, ulpiRegRep, BUTTON) is
     variable v : RegType;
   begin
      v := r;
      if ( ulpiRegRep.ack = '1' ) then
         v.req := '0';
      end if;
      case ( r.state ) is
         when IDLE =>
            if ( BUTTON(1) = '0' ) then      
               v.req   := '1';
               v.state := WAI;
            end if;
         when WAI =>
            if ( ulpiRegRep.ack = '1' ) then
               if ( r.pc = prog'high ) then
                  v.pc    := prog'low;
                  v.state := DEBOUNCE;
               else
                  v.pc    := r.pc + 1;
                  v.req   := '1';
               end if;
            end if;
         when DEBOUNCE =>
            if ( BUTTON(1) = '0' ) then
               v.debcnt := (others => '0');
            elsif ( r.debcnt(r.debcnt'left) = '1' ) then
               v.debcnt := (others => '0');
               v.state  := IDLE;
            else
               v.debcnt := r.debcnt + 1;
            end if;
      end case;
      rin <= v;
   end process P_COMB;

   P_SEQ : process ( ulpiClkLoc ) is
   begin
      if ( rising_edge( ulpiClkLoc ) ) then
         if ( ulpiRst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   -- LEDs are active-low
   LED        <= not ledLoc;
end architecture rtl;
