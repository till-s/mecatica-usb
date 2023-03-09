-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

-- Generic control endpoint for a small number of short requests

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Usb2UtilPkg.all;
use     work.Usb2Pkg.all;
use     work.Usb2EpGenericCtlPkg.all;

entity Usb2EpGenericCtl is

   generic (
      CTL_IFC_NUM_G     : natural;
      HANDLE_REQUESTS_G : Usb2EpGenericReqDefArray;
      MARK_DEBUG_G      : boolean := false
   );
   port (
      usb2Clk           : in  std_logic;
      usb2Rst           : in  std_logic;

      usb2CtlReqParam   : in  usb2CtlReqParamType;
      usb2CtlExt        : out Usb2CtlExtType;

      usb2EpIb          : in  Usb2EndpPairObType;
      usb2EpOb          : out Usb2EndpPairIbType;

      -- handshake. Note that ctlReqVld is *not* identical
      -- with usb2CtlReqParam.vld' the former signal communicates
      -- that this entity is ready to receive the inbound
      -- parameters or has the outbound parameters available;
      -- the bit corresponding to the associated HANDLE_REQUESTS_G
      -- alement is asserted:
      --  - for 'dev2Host' requests: when 'vld' is asserted
      --    prepare the 'paramIb' and assert 'ack' once the
      --    response is ready; 'err' concurrently with 'ack
      --    signals that the control endpoint should reply
      --    with 'STALL'
      --  - for host2dev requests; when 'vld' is asserted
      --    inspect the usb2CtlReqParam and paramOb and
      --    set 'ack' and 'err' (during the same cycle).
      --    If 'err' is set then the request is STALLed.
      --    Note that 'ctlReqVld' may never been asserted
      --    (this happens if the host does not send the
      --    correct amount of data). The user must then
      --    ignore the entire request.
      ctlReqVld         : out std_logic_vector( HANDLE_REQUESTS_G'range );
      ctlReqAck         : in  std_logic;
      ctlReqErr         : in  std_logic;

      paramIb           : in  Usb2ByteArray( 0 to maxParamSize( HANDLE_REQUESTS_G ) - 1 );
      paramOb           : out Usb2ByteArray( 0 to maxParamSize( HANDLE_REQUESTS_G ) - 1 )
   );

end entity Usb2EpGenericCtl;

architecture Impl of Usb2EpGenericCtl is

   type StateType is ( IDLE, WAIT_RESP, SEND, RECV, DONE );

   subtype IndexType is natural range HANDLE_REQUESTS_G'range;

   type RegType is record
      state       : StateType;
      idx         : natural range  0 to maxParamSize( HANDLE_REQUESTS_G ) - 1;
      nBytes      : integer range -1 to maxParamSize( HANDLE_REQUESTS_G ) - 1;
      ctlExt      : Usb2CtlExtType;
      buf         : Usb2ByteArray( paramIb'range );
      reqVld      : std_logic_vector(HANDLE_REQUESTS_G'range);
      reqSel      : std_logic_vector(HANDLE_REQUESTS_G'range);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      idx         => IndexType'low,
      nBytes      => -1,
      ctlExt      => USB2_CTL_EXT_INIT_C,
      buf         => ( others => ( others => '0') ),
      reqVld      => ( others => '0' ),
      reqSel      => ( others => '0' )
   );

   signal r       : RegType := REG_INIT_C;
   signal rin     : RegType := REG_INIT_C;

begin

   P_COMB : process ( r, usb2CtlReqParam, ctlReqAck, ctlReqErr, paramIb, usb2EpIb ) is
      variable v : RegType;
   begin
      v                    := r;

      -- reset flags
      v.ctlExt.ack         := '0';
      v.ctlExt.err         := '0';
      v.ctlExt.don         := '0';

      usb2EpOb             <= USB2_ENDP_PAIR_IB_INIT_C;
      usb2EpOb.mstInp.dat  <= r.buf( r.idx );
      usb2EpOb.mstInp.err  <= '0';
      usb2EpOb.mstInp.don  <= '0';

      case ( r.state ) is
         when IDLE =>
            v.idx        := IndexType'low;
            if ( usb2CtlReqParam.vld = '1' ) then
               v.nBytes     := to_integer(usb2CtlReqParam.length) - 1;
               v.ctlExt.ack := '1';
               v.ctlExt.err := '1';
               v.ctlExt.don := '1';
               v.state      := DONE;

               if ( usb2CtlReqDstInterface( usb2CtlReqParam, CTL_IFC_NUM_G ) ) then

                  for i in HANDLE_REQUESTS_G'range loop
                     if (      HANDLE_REQUESTS_G(i).dev2Host = toSl( usb2CtlReqParam.dev2Host )
                          and  HANDLE_REQUESTS_G(i).request  = usb2CtlReqParam.request
                        ) then

                        if ( usb2CtlReqParam.dev2Host ) then
                           if ( usb2CtlReqParam.length <= HANDLE_REQUESTS_G(i).dataSize ) then
                              v.reqVld(i)  := '1';
                              v.ctlExt.ack := '0';
                              v.ctlExt.err := '0';
                              v.ctlExt.don := '0';
                              v.state      := WAIT_RESP;
                           end if;
                        else
                           if ( usb2CtlReqParam.length = HANDLE_REQUESTS_G(i).dataSize ) then
                              v.ctlExt.ack := '0';
                              v.ctlExt.err := '0';
                              v.ctlExt.don := '0';
                              if ( v.nBytes < 0 ) then
                                 v.reqVld(i)  := '1';
                                 v.state      := WAIT_RESP;
                              else
                                 v.reqSel(i)  := '1';
                                 v.ctlExt.ack := '1';
                                 v.state      := RECV;
                              end if;
                           end if;
                        end if;
                     end if;
                  end loop;
               end if;
            end if;

         when WAIT_RESP =>
            if ( ctlReqAck = '1' ) then
               v.buf        := paramIb;
               v.reqVld     := (others => '0');
               v.ctlExt.ack := '1';
               v.ctlExt.err := ctlReqErr;
               -- r.nBytes is < 0 in case of a zero-length dev2host request
               -- (can this ever happen??) or a successful host2dev request
               if ( ctlReqErr = '1' or r.nBytes < 0 ) then
                  v.ctlExt.don := '1';
                  v.state   := DONE;
               else
                  v.state   := SEND;
               end if;
            end if;

         when SEND =>
            usb2EpOb.mstInp.vld    <= '1';
            if ( r.nBytes < 0 ) then
               usb2EpOb.mstInp.vld <= '0';
               usb2EpOb.mstInp.don <= '1';
            end if;
            if ( usb2EpIb.subInp.rdy = '1' ) then
               if ( r.nBytes < 0 ) then
                  v.ctlExt.ack := '1';
                  v.ctlExt.don := '1';
                  v.state      := DONE;
               else
                  v.nBytes     := r.nBytes - 1;
                  if ( v.nBytes >= 0 ) then
                     v.idx        := r.idx    + 1;
                  end if;
               end if;
            end if;
            -- short read by host is OK
            if ( usb2CtlReqParam.vld = '0' ) then
               v.state := IDLE;
            end if;

         when RECV =>
            usb2EpOb.subOut.rdy <= '1';
            v.buf( r.idx )      := usb2EpIb.mstOut.dat;
            if ( usb2EpIb.mstOut.vld = '1' and r.nBytes >= 0 ) then
               v.nBytes := r.nBytes - 1;
               if ( v.nBytes >= 0 ) then
                  v.idx    := r.idx + 1;
               end if;
            end if;
            if ( usb2EpIb.mstOut.don = '1' ) then
               v.reqSel     := (others => '0');
               if ( r.nBytes < 0 ) then
                  v.reqVld     := r.reqSel;
                  v.state      := WAIT_RESP;
               else
                  v.ctlExt.don := '1';
                  v.ctlExt.ack := '1';
                  v.ctlExt.err := '1';
                  v.state      := DONE;
               end if;
            end if;

         when DONE =>
            if ( usb2CtlReqParam.vld = '0' ) then
               v.state := IDLE;
            end if;

      end case;

      rin        <= v;
   end process P_COMB;


   P_SEQ : process ( usb2Clk ) is
   begin
      if ( rising_edge( usb2Clk ) ) then
        if ( usb2Rst = '1' ) then
          r <= REG_INIT_C;
         else
          r <= rin;
         end if;
      end if;
   end process P_SEQ;

   ctlReqVld  <= r.reqVld;
   paramOb    <= r.buf;
   usb2CtlExt <= r.ctlExt;

end architecture Impl;
