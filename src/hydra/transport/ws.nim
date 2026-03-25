## ws.nim -- WebSocket transport for SP.
##
## Uses httpd/server/websocket for frame codec. SP frames wrapped in WS binary frames.

{.experimental: "strict_funcs".}

import std/[net, strutils, base64]
import ../wire
import ../transport
import httpd/server/websocket

# =====================================================================================================================
# WebSocket handshake
# =====================================================================================================================

proc ws_handshake_request*(host: string, path: string = "/"): string =
  let key = encode("sp-websocket-key-0123")
  "GET " & path & " HTTP/1.1\r\n" &
  "Host: " & host & "\r\n" &
  "Upgrade: websocket\r\n" &
  "Connection: Upgrade\r\n" &
  "Sec-WebSocket-Key: " & key & "\r\n" &
  "Sec-WebSocket-Version: 13\r\n" &
  "Sec-WebSocket-Protocol: sp\r\n" &
  "\r\n"

proc ws_handshake_response*(client_key: string): string =
  let ak = accept_key(client_key)
  "HTTP/1.1 101 Switching Protocols\r\n" &
  "Upgrade: websocket\r\n" &
  "Connection: Upgrade\r\n" &
  "Sec-WebSocket-Accept: " & ak & "\r\n" &
  "Sec-WebSocket-Protocol: sp\r\n" &
  "\r\n"

# =====================================================================================================================
# WebSocket SP connection
# =====================================================================================================================

type
  WsConn* = ref object
    sock*: Socket
    peer_proto*: uint16
    is_client*: bool

proc ws_send*(conn: WsConn, data: string) {.raises: [SpError].} =
  ## Send data as a WebSocket binary frame using httpd codec.
  var payload: seq[byte] = @[]
  for c in data: payload.add(byte(c))
  let frame = encode_frame(wsBinary, payload)
  var frame_str = ""
  for b in frame: frame_str.add(char(b))
  try:
    conn.sock.send(frame_str)
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
  ## Read one WebSocket frame using httpd decoder and return payload.
  # Read initial 2 bytes to determine frame size
  let header = ws_recv_raw(conn.sock, 2)
  let payload_len_byte = uint8(header[1]) and 0x7F
  let masked = (uint8(header[1]) and 0x80) != 0
  var extra_needed = 0
  if payload_len_byte == 126: extra_needed = 2
  elif payload_len_byte == 127: extra_needed = 8
  if masked: extra_needed += 4

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
  ws_send(conn, wire.encode_frame(frame))

proc recv_sp_frame*(conn: WsConn): SpFrame {.raises: [SpError].} =
  let data = ws_recv(conn)
  var pos = 0
  wire.decode_frame(data, pos)

proc close*(conn: WsConn) {.raises: [].} =
  if conn != nil and conn.sock != nil:
    try: conn.sock.close() except CatchableError: discard
