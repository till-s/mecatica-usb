#!/usr/bin/env python3

import sys
import random

class NTB16(object):
  def __init__(self):
    self.lst_  = list()
    # Chain of NDPs
    self.tail_ = None
    self.lck_  = False
    self.add( NTH16() )

  def add(self, o):
    if ( o in self.lst_ ):
      raise RuntimeError("Cannot add same object multiple times")
    if ( self.lck_ ):
      raise RuntimeError("Cannot add to locked NTB16")
    if isinstance(o, NDP16):
      o.lock()
    self.lst_.append(o)

  def wrap(self):
    self.lck_ = True
    idx = 0
    # must word-align the first NDP16
    for i in range( len( self.lst_ ) ):
      if isinstance( self.lst_[i], NDP16 ):
        # first NDP must be word-aligned
        miss = ( (-idx) % 4 )
        break
      idx += self.lst_[i].getLen()
    if ( miss != 0 ):
      print("Doing miss {:d}".format(miss))
      self.lst_.insert( i, BitVecHolder( "PAD", [ 0 for i in range(miss)] ) )
    idx = 0
    # compute positions of everything
    for x in self.lst_:
      x.setIdx( idx )
      idx += x.getLen()
    # set total length
    self.lst_[0].wBlockLength = idx
    # fixup SDPs
    nxt = None
    for x in self.lst_:
      x.fixup()
      nxt = x.nextNDP( nxt )

  def dump(self):
    if ( not self.lck_ ):
      raise RuntimeError("NTB not wrapped")
    for l in self.lst_:
      l.dump()

  def vhdl(self, f=sys.stdout):
    for x in self.lst_[0:-1]:
      x.vhdl( f=f, m=0xff)
    self.lst_[-1].vhdl( f = f )

  def vhdlDgram(self, f=sys.stdout, stripCRC = True):
    for x in self.lst_:
      if isinstance(x, Dgram):
        x.vhdl( f = f, stripCRC = stripCRC )
    
class BitVec(list):

  def __init__(self, l):
    super().__init__()
    for x in l:
       self.append( x & 0xff )
    self.setLst()

  def setLst(self):
    self[-1] |= 256

  @staticmethod
  def isLst(x):
    return (x & 256) != 0

  def set16LE(self, idx, val):
     self[idx+0] = val & 0xff
     self[idx+1] = (val >> 8 ) & 0xff

  def get16LE(self, idx):
     return ((self[idx+1] & 0xff) << 8 ) | (self[idx] & 0xff)

  def vhdl(self, f=sys.stdout, m = 0x1FF, stripCRC = False):
    for x in self:
       print("{:09b}".format(x & m), file=f)

  def clrLst(self):
    if ( len(self) > 0 ):
      self[-1] &= 0xff

  def append(self, x):
    self.clrLst()
    super().append( x & 0xff )
    self.setLst()

  def extend(self, x):
    self.clrLst()
    for y in x:
      self.append( y & 0xff )
    self.setLst()

  def getLen(self):
    return len(self)

class BitVecHolder(object):
  def __init__(self, nam, l):
    self.bv_  = BitVec( l )
    self.nam_ = nam
    self.idx_ = 0

  def getLen(self):
    return self.bv_.getLen()

  def getIdx(self):
    return self.idx_

  def setIdx(self, idx):
    self.idx_ = idx

  def fixup(self):
    pass

  def dump(self):
    print("@ {:4d}: {}".format(self.getIdx(), self.nam_))

  def nextNDP(self, x):
    return x

  def linkNDP(self, x):
    pass

  def vhdl(self, f=sys.stdout, m=0x1ff, stripCRC=False):
    self.bv_.vhdl( f = f, m = m, stripCRC = stripCRC )

class Dgram(BitVecHolder):
  def __init__(self, ndp, l):
    super().__init__( "DGRAM", l)
    self.ndp_ = ndp
    ndp.add( self )

  def extend(self, l):
    self.bv_.extend( l )

  def dump(self):
    super().dump()
    print("  Raw Data     : ", end='')
    for x in self.bv_:
      print("{:02x} ".format( x & 0xff ), end ='')
      if ( self.bv_.isLst( x ) ):
        print(" (LST) ", end ='')
    print()

  def vhdl(self, f = sys.stdout, m = 0x1ff, stripCRC=False):
    if ( not stripCRC or not self.ndp_.hasCRC ):
      super().vhdl( f = f, m = m, stripCRC = stripCRC )
    else:
      for x in self.bv_[0:-5]:
        print("{:09b}".format(x & m), file=f)
      print("{:09b}".format( self.bv_[-5] | 0x100, file = f ))

