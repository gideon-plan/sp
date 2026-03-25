## tshm.nim -- Tests for shared memory inproc transport.

{.experimental: "strict_funcs".}

import std/unittest
import hydra/wire
import hydra/transport/shm

suite "shm ring buffer":
  test "write and read":
    let ring = new_shm_ring(256)
    ring.write("hello")
    let data = ring.read(5)
    check data == "hello"

  test "write and read multiple":
    let ring = new_shm_ring(256)
    ring.write("abc")
    ring.write("def")
    check ring.read(3) == "abc"
    check ring.read(3) == "def"

  test "wrap around":
    let ring = new_shm_ring(16)
    ring.write("12345678")
    discard ring.read(8)
    ring.write("abcdefgh")
    check ring.read(8) == "abcdefgh"

suite "shm pair":
  test "bidirectional send/recv":
    let (a, b) = new_shm_pair()
    shm_send(a, "from a")
    check shm_recv(b, 6) == "from a"
    shm_send(b, "from b")
    check shm_recv(a, 6) == "from b"
    close(a)
    close(b)

  test "SP frame round-trip":
    let (a, b) = new_shm_pair()
    let frame = SpFrame(header: "", payload: "test payload")
    send_frame(a, frame)
    let received = recv_frame(b)
    check received.payload == "test payload"
    close(a)
    close(b)

var g_a {.global.}: ShmConn
var g_b {.global.}: ShmConn

proc writer_thread() {.thread.} =
  {.gcsafe.}:
    for i in 0 ..< 10:
      send_frame(g_a, SpFrame(header: "", payload: "msg" & $i))

suite "shm threaded":
  test "threaded send/recv":
    let (a, b) = new_shm_pair()
    g_a = a
    g_b = b
    var t: Thread[void]
    createThread(t, writer_thread)
    for i in 0 ..< 10:
      let f = recv_frame(g_b)
      check f.payload == "msg" & $i
    joinThread(t)
    close(g_a)
    close(g_b)
