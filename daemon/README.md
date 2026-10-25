# daemon

`hilod` (the per-Mac daemon) and the `hilo` CLI, in Swift. Spec: [docs/components/daemon.md](../docs/components/daemon.md).

| Target | What it is |
| :--- | :--- |
| `HiloContract` | Codable contract types; strict decoding of buddy → Mac messages |
| `HiloCore` | Request registry (pending, expiry, single use), risk policy, hook → contract mapping, hook replies |
| `HiloRuntime` | `Coordinator` (presence-based hold), `BuddySession` (framing, ordered writes, snapshot on link up), `BLECentral` (CoreBluetooth), trusted buddies, macOS presence probe, Unix socket, stdout link |
| `hilod` | Daemon executable |
| `hilo` | CLI: `hilo hook` (called by Claude Code), `hilo buddy '<json>'` (inject a buddy message, development) |

No third-party packages.

## Build and test

```sh
swift build                 # from daemon/
../scripts/swift-test.sh    # tests; works with Xcode or Command Line Tools only
```

## Pair a buddy

Hold the side button 5 s on the buddy's Home view, then run `hilod --pair`. macOS shows its pairing dialog; type the code the buddy shows. The buddy's identifier is saved to `~/Library/Application Support/Hilo/buddies.json` (the bond keys stay in macOS). From then on plain `hilod` reconnects by itself and sends a `snapshot` on every link up.

`hilod` embeds an `Info.plist` with `NSBluetoothAlwaysUsageDescription`; the first run asks for Bluetooth permission.

## Try it without a buddy

`--stdout` writes every Mac → buddy message to stdout, one per line, instead of using BLE.

```sh
.build/debug/hilod --host work --always-away --stdout | node ../shared/src/cli.ts validate
```

| Flag | Default | Meaning |
| :--- | :--- | :--- |
| `--host` | `work` | `host` sent on every message |
| `--away-after` | `120` | Seconds without keyboard/mouse input before the user counts as away |
| `--always-away` | off | Hold every permission for the buddy (development) |
| `--pair` | off | Scan for a buddy in pairing mode and trust it once paired |
| `--stdout` | off | No BLE; print outgoing messages (development) |
| `--socket` | `~/Library/Application Support/Hilo/hilod.sock` | Socket path (max 103 bytes) |

Answer a held request as the buddy would:

```sh
.build/debug/hilo buddy '{"v":1,"id":"<ULID>","ts":0,"type":"permission.decision","data":{"request_id":"<id>","decision":"approve"}}'
```

## Claude Code hooks

[`hooks.example.json`](hooks.example.json) wires every hook to `hilo hook` (put `hilo` on `PATH`). The blocking hooks use a 660 s timeout so `hilod` always expires a request (600 s) before Claude Code kills the hook. If `hilod` is down, `hilo hook` prints nothing and exits 0, so Claude Code behaves as if no hook existed.
