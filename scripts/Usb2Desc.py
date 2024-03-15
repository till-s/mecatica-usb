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
# and eventually a VHDL representation of a byte array (contents
# only) can be emitted:
#
#  with io.open("Myfile","w") as f:
#    c.emitVhdlByteArray( f )
#
# alternatively, a full implementation of the AppCfgPkg body can be
# generated:
#
#  with io.open("AppCfgPkgBody.vhd", "w") as f:
#    f.genAppCfgPkgBody( f )
#
# the generated file should be included with the synthesized file set.
#
import sys
import io
import re
import os

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
      setattr(setter, "offset",   off          )
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
  #  - number of endpoints for each interface (added to interface descriptor)
  #  - number of interfaces (added to configuration descriptor)
  #  - set configuration value; the firmware assumes this is 1-based and contiguous
  #  - total config. descriptor length (added to configuration descriptor)
  #  - create and add string descriptor (for all accumulated strings)
  #  - create and add sentinel descriptor (non-spec conforming but used by FW;
  #    the sentinel descriptor(s) are never sent to the host; they exist only
  #    in the firmware image to mark the end of a set of descriptors.)
  #
  def wrapup(self):
    if ( self.wrapped ):
       raise RuntimeError("Context is already wrapped")
    ns   = self.Usb2Desc.clazz
    # append sentinel
    devds = []
    devd = None
    totl = 0
    self.Usb2DeviceDesc()
    for d in self:
      if ( d.bDescriptorType() == ns.DSC_TYPE_DEVICE ):
        if ( not devd is None ):
          ifcd.bNumEndpoints(nume)
          cnfd.wTotalLength(totl)
          cnfd.bNumInterfaces(ifn + 1)
          devd.bNumConfigurations(numc)
        numc = 0
        cnfd = None
        devd = d
        devds.append(d)
      elif ( d.bDescriptorType() == ns.DSC_TYPE_CONFIGURATION ):
        if ( not cnfd is None ):
          ifcd.bNumEndpoints(nume)
          cnfd.wTotalLength(totl)
          cnfd.bNumInterfaces(ifn + 1)
          print("Configuration total length {:d}, num interfaces {:d}, num endpoints {:d}".format(totl, ifn + 1, tote))
        cnfd  = d
        ifcd  = None
        totl  = 0
        ifn   = -1
        tote  = 0
        numc += 1
        cnfd.bConfigurationValue( numc )
      elif   ( d.bDescriptorType() == ns.DSC_TYPE_INTERFACE_ASSOCIATION ):
        # must keep track when adding them because other descriptors
        # also hold references to interface numbers
        # ifcd.bInterfaceNumber( ifn )
        # d.bFirstInterface( ifn + 1 )
        pass
      elif ( d.bDescriptorType() == ns.DSC_TYPE_INTERFACE ):
        if (not ifcd is None):
           ifcd.bNumEndpoints(nume)
        nume = 0
        ifcd = d
        if ( ifcd.bAlternateSetting() == 0 ):
           ifn += 1
        # must keep track when adding them because other descriptors
        # also hold references to interface numbers
        # ifcd.bInterfaceNumber( ifn )
      elif ( d.bDescriptorType() == ns.DSC_TYPE_ENDPOINT ):
        nume += 1
        tote += 1
      # don't count a separating sentinel
      if ( d.bDescriptorType() != ns.DSC_TYPE_SENTINEL):
        totl += d.bLength()
    # remove sentinel
    self.pop()

    # If there are two device descriptors then assume they describe
    # full- and hi-speed devices, respectively. Insert and fill qualifier
    # descriptors.
    # Note that the devds list still contains the (dummy) sentinel device
    # descriptor.
    if ( len(devds) > 2 ):
       fsd = devds[0]
       hsd = devds[1]
       self.Usb2Device_QualifierDesc( fsd )
       self.Usb2Device_QualifierDesc( hsd )
       fsq = self.pop()
       hsq = self.pop()
       idx = self.index(fsd)
       self.insert( idx + 1, fsq )
       # fsd and hsd may reference the same object
       idx = self.index( hsd, idx + 2 )
       self.insert( idx + 1, hsq )

    # append string descriptors
    if ( len( self.strtbl_ ) > 0 ):
      # lang-id at string index 0
      self.Usb2StringDesc(0x0409) # US-English
      for s in self.strtbl_:
         self.Usb2StringDesc( s )
    # append TAIL
    self.Usb2SentinelDesc()
    self.wrapped_ = True

  def emitVhdlByteArray(self, f = sys.stdout):
    if ( not self.wrapped ):
      RuntimeError("Must wrapup context before VHDL can be emitted")
    if isinstance(f, str):
      with io.open(f, "w") as f:
         self.emitVhdlByteArray(f)
    else:
      i   = 0
      eol = ""
      for x in self:
        print('{}      -- {}'.format(eol, x.className()), file = f)
        eol = ""
        off = 0
        for b in x.cont:
           print('{}      {:3d} => x"{:02x}"'.format(eol, i, b), end = "", file = f)
           offNam = x.nameAt(off)
           i   += 1
           off += 1
           if not offNam is None:
             eol  = ",  -- {}\n".format( offNam )
           else:
             eol  = ",\n"
      if not offNam is None:
        print( "   -- {}".format( offNam ), file = f )
      else:
        print(file = f)

  def genAppCfgPkgBody(self, f = sys.stdout):
    print("-- Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.", file=f)
    print("-- You may obtain a copy of the license at", file=f)
    print("--   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12", file=f)
    print("-- This notice must not be removed.\n", file=f)
    print("-- THIS FILE WAS AUTOMATICALLY GENERATED ({}); DO NOT EDIT!\n".format( os.path.basename(sys.argv[0]) ), file=f)
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
    self.emitVhdlByteArray( f )
    print("      );", file=f)
    print("   begin", file=f)
    print("      return c;", file=f)
    print("   end function usb2AppGetDescriptors;", file=f)
    print("end package body Usb2AppCfgPkg;", file=f)


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

    DSC_FCN_SUBCLASS_AUDIO_UNDEFINED   = 0x00
    DSC_FCN_SUBCLASS_AUDIO_SPEAKER     = 0x22
    DSC_IFC_SUBCLASS_AUDIO_CONTROL     = 0x01
    DSC_IFC_SUBCLASS_AUDIO_STREAMING   = 0x02

    DSC_FCN_PROTOCOL_AUDIO_UAC2        = 0x20
    DSC_FCN_PROTOCOL_AUDIO_UAC3        = 0x30

    DSC_IFC_CLASS_CDC                  = 0x02

    DSC_CDC_SUBCLASS_ACM               = 0x02
    DSC_CDC_SUBCLASS_ECM               = 0x06
    DSC_CDC_SUBCLASS_NCM               = 0x0D

    DSC_CDC_PROTOCOL_NONE              = 0x00

    DSC_IFC_CLASS_DAT                  = 0x0A
    DSC_DAT_SUBCLASS_NONE              = 0x00
    DSC_DAT_PROTOCOL_NONE              = 0x00
    DSC_DAT_PROTOCOL_NCM               = 0x01

    DSC_IFC_CLASS_VENDOR               = 0xff

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

    @property
    def size(self):
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

    def clone(self):
      no = getattr(self.context, self.className())()
      for a in dir(self):
        if ( not getattr(getattr(self, a), "origName", None ) is None ):
          getattr(no, a)( getattr(self, a)() )
      return no

    def nameAt(self, off):
      for a in dir(self):
        tsto = getattr( getattr(self, a), "offset", -1 )
        if tsto == off:
          return getattr( getattr(self, a), "origName" )
      return None

  @factory
  class Usb2SentinelDesc(Usb2Desc.clazz):
    def __init__(self):
      super().__init__(2, self.DSC_TYPE_SENTINEL)

  @factory
  class Usb2StringDesc(Usb2Desc.clazz):

    def __init__(self, s):
      self.isLangId = False
      if isinstance(s, str):
        senc = s.encode('utf-16-le')
        super().__init__(2 + len(senc), self.DSC_TYPE_STRING)
        self.cont[2:] = senc
      elif isinstance(s, int):
        # single language id
        super().__init__(2 + 2, self.DSC_TYPE_STRING)
        self.cont[2]  = (s & 0xff)
        self.cont[3]  = ( (s >> 8) & 0xff );
        self.isLangId = True
      elif isinstance(s, list):
        # list of language ids
        super().__init__(2 + 2*len(s), self.DSC_TYPE_STRING)
        off = 2
        for i in s:
          if not isinstance(s, int):
            raise TypeError('Usb2StringDesc: list of language IDs must be a list of integers')
          self.cont[off + 0] = (i & 0xff)
          self.cont[off + 1] = ( (i >> 8) & 0xff );
          off += 2
        self.isLangId = True
      else:
        raise TypeError("Usb2StringDesc constructor expects str, int or list of int")

    def __repr__(self):
      return self.cont[2:].decode('utf-16-le')

    def nameAt(self, off):
      if ( off < 2 ):
        return super().nameAt( off )
      if ( 0 == off % 2 ):
        if (self.isLangId):
          return 'langID 0x{:04x}'.format(self.cont[off] + (self.cont[off+1]<<8))
        else:
          return self.cont[off:off+2].decode('utf-16-le')
      return None

  @factory
  class Usb2DeviceDesc(Usb2Desc.clazz):

    def __init__(self):
      super().__init__(18, self.DSC_TYPE_DEVICE)
      self.bcdUSB(0x0200)
      self.bcdDevice(0x0200)

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
    def __init__(self, other=None):
      super().__init__(10, self.DSC_TYPE_DEVICE_QUALIFIER)
      self.bcdUSB(0x0200)
      self.bReserved(0)
      if not other is None:
        self.bcdUSB( other.bcdUSB() )
        self.bDeviceClass( other.bDeviceClass() )
        self.bDeviceSubClass( other.bDeviceSubClass() )
        self.bDeviceProtocol( other.bDeviceProtocol() )
        self.bMaxPacketSize0( other.bMaxPacketSize0() )
        self.bNumConfigurations( other.bNumConfigurations() )

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
    def bmAttributes(self, v):
      if isinstance(v, CvtReader):
        v.obj |= 0x80
      else:
        v |= 0x80
      return v
    @acc(8)
    def bMaxPower(self, v): return v

  # Note that descriptors generated for the Usb2 firmware
  # never use 'OTHER_SPEED_CONFIGURATION' descriptors explicitly.
  # Instead, the descriptors for hi-speed capable devices may
  # contain two sections holding device- and configuration descriptors
  # for full- and high-speed, respectively. The firmware patches
  # the descriptor type of configuration descriptors belonging to
  # the currently inactive speed.
  @factory
  class Usb2Other_Speed_ConfigurationDesc(Usb2ConfigurationDesc.clazz):
    def __init__(self):
      super().__init__()
      self.bDescriptorType(self.DSC_TYPE_OTHER_SPEED_CONFIGURATION)

  @factory
  class Usb2InterfaceDesc(Usb2Desc.clazz):
    def __init__(self):
      super().__init__(9, self.DSC_TYPE_INTERFACE)
      self.bInterfaceNumber( 0 )
      self.bAlternateSetting( 0 )
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
    DSC_SUBTYPE_NCM                                      = 0x1A

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
    DSC_ACM_SUP_LINE_STATE          = 0x02
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

  @factory
  class Usb2CDCFuncNCMDesc(Usb2CDCDesc.clazz):

    DSC_NCM_SUP_NET_ADDRESS = 0x02

    def __init__(self):
      super().__init__( 6, self.DSC_TYPE_CS_INTERFACE )
      self.bDescriptorSubtype( self.DSC_SUBTYPE_NCM )
      self.bcdNcmVersion( 0x0100 )
      self.bmNetworkCapabilities( 0x00 )

    @acc(3,2)
    def bcdNcmVersion(self, v): return v

    @acc(5)
    def bmNetworkCapabilities(self, v): return v



  @factory
  class Usb2UAC2Desc(Usb2Desc.clazz):

    DSC_TYPE_CS_INTERFACE                                = 0x24
    DSC_TYPE_CS_ENDPOINT                                 = 0x25

    DSC_SUBTYPE_HEADER                                   = 0x01
    DSC_SUBTYPE_INPUT_TERMINAL                           = 0x02
    DSC_SUBTYPE_OUTPUT_TERMINAL                          = 0x03
    DSC_SUBTYPE_MIXER_UNIT                               = 0x04
    DSC_SUBTYPE_SELECTOR_UNIT                            = 0x05
    DSC_SUBTYPE_FEATURE_UNIT                             = 0x06

    DSC_SUBTYPE_CLOCK_SOURCE                             = 0x0A

    DSC_CATEGORY_DESKTOP_SPEAKER                         = 0x01
    DSC_CATEGORY_MICROPHONE                              = 0x03
    DSC_CATEGORY_HEADSET                                 = 0x04
    DSC_CATEGORY_OTHER                                   = 0xff

    DSC_AUDIO_TERMINAL_TYPE_STREAMING                    = 0x0101
    DSC_AUDIO_TERMINAL_TYPE_OUT_SPEAKER                  = 0x0301

    DSC_SUBTYPE_AS_GENERAL                               = 0x01
    DSC_SUBTYPE_AS_FORMAT_TYPE                           = 0x02

    DSC_AS_FORMAT_TYPE_1                                 = 0x01

    DSC_AS_FORMAT_TYPE_1_PCM                             = 0x00000001

    DSC_SUBTYPE_EP_GENERAL                               = 0x01

    def __init__(self, length, typ):
      super().__init__(length, typ)

    @acc(2)
    def bDescriptorSubtype(self, v): return v

  @factory
  class Usb2UAC2FuncHeaderDesc(Usb2UAC2Desc.clazz):
    def __init__(self):
      super().__init__(9, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_HEADER )
      self.bcdADC(0x0200)

    @acc(3,2)
    def bcdADC(self, v): return v

    @acc(5)
    def bCategory(self, v): return v

    @acc(6,2)
    def wTotalLength(self, v): return v

    @acc(8)
    def bmControls(self, v): return v

  @factory
  class Usb2UAC2ClockSourceDesc(Usb2UAC2Desc.clazz):
    DSC_CLK_SRC_EXTERNAL       = 0x00
    DSC_CLK_SRC_INTERNAL_FIXED = 0x01
    DSC_CLK_SRC_INTERNAL_PROG  = 0x02
    DSC_CLK_SRC_SOF_SYNCED     = 0x04

    DSC_CLK_SRC_CTL_FREQ_RO    = 0x01
    DSC_CLK_SRC_CTL_FREQ_RW    = 0x03
    DSC_CLK_SRC_CTL_VALID_RO   = 0x04
    DSC_CLK_SRC_CTL_VALID_RW   = 0x0C

    def __init__(self):
      super().__init__(8, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_CLOCK_SOURCE )

    @acc(3)
    def bClockID(self, v): return v

    @acc(4)
    def bmAttributes(self, v): return v

    @acc(5)
    def bmControls(self, v): return v

    @acc(6)
    def bAssocTerminal(self, v): return v

    @acc(7)
    def iClockSource(self, v): return self.cvtString(v)

  @factory
  class Usb2UAC2InputTerminalDesc(Usb2UAC2Desc.clazz):
    def __init__(self):
      super().__init__(17, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_INPUT_TERMINAL )

    @acc(3)
    def bTerminalID(self, v): return v

    @acc(4,2)
    def wTerminalType(self, v): return v

    @acc(6)
    def bAssocTerminal(self, v): return v

    @acc(7)
    def bCSourceID(self, v): return v

    @acc(8)
    def bNrChannels(self, v): return v

    @acc(9,4)
    def bmChannelConfig(self, v): return v

    @acc(13)
    def iChannelNames(self, v): return self.cvtString(v)

    @acc(14, 2)
    def bmControls(self, v): return v

    @acc(16)
    def iTerminal(self, v): return self.cvtString(v)

  @factory
  class Usb2UAC2OutputTerminalDesc(Usb2UAC2Desc.clazz):
    def __init__(self):
      super().__init__(12, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_OUTPUT_TERMINAL )

    @acc(3)
    def bTerminalID(self, v): return v

    @acc(4,2)
    def wTerminalType(self, v): return v

    @acc(6)
    def bAssocTerminal(self, v): return v

    @acc(7)
    def bSourceID(self, v): return v

    @acc(8)
    def bCSourceID(self, v): return v

    @acc(8)
    def bNrChannels(self, v): return v

    @acc(9, 2)
    def bmControls(self, v): return v

    @acc(11)
    def iTerminal(self, v): return self.cvtString(v)

  @factory
  class Usb2UAC2MonoFeatureUnitDesc(Usb2UAC2Desc.clazz):
    def __init__(self):
      super().__init__(14, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( d.DSC_SUBTYPE_FEATURE_UNIT )

    @acc(3)
    def bUnitID(self, v): return v

    @acc(4)
    def bSourceID(self, v): return v

    @acc(5, 4)
    def bmaControls0(self, v): return v

    @acc(9, 4)
    def bmaControls1(self, v): return v

    @acc(13)
    def iFeature(self,v): return self.cvtString(v)

  @factory
  class Usb2UAC2StereoFeatureUnitDesc(Usb2UAC2Desc.clazz):
    def __init__(self):
      super().__init__(18, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_FEATURE_UNIT )

    @acc(3)
    def bUnitID(self, v): return v

    @acc(4)
    def bSourceID(self, v): return v

    @acc(5, 4)
    def bmaControls0(self, v): return v

    @acc(9, 4)
    def bmaControls1(self, v): return v

    @acc(13, 4)
    def bmaControls2(self, v): return v

    @acc(17)
    def iFeature(self,v): return self.cvtString(v)

  @factory
  class Usb2UAC2ClassSpecificASInterfaceDesc(Usb2UAC2Desc.clazz):

    def __init__(self):
      super().__init__(16, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_AS_GENERAL )

    @acc(3)
    def bTerminalLink(self, v): return v

    @acc(4)
    def bmControls(self, v): return v

    @acc(5)
    def bFormatType(self, v): return v

    @acc(6,4)
    def bmFormats(self, v): return v

    @acc(10)
    def bNrChannels(self, v): return v

    @acc(11,4)
    def bmChannelConfig(self, v): return v

    @acc(15)
    def iChannelNames(self, v): return self.cvtStr(v)

  @factory
  class Usb2UAC2FormatType1Desc(Usb2UAC2Desc.clazz):

    def __init__(self):
      super().__init__(6, self.DSC_TYPE_CS_INTERFACE)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_AS_FORMAT_TYPE )
      self.bFormatType( self.DSC_AS_FORMAT_TYPE_1 )

    @acc(3)
    def bFormatType(self, v): return v

    @acc(4)
    def bSubslotSize(self, v): return v

    @acc(5)
    def bBitResolution(self, v): return v

  @factory
  class Usb2UAC2ASISOEndpointDesc(Usb2UAC2Desc.clazz):

    def __init__(self):
      super().__init__(8, self.DSC_TYPE_CS_ENDPOINT)
      self.bDescriptorSubtype( self.DSC_SUBTYPE_EP_GENERAL )

    @acc(3)
    def bmAttributes(self, v): return v

    @acc(4)
    def bmControls(self, v): return v

    @acc(5)
    def bLockDelayUnits(self, v): return v

    @acc(6,2)
    def wLockDelay(self, v): return v

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

