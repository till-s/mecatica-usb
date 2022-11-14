import sys
import io

# accessor for an attribute
def acc(off,sz=1):
    def deco(func):
      def setter(self, v = None):
         if ( v is None ):
            v = 0
            for i in range(sz):
               v |= (self.cont[off+i] << (8*i))
            return v
         v = func(self, v)
         for i in range(sz):
            self.cont[off + i] = (v & 0xff)
            v >>= 8
         return self
      return setter
    return deco

class Usb2Desc(object):

  DSC_TYPE_DEVICE                    = 0x01
  DSC_TYPE_CONFIGURATION             = 0x02
  DSC_TYPE_STRING                    = 0x03
  DSC_TYPE_INTERFACE                 = 0x04
  DSC_TYPE_ENDPOINT                  = 0x05
  DSC_TYPE_DEVICE_QUALIFIER          = 0x06
  DSC_TYPE_OTHER_SPEED_CONFIGURATION = 0x07
  DSC_TYPE_INTEFACE_POWER            = 0x08

  DSC_DEV_CLASS_NONE                 = 0x00
  DSC_DEV_SUBCLASS_NONE              = 0x00
  DSC_DEV_PROTOCOL_NONE              = 0x00
  DSC_DEV_CLASS_CDC                  = 0x02

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

  def len(self):
    return len(self.cont)

  @property
  def cont(self):
    return self.cont_
  @acc(0)
  def bLength(self, v): return v
  @acc(1)
  def bDescriptorType(self, v): return v

class Usb2StringDesc(Usb2Desc):
  # language IDs
  tbl    = [ bytearray([0x04, Usb2Desc.DSC_TYPE_STRING, 0x09, 0x04]) ]
  idxgbl = 0

  def __init__(self, s):
    senc = s.encode('utf-16-le')
    super().__init__(2 + len(senc), Usb2Desc.DSC_TYPE_STRING)
    self.cont[2:] = senc
    Usb2StringDesc.idxgbl += 1
    self.idx_     = Usb2StringDesc.idxgbl
    self.tbl.append( self )

  def __repr__(self):
    return self.cont[2:].decode('utf-16-le')

  @property
  def idx(self):
    return self.idx_

class Usb2DeviceDesc(Usb2Desc):

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
  def iManufacturer(self, v): return Usb2StringDesc(v).idx
  @acc(15)
  def iProduct(self, v): return Usb2StringDesc(v).idx
  @acc(16)
  def iSerialNumber(self, v): return Usb2StringDesc(v).idx
  @acc(17)
  def bNumConfigurations(self, v): return v

class Usb2ConfigurationDesc(Usb2Desc):

  CONF_ATT_SELF_POWERED  = 0x40
  CONF_ATT_REMOTE_WAKEUP = 0x20

  def __init__(self):
    super().__init__(9, Usb2Desc.DSC_TYPE_CONFIGURATION)
    self.bmAttributes(0x00)
  @acc(2,2)
  def wTotalLength(self, v): return v
  @acc(4)
  def bNumInterfaces(self, v): return v
  @acc(5)
  def bConfigurationValue(self, v): return v
  @acc(6)
  def iConfiguration(self, v): return Usb2StringDesc(v).idx
  @acc(7)
  def bmAttributes(self, v): return v | 0x80
  @acc(8)
  def bMaxPower(self, v): return v

class Usb2InterfaceDesc(Usb2Desc):
  def __init__(self):
    super().__init__(9, Usb2Desc.DSC_TYPE_INTERFACE)
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
  def iInterface(self, v): return Usb2StringDesc(v).idx

class Usb2EndpointDesc(Usb2Desc):
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
    super().__init__(7, Usb2Desc.DSC_TYPE_ENDPOINT)
  @acc(2)
  def bEndpointAddress(self, v): return v
  @acc(3)
  def bmAttributes(self, v): return v
  @acc(4,2)
  def wMaxPacketSize(self, v): return v
  @acc(6)
  def bInterval(self, v): return v

class Usb2CDCDesc(Usb2Desc):

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
  
class Usb2CDCFuncHeaderDesc(Usb2CDCDesc):
  def __init__(self):
    super().__init__(5, Usb2CDCDesc.DSC_TYPE_CS_INTERFACE)
    self.bDescriptorSubtype( self.DSC_SUBTYPE_HEADER )
    self.bcdCDC(0x0120)
  @acc(3,2)
  def bcdCDC(self, v): return v

class Usb2CDCFuncCallManagementDesc(Usb2CDCDesc):
  DSC_CM_HANDLE_MYSELF            = 0x01
  DSC_CM_OVER_DATA                = 0x02
  def __init__(self):
    super().__init__(5, Usb2CDCDesc.DSC_TYPE_CS_INTERFACE)
    self.bDescriptorSubtype( self.DSC_SUBTYPE_CALL_MANAGEMENT )
  @acc(3)
  def bmCapabilities(self, v): return v
  @acc(4)
  def bDataInterface(self, v): return v

class Usb2CDCFuncACMDesc(Usb2CDCDesc):
  DSC_ACM_SUP_NOTIFY_NETWORK_CONN = 0x08
  DSC_ACM_SUP_SEND_BREAK          = 0x04
  DSC_ACM_SUP_LINE_CODING         = 0x02
  DSC_ACM_SUP_COMM_FEATURE        = 0x01
  def __init__(self):
    super().__init__(4, Usb2CDCDesc.DSC_TYPE_CS_INTERFACE)
    self.bDescriptorSubtype( self.DSC_SUBTYPE_ABSTRACT_CONTROL_MANAGEMENT )
  @acc(3)
  def bmCapabilities(self, v): return v

