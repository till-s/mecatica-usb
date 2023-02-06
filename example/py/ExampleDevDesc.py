# Module to create USB descriptors

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

import Usb2Desc

def mkExampleDevDescriptors(ifcNumber, epAddr, iMACAddr = None, epPktSize=None, sendBreak=False, iProduct=None, doWrap=True, hiSpeed=True):
  remWake = True
  c  = Usb2Desc.SingleCfgDevice(0x0123, 0xabcd, remWake)
  d  = c.deviceDesc
  if ( not iProduct is None ):
    d.iProduct( iProduct )
  d.setIADMultiFunction()

  ifs, eps = Usb2Desc.addBasicACM(c, ifcNumber, epAddr, epPktSize, sendBreak, hiSpeed)
  ifcNumber += ifs
  epAddr    += eps

  ifs, eps = Usb2Desc.addBADDSpeaker( c, ifcNumber, epAddr, hiSpeed = hiSpeed, has24Bits = False, isAsync = True  )
  ifcNumber += ifs
  epAddr    += eps

  if not iMACAddr is None:
    print(iMACAddr)
    ifs, eps = Usb2Desc.addBasicECM( c, ifcNumber, epAddr, iMACAddr = iMACAddr, hiSpeed = hiSpeed)
    ifcNumber += ifs
    epAddr    += eps

  if ( doWrap ):
    c.wrapup()
  return c
