-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;

package UlpiPkg is

   constant ULPI_TXCMD_TX_C                : std_logic_vector(3 downto 0) := "0100";
   constant ULPI_RXCMD_RX_ACTIVE_BIT_C     : natural := 4;

   constant ULPI_RXCMD_LINE_STATE_SE0_C    : std_logic_vector(1 downto 0) := "00";
   constant ULPI_RXCMD_LINE_STATE_FS_J_C   : std_logic_vector(1 downto 0) := "01";
   constant ULPI_RXCMD_LINE_STATE_FS_K_C   : std_logic_vector(1 downto 0) := "10";

   constant ULPI_REG_FUN_CTL_C      : std_logic_vector(3 downto 0) := x"4";
   constant ULPI_REG_OTG_CTL_C      : std_logic_vector(3 downto 0) := x"A";

   -- disable D-/D+ pull-down resistors
   constant ULPI_OTG_CTL_INI_C      : std_logic_vector(7 downto 0) := x"00";

   -- transceiver control
   constant ULPI_FUN_CTL_X_MSK_C    : std_logic_vector(7 downto 0) := x"03";
   -- hi-speed
   constant ULPI_FUN_CTL_X_HS_C     : std_logic_vector(7 downto 0) := x"00";
   -- full-speed
   constant ULPI_FUN_CTL_X_FS_C     : std_logic_vector(7 downto 0) := x"01";
   -- term select
   constant ULPI_FUN_CTL_TERM_C     : std_logic_vector(7 downto 0) := x"04";

   constant ULPI_FUN_CTL_OP_MSK_C   : std_logic_vector(7 downto 0) := x"18";
   -- normal operation
   constant ULPI_FUN_CTL_OP_NRM_C   : std_logic_vector(7 downto 0) := x"00";
   -- disable bit-stuff and nrzi
   constant ULPI_FUN_CTL_OP_CHR_C   : std_logic_vector(7 downto 0) := x"10";
   constant ULPI_FUN_CTL_RST_C      : std_logic_vector(7 downto 0) := x"20";
   constant ULPI_FUN_CTL_SUSPENDM_C : std_logic_vector(7 downto 0) := x"40";

   -- how to generate 'STP'
   --  NORMAL             : assert STP for 1 cycle (regardless of NXT)
   --  WAIT_FOR_NXT       : keep STP asserted until NXT is also asserted
   --  WAIT_FOR_NXT_MASKED: wait until NXT is asserted and assert STP
   --                       simultaneously with NXT. Note that this requires
   --                       a combinatorial path that is unlikely to make
   --                       timing.
   -- While the ULPI spec does not elaborate on NXT during a STP cycle; it
   -- says "when the link has consumed the last byte, the link asserts STP
   -- for 1 cycle".
   --
   -- However, in the USB3340 datasheet we find: "The Link cannot assert STP
   -- with NXT de-asserted since the USB3340 is expecting to fetch another byte
   -- from the Link".
   -- This requires WAIT_FOR_NXT_MASKED but will be very difficult to implement
   -- without an external logic gate. The timing budget (6ns output delay + 5ns
   -- setup time leaves ~5ns for board trace delays (small) and in-FPGA (significant)
   -- delay; (e.g., ARTIX-7 speed grade 1 needs IBUF + routing + OBUF ~ 8ns).
   -- Experiments showed that the USB3340 did work just fine in NORMAL
   -- mode but actually failed in one of the other modes. So these are
   -- kept mostly for the record.
   type UlpiStpModeType is ( NORMAL, WAIT_FOR_NXT, WAIT_FOR_NXT_MASKED );

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
      stp   :  std_logic;
   end record UlpiRxType;

   constant ULPI_RX_INIT_C : UlpiRxType := (
      dat   => (others => '0'),
      dir   => '1',
      nxt   => '0',
      trn   => '0',
      stp   => '0'
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
      err   :  std_logic;
   end record UlpiTxReqType;

   constant ULPI_TX_REQ_INIT_C : UlpiTxReqType := (
      dat   => (others => '0'),
      vld   => '0',
      err   => '0'
   );
   
   type UlpiTxRepType is record
      nxt   :  std_logic;
      -- error is asserted if the PHY aborted
      -- the transaction
      err   :  std_logic;
      don   :  std_logic;
   end record UlpiTxRepType;

   type UlpiIbType is record
      dir   : std_logic;
      nxt   : std_logic;
      -- feedback of stp (optional) for debugging
      stp   : std_logic;
      dat   : std_logic_vector(7 downto 0);
   end record UlpiIbType;

   constant ULPI_IB_INIT_C : UlpiIbType := (
      dir  => '0',
      nxt  => '0',
      stp  => '0',
      dat  => (others => '0')
   );

   type UlpiObType is record
      dat   : std_logic_vector(7 downto 0);
      stp   : std_logic;
   end record UlpiObType;

   constant ULPI_OB_INIT_C : UlpiObType := (
      stp  => '0',
      dat  => (others => '0')
   );


end package UlpiPkg;

package body UlpiPkg is

   function ulpiIsRxCmd(constant x : in UlpiRxType)
   return boolean is
   begin
      return (x.dir and not x.trn and not x.nxt) = '1';
   end function ulpiIsRxCmd;
 
end package body UlpiPkg;
