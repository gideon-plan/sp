## tls.nim -- TLS over TCP transport for SP.
##
## Wraps existing TCP transport with std/net SSL context.

{.experimental: "strict_funcs".}

import std/net
import ../wire
import ../transport

# =====================================================================================================================
# TLS dial/listen
# =====================================================================================================================

proc tls_dial*(host: string, port: int, proto: uint16,
               cert_file: string = "", key_file: string = ""
              ): SpConn {.raises: [SpError].} =
  ## Connect to a TLS endpoint and perform SP handshake.
  result = SpConn(kind: tkTcp)  # TLS uses TCP underneath
  try:
    let ctx = newContext(verifyMode = CVerifyNone)
    result.sock = newSocket()
    ctx.wrapSocket(result.sock)
    result.sock.connect(host, Port(port))
  except CatchableError as e:
    raise newException(SpError, "tls dial: " & e.msg)
  do_handshake(result, proto)

proc tls_listen*(port: int, proto: uint16,
                 cert_file: string, key_file: string
                ): SpListener {.raises: [SpError].} =
  ## Bind and listen on a TLS port.
  result = SpListener(kind: tkTcp, proto: proto)
  try:
    let ctx = newContext(certFile = cert_file, keyFile = key_file)
    result.sock = newSocket()
    result.sock.setSockOpt(OptReuseAddr, true)
    result.sock.bindAddr(Port(port))
    result.sock.listen()
    ctx.wrapSocket(result.sock)
  except CatchableError as e:
    raise newException(SpError, "tls listen: " & e.msg)

proc tls_accept*(listener: SpListener): SpConn {.raises: [SpError].} =
  ## Accept a TLS connection. Delegates to standard accept (SSL wrapped).
  accept(listener)