def addBasicECM(ctxt, ifcNumber, epAddr, iMACAddr, epPktSize=None, hiSpeed=True, fcnTitle=None):
  numIfcs = 0
  numEPPs = 0
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
  if not fcnTitle is None:
    d.iFunction( fcnTitle )

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

  # endpoint 2, IRQ IN
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_IN | (epAddr + 1) )
  d.bmAttributes( d.ENDPOINT_TT_INTERRUPT )
  d.wMaxPacketSize( 16 )

  if ( hiSpeed ):
    d.bInterval(8) # (2**(interval - 1) microframes; 16 is max.
  else:
    d.bInterval(16) #ms

  numEPPs += 1
  numIfcs += 1

  # interface 1 - alt 0
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + 1 )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_DAT )
  d.bInterfaceSubClass( d.DSC_DAT_SUBCLASS_NONE )
  d.bInterfaceProtocol( d.DSC_CDC_PROTOCOL_NONE )

  # interface 1 - alt 1
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + 1 )
  d.bAlternateSetting(1)
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

  numEPPs += 1
  numIfcs += 1
  # return number of interfaces and endpoint pairs used
  return numIfcs, numEPPs

def addBasicNCM(ctxt, ifcNumber, epAddr, iMACAddr, epPktSize=None, hiSpeed=True, fcnTitle=None):
  numIfcs = 0
  numEPPs = 0
  if epPktSize is None:
    if ( hiSpeed ):
      epPktSize = 512
    else:
      epPktSize = 64
  d = ctxt.Usb2InterfaceAssociationDesc()
  d.bFirstInterface( ifcNumber )
  d.bInterfaceCount( 2 )
  d.bFunctionClass( d.DSC_IFC_CLASS_CDC )
  d.bFunctionSubClass( d.DSC_CDC_SUBCLASS_NCM )
  d.bFunctionProtocol( d.DSC_CDC_PROTOCOL_NONE )
  if not fcnTitle is None:
    d.iFunction( fcnTitle )

  # interface 0
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_CDC )
  d.bInterfaceSubClass( d.DSC_CDC_SUBCLASS_NCM )
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

  # functional descriptors; NCM
  d = ctxt.Usb2CDCFuncNCMDesc()

  # endpoint 2, IRQ IN
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_IN | (epAddr + 1) )
  d.bmAttributes( d.ENDPOINT_TT_INTERRUPT )
  d.wMaxPacketSize( 16 )

  if ( hiSpeed ):
    d.bInterval(8) # (2**(interval - 1) microframes; 16 is max.
  else:
    d.bInterval(16) #ms

  numEPPs += 1
  numIfcs += 1

  # interface 1 - alt 0
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + 1 )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_DAT )
  d.bInterfaceSubClass( d.DSC_DAT_SUBCLASS_NONE )
  d.bInterfaceProtocol( d.DSC_DAT_PROTOCOL_NCM )

  # interface 1 - alt 1
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + 1 )
  d.bAlternateSetting(1)
  d.bInterfaceClass( d.DSC_IFC_CLASS_DAT )
  d.bInterfaceSubClass( d.DSC_DAT_SUBCLASS_NONE )
  d.bInterfaceProtocol( d.DSC_DAT_PROTOCOL_NCM )

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

  numEPPs += 1
  numIfcs += 1
  # return number of interfaces and endpoint pairs used
  return numIfcs, numEPPs


