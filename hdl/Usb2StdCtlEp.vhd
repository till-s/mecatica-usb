-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;
use     work.Usb2DescPkg.all;

-- Control endpoint 0; handles standard USB requests.
-- Additional features may be implemented by an external
-- 'agent' to which unknown requests can be off-loaded.

entity Usb2StdCtlEp is
   generic (
      NUM_ENDPOINTS_G   : positive;
      ENDPOINT_G        : Usb2EndpIdxType := USB2_ENDP_ZERO_C;
      DESCRIPTORS_G     : Usb2ByteArray;
      DESCRIPTOR_BRAM_G : boolean         := true;
      MARK_DEBUG_G      : boolean         := true
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';

      -- EP0 connection to the packet engine
      epIb            : in  Usb2EndpPairObType;
      epOb            : out Usb2EndpPairIbType;

      -- observe other endpoints
      usrEpIb         : in  Usb2EndpPairIbArray(1 to NUM_ENDPOINTS_G - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);

      pktHdr          : in  Usb2PktHdrType;

      param           : out Usb2CtlReqParamType;
      -- an external agent may take over the
      -- data phase and execution of the control
      -- transaction. It must monitor the 'epIb'
      -- stream(s) and store any data needed.
      -- Once the param.vld is asserted '1' the
      -- external agent needs to 'ack' with the 'err' and 'don'
      -- flags clear.
      -- Once the transaction is processed the
      -- external agent asserts 'don' and conveys status
      -- in 'ack' and 'err'.
      -- If 'ack' is not asserted with 'don' then this
      -- module will keep monitoring 'ack' and extend the status phase
      -- until it is asserted.
      ctlExt          : in  Usb2CtlExtType     := USB2_CTL_EXT_NAK_C;
      ctlEpExt        : in  Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      suspend         : in  std_logic          := '0';
      hiSpeed         : in  std_logic          := '0';
      selfPowered     : in  std_logic          := '0';

      devStatus       : out Usb2DevStatusType;
      epConfig        : out Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_G - 1);

      -- access to descriptors in memory (only if DESCRIPTOR_BRAM_G is true)
      -- NOTE: when modifying contents be *very careful*! Nothing that
      --       alters the structure and layout of descriptors must be changed!
      --       This is only intended for tweaking contents such as a MAC
      --       address, for example.
      descRWClk       : in  std_logic          := '0';
      descRWIb        : in  Usb2DescRWIbType   := USB2_DESC_RW_IB_INIT_C;
      -- readout has a 1-cycle pipeline delay
      descRWOb        : out Usb2DescRWObType   := USB2_DESC_RW_OB_INIT_C
   );
end entity Usb2StdCtlEp;

