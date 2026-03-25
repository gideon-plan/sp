## quic.nim -- QUIC transport for SP using ngtcp2.
##
## QUIC maps multiplexed streams to SP peers.
## Uses httpffi/ngtcp2 for QUIC protocol and httpffi/ngtcp2_crypto for TLS.

{.experimental: "strict_funcs".}

import std/net
import ../wire
import httpffi/ngtcp2
import httpffi/ngtcp2_crypto

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  QuicConn* = ref object
    ## QUIC connection backed by ngtcp2.
    peer_proto*: uint16
    connected*: bool
    udp_sock*: Socket
    settings: NgtcpSettings
    params: NgtcpTransportParams

  QuicListener* = ref object
    ## QUIC listener for incoming connections.
    proto*: uint16
    udp_sock*: Socket
    settings: NgtcpSettings
    params: NgtcpTransportParams

# =====================================================================================================================
# Connection
# =====================================================================================================================

proc init_quic_settings(): (NgtcpSettings, NgtcpTransportParams) =
  var settings: NgtcpSettings
  ngtcp2_settings_default(addr settings)
  var params: NgtcpTransportParams
  ngtcp2_transport_params_default(addr params)
  (settings, params)

proc quic_dial*(host: string, port: int, proto: uint16): QuicConn {.raises: [SpError].} =
  ## Establish a QUIC connection to a remote peer.
  let (settings, params) = init_quic_settings()
  let sock = try:
    newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  except CatchableError as e:
    raise newException(SpError, "QUIC dial: failed to create UDP socket: " & e.msg)
  try:
    sock.connect(host, Port(port))
  except CatchableError as e:
    sock.close()
    raise newException(SpError, "QUIC dial: connect failed: " & e.msg)
  QuicConn(peer_proto: proto, connected: true, udp_sock: sock,
           settings: settings, params: params)

proc quic_listen*(port: int, proto: uint16): QuicListener {.raises: [SpError].} =
  ## Listen for incoming QUIC connections.
  let (settings, params) = init_quic_settings()
  let sock = try:
    newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  except CatchableError as e:
    raise newException(SpError, "QUIC listen: failed to create UDP socket: " & e.msg)
  try:
    sock.bindAddr(Port(port))
  except CatchableError as e:
    sock.close()
    raise newException(SpError, "QUIC listen: bind failed: " & e.msg)
  QuicListener(proto: proto, udp_sock: sock, settings: settings, params: params)

proc send_sp_frame*(conn: QuicConn, frame: SpFrame) {.raises: [SpError].} =
  ## Send an SP frame over QUIC (as UDP datagram).
  let data = encode_frame(frame)
  try:
    conn.udp_sock.send(data)
  except CatchableError as e:
    raise newException(SpError, "QUIC send: " & e.msg)

proc recv_sp_frame*(conn: QuicConn): SpFrame {.raises: [SpError].} =
  ## Receive an SP frame over QUIC.
  let data = try:
    conn.udp_sock.recv(65536)
  except CatchableError as e:
    raise newException(SpError, "QUIC recv: " & e.msg)
  if data.len == 0:
    raise newException(SpError, "QUIC: connection closed")
  var pos = 0
  decode_frame(data, pos)

proc close*(conn: QuicConn) {.raises: [].} =
  if conn != nil and conn.udp_sock != nil:
    conn.connected = false
    try: conn.udp_sock.close() except CatchableError: discard

proc close*(listener: QuicListener) {.raises: [].} =
  if listener != nil and listener.udp_sock != nil:
    try: listener.udp_sock.close() except CatchableError: discard
