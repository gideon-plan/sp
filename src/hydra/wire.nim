## wire.nim -- SP wire format: encode/decode frames, 64-bit size prefix, protocol IDs.
##
## SP frame: 8-byte size (network byte order, big-endian) + SP header + payload.
## SP header varies by protocol (e.g., REQ/REP includes backtrace).

{.experimental: "strict_funcs".}

# =====================================================================================================================
# Errors
# =====================================================================================================================

type
  SpError* = object of CatchableError

# =====================================================================================================================
# Protocol IDs
# =====================================================================================================================

const
  spPair*       = 0x10'u16
  spPub*        = 0x20'u16
  spSub*        = 0x21'u16
  spReq*        = 0x30'u16
  spRep*        = 0x31'u16
  spPush*       = 0x50'u16
  spPull*       = 0x51'u16
  spSurveyor*   = 0x60'u16
  spRespondent* = 0x61'u16
  spBus*        = 0x70'u16

proc peer_protocol*(proto: uint16): uint16 =
  ## Return the expected peer protocol for a given protocol.
  case proto
  of spPair: spPair
  of spPub: spSub
  of spSub: spPub
  of spReq: spRep
  of spRep: spReq
  of spPush: spPull
  of spPull: spPush
  of spSurveyor: spRespondent
  of spRespondent: spSurveyor
  of spBus: spBus
  else: 0

# =====================================================================================================================
# Frame encode/decode
# =====================================================================================================================

proc encode_size*(size: uint64): string =
  ## Encode a 64-bit size in network byte order (big-endian).
  result = newString(8)
  result[0] = char((size shr 56) and 0xFF)
  result[1] = char((size shr 48) and 0xFF)
  result[2] = char((size shr 40) and 0xFF)
  result[3] = char((size shr 32) and 0xFF)
  result[4] = char((size shr 24) and 0xFF)
  result[5] = char((size shr 16) and 0xFF)
  result[6] = char((size shr 8) and 0xFF)
  result[7] = char(size and 0xFF)

proc decode_size*(buf: string, pos: var int): uint64 {.raises: [SpError].} =
  ## Decode a 64-bit size from network byte order. Advances pos by 8.
  if pos + 8 > buf.len:
    raise newException(SpError, "buffer too short for size prefix")
  result = (uint64(uint8(buf[pos])) shl 56) or
           (uint64(uint8(buf[pos + 1])) shl 48) or
           (uint64(uint8(buf[pos + 2])) shl 40) or
           (uint64(uint8(buf[pos + 3])) shl 32) or
           (uint64(uint8(buf[pos + 4])) shl 24) or
           (uint64(uint8(buf[pos + 5])) shl 16) or
           (uint64(uint8(buf[pos + 6])) shl 8) or
           uint64(uint8(buf[pos + 7]))
  pos += 8

type
  SpFrame* = object
    ## An SP message frame: optional header bytes + payload.
    header*: string   ## Protocol-specific header (e.g., backtrace for REQ/REP)
    payload*: string  ## Application data

proc encode_frame*(frame: SpFrame): string =
  ## Encode an SP frame with 64-bit size prefix.
  let body = frame.header & frame.payload
  result = encode_size(uint64(body.len)) & body

proc decode_frame*(buf: string, pos: var int): SpFrame {.raises: [SpError].} =
  ## Decode an SP frame from buf starting at pos. Advances pos.
  let size = int(decode_size(buf, pos))
  if pos + size > buf.len:
    raise newException(SpError, "frame extends beyond buffer")
  let body = buf[pos ..< pos + size]
  pos += size
  result = SpFrame(header: "", payload: body)

# =====================================================================================================================
# SP handshake
# =====================================================================================================================

const
  spHandshakeLen* = 8  ## 4 bytes "\x00SP\x00" + 2 bytes protocol + 2 bytes reserved

proc encode_handshake*(proto: uint16): string =
  ## Encode SP handshake: \x00SP\x00 + protocol ID (big-endian) + 2 reserved bytes.
  result = newString(8)
  result[0] = '\x00'
  result[1] = 'S'
  result[2] = 'P'
  result[3] = '\x00'
  result[4] = char((proto shr 8) and 0xFF)
  result[5] = char(proto and 0xFF)
  result[6] = '\x00'
  result[7] = '\x00'

proc decode_handshake*(buf: string, pos: var int): uint16 {.raises: [SpError].} =
  ## Decode SP handshake. Returns the peer's protocol ID. Advances pos by 8.
  if pos + 8 > buf.len:
    raise newException(SpError, "buffer too short for handshake")
  if buf[pos] != '\x00' or buf[pos + 1] != 'S' or buf[pos + 2] != 'P' or buf[pos + 3] != '\x00':
    raise newException(SpError, "invalid SP handshake magic")
  result = (uint16(uint8(buf[pos + 4])) shl 8) or uint16(uint8(buf[pos + 5]))
  pos += 8