class NTH16(BitVecHolder):
  seq = 1
  def __init__(self):
    l = list()
    l.extend( [0x4E, 0x43, 0x4D, 0x48] )
    l.extend( [ 0,0] ) # Header Length
    l.extend( [ 0,0] ) # seq
    l.extend( [ 0,0] ) # block length
    l.extend( [ 0,0] ) # sdpOff
    super().__init__( "NTH16", l )
    self.wHeaderLength = 12
    self.wSequence     = self.seq
    self.seq          += 1

  @property
  def wHeaderLength(self):
    return self.bv_.get16LE(4)

  @wHeaderLength.setter
  def wHeaderLength(self, v):
    self.bv_.set16LE(4, v)

  @property
  def wSequence(self):
    return self.bv_.get16LE(6)

  @wSequence.setter
  def wSequence(self, v):
    self.bv_.set16LE(6, v)

  @property
  def wBlockLength(self):
    return self.bv_.get16LE(8)

  @wBlockLength.setter
  def wBlockLength(self, v):
    self.bv_.set16LE(8, v)

  @property
  def wNdpIndex(self):
    return self.bv_.get16LE(10)

  @wNdpIndex.setter
  def wNdpIndex(self, v):
    self.bv_.set16LE(10, v)

  def dump(self):
    super().dump()
    print("  signature: {:c}{:c}{:c}{:c}".format( self.bv_[0], self.bv_[1], self.bv_[2], self.bv_[3] ))
    print("  wHeaderLength: {:4d}".format( self.wHeaderLength ) )
    print("  wSequence    : {:4d}".format( self.wSequence     ) )
    print("  wBlockLength : {:4d}".format( self.wBlockLength  ) )
    print("  wNdpIndex    : {:4d}".format( self.wNdpIndex     ) )

  def nextNDP(self, x):
    return self

  def linkNDP(self, x):
    self.wNdpIndex = x.getIdx()


class NDP16(BitVecHolder):

  seq = 1

  def __init__(self, hasCRC=False):
    l = list()
    l.extend( [0x4E, 0x43, 0x4D, 0x30] )
    if (hasCRC):
       l[3] |= 1
    l.extend( [ 0,0] ) # Header Length
    l.extend( [ 0,0] ) # Next NDP
    l.extend( [ 0,0] ) # first PTR
    l.extend( [ 0,0] ) # first LEN
    l.extend( [ 0,0] ) # trailing zero index
    l.extend( [ 0,0] ) # trailing zero length
    super().__init__( "NDP16", l )
    self.lck_ = False
    self.dgs_ = list()
    self.setHeaderLength()

  def lock(self):
    if ( self.lck_ ):
      raise RuntimeError("Cannot re-lock")
    self.lck_ = True

  @property
  def hasCRC(self):
    return (self.bv_[3] & 1) != 0

  @property
  def wHeaderLength(self):
    return self.bv_.get16LE(4)

  @property
  def wNextNdpIndex(self):
    return self.bv_.get16LE(6)

  @wNextNdpIndex.setter
  def wNextNdpIndex(self, v):
    self.bv_.set16LE(6, v)

  def setHeaderLength(self):
    self.bv_.set16LE(4, self.getLen())

  def add(self, dgram):
    if ( self.hasCRC ):
      dgram.extend([0,0,0,0])
    if ( len( self.dgs_ ) != 0 ):
      self.bv_.extend( [0,0,0,0] )
    # else use first slot
    self.setHeaderLength()
    self.dgs_.append( dgram )

  def fixup(self):
    pos = 8
    for dg in self.dgs_:
      self.bv_.set16LE( pos, dg.getIdx() )
      pos += 2
      self.bv_.set16LE( pos, dg.getLen() )
      pos += 2
  
  def dump(self):
    super().dump()
    print("  signature: {:c}{:c}{:c}{:c}".format( self.bv_[0], self.bv_[1], self.bv_[2], self.bv_[3] ))
    print("  wHeaderLength: {:4d}".format( self.wHeaderLength ) )
    print("  wNextNdpIndex: {:4d}".format( self.wNextNdpIndex ) )
    i = 8
    while i < self.getLen():
      print("  wIdx[{:2d}]: {:4d}".format( (i - 8)>>2, self.bv_.get16LE(i    ) ))
      print("  wLen[{:2d}]: {:4d}".format( (i - 8)>>2, self.bv_.get16LE(i + 2) ))
      i += 4

  def nextNDP(self, x):
    x.linkNDP( self )
    return self

  def linkNDP(self, x):
    self.wNextNdpIndex = x.getIdx()

n=NTB16()
ndp=NDP16()
ndpc=NDP16( hasCRC=True )
dg0=Dgram(ndp, [1,2,4])
dg1=Dgram(ndp, [8,6,7])
dg2=Dgram(ndpc, [1])
n.add(dg0)
n.add(ndp)
n.add(NDP16())
n.add(ndpc)
n.add(dg1)
n.add(dg2)
n.wrap()
n.dump()
