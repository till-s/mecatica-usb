-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2Pkg.all;

-- Example for how to extend EP0 functionality.
-- This module implements the class-specific control endpoint requests for
-- the UAC3 BADD speaker profile.

entity BADDSpkrCtl is
   generic (
      VOL_RNG_MIN_G   : integer range -32767 to 32767 := -32767; -- -128 + 1/156 db
      VOL_RNG_MAX_G   : integer range -32767 to 32767 := +32767; -- +128 - 1/156 db
      VOL_RNG_RES_G   : integer range      1 to 32767 := 256;    --    1         db
      AC_IFC_NUM_G    : Usb2InterfaceNumType
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic := '0';
      
      usb2Ep0ReqParam : in  Usb2CtlReqParamType;
      usb2Ep0CtlExt   : out Usb2CtlExtType;
      usb2Ep0ObExt    : out Usb2EndpPairIbType;
      usb2Ep0IbExt    : in  Usb2EndpPairObType;
      volMaster       : out signed(15 downto 0);
      volLeft         : out signed(15 downto 0);
      volRight        : out signed(15 downto 0);
      muteMaster      : out std_logic;
      muteLeft        : out std_logic;
      muteRight       : out std_logic;
      powerState      : out unsigned(1 downto 0)
   );
end entity BADDSpkrCtl;

