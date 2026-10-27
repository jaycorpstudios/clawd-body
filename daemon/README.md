# daemon

`hilod` (the per-Mac daemon) and the `hilo` CLI, in Swift. Spec: [docs/components/daemon.md](../docs/components/daemon.md).

| Target | What it is |
| :--- | :--- |
| `HiloContract` | Codable contract types; strict decoding of buddy → Mac messages |
| `HiloCore` | Request registry (pending, expiry, single use), risk policy, hook → contract mapping, hook replies, usage tracker |
| `HiloRuntime` | `Coordinator` (presence-based hold), `BuddySession` (framing, ordered writes, snapshot on link up), `BLECentral` (CoreBluetooth), trusted buddies, macOS presence probe, Unix socket, stdout link, config file, transcript token counter |
| `hilod` | Daemon executable |
| `HiloStore` | SQLite store shared with the Hilo app: projects, tasks, sessions and steps, agreements |
| `hilo` | CLI: `hilo hook` (called by Claude Code), tasks and agreements (`hilo today`, `add`, `start`, `done`, `agree`, `sessions`, `link`), `hilo resume` and `hilo week [--md]`, `hilo mcp` (MCP server for Claude Code), `hilo statusline` (usage from the status line), `hilo install` / `uninstall` (LaunchAgent), `hilo buddy '<json>'` (development) |

No third-party packages.

## Build and test

```sh
swift build                 # from daemon/
../scripts/swift-test.sh    # tests; works with Xcode or Command Line Tools only
../scripts/build-hilod.sh   # signed release build (creates a local signing identity once)
```

macOS ties the Bluetooth permission to the code signature. An ad-hoc signature changes on every build, so `build-hilod.sh` signs with a self-signed "Hilo Local Signing" identity in the login keychain. The first time, macOS asks for the keychain password so `codesign` can use the key.

Run `hilod` under launchd; started from a terminal, macOS aborts it on first Bluetooth use. `hilo install` writes the LaunchAgent `~/Library/LaunchAgents/dev.hilo.hilod.plist` (`RunAtLoad`, `KeepAlive`, log in `~/Library/Logs/Hilo/hilod.log`) for the `hilod` inside `Hilo.app` (or `--hilod <path>`) and bootstraps it, replacing a job started with `launchctl submit`; it then starts at every login. `hilo uninstall` stops it and removes the plist. Hilo › Setup uses the same code. For a quick run of a dev build without installing anything:

```sh
launchctl submit -l dev.hilo.hilod -o ~/Library/Logs/Hilo/hilod.log -e ~/Library/Logs/Hilo/hilod.log -- "$PWD/.build/release/hilod"
```

The log records the buddy link, every held or released request and every buddy decision.

## Pair a buddy

The Hilo app's Setup section does this without a terminal (socket ops `pair`, `pair-cancel`, `status`). By hand:

Hold the side button 5 s on the buddy's Home view, then run `hilod --pair`. macOS shows its pairing dialog; type the code the buddy shows. The buddy's identifier is saved to `~/Library/Application Support/Hilo/buddies.json` (the bond keys stay in macOS). From then on plain `hilod` reconnects by itself and sends a `snapshot` on every link up.

`hilod` embeds an `Info.plist` with `NSBluetoothAlwaysUsageDescription`; the first run asks for Bluetooth permission.

## Now playing

Every 3 s `hilod` asks Spotify and then Music.app (only if already running) what is playing over AppleScript and forwards changes as `media.now_playing`; the buddy's play/pause, next and previous come back as `media.control` and run as the matching AppleScript command on that app. macOS asks once per app for Automation permission ("hilod wants to control Spotify"); if it is denied (-1743) the log says so once and `hilod` asks that app again only every 5 min, so allowing it later in System Settings works without a restart. Scripts run off the coordinator with a 5 s AppleEvent timeout, so a pending prompt or a hung player never delays hooks or buddy messages; buddy controls run in order on one serial queue, and a player that quits mid-query simply reads as "nothing playing". See [open questions](../docs/plans/open-questions.md) for what to do if the prompt never shows under launchd.

