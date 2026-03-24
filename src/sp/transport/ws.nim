## ws.nim -- WebSocket transport for SP.
##
## Pure Nim WebSocket frame codec + HTTP upgrade. SP frames wrapped in WS binary frames.

{.experimental: "strict_funcs".}

import std/[net, strutils, base64, sha1]
import ../wire
import ../transport

# =====================================================================================================================
# WebSocket frame codec
# =====================================================================================================================

const
  wsOpBinary = 0x02'u8
  wsOpClose  = 0x08'u8
  wsFinBit   = 0x80'u8

proc encode_ws_frame*(payload: string, masked: bool = false): string =
  ## Encode a WebSocket binary frame.
  var frame = ""
  frame.add(char(wsFinBit or wsOpBinary))
  let mask_bit = if masked: 0x80'u8 else: 0x00'u8
  if payload.len < 126:
    frame.add(char(mask_bit or uint8(payload.len)))
  elif payload.len < 65536:
    frame.add(char(mask_bit or 126'u8))
    frame.add(char((payload.len shr 8) and 0xFF))
    frame.add(char(payload.len and 0xFF))
  else:
    frame.add(char(mask_bit or 127'u8))
    for i in countdown(7, 0):
      frame.add(char((payload.len shr (i * 8)) and 0xFF))
  if masked:
    # Simple mask key
    frame.add("\x01\x02\x03\x04")
    for i, c in payload:
      frame.add(char(uint8(c) xor uint8(frame[frame.len - 4 + (i mod 4)])))
  else:
    frame.add(payload)
  frame

proc ws_handshake_request*(host: string, path: string = "/"): string =
  ## Generate WebSocket upgrade request.
  let key = encode("sp-websocket-key-0123")  # Simplified; production should use random
  "GET " & path & " HTTP/1.1\r\n" &
  "Host: " & host & "\r\n" &
  "Upgrade: websocket\r\n" &
  "Connection: Upgrade\r\n" &
  "Sec-WebSocket-Key: " & key & "\r\n" &
  "Sec-WebSocket-Version: 13\r\n" &
  "Sec-WebSocket-Protocol: sp\r\n" &
  "\r\n"

proc ws_handshake_response*(accept_key: string): string =
  ## Generate WebSocket upgrade response.
  "HTTP/1.1 101 Switching Protocols\r\n" &
  "Upgrade: websocket\r\n" &
  "Connection: Upgrade\r\n" &
  "Sec-WebSocket-Accept: " & accept_key & "\r\n" &
  "Sec-WebSocket-Protocol: sp\r\n" &
  "\r\n"

proc compute_accept_key*(client_key: string): string =
  ## Compute Sec-WebSocket-Accept from client key.
  let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  let combined = client_key & magic
  encode($secureHash(combined))

# =====================================================================================================================
# WebSocket SP connection
# =====================================================================================================================

type
  WsConn* = ref object
    sock*: Socket
    peer_proto*: uint16
    is_client*: bool

proc ws_send*(conn: WsConn, data: string) {.raises: [SpError].} =
  let frame = encode_ws_frame(data, conn.is_client)
  try:
    conn.sock.send(frame)
  except CatchableError as e:
    raise newException(SpError, "ws send: " & e.msg)

proc ws_recv_raw(sock: Socket, n: int): string {.raises: [SpError].} =
  result = ""
  while result.len < n:
    let buf = try:
      sock.recv(n - result.len)
    except CatchableError as e:
      raise newException(SpError, "ws recv: " & e.msg)
    if buf.len == 0:
      raise newException(SpError, "ws: connection closed")
    result.add(buf)

proc ws_recv*(conn: WsConn): string {.raises: [SpError].} =
  ## Read one WebSocket frame and return payload.
  let header = ws_recv_raw(conn.sock, 2)
  let payload_len_byte = uint8(header[1]) and 0x7F
  let masked = (uint8(header[1]) and 0x80) != 0
  var payload_len: int
  if payload_len_byte < 126:
    payload_len = int(payload_len_byte)
  elif payload_len_byte == 126:
    let ext = ws_recv_raw(conn.sock, 2)
    payload_len = int(uint8(ext[0])) shl 8 or int(uint8(ext[1]))
  else:
    let ext = ws_recv_raw(conn.sock, 8)
    payload_len = 0
    for i in 0 ..< 8:
      payload_len = payload_len shl 8 or int(uint8(ext[i]))
  var mask_key = ""
  if masked:
    mask_key = ws_recv_raw(conn.sock, 4)
  var payload = ws_recv_raw(conn.sock, payload_len)
  if masked:
    for i in 0 ..< payload.len:
      payload[i] = char(uint8(payload[i]) xor uint8(mask_key[i mod 4]))
  payload

proc send_sp_frame*(conn: WsConn, frame: SpFrame) {.raises: [SpError].} =
  ws_send(conn, encode_frame(frame))

proc recv_sp_frame*(conn: WsConn): SpFrame {.raises: [SpError].} =
  let data = ws_recv(conn)
  var pos = 0
  decode_frame(data, pos)

proc close*(conn: WsConn) {.raises: [].} =
  if conn != nil and conn.sock != nil:
    try: conn.sock.close() except CatchableError: discard
