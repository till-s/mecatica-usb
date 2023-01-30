# Module to create USB descriptors

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# Create a context
#  c = Usb2DescContext()
#
# add desriptors (they end up in the binary representation in
# in the order in which they were added to the context!)
#
#  dd = c.Usb2DeviceDesc()
#
# modify attributes
#
#  dd.idVendor(0x1234)
#  dd.iProduct("My Product String")
#
# eventually, 'wrap up' the context (it computes and fills in a few
# numbers such as the number of interfaces etc., appends string
# descriptors etc.)
#
#  c.wrapup()
#
# and eventually a VHDL representation can be emitted
#
#  with io.open("Myfile","w") as f:
#    c.vhdl( f )
#
import sys
import io
import re

# Helper class (see below)
class CvtReader(object):
  def __init__(self, o):
    super().__init__()
    self._obj = o
  @property
  def obj(self):
    return self._obj
  @obj.setter
  def obj(self,new):
    self._obj = new

# accessor for an attribute; the attribute
# maps to a sequence of 'sz' bytes at offset 'off'
# in the binary representation of the descriptor
#
# The actual class method is just a converter to/from
# binary representation (in most cases the identity
# transformation just returning the argument).
#
# The converter must operate in both directions
#  - read (convert binary representation in descriptor
#    to user-readable value
#  - write (convert user-value into binary representation)
#
# For the converter to distinguish between read vs write
# access w/o the need of extra arguments (and more typing
# when defining attributes) the argument in 'read' direction
# is wrapped into a (dummy) CvtRead class object and in 'write'
# direction it is not.
#
# See the 'cvtString' method for an example.
#  - when writing it finds or adds a string to the string table and
#    returns its index for entry into the binary descriptor
#  - when reading it converts the index into the corresponding string
def acc(off,sz=1):
    def deco(func):
      fqn = func.__qualname__
      def setter(self, v = None):
         if ( v is None ):
            v = 0
            for i in range(sz):
               v |= (self.cont[off+i] << (8*i))
            # cheap hack so that the 'func' can distinguish
            # between read (isinstance(CvtReader)) and write access
            return func(self, CvtReader(v)).obj
         v = func(self, v)
         for i in range(sz):
            self.cont[off + i] = (v & 0xff)
            v >>= 8
         return self
      setattr(setter, "origName", func.__name__)
      return setter
    return deco

