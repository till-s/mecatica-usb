-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
-- You may obtain a copy of the license at
--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
-- This notice must not be removed.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.UlpiPkg.all;
use     work.Usb2UtilPkg.all;

-- Ulpi emulation for asynchronous FS/LS transceivers.

entity UlpiFSLSEmul is
   generic (
      -- synchronization stages for async vp/vm inputs
      SYNC_STAGES_G        : natural := 3;
      IS_FS_G              : boolean := true;
      -- input-mode:
      --   true : vp -> 'vp', vm -> 'vm'
      --   false:             vm -> 'se0'
      -- note: output mode is always vp/vm
      INPUT_MODE_VPVM_G    : boolean := true
   );
   port (
      -- 4 * clock rate, 48MHz for FS, 6MHz for LS;
      -- phase-locked to ulpiClk!
      smplClk              : in  std_logic;
      smplRst              : in  std_logic;

      -- transceiver interface
      fslsIb               : in  FsLsIbType;
      fslsOb               : out FsLsObType;

      ulpiClk              : in  std_logic;
      ulpiRst              : in  std_logic;

      ulpiRx               : out UlpiRxType;
      ulpiTxReq            : in  UlpiTxReqType := ULPI_TX_REQ_INIT_C;
      ulpiTxRep            : out UlpiTxRepType;

      -- USB device state interface
      usb2RemWake          : in  std_logic := '0';
      usb2Rst              : out std_logic;
      usb2Suspend          : out std_logic
   );
end entity UlpiFSLSEmul;

architecture rtl of UlpiFSLSEmul is
   constant CLK_FREQ_C       : real := ite( IS_FS_G, 48.0E6, 6.0E6 );

   type StateType            is ( RX, TX );

   type RegType is record
      state                  : StateType;
      vldLst                 : std_logic;
      dirLst                 : std_logic;
      txDon                  : std_logic;
   end record RegType;

   constant REG_INIT_C       : RegType := (
      state                  => RX,
      vldLst                 => '0',
      dirLst                 => '0',
      txDon                  => '0'
   );

   signal   r                : RegType := REG_INIT_C;
   signal   rin              : RegType;

   signal   rxJ              : std_logic;
   signal   rxSE0            : std_logic;
   signal   rxInpLoc         : std_logic;
   signal   vpInpLoc         : std_logic;
   signal   vmInpLoc         : std_logic;
   signal   rxInpSyn         : std_logic;
   signal   vpInpSyn         : std_logic;
   signal   vmInpSyn         : std_logic;
   signal   vpOutLoc         : std_logic;
   signal   vmOutLoc         : std_logic;
   signal   txActive         : std_logic;
   signal   txData           : std_logic_vector(7 downto 0);
   signal   txNxt            : std_logic;
   signal   txStp            : std_logic := '0';
   signal   rxActive         : std_logic;
   signal   rxValid          : std_logic;
   signal   txOE             : std_logic;
   signal   rxData           : std_logic_vector(7 downto 0);
   signal   rxCmdValid       : std_logic;
   signal   sendK            : std_logic;
   signal   ulpiDir          : std_logic;
   signal   ulpiRxLoc        : UlpiRxType;