# epPktSize None selects the max. allowed for the selected speed
# ifcNum defines the index of the first of two interfaces used by
# this class
def addBasicACM(ctxt, ifcNumber, epAddr, epPktSize=None, sendBreak=False, lineState=False, hiSpeed=True, fcnTitle = None):
  numIfcs = 0
  numEPPs = 0
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
  if not fcnTitle is None:
    d.iFunction( fcnTitle )

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
  if ( lineState ):
    v |= d.DSC_ACM_SUP_LINE_STATE
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
    if ( lineState ):
      d.bInterval(8)
    else:
      d.bInterval(16) # (2**(interval - 1) microframes; 16 is max.
  else:
    if ( lineState ):
      d.bInterval(16) #ms
    else:
      d.bInterval(255) #ms

  numIfcs += 1
  numEPPs += 1

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

  numEPPs += 1
  numIfcs += 1
  # return number of interfaces and endpoint pairs used
  return numIfcs, numEPPs

def addUAC2Speaker(ctxt, ifcNumber, epAddr, hiSpeed = True, has24Bits = True, isAsync = True, fcnTitle=None):
  numIfcs = 0
  numEPPs = 0

  # MacOS would mute the device if they found that we support
  # no controls. Thus, enable them. The related control requests
  # are supported anyways; just no i2c implementation...
  haveMasterMute   = True
  haveMasterVolume = True

  haveLRMute       = True
  haveLRVolume     = True

  d = ctxt.Usb2InterfaceAssociationDesc()
  d.bFirstInterface( ifcNumber )
  d.bInterfaceCount( 2 )
  d.bFunctionClass( d.DSC_IFC_CLASS_AUDIO )
  d.bFunctionSubClass( d.DSC_FCN_SUBCLASS_AUDIO_UNDEFINED )
  d.bFunctionProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC2 )
  if not fcnTitle is None:
    d.iFunction( fcnTitle )

  # AC (audio-control) interface
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + numIfcs )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_CONTROL )
  d.bInterfaceProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC2 )

  # no endpoints (optional interrupt endpoint omitted)

  numIfcs += 1

  numChannels = 2
  totl        = 0
  d = ctxt.Usb2UAC2FuncHeaderDesc()
  d.bCategory( d.DSC_CATEGORY_DESKTOP_SPEAKER )
  d.bmControls( 0x00 )
  hdr   = d
  totl += d.size

  # IDs must match BADD profile for the BADDSpkrCtl to be
  # able to dispatch the requests to the correct unit
  clkID = 0x09
  inTID = 0x01
  ftrID = 0x02
  ouTID = 0x03

  d = ctxt.Usb2UAC2ClockSourceDesc()
  d.bClockID( clkID )
  d.bmAttributes( d.DSC_CLK_SRC_EXTERNAL )
  d.bmControls( d.DSC_CLK_SRC_CTL_FREQ_RO )
  d.bAssocTerminal( 0x00 )
  totl += d.size

  d = ctxt.Usb2UAC2InputTerminalDesc()
  d.bTerminalID( inTID )
  d.wTerminalType( d.DSC_AUDIO_TERMINAL_TYPE_STREAMING )
  d.bAssocTerminal( 0x00 )
  d.bCSourceID( clkID )
  d.bNrChannels( numChannels )
  if ( 2 == numChannels ):
    channelConfig = 0x3 # front left right
  else:
    channelConfig = 0x4 # front center
  d.bmChannelConfig( channelConfig )
  totl += d.size

  if ( 2 == numChannels ):
    d = ctxt.Usb2UAC2StereoFeatureUnitDesc()
  else:
    d = ctxt.Usb2UAC2MonoFeatureUnitDesc()

  d.bUnitID( ftrID )
  d.bSourceID( inTID )

  ctls = 0
  if ( haveMasterMute ):
    ctls |= 3
  if ( haveMasterVolume ):
    ctls |= 0xc
  d.bmaControls0( ctls )

  ctls = 0
  if ( haveLRMute ):
    ctls |= 3
  if ( haveLRVolume ):
    ctls |= 0xc
  d.bmaControls1( ctls )
  if ( 2 == numChannels ):
    d.bmaControls2( ctls )
  totl += d.size

  d = ctxt.Usb2UAC2OutputTerminalDesc()
  d.bTerminalID( ouTID )
  d.wTerminalType( d.DSC_AUDIO_TERMINAL_TYPE_OUT_SPEAKER )
  d.bAssocTerminal( 0x00 )
  d.bSourceID( ftrID )
  d.bCSourceID( clkID )
  d.bmControls( 0x0000 )
  totl += d.size

  hdr.wTotalLength( totl )

  # AS (audio-streaming interface)
  d = ctxt.Usb2InterfaceDesc()
  # zero-bandwidth altsetting 0
  d.bInterfaceNumber( ifcNumber + numIfcs )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_STREAMING )
  d.bInterfaceProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC2 )

  # AS (audio-streaming interface)
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + numIfcs )
  # 1kHz altsetting 1
  d.bAlternateSetting(1)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_STREAMING )
  d.bInterfaceProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC2 )

  # AS CS-specific interface
  d = ctxt.Usb2UAC2ClassSpecificASInterfaceDesc()
  d.bTerminalLink( inTID )
  d.bmControls( 0x00 )
  d.bFormatType( d.DSC_AS_FORMAT_TYPE_1 )
  d.bmFormats( d.DSC_AS_FORMAT_TYPE_1_PCM )
  d.bNrChannels( numChannels )
  d.bmChannelConfig( channelConfig )

  # AS CS-specific format
  d = ctxt.Usb2UAC2FormatType1Desc()
  if ( has24Bits ):
    d.bSubslotSize( 3 )
    d.bBitResolution( 24 )
  else:
    d.bSubslotSize( 2 )
    d.bBitResolution( 16 )

  # endpoint 1, ISO OUT
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_OUT | (epAddr + numEPPs) )
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
  pktSize = 48*numChannels*smpSize
  if ( isAsync ):
    pktSize += numChannels*smpSize
  d.wMaxPacketSize( pktSize )
  if ( hiSpeed ):
    d.bInterval(0x04)
  else:
    d.bInterval(0x01)

  d = ctxt.Usb2UAC2ASISOEndpointDesc()
  d.bmAttributes( 0x00 )

  if ( isAsync ):
    # endpoint 1, ISO INP -- feedback
    d = ctxt.Usb2EndpointDesc()
    d.bEndpointAddress( d.ENDPOINT_IN  | (epAddr + numEPPs) )
    atts =d.ENDPOINT_TT_ISOCHRONOUS | d.ENDPOINT_SYNC_NONE | d.ENDPOINT_USAGE_FEEDBACK
    d.bmAttributes( atts )
    if ( hiSpeed ):
      d.wMaxPacketSize( 4 )
      d.bInterval(0x04)
    else:
      d.wMaxPacketSize( 3 )
      d.bInterval(0x01)
  numEPPs += 1

  numIfcs += 1
  # return number of interfaces and endpoint pairs used
  return numIfcs, numEPPs