class Usb2CDCFuncUnionDesc(Usb2CDCDesc):
  def __init__(self, numSubordinateInterfaces):
    super().__init__(4 + numSubordinateInterfaces, Usb2CDCDesc.DSC_TYPE_CS_INTERFACE)
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

class Usb2DescriptorList(list):
  def __init__(self, *args, **kwargs):
    super().__init__(*args, **kwargs)

  def wrapup(self):
    cnf  = None
    totl = 0
    numi = 0
    seti = set()
    for d in self:
      if ( d.bDescriptorType() == Usb2Desc.DSC_TYPE_CONFIGURATION ):
        if ( not cnf is None ):
          break
        cnf  = d
        totl = 0
        numi = 0
        seti = set()
      if ( d.bDescriptorType() == Usb2Desc.DSC_TYPE_INTERFACE ):
        ifn =  d.bInterfaceNumber()
        if not ifn in seti:
           numi += 1
           seti.add(ifn)
      totl += d.bLength()
    print("Total length {:d}, num interfaces {:d}".format(totl, numi))
    cnf.wTotalLength(totl)
    cnf.bNumInterfaces(numi)

  def vhdl(self, f = sys.stdout):
    if isinstance(f, str):
      with io.open(f, "w") as f:
         self.vhdl(f)
    else:
      i = 0
      for x in self:
        for b in x.cont:
           print('      {:3d} => x"{:02x}",'.format(i, b), file = f)
           i += 1

def basicACM():
  l = Usb2DescriptorList()

  # device
  d = Usb2DeviceDesc()
  d.bDeviceClass( Usb2Desc.DSC_DEV_CLASS_NONE )
  d.bDeviceSubClass( Usb2Desc.DSC_DEV_SUBCLASS_NONE )
  d.bDeviceProtocol( Usb2Desc.DSC_DEV_PROTOCOL_NONE )
  d.bMaxPacketSize0( 8 )
  d.idVendor(0x0123)
  d.idProduct(0xabcd)
  d.bcdDevice(0x0100)
  d.bNumConfigurations(1)
  l.append(d)

  # configuration
  d = Usb2ConfigurationDesc()
  d.bNumInterfaces(2)
  d.bConfigurationValue(1)
  d.bMaxPower(0x32)
  l.append(d)

  # interface 0
  d = Usb2InterfaceDesc()
  d.bInterfaceNumber(0)
  d.bAlternateSetting(0)
  d.bNumEndpoints(1)
  d.bInterfaceClass( Usb2Desc.DSC_IFC_CLASS_CDC )
  d.bInterfaceSubClass( Usb2Desc.DSC_CDC_SUBCLASS_ACM )
  d.bInterfaceProtocol( Usb2Desc.DSC_CDC_PROTOCOL_NONE )
  l.append(d)

  # functional descriptors; header
  d = Usb2CDCFuncHeaderDesc()
  l.append(d)

  # functional descriptors; call management
  d = Usb2CDCFuncCallManagementDesc()
  d.bDataInterface(1)
  l.append(d)

  # functional descriptors; header
  d = Usb2CDCFuncACMDesc()
  d.bmCapabilities(0)
  l.append(d)

  # functional descriptors; union
  d = Usb2CDCFuncUnionDesc( numSubordinateInterfaces = 1 )
  d.bControlInterface( 0 )
  d.bSubordinateInterface( 0, 1 )
  l.append(d)

  # Endpoint -- unused but linux cdc-acm driver refuses to load w/o it
  # endpoint 2, INTERRUPT IN
  d = Usb2EndpointDesc()
  d.bEndpointAddress( Usb2EndpointDesc.ENDPOINT_IN  | 0x02 )
  d.bmAttributes( Usb2EndpointDesc.ENDPOINT_TT_INTERRUPT )
  d.wMaxPacketSize(64)
  d.bInterval(255) #ms
  l.append(d)

  # interface 1
  d = Usb2InterfaceDesc()
  d.bInterfaceNumber(1)
  d.bAlternateSetting(0)
  d.bNumEndpoints(2)
  d.bInterfaceClass( Usb2Desc.DSC_IFC_CLASS_DAT )
  d.bInterfaceSubClass( Usb2Desc.DSC_DAT_SUBCLASS_NONE )
  d.bInterfaceProtocol( Usb2Desc.DSC_CDC_PROTOCOL_NONE )
  l.append(d)

  # endpoint 1, BULK IN
  d = Usb2EndpointDesc()
  d.bEndpointAddress( Usb2EndpointDesc.ENDPOINT_IN | 0x01 )
  d.bmAttributes( Usb2EndpointDesc.ENDPOINT_TT_BULK )
  d.wMaxPacketSize(64)
  d.bInterval(0)
  l.append(d)

  # endpoint 1, BULK OUT
  d = Usb2EndpointDesc()
  d.bEndpointAddress( Usb2EndpointDesc.ENDPOINT_OUT | 0x01 )
  d.bmAttributes( Usb2EndpointDesc.ENDPOINT_TT_BULK )
  d.wMaxPacketSize(64)
  d.bInterval(0)
  l.append(d)

  l.wrapup()
  return l
