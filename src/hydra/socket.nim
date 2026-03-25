## socket.nim -- SP socket abstraction.
##
## Wraps transport connections with protocol enforcement, peer management,
## and pattern-agnostic send/recv. Under atomicArc, SpSocket is a ref object.

{.experimental: "strict_funcs".}

import std/[locks, tables]
import wire, transport

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  PeerId* = int

  SpSocket* = ref object
    proto*: uint16
    lock*: Lock
    peers*: Table[PeerId, SpConn]
    next_id: int
    listener*: SpListener
    rr_index: int

# =====================================================================================================================
# Constructor
# =====================================================================================================================

proc new_socket*(proto: uint16): SpSocket =
  result = SpSocket(proto: proto, peers: initTable[PeerId, SpConn](), next_id: 1, rr_index: 0)
  initLock(result.lock)

# =====================================================================================================================
# Peer management
# =====================================================================================================================

proc add_peer*(sock: SpSocket, conn: SpConn): PeerId =
  acquire(sock.lock)
  let id = sock.next_id
  inc sock.next_id
  sock.peers[id] = conn
  release(sock.lock)
  return id

proc remove_peer*(sock: SpSocket, id: PeerId) =
  acquire(sock.lock)
  if id in sock.peers:
    try: close(sock.peers[id]) except CatchableError: discard
    sock.peers.del(id)
  release(sock.lock)

proc peer_count*(sock: SpSocket): int =
  acquire(sock.lock)
  result = sock.peers.len
  release(sock.lock)

# =====================================================================================================================
# Connect / Bind
# =====================================================================================================================

proc connect*(sock: SpSocket, host: string, port: int): PeerId {.raises: [SpError].} =
  let conn = tcp_dial(host, port, sock.proto)
  return sock.add_peer(conn)

proc connect_ipc*(sock: SpSocket, path: string): PeerId {.raises: [SpError].} =
  let conn = ipc_dial(path, sock.proto)
  return sock.add_peer(conn)

proc listen*(sock: SpSocket, port: int) {.raises: [SpError].} =
  sock.listener = tcp_listen(port, sock.proto)

proc listen_ipc*(sock: SpSocket, path: string) {.raises: [SpError].} =
  sock.listener = ipc_listen(path, sock.proto)

proc accept_peer*(sock: SpSocket): PeerId {.raises: [SpError].} =
  if sock.listener == nil:
    raise newException(SpError, "not listening")
  let conn = accept(sock.listener)
  return sock.add_peer(conn)

# =====================================================================================================================
# Send / Recv
# =====================================================================================================================

proc send_to*(sock: SpSocket, peer_id: PeerId, data: string) {.raises: [SpError].} =
  acquire(sock.lock)
  let conn = try:
    sock.peers[peer_id]
  except KeyError:
    release(sock.lock)
    raise newException(SpError, "unknown peer: " & $peer_id)
  release(sock.lock)
  send_frame(conn, SpFrame(header: "", payload: data))

proc recv_from*(sock: SpSocket, peer_id: PeerId): string {.raises: [SpError].} =
  acquire(sock.lock)
  let conn = try:
    sock.peers[peer_id]
  except KeyError:
    release(sock.lock)
    raise newException(SpError, "unknown peer: " & $peer_id)
  release(sock.lock)
  let frame = recv_frame(conn)
  return frame.payload

proc send_round_robin*(sock: SpSocket, data: string) {.raises: [SpError].} =
  acquire(sock.lock)
  if sock.peers.len == 0:
    release(sock.lock)
    raise newException(SpError, "no peers connected")
  var ids: seq[PeerId] = @[]
  for id in sock.peers.keys:
    ids.add(id)
  let idx = sock.rr_index mod ids.len
  sock.rr_index = idx + 1
  let conn = try:
    sock.peers[ids[idx]]
  except KeyError:
    release(sock.lock)
    raise newException(SpError, "peer disappeared during round-robin")
  release(sock.lock)
  send_frame(conn, SpFrame(header: "", payload: data))

proc send_all*(sock: SpSocket, data: string) {.raises: [SpError].} =
  acquire(sock.lock)
  var conns: seq[SpConn] = @[]
  for conn in sock.peers.values:
    conns.add(conn)
  release(sock.lock)
  for conn in conns:
    send_frame(conn, SpFrame(header: "", payload: data))

proc recv_any*(sock: SpSocket): (PeerId, string) {.raises: [SpError].} =
  acquire(sock.lock)
  if sock.peers.len == 0:
    release(sock.lock)
    raise newException(SpError, "no peers connected")
  var first_id: PeerId = 0
  for id in sock.peers.keys:
    first_id = id
    break
  let conn = try:
    sock.peers[first_id]
  except KeyError:
    release(sock.lock)
    raise newException(SpError, "peer disappeared")
  release(sock.lock)
  let frame = recv_frame(conn)
  return (first_id, frame.payload)

# =====================================================================================================================
# Close
# =====================================================================================================================

proc close*(sock: SpSocket) {.raises: [].} =
  if sock == nil: return
  acquire(sock.lock)
  for conn in sock.peers.values:
    transport.close(conn)
  sock.peers.clear()
  release(sock.lock)
  if sock.listener != nil:
    transport.close(sock.listener)
  deinitLock(sock.lock)