class Usb2DescContext(list):

  def __init__(self):
    super().__init__()
    self.strtbl_  = []
    # language IDs
    self.wrapped_ = False

  # get nth descriptor of type 'typ'. Count is zero-based, i.e.,
  # to find the first descriptor pass '0'
  def getNthDescOfType( self, typ, n = 0 ):
    inst = 0
    for d in self:
      if ( d.bDescriptorType() == typ ):
         if ( inst == n ):
            return d
         else:
            inst += 1
    raise KeyError("Requested Descriptor not found")

  @property
  def wrapped(self):
    return self.wrapped_

  def nStrings(self):
    return len(self.strtbl_)

  def addString(self, s):
    if ( self.wrapped ):
      raise RuntimeError("Nothing can be added to the context once it is wrapped")
    try:
      return self.strtbl_.index(s) + 1
    except ValueError:
      self.strtbl_.append(s)
      return len(self.strtbl_)

  def getString(self, i):
    if i < 1:
      return None
    return self.strtbl_[i-1]

  # compute and insert the following data
  #  - interface number (added to interface descriptor and interface association descriptor's
  #    'bFirstInterface')
  #  - number of endpoints for each interface (added to interface descriptor)
  #  - number of interfaces (added to configuration descriptor)
  #  - total config. descriptor length (added to configuration descriptor)
  #  - create and add string descriptor (for all accumulated strings)
  #  - create and add sentinel descriptor (non-spec conforming but used by FW)
  def wrapup(self):
    if ( self.wrapped ):
       raise RuntimeError("Context is already wrapped")
    cnf  = None
    totl = 0
    nume = 0
    intf = None
    ns   = self.Usb2Desc.clazz
    ifn  = -1
    for d in self:
      if ( d.bDescriptorType() == ns.DSC_TYPE_CONFIGURATION ):
        if ( not cnf is None ):
          raise RuntimeError("Multiple Configurations Not Supported (shouldn't be hard to add)")
        cnf  = d
        totl = 0
        ifn  = -1
      if   ( d.bDescriptorType() == ns.DSC_TYPE_INTERFACE_ASSOCIATION ):
        # must keep track when adding them because other descriptors
        # also hold references to interface numbers
        # intf.bInterfaceNumber( ifn )
        # d.bFirstInterface( ifn + 1 )
        pass
      elif ( d.bDescriptorType() == ns.DSC_TYPE_INTERFACE ):
        if (not intf is None):
           intf.bNumEndpoints(nume)
        nume = 0
        intf = d
        if ( intf.bAlternateSetting() == 0 ):
           ifn += 1
        # must keep track when adding them because other descriptors
        # also hold references to interface numbers
        # intf.bInterfaceNumber( ifn )
      elif ( d.bDescriptorType() == ns.DSC_TYPE_ENDPOINT ):
        nume += 1
      totl += d.bLength()
    if ( not intf is None ):
       intf.bNumEndpoints(nume)
    cnf.wTotalLength(totl)
    cnf.bNumInterfaces(ifn + 1)
    print("Configuration total length {:d}, num interfaces {:d}".format(totl, ifn + 1))
    # append string descriptors
    if ( len( self.strtbl_ ) > 0 ):
      # lang-id at string index 0
      self.Usb2Desc(4, ns.DSC_TYPE_STRING).cont[2:4] = [0x09, 0x04]
      for s in self.strtbl_:
         self.Usb2StringDesc( s )
    # append TAIL
    self.Usb2Desc(2, ns.DSC_TYPE_SENTINEL)
    self.wrapped_ = True

  def vhdl(self, f = sys.stdout):
    if ( not self.wrapped ):
      RuntimeError("Must wrapup context before VHDL can be emitted")
    if isinstance(f, str):
      with io.open(f, "w") as f:
         self.vhdl(f)
    else:
      i   = 0
      eol = ""
      for x in self:
        print('{}      -- {}'.format(eol, x.className()), file = f)
        eol = ""
        for b in x.cont:
           print('{}      {:3d} => x"{:02x}"'.format(eol, i, b), end = "", file = f)
           i += 1
           eol = ",\n"
      print(file = f)


  # the 'factory' decorator converts local classes
  # to factory methods of the context class. Subclasses
  # of the local classes use the 'clazz' attribute from
  # the decorated members (which have been converted
  # from class constructors to context members)
  def factory(clazz):
    def instantiate(ctxt, *args, **kwargs):
      if ( ctxt.wrapped ):
        raise RuntimeError("Nothing can be added to the context once it is wrapped")
      i = clazz(*args, **kwargs)
      i.setContext(ctxt)
      ctxt.append(i)
      return i
    setattr(instantiate, "clazz", clazz)
    return instantiate

  @factory
  class Usb2Desc(object):

    DSC_TYPE_RESERVED                  = 0x00
    DSC_TYPE_DEVICE                    = 0x01
    DSC_TYPE_CONFIGURATION             = 0x02
    DSC_TYPE_STRING                    = 0x03
    DSC_TYPE_INTERFACE                 = 0x04
    DSC_TYPE_ENDPOINT                  = 0x05
    DSC_TYPE_DEVICE_QUALIFIER          = 0x06
    DSC_TYPE_OTHER_SPEED_CONFIGURATION = 0x07
    DSC_TYPE_INTERFACE_POWER           = 0x08
    DSC_TYPE_INTERFACE_ASSOCIATION     = 0x0B
    # special value we use to terminate the descriptor table
    DSC_TYPE_SENTINEL                  = 0xFF

    DSC_DEV_CLASS_NONE                 = 0x00
    DSC_DEV_SUBCLASS_NONE              = 0x00
    DSC_DEV_PROTOCOL_NONE              = 0x00
    DSC_DEV_CLASS_CDC                  = 0x02
    DSC_DEV_CLASS_MISC                 = 0xEF

    DSC_IFC_CLASS_AUDIO                = 0x01

    DSC_FCN_SUBCLASS_AUDIO_SPEAKER     = 0x22
    DSC_IFC_SUBCLASS_AUDIO_CONTROL     = 0x01
    DSC_IFC_SUBCLASS_AUDIO_STREAMING   = 0x02

    DSC_IFC_CLASS_CDC                  = 0x02

    DSC_CDC_SUBCLASS_ACM               = 0x02
    DSC_CDC_SUBCLASS_ECM               = 0x06

    DSC_CDC_PROTOCOL_NONE              = 0x00

    DSC_IFC_CLASS_DAT                  = 0x0A
    DSC_DAT_SUBCLASS_NONE              = 0x00
    DSC_DAT_PROTOCOL_NONE              = 0x00

    def __init__(self, length, typ):
      super().__init__()
      self.cont_    = bytearray(length)
      self.bLength( length )
      self.bDescriptorType( typ )
      self.ctxt_ = None
      self.nams_ = dict()

    def setContext(self, ctxt):
      self.ctxt_ = ctxt

    @property
    def context(self):
      return self.ctxt_

    def cvtString(self, s):
      if isinstance(s,CvtReader):
        # read conversion indicated by 's' arg being a list
        s.obj = self.context.getString(s.obj)
      else:
        # write conversion
        s = self.context.addString(s)
      return s

    def len(self):
      return len(self.cont)

    def className(self):
      return self.__class__.__name__

    @property
    def cont(self):
      return self.cont_
    @acc(0)
    def bLength(self, v): return v
    @acc(1)
    def bDescriptorType(self, v): return v

  @factory
  class Usb2StringDesc(Usb2Desc.clazz):

    def __init__(self, s):
      senc = s.encode('utf-16-le')
      super().__init__(2 + len(senc), self.DSC_TYPE_STRING)
      self.cont[2:] = senc

    def __repr__(self):
      return self.cont[2:].decode('utf-16-le')

  @factory
  class Usb2DeviceDesc(Usb2Desc.clazz):

    def __init__(self):
      super().__init__(18, self.DSC_TYPE_DEVICE)
      self.bcdDevice(0x0200)

    @acc(4)
    def bDeviceClass(self, v): return v
    @acc(5)
    def bDeviceSubClass(self, v): return v
    @acc(6)
    def bDeviceProtocol(self, v): return v
    @acc(7)
    def bMaxPacketSize0(self, v): return v
    @acc(8,2)
    def idVendor(self,v): return v
    @acc(10,2)
    def idProduct(self,v): return v
    @acc(12,2)
    def bcdDevice(self,v): return v
    @acc(14)
    def iManufacturer(self, v): return self.cvtString(v)
    @acc(15)
    def iProduct(self, v): return self.cvtString(v)
    @acc(16)
    def iSerialNumber(self, v): return self.cvtString(v)
    @acc(17)
    def bNumConfigurations(self, v): return v

    def setIADMultiFunction(self):
      # this device uses IAD descriptors
      self.bDeviceClass( self.DSC_DEV_CLASS_MISC )
      self.bDeviceSubClass( 0x02 )
      self.bDeviceProtocol( 0x01 )

  @factory
  class Usb2Device_QualifierDesc(Usb2Desc.clazz):
    def __init__(self):
      super.__init__(10, self.DSC_TYPE_DEVICE_QUALIFIER)
      self.bcdUSB(0x0200)
      self.bReserved(0)

    @acc(2,2)
    def bcdUSB(self, v): return v

    @acc(4)
    def bDeviceClass(self, v): return v
    @acc(5)
    def bDeviceSubClass(self, v): return v
    @acc(6)
    def bDeviceProtocol(self, v): return v
    @acc(7)
    def bMaxPacketSize0(self, v): return v
    @acc(8)
    def bNumConfigurations(self, v): return v
    @acc(9)
    def bReserved(self, v): return v

  @factory
  class Usb2ConfigurationDesc(Usb2Desc.clazz):

    CONF_ATT_SELF_POWERED  = 0x40
    CONF_ATT_REMOTE_WAKEUP = 0x20

    def __init__(self):
      super().__init__(9, self.DSC_TYPE_CONFIGURATION)
      self.bmAttributes(0x00)
    @acc(2,2)
    def wTotalLength(self, v): return v
    @acc(4)
    def bNumInterfaces(self, v): return v
    @acc(5)
    def bConfigurationValue(self, v): return v
    @acc(6)
    def iConfiguration(self, v): return self.cvtString(v)
    @acc(7)
    def bmAttributes(self, v): return v | 0x80
    @acc(8)
    def bMaxPower(self, v): return v

  @factory
  class Usb2Other_Speed_ConfigurationDesc(Usb2ConfigurationDesc.clazz):
    def __init__(self):
      super().__init__()
      self.bDescriptorType(self.DSC_TYPE_OTHER_SPEED_CONFIGURATION)

  @factory
  class Usb2InterfaceDesc(Usb2Desc.clazz):
    def __init__(self):
      super().__init__(9, self.DSC_TYPE_INTERFACE)
    @acc(2)
    def bInterfaceNumber(self, v): return v
    @acc(3)
    def bAlternateSetting(self, v): return v
    @acc(4)
    def bNumEndpoints(self, v): return v
    @acc(5)
    def bInterfaceClass(self, v): return v
    @acc(6)
    def bInterfaceSubClass(self, v): return v
    @acc(7)
    def bInterfaceProtocol(self, v): return v
    @acc(8)
    def iInterface(self, v): return self.cvtString(v)

  @factory
  class Usb2InterfaceAssociationDesc(Usb2Desc.clazz):
    def __init__(self):
      super().__init__(8, self.DSC_TYPE_INTERFACE_ASSOCIATION)
    @acc(2)
    def bFirstInterface(self, v): return v
    @acc(3)
    def bInterfaceCount(self, v): return v
    @acc(4)
    def bFunctionClass(self, v): return v
    @acc(5)
    def bFunctionSubClass(self, v): return v
    @acc(6)
    def bFunctionProtocol(self, v): return v
    @acc(7)
    def iFunction(self, v): return self.cvtString(v)

  @factory
  class Usb2EndpointDesc(Usb2Desc.clazz):
    ENDPOINT_IN  = 0x80
    ENDPOINT_OUT = 0x00

    ENDPOINT_TT_CONTROL            = 0x00
    ENDPOINT_TT_ISOCHRONOUS        = 0x01
    ENDPOINT_TT_BULK               = 0x02
    ENDPOINT_TT_INTERRUPT          = 0x03

    ENDPOINT_SYNC_NONE             = 0x00
    ENDPOINT_SYNC_ASYNC            = 0x04
    ENDPOINT_SYNC_ADAPTIVE         = 0x08
    ENDPOINT_SYNC_SYNCHRONOUS      = 0x0c

    ENDPOINT_USAGE_DATA            = 0x00
    ENDPOINT_USAGE_FEEDBACK        = 0x10
    ENDPOINT_USAGE_IMPLICIT        = 0x20

    def __init__(self):
      super().__init__(7, self.DSC_TYPE_ENDPOINT)
    @acc(2)
    def bEndpointAddress(self, v): return v
    @acc(3)
    def bmAttributes(self, v): return v
    @acc(4,2)
    def wMaxPacketSize(self, v): return v
    @acc(6)
    def bInterval(self, v): return v

  @factory
  class Usb2CDCDesc(Usb2Desc.clazz):

    DSC_TYPE_CS_INTERFACE                                = 0x24
    DSC_TYPE_CS_ENDPOINT                                 = 0x25

    DSC_SUBTYPE_HEADER                                   = 0x00
    DSC_SUBTYPE_CALL_MANAGEMENT                          = 0x01
    DSC_SUBTYPE_UNION                                    = 0x06
    DSC_SUBTYPE_ABSTRACT_CONTROL_MANAGEMENT              = 0x02
    DSC_SUBTYPE_ETHERNET_NETWORKING                      = 0x0F

    def __init__(self, length, typ):
      super().__init__(length, typ)

    @acc(2)
    def bDescriptorSubtype(self, v): return v

  @factory
  class Usb2CDCFuncHeaderDesc(Usb2CDCDesc.clazz):
    def __init__(self):
      super().__init__(5, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_HEADER )
      self.bcdCDC(0x0120)
    @acc(3,2)
    def bcdCDC(self, v): return v

  @factory
  class Usb2CDCFuncCallManagementDesc(Usb2CDCDesc.clazz):
    DSC_CM_HANDLE_MYSELF            = 0x01
    DSC_CM_OVER_DATA                = 0x02
    def __init__(self):
      super().__init__(5, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_CALL_MANAGEMENT )
    @acc(3)
    def bmCapabilities(self, v): return v
    @acc(4)
    def bDataInterface(self, v): return v

  @factory
  class Usb2CDCFuncACMDesc(Usb2CDCDesc.clazz):
    DSC_ACM_SUP_NOTIFY_NETWORK_CONN = 0x08
    DSC_ACM_SUP_SEND_BREAK          = 0x04
    DSC_ACM_SUP_LINE_CODING         = 0x02
    DSC_ACM_SUP_COMM_FEATURE        = 0x01
    def __init__(self):
      super().__init__(4, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_ABSTRACT_CONTROL_MANAGEMENT )
    @acc(3)
    def bmCapabilities(self, v): return v

  @factory
  class Usb2CDCFuncUnionDesc(Usb2CDCDesc.clazz):
    def __init__(self, numSubordinateInterfaces):
      super().__init__(4 + numSubordinateInterfaces, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_UNION )
    @acc(3)
    def bControlInterface(self, v): return v

    def bSubordinateInterface(self, n, v = None):
      if ( n + 4 > self.bLength() ):
        raise ValueError("subordinate interface out of range")

      if ( v is None ):
        return self.cont[4 + n]
      self.cont[4+n] = v & 0xff
      return self

  @factory
  class Usb2CDCFuncEthernetDesc(Usb2CDCDesc.clazz):

    DSC_ETH_SUP_MC_PERFECT = 0x8000 # flag in wNumberMCFilters

    def __init__(self):
      super().__init__(13, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_ETHERNET_NETWORKING )
      self.bmEthernetStatistics( 0 )
      self.wMaxSegmentSize( 1514 )
      self.wNumberMCFilters( 0x8000 )
      self.bNumberPowerFilters( 0 )
    @acc(3)
    def iMACAddress(self, v): return self.cvtString(v)
    @acc(4,4)
    def bmEthernetStatistics(self, v): return v
    @acc(8,2)
    def wMaxSegmentSize(self, v): return v
    @acc(10, 2)
    def wNumberMCFilters(self, v): return v
    @acc(12)
    def bNumberPowerFilters(self, v): return v

    def checkMAC(self, v):
      if not isinstance(v,CvtReader):
        # check format
        if re.match('^[0-9a-fA-F]{3}$', v) is None:
          raise RuntimeError("Invalid MAC address - must be 12 hex chars")
      return self.cvtString(v)

