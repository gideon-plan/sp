## valkey_overlay.nim -- SP patterns over Valkey streams and channels.
##
## PIPELINE: Valkey streams with XREADGROUP consumer groups.
## PUBSUB: Valkey pub/sub channels.
## Requires a Valkey 7.x server.

{.experimental: "strict_funcs".}

import ../wire

# =====================================================================================================================
# Configuration
# =====================================================================================================================

type
  ValkeyOverlayConfig* = object
    host*: string
    port*: int
    stream_prefix*: string

  ValkeyMapping* = object
    stream_key*: string      ## For PIPELINE (Valkey stream)
    channel_name*: string    ## For PUBSUB (Valkey pub/sub channel)
    consumer_group*: string  ## For PIPELINE consumer group

proc default_valkey_config*(host: string = "localhost", port: int = 6379,
                            prefix: string = "sp"): ValkeyOverlayConfig =
  ValkeyOverlayConfig(host: host, port: port, stream_prefix: prefix)

proc map_pipeline*(config: ValkeyOverlayConfig, queue: string,
                   group: string = "sp_workers"): ValkeyMapping =
  ## PIPELINE: PUSH writes to stream, PULL does XREADGROUP.
  ValkeyMapping(
    stream_key: config.stream_prefix & ":pipeline:" & queue,
    consumer_group: group)

proc map_pubsub*(config: ValkeyOverlayConfig, channel: string): ValkeyMapping =
  ## PUBSUB: Valkey pub/sub channel.
  ValkeyMapping(channel_name: config.stream_prefix & ":pubsub:" & channel)

proc map_bus*(config: ValkeyOverlayConfig, mesh: string): ValkeyMapping =
  ## BUS: all-to-all via Valkey pub/sub.
  ValkeyMapping(channel_name: config.stream_prefix & ":bus:" & mesh)

# =====================================================================================================================
# Connection types (abstract -- actual Valkey I/O delegates to valkey satellite)
# =====================================================================================================================

type
  ValkeySendFn* = proc(key: string, data: string) {.raises: [SpError].}
  ValkeyRecvFn* = proc(key: string): string {.raises: [SpError].}

  ValkeyOverlayConn* = ref object
    config*: ValkeyOverlayConfig
    mapping*: ValkeyMapping
    send_fn*: ValkeySendFn
    recv_fn*: ValkeyRecvFn

proc overlay_send*(conn: ValkeyOverlayConn, data: string) {.raises: [SpError].} =
  let key = if conn.mapping.stream_key.len > 0: conn.mapping.stream_key
            else: conn.mapping.channel_name
  conn.send_fn(key, data)

proc overlay_recv*(conn: ValkeyOverlayConn): string {.raises: [SpError].} =
  let key = if conn.mapping.stream_key.len > 0: conn.mapping.stream_key
            else: conn.mapping.channel_name
  conn.recv_fn(key)

proc close*(conn: ValkeyOverlayConn) {.raises: [].} =
  discard
