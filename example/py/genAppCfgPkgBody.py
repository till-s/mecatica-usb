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
import getopt

here=os.path.abspath(os.path.dirname(__file__))

sys.path.append( here + '/../../scripts' )

import Usb2Desc
import ExampleDevDesc

if __name__ == "__main__":

  fnam        = here + '/../hdl/AppCfgPkgBody.vhd'

  idVendor    = 0x1209
  idProduct   = None
  iSerial     = None
  uacProto    = "UAC2"
  # one MAC address is patched by the firmware using DeviceDNA
  iECMMACAddr ="02DEADBEEF34"
  iNCMMACAddr ="02DEADBEEF31"
  haveACM     = True

  (opt, args) = getopt.getopt(sys.argv[1:], "hv:p:f:s:SNEA")
  for o in opt:
    if o[0] in ("-h"):
       print("usage: {} [-h] [-v <vendor_id>] [-f <output_file>] -p <product_id>".format(sys.argv[0]))
       print("          -h               : this message")
       print("          -v vendor_id     : vendor_id (hex), defaults to 0x{:04x}".format(idVendor))
       print("          -p product_id    : product_id (use 0x0001 for private testing *only*)")
       print("          -f file_name     : output file name, defaults to '{}'".format(fnam))
       print("          -s serial_number : (string) goes into the device descriptor")
       print("          -S               : Disable sound function")
       print("          -E               : Disable ECM ethernet function")
       print("          -N               : Disable NCM ethernet function")
       print("          -A               : Disable ACM function")
    elif o[0] in ("-v"):
       idVendor  = int(o[1], 0)
    elif o[0] in ("-p"):
       idProduct = int(o[1], 0)
    elif o[0] in ("-f"):
       fnam      = o[1]
    elif o[0] in ("-2"):
       iSerial   = o[1]
    elif o[0] in ("-S"):
       uacProto  = None
    elif o[0] in ("-S"):
       uacProto  = None
    elif o[0] in ("-E"):
       iECMMACAddr = None
    elif o[0] in ("-N"):
       iNCMMACAddr = None
    elif o[0] in ("-A"):
       haveACM   = False

  if idProduct is None:
    raise RuntimeError(
            "A hex product id *must* be specified!\n" +
            "for **private testing only** you may\n\n" +
            "use -p 0x0001\n\n" + 
            "see https://pid.codes/1209/0001/")

  iProduct="Till's Mecatica USB Example Device"
  ctxt = ExampleDevDesc.mkExampleDevDescriptors(idVendor=idVendor, idProduct=idProduct, ifcNumber=0, epAddr=1, iECMMACAddr=iECMMACAddr, iNCMMACAddr=iNCMMACAddr, dualSpeed=True, iProduct=iProduct, iSerial=iSerial, uacProto=uacProto, haveACM=haveACM)
 
  with io.open( fnam, 'x' ) as f:
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
    print("   function usb2AppGetDescriptors return Usb2ByteArray is", file=f)
    print("      constant c : Usb2ByteArray := (", file=f)
    ctxt.vhdl( f )
    print("      );", file=f)
    print("   begin", file=f)
    print("      return c;", file=f)
    print("   end function usb2AppGetDescriptors;", file=f)
    print("end package body Usb2AppCfgPkg;", file=f)
