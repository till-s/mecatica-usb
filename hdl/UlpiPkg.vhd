library ieee;
use     ieee.std_logic_1164.all;

package UlpiPkg is

   type UlpiRegReqType is record
      addr  : std_logic_vector(7 downto 0);
      wdat  : std_logic_vector(7 downto 0);
      extnd : std_logic;
      valid : std_logic;
      rdnwr : std_logic;
   end record UlpiRegReqType;

   constant ULPI_REG_REQ_INIT_C : UlpiRegReqType := (
      addr  => (others => '0'),
      wdat  => (others => '0'),
      extnd => '0',
      valid => '0',
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

   type UlpiStrmMstType is record
      dat   : std_logic_vector(7 downto 0);
      vld   : std_logic;
      lst   : std_logic;
   end record UlpiStrmMstType;

   constant ULPI_STRM_MST_INIT_C : UlpiStrmMstType := (
      dat   => (others => '0'),
      vld   => '0',
      lst   => '0'
   );

   type UlpiStrmSubType is record
      rdy   : std_logic;
      err   : std_logic;
   end record UlpiStrmSubType;

   constant ULPI_STRM_SUB_INIT_C : UlpiStrmSubType := (
      rdy   => '0',
      err   => '0'
   );
  
end package UlpiPkg;
