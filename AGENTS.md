# AGENTS.md

> Single source of truth for agents in this repository.
> `CLAUDE.md` mirrors this file — edit this one.

## Mission

A desk buddy (ESP32-S3 AMOLED) and **Hilo**, a local macOS app + daemon, that show Claude Code session state and let the user answer low-risk prompts from the device.
Correct means: nothing high-risk is ever approved off the Mac, and the device never holds a secret.

## Structure

| Path | Role |
| :--- | :--- |
| `docs/` | Product, architecture, component specs, flows, security (start at `docs/README.md`) |
| `prototypes/` | Approved UI references: device simulator and Hilo screens |
| `shared/` | Event schema (single source of truth for the contract), fixtures, `buddy-emit` tool |
| `firmware/` | ESP-IDF 5.5.6 + LVGL 9 firmware (display bring-up so far; views, BLE, audio next) |
| `daemon/` | `hilod` and `hilo` CLI in Swift: contract types, risk policy, request registry, hook ingestion, BLE central, SQLite store (MCP planned) |
| `hilo/` | Hilo macOS app (SwiftUI, SwiftPM) over the shared SQLite store |

## How to work here

1. Read the spec of the component you touch before proposing changes.
2. Propose a short plan before large changes and wait for confirmation.
3. Work one component at a time; the event contract is the boundary between them.
4. For UI, the approved prototypes win over prose — match views, states, timings and sounds.
5. Open decisions live in `docs/plans/open-questions.md`: present options with trade-offs, never decide silently.
6. Repo content is English; keep docs and indexes in sync when adding files.

Validate with `pnpm test` (contract, `shared/`) and `scripts/swift-test.sh` (daemon), `scripts/firmware-test.sh` (firmware model, host) and `scripts/idf.sh build` (firmware); `scripts/firmware-render.sh` draws buddy screens to PNG on the Mac for a layout check. `scripts/build-hilod.sh` and `scripts/build-hilo-app.sh` make the signed Mac builds; `scripts/doctor.sh` checks a Mac for them. Node version: `.nvmrc`.

## Set up a new Mac

When asked to get Hilo running on this Mac:

1. Run `scripts/doctor.sh` and report what is missing. It installs nothing.
2. For a MISS, tell the user the fix and wait; never install anything (Xcode, Command Line Tools, Node, ESP-IDF) without their OK.
3. Build with `scripts/build-hilod.sh` then `scripts/build-hilo-app.sh`. The first one may ask for the login keychain password; let the user answer.
4. Ask whether they want a Desktop shortcut while the app has no installer; if yes, `scripts/desktop-shortcut.sh`.
5. Run `open hilo/.build/Hilo.app` and hand over to Hilo › Setup (README, "Set up a Mac"). Do not edit `~/.claude/settings.json`, install the LaunchAgent or pair from the terminal: Setup does those, with the user watching.
6. Run `scripts/doctor.sh` again and summarize.

## Start here

- [docs/README.md](docs/README.md) — documentation index
- [docs/product/vision.md](docs/product/vision.md) — problem, users, scope
- [docs/architecture/overview.md](docs/architecture/overview.md) — system map and repo layout
- [docs/architecture/event-contract.md](docs/architecture/event-contract.md) — Mac ⇄ buddy messages
- [docs/components/README.md](docs/components/README.md) — firmware, daemon, Hilo, device UI specs
- [docs/flows/README.md](docs/flows/README.md) — hook ingestion, decisions, pairing, reconnection
- [docs/security/README.md](docs/security/README.md) — threat model and risk policy
- [docs/plans/open-questions.md](docs/plans/open-questions.md) — everything still pending to define
- [docs/approval-policy.md](docs/approval-policy.md) — what an agent may do without asking

## Skills

| Skill | Purpose | Source of truth |
| :--- | :--- | :--- |
| — | No project skills yet | — |

## Non-negotiables

- The buddy never stores credentials, tokens or API keys; only BLE bonding keys managed by the stack.
- BLE uses LE Secure Connections with passkey; unbonded connections are always rejected.
- High-risk actions are approved only on the Mac; the daemon owns the remote-approval allowlist.
- Every decision from the buddy is validated by the daemon: pending `request_id`, not expired, single use.
- Hilo data stays on the Mac that produced it; no sync between machines.
- This repo is public: no personal data, absolute paths, hostnames or real work project names.

## Preferred workflow

Understand → read the component spec → short plan → confirm → smallest change → validate → update docs.

## If information is missing

Add a "Pending to define" row to `docs/plans/open-questions.md` (gap → context → what to fill).
Never invent hardware, protocol or product detail.
