## pipeline.nim -- PUSH/PULL pattern: load-balanced work distribution.
##
## PUSH: send to one of N connected PULLs (round-robin).
## PULL: recv from any connected PUSH.

{.experimental: "strict_funcs".}

import wire, socket
import basis/code/choice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpPush* = ref object
    sock: SpSocket

  SpPull* = ref object
    sock: SpSocket

# =====================================================================================================================
# PUSH
# =====================================================================================================================

proc new_push*(): SpPush =
  SpPush(sock: new_socket(spPush))

proc connect*(push: SpPush, host: string, port: int): Choice[bool] =
  try:
    discard push.sock.connect(host, port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc listen*(push: SpPush, port: int): Choice[bool] =
  try:
    push.sock.listen(port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc accept*(push: SpPush): Choice[bool] =
  try:
    discard push.sock.accept_peer()
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc send*(push: SpPush, data: string): Choice[bool] =
  ## Send data to the next PULL peer (round-robin).
  try:
    push.sock.send_round_robin(data)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc close*(push: SpPush) =
  if push != nil and push.sock != nil:
    socket.close(push.sock)

# =====================================================================================================================
# PULL
# =====================================================================================================================

proc new_pull*(): SpPull =
  SpPull(sock: new_socket(spPull))

proc connect*(pull: SpPull, host: string, port: int): Choice[bool] =
  try:
    discard pull.sock.connect(host, port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc listen*(pull: SpPull, port: int): Choice[bool] =
  try:
    pull.sock.listen(port)
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc accept*(pull: SpPull): Choice[bool] =
  try:
    discard pull.sock.accept_peer()
    good(true)
  except SpError as e:
    bad[bool]("sp", e.msg)

proc recv*(pull: SpPull): Choice[string] =
  try:
    let (_, data) = pull.sock.recv_any()
    good(data)
  except SpError as e:
    bad[string]("sp", e.msg)

proc close*(pull: SpPull) =
  if pull != nil and pull.sock != nil:
    socket.close(pull.sock)