When the track changes `hilod` also reads its cover once, off the coordinator: Music.app hands over `raw data of artwork 1`; Spotify only gives an `artwork url`, which is downloaded only when it is `https://i.scdn.co/…` (no other host, port or user info, redirects only to the same host), with an ephemeral session (no cookies, cache or credentials), a 5 s timeout and a 2 MB cap. ImageIO decodes it (at most 384 px) and CoreGraphics scales it to 96×96 RGB565; `media.now_playing` then names it by hash and the buddy asks for the chunks ([covers](../docs/architecture/event-contract.md#covers)). A cover that arrives after the track changed is dropped; a track without one keeps the generated pixel cover. This download is the only outbound network request `hilod` makes.

## Socket ops

One request per connection on the Unix socket: the first line is the op, the rest its body. Only the same user can connect.

| Op | Body | Reply | Used by |
| :--- | :--- | :--- | :--- |
| `hook` | Claude Code hook JSON | What the hook prints | `hilo hook` |
| `usage` | `rate_limits` JSON | `ok` | `hilo statusline` |
| `hilo` | — | `ok`; re-sends the snapshot | CLI, MCP, app after a store change |
| `buddy` | A buddy → Mac message | `ok` or `rejected` | `hilo buddy` (development) |
| `status` | — | `DaemonStatus` JSON: host, buddy link and pairing, transcript tokens, and the buddy's last `device.settings` | Hilo app |
| `pair` / `pair-cancel` | — | `DaemonStatus` | Setup |
| `host` | Display name | `DaemonStatus`; saves `config.json`, re-links | Setup |
| `settings` | `{ sound?, volume?, brightness? }` | `DaemonStatus`; sends `settings.set` (the buddy's answer shows up in a later `status`) | Setup |
| `pomodoro` | `{"action":"toggle"}`, `{"action":"reset"}` or `{"action":"durations","work_min"?,"break_min"?}` | `DaemonStatus` with `pomodoro`; sends `pomodoro.state`. Durations change only while stopped | Hilo › Focus |

The Pomodoro state is saved in the store (`focus_state`) in the same transaction as the work phases it finished (`focus_cycle`) and restored when `hilod` starts: a restart mid-cycle records the phases that ended while it was down exactly once, and Hilo › Focus has the timer before the buddy reconnects. A buddy with a newer `updated_at` still wins when it reconnects.
| `face` | — | `DaemonStatus`; reloads `face.png` next to `config.json`, scales it to 120×120 RGB565 (ImageIO/CoreGraphics) and sends it, or clears it if the file is gone | Setup |

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
| `--tokens-from-transcripts` | off | Count today's tokens from Claude Code's local transcripts (see [Usage](#usage)) |
| `--socket` | `~/Library/Application Support/Hilo/hilod.sock` | Socket path (max 103 bytes) |

`~/Library/Application Support/Hilo/config.json` (`HILO_CONFIG` overrides the path) holds the same settings for a plain `hilod` run; flags win:

```json
{ "host": "work", "tokens_from_transcripts": true }
```

Answer a held request as the buddy would:

```sh
.build/debug/hilo buddy '{"v":1,"id":"<ULID>","ts":0,"type":"permission.decision","data":{"request_id":"<id>","decision":"approve"}}'
```

`../scripts/hilod-e2e.sh [workdir]` does this end to end with a scratch config, store and socket: a low-risk deny, a question answer and an ignored high-risk approval go through `hilo hook` and `hilo buddy`, the secret in a `curl` header must not reach stdout, and every message is validated against the schema.

## Usage

`usage.update` and `snapshot.usage` come from two local sources; no account credentials or API calls.

- **5 h and weekly percent, reset time.** Claude Code hands its status line command a `rate_limits` object (`five_hour` / `seven_day`, each `used_percentage` and `resets_at`). `hilo statusline` forwards only that object to `hilod` (socket op `usage`) and then runs the wrapped command with the same input, so an existing status line keeps working. In `~/.claude/settings.json`:

  ```json
  "statusLine": { "type": "command", "command": "hilo statusline -- bash ~/.claude/statusline-command.sh" }
  ```

  Without a wrapped command it prints nothing. Values only move while a Claude Code window is open; a new 5 h window (a later `resets_at`) sends `usage.window_reset` first. `hilod` sends an update only when a percent or the window changes; the buddy counts the reset down by itself.
- **Tokens today** (opt-in, `--tokens-from-transcripts` or `tokens_from_transcripts`): every 60 s `hilod` reads the new lines of today's `~/.claude/projects/**/*.jsonl` (`CLAUDE_CONFIG_DIR` respected) and sums `input + cache writes + output` of each assistant message once (cache reads are left out; they would dwarf the rest). The same scan stores each session's whole-transcript total (its subagents included) in the Hilo store, shown in Hilo › Sessions; a transcript is named after its session id. Opt-in because the transcript format is internal to Claude Code and may change.

## Claude Code hooks

[`hooks.example.json`](hooks.example.json) wires every hook to `hilo hook` (put `hilo` on `PATH`). The blocking hooks use a 660 s timeout so `hilod` always expires a request (600 s) before Claude Code kills the hook. If `hilod` is down, `hilo hook` prints nothing and exits 0, so Claude Code behaves as if no hook existed.
