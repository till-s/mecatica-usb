#!/usr/bin/env python3

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

import sys
import random
import io
import getopt

# read a bitvec file
def bv2l(nm):
  rv = []
  with io.open(nm) as f:
    for l in f:
      rv.append( int( l, 2 ) )
  return rv

class NTB16(object):
  def __init__(self, l=None):
    self.lst_  = list()
    # Chain of NDPs
    self.tail_ = None
    self.lck_  = False
    if l is None:
      self.add( NTH16() )
    else:
      nth = NTH16(l = l)
      b   = nth.wNdpIndex
      e   = nth.wBlockLength
      self.add(nth)
      while b != 0:
        ndp = NDP16( l = l[b:e] )
        self.add( ndp )
        idx = 0
        b   = ndp.wDatagramIndex(idx)
        while ( b > 0 ):
         self.add( Dgram( ndp=ndp, l = l[b: b + ndp.wDatagramSize(idx)] ) )
         idx += 1
         b = ndp.wDatagramIndex(idx)
        b = ndp.wNextNdpIndex
      self.lck_ = True

  def getNTH(self):
    return self.lst_[0]

  def getDgrams(self):
    rv = list()
    for x in self.lst_:
      if isinstance(x, Dgram):
        rv.append(x)
    return rv

  def add(self, o):
    if ( o in self.lst_ ):
      raise RuntimeError("Cannot add same object multiple times")
    if ( self.lck_ ):
      raise RuntimeError("Cannot add to locked NTB16")
    if isinstance(o, NDP16):
      o.lock()
    self.lst_.append(o)

  def wrap(self, hasBlockLen = True):
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
    if ( hasBlockLen ):
      bl = idx
    else:
      bl = 0
    self.lst_[0].wBlockLength = bl
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

  def bitVec(self, f=sys.stdout):
    for x in self.lst_:
      x.bitVec( f=f, m=0xff)
    # this is a 'don' (not LST) flag
    print("100000000", file=f)

  def bitVecDgram(self, f=sys.stdout, stripCRC = True):
    for x in self.lst_:
      if isinstance(x, Dgram):
        x.bitVec( f = f, stripCRC = stripCRC )

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

  def bitVec(self, f=sys.stdout, m = 0x1FF, stripCRC = False):
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

  def bitVec(self, f=sys.stdout, m=0x1ff, stripCRC=False):
    self.bv_.bitVec( f = f, m = m, stripCRC = stripCRC )

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

  def bitVec(self, f = sys.stdout, m = 0x1ff, stripCRC=False):
    super().bitVec( f = f, m = m, stripCRC = stripCRC )

  def getContent(self):
    return self.bv_

class NTH16(BitVecHolder):
  seq = 1
  def __init__(self, l=None):
    sig = [0x4E, 0x43, 0x4D, 0x48]
    if l is None:
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
    else:
      for i in range( len( sig ) ):
        if l[i] != sig[i]:
           raise RuntimeError("NTH16 Invalid signature")
      super().__init__("NTH16", l)
      if self.wHeaderLength != 12:
         raise RuntimeError("NTH16: invalid header length")

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

  def __init__(self, addCRC=False, l=None):
    sig       = [0x4E, 0x43, 0x4D, 0x30]
    self.lck_ = False
    self.dgs_ = list()
    if l is None:
      l = list()
      l.extend( [0x4E, 0x43, 0x4D, 0x30] )
      if (addCRC):
         l[3] |= 1
      l.extend( [ 0,0] ) # Header Length
      l.extend( [ 0,0] ) # Next NDP
      l.extend( [ 0,0] ) # first PTR
      l.extend( [ 0,0] ) # first LEN
      l.extend( [ 0,0] ) # trailing zero index
      l.extend( [ 0,0] ) # trailing zero length
      super().__init__( "NDP16", l )
      self.setHeaderLength()
    else:
      for i in range(3):
        if ( sig[i] != l[i] ):
          raise RuntimeError("NDP16: signature mismatch")
      if   ( l[3] != 0x30 and  l[3] != 0x31 ):
        raise RuntimeError("NDP16: signature mismatch")
      hl = (l[5] << 8) + l[4]
      if ( hl > 100 ):
        raise RuntimeError("NDP16: unreasonable header length")
      super().__init__( "NDP16", l[0:hl] )

  def lock(self):
    if ( self.lck_ ):
      raise RuntimeError("Cannot re-lock")
    self.lck_ = True

  @property
  def addCRC(self):
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

  def wDatagramIndex(self, n):
    return self.bv_.get16LE( 8 + n*4 )

  def wDatagramSize(self, n):
    return self.bv_.get16LE( 8 + 2 + n*4 )

  def setHeaderLength(self):
    self.bv_.set16LE(4, self.getLen())

  def add(self, dgram):
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

  def getDatagrams(self):
    return self.dgs_

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