architecture Impl of BADDSpkrCtl is

   type StateType is (IDLE, SEND_DAT, GET_PARAM, DONE);

   type BufType is record
      dat             : Usb2ByteArray(15 downto 0);
      idx             : signed(4 downto 0);
   end record BufType;

   constant BUF_INIT_C : BufType := (
      dat             => (others => (others => '0')),
      idx             => (others => '1')
   );

   procedure bufStore(
      variable b : inout BufType;
      constant v : in  Usb2ByteType
   ) is
      constant i : natural := to_integer( unsigned( b.idx(b.idx'left - 1 downto 0) ) );
   begin
      b := b;
      if ( b.idx(b.idx'left) = '0' ) then
         b.dat( i ) := v;
         b.idx      := b.idx - 1;
      end if;
   end procedure bufStore;

   procedure bufFill(
      variable b : out BufType;
      constant v : in  Usb2ByteType
   ) is
   begin
      b.dat(0) := v;
      b.idx    := to_signed(0, b.idx'length);
   end procedure bufFill;

   procedure bufFill(
      variable b : out BufType;
      constant v : in  std_logic
   ) is
   begin
      b.dat(0) := ( 0 => v, others => '0');
      b.idx    := to_signed(0, b.idx'length);
   end procedure bufFill;


   function toBytes(constant x : in unsigned) return Usb2ByteArray is
      variable v : Usb2ByteArray( (x'length + 7)/8 - 1 downto 0 );
   begin
      for i in v'low to v'high loop
         v(v'high - i) := Usb2ByteType( x(8*i + 7 downto 8*i) );
      end loop;
      return v;
   end function toBytes;

   function toBytes(constant x : in signed) return Usb2ByteArray is
   begin
      return toBytes(unsigned(x));
   end function toBytes;

   procedure bufFill(
      variable b : out BufType;
      constant v : in  unsigned
   ) is
      constant e : natural := (v'length + 7)/8 - 1;
   begin
      b.idx := to_signed(e, b.idx'length);
      b.dat(e downto 0) := toBytes( v );
   end procedure bufFill;

   procedure bufFill(
      variable b : out BufType;
      constant v : in  signed
   ) is
   begin
      bufFill( b, unsigned( v ) );
   end procedure bufFill;

   procedure bufFill2(
      variable b : out BufType;
      constant l : in  signed  (15 downto 0);
      constant h : in  signed  (15 downto 0);
      constant r : in  unsigned(15 downto 0)
   ) is
   begin
      b.idx    := to_signed( 8 - 1, b.idx'length );
      b.dat(7) := x"01";
      b.dat(6) := x"00";
      b.dat(5 downto 4) := toBytes( l );
      b.dat(3 downto 2) := toBytes( h );
      b.dat(1 downto 0) := toBytes( r );
   end procedure bufFill2;

   procedure bufFill3(
      variable b : out BufType;
      constant l : in  unsigned(31 downto 0);
      constant h : in  unsigned(31 downto 0);
      constant r : in  unsigned(31 downto 0)
   ) is
   begin
      b.idx     := to_signed(14 - 1, b.idx'length );
      b.dat(13) := x"01";
      b.dat(12) := x"00";
      b.dat(11 downto 8) := toBytes( l );
      b.dat( 7 downto 4) := toBytes( h );
      b.dat( 3 downto 0) := toBytes( r );
   end procedure bufFill3;
  
   type RegType is record
      state           : stateType;
      ctlExt          : Usb2CtlExtType;
      volMaster       : signed(15 downto 0);
      volLeft         : signed(15 downto 0);
      volRight        : signed(15 downto 0);
      muteMaster      : std_logic;
      muteLeft        : std_logic;
      muteRight       : std_logic;
      powerState      : unsigned(1 downto 0);
      buf             : bufType;
   end record RegType;


   constant REG_INIT_C : RegType := (
      state           => IDLE,
      ctlExt          => USB2_CTL_EXT_INIT_C,
      volMaster       => (others => '0'),
      volLeft         => (others => '0'),
      volRight        => (others => '0'),
      muteMaster      => '0',
      muteLeft        => '0',
      muteRight       => '0',
      powerState      => to_unsigned(1, 2),
      buf             => BUF_INIT_C
   );

   signal r    : RegType := REG_INIT_C;
   signal rin  : RegType;

   constant REQ_AC_CUR_C      : Usb2CtlRequestCodeType := x"01";
   constant REQ_AC_RANGE_C    : Usb2CtlRequestCodeType := x"02";

   constant ID_FEATURE_UNIT_C : natural range 0 to 255 :=  2;
   constant ID_CLOCK_SOURCE_C : natural range 0 to 255 :=  9;
   constant ID_POWER_DOMAIN_C : natural range 0 to 255 := 10;

   constant FU_MUTE_CTL_C     : std_logic_vector(7 downto 0) := x"01";
   constant FU_VOLUME_CTL_C   : std_logic_vector(7 downto 0) := x"02";

   constant CS_SAM_FREQ_CTL_C : std_logic_vector(7 downto 0) := x"01";
   constant AC_PWR_DOM_CTL_C  : std_logic_vector(7 downto 0) := x"02";
   

   type AcReqType    is ( INVALID, CUR, RNG );
   type ChannelType  is ( INVALID, CH_LEFT, CH_RIGHT, CH_MASTER );

   function accept(constant x: Usb2CtlReqParamType; constant acr : AcReqType; constant ch : ChannelType)
   return boolean is
   begin
      if ( x.reqType /= USB2_REQ_TYP_TYPE_CLASS_C or not usb2CtlReqDstInterface( x, AC_IFC_NUM_G ) ) then
         return false;
      end if;
      if ( acr = INVALID or (acr = RNG and not x.dev2Host) ) then
         -- range only supports GET
         return false;
      end if;
      if ( ch = INVALID ) then
         return false;
      end if;
      return true;
   end function accept;

begin

   P_COMB : process ( r, usb2Ep0ReqParam, usb2Ep0IbExt ) is
      variable v        : RegType;
      variable entityId : natural range 0 to 255;
      variable acCtlReq : AcReqType;
      variable code     : std_logic_vector(7 downto 0);
      variable channel  : ChannelType;
      variable boolVal  : std_logic;
      variable s16Val   : signed(15 downto 0);
   begin
      v := r;

      usb2Ep0ObExt            <= USB2_ENDP_PAIR_IB_INIT_C;
      usb2Ep0ObExt.mstInp.dat <= r.buf.dat( to_integer( unsigned( r.buf.idx(3 downto 0) ) ) );

      entityId     := to_integer( unsigned( usb2Ep0ReqParam.index(15 downto 8) ) );
      case ( Usb2CtlRequestCodeType( usb2Ep0ReqParam.request ) ) is
         when REQ_AC_CUR_C   => acCtlReq := CUR;
         when REQ_AC_RANGE_C => acCtlReq := RNG;
         when others         => acCtlReq := INVALID;
      end case;
      if ( usb2Ep0ReqParam.value(7 downto 2) /= "000000" ) then
         channel := INVALID;
      else
         case ( usb2Ep0ReqParam.value(1 downto 0) ) is
            when "00"   => channel := CH_MASTER;
            when "01"   => channel := CH_LEFT;
            when "10"   => channel := CH_RIGHT;
            when others => channel := INVALID;
         end case;
      end if;
      code         := usb2Ep0ReqParam.value(15 downto 8);
      boolVal      := '0';

      -- reset flags
      v.ctlExt.ack := '0';
      v.ctlExt.err := '0';
      v.ctlExt.don := '0';

      case ( r.state ) is
         when IDLE =>
            if ( usb2Ep0ReqParam.vld = '1' ) then
               v.ctlExt.ack := '1';
               v.ctlExt.err := '1';
               v.ctlExt.don := '1';
               v.state      := DONE;
               if ( accept(usb2Ep0ReqParam, acCtlReq, channel) ) then
                  case ( entityId ) is
                     when ID_FEATURE_UNIT_C =>
                        v.ctlExt.err := '0';
                        v.ctlExt.don := '0';
                        if ( usb2Ep0ReqParam.dev2Host ) then
                           v.state := SEND_DAT;
                           if ( acCtlReq = CUR ) then
                              if    ( code = FU_MUTE_CTL_C ) then
                                 if    ( channel = CH_RIGHT ) then
                                    boolVal := r.muteRight;
                                 elsif ( channel = CH_LEFT ) then
                                    boolVal := r.muteLeft;
                                 else
                                    boolVal := r.muteMaster;
                                 end if;
                                 bufFill( v.buf, boolVal );
                              elsif ( code = FU_VOLUME_CTL_C ) then
                                 if    ( channel = CH_RIGHT ) then
                                    s16Val  := r.volRight;
                                 elsif ( channel = CH_LEFT ) then
                                    s16Val  := r.volLeft;
                                 else
                                    s16Val  := r.volMaster;
                                 end if;
                                 bufFill( v.buf, s16Val );
                              else
                                 v.ctlExt.err := '1';
                                 v.state      := DONE;
                              end if;
                           elsif ( acCtlReq = RNG and code = FU_VOLUME_CTL_C ) then
                              bufFill2(
                                 v.buf,
                                 to_signed( VOL_RNG_MIN_G, 16 ),
                                 to_signed( VOL_RNG_MAX_G, 16 ),
                                 to_unsigned( VOL_RNG_RES_G, 16 )
                              );
                           else
                              v.ctlExt.err := '1';
                              v.ctlExt.don := '1';
                              v.state      := DONE;
                           end if;
                        else
                           v.state     := GET_PARAM;
                           -- must be 'set CUR'
                           if    ( code = FU_MUTE_CTL_C ) then
                              v.buf.idx := to_signed(0, v.buf.idx'length);
                           elsif ( code = FU_VOLUME_CTL_C ) then
                              v.buf.idx := to_signed(1, v.buf.idx'length);
                           else
                              v.ctlExt.err := '1';
                              v.ctlExt.don := '1';
                              v.state      := DONE;
                           end if;
                        end if;
                                 
                     when ID_CLOCK_SOURCE_C =>
                        -- only 'GET' supported
                        if ( usb2Ep0ReqParam.dev2Host and channel = CH_MASTER and code = CS_SAM_FREQ_CTL_C and acCtlReq /= INVALID ) then

                           v.ctlExt.err := '0';
                           v.ctlExt.don := '0';
                           v.state      := SEND_DAT;
                           if    ( acCtlReq = CUR ) then
                              bufFill( v.buf, to_unsigned( 48000, 32 ) );
                           else
                              -- must be RNG
                              bufFill3(
                                 v.buf,
                                 to_unsigned( 48000, 32 ),
                                 to_unsigned( 48000, 32 ),
                                 to_unsigned(     0, 32 )
                              );
                           end if;
                        end if;
                     when ID_POWER_DOMAIN_C =>
                        if ( acCtlReq = CUR and channel = CH_MASTER and code = AC_PWR_DOM_CTL_C ) then
                           v.ctlExt.err := '0';
                           v.ctlExt.don := '0';
                           if ( usb2Ep0ReqParam.dev2Host ) then
                              bufFill( v.buf, resize( r.powerState, 8 ) );
                              v.state     := SEND_DAT;
                           else
                              v.buf.idx   := to_signed( 0, v.buf.idx'length );
                              v.state     := GET_PARAM;
                           end if;
                        end if;
                     when others            =>
                  end case;
               end if;
            end if;

         when GET_PARAM =>
            usb2Ep0ObExt.subOut.rdy <= '1';
            if ( usb2Ep0IbExt.mstOut.vld = '1' ) then
               if ( r.buf.idx(r.buf.idx'left) = '0' ) then
                  bufStore( v.buf, usb2Ep0IbExt.mstOut.dat );
               end if;
            end if;
            if ( usb2Ep0IbExt.mstOut.don = '1' ) then
               v.ctlExt.ack := '1';
               v.ctlExt.don := '1';
               v.state      := DONE;
               if ( entityId = ID_FEATURE_UNIT_C ) then
                  if ( code = FU_MUTE_CTL_C ) then
                     if    ( channel = CH_RIGHT ) then
                        v.muteRight  := r.buf.dat(0)(0);
                     elsif ( channel = CH_LEFT  ) then
                        v.muteLeft   := r.buf.dat(0)(0);
                     else
                        v.muteMaster := r.buf.dat(0)(0);
                     end if;
                  else
                     -- must be volume
                     if    ( channel = CH_RIGHT ) then
                        v.volRight   := signed( r.buf.dat(0) ) & signed( r.buf.dat(1) );
                     elsif ( channel = CH_LEFT  ) then
                        v.volLeft    := signed( r.buf.dat(0) ) & signed( r.buf.dat(1) );
                     else
                        v.volMaster  := signed( r.buf.dat(0) ) & signed( r.buf.dat(1) );
                     end if;
                  end if;
               else -- ID_POWER_DOMAIN_C
                  v.powerState := unsigned( r.buf.dat(0)(1 downto 0) );
               end if;
            end if;

         when SEND_DAT =>
            usb2Ep0ObExt.mstInp.vld <= not r.buf.idx(r.buf.idx'left);
            usb2Ep0ObExt.mstInp.don <= r.buf.idx(r.buf.idx'left);
            if ( usb2Ep0IbExt.subInp.rdy = '1' ) then
               if ( r.buf.idx(r.buf.idx'left) = '0' ) then
                  v.buf.idx := r.buf.idx - 1;
               else
                  -- done
                  v.ctlExt.ack := '1';
                  v.ctlExt.don := '1';
                  v.state      := DONE;
               end if;
            end if;

         when DONE => -- flags are asserted during this cycle
            v.state := IDLE;
      end case;

      -- host did not bother to read all the data
      if ( usb2Ep0ReqParam.vld = '0' ) then
         v.state := IDLE;
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

   usb2Ep0CtlExt <= r.ctlExt;

   volMaster     <= r.volMaster;
   volLeft       <= r.volLeft;
   volRight      <= r.volRight;
   volMaster     <= r.volMaster;
   muteLeft      <= r.muteLeft;
   muteRight     <= r.muteRight;
   muteMaster    <= r.muteMaster;
   powerState    <= r.powerState;

end architecture Impl;
