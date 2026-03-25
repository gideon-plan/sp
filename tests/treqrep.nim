## treqrep.nim -- REQ/REP pattern integration tests.

{.experimental: "strict_funcs".}

import std/[unittest, os]
import basis/code/choice
import hydra/[reqrep]

when not declared(reqrep_port):
  const reqrep_port = 41010

var g_rep: SpRep

proc rep_server_thread() {.thread.} =
  {.gcsafe.}:
    g_rep = new_rep()
    discard g_rep.listen(reqrep_port)
    discard g_rep.accept()
    # Handle 3 requests
    for i in 0 ..< 3:
      let r = g_rep.recv_request()
      if r.is_good:
        let (rid, payload) = r.val
        discard g_rep.send_reply(rid, "reply:" & payload)

suite "REQREP":
  test "single request-reply":
    var t: Thread[void]
    createThread(t, rep_server_thread)
    sleep(200)

    let req = new_req()
    let cr = req.connect("127.0.0.1", reqrep_port)
    check cr.is_good

    let r = req.request("hello")
    check r.is_good
    check r.val == "reply:hello"

    close(req)
    joinThread(t)
    close(g_rep)

  test "multiple requests":
    var t: Thread[void]
    # Need fresh server for new test
    createThread(t, rep_server_thread)
    sleep(200)

    let req = new_req()
    let cr = req.connect("127.0.0.1", reqrep_port)
    check cr.is_good

    for i in 0 ..< 3:
      let r = req.request("msg" & $i)
      check r.is_good
      check r.val == "reply:msg" & $i

    close(req)
    joinThread(t)
    close(g_rep)
