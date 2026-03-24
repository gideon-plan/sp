## quic.nim -- QUIC transport stub for SP.
##
## Placeholder for future ngtcp2/quiche FFI integration.
## QUIC maps multiplexed streams to SP peers.

{.experimental: "strict_funcs".}

import ../wire

# =====================================================================================================================
# Types (stub)
# =====================================================================================================================

type
  QuicConn* = ref object
    ## Placeholder QUIC connection.
    peer_proto*: uint16
    connected*: bool

  QuicListener* = ref object
    ## Placeholder QUIC listener.
    proto*: uint16

# =====================================================================================================================
# Stub implementations
# =====================================================================================================================

proc quic_dial*(host: string, port: int, proto: uint16): QuicConn {.raises: [SpError].} =
  ## Stub: QUIC dial not yet implemented.
  raise newException(SpError, "QUIC transport not yet implemented (requires ngtcp2/quiche FFI)")

proc quic_listen*(port: int, proto: uint16): QuicListener {.raises: [SpError].} =
  ## Stub: QUIC listen not yet implemented.
  raise newException(SpError, "QUIC transport not yet implemented (requires ngtcp2/quiche FFI)")

proc close*(conn: QuicConn) {.raises: [].} =
  discard

proc close*(listener: QuicListener) {.raises: [].} =
  discard
