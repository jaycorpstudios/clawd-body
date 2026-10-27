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
| Presence decided once | `hilod` checks presence only when the request arrives. Found 2026-10-25 in a real session: right after typing a prompt the user is always "present", so short turns never reach the buddy even if the user walks away a second later | Options: (a) keep as is; (b) always hold and let the user decide on the buddy (low risk), in a Hilo window/notification on the Mac (any risk), or hand back to the terminal; (c) hand an already-shown terminal prompt to the buddy is not possible (the hook has returned). Needs a decision: (b) changes the decision flow. **Recommendation (agent, 2026-10-25):** a variant of (b) that leaves the contract and risk policy as they are: hold every request for a short grace (e.g. 10–15 s) and re-check presence at the end of it instead of at arrival; send it to the buddy only if the user is away by then, otherwise hand it to the terminal. Trade-offs: short turns reach the buddy when you walk away right after typing; every terminal prompt appears up to the grace later (noticeable when you are at the Mac); pairs well with screen lock as the away signal from "Presence signal". Full (b) with a Hilo window for high-risk is more work and adds a second approval surface on the Mac | 4 |
| Policy file | See [risk-policy.md](../security/risk-policy.md) | Location, format, rule syntax, per-project overrides | 4 |
| How `hilod` is launched | Started from a terminal (Warp, Terminal.app) macOS aborts it on first Bluetooth use: TCC checks the *responsible* app, and terminals declare no `NSBluetoothAlwaysUsageDescription`. Under launchd it is its own responsible process and the embedded `Info.plist` applies (verified 2026-10-25 with `launchctl submit`) | Answered 2026-10-25/26: `hilo install` and Hilo › Setup write a LaunchAgent plist (`RunAtLoad`, `KeepAlive`) for the `hilod` bundled in `Hilo.app` and bootstrap it in `gui/<uid>`, replacing a submitted job; pairing runs through the socket op `pair`. Left: install it once by hand and confirm it survives a logout and keeps the Bluetooth permission (hardware checklist); later, `SMAppService` once the app is notarized (see Distribution) | 3 |
| Stable code signature for `hilod` | Ad-hoc signing changes the binary's hash on every build, and macOS asks for Bluetooth permission again each time | `scripts/build-hilod.sh` now signs with a local self-signed identity (designated requirement: identifier + certificate leaf). 2026-10-25: after the first signed launch, a rebuilt and restarted `hilod` kept the Bluetooth permission with no prompt. Left open: whether to ship `hilod` inside the Hilo app bundle as a login item | 3 |

## Firmware

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Sound playback | ES8311 codec. Implemented 2026-10-25: the cues are synthesized on the device from the prototype's `SOUNDS` / `FAM` (no samples in flash), behind the build option `CONFIG_BUDDY_SOUND` (off by default, as the spec asks) | Confirm synthesis over PCM samples after listening; volume range and default; how the user turns sound on and sets the volume without a rebuild (a device setting, or a Hilo setting sent in a message, which would need a contract field) | 2 |
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

## Security

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Device lock | Anyone at the desk can hold-to-approve | Whether low-risk approvals need a lock/PIN or auto-lock when the user is away | 4 |
| High-risk deny | Contract said "never accepted"; the UI shows "Deny" | Confirm: deny from the buddy is always honored, approve never (current docs assume this) | 4 |
| Secrets in `detail` | Implemented 2026-10-26: conservative redaction in `hilod` ([daemon › security](../components/daemon.md#security)). Heuristic: a secret passed as a positional argument (`aws configure set aws_secret_access_key <value>`) or behind a short flag (`docker login -p <value>`) still reaches the buddy | Whether high-risk Bash should show only the command's first word(s) on the buddy (it can only be denied there, so the full text matters less) — changes what the buddy shows for high risk, not the contract | 3 |
