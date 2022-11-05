library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.Usb2Pkg.all;
use     work.UlpiPkg.all;
use     work.UsbUtilPkg.all;
use     work.Usb2DescPkg.all;

entity Usb2StdCtlEp is
   generic (
      MARK_DEBUG_G      : boolean  := true;
      NUM_ENDPOINTS_G   : positive;
      MAX_INTERFACES_G  : natural;
      MAX_ALTSETTINGS_G : positive;
      DESCRIPTORS_G     : Usb2ByteArray;
      -- CFG_IDX_TABLE_G must start with a dummy element
      -- for configuration # 0
      CFG_IDX_TABLE_G   : Usb2DescIdxArray
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';

      -- EP0 connection to the packet engine
      epIb            : in  Usb2EndpPairObType;
      epOb            : out Usb2EndpPairIbType;

      -- observe other endpoints
      usrEpIb         : in  Usb2EndpPairIbArray(1 to NUM_ENDPOINTS_G - 1) := (others => USB2_ENDP_PAIR_IB_INIT_C);

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
      ctlExt          : in  Usb2CtlExtType     := USB2_CTL_EXT_INIT_C;
      ctlEpExt        : in  Usb2EndpPairIbType := USB2_ENDP_PAIR_IB_INIT_C;

      devStatus       : out Usb2DevStatusType;
      epConfig        : out Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_G - 1)
   );
end entity Usb2StdCtlEp;

