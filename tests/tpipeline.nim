## tpipeline.nim -- PUSH/PULL pattern integration tests.

{.experimental: "strict_funcs".}

import std/[unittest, os]
import basis/code/choice
import hydra/[pipeline]

when not declared(pipeline_port):
  const pipeline_port = 41030

var g_pull: SpPull

proc pull_worker_thread() {.thread.} =
  {.gcsafe.}:
    g_pull = new_pull()
    discard g_pull.listen(pipeline_port)
    discard g_pull.accept()

suite "PIPELINE":
  test "push/pull single message":
    var t: Thread[void]
    createThread(t, pull_worker_thread)
    sleep(200)

    let push = new_push()
    let cr = push.connect("127.0.0.1", pipeline_port)
    check cr.is_good

    let sr = push.send("work item")
    check sr.is_good

    let rr = g_pull.recv()
    check rr.is_good
    check rr.val == "work item"

    close(push)
    joinThread(t)
    close(g_pull)

  test "push multiple items":
    var t: Thread[void]
    createThread(t, pull_worker_thread)
    sleep(200)

    let push = new_push()
    let cr = push.connect("127.0.0.1", pipeline_port)
    check cr.is_good

    for i in 0 ..< 5:
      let sr = push.send("item:" & $i)
      check sr.is_good

    for i in 0 ..< 5:
      let rr = g_pull.recv()
      check rr.is_good
      check rr.val == "item:" & $i

    close(push)
    joinThread(t)
    close(g_pull)
