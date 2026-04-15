# Module to create USB descriptors

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

import Usb2Desc
import sys

def mkExampleDevDescriptors():
  c  = Usb2Desc.Usb2DescContext()
  d  = c.Usb2DeviceDesc()
  # Low-speed allows just 8
  d.bMaxPacketSize0( 8 )
  d.idVendor( 0x1209 )
  d.idProduct( 0x0001 )
  d.bcdDevice( 0x0100 )
  d.iProduct( "Lo-speed Test Device" )
  d.iManufacturer( "Till" )

  d = c.Usb2ConfigurationDesc()
  d.bMaxPower( 0x32 )
  d.iConfiguration( "empty configuration" )

  # NOTE: No bulk EPs with LS
  d = c.Usb2InterfaceDesc();

  c.wrapup()
  return c


ctxt=mkExampleDevDescriptors()
#with open('AppCfgPkgBody.vhd', 'w') as f:
if (True):
  f = sys.stdout
  ctxt.genAppCfgPkgBody( f, 'automatically generated with loSpeedJustEp0.py' )