class SingleCfgDevice(Usb2DescContext):
  def __init__(self, idVendor, idDevice, remWake = False, bcdDevice = 0x0100):
    super().__init__()
    # device
    d = self.Usb2DeviceDesc()
    d.bDeviceClass( d.DSC_DEV_CLASS_NONE )
    d.bDeviceSubClass( d.DSC_DEV_SUBCLASS_NONE )
    d.bDeviceProtocol( d.DSC_DEV_PROTOCOL_NONE )
    d.bMaxPacketSize0( 64 )
    d.idVendor(idVendor)
    d.idProduct(idDevice)
    d.bcdDevice(bcdDevice)
    d.bNumConfigurations(1)
    self.deviceDesc_ = d

    # configuration
    d = self.Usb2ConfigurationDesc()
    d.bConfigurationValue(1)
    d.bMaxPower(0x32)
    if ( remWake ):
      d.bmAttributes( d.CONF_ATT_REMOTE_WAKEUP )
    self.configurationDesc_ = d
    self.endpointAddr = 1

  @property
  def deviceDesc(self):
    return self.deviceDesc_

  @property
  def configurationDesc(self):
    return self.configurationDesc_

def addBasicECM(ctxt, ifcNumber, epAddr, iMACAddr, epPktSize=None, hiSpeed=True):
  if epPktSize is None:
    if ( hiSpeed ):
      epPktSize = 512
    else:
      epPktSize = 64
  d = ctxt.Usb2InterfaceAssociationDesc()
  d.bFirstInterface( ifcNumber )
  d.bInterfaceCount( 2 )
  d.bFunctionClass( d.DSC_IFC_CLASS_CDC )
  d.bFunctionSubClass( d.DSC_CDC_SUBCLASS_ECM )
  d.bFunctionProtocol( d.DSC_CDC_PROTOCOL_NONE )

  # interface 0
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_CDC )
  d.bInterfaceSubClass( d.DSC_CDC_SUBCLASS_ECM )
  d.bInterfaceProtocol( d.DSC_CDC_PROTOCOL_NONE )

  # functional descriptors; header
  d = ctxt.Usb2CDCFuncHeaderDesc()

  # functional descriptors; union
  d = ctxt.Usb2CDCFuncUnionDesc( numSubordinateInterfaces = 1 )
  d.bControlInterface( ifcNumber + 0 )
  d.bSubordinateInterface( 0, ifcNumber + 1 )

  # functional descriptors; ethernet
  d = ctxt.Usb2CDCFuncEthernetDesc()
  d.iMACAddress( iMACAddr )

  # interface 1
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + 1 )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_DAT )
  d.bInterfaceSubClass( d.DSC_DAT_SUBCLASS_NONE )
  d.bInterfaceProtocol( d.DSC_CDC_PROTOCOL_NONE )

  # endpoint 1, BULK IN
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_IN | epAddr )
  d.bmAttributes( d.ENDPOINT_TT_BULK )
  d.wMaxPacketSize(epPktSize)
  d.bInterval(0)

  # endpoint 1, BULK OUT
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_OUT | epAddr )
  d.bmAttributes( d.ENDPOINT_TT_BULK )
  d.wMaxPacketSize(epPktSize)
  d.bInterval(0)
  # return number of interfaces and endpoint pairs used
  return 2, 1

