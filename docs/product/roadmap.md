# Roadmap

> Initial outline. Detailed phase planning (deliverables, exit criteria, dependencies) is the next step and will replace this list.

```mermaid
flowchart LR
    P1[1 · Event contract<br/>+ terminal simulator] --> P2[2 · Firmware views<br/>with fake data]
    P1 --> P3[3 · Daemon: hooks → events → BLE<br/>secure pairing]
    P2 --> P4[4 · Remote decisions<br/>validated in daemon]
    P3 --> P4
    P3 --> P5[5 · Hilo: SQLite, CLI, MCP, then UI]
    P4 --> P6[6 · Extras: Hilo on buddy,<br/>music, per-project accessories]
    P5 --> P6
```

| Phase | Outcome | Status |
| :--- | :--- | :--- |
| 1 | Event schema in `shared/` as single source of truth; a terminal tool that emits contract events | Done |
| 2 | Firmware renders all views and the pet from fake data, matching the simulator | All views, pet, alerts, permission screen and sheets drawn from the model; demo build verified on the board ([hardware checklist](../plans/testing-strategy.md#hardware-checklist)); battery (AXP2101) and RTC (PCF85063) read on the board; sound synthesized and played through the ES8311 behind a build option, not listened to yet |
| 3 | `hilod` turns Claude Code hooks into events and sends them over a bonded BLE link | Hook ingestion, risk policy, NimBLE peripheral and CoreBluetooth central with passkey pairing done and verified on the board (bond, MTU 517, snapshot, reconnects); usage from the status line's `rate_limits` (and, opt-in, transcript tokens) reaches the buddy; unbonded central, two Macs and RPA not tested yet |
| 4 | Permission and question decisions from the buddy, validated by the daemon | Daemon side (registry, presence-based hold) and buddy permission screen with hold-to-approve done; a low-risk approval (synthetic and from a real Claude Code session) and the high-risk block verified on the board; deny, questions and presence timing still open |
| 5 | Hilo data layer (SQLite), CLI and MCP; then the macOS UI | SQLite store, session recording in `hilod`, `hilo` CLI, MCP server, the SwiftUI app with all five screens, Setup (name, `hilod`, guided pairing; pairing not yet run from the app) and automatic capture of commits and active time done; Jira and Claude-drafted weekly summary not started |
| 6 | Hilo view on the buddy, music view, per-project accessories | Buddy Hilo and Music views drawn; per-project hue and accessory derived from the project name, identical on the buddy and in Hilo; no music producer yet |
