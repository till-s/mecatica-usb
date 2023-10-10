# Module to parse ulpi bus transactions

# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# The ulpi log data are presented in a bytarray of the following
# format:
#
#    data_byte, flag_byte, data_byte, flag_byte, ...
#
# The flag byte has the ulpi 'DIR' bit in the lsbit position.
#
# Packets are delimited by a change in DIR; the data associated
# with such a delimiter are undefined when DIR == 1
# (but 0x00 if DIR == 0).
#
# Note that a DIR == 1 packet is ended by a DIR == 0 delimiter
# which may be followed by an arbitrary number of NULL markers
# (DIR == 0, DAT == 0x00).
#
# E.g.
#   DIR  DAT
#    1   d0     first data byte of a DIR == 1 packet
#    1   d1
#    1   d2
#    1   d3     last data byte of a DIR == 1 packet
#    0   xx  <- delimiter
#    0   00  <- null marker (optional) 
#    0   00  <- null marker (optional)
#    0   d0    first byte of DIR == 0 packet
#    0   d1    first byte of DIR == 0 packet
#    1   xx  <- delimiter
#
# null markers can appear due to RXCMD in the ulpi data stream.
# Note that RXCMD can not be represented by this data format and
# must be dropped before storing data + flag bytes.

# THIS IS WIP

class UlpiLogParser(bytearray):

  DIR = 0x1

  def __init__(self, *args, **kwargs):
    super().__init__( *args, **kwargs )
    self._p   =  0

  def dir(self, off = 0):
    return bool( (self[self._p + off + 1] & 1) )

  def nullmark(self):
      return ( not self.dir() ) and ( self[self._p] == 0x00 )

  def getpkt(self):
    try:
      e = 2
      d = self.dir()
      while ( self.dir( e ) == d ):
        e += 2
      e += self._p
      rb      = self[self._p: e : 2]
      self._p = e
    except IndexError as ex:
      raise(ex)

    # skip mark
    nullmark = self.nullmark()
    # skip mark
    self._p += 2

    if nullmark:
      # rxcommand may leave multiple 0x00 markers
      try:
        while self.nullmark():
           self._p += 2
      except IndexError:
        pass
    return rb, d

  def rewind(self):
    self._p = 0

  pidTbl = [
    "NULL",
    "OUT",
    "ACK",
    "DATA0",
    "PING",
    "SOF",
    "NYET",
    "DATA2",
    "SPLIT",
    "IN",
    "NAK",
    "DATA1",
    "PRE",
    "SETUP",
    "STALL",
    "MDATA"
  ]

  @staticmethod
  def dump(tup, verbose = False):
    buf   = tup[0]
    isRx  = tup[1]
    pid   = buf[0]
    isDat = ((pid & 3) == 3);
    if ( isRx ):
      if ( ( pid >> 4 ) ^ pid ) & 0xf != 0xf:
        print("PID error 0x{:02x}".format(pid))
      print("RX: PID {:5s}".format(UlpiLogParser.pidTbl[ (pid&0xf) ]), end="")
    else:
      if   ( pid & 0xc0 == 0x00 ):
        print("TX: NOOP ?", end="")
        isDat = False
      elif ( pid & 0xc0 == 0x40 ):
        print("TX: PID {:5s}".format(UlpiLogParser.pidTbl[ (pid&0xf) ]), end="")
      elif ( pid & 0xc0 == 0x80 ):
        print("WR: REG 0x{:2x}".format( pid & 0x3f ), end="")
        isDat = False
      else:
        print("RD: REG 0x{:2x}".format( pid & 0x3f ), end="")
        isDat = False
    if ( isDat ):
      print(" ({:d})".format( len(buf) - 3, end="" ), end="")
      if ( verbose ):
        l = 0
        for d in buf[0:-2]:
          if ( 0 == l ):
            print("\n     ", end = "")
          print(" {:02X}".format(d), end="")
          l = (l + 1) & 0xf
    print()

  def dumpPkts(self, verbose = False):
    p = self._p
    self.rewind()
    try: 
      # first one may be corrupt
      self.getpkt()
      while True:
        self.dump( self.getpkt(), verbose )
    except IndexError:
      pass
    self._p = p