# epPktSize None selects the max. allowed for the selected speed
# ifcNum defines the index of the first of two interfaces used by
# this class
def addBasicACM(ctxt, ifcNumber, epAddr, epPktSize=None, sendBreak=False, hiSpeed=True):
  if epPktSize is None:
    if ( hiSpeed ):
      epPktSize = 512
    else:
      epPktSize = 64
  d = ctxt.Usb2InterfaceAssociationDesc()
  d.bFirstInterface( ifcNumber )
  d.bInterfaceCount( 2 )
  d.bFunctionClass( d.DSC_IFC_CLASS_CDC )
  d.bFunctionSubClass( d.DSC_CDC_SUBCLASS_ACM )
  d.bFunctionProtocol( d.DSC_CDC_PROTOCOL_NONE )

  # interface 0
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_CDC )
  d.bInterfaceSubClass( d.DSC_CDC_SUBCLASS_ACM )
  d.bInterfaceProtocol( d.DSC_CDC_PROTOCOL_NONE )

  # functional descriptors; header
  d = ctxt.Usb2CDCFuncHeaderDesc()

  # functional descriptors; call management
  d = ctxt.Usb2CDCFuncCallManagementDesc()
  d.bDataInterface(ifcNumber + 1)

  # functional descriptors; header
  d = ctxt.Usb2CDCFuncACMDesc()
  v = 0
  if ( sendBreak ):
    v |= d.DSC_ACM_SUP_SEND_BREAK
  d.bmCapabilities(v)

  # functional descriptors; union
  d = ctxt.Usb2CDCFuncUnionDesc( numSubordinateInterfaces = 1 )
  d.bControlInterface( ifcNumber + 0 )
  d.bSubordinateInterface( 0, ifcNumber + 1 )

  # Endpoint -- unused but linux cdc-acm driver refuses to bind w/o it.
  # endpoint 2, INTERRUPT IN
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_IN  | (epAddr + 1) )
  d.bmAttributes( d.ENDPOINT_TT_INTERRUPT )
  d.wMaxPacketSize(8)
  if ( hiSpeed ):
    d.bInterval(16) # (2**(interval - 1) microframes; 16 is max.
  else:
    d.bInterval(255) #ms

  # interface 1
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + 1 )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_DAT )
  d.bInterfaceSubClass( d.DSC_DAT_SUBCLASS_NONE )
  d.bInterfaceProtocol( d.DSC_CDC_PROTOCOL_NONE )

  # endpoint 1, BULK IN
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_IN | epAddr )
  d.bmAttributes( d.ENDPOINT_TT_BULK )
  d.wMaxPacketSize(epPktSize)
  d.bInterval(0)

  # endpoint 1, BULK OUT
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_OUT | epAddr )
  d.bmAttributes( d.ENDPOINT_TT_BULK )
  d.wMaxPacketSize(epPktSize)
  d.bInterval(0)
  # return number of interfaces and endpoint pairs used
  return 2, 2

