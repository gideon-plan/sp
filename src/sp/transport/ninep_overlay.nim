## ninep_overlay.nim -- SP endpoints as 9P files.
##
## Exposes SP send/recv as write/read on 9P file descriptors.
## Basic overlay: write to /sp/send, read from /sp/recv.

{.experimental: "strict_funcs".}

import ../wire

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  NinepWriteFn* = proc(path: string, data: string) {.raises: [SpError].}
    ## Write data to a 9P file path.

  NinepReadFn* = proc(path: string, n: int): string {.raises: [SpError].}
    ## Read n bytes from a 9P file path.

  NinepOverlayConfig* = object
    host*: string
    port*: int
    root*: string  ## 9P root path for SP files

  NinepOverlayConn* = ref object
    config*: NinepOverlayConfig
    send_path*: string
    recv_path*: string
    write_fn*: NinepWriteFn
    read_fn*: NinepReadFn

# =====================================================================================================================
# Configuration
# =====================================================================================================================

proc default_ninep_config*(host: string = "localhost", port: int = 564,
                           root: string = "/sp"): NinepOverlayConfig =
  NinepOverlayConfig(host: host, port: port, root: root)

proc new_ninep_overlay*(config: NinepOverlayConfig, pattern: string, id: string,
                        write_fn: NinepWriteFn, read_fn: NinepReadFn
                       ): NinepOverlayConn =
  let base = config.root & "/" & pattern & "/" & id
  NinepOverlayConn(config: config, send_path: base & "/send",
                   recv_path: base & "/recv",
                   write_fn: write_fn, read_fn: read_fn)

# =====================================================================================================================
# Send / Recv
# =====================================================================================================================

proc overlay_send*(conn: NinepOverlayConn, data: string) {.raises: [SpError].} =
  conn.write_fn(conn.send_path, data)

proc overlay_recv*(conn: NinepOverlayConn, n: int): string {.raises: [SpError].} =
  conn.read_fn(conn.recv_path, n)

proc send_frame*(conn: NinepOverlayConn, frame: SpFrame) {.raises: [SpError].} =
  overlay_send(conn, encode_frame(frame))

proc recv_frame*(conn: NinepOverlayConn): SpFrame {.raises: [SpError].} =
  let size_buf = overlay_recv(conn, 8)
  var pos = 0
  let size = int(decode_size(size_buf, pos))
  if size > 0:
    let body = overlay_recv(conn, size)
    SpFrame(header: "", payload: body)
  else:
    SpFrame(header: "", payload: "")

proc close*(conn: NinepOverlayConn) {.raises: [].} =
  discard