def addBADDSpeaker(ctxt, ifcNumber, epAddr, hiSpeed = True, has24Bits = True, isAsync = True, fcnTitle=None):
  numIfcs = 0
  numEPPs = 0
  d = ctxt.Usb2InterfaceAssociationDesc()
  d.bFirstInterface( ifcNumber )
  d.bInterfaceCount( 2 )
  d.bFunctionClass( d.DSC_IFC_CLASS_AUDIO )
  d.bFunctionSubClass( d.DSC_FCN_SUBCLASS_AUDIO_SPEAKER )
  d.bFunctionProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC3 )
  if not fcnTitle is None:
    d.iFunction( fcnTitle )

  # AC (audio-control) interface
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + numIfcs )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_CONTROL )
  d.bInterfaceProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC3 )
  # no endpoints (optional interrupt endpoint omitted)

  numIfcs += 1

  # AS (audio-streaming interface)
  d = ctxt.Usb2InterfaceDesc()
  # zero-bandwidth altsetting 0
  d.bInterfaceNumber( ifcNumber + numIfcs )
  d.bAlternateSetting(0)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_STREAMING )
  d.bInterfaceProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC3 )

  # AS (audio-streaming interface)
  d = ctxt.Usb2InterfaceDesc()
  d.bInterfaceNumber( ifcNumber + numIfcs )
  # 1kHz altsetting 1
  d.bAlternateSetting(1)
  d.bInterfaceClass( d.DSC_IFC_CLASS_AUDIO )
  d.bInterfaceSubClass( d.DSC_IFC_SUBCLASS_AUDIO_STREAMING )
  d.bInterfaceProtocol( d.DSC_FCN_PROTOCOL_AUDIO_UAC3 )

  # endpoint 1, ISO OUT
  d = ctxt.Usb2EndpointDesc()
  d.bEndpointAddress( d.ENDPOINT_OUT | (epAddr + numEPPs) )
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
    d.bEndpointAddress( d.ENDPOINT_IN  | (epAddr + numEPPs) )
    atts =d.ENDPOINT_TT_ISOCHRONOUS | d.ENDPOINT_SYNC_NONE | d.ENDPOINT_USAGE_FEEDBACK
    d.bmAttributes( atts )
    if ( hiSpeed ):
      d.wMaxPacketSize( 4 )
      d.bInterval(0x04)
    else:
      d.wMaxPacketSize( 3 )
      d.bInterval(0x01)
  numEPPs += 1

  numIfcs += 1
  # return number of interfaces and endpoint pairs used
  return numIfcs, numEPPs
