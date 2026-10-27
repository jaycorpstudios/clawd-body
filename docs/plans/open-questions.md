# Open questions (pending to define)

Each row: **gap → context → what to fill**. "Phase" is the first [roadmap](../product/roadmap.md) phase it blocks. When resolved, record the decision in the relevant spec and delete the row.

## Product

Nothing pending.

## Architecture

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |

## Contract

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Replay window | "Stale messages are rejected" has no number. Today `hilod` ignores the buddy's `ts`; decisions are still single use and expire (600 s), so a replayed decision is dropped by the registry. The buddy cannot judge staleness of Mac messages, since its clock follows their `ts` | Accepted `ts` skew. **Analysis (agent, 2026-10-26):** (a) daemon-only window: reject a buddy message whose `ts` is more than 120 s from the Mac clock, plus an id cache for 10 min (covers the window twice); the buddy clock comes from the Mac (and the RTC across reboots), so honest skew stays at a few seconds; (b) also on the buddy: reject Mac messages older than the last accepted `ts` minus 120 s; protects against a replayed `snapshot` reordering state, but a Mac whose clock jumps back would be locked out until it catches up; (c) no window, rely on single use + expiry + bonded encrypted link (a replay needs the LTK already). **Recommendation:** (a) with 120 s; it changes the contract doc's rule from prose to a number and `hilo buddy` must then fill a real `ts` (it sends 0 today), so it needs your approval | 3 |

## BLE

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Two simultaneous Macs | Buddy may be bonded to both. `CONFIG_BT_NIMBLE_MAX_CONNECTIONS=2`, `MAX_BONDS=4`, `BM_MAX_HOSTS=2`; both links' reassembly buffers (2 × 8 KB) are static | Confirm concurrent links on ESP32-S3 and memory budget. **Measured (2026-10-26):** BLE build with one Mac linked: 163 KB internal free after boot, low-water 69 KB within the first minute (connect, MTU 517, 1 KB snapshot), 133 KB on the sleep clock; PSRAM 6.2 MB free; the model (76 KB, two hosts) lives in PSRAM. Demo build, two simulated hosts, no BLE (2026-10-25): 196 KB free, low-water 94 KB over an hour. NimBLE allocates both connections at init, so a second link adds only transient buffers (mbufs for its snapshot, up to 8 KB message). **Assessment:** fits, but the 69 KB low-water after one connect is the number to watch; if two snapshots at once push it under ~40 KB, move the frame reassembly buffers to PSRAM. Left for the board: two Macs connected at once (hardware checklist) and the heap line during both snapshots. **Faces (2026-10-26, one Mac linked):** both hosts' picture slots sit in the model, sized for the contract's 160×160 RGB565 maximum (2 × 51.2 KB plus a 51.2 KB receive buffer; model now 230 KB in PSRAM), plus one 240×240 display buffer (115 KB PSRAM), so a second picture costs no new memory. Internal heap: 146 KB free after boot, low-water 65.7 KB within the first minute with or without a picture (the dip is the BLE connect, not the 7 × 6 KB `host.face` chunks: 64.2 KB with the transfer), 150 KB on the sleep cards; PSRAM 5.7 MB free | 3 |
| Pairing UX | See [pairing flow](../flows/ble-pairing-flow.md); pairing mode is a 5 s hold on Home | Forgetting a Mac on the device, macOS passkey dialog steps | 3 |

