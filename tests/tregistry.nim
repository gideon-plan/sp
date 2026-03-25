## tregistry.nim -- Tests for URL-based transport registry.

{.experimental: "strict_funcs".}

import std/unittest
import hydra/wire
import hydra/registry

suite "URL parsing":
  test "parse tcp URL":
    let ep = parse_endpoint("tcp://localhost:5555")
    check ep.scheme == ssTcp
    check ep.host == "localhost"
    check ep.port == 5555

  test "parse ipc URL":
    let ep = parse_endpoint("ipc:///tmp/sp.sock")
    check ep.scheme == ssIpc
    check ep.path == "/tmp/sp.sock"

  test "parse tls URL":
    let ep = parse_endpoint("tls://example.com:4433")
    check ep.scheme == ssTls
    check ep.host == "example.com"
    check ep.port == 4433

  test "parse shm URL":
    let ep = parse_endpoint("shm://channel_name")
    check ep.scheme == ssShm
    check ep.path == "channel_name"

  test "parse quic URL":
    let ep = parse_endpoint("quic://host:4434")
    check ep.scheme == ssQuic
    check ep.host == "host"
    check ep.port == 4434

  test "parse mqtt URL with path":
    let ep = parse_endpoint("mqtt://broker:1883/sp_prefix")
    check ep.scheme == ssMqtt
    check ep.host == "broker"
    check ep.port == 1883
    check ep.path == "/sp_prefix"

  test "parse valkey URL":
    let ep = parse_endpoint("valkey://redis:6379/streams")
    check ep.scheme == ssValkey
    check ep.host == "redis"
    check ep.port == 6379
    check ep.path == "/streams"

  test "parse ws URL":
    let ep = parse_endpoint("ws://localhost:8080/sp")
    check ep.scheme == ssWs
    check ep.host == "localhost"
    check ep.port == 8080
    check ep.path == "/sp"

  test "parse 9p URL":
    let ep = parse_endpoint("9p://host:564/sp_root")
    check ep.scheme == ssNinep
    check ep.host == "host"
    check ep.port == 564

  test "invalid URL raises":
    expect SpError:
      discard parse_endpoint("no_scheme")

  test "unknown scheme raises":
    expect SpError:
      discard parse_endpoint("ftp://host:21")

  test "mqtt default port":
    let ep = parse_endpoint("mqtt://broker")
    check ep.port == 1883

  test "valkey default port":
    let ep = parse_endpoint("valkey://host")
    check ep.port == 6379

suite "URL reconstruction":
  test "tcp round-trip":
    let ep = parse_endpoint("tcp://localhost:5555")
    check to_url(ep) == "tcp://localhost:5555"

  test "ipc round-trip":
    let ep = parse_endpoint("ipc:///tmp/sp.sock")
    check to_url(ep) == "ipc:///tmp/sp.sock"

  test "shm round-trip":
    let ep = parse_endpoint("shm://channel")
    check to_url(ep) == "shm://channel"

suite "dial/listen dispatch":
  test "unsupported scheme raises":
    let ep = parse_endpoint("quic://host:4434")
    expect SpError:
      discard dial(ep, spPair)
    expect SpError:
      discard listen(ep, spPair)
