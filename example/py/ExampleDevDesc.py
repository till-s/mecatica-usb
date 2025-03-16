# Module to create USB descriptors

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

import Usb2Desc

def mkExampleDevDescriptors(
  # Configuation YAML
  yml,
  # Interface and Endpoint Details
  ifcNumber           = 0,
  epAddr              = 1,
  # Wrap up the descriptors
  doWrap              = True
  ):
  ymlDev = yml['deviceDesc']
  remWake = True
  c  = Usb2Desc.Usb2DescContext()
  d  = c.Usb2DeviceDesc()
  d.bMaxPacketSize0( 64 )
  d.idVendor( ymlDev.get('idVendor', 0x1209) )
  d.idProduct( ymlDev['idProduct'] )
  d.bcdDevice( 0x0100 )
  d.iProduct( ymlDev.get("iProduct") )
  d.iSerialNumber( ymlDev.get("iSerialNumber") )
  d.iManufacturer( ymlDev.get("iManufacturer") )
  d.setIADMultiFunction()
  devd = d

  speedStr = ymlDev.get("speeds", "dual")

  if ( speedStr == "dual" ):
    speeds = [ False, True ]
  elif ( speedStr == "high" ):
    speeds = [ True ]
  else:
    speeds = [ False ]

  ymlCfg = ymlDev['configurationDesc']

  d = c.Usb2ConfigurationDesc()
  d.bMaxPower(0x32)
  if ( ymlCfg.get('remoteWakeup', True) ):
    d.bmAttributes( d.CONF_ATT_REMOTE_WAKEUP )
  d.iConfiguration( ymlCfg.get("iConfiguration") )
  cnfd = d

  for i in range(len(speeds)):
    speed = speeds[i]

    ifcNumber_ = ifcNumber
    epAddr_    = epAddr

    ymlFun     = ymlCfg.get("functionACM")
    # function is enabled by default; using default settings
    if ( ymlFun is None ):
      ymlFun = dict()
      ymlFun['enabled'] = True
    try:
      ymlFun['iFunction']
    except KeyError:
      ymlFun['iFunction'] = 'Mecatica ACM'
    if ( ymlFun.get("enabled", True) ):
      ifs, eps = Usb2Desc.addBasicACM(c, ymlFun, ifcNumber_, epAddr_, hiSpeed = speed)
      ifcNumber_ += ifs
      epAddr_    += eps

    ymlFun     = ymlCfg.get('functionUAC2I2SOutput')
    if ( not ymlFun is None and ymlFun.get('enabled', True) ):
      try:
        ymlFun['iFunction']
      except KeyError:
        ymlFun['iFunction'] = "Mecatica UAC2 Speaker"
      ifs, eps = Usb2Desc.addUAC2Speaker( c, ymlFun, ifcNumber_, epAddr_, hiSpeed = speed, isAsync = True )
      ifcNumber_ += ifs
      epAddr_    += eps

    ymlFun     = ymlCfg.get('functionUAC2Input')
    if ( not ymlFun is None and ymlFun.get('enabled', True) ):
      try:
        ymlFun['iFunction']
      except KeyError:
        ymlFun['iFunction'] = "Mecatica UAC2 Microphone"
      ifs, eps = Usb2Desc.addUAC2Microphone( c, ymlFun, ifcNumber_, epAddr_, hiSpeed = speed, isAsync = True )
      ifcNumber_ += ifs
      epAddr_    += eps

    # BADD from yaml not supported ATM
    # ifs, eps = Usb2Desc.addBADDSpeaker( c, ifcNumber_, epAddr_, hiSpeed = speed, numBits = uacNumBits, isAsync = True, fcnTitle = "Mecatica UAC3 Speaker", numChannels = uacNumChannels, maxSmplFreq = uacMaxSmplFreq)
    # ifcNumber_ += ifs
    # epAddr_    += eps

    ymlFun     = ymlCfg.get('functionECM')
    if ( not ymlFun is None and ymlFun.get('enabled', True) ):
      try:
        ymlFun['iFunction']
      except KeyError:
        ymlFun['iFunction'] = "Mecatica ECM"
      ifs, eps = Usb2Desc.addBasicECM( c, ymlFun, ifcNumber_, epAddr_, hiSpeed = speed )
      ifcNumber_ += ifs
      epAddr_    += eps

    ymlFun     = ymlCfg.get('functionNCM')
    if ( not ymlFun is None and ymlFun.get('enabled', True) ):
      try:
        ymlFun['iFunction']
      except KeyError:
        ymlFun['iFunction'] = "Mecatica NCM"
      ifs, eps = Usb2Desc.addBasicNCM( c, ymlFun, ifcNumber_, epAddr_, hiSpeed = speed )
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