## Daemon

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Presence signal | Remote-decision mode is presence-based (see [remote decision flow](../flows/remote-decision-flow.md#remote-decision-mode)) | Idle threshold before the Mac counts as "away"; verify on real hardware that the terminal prompt stays hidden while the hook waits. Found 2026-10-25: on a laptop a palm resting near the trackpad resets `HIDIdleTime` every few seconds, so the user never counts as away; consider screen lock or display sleep as the main signal, or a manual "away" toggle | 4 |
| Presence decided once | `hilod` checks presence only when the request arrives. Found 2026-10-25 in a real session: right after typing a prompt the user is always "present", so short turns never reach the buddy even if the user walks away a second later | Options: (a) keep as is; (b) always hold and let the user decide on the buddy (low risk), in a Hilo window/notification on the Mac (any risk), or hand back to the terminal; (c) hand an already-shown terminal prompt to the buddy is not possible (the hook has returned). Needs a decision: (b) changes the decision flow. **Recommendation (agent, 2026-10-25):** a variant of (b) that leaves the contract and risk policy as they are: hold every request for a short grace (e.g. 10–15 s) and re-check presence at the end of it instead of at arrival; send it to the buddy only if the user is away by then, otherwise hand it to the terminal. Trade-offs: short turns reach the buddy when you walk away right after typing; every terminal prompt appears up to the grace later (noticeable when you are at the Mac); pairs well with screen lock as the away signal from "Presence signal". Full (b) with a Hilo window for high-risk is more work and adds a second approval surface on the Mac | 4 |
| Policy file | See [risk-policy.md](../security/risk-policy.md); built-in defaults in `RiskPolicy.swift` | Location, format, rule syntax, per-project overrides. **Analysis (agent, 2026-10-26):** format: JSON is the only parser without a new dependency (TOML/YAML would need one); location: `~/Library/Application Support/Hilo/policy.json` next to `config.json`, never a file inside the repo (a cloned repo could allowlist its own commands); syntax: per tool, Bash rules as exact argv lists with an optional trailing `<pkg>@<x.y.z>`-style placeholder (no globs or regex, the same "no shell syntax" check stays in code), WebFetch as an https host list, Read/Edit stay "inside the repo" in code; per-project overrides keyed by project name, only adding rules; a file that fails to parse falls back to the defaults and the Hilo app shows the error. Trade-offs: JSON has no comments (a `"why"` field per rule instead); exact argv lists are verbose but cannot be widened by accident. **Recommendation:** as above; it changes the risk policy, so it needs your approval before implementing | 4 |
| How `hilod` is launched | Started from a terminal (Warp, Terminal.app) macOS aborts it on first Bluetooth use: TCC checks the *responsible* app, and terminals declare no `NSBluetoothAlwaysUsageDescription`. Under launchd it is its own responsible process and the embedded `Info.plist` applies (verified 2026-10-25 with `launchctl submit`) | Answered 2026-10-25/26: `hilo install` and Hilo › Setup write a LaunchAgent plist (`RunAtLoad`, `KeepAlive`) for the `hilod` bundled in `Hilo.app` and bootstrap it in `gui/<uid>`, replacing a submitted job; pairing runs through the socket op `pair`. Left: install it once by hand and confirm it survives a logout and keeps the Bluetooth permission (hardware checklist); later, `SMAppService` once the app is notarized (see Distribution) | 3 |
| Stable code signature for `hilod` | Ad-hoc signing changes the binary's hash on every build, and macOS asks for Bluetooth permission again each time | `scripts/build-hilod.sh` now signs with a local self-signed identity (designated requirement: identifier + certificate leaf). 2026-10-25: after the first signed launch, a rebuilt and restarted `hilod` kept the Bluetooth permission with no prompt. Left open: whether to ship `hilod` inside the Hilo app bundle as a login item | 3 |

## Firmware

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Sound playback | ES8311 codec. The cues are synthesized on the device from the prototype's `SOUNDS` / `FAM` (no samples in flash). Since 2026-10-27 sound is always built in and is a device setting (off by default, volume 60), set from the buddy's settings panel or Hilo › Setup (`settings.set` / `device.settings`) | Confirm synthesis over PCM samples after listening; whether 60 is the right default volume on this speaker | 2 |
| Time zone | The clock comes from the envelope `ts` (UTC); the offset is a build setting for now | Where the user sets it (Hilo settings sent in a message, or a fixed per-device setting) and DST handling | 2 |
| Battery target | 1000 mAh Li-ion. Implemented 2026-10-26: panel at 100 % awake and 20 % on the sleep clock (build options), and a battery log line every 60 s (`battery … % … mV, usb, charging, up N min, sleeping 0/1`) so a discharge can be read off the serial log; not measured yet (the board was on USB) | Expected hours per charge. **Proposal (agent):** aim for a working day away from USB (≥ 10 h, mostly on the sleep clock) and measure before tuning: one unplugged run from 100 % with the serial log, reading %/h and mV/h awake vs. sleeping from the 60 s lines. If it falls short, in order of cost: (a) awake brightness 70 % (`CONFIG_BUDDY_BRIGHTNESS`); (b) panel off after e.g. 10 min on the sleep clock, wake on touch or button (no clock visible; touch stays powered); (c) a slower LVGL refresh while asleep; (d) BLE connection interval / modem sleep tuning (affects reconnect and notify latency). Nothing measured about current draw: the AXP2101 gauge only gives percent and voltage | 2 |
| OTA | Not decided | Skip, or signed images only (signing key custody, rollback) | 6 |

## Hilo

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Session ↔ task linking | Sessions must attach to Hilo tasks. Implemented default: a session links to its project's task in progress when there is exactly one; otherwise by hand (app or `hilo link`). Project = repo directory name | Confirm the default, or add branch matching / a prompt when the session starts | 5 |
| Weekly summary drafting | "Drafted by Claude" | How, without storing API keys in Hilo (e.g. via Claude Code + MCP) | 5 |
| Jira credentials | Optional per-project sync | Storage (macOS Keychain), scopes, sync interval | 5 |
| Project hue/accessory | Fixed per project, same on buddy and Hilo; the contract has no hue/accessory field yet | Assigned manually, from config, or derived from the name | 5 |
| Music source | `media.now_playing` has no producer | Which player(s) and how `hilod` reads now-playing on macOS | 6 |
| Setup and pairing in the app | Implemented 2026-10-25 as the app's Setup section (see [hilo.md](../components/hilo.md#screens)); pairing itself not yet run from the app on the board | Confirm the flow after a real pairing; whether Setup should also open as a modal on first run; renaming a Mac drops the old name's sessions on the buddy (it frees the slot) | 5 |
| Distribution | `Hilo.app` is built with SwiftPM and bundled by `scripts/build-hilo-app.sh`, signed with the local identity; `hilod` runs as a LaunchAgent pointing into the bundle (`hilo install` or Setup) | Embed `hilod` in the app as a login item (stable Bluetooth permission, no `launchctl submit`), notarization, install/update path | 5 |
| Prototype parity gaps | Reviewed 2026-10-26 with `HILO_SNAPSHOT` and scratch data. Done: tokens column, JetBrains Mono, Week's hours per day and tasks closed | (a) Bricolage Grotesque / Hanken Grotesk: fetch the OFL TTFs from their upstream repos at a pinned commit with SHA-256 (as the firmware fonts) and bundle them, or keep the system font; (b) "Warp tab" column and "Open in Warp": needs a way to map a session to a terminal tab (Warp has no public API for it; drop the column or show the terminal app only); (c) Week: previous/next week navigation and "Export .md" (save panel) are small, pure UI; the Claude summary depends on "Weekly summary drafting" | 5 |

## Security

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Device lock | Anyone at the desk can hold-to-approve | Whether low-risk approvals need a lock/PIN or auto-lock when the user is away | 4 |
| High-risk deny | Contract said "never accepted"; the UI shows "Deny" | Confirm: deny from the buddy is always honored, approve never (current docs assume this) | 4 |
| Secrets in `detail` | Implemented 2026-10-26: conservative redaction in `hilod` ([daemon › security](../components/daemon.md#security)). Heuristic: a secret passed as a positional argument (`aws configure set aws_secret_access_key <value>`) or behind a short flag (`docker login -p <value>`) still reaches the buddy | Whether high-risk Bash should show only the command's first word(s) on the buddy (it can only be denied there, so the full text matters less) — changes what the buddy shows for high risk, not the contract | 3 |
