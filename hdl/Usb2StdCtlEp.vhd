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
      CFG_DESCRIPTORS_G : Usb2ByteArray;
      DEV_DESCRIPTOR_G  : Usb2ByteArray
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

      devStatus       : out Usb2DevStatusType
   );
end entity Usb2StdCtlEp;

architecture Impl of Usb2StdCtlEp is

   alias DSC_C : Usb2ByteArray is CFG_DESCRIPTORS_G;

   -- FIXME
   constant NAK_TIMEOUT_C : Usb2TimerType := to_unsigned( 100, Usb2TimerType'length );

   type StateType is (GET_PARAMS, WAIT_CTL_DONE, WAIT_EXT, WAIT_EXT_DONE, STD_REQUEST, RETURN_VALUE, STATUS);

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
   subtype IfcIdxType    is natural range 0 to MAX_INTERFACES_G - 1;

   type    AltSetArray   is array(IfcIdxType) of AltSetIdxType;

   type RegType   is record
      state       : StateType;
      devStatus   : Usb2DevStatusType;
      reqParam    : Usb2CtlReqParamType;
      parmIdx     : unsigned(2 downto 0);
      err         : std_logic;
      protoStall  : std_logic;
      epConfig    : Usb2EndpPairConfigArray(NUM_ENDPOINTS_G - 1 downto 0);
      cfgIdx      : Usb2DescIdxType;
      readIdx     : Usb2DescIdxType;
      retVal      : Usb2ByteType;
      retSz2      : boolean;
      flg         : std_logic;
      altSettings : AltSetArray;
      statusAck   : std_logic;
      timer       : Usb2TimerType;
   end record RegType;

   function REG_INIT_F return RegType is
      variable v : RegType;
   begin
      v.state       := GET_PARAMS;
      v.devStatus   := USB2_DEV_STATUS_INIT_C;
      v.reqParam    := USB2_CTL_REQ_PARAM_INIT_C;
      v.parmIdx     := (others => '0');
      v.err         := '0';
      v.protoStall  := '0';
      v.epConfig    := (others => USB2_ENDP_PAIR_CONFIG_INIT_C);
      v.cfgIdx      := 0;
      v.retVal      := (others => '0');
      v.altSettings := (others => 0);
      v.readIdx     := 0;
      v.flg         := '0';
      v.retSz2      := false;
      v.statusAck   := '1';
      v.timer       := (others => '0');
      b2u( v.epConfig(0).maxPktSizeInp, DEV_DESCRIPTOR_G, USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C );
      b2u( v.epConfig(0).maxPktSizeOut, DEV_DESCRIPTOR_G, USB2_DEV_DESC_IDX_MAX_PKT_SIZE0_C );
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
begin

   P_COMB : process ( r, epIb, ctlExt, ctlEpExt ) is
      variable v : RegType;
   begin
      v    := r;
      epOb <= USB2_ENDP_PAIR_IB_INIT_C;

      epOb.stalledInp           <= r.protoStall;
      epOb.stalledOut           <= r.protoStall;
      v.devStatus.clrHalt       := '0';
      v.devStatus.setHalt       := '0';
      v.devStatus.selHaltInp    := (others => '0');
      v.devStatus.selHaltOut    := (others => '0');

      if ( r.timer > 0 ) then
         v.timer := r.timer - 1;
      end if;

      case ( r.state ) is
         when GET_PARAMS =>
            v.err           := '0';
            v.flg           := '0';
            epOb.subOut.rdy <= '1';
            if ( epIb.mstCtl.vld = '1' ) then

               -- new request; clear the stall condition (protocol error)
               v.protoStall := '0';

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
            epOb.subOut.don <= r.flg;
            if ( epIb.mstCtl.don = '1' ) then
               if ( r.flg = '1' ) then
                  v.reqParam.vld  := '1';
                  v.state         := WAIT_EXT;
                  v.flg           := '0';
               else
                  v.flg           := '1';
               end if;
            end if;

         when WAIT_EXT =>
            if ( ctlExt.ack = '1' ) then
               if ( ctlExt.err = '1' ) then
                  v.state := STD_REQUEST;
               else
                  v.state := WAIT_EXT_DONE;
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
               v.state     := STATUS;
            end if;

         when STD_REQUEST =>
            -- dispatch standard requests

            -- by default bail
            v.protoStall := '1';
            v.state      := GET_PARAMS;
            v.retVal     := (others => '0');
            v.retSz2     := false;
            v.flg        := '0';
            v.statusAck  := '1';

            if (    ( r.reqParam.reqType = USB2_REQ_TYP_TYPE_STANDARD_C )
                and ( r.reqParam.request(7 downto 4) = "0000"           )
                and not (     ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_IFC_C )
                         and  ( unsigned(r.reqParam.index(7 downto 0)) >= numInterfaces(r)   )
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
                        if ( DSC_C( r.cfgIdx + USB2_CFG_DESC_IDX_ATTRIBUTES_C )(5) = '1' ) then
                           v.devStatus.remWakeup := ( r.reqParam.request(3 downto 0) = USB2_REQ_STD_SET_FEATURE_C );
                           v.state               := STATUS;
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
                     if ( r.devStatus.state = CONFIGURED ) then
                        v.retVal := DSC_C(r.cfgIdx + USB2_CFG_DESC_IDX_CFG_VALUE_C);
                     end if;
                     v.state := RETURN_VALUE;

                  when USB2_REQ_STD_GET_DESCRIPTOR_C    =>

                  when USB2_REQ_STD_GET_INTERFACE_C     =>
                     if ( r.devStatus.state = CONFIGURED ) then
                        if ( unsigned( r.reqParam.index(6 downto 0) ) < r.altSettings'length ) then
                           v.retVal := altSetSlv8( r, unsigned( r.reqParam.index( 6 downto 0 ) ) );
                           v.state  := RETURN_VALUE;
                        end if;
                     end if;

                  when USB2_REQ_STD_GET_STATUS_C        =>
                     v.retSz2 := true;
                     if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_DEV_C )
                     then
                        -- self powered
                        v.retVal(0) := DSC_C( r.cfgIdx + USB2_CFG_DESC_IDX_ATTRIBUTES_C )(6);
                        -- remote wakeup
                        v.retVal(1) := DSC_C( r.cfgIdx + USB2_CFG_DESC_IDX_ATTRIBUTES_C )(5);
                        v.state     := RETURN_VALUE;
                     elsif (    ( r.devStatus.state = CONFIGURED )
                             or ( r.reqParam.index(6 downto 0) = "0000000" ) )
                     then
                        if    ( r.reqParam.recipient = USB2_REQ_TYP_RECIPIENT_EPT_C ) then
                           if (     unsigned(r.reqParam.index(3 downto 0)) < NUM_ENDPOINTS_G ) then
                              v.state     := RETURN_VALUE;
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
                          v.state := RETURN_VALUE;
                          -- ignore check for invalid interface
                        end if;
                     end if;

                  when USB2_REQ_STD_SET_ADDRESS_C       =>
                     v.state := STATUS;

                  when USB2_REQ_STD_SET_CONFIGURATION_C =>
                  when USB2_REQ_STD_SET_DESCRIPTOR_C    =>
                    -- unsupported
                  when USB2_REQ_STD_SET_INTERFACE_C     =>
                  when USB2_REQ_STD_SYNCH_FRAME_C       =>
                  when others => 
               end case;
            end if;
            if ( v.state /= GET_PARAMS ) then
               v.protoStall := '0';
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
                     v.protoStall := '1';
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
            -- when successfully SET_ADDRESS completed we set the device address and change state DEFAULT <=> ADDRESS
            -- behaviour when CONFIGURED is undefined
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

end architecture Impl;