begin

   G_FS_MAP : if ( IS_FS_G ) generate
      vpInpLoc   <= fslsIb.vp;
      vmInpLoc   <= fslsIb.vm;
      rxInpLoc   <= fslsIb.rcv;
      fslsOb.vp  <= vpOutLoc;
      fslsOb.vm  <= vmOutLoc;
   end generate G_FS_MAP;

   G_LS_MAP : if ( not IS_FS_G ) generate

      rxInpLoc   <= not fslsIb.rcv;

      G_LS_VPVM : if ( INPUT_MODE_VPVM_G ) generate
         vpInpLoc <= fslsIb.vm;
         vmInpLoc <= fslsIb.vp;
      end generate G_LS_VPVM;

      G_LS_SE0J : if ( not INPUT_MODE_VPVM_G ) generate
         vpInpLoc <= fslsIb.vp;
         vmInpLoc <= fslsIb.vm;
      end generate G_LS_SE0J;

      fslsOb.vp   <= vmOutLoc;
      fslsOb.vm   <= vpOutLoc;
   end generate G_LS_MAP;

   fslsOb.oe <= txOE;

   G_SE0_COMB : if ( INPUT_MODE_VPVM_G ) generate
      rxSE0    <= vpInpSyn nor vmInpSyn;
   end generate G_SE0_COMB;

   G_SE0      : if ( not INPUT_MODE_VPVM_G ) generate
      rxSE0    <= vmInpSyn;
   end generate G_SE0;

   G_SYNC     : if ( SYNC_STAGES_G > 0 ) generate

      U_SYNC_RX : entity work.Usb2CCSync
         generic map (
            STAGES_G          => SYNC_STAGES_G,
            INIT_G            => '1'
         )
         port map (
            clk               => smplClk,
            rst               => smplRst,
            d                 => rxInpLoc,
            q                 => rxInpSyn
         );

      U_SYNC_VP : entity work.Usb2CCSync
         generic map (
            STAGES_G          => SYNC_STAGES_G,
            INIT_G            => '1'
         )
         port map (
            clk               => smplClk,
            rst               => smplRst,
            d                 => vpInpLoc,
            q                 => vpInpSyn
         );

      U_SYNC_VM : entity work.Usb2CCSync
         generic map (
            STAGES_G          => SYNC_STAGES_G,
            INIT_G            => '0'
         )
         port map (
            clk               => smplClk,
            rst               => smplRst,
            d                 => vmInpLoc,
            q                 => vmInpSyn
         );

   end generate G_SYNC;

   G_NO_SYNC  : if ( SYNC_STAGES_G = 0 ) generate
      rxInpSyn <= rxInpLoc;
      vpInpSyn <= vpInpLoc;
      vmInpSyn <= vmInpLoc;
   end generate G_NO_SYNC;

   rxJ <= rxInpSyn;

   U_FSLS_RX : entity work.Usb2FSLSRx
      generic map (
         IS_FS_G           => IS_FS_G,
         CLK_FREQ_G        => CLK_FREQ_C
      )
      port map (
         smplClk           => smplClk,
         smplRst           => smplRst,
         j                 => rxJ,
         se0               => rxSE0,
         outClk            => ulpiClk,
         outRst            => ulpiRst,
         txActive          => txActive,
         valid             => rxValid,
         data              => rxData,
         active            => rxActive,
         rxCmdVld          => rxCmdValid,
         suspended         => usb2Suspend,
         usb2Reset         => usb2Rst,
         remWake           => usb2RemWake,
         sendK             => sendK
      );

   U_FSLS_TX : entity work.Usb2FSLSTx
      port map (
         clk               => ulpiClk,
         rst               => ulpiRst,
         data              => txData,
         stp               => txStp,
         nxt               => txNxt,
         j                 => vpOutLoc,
         se0               => open,
         vm                => vmOutLoc,
         sendK             => sendK,
         active            => txActive,
         oe                => txOE
      );

   ulpiTxRep.err    <= '0';
   ulpiTxRep.don    <= r.txDon;
   ulpiTxRep.nxt    <= txNxt;

   ulpiDir          <= rxActive or rxCmdValid;

   ulpiRxLoc.dat    <= rxData;
   ulpiRxLoc.dir    <= ulpiDir;
   ulpiRxLoc.nxt    <= rxValid;
   ulpiRxLoc.trn    <= (ulpiDir xor r.dirLst);
   ulpiRxLoc.stp    <= txStp;

   P_COMB : process (r, ulpiTxReq, txActive, ulpiDir, txStp ) is
      variable v : RegType;
   begin
      v        := r;
      txData   <= x"00";
      txStp    <= '0';
      v.dirLst := ulpiDir;

      case ( r.state ) is
         when RX =>
            if ( ( r.dirLst = '0' ) and (ulpiTxReq.dat /= x"00") ) then
               txData  <= ulpiTxReq.dat;
               v.state := TX;
            end if;
         when TX =>
            v.vldLst := ulpiTxReq.vld;
            txData   <= ulpiTxReq.dat;
            if ( (not ulpiTxReq.vld and r.vldLst) = '1' ) then
               txData <= (others => ulpiTxReq.err);
               txStp  <= '1';
            end if;
            if ( txActive = '0' ) then
               v.state := RX;
            end if;

      end case;

      -- register to avoid combinatorial loop
      v.txDon := txStp;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( ulpiClk ) is
   begin
      if ( rising_edge( ulpiClk ) ) then
         if ( ulpiRst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   ulpiRx <= ulpiRxLoc;

end architecture rtl;
