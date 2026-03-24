## registry.nim -- URL scheme-based transport selection.
##
## Parse endpoint URLs and dispatch to appropriate transport.
## Schemes: tcp://, ipc://, tls://, shm://, quic://, mqtt://, valkey://, ws://, 9p://

{.experimental: "strict_funcs".}

import std/strutils
import wire, transport

# =====================================================================================================================
# URL parsing
# =====================================================================================================================

type
  SpScheme* = enum
    ssTcp
    ssIpc
    ssTls
    ssShm
    ssQuic
    ssMqtt
    ssValkey
    ssWs
    ssNinep

  SpEndpoint* = object
    scheme*: SpScheme
    host*: string
    port*: int
    path*: string  ## For IPC path, SHM channel name, overlay prefix

proc parse_endpoint*(url: string): SpEndpoint {.raises: [SpError].} =
  ## Parse an SP endpoint URL.
  let sep = url.find("://")
  if sep < 0:
    raise newException(SpError, "invalid endpoint URL: missing scheme: " & url)
  let scheme_str = url[0 ..< sep].toLowerAscii()
  let rest = url[sep + 3 ..< url.len]
  let scheme = case scheme_str
    of "tcp": ssTcp
    of "ipc": ssIpc
    of "tls": ssTls
    of "shm": ssShm
    of "quic": ssQuic
    of "mqtt": ssMqtt
    of "valkey": ssValkey
    of "ws": ssWs
    of "9p": ssNinep
    else: raise newException(SpError, "unknown scheme: " & scheme_str)
  case scheme
  of ssIpc:
    SpEndpoint(scheme: scheme, path: rest)
  of ssShm:
    SpEndpoint(scheme: scheme, path: rest)
  else:
    # Parse host:port/path
    var host = ""
    var port = 0
    var path = ""
    let slash_pos = rest.find('/')
    let host_port = if slash_pos >= 0:
      path = rest[slash_pos ..< rest.len]
      rest[0 ..< slash_pos]
    else:
      rest
    let colon_pos = host_port.find(':')
    if colon_pos >= 0:
      host = host_port[0 ..< colon_pos]
      try:
        port = parseInt(host_port[colon_pos + 1 ..< host_port.len])
      except ValueError:
        raise newException(SpError, "invalid port in URL: " & url)
    else:
      host = host_port
      port = case scheme
        of ssTcp, ssTls: 0
        of ssQuic: 0
        of ssMqtt: 1883
        of ssValkey: 6379
        of ssWs: 80
        of ssNinep: 564
        else: 0
    SpEndpoint(scheme: scheme, host: host, port: port, path: path)

proc dial*(endpoint: SpEndpoint, proto: uint16): SpConn {.raises: [SpError].} =
  ## Dial a TCP or IPC endpoint. For other schemes, use scheme-specific functions.
  case endpoint.scheme
  of ssTcp:
    tcp_dial(endpoint.host, endpoint.port, proto)
  of ssIpc:
    ipc_dial(endpoint.path, proto)
  else:
    raise newException(SpError, "dial not supported for scheme: " & $endpoint.scheme &
                       " -- use scheme-specific dial function")

proc listen*(endpoint: SpEndpoint, proto: uint16): SpListener {.raises: [SpError].} =
  ## Listen on a TCP or IPC endpoint. For other schemes, use scheme-specific functions.
  case endpoint.scheme
  of ssTcp:
    tcp_listen(endpoint.port, proto)
  of ssIpc:
    ipc_listen(endpoint.path, proto)
  else:
    raise newException(SpError, "listen not supported for scheme: " & $endpoint.scheme &
                       " -- use scheme-specific listen function")

proc to_url*(ep: SpEndpoint): string =
  ## Reconstruct URL from endpoint.
  let scheme = case ep.scheme
    of ssTcp: "tcp"
    of ssIpc: "ipc"
    of ssTls: "tls"
    of ssShm: "shm"
    of ssQuic: "quic"
    of ssMqtt: "mqtt"
    of ssValkey: "valkey"
    of ssWs: "ws"
    of ssNinep: "9p"
  case ep.scheme
  of ssIpc, ssShm:
    scheme & "://" & ep.path
  else:
    var url = scheme & "://" & ep.host
    if ep.port > 0:
      url &= ":" & $ep.port
    if ep.path.len > 0:
      url &= ep.path
    url
