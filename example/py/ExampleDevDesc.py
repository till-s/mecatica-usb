# Module to create USB descriptors

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

import Usb2Desc

def mkExampleDevDescriptors(
  # Vendor and Product Info
  idVendor, idProduct,
  iProduct            = None,
  iSerial             = None,
  # Speed Options
  hiSpeed             = True,
  dualSpeed           = False,
  # Interface and Endpoint Details
  ifcNumber           = 0,
  epAddr              = 1,
  epPktSize           = None,
  ## Features/Functions
  # ACM Function
  haveACM             = True,
  haveACMLineState    = True,
  haveACMLineBreak    = True,
  # ECM Function
  iECMMACAddr         = None,
  # NCM Function
  iNCMMACAddr         = None,
  haveNCMDynAddr      = False,
  numNCMMcFilters     = -1,
  # Sound Function
  uacProto            = "UAC2Spkr",
  uacNumBits          = 24,
  uacNumChannels      = 2,
    # max. sampling freq. defines maxPktSize of endpoint
  uacMaxSmplFreq      = 48000,
  # Wrap up the descriptors
  doWrap              = True
  ):
  remWake = True
  c  = Usb2Desc.Usb2DescContext()
  d  = c.Usb2DeviceDesc()
  d.bMaxPacketSize0( 64 )
  d.idVendor( idVendor )
  d.idProduct( idProduct )
  d.bcdDevice( 0x0100 )
  if not iProduct is None:
    d.iProduct( iProduct )
  if not iSerial  is None:
    d.iSerialNumber( iSerial )
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

    if ( haveACM ):
      ifs, eps = Usb2Desc.addBasicACM(c, ifcNumber_, epAddr_, epPktSize, sendBreak=haveACMLineBreak, lineState=haveACMLineState, hiSpeed = speed, fcnTitle = "Mecatica ACM")
      ifcNumber_ += ifs
      epAddr_    += eps

    if ( uacProto is None ):
      pass
    elif ( uacProto == "UAC2Spkr" ):
      ifs, eps = Usb2Desc.addUAC2Speaker( c, ifcNumber_, epAddr_, hiSpeed = speed, numBits = uacNumBits, isAsync = True,  fcnTitle = "Mecatica UAC2 Speaker", numChannels = uacNumChannels, maxSmplFreq = uacMaxSmplFreq)
      ifcNumber_ += ifs
      epAddr_    += eps
    elif ( uacProto == "UAC2Micr" ):
      ifs, eps = Usb2Desc.addUAC2Microphone( c, ifcNumber_, epAddr_, hiSpeed = speed, numBits = uacNumBits, isAsync = True, fcnTitle = "Mecatica UAC2 Microphone", numChannels = uacNumChannels, maxSmplFreq = uacMaxSmplFreq)
      ifcNumber_ += ifs
      epAddr_    += eps
    elif ( uacProto == "UAC3Spkr" ):
      ifs, eps = Usb2Desc.addBADDSpeaker( c, ifcNumber_, epAddr_, hiSpeed = speed, numBits = uacNumBits, isAsync = True, fcnTitle = "Mecatica UAC3 Speaker", numChannels = uacNumChannels, maxSmplFreq = uacMaxSmplFreq)
      ifcNumber_ += ifs
      epAddr_    += eps
    else:
      raise RuntimeError("Unsupported uacProto argument")

    if not iECMMACAddr is None:
      ifs, eps = Usb2Desc.addBasicECM( c, ifcNumber_, epAddr_, iMACAddr = iECMMACAddr, hiSpeed = speed, fcnTitle = "Mecatica ECM")
      ifcNumber_ += ifs
      epAddr_    += eps

    if not iNCMMACAddr is None:
      ifs, eps = Usb2Desc.addBasicNCM( c, ifcNumber_, epAddr_, iMACAddr = iNCMMACAddr, hiSpeed = speed, fcnTitle = "Mecatica NCM", dynAddr = haveNCMDynAddr, numMCFilters = numNCMMcFilters)
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
