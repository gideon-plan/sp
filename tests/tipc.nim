## tipc.nim -- IPC transport tests (Unix domain sockets).

{.experimental: "strict_funcs".}

import std/[unittest, os]
import hydra/[wire, socket, pair]

const ipc_path = "/tmp/sp_test.sock"

var g_ipc_server: SpPair

proc ipc_server_thread() {.thread.} =
  {.gcsafe.}:
    g_ipc_server = new_pair()
    let sock = new_socket(spPair)
    g_ipc_server = SpPair()  # reset
    # Use raw socket for IPC
    let listener_sock = new_socket(spPair)
    listener_sock.listen_ipc(ipc_path)
    let pid = listener_sock.accept_peer()
    # Echo back
    let (_, data) = listener_sock.recv_any()
    listener_sock.send_to(pid, data)
    socket.close(listener_sock)

suite "IPC transport":
  setup:
    removeFile(ipc_path)

  test "pair over IPC":
    var t: Thread[void]
    createThread(t, ipc_server_thread)
    sleep(200)

    let client_sock = new_socket(spPair)
    let pid = client_sock.connect_ipc(ipc_path)
    client_sock.send_to(pid, "ipc hello")
    let (_, data) = client_sock.recv_any()
    check data == "ipc hello"

    socket.close(client_sock)
    joinThread(t)
