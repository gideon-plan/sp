## tpair.nim -- PAIR pattern integration tests.

{.experimental: "strict_funcs".}

import std/[unittest, os]
import basis/code/choice
import hydra/[pair]

when not declared(pair_port):
  const pair_port = 41000

var g_pair_server: SpPair

proc pair_server_thread() {.thread.} =
  {.gcsafe.}:
    g_pair_server = new_pair()
    discard g_pair_server.listen(pair_port)
    discard g_pair_server.accept()
    # Echo back what we receive
    let r = g_pair_server.recv()
    if r.is_good:
      discard g_pair_server.send(r.val)

suite "PAIR":
  test "bidirectional send/recv":
    var t: Thread[void]
    createThread(t, pair_server_thread)
    sleep(200)

    let client = new_pair()
    let cr = client.connect("127.0.0.1", pair_port)
    check cr.is_good

    let sr = client.send("ping")
    check sr.is_good

    let rr = client.recv()
    check rr.is_good
    check rr.val == "ping"

    close(client)
    joinThread(t)
    close(g_pair_server)
