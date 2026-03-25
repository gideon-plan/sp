## tbus.nim -- BUS pattern integration tests.

{.experimental: "strict_funcs".}

import std/[unittest, os]
import basis/code/choice
import hydra/[bus]

when not declared(bus_port):
  const bus_port = 41050

var g_bus_server: SpBus

proc bus_server_thread() {.thread.} =
  {.gcsafe.}:
    g_bus_server = new_bus()
    discard g_bus_server.listen(bus_port)
    discard g_bus_server.accept()

suite "BUS":
  test "two-node send/recv":
    var t: Thread[void]
    createThread(t, bus_server_thread)
    sleep(200)

    let client = new_bus()
    let cr = client.connect("127.0.0.1", bus_port)
    check cr.is_good
    sleep(100)

    # Client sends, server receives
    let sr = client.send("bus message")
    check sr.is_good

    let rr = g_bus_server.recv()
    check rr.is_good
    check rr.val == "bus message"

    close(client)
    joinThread(t)
    close(g_bus_server)
