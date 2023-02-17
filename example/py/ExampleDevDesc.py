# Module to create USB descriptors

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

import Usb2Desc

def mkExampleDevDescriptors(ifcNumber=0, epAddr=1, iMACAddr = None, epPktSize=None, iProduct=None, doWrap=True, hiSpeed=True, dualSpeed=False):
  remWake = True
  c  = Usb2Desc.Usb2DescContext()
  d  = c.Usb2DeviceDesc()
  d.bMaxPacketSize0( 64 )
  d.idVendor( 0x0123 )
  d.idProduct( 0xabcd )
  d.bcdDevice( 0x0100 )
  if not iProduct is None:
    d.iProduct( iProduct )
  d.setIADMultiFunction()
  devd = d
  
  d = c.Usb2ConfigurationDesc()
  d.bMaxPower(0x32)
  if ( remWake ):
    d.bmAttributes( d.CONF_ATT_REMOTE_WAKEUP )
  cnfd = d

  if ( dualSpeed ):
    speeds = [ False, True ]
  elif ( hiSpeed ):
    speeds = [ True ]
  else:
    speeds = [ False ]

  for i in range(len(speeds)):
    speed = speeds[i]

    ifcNumber_ = ifcNumber
    epAddr_    = epAddr

    ifs, eps = Usb2Desc.addBasicACM(c, ifcNumber_, epAddr_, epPktSize, sendBreak=True, lineState=True, hiSpeed = speed)
    ifcNumber_ += ifs
    epAddr_    += eps

    ifs, eps = Usb2Desc.addBADDSpeaker( c, ifcNumber_, epAddr_, hiSpeed = speed, has24Bits = False, isAsync = True  )
    ifcNumber_ += ifs
    epAddr_    += eps

    if not iMACAddr is None:
      print(iMACAddr)
      ifs, eps = Usb2Desc.addBasicECM( c, ifcNumber_, epAddr_, iMACAddr = iMACAddr, hiSpeed = speed)
      ifcNumber_ += ifs
      epAddr_    += eps

    if i < len(speeds) - 1:
      # separate multiple (speed) device descriptors by a sentinel
      c.Usb2SentinelDesc()
      devd.clone()
      cnfd.clone()

  if ( doWrap ):
    c.wrapup()
  return c