def genVecs(pre):

  n=NTB16()
  ndp=NDP16()
  ndpc=NDP16( addCRC=True )
  dg0=Dgram(ndp, [1,2,4])
  dg1=Dgram(ndp, [8,6,7])
  dg2=Dgram(ndpc, [1])
  n.add(dg0)
  n.add(ndp)
  n.add(NDP16())
  n.add(ndpc)
  n.add(dg1)
  n.add(dg2)
  n.wrap(hasBlockLen = True)
  n.dump()

  n1=NTB16()
  ndp=NDP16()
  n1.add( Dgram(ndp, random.randbytes(7)) )
  n1.add( Dgram(ndp, random.randbytes(16)) )
  n1.add(ndp)
  n1.wrap(hasBlockLen = False)
  n1.dump()

  n1a=NTB16()
  ndp=NDP16()
  n1a.add( Dgram(ndp, random.randbytes(7)) )
  n1a.add( Dgram(ndp, random.randbytes(16)) )
  n1a.add(ndp)
  n1a.wrap(hasBlockLen = True)
  n1a.dump()


  n2=NTB16()
  ndp=NDP16()
  n2.add(ndp)
  n2.add( Dgram(ndp, random.randbytes(31)) )
  ndp=NDP16(addCRC=True)
  n2.add(ndp)
  n2.add( Dgram(ndp, random.randbytes(30)) )
  n2.wrap(hasBlockLen=True)
  n2.dump()

  with io.open(pre + "OutTst.txt","w") as f:
    n.bitVec(f = f)
    n1.bitVec(f = f)
    n1a.bitVec(f = f)
    n2.bitVec(f = f)
  with io.open(pre + "OutCmp.txt","w") as f:
    n.bitVecDgram(f = f)
    n1.bitVecDgram(f = f)
    n1a.bitVecDgram(f = f)
    n2.bitVecDgram(f = f)

def inpVerify(pre):
  cmp  = bv2l( pre+"InpCmp.txt" )
  b    = 0
  ntbs = list()
  dgs  = list()
  while b < len(cmp):
    ntb = NTB16( l = cmp[b:] )
    ntbs.append(ntb)
    for dg in ntb.getDgrams():
      dgs.extend( dg.getContent() )
    b  += ntb.getNTH().wBlockLength
  tst = bv2l( pre+"InpTst.txt" )
  if ( tst != dgs ):
    for i in range(len(tst)):
      if ( tst[i] != dgs[i] ):
        mrk = "****<<<<<"
      else:
        mrk = ""
      print("{:d}: {:02x}, {:02x} {}".format( i, tst[i], dgs[i], mrk ) )
    raise RuntimeError("Verification mismatch")

if __name__ == "__main__":

  pre = "NCM"
  gen = False
  chk = False

  ( opts, args ) = getopt.getopt(sys.argv[1:], "p:oi")
  for opt in opts:
    if   opt[0] in ("-p"):
      pre = opt[1]
    elif opt[0] in ("-o"):
      gen = True
    elif opt[0] in ("-i"):
      chk = True

  if ( gen ) :
    genVecs( pre )
  if ( chk ):
    inpVerify( pre )