architecture Impl of Usb2StdCtlEp is

   alias DSC_C : Usb2ByteArray is DESCRIPTORS_G;

   -- FIXME
   constant NAK_TIMEOUT_C : Usb2TimerType := to_unsigned( 100, Usb2TimerType'length );

   type StateType is (
      GET_PARAMS,
      WAIT_CTL_DONE,
      WAIT_EXT,
      WAIT_EXT_DONE,
      STD_REQUEST,
      READ_TBL,
      SCAN_DESC,
      SETUP_CONFIG,
      LOAD_ALT,
      LOAD_EPTS,
      DEV_FEATURE,
      RETURN_VALUE,
      STATUS
   );

   function numConfigs
   return natural is
      variable v : natural;
   begin
      v := to_integer( unsigned( DESCRIPTORS_G( CFG_IDX_TABLE_G(0) +  USB2_DEV_DESC_IDX_NUM_CONFIGURATIONS_C ) ) );
      report integer'image(v) & " Configurations";
      return v;
   end function numConfigs;

   function epIdx(constant x: Usb2CtlReqParamType)
   return natural is
   begin
      return to_integer( unsigned( x.index(3 downto 0) ) );
   end function epIdx;

   procedure b2u(variable v : out unsigned; constant a: in Usb2ByteArray; constant o : in natural) is
   begin
      v := resize( unsigned( a(o) ), v'length );
   end procedure b2u;

   procedure w2u(variable v : out unsigned; constant a: in Usb2ByteArray; constant o : in natural) is
      constant x : std_logic_vector(15 downto 0) := a(o+1) & a(0);
   begin
      v := resize( unsigned( x ), v'length );
   end procedure w2u;

   subtype AltSetIdxType is natural range 0 to MAX_ALTSETTINGS_G - 1;
   subtype IfcIdxType    is natural range 0 to MAX_INTERFACES_G;
   subtype EpIdxType     is natural range 0 to NUM_ENDPOINTS_G;
   subtype CfgIdxType    is natural range 0 to numConfigs;

   type    AltSetArray   is array(IfcIdxType) of AltSetIdxType;

   type RegType   is record
      state       : StateType;
      retState    : StateType;
      devStatus   : Usb2DevStatusType;
      reqParam    : Usb2CtlReqParamType;
      parmIdx     : unsigned(2 downto 0);
      err         : std_logic;
      protoStall  : std_logic;
      epConfig    : Usb2EndpPairConfigArray(0 to NUM_ENDPOINTS_G - 1);
      cfgIdx      : Usb2DescIdxType;
      cfgCurr     : CfgIdxType;
      retVal      : Usb2ByteType;
      retSz2      : boolean;
      flg         : std_logic;
      tblIdx      : Usb2DescIdxType;
      tblOff      : Usb2DescIdxType;
      auxOff      : Usb2DescIdxType;
      tblRdDone   : boolean;
      altSettings : AltSetArray;
      statusAck   : std_logic;
      timer       : Usb2TimerType;
      ifcIdx      : IfcIdxType;
      altIdx      : AltSetIdxType;
      numIfc      : IfcIdxType;
      epIdx       : EpIdxType;
      epIsInp     : boolean;
      numEp       : EpIdxType;
      descType    : Usb2StdDescriptorTypeType;
   end record RegType;

   function REG_INIT_F return RegType is
      variable v : RegType;
   begin
      v.state       := GET_PARAMS;
      v.retState    := GET_PARAMS;
      v.devStatus   := USB2_DEV_STATUS_INIT_C;
      v.reqParam    := USB2_CTL_REQ_PARAM_INIT_C;
      v.parmIdx     := (others => '0');
      v.err         := '0';
      v.protoStall  := '0';
      v.epConfig    := (others => USB2_ENDP_PAIR_CONFIG_INIT_C);
      v.cfgIdx      := 0;
      v.cfgCurr     := 0;
      v.retVal      := (others => '0');
      v.altSettings := (others => 0);
      v.flg         := '0';
      v.tblIdx      := 0;
      v.tblOff      := 0;
      v.auxOff      := 0;
      v.tblRdDone   := false;
      v.retSz2      := false;
      v.statusAck   := '1';
      v.timer       := (others => '0');
      v.ifcIdx      := 0;
      v.numIfc      := 0;
      v.epIdx       := 0;
      v.epIsInp     := false;
      v.descType    := (others => '0');
      for i in 1 to v.epConfig'length - 1 loop
         v.epConfig(i).hasHaltInp := true;
         v.epConfig(i).hasHaltOut := true;
      end loop;
      b2u( v.epConfig(0).maxPktSizeInp, DESCRIPTORS_G, CFG_IDX_TABLE_G(0) + USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C );
      b2u( v.epConfig(0).maxPktSizeOut, DESCRIPTORS_G, CFG_IDX_TABLE_G(0) + USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C );
      report "Max pkt size 0 " & integer'image(to_integer(v.epConfig(0).maxPktSizeInp));
      return v;
   end function REG_INIT_F;

   signal r   : RegType := REG_INIT_F;
   signal rin : RegType;

   function numInterfaces(constant x : in RegType)
   return natural is
   begin 
      return to_integer( unsigned( DSC_C( x.cfgIdx + USB2_CFG_DESC_IDX_NUM_INTERFACES_C ) ) );
   end function numInterfaces;

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

   signal tblAddr : Usb2DescIdxType;
begin


   P_COMB : process ( r, epIb, ctlExt, ctlEpExt ) is
      variable v       : RegType;
      variable descVal : Usb2ByteType;
   begin
      v    := r;
      epOb                      <= USB2_ENDP_PAIR_IB_INIT_C;

      descVal                   := DSC_C( r.tblIdx + r.tblOff );

      epOb.stalledInp           <= r.protoStall;
      epOb.stalledOut           <= r.protoStall;
      v.devStatus.clrHalt       := '0';
      v.devStatus.setHalt       := '0';
      v.devStatus.selHaltInp    := (others => '0');
      v.devStatus.selHaltOut    := (others => '0');

      v.reqParam.vld            := '0';

      if ( r.timer > 0 ) then
         v.timer := r.timer - 1;
      end if;

      case ( r.state ) is
         when GET_PARAMS =>
            v.err           := '0';
            v.flg           := '0';
            v.tblRdDone     := false;
            epOb.subOut.rdy <= '1';
            if ( epIb.mstCtl.vld = '1' ) then

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
                     v.state               := WAIT_EXT;
                     v.reqParam.vld        := '1';
               end case;
               v.parmIdx := r.parmIdx + 1;
            end if;

         when WAIT_EXT =>
            if ( ctlExt.ack = '1' ) then
               if ( ctlExt.err = '1' ) then
                  v.state    := STD_REQUEST;
               else
                  v.retState := WAIT_EXT_DONE;
                  v.state    := WAIT_CTL_DONE;
               end if;
            end if;


         when WAIT_CTL_DONE =>
            epOb.subOut.don <= r.flg;
            epOb.subOut.err <= r.err;
            if ( epIb.mstCtl.don = '1' ) then
               if ( r.flg = '1' ) then
                  v.state         := r.retState;
                  v.flg           := '0';
               else
                  v.flg           := '1';
               end if;
            end if;

         when WAIT_EXT_DONE =>
            epOb <= ctlEpExt;
            if ( ctlExt.don = '1' ) then
               v.err       := ctlExt.err;
               v.statusAck := ctlExt.ack;
               if ( ctlExt.ack = '0' ) then
                  v.timer := NAK_TIMEOUT_C;
               end if;
               v.state    := STATUS;
            end if;

         when READ_TBL =>
            v.retVal      := descVal;
            v.state       := r.retState;
            v.tblRdDone   := true;

         when STD_REQUEST =>
            -- dispatch standard requests

            -- by default bail
            v.state       := WAIT_CTL_DONE;
            v.retState    := GET_PARAMS;
            v.err         := '1';
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
                        v.tblIdx   := r.cfgIdx;
                        v.tblOff   := USB2_CFG_DESC_IDX_ATTRIBUTES_C;
                        v.retState := DEV_FEATURE;
                        v.state    := READ_TBL;
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
                                    v.retState          := STATUS;
                                    v.err               := '0';
                                 elsif ( hasHaltInp( r, r.reqParam.index(3 downto 0) ) ) then
                                    v.devStatus.selHaltInp(epIdx(r.reqParam)) := '1';
                                    v.devStatus.setHalt := '1';
                                    v.retState          := STATUS;
                                    v.err               := '0';
                                 end if;
                              else
                                 -- this resets the data toggles on the target endpoint
                                 if ( r.reqParam.index(7) = '0' ) then 
                                    v.devStatus.selHaltOut(epIdx(r.reqParam)) := '1';
                                    v.devStatus.clrHalt := '1';
                                    v.retState          := STATUS;
                                    v.err               := '0';
                                 else
                                    v.devStatus.selHaltInp(epIdx(r.reqParam)) := '1';
                                    v.devStatus.clrHalt := '1';
                                    v.retState          := STATUS;
                                    v.err               := '0';
                                 end if;
                              end if;
                           end if;
                        end if;
                     end if;

                  when USB2_REQ_STD_GET_CONFIGURATION_C =>
                     v.retVal   := std_logic_vector(to_unsigned(r.cfgCurr, v.retVal'length));
                     v.retState := RETURN_VALUE;
                     v.err      := '0';

                  when USB2_REQ_STD_GET_DESCRIPTOR_C    =>
                    -- TODO; not implemented yet

                  when USB2_REQ_STD_GET_INTERFACE_C     =>
                     if ( r.devStatus.state = CONFIGURED ) then
                        if ( unsigned( r.reqParam.index(6 downto 0) ) < r.altSettings'length ) then
                           v.retVal    := altSetSlv8( r, unsigned( r.reqParam.index( 6 downto 0 ) ) );
                           v.retState  := RETURN_VALUE;
                           v.err       := '0';
                        end if;
                     end if;

                  when USB2_REQ_STD_GET_STATUS_C        =>
                     v.retSz2 := true;
                     if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_DEV_C )
                     then
                        if ( r.tblRdDone ) then
                           -- self powered
                           v.retVal    := x"00";
                           v.retVal(0) := DSC_C( r.cfgIdx + USB2_CFG_DESC_IDX_ATTRIBUTES_C )(6);
                           -- remote wakeup
                           v.retVal(1) := DSC_C( r.cfgIdx + USB2_CFG_DESC_IDX_ATTRIBUTES_C )(5);
                           v.retState  := RETURN_VALUE;
                           v.err       := '0';
                        else
                           v.tblIdx    := r.cfgIdx;
                           v.tblOff    := USB2_CFG_DESC_IDX_ATTRIBUTES_C;
                           v.retState  := r.state;
                           v.state     := READ_TBL;
                        end if;
                     elsif (    ( r.devStatus.state = CONFIGURED )
                             or ( r.reqParam.index(6 downto 0) = "0000000" ) )
                     then
                        if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_EPT_C ) then
                           if (     unsigned(r.reqParam.index(3 downto 0)) < NUM_ENDPOINTS_G ) then
                              v.retState  := RETURN_VALUE;
                              v.err       := '0';
                              if ( unsigned(r.reqParam.index(3 downto 0)) > 0 ) then
                                 if ( r.reqParam.index(7) = '0' ) then
                                    v.retVal(0) := usrEpIb( to_integer( unsigned( r.reqParam.index(3 downto 0) ) ) ).stalledOut;
                                 else
                                    v.retVal(0) := usrEpIb( to_integer( unsigned( r.reqParam.index(3 downto 0) ) ) ).stalledInp;
                                 end if;
                              else
                                 -- EP0 is never halted
                              end if;
                           end if;
                        else
                          v.retState := RETURN_VALUE;
                          v.err      := '0';
                          -- ignore check for invalid interface
                        end if;
                     end if;

                  when USB2_REQ_STD_SET_ADDRESS_C       =>
                     v.retState := STATUS;
                     v.err      := '0';

                  when USB2_REQ_STD_SET_CONFIGURATION_C =>
                     if ( r.reqParam.value(7 downto 0) = x"00" ) then
                        v.devStatus.state := ADDRESS;
                        v.retState        := STATUS;
                        v.err             := '0';
                        v.cfgCurr         := 0;
                     elsif ( unsigned( r.reqParam.value(7 downto 0) ) <= numConfigs ) then
                        -- assume the configuration value equals the index in the CFG_IDX_TABLE_G!
                        if ( not r.tblRdDone ) then
                           v.cfgCurr         := to_integer( unsigned( r.reqParam.value( 7 downto 0 ) ) );
                           v.cfgIdx          := CFG_IDX_TABLE_G( v.cfgCurr );
                           v.tblIdx          := v.cfgIdx;
                           v.tblOff          := USB2_CFG_DESC_IDX_NUM_INTERFACES_C;
                           v.ifcIdx          := 0;
                           v.epIdx           := 0;
                           v.retState        := r.state;
                           v.state           := READ_TBL;
                        else
                           v.retState        := SETUP_CONFIG;
                           v.state           := WAIT_CTL_DONE;
                           v.err             := '0';
                           v.numIfc          := to_integer(unsigned(descVal));
                           for i in 1 to v.epConfig'length - 1 loop
                              v.epConfig(i).maxPktSizeInp := (others => '0');
                              v.epConfig(i).maxPktSizeOut := (others => '0');
                           end loop;
                        end if;
                     end if;

                  when USB2_REQ_STD_SET_DESCRIPTOR_C    =>
                    -- unsupported
                  when USB2_REQ_STD_SET_INTERFACE_C     =>
                    -- TODO; not implemented yet
                  when USB2_REQ_STD_SYNCH_FRAME_C       =>
                    -- TODO; not implemented yet
                  when others => 
               end case;
            end if;

         when DEV_FEATURE =>
            v.retState := GET_PARAMS;
            if ( r.retVal(5) = '1' ) then
               v.devStatus.remWakeup := ( r.reqParam.request(3 downto 0) = USB2_REQ_STD_SET_FEATURE_C );
               v.retState            := STATUS;
               v.err                 := '0';
            end if;
            v.state := WAIT_CTL_DONE;

         -- skip the current descriptor and look for 'descType'
         when SCAN_DESC =>
            v.tblRdDone := not r.tblRdDone;
            if ( not r.tblRdDone ) then
               v.tblIdx := r.tblIdx + to_integer(unsigned(descVal));
               v.tblOff := USB2_DESC_IDX_TYPE_C;
            else
               v.tblOff := USB2_DESC_IDX_LENGTH_C;
               if ( Usb2StdDescriptorTypeType(descVal(3 downto 0)) = r.descType ) then
                  -- found; pre-read aux entry
                  v.tblOff := r.auxOff;
                  v.state  := r.retState;
               end if;
            end if;

         when SETUP_CONFIG =>
            if ( r.ifcIdx = r.numIfc ) then
               v.devStatus.state := CONFIGURED;
               v.state           := STATUS;
               v.err             := '0';
            else
               v.altSettings(r.ifcIdx) := 0;
               -- load endpoint table for this alt-setting
               v.tblOff                := USB2_DESC_IDX_LENGTH_C;
               v.descType              := USB2_STD_DESC_TYPE_INTERFACE_C;
               v.state                 := LOAD_ALT;
            end if;

         when LOAD_ALT =>
            -- setup things to scan for the next descriptor
            v.retState := r.state;
            v.tblOff   := USB2_DESC_IDX_LENGTH_C;
            v.auxOff   := USB2_IFC_DESC_IDX_IFC_NUM_C;
            v.state    := SCAN_DESC;
            if    ( r.tblOff = USB2_IFC_DESC_IDX_IFC_NUM_C   ) then
               if ( r.ifcIdx = to_integer(unsigned(descVal)) ) then
                  v.tblOff := USB2_IFC_DESC_IDX_ALTSETTING_C;
                  v.state  := r.state;
               end if;
            elsif ( r.tblOff = USB2_IFC_DESC_IDX_ALTSETTING_C ) then
               if ( r.altSettings(r.ifcIdx) = to_integer(unsigned(descVal)) ) then
                  v.tblOff := USB2_IFC_DESC_IDX_NUM_ENDPOINTS_C;
                  v.state  := r.state;
               end if;
            elsif ( r.tblOff = USB2_IFC_DESC_IDX_NUM_ENDPOINTS_C ) then
               v.numEp    := to_integer(unsigned(descVal));
               v.ifcIdx   := r.ifcIdx + 1;
               v.state    := LOAD_EPTS;
            end if;

         when LOAD_EPTS =>
            if ( r.numEp = 0 ) then
               if ( r.reqParam.request(3 downto 0) = USB2_REQ_STD_SET_CONFIGURATION_C ) then
                  v.state := SETUP_CONFIG;
               end if;
            else
               v.retState := r.state;
               v.auxOff   := USB2_EPT_DESC_IDX_ADDRESS_C;
               v.descType := USB2_STD_DESC_TYPE_ENDPOINT_C;
               v.state    := SCAN_DESC;

               if    ( r.tblOff = USB2_EPT_DESC_IDX_ADDRESS_C ) then
report integer'image(r.tblOff) & " " & integer'image(to_integer(unsigned(descVal(3 downto 0)))) & " " & integer'image(r.tblIdx);
                  v.epIdx   := to_integer(unsigned(descVal(3 downto 0)));
                  v.epIsInp := (descVal(7) = '1');
                  v.tblOff  := USB2_EPT_DESC_IDX_ATTRIBUTES_C;
                  v.state   := r.state;
               elsif ( r.tblOff = USB2_EPT_DESC_IDX_ATTRIBUTES_C ) then
                  if ( r.epIsInp ) then
                     v.epConfig( r.epIdx ).transferTypeInp := descVal(1 downto 0);
                  else
                     v.epConfig( r.epIdx ).transferTypeOut := descVal(1 downto 0);
                  end if;
                  v.tblOff  := USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C;
                  v.state   := r.state;
               elsif ( r.tblOff = USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C     ) then
                  v.tblOff  := USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C + 1;
                  v.state   := r.state;
                  -- intermediate storage
                  v.retVal  := descVal;
               elsif ( r.tblOff = USB2_EPT_DESC_IDX_MAX_PKT_SIZE_C + 1 ) then
                  if ( r.epIsInp ) then
                     v.epConfig( r.epIdx ).maxPktSizeInp := toPktSizeType(descVal & r.retVal);
                  else
                     v.epConfig( r.epIdx ).maxPktSizeOut := toPktSizeType(descVal & r.retVal);
                  end if;
                  v.numEp  := r.numEp - 1;
                  v.tblOff := USB2_DESC_IDX_LENGTH_C;
                  v.state  := r.state; -- causes r.numEp to be checked before scanning the next desc.
               end if;
            end if;

         when RETURN_VALUE =>
            epOb.mstInp.dat <= r.retVal;
            epOb.mstInp.vld <= not r.flg;
            epOb.mstInp.don <= r.flg;
            epOb.mstInp.err <= '0';
            if ( r.flg = '1' ) then
               -- wait for send to be done
               if ( epIb.subInp.don = '1' ) then
                  v.flg := '0';
                  if ( epIb.subInp.err = '1' ) then
                     -- no status
                     v.state      := GET_PARAMS; 
                  else
                     v.state      := STATUS;
                  end if;
               end if;
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
               epOb.subOut.err <= '0';

               if ( r.statusAck = '0' ) then
                  -- need a timeout as we won't see
                  -- anything from the host; the handshake is handled
                  -- by the packet buffer
                  if ( r.timer = 0 ) then
                     v.state := GET_PARAMS;
                  end if;
               else
                  epOb.subOut.rdy <= '1';
                  epOb.subOut.err <= '0';
                  epOb.subOut.don <= r.flg;
                  if ( epIb.mstOut.don = '1' ) then
                     if ( r.flg = '0' ) then
                        v.flg := '1';
                     else
                        v.state := GET_PARAMS;
                     end if;
                  end if;
               end if;
            else
               epOb.mstInp.vld <= '0';
               epOb.mstInp.err <= '0';
               epOb.mstInp.don <= r.statusAck;
               if ( r.statusAck = '0' ) then
                   -- need a timeout as we won't see
                   -- anything from the host; the handshake is handled
                   -- by the packet buffer
                  if ( r.timer = 0 ) then
                     v.state := GET_PARAMS;
                  end if;
               else
                  if ( epIb.subInp.don = '1' ) then
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

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_F;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   param     <= r.reqParam;
   devStatus <= r.devStatus;
   epConfig  <= r.epConfig;

end architecture Impl;
