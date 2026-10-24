# Open questions (pending to define)

Each row: **gap → context → what to fill**. "Phase" is the first [roadmap](../product/roadmap.md) phase it blocks. When resolved, record the decision in the relevant spec and delete the row.

## Product

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Success criteria | No measurable targets yet | Hook-to-screen latency, battery life, idle CPU budget, "no high-risk approval from device" test | 1 |
| Project name | "Clawd" is Anthropic's mascot name; repo is public | Keep with disclaimer or rename before publishing | 1 |

## Architecture

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Daemon and app stack | Native Swift vs. TypeScript/Node + Tauri/Electron, etc. | Choice with trade-offs: CoreBluetooth stability, power, login-item packaging, MCP SDK availability | 3 |
| Host naming | `host` is a short user-configured name | Where it is configured, allowed characters (schema: `^[a-z0-9-]{1,16}$`) | 1 |

## Contract

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| `snapshot` shape | Only top-level keys are listed | Full schema for `sessions`, `usage`, `hilo`, `media`; max size | 1 |
| Question resolution | Only `agent.permission_resolved` exists | Message that closes a question answered on the Mac or expired | 1 |
| Schema coverage | JSON Schema covers 4 of 21 types | Payload schema for every type; `host` required for Mac → buddy | 1 |
| Replay window | "Stale messages are rejected" has no number | Accepted `ts` skew; clock source on the buddy (see RTC row) | 3 |
| Usage across Macs | Both Macs may report usage for the same account | Which value the buddy shows (latest, max, per host) | 2 |

## BLE

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| GATT layout and framing | See [ble-transport.md](../architecture/ble-transport.md) | UUIDs, characteristics, MTU strategy (write long vs. length + CRC framing) | 3 |
| Two simultaneous Macs | Buddy may be bonded to both | Confirm concurrent links on ESP32-S3 and memory budget | 3 |
| Pairing UX | See [pairing flow](../flows/ble-pairing-flow.md) | Pairing-mode gesture, forgetting a Mac on the device, macOS passkey dialog steps | 3 |

## Daemon

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Hook ↔ daemon IPC | Hooks run as short commands | Transport (e.g. user-only Unix socket), auth, fail-open behavior when `hilod` is down | 3 |
| Hook event mapping | Contract types must map to real Claude Code hook events | Table hook event → contract type, verified against current Claude Code docs | 3 |
| Blocking and timeout | Expiry default is 10 min | Whether a permission hook can wait that long; fallback to the Mac prompt on timeout; how the hook learns the terminal answered first | 4 |
| Answering questions | Device answers `AskUserQuestion` | Whether a hook can inject the answer; if not, scope questions as display-only | 4 |
| Usage source | 5 h window, weekly %, tokens today | Claude Code local stats vs. hook payloads; never account credentials | 3 |
| Policy file | See [risk-policy.md](../security/risk-policy.md) | Location, format, rule syntax, per-project overrides | 4 |

## Firmware

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Framework | ESP-IDF + LVGL vs. Arduino + LVGL | Choice; confirm pins and drivers against the Waveshare schematic and official examples | 2 |
| Sound playback | ES8311 codec | Simple synthesis vs. short PCM samples; volume range | 2 |
| RTC time source | PCF85063 RTC on board | Who sets the clock (time sync message from the Mac?) | 2 |
| Battery target | 1000 mAh Li-ion | Expected hours per charge; brightness/sleep policy to meet it | 2 |
| OTA | Not decided | Skip, or signed images only (signing key custody, rollback) | 6 |

## Hilo

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Session ↔ task linking | Sessions must attach to Hilo tasks | By directory, branch, or a prompt when the session starts | 5 |
| Weekly summary drafting | "Drafted by Claude" | How, without storing API keys in Hilo (e.g. via Claude Code + MCP) | 5 |
| Jira credentials | Optional per-project sync | Storage (macOS Keychain), scopes, sync interval | 5 |
| Project hue/accessory | Fixed per project, same on buddy and Hilo | Assigned manually, from config, or derived from the name | 5 |
| Music source | `media.now_playing` has no producer | Which player(s) and how `hilod` reads now-playing on macOS | 6 |
| Distribution | Login item + app | Signing, notarization, install/update path | 5 |

## Security

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Device lock | Anyone at the desk can hold-to-approve | Whether low-risk approvals need a lock/PIN or auto-lock when the user is away | 4 |
| High-risk deny | Contract said "never accepted"; the UI shows "Deny" | Confirm: deny from the buddy is always honored, approve never (current docs assume this) | 4 |
