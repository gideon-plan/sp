## bus.nim -- BUS pattern: full mesh broadcast.
##
## Every node sees every message from every other node.
## Send broadcasts to all peers. Recv from any peer.

{.experimental: "strict_funcs".}

import wire, socket
import basis/code/choice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpBus* = ref object
    sock: SpSocket

# =====================================================================================================================
# BUS
# =====================================================================================================================

proc new_bus*(): SpBus =
  SpBus(sock: new_socket(spBus))

proc connect*(bus: SpBus, host: string, port: int): Choice[bool] =
  try:
    discard bus.sock.connect(host, port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc listen*(bus: SpBus, port: int): Choice[bool] =
  try:
    bus.sock.listen(port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc accept*(bus: SpBus): Choice[bool] =
  try:
    discard bus.sock.accept_peer()
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc send*(bus: SpBus, data: string): Choice[bool] =
  ## Broadcast data to all peers.
  try:
    bus.sock.send_all(data)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc recv*(bus: SpBus): Choice[string] =
  ## Receive from any peer.
  try:
    let (_, data) = bus.sock.recv_any()
    good(data)
  except SpError as e:
    bad[string]("sp", e.msg)

proc close*(bus: SpBus) =
  if bus != nil and bus.sock != nil:
    socket.close(bus.sock)
