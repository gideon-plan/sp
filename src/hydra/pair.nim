## pair.nim -- PAIR pattern: bidirectional 1:1.
##
## Exactly one peer. Send and recv are symmetric.

{.experimental: "strict_funcs".}

import wire, socket
import basis/code/choice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpPair* = ref object
    sock: SpSocket
    peer_id: PeerId

# =====================================================================================================================
# Constructor
# =====================================================================================================================

proc new_pair*(): SpPair =
  SpPair(sock: new_socket(spPair), peer_id: 0)

proc connect*(pair: SpPair, host: string, port: int): Choice[bool] =
  try:
    pair.peer_id = pair.sock.connect(host, port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc listen*(pair: SpPair, port: int): Choice[bool] =
  try:
    pair.sock.listen(port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc accept*(pair: SpPair): Choice[bool] =
  try:
    pair.peer_id = pair.sock.accept_peer()
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc send*(pair: SpPair, data: string): Choice[bool] =
  try:
    pair.sock.send_to(pair.peer_id, data)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc recv*(pair: SpPair): Choice[string] =
  try:
    let (_, data) = pair.sock.recv_any()
    good(data)
  except SpError as e:
    bad[string]("sp", e.msg)

proc close*(pair: SpPair) =
  if pair != nil and pair.sock != nil:
    socket.close(pair.sock)