architecture Impl of Usb2StdCtlEp is

   alias DSC_C : Usb2ByteArray is DESCRIPTORS_G;

   procedure pr(constant x: Usb2ByteArray) is
      variable s : string(1 to 8);
   begin
      for i in x'range loop
         for j in x(i)'left downto x(i)'right loop
            s(8-j) := std_logic'image(x(i)(j))(2);
         end loop;
         report "D[" & integer'image(i) & "]  => " & s;
      end loop;
   end procedure pr;

   constant MAX_ALTSETTINGS_C  : natural          := USB2_APP_MAX_ALTSETTINGS_F( DESCRIPTORS_G );
   constant MAX_INTERFACES_C   : natural          := USB2_APP_MAX_INTERFACES_F ( DESCRIPTORS_G );
   constant STRINGS_IDX_C      : Usb2DescIdxType  := USB2_APP_STRINGS_IDX_F    ( DESCRIPTORS_G );
   constant NUM_STRINGS_C      : natural          := USB2_APP_NUM_STRINGS_F    ( DESCRIPTORS_G );

   constant FS_CFG_IDX_TABLE_C : Usb2DescIdxArray := USB2_APP_CONFIG_IDX_TBL_F ( DESCRIPTORS_G, false );
   constant HS_CFG_IDX_TABLE_C : Usb2DescIdxArray := USB2_APP_CONFIG_IDX_TBL_F ( DESCRIPTORS_G, true  );

   function FS_QUAL_IDX_F( constant d : in Usb2ByteArray ) return integer is
   begin
      if ( FS_CFG_IDX_TABLE_C'length > 0 ) then
         return usb2NextDescriptor( d, FS_CFG_IDX_TABLE_C(0), USB2_STD_DESC_TYPE_DEVICE_QUALIFIER_C, true );
      else
         return -1;
      end if;
   end function FS_QUAL_IDX_F;

   function HS_QUAL_IDX_F( constant d : in Usb2ByteArray ) return integer is
   begin
      if ( HS_CFG_IDX_TABLE_C'length > 0 ) then
         return usb2NextDescriptor( d, HS_CFG_IDX_TABLE_C(0), USB2_STD_DESC_TYPE_DEVICE_QUALIFIER_C, true );
      else
         return -1;
      end if;
   end function HS_QUAL_IDX_F;

   constant FS_QUAL_IDX_C      : integer          := FS_QUAL_IDX_F( DESCRIPTORS_G );
   constant HS_QUAL_IDX_C      : integer          := HS_QUAL_IDX_F( DESCRIPTORS_G );

   type StateType is (
      GET_PARAMS,
      WAIT_CTL_DONE,
      WAIT_EXT,
      WAIT_EXT_DONE,
      STD_REQUEST,
      READ_TBL,
      SCAN_DESC,
      SCAN_DESC_LOOP,
      SETUP_CONFIG,
      DEACT_IFC,
      LOAD_ALT,
      LOAD_EPTS,
      GET_DESCRIPTOR_SIZE,
      READ_DESCRIPTOR,
      RETURN_VALUE,
      STATUS
   );

   function max(constant a, b: integer) return integer is
   begin
      if ( a > b ) then return a; else return b; end if;
   end function max;

   function selCfgIdxTbl(constant hs: in boolean) return Usb2DescIdxArray is
   begin
      if ( hs and HS_CFG_IDX_TABLE_C'length > 0 ) then
         return HS_CFG_IDX_TABLE_C;
      else
         return FS_CFG_IDX_TABLE_C;
      end if;
   end function selCfgIdxTbl;

   function numConfigs(constant hs : in boolean)
   return natural is
      variable v : natural;
   begin
      v := to_integer( unsigned(
              DESCRIPTORS_G( selCfgIdxTbl( hs )(0) +  USB2_DEV_DESC_IDX_NUM_CONFIGURATIONS_C )
           ) );
      return v;
   end function numConfigs;

   function epIdx(constant x: Usb2CtlReqParamType)
   return natural is
   begin
      return to_integer( unsigned( x.index(3 downto 0) ) );
   end function epIdx;

   function fsEp0MaxPktSize return natural is
   begin
      -- may add other generic to define the max size
      assert ENDPOINT_G = USB2_ENDP_ZERO_C report "auto-setting of maxPktSize not implemented yet" severity failure;
      return to_integer( unsigned( DESCRIPTORS_G( FS_CFG_IDX_TABLE_C(0) + USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C ) ) );
   end function fsEp0MaxPktSize;

   function fsEp0MaxPktSizeLd return natural is
   begin
      case fsEp0MaxPktSize is
         when 8  => return 3;
         when 16 => return 4;
         when 32 => return 5;
         when 64 => return 6;
         when others =>
      end case;
      assert false report "Illegal MaxPktSize" severity failure;
      return 0; -- silence vivado warning about missing return value
   end function fsEp0MaxPktSizeLd;

   constant FS_EP0_PKT_SIZE_MSK_C : unsigned(fsEp0MaxPktSizeLd - 1 downto 0) := (others => '0');
   constant HS_EP0_PKT_SIZE_MSK_C : unsigned(6                 - 1 downto 0) := (others => '0');

   procedure w2u(variable v : out unsigned; constant a: in Usb2ByteArray; constant o : in natural) is
      constant x : std_logic_vector(15 downto 0) := a(o+1) & a(0);
   begin
      v := resize( unsigned( x ), v'length );
   end procedure w2u;

   function w2u(constant x : std_logic_vector(15 downto 0)) return unsigned is
   begin
      return unsigned( x );
   end function w2u;

   subtype AltSetIdxType is natural range 0 to MAX_ALTSETTINGS_C - 1;
   -- vivado complains that the v.ifcIdx := r.ifcIdx + 1 violates the range
   -- but is not smart enough to see that this can never be executed.
   subtype IfcIdxType    is natural range 0 to MAX_INTERFACES_C  + 1;
   subtype EpIdxType     is natural range 0 to NUM_ENDPOINTS_G;
   subtype CfgIdxType    is natural range 0 to max(numConfigs(true), numConfigs(false));

   type    AltSetArray   is array(IfcIdxType) of AltSetIdxType;

   type EndpAssocType is record
      ifc         : IfcIdxType;
   end record EndpAssocType;

   constant ENDP_ASSOC_INIT_C : EndpAssocType := (
      ifc         => 0
   );

   type EndpAssocArray is array (natural range 1 to NUM_ENDPOINTS_G - 1) of EndpAssocType;

   type RegType   is record
      state       : StateType;
      retState    : StateType;
      retFromRd   : StateType;
      devStatus   : Usb2DevStatusType;
      reqParam    : Usb2CtlReqParamType;
      parmIdx     : unsigned(2 downto 0);
      err         : std_logic;
      protoStall  : std_logic;
      epConfig    : Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_G - 1);
      epAssocInp  : EndpAssocArray;
      epAssocOut  : EndpAssocArray;
      cfgIdx      : Usb2DescIdxType;
      cfgCurr     : CfgIdxType;
      retVal      : Usb2ByteType;
      readVal     : Usb2ByteType;
      tmpVal      : Usb2ByteType;
      retSz2      : boolean;
      flg         : std_logic;
      tblIdx      : Usb2DescIdxType;
      tblOff      : Usb2DescIdxType;
      auxOff      : Usb2DescIdxType;
      count       : Usb2DescIdxType;
      tblRdDone   : boolean;
      skipDesc    : boolean;
      altSettings : AltSetArray;
      statusAck   : std_logic;
      ifcIdx      : IfcIdxType;
      altIdx      : AltSetIdxType;
      numIfc      : IfcIdxType;
      epIdx       : EpIdxType;
      epIsInp     : boolean;
      numEp       : EpIdxType;
      descType    : Usb2StdDescriptorTypeType;
      size2B      : boolean;
      sizeMatch   : boolean;
      setupDone   : boolean;
      patchOthCfg : std_logic_vector(1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => GET_PARAMS,
      retState    => GET_PARAMS,
      retFromRd   => GET_PARAMS,
      devStatus   => USB2_DEV_STATUS_INIT_C,
      reqParam    => USB2_CTL_REQ_PARAM_INIT_C,
      parmIdx     => (others => '0'),
      err         => '0',
      protoStall  => '0',
      epConfig    => (
                        0      => ( 
                                     transferTypeInp => USB2_TT_CONTROL_C,
                                     transferTypeOut => USB2_TT_CONTROL_C,
                                     maxPktSizeInp   => to_unsigned( fsEp0MaxPktSize, epConfig(0).maxPktSizeInp'length ),
                                     maxPktSizeOut   => to_unsigned( fsEp0MaxPktSize, epConfig(0).maxPktSizeInp'length ),
                                     hasHaltInp      => false,
                                     hasHaltOut      => false
                                  ),
                        others => USB2_ENDP_PAIR_CONFIG_INIT_C
                     ),
      epAssocInp  => (others => ENDP_ASSOC_INIT_C),
      epAssocOut  => (others => ENDP_ASSOC_INIT_C),
      cfgIdx      => 0,
      cfgCurr     => 0,
      retVal      => (others => '0'),
      readVal     => (others => '0'),
      tmpVal      => (others => '0'),
      altSettings => (others => 0),
      flg         => '0',
      tblIdx      => 0,
      tblOff      => 0,
      auxOff      => 0,
      count       => 0,
      tblRdDone   => false,
      skipDesc    => true,
      retSz2      => false,
      statusAck   => '1',
      ifcIdx      => 0,
      altIdx      => 0,
      numIfc      => 0,
      numEp       => 0,
      epIdx       => 0,
      epIsInp     => false,
      descType    => (others => '0'),
      size2B      => false,
      sizeMatch   => false,
      setupDone   => false,
      patchOthCfg => (others => '0')
   );

   -- a vivado work-around. Vivado complained about a index expression (when NUM_ENDPOINTS_G = 0) but
   -- failed to realize that the case could be optimized away (if unsigned < NUM_ENDPONTS and unsigned > 0)
   -- therefore we introduce a dummy signal array that is never empty.
   signal allEpIb: Usb2EndpPairIbArray(0 to NUM_ENDPOINTS_G - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);

   signal r                 : RegType := REG_INIT_C;
   signal rin               : RegType;

   signal ramDatA           : Usb2ByteType := (others => '0');
   signal ramRenA           : std_logic    := '0';

   procedure READ_TBL( variable v : inout RegType ) is
   begin
      v           := v;
      v.retFromRd := r.state;
      v.state     := READ_TBL;
   end procedure READ_TBL;

   procedure READ_TBL( variable v : inout RegType; constant t : in StateType) is
   begin
      v           := v;
      v.retFromRd := t;
      v.state     := READ_TBL;
   end procedure READ_TBL;


   function hasHaltInp   (constant x : in RegType; constant o : std_logic_vector)
   return boolean is
   begin
      return x.epConfig( to_integer( unsigned( o ) ) ).hasHaltInp;
   end function hasHaltInp;

   function hasHaltOut   (constant x : in RegType; constant o : std_logic_vector)
   return boolean is
   begin
      return x.epConfig( to_integer( unsigned( o ) ) ).hasHaltOut;
   end function hasHaltOut;

   function altSetSlv8(constant x : in RegType; constant i: in unsigned)
   return std_logic_vector is
   begin
      return std_logic_vector( to_unsigned( x.altSettings( to_integer( i ) ), 8 ) );
   end function altSetSlv8;

   function toPktSizeType(constant x : std_logic_vector(15 downto 0)) return Usb2PktSizeType is
   begin
      return Usb2PktSizeType( x(Usb2PktSizeType'range) );
   end function toPktSizeType;

   attribute MARK_DEBUG of r : signal is toStr(MARK_DEBUG_G);

begin

   allEpIb(1 to NUM_ENDPOINTS_G - 1) <= usrEpIb;

   P_COMB : process ( r, epIb, allEpIb, ctlExt, ctlEpExt, pktHdr, suspend, hiSpeed, selfPowered, ramDatA ) is
      variable v          : RegType;
      variable descVal    : Usb2ByteType;
      variable tokOutSeen : boolean;
      variable tblSelHS   : boolean;
   begin
      v    := r;
      epOb                      <= USB2_ENDP_PAIR_IB_INIT_C;

      if ( DESCRIPTOR_BRAM_G ) then
         descVal                := ramDatA;
      else
         descVal                := DSC_C( r.tblIdx + r.tblOff );
      end if;

      epOb.stalledInp           <= r.protoStall;
      epOb.stalledOut           <= r.protoStall;
      v.devStatus.clrHalt       := '0';
      v.devStatus.setHalt       := '0';
      v.devStatus.selHaltInp    := (others => '0');
      v.devStatus.selHaltOut    := (others => '0');
      v.tblRdDone               := false;
      ramRenA                   <= '0';

      if ( ctlExt.don = '1' ) then
         v.reqParam.vld            := '0';
      end if;
      v.devStatus.hiSpeed       := (hiSpeed = '1');
      tblSelHS                  := r.devStatus.hiSpeed;

      if ( r.devStatus.hiSpeed ) then
         v.epConfig(0).maxPktSizeInp := to_unsigned( 64, v.epConfig(0).maxPktSizeInp'length );
         v.epConfig(0).maxPktSizeOut := to_unsigned( 64, v.epConfig(0).maxPktSizeInp'length );
      else
         v.epConfig(0).maxPktSizeInp := to_unsigned( fsEp0MaxPktSize, v.epConfig(0).maxPktSizeInp'length );
         v.epConfig(0).maxPktSizeOut := to_unsigned( fsEp0MaxPktSize, v.epConfig(0).maxPktSizeInp'length );
      end if;

      if ( epIb.mstCtl.vld = '0' ) then
         v.setupDone := true;
      end if;

      if ( pktHdr.vld = '1' and pktHdr.pid = USB2_PID_TOK_SETUP_C ) then
         -- due to buffering of the next request in the packet processor
         -- (needed to determine CRC correctness) there is considerable
         -- pipeline delay. We must make sure to withdraw our stall condition
         -- early enough for the packet processor not rejecting a fresh
         -- SETUP. Therefore we watch the packet header here...
         if (     (    (     ( usb2TokenPktAddr( pktHdr ) = USB2_DEV_ADDR_DFLT_C )
                         and ( ENDPOINT_G                 = USB2_ENDP_ZERO_C     )
                       )
                    or       ( usb2TokenPktAddr( pktHdr ) = r.devStatus.devAddr  )
                  )
              and            ( ENDPOINT_G                 = USB2_ENDP_ZERO_C     )
            )
         then
            v.protoStall          := '0';
            v.reqParam.extAbort   := false;
         end if;
         v.reqParam.vld := '0';
      end if;

      tokOutSeen:= ( pktHdr.vld = '1' and pktHdr.pid = USB2_PID_TOK_OUT_C );

      case ( r.state ) is
         when GET_PARAMS =>
            v.flg           := '0';
            if ( epIb.mstCtl.vld = '1' ) then
               v.protoStall    := '0';
               v.err           := '0';
               v.setupDone     := false;

               case ( r.parmIdx ) is
                  when "000" =>
                     v.reqParam.dev2Host  := USB2_REQ_TYP_DEV2HOST_F ( epIb.mstCtl.dat );
                     v.reqParam.reqType   := USB2_REQ_TYP_TYPE_F     ( epIb.mstCtl.dat );
                     v.reqParam.recipient := USB2_REQ_TYP_RECIPIENT_F( epIb.mstCtl.dat );
                  when "001" =>
                     v.reqParam.request             := unsigned(epIb.mstCtl.dat);
                  when "010" =>
                     v.reqParam.value( 7 downto 0)  := epIb.mstCtl.dat;
                  when "011" =>
                     v.reqParam.value(15 downto 8)  := epIb.mstCtl.dat;
                  when "100" =>
                     v.reqParam.index( 7 downto 0)  := epIb.mstCtl.dat;
                  when "101" =>
                     v.reqParam.index(15 downto 8)  := epIb.mstCtl.dat;
                  when "110" =>
                     v.reqParam.length( 7 downto 0) := unsigned(epIb.mstCtl.dat);
                  when others =>
                     v.reqParam.length(15 downto 8) := unsigned(epIb.mstCtl.dat);
                     v.state               := WAIT_CTL_DONE;
               end case;
               v.parmIdx := r.parmIdx + 1;
            end if;

         when WAIT_CTL_DONE =>
            if ( v.setupDone ) then
               v.state         := WAIT_EXT;
               -- only assert 'vld' now; we have no handshake with ctlExt; they
               -- must respond to our 'vld' flag and we must not miss the ack
               v.reqParam.vld  := '1';
            end if;

         when WAIT_EXT =>
            if ( ctlExt.ack = '1' ) then
               if ( ctlExt.err = '1' ) then
                  v.state    := STD_REQUEST;
               else
                  -- ctlExt.don may arrive this cycle or any time after
                  v.state    := WAIT_EXT_DONE;
                  if ( ctlExt.don = '1' ) then
                     v.statusAck := '1';
                     v.state     := STATUS;
                  end if;
               end if;
            end if;

         when WAIT_EXT_DONE =>
            epOb <= ctlEpExt;
            if ( tokOutSeen and r.reqParam.dev2Host ) then
               -- host does not read all available data
               v.state               := STATUS;
               v.statusAck           := '1';
               v.reqParam.extAbort   := true;
            elsif ( ctlExt.don = '1' ) then
               v.protoStall := ctlExt.err;
               v.statusAck  := ctlExt.ack;
               if ( ctlExt.err = '1' ) then
                  v.state   := GET_PARAMS;
               else
                  v.state   := STATUS;
               end if;
            end if;

         when READ_TBL =>
            if ( DESCRIPTOR_BRAM_G and not r.tblRdDone ) then
               v.tblRdDone   := true;
               ramRenA       <= '1';
               if ( r.retFromRd = READ_DESCRIPTOR ) then
                  -- pre-increment table offset (pipeline)
                  v.tblOff := r.tblOff + 1;
               end if;
            else
               -- keep result in a register mostly to ensure
               -- every read goes through this READ_TBL 'wait' state
               -- this is necessary if DESCRIPTOR_BRAM_G is enabled
               v.readVal     := descVal;
               v.state       := r.retFromRd;
               -- flag is reset by default but we
               -- keep it asserted
               v.tblRdDone   := true;
            end if;

         when STD_REQUEST =>
            -- dispatch standard requests

            -- by default bail
            v.state       := GET_PARAMS;
            v.err         := '0';
            v.retVal      := (others => '0');
            v.retSz2      := false;
            v.statusAck   := '1';

            if (    ( r.reqParam.reqType = USB2_REQ_TYP_TYPE_STANDARD_C )
                and ( r.reqParam.request(7 downto 4) = "0000"           )
                and not (     ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_IFC_C )
                         and  ( unsigned(r.reqParam.index(7 downto 0)) >= r.numIfc  )
                        )
                and not (     ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_EPT_C )
                         and  ( unsigned(r.reqParam.index(3 downto 0)) >= NUM_ENDPOINTS_G )
                        )
               ) then
               case ( r.reqParam.request(3 downto 0) ) is

                  when USB2_REQ_STD_CLEAR_FEATURE_C
                   |   USB2_REQ_STD_SET_FEATURE_C       =>
                     if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_DEV_C )
                     then
                        if ( Usb2StdFeatureType( r.reqParam.value(1 downto 0) ) = USB2_STD_FEAT_DEVICE_REMOTE_WAKEUP_C ) then
                           if ( not r.tblRdDone ) then
                              v.tblIdx   := r.cfgIdx;
                              v.tblOff   := USB2_CFG_DESC_IDX_ATTRIBUTES_C;
                              READ_TBL( v );
                           else
                              if ( r.readVal(5) = '1' ) then
                                 -- device supports the feature
                                 v.devStatus.remWakeup := ( r.reqParam.request(3 downto 0) = USB2_REQ_STD_SET_FEATURE_C );
                                 v.state               := STATUS;
                              end if;
                           end if;
                        end if;
                     elsif (    ( r.devStatus.state = CONFIGURED )
                             or ( r.reqParam.index(6 downto 0) = "0000000" )
                             -- there are no std interface features; otherwise
                             -- we'd have to compare bit 7 as well (1/0 for endpoints but
                             -- part of the interface number)
                           )
                     then
                        if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_IFC_C )
                        then
                        elsif ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_EPT_C )
                        then
                           if ( Usb2StdFeatureType( r.reqParam.value(1 downto 0) ) = USB2_STD_FEAT_ENDPOINT_HALT_C ) then
                              if ( r.reqParam.request = USB2_REQ_STD_SET_FEATURE_C ) then
                                 if ( r.reqParam.index(7) = '0' and hasHaltOut(r, r.reqParam.index(3 downto 0)) ) then 
                                    v.devStatus.selHaltOut(epIdx(r.reqParam)) := '1';
                                    v.devStatus.setHalt := '1';
                                    v.state             := STATUS;
                                 elsif ( hasHaltInp( r, r.reqParam.index(3 downto 0) ) ) then
                                    v.devStatus.selHaltInp(epIdx(r.reqParam)) := '1';
                                    v.devStatus.setHalt := '1';
                                    v.state             := STATUS;
                                 end if;
                              else
                                 -- this resets the data toggles on the target endpoint
                                 if ( r.reqParam.index(7) = '0' ) then 
                                    v.devStatus.selHaltOut(epIdx(r.reqParam)) := '1';
                                    v.devStatus.clrHalt := '1';
                                    v.state             := STATUS;
                                 else
                                    v.devStatus.selHaltInp(epIdx(r.reqParam)) := '1';
                                    v.devStatus.clrHalt := '1';
                                    v.state             := STATUS;
                                 end if;
                              end if;
                           end if;
                        end if;
                     end if;

                  when USB2_REQ_STD_GET_CONFIGURATION_C =>
                     v.retVal   := std_logic_vector(to_unsigned(r.cfgCurr, v.retVal'length));
                     v.state    := RETURN_VALUE;

                  when USB2_REQ_STD_GET_DESCRIPTOR_C    =>
                     v.tblOff      := USB2_DESC_IDX_LENGTH_C;
                     v.retVal      := (others => '0');
                     v.size2B      := false;
                     v.state       := GET_DESCRIPTOR_SIZE;
                     v.count       := 0;
                     v.patchOthCfg := (others => '0');

                     case ( Usb2StdDescriptorTypeType( r.reqParam.value(11 downto 8) ) ) is
                        when USB2_STD_DESC_TYPE_DEVICE_C            =>
                           v.tblIdx   := selCfgIdxTbl( tblSelHS )(0);

                        when USB2_STD_DESC_TYPE_DEVICE_QUALIFIER_C  =>
                           if ( FS_QUAL_IDX_C > 0 and HS_QUAL_IDX_C > 0 ) then
                              if ( r.devStatus.hiSpeed ) then
                                 v.tblIdx := HS_QUAL_IDX_C;
                              else
                                 v.tblIdx := FS_QUAL_IDX_C;
                              end if;
                           else
                              -- full-speed only device must return error
                              v.protoStall := '1';
                           end if;

                        when USB2_STD_DESC_TYPE_CONFIGURATION_C     |
                             USB2_STD_DESC_TYPE_OTHER_SPEED_CONF_C  =>
                           if (   Usb2StdDescriptorTypeType( r.reqParam.value(11 downto 8) )
                                = USB2_STD_DESC_TYPE_OTHER_SPEED_CONF_C ) then
                              if ( FS_CFG_IDX_TABLE_C'length > 0 and HS_CFG_IDX_TABLE_C'length > 0 ) then
                                 tblSelHS         := not tblSelHS; -- other speed
                                 -- during READ_DESCRIPTOR we must patch the descriptor type
                                 -- to read 'OTHER_SPEED_CONFIGURATION'
                                 v.patchOthCfg(1) := '1';
                              else
                                 -- use a table that fails the '<' comparison below
                                 tblSelHs         := ( HS_CFG_IDX_TABLE_C'length <= 0 );
                              end if;
                           end if;
                           -- according to the spec this is 0-based and thus not identical
                           -- with the configuration value.
                           if ( to_integer(unsigned(r.reqParam.value(7 downto 0))) < numConfigs(tblSelHS) ) then
                              v.tblIdx     := selCfgIdxTbl( tblSelHS )( to_integer(unsigned(r.reqParam.value(7 downto 0))) + 1 );
                              v.tblOff     := USB2_CFG_DESC_IDX_TOTAL_LENGTH_C + 1;
                              v.size2B     := true;
                           else
                              v.protoStall := '1';
                           end if;

                        when USB2_STD_DESC_TYPE_STRING_C            =>
                           if ( NUM_STRINGS_C > 0 ) then
                              v.count := to_integer(unsigned(r.reqParam.value(7 downto 0)));
                              -- ignore language ID
                              v.tblIdx     := STRINGS_IDX_C;
                              v.descType   := USB2_STD_DESC_TYPE_STRING_C;
                           else
                              v.protoStall := '1';
                           end if;
                        when others                                 =>
                           v.protoStall := '1';
                     end case;
                     if ( v.protoStall = '1' ) then
                        v.state    := GET_PARAMS;
                     end if;

                  when USB2_REQ_STD_GET_INTERFACE_C     =>
                     if ( r.devStatus.state = CONFIGURED ) then
                        if ( unsigned( r.reqParam.index(6 downto 0) ) < r.altSettings'length ) then
                           v.retVal    := altSetSlv8( r, unsigned( r.reqParam.index( 6 downto 0 ) ) );
                           v.state     := RETURN_VALUE;
                        end if;
                     end if;

                  when USB2_REQ_STD_GET_STATUS_C        =>
                     v.retSz2 := true;
                     if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_DEV_C ) then
                        -- self powered
                        v.retVal    := x"00";
                        v.retVal(0) := selfPowered;
                        -- remote wakeup
                        v.retVal(1) := toSl( r.devStatus.remWakeup );
                        v.state     := RETURN_VALUE;
                     elsif (    ( r.devStatus.state = CONFIGURED )
                             or ( r.reqParam.index(6 downto 0) = "0000000" ) ) then
                        if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_EPT_C ) then
                           if (     unsigned(r.reqParam.index(3 downto 0)) < NUM_ENDPOINTS_G ) then
                              v.state     := RETURN_VALUE;
                              if ( unsigned(r.reqParam.index(3 downto 0)) > 0 ) then
                                 if ( r.reqParam.index(7) = '0' ) then
                                    v.retVal(0) := allEpIb( to_integer( unsigned( r.reqParam.index(3 downto 0) ) ) ).stalledOut;
                                 else
                                    v.retVal(0) := allEpIb( to_integer( unsigned( r.reqParam.index(3 downto 0) ) ) ).stalledInp;
                                 end if;
                              else
                                 -- EP0 is never halted
                              end if;
                           end if;
                        else
                          v.state    := RETURN_VALUE;
                          -- ignore check for invalid interface
                        end if;
                     end if;

                  when USB2_REQ_STD_SET_ADDRESS_C       =>
                     v.state    := STATUS;

                  when USB2_REQ_STD_SET_CONFIGURATION_C =>
                     if ( r.reqParam.value(7 downto 0) = x"00" ) then
                        v.devStatus.state := ADDRESS;
                        v.state           := STATUS;
                        v.cfgCurr         := 0;
                     elsif ( unsigned( r.reqParam.value(7 downto 0) ) <= numConfigs( r.devStatus.hiSpeed ) ) then
                        -- assume the configuration value equals the index in the CFG_IDX_TABLE_C!
                        if ( not r.tblRdDone ) then
                           v.cfgCurr         := to_integer( unsigned( r.reqParam.value( 7 downto 0 ) ) );
                           v.cfgIdx          := selCfgIdxTbl( tblSelHS )( v.cfgCurr );
                           v.tblIdx          := v.cfgIdx;
                           v.tblOff          := USB2_CFG_DESC_IDX_NUM_INTERFACES_C;
                           v.ifcIdx          := 0;
                           v.epIdx           := 0;
                           READ_TBL( v );
                        else
                           v.state           := SETUP_CONFIG;
                           v.numIfc          := to_integer(unsigned(r.readVal));
                           for i in 1 to v.epConfig'length - 1 loop
                              v.epConfig(i).maxPktSizeInp := (others => '0');
                              v.epConfig(i).maxPktSizeOut := (others => '0');
                           end loop;
                        end if;
                     end if;

                  when USB2_REQ_STD_SET_DESCRIPTOR_C    =>
                    -- unsupported

                  when USB2_REQ_STD_SET_INTERFACE_C     =>
                     if (    ( r.devStatus.state = CONFIGURED                                             )
                         and ( to_integer(unsigned( r.reqParam.index(7 downto 0) )) <  r.numIfc           )
                         and ( to_integer(unsigned( r.reqParam.value(7 downto 0) )) <= AltSetIdxType'high )
                         ) then
                           v.ifcIdx   := to_integer(unsigned( r.reqParam.index(7 downto 0)));
                           v.altIdx   := to_integer(unsigned( r.reqParam.value(7 downto 0)));
                           v.tblOff   := USB2_DESC_IDX_LENGTH_C;
                           v.tblIdx   := r.cfgIdx;
                           v.descType := USB2_STD_DESC_TYPE_INTERFACE_C;
                           v.state    := DEACT_IFC;
                           v.epIdx    := 1;
                     end if;

                  when USB2_REQ_STD_SYNCH_FRAME_C       =>
                    -- TODO; not implemented yet
                  when others => 
               end case;
            end if;
            if ( v.state    = GET_PARAMS ) then
               v.protoStall := '1';
               -- if we cause a STALL we don't explicitly have to enter STATUS state;
               -- any transaction but a new SETUP will be STALLed by the packet processor.
               -- OTOH, we want to be ready for a new SETUP so going back to GET_PARAMS
               -- is what we have to do
            end if;

         -- skip the current descriptor and look for 'descType'
         when SCAN_DESC =>
            READ_TBL( v, SCAN_DESC_LOOP );

         when SCAN_DESC_LOOP =>
            v.skipDesc := not r.skipDesc;
            READ_TBL( v );
            if ( r.skipDesc ) then
               v.tblIdx := r.tblIdx + to_integer(unsigned(r.readVal));
               v.tblOff := USB2_DESC_IDX_TYPE_C;
            else
               v.tblOff := USB2_DESC_IDX_LENGTH_C;
               if ( usb2DescIsSentinel( r.readVal ) ) then
                  -- USB2_STD_DESC_TYPE_SENTINEL_C detected; -> end of table
                  v.protoStall := '1';
                  v.state      := GET_PARAMS;
               elsif ( Usb2StdDescriptorTypeType(r.readVal(3 downto 0)) = r.descType ) then
                  -- found; pre-read aux entry
                  v.tblOff := r.auxOff;
                  READ_TBL( v, r.retState );
               end if;
            end if;

         when SETUP_CONFIG =>
            if ( r.ifcIdx = r.numIfc ) then
               v.devStatus.state       := CONFIGURED;
               v.state                 := STATUS;
            else
               v.altSettings(r.ifcIdx) := 0;
               -- load endpoint table for this alt-setting
               v.tblOff                := USB2_DESC_IDX_LENGTH_C;
               v.descType              := USB2_STD_DESC_TYPE_INTERFACE_C;
               v.state                 := LOAD_ALT;
               v.altIdx                :=  0;
               v.err                   := '0';
            end if;

         when DEACT_IFC =>
            if ( r.epIdx > r.epAssocInp'high ) then
               v.state := LOAD_ALT;
            else
               if ( r.epAssocInp( r.epIdx ).ifc = r.ifcIdx ) then
                  v.epConfig( r.epIdx ).maxPktSizeInp := (others => '0');
               end if;
               if ( r.epAssocOut( r.epIdx ).ifc = r.ifcIdx ) then
                  v.epConfig( r.epIdx ).maxPktSizeOut := (others => '0');
               end if;
               v.epIdx := r.epIdx + 1;
            end if;

         when LOAD_ALT =>
            -- setup things to scan for the next descriptor
            v.retState := r.state;
            v.tblOff   := USB2_DESC_IDX_LENGTH_C;
            v.auxOff   := USB2_IFC_DESC_IDX_IFC_NUM_C;
            v.state    := SCAN_DESC;
            if    ( r.err = '1' ) then
               -- not found
               v.numEp := 0;
               v.state := LOAD_EPTS;
            elsif ( r.tblOff = USB2_IFC_DESC_IDX_IFC_NUM_C   ) then
               if ( r.ifcIdx = to_integer(unsigned(r.readVal)) ) then
                  v.tblOff := USB2_IFC_DESC_IDX_ALTSETTING_C;
                  READ_TBL( v );
               end if;
            elsif ( r.tblOff = USB2_IFC_DESC_IDX_ALTSETTING_C ) then
               if ( r.altIdx = to_integer(unsigned(r.readVal)) ) then
                  v.tblOff := USB2_IFC_DESC_IDX_NUM_ENDPOINTS_C;
                  READ_TBL( v );
               end if;
            elsif ( r.tblOff = USB2_IFC_DESC_IDX_NUM_ENDPOINTS_C ) then
               v.numEp    := to_integer(unsigned(r.readVal));
               v.state    := LOAD_EPTS;
            end if;

         when LOAD_EPTS =>
            if ( r.numEp = 0 ) then
               if ( r.reqParam.request(3 downto 0) = USB2_REQ_STD_SET_CONFIGURATION_C ) then
                  v.state  := SETUP_CONFIG;
                  v.ifcIdx := r.ifcIdx + 1;
               else
                  -- must be a SET_INTERFACE command
                  if ( r.err = '0' ) then
                     -- update
                     v.altSettings(r.ifcIdx) := r.altIdx;
                  end if;
                  v.state := STATUS;
               end if;
            else
               v.retState := r.state;
               v.auxOff   := USB2_EPT_DESC_IDX_ADDRESS_C;
               v.descType := USB2_STD_DESC_TYPE_ENDPOINT_C;
               v.state    := SCAN_DESC;

               if    ( r.tblOff = USB2_EPT_DESC_IDX_ADDRESS_C ) then
                  v.epIdx   := to_integer(unsigned(r.readVal(3 downto 0)));
                  v.epIsInp := (r.readVal(7) = '1');
                  v.tblOff  := USB2_EPT_DESC_IDX_ATTRIBUTES_C;
                  READ_TBL( v );
               elsif ( r.tblOff = USB2_EPT_DESC_IDX_ATTRIBUTES_C ) then
                  if ( r.epIsInp ) then
                     v.epConfig( r.epIdx ).transferTypeInp := r.readVal(1 downto 0);
                  else
                     v.epConfig( r.epIdx ).transferTypeOut := r.readVal(1 downto 0);
                  end if;
                  v.tblOff  := USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C;
                  READ_TBL( v );
               elsif ( r.tblOff = USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C     ) then
                  -- intermediate storage
                  v.tmpVal  := r.readVal;
                  v.tblOff  := USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C + 1;
                  READ_TBL( v );
               elsif ( r.tblOff = USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C + 1 ) then
                  if ( r.epIsInp ) then
                     v.epConfig( r.epIdx ).maxPktSizeInp := toPktSizeType(r.readVal & r.tmpVal);
                     v.epAssocInp( r.epIdx ).ifc         := r.ifcIdx;
                  else
                     v.epConfig( r.epIdx ).maxPktSizeOut := toPktSizeType(r.readVal & r.tmpVal);
                     v.epAssocOut( r.epIdx ).ifc         := r.ifcIdx;
                  end if;
                  v.numEp  := r.numEp - 1;
                  v.tblOff := USB2_DESC_IDX_LENGTH_C;
                  READ_TBL( v ); -- causes r.numEp to be checked before scanning the next desc.
               end if;
            end if;

         when GET_DESCRIPTOR_SIZE =>
            if ( r.count /= 0 ) then
               v.auxOff   := 0;
               v.retState := r.state;
               v.state    := SCAN_DESC;
               v.count    := r.count - 1;
            else
               if ( not r.tblRdDone ) then
                  READ_TBL( v );
               elsif ( r.size2B ) then
                  v.tblOff := r.tblOff - 1;
                  v.tmpVal := r.readVal;
                  v.size2B := false;
               else
                  if ( r.reqParam.length > w2u( r.tmpVal & r.readVal ) ) then
                     v.auxOff    := to_integer( w2u( r.tmpVal & r.readVal ) ) - 1 ;
                  else
                     v.auxOff    := to_integer(r.reqParam.length) - 1;
                     -- is the requested length an exact multiple of the packet size?
                     -- suppress zero-length delimiter in this case!
                     if ( hiSpeed = '1' ) then
                        v.sizeMatch := (r.reqParam.length(HS_EP0_PKT_SIZE_MSK_C'range) = HS_EP0_PKT_SIZE_MSK_C);
                     else
                        v.sizeMatch := (r.reqParam.length(FS_EP0_PKT_SIZE_MSK_C'range) = FS_EP0_PKT_SIZE_MSK_C);
                     end if;
                  end if;
                  v.tblOff := 0;
                  READ_TBL( v, READ_DESCRIPTOR );
                  v.flg    := '0';
               end if;
            end if;

         when READ_DESCRIPTOR =>
            -- apparently the host may cut a control-read short by
            -- requesting status earlier than indicated by the requested
            -- length...
            -- Thus, if we see an OUT token fly by we move to STATUS
            if ( tokOutSeen ) then
               v.state := STATUS;
            else
               epOb.mstInp.dat <= descVal;
               if ( r.patchOthCfg(0) = '1' ) then
                  epOb.mstInp.dat(Usb2StdDescriptorTypeType'range) <= std_logic_vector( USB2_STD_DESC_TYPE_OTHER_SPEED_CONF_C );
               end if;
               epOb.mstInp.vld <= not r.flg;
               epOb.mstInp.don <= r.flg;
               epOb.mstInp.err <= '0';
               if ( r.flg = '1' ) then
                  v.flg   := '0';
                  v.state := STATUS;
               else
                  if ( epIb.subInp.rdy = '1' ) then
                     -- account for pipeline delay when reading BRAM
                     if ( r.tblOff = r.auxOff + ite( DESCRIPTOR_BRAM_G, 1, 0 ) ) then
                        if ( r.sizeMatch ) then
                           v.state := STATUS;
                        else
                           v.flg := '1';
                        end if;
                     else
                        ramRenA  <= '1';
                        v.tblOff := r.tblOff + 1;
                     end if;
                     v.patchOthCfg := '0' & r.patchOthCfg(r.patchOthCfg'left downto 1);
                  end if;
               end if;
            end if;

         when RETURN_VALUE =>
            epOb.mstInp.dat <= r.retVal;
            epOb.mstInp.vld <= not r.flg;
            epOb.mstInp.don <= r.flg;
            epOb.mstInp.err <= '0';
            if ( r.flg = '1' ) then
               -- wait for send to be done
               v.flg := '0';
               v.state      := STATUS;
            elsif ( epIb.subInp.rdy = '1' ) then
               if ( r.retSz2 ) then
                  v.retVal := (others => '0');
                  v.retSz2 := false;
               else
                  -- done
                  v.flg    := '1';
               end if;
            end if;

         when STATUS =>
            if ( r.reqParam.dev2Host ) then
               epOb.subOut.rdy <= r.statusAck;

               -- wait for external agent done
               if ( ( not r.statusAck and ctlExt.ack ) = '1' ) then
                  v.statusAck  := '1';
               end if;

               if ( (r.statusAck and epIb.mstOut.don) = '1' ) then
                  v.state := GET_PARAMS;
               end if;

            else
               epOb.mstInp.vld <= '0';
               epOb.mstInp.err <= '0';
               epOb.mstInp.don <= r.statusAck;
               if ( r.statusAck = '0' ) then
                  -- packet processor keeps sending NAK until
                  -- it sees 'vld' or 'don'. Keep monitoring
                  -- the external agent
                  v.statusAck     := ctlExt.ack;
                  epOb.mstInp.don <= ctlExt.ack;
                  if ( ctlExt.ack = '1' ) then
                     if ( epIb.subInp.rdy = '1' ) then
                        v.state := GET_PARAMS;
                     end if;
                  end if;
               else
                  epOb.mstInp.don <= '1';
                  if ( epIb.subInp.rdy = '1' ) then
                     if ( r.reqParam.request = USB2_REQ_STD_SET_ADDRESS_C ) then
                           -- when SET_ADDRESS completed successfully we set the device address and
                           -- change state DEFAULT <=> ADDRESS
                           -- behaviour when CONFIGURED is undefined
                        v.devStatus.devAddr := Usb2DevAddrType(r.reqParam.value(Usb2DevAddrType'range));
                        if ( v.devStatus.devAddr = USB2_DEV_ADDR_DFLT_C ) then
                           v.devStatus.state := DEFAULT;
                        else
                           v.devStatus.state := ADDRESS;
                        end if;
                     end if;
                     v.state := GET_PARAMS;
                  end if;
               end if;
            end if;
      end case;

      devStatus <= r.devStatus;
      if ( suspend = '1' ) then
         devStatus.state <= SUSPENDED;
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

   G_DESC_BRAM : if ( DESCRIPTOR_BRAM_G ) generate
      attribute RAM_STYLE   : string;
      attribute ROM_STYLE   : string;

      constant AW_C   : positive         := numBits(DESCRIPTORS_G'high);

      function INIT_F return std_logic_vector is
         variable v : std_logic_vector(0 to 8*DESCRIPTORS_G'length - 1);
      begin
         for i in v'range loop
            v(i) := DESCRIPTORS_G( i / Usb2ByteType'length )( i mod Usb2ByteType'length );
         end loop;
         return v;
      end function INIT_F;

      signal   addrA  : unsigned(AW_C - 1 downto 0);

      signal descMem  : Usb2ByteArray(DESCRIPTORS_G'range) := DESCRIPTORS_G;

      attribute RAM_STYLE of descMem : signal is "BLOCK";
      attribute ROM_STYLE of descMem : signal is "BLOCK";

   begin

      addrA <= to_unsigned( r.tblIdx + r.tblOff, addrA'length );

      -- Note: I could not use Usb2Bram here - when used as
      --       a pure ROM vivado (2022.1) would always synthesize
      --       it into fabric; no ROM_STYLE/RAM_STYLE helped...
      --       It worked when applying the attributes to a signal
      --       (as opposed to a shared variable required by TDP)

      P_BRAM_A : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( ramRenA = '1' ) then
               ramDatA <= descMem( r.tblIdx + r.tblOff );
            end if;
         end if;
      end process P_BRAM_A;

      P_BRAM_B : process ( descRWClk ) is
      begin
         if ( rising_edge( descRWClk ) ) then
            if ( descRWIb.cen = '1' ) then
               descRWOb.rdata <= descMem( to_integer( descRWIb.addr ) );
               if ( descRWIb.wen = '1' ) then
                  descMem( to_integer( descRWIb.addr ) ) <= descRWIb.wdata;
               end if;
            end if;
         end if;
      end process P_BRAM_B;

   end generate G_DESC_BRAM;

   param     <= r.reqParam;
   epConfig  <= r.epConfig;

end architecture Impl;
