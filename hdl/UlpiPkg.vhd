library ieee;
use     ieee.std_logic_1164.all;

package UlpiPkg is

   constant ULPI_TXCMD_TX_C                : std_logic_vector(3 downto 0) := "0100";
   constant ULPI_RXCMD_RX_ACTIVE_BIT_C     : natural := 4;

   constant ULPI_RXCMD_LINE_STATE_SE0_C    : std_logic_vector(1 downto 0) := "00";
   constant ULPI_RXCMD_LINE_STATE_FS_J_C   : std_logic_vector(1 downto 0) := "01";
   constant ULPI_RXCMD_LINE_STATE_FS_K_C   : std_logic_vector(1 downto 0) := "10";

   type UlpiRegReqType is record
      addr  : std_logic_vector(7 downto 0);
      wdat  : std_logic_vector(7 downto 0);
      extnd : std_logic;
      vld   : std_logic;
      rdnwr : std_logic;
   end record UlpiRegReqType;

   constant ULPI_REG_REQ_INIT_C : UlpiRegReqType := (
      addr  => (others => '0'),
      wdat  => (others => '0'),
      extnd => '0',
      vld   => '0',
      rdnwr => '0'
   );

   type UlpiRegRepType is record
      rdat  : std_logic_vector(7 downto 0);
      ack   : std_logic;
      err   : std_logic;
   end record UlpiRegRepType;

   constant ULPI_REG_REP_INIT_C : UlpiRegRepType := (
      rdat  => (others => '0'),
      ack   => '0',
      err   => '0'
   );

   type UlpiRxType is record
      dat   :  std_logic_vector(7 downto 0);
      dir   :  std_logic;
      nxt   :  std_logic;
      trn   :  std_logic;
   end record UlpiRxType;

   constant ULPI_RX_INIT_C : UlpiRxType := (
      dat   => (others => '0'),
      dir   => '1',
      nxt   => '0',
      trn   => '0'
   );

   function ulpiIsRxCmd(constant x : in UlpiRxType) return boolean;

   -- The first data byte must be a TXCMD byte.
   -- The first cycle after 'vld' is deasserted
   -- generates a 'stop' cycle on ULPI; the
   -- data during this cycle must be driven!
   -- x"00" -> OK, x"FF" -> Error
   type UlpiTxReqType is record
      dat   :  std_logic_vector(7 downto 0);
      vld   :  std_logic;
   end record UlpiTxReqType;

   constant ULPI_TX_REQ_INIT_C : UlpiTxReqType := (
      dat   => (others => '0'),
      vld   => '0'
   );
   
   type UlpiTxRepType is record
      nxt   :  std_logic;
      -- error is asserted if the PHY aborted
      -- the transaction
      err   :  std_logic;
      don   :  std_logic;
   end record UlpiTxRepType;

end package UlpiPkg;

package body UlpiPkg is

   function ulpiIsRxCmd(constant x : in UlpiRxType)
   return boolean is
   begin
      return (x.dir and not x.trn and not x.nxt) = '1';
   end function ulpiIsRxCmd;
 
end package body UlpiPkg;