def addBADDSpeaker(ctxt, ifcNumber, epAddr, hiSpeed = True, has24Bits = True, isAsync = True):
  d = ctxt.Usb2InterfaceAssociationDesc()
  d.bFirstInterface( ifcNumber )
  d.bInterfaceCount( 2 )
  d.bFunctionClass( d.DSC_IFC_CLASS_AUDIO )
  d.bFunctionSubClass( d.DSC_FCN_SUBCLASS_AUDIO_SPEAKER )
  d.bFunctionProtocol( 0x30 )

  # AC (audio-control) interface
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_CONTROL )
  d.bInterfaceProtocol( 0x30 )
  # no endpoints (optional interrupt endpoint omitted)

  # AS (audio-streaming interface)
  d = ctxt.Usb2InterfaceDesc()
  # zero-bandwidth altsetting 0
  d.bInterfaceNumber( ifcNumber + 1 )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_STREAMING )
  d.bInterfaceProtocol( 0x30 )

  # AS (audio-streaming interface)
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + 1 )
  # 1kHz altsetting 1
  d.bAlternateSetting(1)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_STREAMING )
  d.bInterfaceProtocol( 0x30 )

  # endpoint 1, ISO OUT
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_OUT | epAddr )
  atts = d.ENDPOINT_TT_ISOCHRONOUS
  if ( isAsync ):
    atts |= d.ENDPOINT_SYNC_ASYNC
  else:
    atts |= d.ENDPOINT_SYNC_SYNCHRONOUS
  d.bmAttributes( atts )
  if ( has24Bits ):
    smpSize = 3
  else:
    smpSize = 2
  # stereo, 48KHz sample size
  pktSize = 48*2*smpSize
  if ( isAsync ):
    pktSize += 2*smpSize
  d.wMaxPacketSize( pktSize )
  if ( hiSpeed ):
    d.bInterval(0x04)
  else:
    d.bInterval(0x01)
  if ( isAsync ):
    # endpoint 1, ISO INP -- feedback
    d = ctxt.Usb2EndpointDesc()
    d.bEndpointAddress( d.ENDPOINT_IN  | epAddr )
    atts =d.ENDPOINT_TT_ISOCHRONOUS | d.ENDPOINT_SYNC_NONE | d.ENDPOINT_USAGE_FEEDBACK
    d.bmAttributes( atts )
    if ( hiSpeed ):
      d.wMaxPacketSize( 4 )
      d.bInterval(0x04)
    else:
      d.wMaxPacketSize( 3 )
      d.bInterval(0x01)
  return 2, 2

def basicACM(ifcNumber, epAddr, iMACAddr = None, epPktSize=None, sendBreak=False, iProduct=None, doWrap=True, hiSpeed=True):
  remWake = True
  c  = SingleCfgDevice(0x0123, 0xabcd, remWake)
  d  = c.deviceDesc
  if ( not iProduct is None ):
    d.iProduct( iProduct )
  d.setIADMultiFunction()

  ifs, eps = addBasicACM(c, ifcNumber, epAddr, epPktSize, sendBreak, hiSpeed)
  ifcNumber += ifs
  epAddr    += eps

  ifs, eps = addBADDSpeaker( c, ifcNumber, epAddr, hiSpeed = hiSpeed, has24Bits = False, isAsync = True  )
  ifcNumber += ifs
  epAddr    += eps

  if not iMACAddr is None:
    print(iMACAddr)
    ifs, eps = addBasicECM( c, ifcNumber, epAddr, iMACAddr = iMACAddr, hiSpeed = hiSpeed)
    ifcNumber += ifs
    epAddr    += eps

  if ( doWrap ):
    c.wrapup()
  return c
