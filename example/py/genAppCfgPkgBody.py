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
import re

here=os.path.abspath(os.path.dirname(__file__))

sys.path.append( here + '/../../scripts' )

import Usb2Desc
import ExampleDevDesc

if __name__ == "__main__":

  fnam                = here + '/../hdl/AppCfgPkgBody.vhd'

  idVendor            = 0x1209
  idProduct           = None
  iProduct            = "Till's Mecatica USB Example Device"
  iSerial             = None
  uacProto            = "UAC2Spkr"
  # one MAC address is patched by the firmware using DeviceDNA
  iECMMACAddr         = None
  iNCMMACAddr         = None
  haveNCMDynAddr      = False
  haveACM             = True
  haveACMLineBreak    = True
  haveACMLineState    = True
  dualSpeed           = True
  hiSpeed             = True
  numNCMMcFilters     = -1

  cmdline             = os.path.basename(sys.argv[0]) + ' ' + ' '.join(sys.argv[1:])

  (opt, args) = getopt.getopt(sys.argv[1:], "hv:p:f:d:s:FSN:E:AL:am:")
  for o in opt:
    if o[0] in ("-h"):
       print("usage: {} [-h] [-v <vendor_id>] [-f <output_file>] -p <product_id>".format(sys.argv[0]))
       print("          -h               : this message")
       print("          -v vendor_id     : vendor_id (hex), defaults to 0x{:04x}".format(idVendor))
       print("          -p product_id    : product_id (use 0x0001 for private testing *only*)")
       print("          -f file_name     : output file name, defaults to '{}'".format(fnam))
       print("          -s serial_number : (string) goes into the device descriptor")
       print("          -d description   : product description (iProduct string); goes into the device descriptor")
       print("          -F               : Full-speed only")
       print("          -S               : Disable sound function")
       print("          -E macAddr       : Enable ECM ethernet function; mac-addr in hex, e.g., 02deadbeef33")
       print("          -N macAddr       : Enable NCM ethernet function; mac-addr in hex, e.g., 02deadbeef33")
       print("          -a               : Enable support for SET_NET_ADDRESS (NCM only)")
       print("          -m numMcFilters  : Set wNumberMCFilters (NCM only, bit 15 indicates that filtering is imperfect\n")
       print("                             -m 0x8000 disables support for setting MC filters\n")
       print("          -A               : Disable ACM function")
       print("          -L break         : Disable ACM line-break support")
       print("          -L state         : Disable ACM line-state support")
       sys.exit(0)
    elif o[0] in ("-v"):
       idVendor          = int(o[1], 0)
    elif o[0] in ("-p"):
       idProduct         = int(o[1], 0)
    elif o[0] in ("-f"):
       fnam              = o[1]
    elif o[0] in ("-s"):
       iSerial           = o[1]
    elif o[0] in ("-d"):
       iProduct          = o[1]
       if ( len(iProduct) == 0 ):
         iProduct = None
    elif o[0] in ("-S"):
       uacProto          = None
    elif o[0] in ("-E"):
       iECMMACAddr       = o[1]
    elif o[0] in ("-N"):
       iNCMMACAddr       = o[1]
    elif o[0] in ("-A"):
       haveACM           = False
    elif o[0] in ("-F"):
       hiSpeed           = False
       dualSpeed         = False
    elif o[0] in ("-L"):
       arg = o[1].upper()
       if   arg[0] == 'B':
         haveACMLineBreak = False
       elif arg[0] == 'S':
         haveACMLineState = False
       else:
         raise RuntimeError("invalid argument to '-L' option")
    elif o[0] in ("-a"):
       haveNCMDynAddr     = True
    elif o[0] in ("-m"):
       numNCMMcFilters = int(o[1],0)
       if ( numNCMMcFilters < 0 or numNCMMcFilters > 65535 ):
         raise RuntimeError("invalid argument to '-m' option (0 <= val <= 65535)")

  if idProduct is None:
    raise RuntimeError(
            "A hex product id *must* be specified!\n" +
            "for **private testing only** you may\n\n" +
            "use -p 0x0001\n\n" +
            "see https://pid.codes/1209/0001/")

  ctxt = ExampleDevDesc.mkExampleDevDescriptors(
              idVendor=idVendor,
              idProduct=idProduct,
              ifcNumber=0,
              epAddr=1,
              iECMMACAddr=iECMMACAddr,
              iNCMMACAddr=iNCMMACAddr,
              dualSpeed=dualSpeed,
              hiSpeed=hiSpeed,
              iProduct=iProduct,
              iSerial=iSerial,
              uacProto=uacProto,
              haveACM=haveACM,
              haveACMLineState=haveACMLineState,
              haveACMLineBreak=haveACMLineBreak,
              haveNCMDynAddr=haveNCMDynAddr,
              numNCMMcFilters=numNCMMcFilters
  )

  comment = 'Generated with: {}'.format(cmdline)
  with io.open( fnam, 'x' ) as f:
    ctxt.genAppCfgPkgBody( f, comment )
