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
| Replay window | "Stale messages are rejected" has no number | Accepted `ts` skew; clock source on the buddy (see RTC row) | 3 |
| Usage across Macs | Both Macs may report usage for the same account | Which value the buddy shows (latest, max, per host) | 2 |

## BLE

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Two simultaneous Macs | Buddy may be bonded to both | Confirm concurrent links on ESP32-S3 and memory budget | 3 |
| Pairing UX | See [pairing flow](../flows/ble-pairing-flow.md) | Pairing-mode gesture, forgetting a Mac on the device, macOS passkey dialog steps | 3 |

## Daemon

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Presence signal | Remote-decision mode is presence-based (see [remote decision flow](../flows/remote-decision-flow.md#remote-decision-mode)) | Idle threshold before the Mac counts as "away"; verify on real hardware that the terminal prompt stays hidden while the hook waits | 4 |
| Usage source | 5 h window, weekly %, tokens today | Claude Code local stats vs. hook payloads; never account credentials ; until then `snapshot.usage` carries zeros | 3 |
| Policy file | See [risk-policy.md](../security/risk-policy.md) | Location, format, rule syntax, per-project overrides | 4 |

## Firmware

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Pins and drivers | ESP-IDF + LVGL 9 chosen | Confirm CO5300, CST9220, AXP2101, ES8311 drivers and pins against the Waveshare schematic and official ESP-IDF demos; ESP-IDF version to pin | 2 |
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
| Project hue/accessory | Fixed per project, same on buddy and Hilo; the contract has no hue/accessory field yet | Assigned manually, from config, or derived from the name | 5 |
| Music source | `media.now_playing` has no producer | Which player(s) and how `hilod` reads now-playing on macOS | 6 |
| Distribution | Login item + app | Signing, notarization, install/update path | 5 |

## Security

| Gap | Context | What to fill | Phase |
| :--- | :--- | :--- | :---: |
| Device lock | Anyone at the desk can hold-to-approve | Whether low-risk approvals need a lock/PIN or auto-lock when the user is away | 4 |
| High-risk deny | Contract said "never accepted"; the UI shows "Deny" | Confirm: deny from the buddy is always honored, approve never (current docs assume this) | 4 |
| Secrets in `detail` | The buddy shows the full Bash command, which may include a token (`curl -H "Authorization: …"`, `export KEY=…`); unknown tools already send only their name | Redaction rules before sending (header values, `KEY=value`, long base64/hex strings) or show only the first word for high-risk commands | 3 |
