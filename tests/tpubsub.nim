## tpubsub.nim -- PUB/SUB pattern integration tests.

{.experimental: "strict_funcs".}

import std/[unittest, os, atomics]
import basis/code/choice
import hydra/[pubsub]

when not declared(pubsub_port):
  const pubsub_port = 41020

var g_pub: SpPub
var g_sub_count: Atomic[int]

proc pub_server_thread() {.thread.} =
  {.gcsafe.}:
    g_pub = new_pub()
    discard g_pub.listen(pubsub_port)
    discard g_pub.accept()
    sleep(100)
    # Publish 3 messages
    for i in 0 ..< 3:
      discard g_pub.publish("topic:" & $i)
      sleep(50)

suite "PUBSUB":
  test "subscribe and receive":
    var t: Thread[void]
    createThread(t, pub_server_thread)
    sleep(200)

    let sub = new_sub()
    let cr = sub.connect("127.0.0.1", pubsub_port)
    check cr.is_good

    var received: seq[string] = @[]
    for i in 0 ..< 3:
      let r = sub.recv()
      if r.is_good:
        received.add(r.val)

    check received.len == 3
    check received[0] == "topic:0"

    close(sub)
    joinThread(t)
    close(g_pub)

  test "subscribe with filter":
    var t: Thread[void]
    createThread(t, pub_server_thread)
    sleep(200)

    let sub = new_sub("topic:1")
    let cr = sub.connect("127.0.0.1", pubsub_port)
    check cr.is_good

    # Should skip topic:0, receive topic:1
    let r = sub.recv()
    check r.is_good
    check r.val == "topic:1"

    close(sub)
    joinThread(t)
    close(g_pub)
