#!/usr/bin/env python3

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# script to generate the body of the AppCfgPkg package which defines
# the USB descriptors

import sys
import os
import io

here=os.path.abspath(os.path.dirname(__file__))

sys.path.append( here + '/../../scripts' )

import Usb2Desc

# Hi-speed bulk endpoint supports pktSize=512
iProduct="Till's Zynq ULPI Test Board"
ctxt = Usb2Desc.basicACM(epAddr=1, hiSpeed=True, sendBreak=True, iProduct=iProduct)

with io.open( here + '/../hdl/AppCfgPkgBody.vhd', 'x' ) as f:
  print("-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.", file=f)
  print("-- You may obtain a copy of the license at", file=f)
  print("--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12", file=f)
  print("-- This notice must not be removed.\n", file=f)
  print("-- THIS FILE WAS AUTOMATICALLY GENERATED ({}); DO NOT EDIT!\n".format( os.path.basename(__file__) ), file=f)
  print("library ieee;", file=f)
  print("use     ieee.std_logic_1164.all;", file=f)
  print("use     ieee.numeric_std.all;", file=f)
  print("use     ieee.math_real.all;", file=f)
  print("", file=f)
  print("use     work.Usb2Pkg.all;", file=f)
  print("use     work.UlpiPkg.all;", file=f)
  print("use     work.Usb2UtilPkg.all;", file=f)
  print("use     work.Usb2DescPkg.all;", file=f)
  print("", file=f)
  print("package body Usb2AppCfgPkg is", file=f)
  print("   function USB2_APP_DESCRIPTORS_F return Usb2ByteArray is", file=f)
  print("      constant c : Usb2ByteArray := (", file=f)
  ctxt.vhdl( f )
  print("      );", file=f)
  print("   begin", file=f)
  print("      return c;", file=f)
  print("   end function USB2_APP_DESCRIPTORS_F;", file=f)
  print("end package body Usb2AppCfgPkg;", file=f)
