## pubsub.nim -- PUB/SUB pattern: topic-based fan-out.
##
## PUB: send to all connected subscribers.
## SUB: subscribe with topic prefix filter; recv only matching messages.

{.experimental: "strict_funcs".}

import std/strutils
import basis/code/choice
import wire, socket

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpPub* = ref object
    sock: SpSocket

  SpSub* = ref object
    sock: SpSocket
    peer_id: PeerId
    filter: string  ## topic prefix filter; empty = receive all

# =====================================================================================================================
# PUB
# =====================================================================================================================

proc new_pub*(): SpPub =
  SpPub(sock: new_socket(spPub))

proc listen*(pub: SpPub, port: int): Choice[bool] =
  try:
    pub.sock.listen(port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc accept*(pub: SpPub): Choice[bool] =
  try:
    discard pub.sock.accept_peer()
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc publish*(pub: SpPub, data: string): Choice[bool] =
  ## Send data to all connected subscribers.
  try:
    pub.sock.send_all(data)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc close*(pub: SpPub) =
  if pub != nil and pub.sock != nil:
    socket.close(pub.sock)

# =====================================================================================================================
# SUB
# =====================================================================================================================

proc new_sub*(filter: string = ""): SpSub =
  SpSub(sock: new_socket(spSub), peer_id: 0, filter: filter)

proc connect*(sub: SpSub, host: string, port: int): Choice[bool] =
  try:
    sub.peer_id = sub.sock.connect(host, port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc set_filter*(sub: SpSub, filter: string) =
  sub.filter = filter

proc recv*(sub: SpSub): Choice[string] =
  ## Receive the next message matching the subscription filter.
  ## Blocks until a matching message arrives.
  while true:
    try:
      let (_, data) = sub.sock.recv_any()
      if sub.filter.len == 0 or data.startsWith(sub.filter):
        return good(data)
      # Non-matching message: discard, read next
    except SpError as e:
      return bad[string]("sp", e.msg)

proc close*(sub: SpSub) =
  if sub != nil and sub.sock != nil:
    socket.close(sub.sock)
