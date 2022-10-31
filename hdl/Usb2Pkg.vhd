library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package Usb2Pkg is

   subtype Usb2PidType      is std_logic_vector(3 downto 0);
   subtype Usb2PidGroupType is std_logic_vector(1 downto 0);

   subtype Usb2EndpIdxType  is unsigned(3 downto 0);
   subtype Usb2DevAddrType  is std_logic_vector(6 downto 0);

   subtype Usb2ByteType     is std_logic_vector(7 downto 0);
 

   constant USB2_DEV_ADDR_DFLT_C    : Usb2DevAddrType := (others => '0');
   constant USB2_ENDP_ZERO_C        : Usb2EndpIdxType := (others => '0');

   function usb2PidIsTok(constant x : in Usb2PidType) return boolean;
   function usb2PidIsDat(constant x : in Usb2PidType) return boolean;
   function usb2PidIsHsk(constant x : in Usb2PidType) return boolean;
   function usb2PidIsSpc(constant x : in Usb2PidType) return boolean;

   function usb2PidGroup(constant x : in Usb2PidType) return Usb2PidGroupType;

   constant USB2_PID_GROUP_TOK_C: Usb2PidGroupType := "01";
   constant USB2_PID_GROUP_DAT_C: Usb2PidGroupType := "11";
   constant USB2_PID_GROUP_HSK_C: Usb2PidGroupType := "10";
   constant USB2_PID_GROUP_SPC_C: Usb2PidGroupType := "00";

   constant USB2_PID_TOK_OUT_C  : Usb2PidType := x"1";
   constant USB2_PID_TOK_SOF_C  : Usb2PidType := x"5";
   constant USB2_PID_TOK_IN_C   : Usb2PidType := x"9";
   constant USB2_PID_TOK_SETUP_C: Usb2PidType := x"D";

   constant USB2_PID_DAT_DATA0_C: Usb2PidType := x"3";
   constant USB2_PID_DAT_DATA2_C: Usb2PidType := x"7";
   constant USB2_PID_DAT_DATA1_C: Usb2PidType := x"B";
   constant USB2_PID_DAT_MDATA_C: Usb2PidType := x"F";

   constant USB2_PID_HSK_ACK_C  : Usb2PidType := x"2";
   constant USB2_PID_HSK_NYET_C : Usb2PidType := x"6";
   constant USB2_PID_HSK_NAK_C  : Usb2PidType := x"A";
   constant USB2_PID_HSK_STALL_C: Usb2PidType := x"E";

   constant USB2_PID_SPC_PRE_C  : Usb2PidType := x"C";
   constant USB2_PID_SPC_ERR_C  : Usb2PidType := x"C"; -- reused
   constant USB2_PID_SPC_SPLIT_C: Usb2PidType := x"8";
   constant USB2_PID_SPC_PING_C : Usb2PidType := x"4";

   constant USB2_PID_SPC_NONE_C : Usb2PidType := x"0"; -- reserved

   type Usb2PktHdrType is record
      pid     : Usb2PidType;
      tokDat  : std_logic_vector(10 downto 0);
      vld     : std_logic; -- asserted for 1 cycle
   end record Usb2PktHdrType;

   constant USB2_PKT_HDR_INIT_C : Usb2PktHdrType := (
      pid     => USB2_PID_SPC_NONE_C,
      tokDat  => (others => '0'),
      vld     => '0'
   );

   function usb2TokenPktAddr(constant x : in Usb2PktHdrType)
      return Usb2DevAddrType;

   function usb2TokenPktEndp(constant x : in Usb2PktHdrType)
      return Usb2EndpIdxType;

   type Usb2StrmMstType is record
      dat   : std_logic_vector(7 downto 0);
      usr   : std_logic_vector(3 downto 0);
      vld   : std_logic;
      don   : std_logic;
      err   : std_logic; -- when asserted with 'don' then there was e.g., a bad checksum
   end record Usb2StrmMstType;

   constant USB2_STRM_MST_INIT_C : Usb2StrmMstType := (
      dat   => (others => '0'),
      usr   => (others => '0'),
      vld   => '0',
      don   => '0',
      err   => '0'
   );

   type Usb2StrmSubType is record
      rdy   : std_logic;
      -- if an error occurs then the stream is aborted (sender must stop)
      -- i.e., 'don' may be asserted before all the data are sent!
      err   : std_logic;
      don   : std_logic;
   end record Usb2StrmSubType;

   constant USB2_STRM_SUB_INIT_C : Usb2StrmSubType := (
      rdy   => '0',
      err   => '0',
      don   => '0'
   );

   constant USB2_CRC5_POLY_C  : std_logic_vector(15 downto 0) := x"0014";
   constant USB2_CRC5_CHCK_C  : std_logic_vector(15 downto 0) := x"0006";
   constant USB2_CRC5_INIT_C  : std_logic_vector(15 downto 0) := x"001F";

   constant USB2_CRC16_POLY_C : std_logic_vector(15 downto 0) := x"A001";
   constant USB2_CRC16_CHCK_C : std_logic_vector(15 downto 0) := x"B001";
   constant USB2_CRC16_INIT_C : std_logic_vector(15 downto 0) := x"FFFF";

   type Usb2DevStateType is (POWERED, DEFAULT, ADDRESS, CONFIGURED, SUSPENDED);

   type Usb2DevStatusType is record
      state      : Usb2DevStateType;
      devAddr    : Usb2DevAddrType;
      clrHaltInp : std_logic_vector(15 downto 0);
      clrHaltOut : std_logic_vector(15 downto 0);
   end record;

   -- signals traveling from EP -> bus
   type Usb2EndpPairIbType is record
      stalledInp : std_logic; -- input  endpoint is halted
      stalledOut : std_logic; -- output endpoint is halted
      -- if mstInp.vld is asserted then the endpoint
      -- must be able to supply the entire payload of
      -- a data packet (or less if there is no data; 
      -- empty packets are sent setting 'vld = 0, don = 1'
      mstInp     : Usb2StrmMstType;
      -- if subOut.rdy is asserted then the endpoint
      -- must be able to absorb an entire payload of
      -- packet data.
      -- Note that it is only known once the packet
      -- is 'done' if the data are valid (but it is
      -- the EP's job to implement a buffer which
      -- must be invalidated if the data turn out to
      -- be bad).
      subOut     : Usb2StrmSubType;
   end record Usb2EndpPairIbType;

   constant USB2_ENDP_PAIR_IB_INIT_C : Usb2EndpPairIbType := (
      stalledInp => '0',
      stalledOut => '0',
      mstInp     => USB2_STRM_MST_INIT_C,
      subOut     => USB2_STRM_SUB_INIT_C
   );
 
   -- signals traveling from bus -> EP
   type Usb2EndpPairObType is record
      mstOut     : Usb2StrmMstType;
      -- the don/err/rdy bits encode the following information
      --   rdy don err
      --   1/0  0   x   normal handshake for data transfer
      --    1   1   0   partial buffer has been transmitted
      --                no data must be transferred during the
      --                current cycle but the sender must remember
      --                the current stream pointer for a retry operation
      --    1   1   1   transmission of partial buffer must be retried
      --                => rewind the stream pointer to the last
      --                   remembered position
      --    0   1   0   => transmission completed successfully
      --    0   1   1   => transmission aborted
      ------------------------------------
      --   if ( don = '1' ) then
      --      if ( rdy = '0' ) then
      --         if ( err = '1' ) then
      --            abort
      --         else
      --            done
      --         end if;
      --      elsif ( err = '0' ) then
      --         last_ptr <= curr_ptr;
      --      else
      --         curr_ptr <= last_ptr; --rewind!
      --      end if;
      --  elsif ( rdy = '1' ) then
      --      output := data(curr_ptr);
      --      curr_ptr <= curr_ptr + 1;
      --  end if;
      --        
      subInp     : Usb2StrmSubType;
      -- control endpoints receive setup data here;
      -- they MUST accept, thus there is no corresponding
      -- subordinate.
      mstCtl     : Usb2StrmMstType;
   end record Usb2EndpPairObType;

   constant USB2_ENDP_PAIR_OB_INIT_C : Usb2EndpPairObType := (
      mstOut     => USB2_STRM_MST_INIT_C,
      subInp     => USB2_STRM_SUB_INIT_C,
      mstCtl     => USB2_STRM_MST_INIT_C
   );

   subtype Usb2TransferType is std_logic_vector(1 downto 0);

   subtype Usb2PktSizeType  is unsigned(10 downto 0);

   constant USB2_TT_CONTROL_C     : Usb2TransferType := "00";
   constant USB2_TT_ISOCHRONOUS_C : Usb2TransferType := "01";
   constant USB2_TT_BULK_C        : Usb2TransferType := "10";
   constant USB2_TT_INTERRUPT_C   : Usb2TransferType := "11";

   -- this information is passed via generic to the packet
   -- processor but also passed into the endpoint descriptor
   -- Note that the endpoint address/number is implicitly
   -- encoded (place of the endpoint in an array).
   -- If one direction of a pair is unsupported/not implemented
   -- then 'maxPktSize' must be set to 0.
   type Usb2EndpPairPropertyType is record
      transferTypeInp  : Usb2TransferType;
      maxPktSizeInp    : Usb2PktSizeType;
      hasHaltInp       : boolean;
      transferTypeOut  : Usb2TransferType;
      maxPktSizeOut    : Usb2PktSizeType;
      hasHaltOut       : boolean;
   end record Usb2EndpPairPropertyType;

   type Usb2EndpPairPropertyArray is array (natural range <>) of Usb2EndpPairPropertyType;
   type Usb2EndpPairIbArray       is array (natural range <>) of Usb2EndpPairIbType;
   type Usb2EndpPairObArray       is array (natural range <>) of Usb2EndpPairObType;

   type Usb2DevPropertyType is record
      hasRemoteWakeup  : boolean;
   end record Usb2DevPropertyType;

   function USB2_REQ_TYP_DEV2HOST_F (constant reqTyp : in Usb2ByteType) return boolean;
   function USB2_REQ_TYP_TYPE_F     (constant reqTyp : in Usb2ByteType) return std_logic_vector;
   function USB2_REQ_TYP_RECIPIENT_F(constant reqTyp : in Usb2ByteType) return std_logic_vector;

   constant USB2_REQ_TYP_TYPE_STANDARD_C           : std_logic_vector(1 downto 0) := "00";
   constant USB2_REQ_TYP_TYPE_CLASS_C              : std_logic_vector(1 downto 0) := "01";
   constant USB2_REQ_TYP_TYPE_VENDOR_C             : std_logic_vector(1 downto 0) := "10";

   constant USB2_REQ_TYP_RECIPIENT_DEV_C           : std_logic_vector(1 downto 0) := "00";
   constant USB2_REQ_TYP_RECIPIENT_IRC_C           : std_logic_vector(1 downto 0) := "01";
   constant USB2_REQ_TYP_RECIPIENT_EPT_C           : std_logic_vector(1 downto 0) := "10";

   subtype  Usb2StdRequestCodeType                 is unsigned(3 downto 0);
   constant USB2_REQ_STD_GET_STATUS_C              : Usb2StdRequestCodeType     := x"0";
   constant USB2_REQ_STD_CLEAR_FEATURE_C           : Usb2StdRequestCodeType     := x"1";
   constant USB2_REQ_STD_SET_FEATURE_C             : Usb2StdRequestCodeType     := x"3";
   constant USB2_REQ_STD_SET_ADDRESS_C             : Usb2StdRequestCodeType     := x"5";
   constant USB2_REQ_STD_GET_DESCRIPTOR_C          : Usb2StdRequestCodeType     := x"6";
   constant USB2_REQ_STD_SET_DESCRIPTOR_C          : Usb2StdRequestCodeType     := x"7";
   constant USB2_REQ_STD_GET_CONFIGURATION_C       : Usb2StdRequestCodeType     := x"8";
   constant USB2_REQ_STD_SET_CONFIGURATION_C       : Usb2StdRequestCodeType     := x"9";
   constant USB2_REQ_STD_GET_INTERFACE_C           : Usb2StdRequestCodeType     := x"A";
   constant USB2_REQ_STD_SET_INTERFACE_C           : Usb2StdRequestCodeType     := x"B";
   constant USB2_REQ_STD_SYNCH_FRAME_C             : Usb2StdRequestCodeType     := x"C";

   subtype  Usb2StdDescriptorTypeType              is unsigned(3 downto 0);
   constant USB2_STD_DESC_TYPE_DEVICE_C            : Usb2StdDescriptorTypeType  := x"1";
   constant USB2_STD_DESC_TYPE_CONFIGURATION_C     : Usb2StdDescriptorTypeType  := x"2";
   constant USB2_STD_DESC_TYPE_STRING_C            : Usb2StdDescriptorTypeType  := x"3";
   constant USB2_STD_DESC_TYPE_INTERFACE_C         : Usb2StdDescriptorTypeType  := x"4";
   constant USB2_STD_DESC_TYPE_ENDPOINT_C          : Usb2StdDescriptorTypeType  := x"5";
   constant USB2_STD_DESC_TYPE_DEVICE_QUALIFIER_C  : Usb2StdDescriptorTypeType  := x"6";
   constant USB2_STD_DESC_TYPE_OTHER_SPEED_CONF_C  : Usb2StdDescriptorTypeType  := x"7";
   constant USB2_STD_DESC_TYPE_INTERFACE_POWER_C   : Usb2StdDescriptorTypeType  := x"8";
    
   subtype  Usb2StdFeatureType                     is unsigned(1 downto 0);
   constant USB2_STD_FEAT_ENDPOINT_HALT            : Usb2StdFeatureType         := "00";
   constant USB2_STD_FEAT_DEVICE_REMOTE_WAKEUP_C   : Usb2StdFeatureType         := "01";
   constant USB2_STD_FEAT_DEVICE_TEST_MODE_C       : Usb2StdFeatureType         := "10";

   type     Usb2CtlReqParamType is record
      dev2Host  : boolean;
      reqType   : std_logic_vector( 1 downto 0);
      recipient : std_logic_vector( 1 downto 0);
      -- hold all bits to support non-std requests
      request   : unsigned        ( 7 downto 0);   
      value     : std_logic_vector(15 downto 0);
      index     : std_logic_vector(15 downto 0);
      length    : unsigned        (15 downto 0);
      vld       : std_logic;
   end record Usb2CtlReqParamType;

   constant USB2_CTL_REQ_PARAM_INIT_C : Usb2CtlReqParamType := (
      dev2Host  => false,
      reqType   => ( others => '0' ),
      recipient => ( others => '0' ),
      request   => ( others => '0' ),
      value     => ( others => '0' ),
      index     => ( others => '0' ),
      length    => ( others => '0' ),
      vld       => '0'
    );

   type Usb2CtlExtType is record
      -- 'ack' the param's 'vld' flag
      ack       : std_logic;
      -- if set during the 'ack' phase
      -- then the external agent is OK
      -- to take over the data phase of
      -- the request; otherwise (err=1)
      -- a STALL will be emitted by the
      -- default controller.
      err       : std_logic;
      -- once the external agent is
      -- finished processing it asserts
      -- 'don' for 1 cycle and conveys
      -- status:
      --    don  ack  err
      --     1    0    0    -> NAK
      --     1    1    0    -> ACK
      --     1    0    1    -> STALL
      --     1    1    1    -> STALL
      don       : std_logic;
   end record Usb2CtlExtType;

   constant USB2_CTL_EXT_INIT_C : Usb2CtlExtType := (
      ack       => '1',
      err       => '1',
      don       => '0'
   );

end package Usb2Pkg;

package body Usb2Pkg is

   function usb2TokenPktAddr(constant x : in Usb2PktHdrType)
      return Usb2DevAddrType is
   begin
      return x.tokDat(6 downto 0);
   end function usb2TokenPktAddr;

   function usb2TokenPktEndp(constant x : in Usb2PktHdrType)
      return Usb2EndpIdxType is
   begin
      return unsigned( x.tokDat(10 downto 7) );
   end function usb2TokenPktEndp;

   function usb2PidIsTok(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "01";
   end function usb2PidIsTok;

   function usb2PidIsDat(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "11";
   end function usb2PidIsDat;

   function usb2PidIsHsk(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "10";
   end function usb2PidIsHsk;

   function usb2PidIsSpc(constant x : in Usb2PidType) return boolean is
   begin
      return x(1 downto 0) = "00";
   end function usb2PidIsSpc;

   function usb2PidGroup(constant x : in Usb2PidType) return Usb2PidGroupType is
   begin
      return x(1 downto 0);
   end function usb2PidGroup;

   function USB2_REQ_TYP_DEV2HOST_F (constant reqTyp : in Usb2ByteType)
   return boolean is begin
      return reqTyp(7) = '1';
   end function USB2_REQ_TYP_DEV2HOST_F;

   function USB2_REQ_TYP_TYPE_F     (constant reqTyp : in Usb2ByteType)
   return std_logic_vector is begin
      return reqTyp(6 downto 5);
   end function USB2_REQ_TYP_TYPE_F;

   function USB2_REQ_TYP_RECIPIENT_F(constant reqTyp : in Usb2ByteType)
   return std_logic_vector is begin
      return reqTyp(1 downto 0);
   end function USB2_REQ_TYP_RECIPIENT_F;

end package body Usb2Pkg;
