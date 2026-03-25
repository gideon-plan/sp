## shm.nim -- Shared memory inproc transport for SP.
##
## Ring buffer between threads, no syscalls. Uses atomicArc for safe sharing.

{.experimental: "strict_funcs".}

import std/[atomics, locks]
import ../wire

# =====================================================================================================================
# Ring buffer
# =====================================================================================================================

const ShmBufSize* = 65536  ## Default ring buffer size

type
  ShmRing* = ref object
    buf: seq[uint8]
    capacity: int
    head: int         ## Write position
    tail: int         ## Read position
    lock: Lock
    not_empty: Cond
    not_full: Cond
    closed: Atomic[bool]

proc new_shm_ring*(capacity: int = ShmBufSize): ShmRing =
  result = ShmRing(buf: newSeq[uint8](capacity), capacity: capacity)
  initLock(result.lock)
  initCond(result.not_empty)
  initCond(result.not_full)
  result.closed.store(false)

proc available(ring: ShmRing): int =
  if ring.head >= ring.tail:
    ring.head - ring.tail
  else:
    ring.capacity - ring.tail + ring.head

proc free_space(ring: ShmRing): int =
  ring.capacity - 1 - available(ring)

proc write*(ring: ShmRing, data: string) {.raises: [SpError].} =
  ## Write data to ring buffer. Blocks if full.
  if ring.closed.load:
    raise newException(SpError, "shm: channel closed")
  acquire(ring.lock)
  for i in 0 ..< data.len:
    while free_space(ring) == 0:
      if ring.closed.load:
        release(ring.lock)
        raise newException(SpError, "shm: channel closed")
      wait(ring.not_full, ring.lock)
    ring.buf[ring.head] = uint8(data[i])
    ring.head = (ring.head + 1) mod ring.capacity
  signal(ring.not_empty)
  release(ring.lock)

proc read*(ring: ShmRing, n: int): string {.raises: [SpError].} =
  ## Read n bytes from ring buffer. Blocks if empty.
  result = newString(n)
  acquire(ring.lock)
  for i in 0 ..< n:
    while available(ring) == 0:
      if ring.closed.load:
        release(ring.lock)
        raise newException(SpError, "shm: channel closed")
      wait(ring.not_empty, ring.lock)
    result[i] = char(ring.buf[ring.tail])
    ring.tail = (ring.tail + 1) mod ring.capacity
  signal(ring.not_full)
  release(ring.lock)

proc close_ring*(ring: ShmRing) =
  ring.closed.store(true)
  acquire(ring.lock)
  signal(ring.not_empty)
  signal(ring.not_full)
  release(ring.lock)

# =====================================================================================================================
# Shared memory SP connection
# =====================================================================================================================

type
  ShmConn* = ref object
    ## Bidirectional shared memory connection.
    tx*: ShmRing   ## Write ring (our send -> peer recv)
    rx*: ShmRing   ## Read ring (peer send -> our recv)
    peer_proto*: uint16

proc shm_send*(conn: ShmConn, data: string) {.raises: [SpError].} =
  conn.tx.write(data)

proc shm_recv*(conn: ShmConn, n: int): string {.raises: [SpError].} =
  conn.rx.read(n)

proc send_frame*(conn: ShmConn, frame: SpFrame) {.raises: [SpError].} =
  shm_send(conn, encode_frame(frame))

proc recv_frame*(conn: ShmConn): SpFrame {.raises: [SpError].} =
  let size_buf = shm_recv(conn, 8)
  var pos = 0
  let size = int(decode_size(size_buf, pos))
  if size > 0:
    let body = shm_recv(conn, size)
    SpFrame(header: "", payload: body)
  else:
    SpFrame(header: "", payload: "")

proc close*(conn: ShmConn) =
  if conn != nil:
    if conn.tx != nil: close_ring(conn.tx)
    if conn.rx != nil: close_ring(conn.rx)

# =====================================================================================================================
# Channel pair creation
# =====================================================================================================================

proc new_shm_pair*(capacity: int = ShmBufSize): (ShmConn, ShmConn) =
  ## Create a bidirectional shared memory channel pair.
  ## Returns (conn_a, conn_b) where a's tx is b's rx and vice versa.
  let ring_ab = new_shm_ring(capacity)
  let ring_ba = new_shm_ring(capacity)
  let a = ShmConn(tx: ring_ab, rx: ring_ba)
  let b = ShmConn(tx: ring_ba, rx: ring_ab)
  (a, b)
