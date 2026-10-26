# Open questions (pending to define)

Each row: **gap → context → what to fill**. "Phase" is the first [roadmap](../product/roadmap.md) phase it blocks. When resolved, record the decision in the relevant spec and delete the row.

## Product

Nothing pending.

## Architecture

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Host naming | Allowed characters are fixed by the schema (`^[a-z0-9-]{1,16}$`) | Where the user configures it (daemon config file, Hilo settings) and the default | 3 |

## Contract

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Replay window | "Stale messages are rejected" has no number | Accepted `ts` skew (the buddy clock follows the envelope `ts`, see [firmware model behavior](../components/firmware.md#model-behavior)) | 3 |

## BLE

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Two simultaneous Macs | Buddy may be bonded to both | Confirm concurrent links on ESP32-S3 and memory budget | 3 |
| Pairing UX | See [pairing flow](../flows/ble-pairing-flow.md); pairing mode is a 5 s hold on Home | Forgetting a Mac on the device, macOS passkey dialog steps | 3 |

## Daemon

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Presence signal | Remote-decision mode is presence-based (see [remote decision flow](../flows/remote-decision-flow.md#remote-decision-mode)) | Idle threshold before the Mac counts as "away"; verify on real hardware that the terminal prompt stays hidden while the hook waits. Found 2026-10-25: on a laptop a palm resting near the trackpad resets `HIDIdleTime` every few seconds, so the user never counts as away; consider screen lock or display sleep as the main signal, or a manual "away" toggle | 4 |
| Presence decided once | `hilod` checks presence only when the request arrives. Found 2026-10-25 in a real session: right after typing a prompt the user is always "present", so short turns never reach the buddy even if the user walks away a second later | Options: (a) keep as is; (b) always hold and let the user decide on the buddy (low risk), in a Hilo window/notification on the Mac (any risk), or hand back to the terminal; (c) hand an already-shown terminal prompt to the buddy is not possible (the hook has returned). Needs a decision: (b) changes the decision flow | 4 |
| Usage source | 5 h window, weekly %, tokens today | Claude Code local stats vs. hook payloads; never account credentials; until then `snapshot.usage` carries zeros | 3 |
| Policy file | See [risk-policy.md](../security/risk-policy.md) | Location, format, rule syntax, per-project overrides | 4 |
| How `hilod` is launched | Started from a terminal (Warp, Terminal.app) macOS aborts it on first Bluetooth use: TCC checks the *responsible* app, and terminals declare no `NSBluetoothAlwaysUsageDescription`. Under launchd it is its own responsible process and the embedded `Info.plist` applies (verified 2026-10-25 with `launchctl submit`) | LaunchAgent plist and who installs it (`hilo install`?), log location, how `--pair` is run | 3 |
| Stable code signature for `hilod` | Ad-hoc signing changes the binary's hash on every build, and macOS asks for Bluetooth permission again each time | `scripts/build-hilod.sh` now signs with a local self-signed identity (designated requirement: identifier + certificate leaf). 2026-10-25: after the first signed launch, a rebuilt and restarted `hilod` kept the Bluetooth permission with no prompt. Left open: whether to ship `hilod` inside the Hilo app bundle as a login item | 3 |

## Firmware

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Sound playback | ES8311 codec. Implemented 2026-10-25: the cues are synthesized on the device from the prototype's `SOUNDS` / `FAM` (no samples in flash), behind the build option `CONFIG_BUDDY_SOUND` (off by default, as the spec asks) | Confirm synthesis over PCM samples after listening; volume range and default; how the user turns sound on and sets the volume without a rebuild (a device setting, or a Hilo setting sent in a message, which would need a contract field) | 2 |
| Time zone | The clock comes from the envelope `ts` (UTC); the offset is a build setting for now | Where the user sets it (Hilo settings sent in a message, or a fixed per-device setting) and DST handling | 2 |
| Battery target | 1000 mAh Li-ion | Expected hours per charge; brightness/sleep policy to meet it | 2 |
| OTA | Not decided | Skip, or signed images only (signing key custody, rollback) | 6 |

## Hilo

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Session ↔ task linking | Sessions must attach to Hilo tasks. Implemented default: a session links to its project's task in progress when there is exactly one; otherwise by hand (app or `hilo link`). Project = repo directory name | Confirm the default, or add branch matching / a prompt when the session starts | 5 |
| Weekly summary drafting | "Drafted by Claude" | How, without storing API keys in Hilo (e.g. via Claude Code + MCP) | 5 |
| Jira credentials | Optional per-project sync | Storage (macOS Keychain), scopes, sync interval | 5 |
| Project hue/accessory | Fixed per project, same on buddy and Hilo; the contract has no hue/accessory field yet | Assigned manually, from config, or derived from the name | 5 |
| Music source | `media.now_playing` has no producer | Which player(s) and how `hilod` reads now-playing on macOS | 6 |
| Setup and pairing in the app | Today `hilod --pair`, `launchctl submit` and the `--host` flag are terminal-only, and each Mac's name on the buddy defaults to `work` | Requirement (2026-10-25): a first-run wizard in Hilo that names this Mac (e.g. Work / Home, editable later in settings and sent as `host`), starts `hilod`, walks through buddy pairing (hold the button 5 s, passkey) and shows link status; nothing should need the terminal | 5 |
| Distribution | `Hilo.app` is built with SwiftPM and bundled by `scripts/build-hilo-app.sh`, signed with the local identity; `hilod` still runs as a separate launchd job | Embed `hilod` in the app as a login item (stable Bluetooth permission, no `launchctl submit`), notarization, install/update path | 5 |

## Security

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Device lock | Anyone at the desk can hold-to-approve | Whether low-risk approvals need a lock/PIN or auto-lock when the user is away | 4 |
| High-risk deny | Contract said "never accepted"; the UI shows "Deny" | Confirm: deny from the buddy is always honored, approve never (current docs assume this) | 4 |
| Secrets in `detail` | The buddy shows the full Bash command, which may include a token (`curl -H "Authorization: …"`, `export KEY=…`); unknown tools already send only their name | Redaction rules before sending (header values, `KEY=value`, long base64/hex strings) or show only the first word for high-risk commands | 3 |
