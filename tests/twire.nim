## twire.nim -- Wire format unit tests.

{.experimental: "strict_funcs".}

import std/unittest
import hydra/wire

suite "wire format":
  test "encode/decode size 0":
    let enc = encode_size(0)
    check enc.len == 8
    var pos = 0
    check decode_size(enc, pos) == 0'u64

  test "encode/decode size 256":
    let enc = encode_size(256)
    var pos = 0
    check decode_size(enc, pos) == 256'u64

  test "encode/decode large size":
    let enc = encode_size(0xFFFFFFFF'u64)
    var pos = 0
    check decode_size(enc, pos) == 0xFFFFFFFF'u64

  test "frame round-trip":
    let frame = SpFrame(header: "", payload: "hello sp")
    let encoded = encode_frame(frame)
    var pos = 0
    let decoded = decode_frame(encoded, pos)
    check decoded.payload == "hello sp"

  test "frame empty payload":
    let frame = SpFrame(header: "", payload: "")
    let encoded = encode_frame(frame)
    var pos = 0
    let decoded = decode_frame(encoded, pos)
    check decoded.payload == ""

  test "handshake round-trip PAIR":
    let enc = encode_handshake(spPair)
    check enc.len == 8
    var pos = 0
    let proto = decode_handshake(enc, pos)
    check proto == spPair

  test "handshake round-trip REQ":
    let enc = encode_handshake(spReq)
    var pos = 0
    let proto = decode_handshake(enc, pos)
    check proto == spReq

  test "handshake invalid magic":
    let bad = "\x00XX\x00\x00\x10\x00\x00"
    var pos = 0
    expect SpError:
      discard decode_handshake(bad, pos)

  test "peer protocol mapping":
    check peer_protocol(spReq) == spRep
    check peer_protocol(spRep) == spReq
    check peer_protocol(spPub) == spSub
    check peer_protocol(spSub) == spPub
    check peer_protocol(spPush) == spPull
    check peer_protocol(spPull) == spPush
    check peer_protocol(spSurveyor) == spRespondent
    check peer_protocol(spRespondent) == spSurveyor
    check peer_protocol(spPair) == spPair
    check peer_protocol(spBus) == spBus

  test "multi-frame decode":
    let f1 = encode_frame(SpFrame(header: "", payload: "one"))
    let f2 = encode_frame(SpFrame(header: "", payload: "two"))
    let buf = f1 & f2
    var pos = 0
    let d1 = decode_frame(buf, pos)
    check d1.payload == "one"
    let d2 = decode_frame(buf, pos)
    check d2.payload == "two"
    check pos == buf.len
