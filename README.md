# Hilo Buddy

A desk companion that shows what your Claude Code sessions are doing, plus **Hilo**, a local macOS app that keeps track of tasks, sessions, agreements and weekly history.

- **Buddy**: an ESP32-S3 board with a 480×480 AMOLED inside a 3D-printed figure (the screen is its belly). It shows session status, usage and extras, and lets you approve or deny low-risk permission prompts.
- **Hilo**: a macOS app with a CLI and an MCP server. It includes `hilod`, the daemon that receives Claude Code hooks and talks to the buddy over BLE.

> **Status:** working end to end on one Mac and the board; still a development build (no installer, no notarization). Per-phase status: [roadmap](docs/product/roadmap.md).

## What you need

| | Requirement | Notes |
| :--- | :--- | :--- |
| Mac | macOS 14 or later, Apple silicon | Intel is untested |
| Toolchain | Xcode 26 **or** Command Line Tools 26 (Swift 6.2+) | `xcode-select --install` is enough; no Xcode project, no Homebrew |
| Claude Code | The `claude` CLI | Hilo's Setup hands you prompts to paste into a Claude Code session |
| Bluetooth | On | macOS asks once for `hilod`'s Bluetooth permission |
| Buddy | A board already flashed with the firmware | Building and flashing: [`firmware/README.md`](firmware/README.md) |

The Mac side has no third-party packages: nothing to install from npm, pip or brew to build and run Hilo. Node and pnpm are only for the contract tests in `shared/`, and ESP-IDF only for the firmware.

## Set up a Mac

```sh
git clone https://github.com/jaycorpstudios/clawd-body.git
cd clawd-body
scripts/doctor.sh             # checks this Mac; installs nothing
scripts/build-hilod.sh        # daemon + CLI, signed (asks for the login keychain password the first time)
scripts/build-hilo-app.sh     # bundles everything as hilo/.build/Hilo.app
scripts/desktop-shortcut.sh   # optional: a Hilo link on the Desktop that survives rebuilds
open hilo/.build/Hilo.app
```

The first build takes a few minutes. `build-hilod.sh` creates a self-signed "Hilo Local Signing" identity in the login keychain once, so macOS keeps `hilod`'s Bluetooth permission across rebuilds.

Everything else happens in **Hilo › Setup**, which opens by itself on a Mac that has never run it:

1. **Name this Mac** (Work, Home or your own). The buddy uses it to tell your Macs apart.
2. **Run hilod**: Start installs a LaunchAgent, so `hilod` also runs at every login. Allow Bluetooth when macOS asks.
3. **Claude Code hooks**: copy the prompt, paste it into a Claude Code session, check the diff and answer `ok`. Hooks load when a session starts, so open a new one afterwards.
4. **Pair the buddy**: hold the buddy's side button 5 s on its Home view, click Start pairing, type the 6-digit code it shows into the macOS dialog.
5. Optional: **usage** on the buddy (status line, same copy-a-prompt flow), buddy settings, a picture for this Mac, music.

Done when a new Claude Code session shows up in Hilo › Sessions and on the buddy.

The app, `hilod`, the hooks and the status line all point at this clone's `hilo/.build/Hilo.app`. If you move the clone, rebuild and redo steps 2, 3 and 5.

### Let an agent do it

Open Claude Code in the clone and ask it to set up this Mac for Hilo. [AGENTS.md](AGENTS.md#set-up-a-new-mac) tells it what to check, what to build and what to leave to you (anything it would install, and everything in Setup).

## Two Macs, one buddy

Each Mac has its own clone, its own build, its own `hilod` and its own data; nothing syncs between them. Set each one up as above, give them different names, and pair each Mac with the buddy separately. The buddy keeps both links at once and shows each Mac's sessions under its name; a third Mac is turned away while two are linked.

## Update

```sh
git pull
scripts/build-hilod.sh && scripts/build-hilo-app.sh
```

Then **Hilo › Setup › Run hilod › Restart**, so the LaunchAgent runs the new `hilod`. Quit and reopen the app.

## Uninstall

Setup › Run hilod › Stop (removes the LaunchAgent), remove the hooks and status line from `~/.claude/settings.json` (Setup's prompts leave a `settings.json.bak-hilo` backup), then `scripts/desktop-shortcut.sh remove` and delete the clone. Data lives in `~/Library/Application Support/Hilo`; logs in `~/Library/Logs/Hilo`.

## Troubleshooting

| Symptom | Check |
| :--- | :--- |
| Setup says "No hilo next to hilod" | Run `scripts/build-hilod.sh`, then `scripts/build-hilo-app.sh` again |
| `hilod` dies right after starting, or Start does nothing | Setup now says why. `launchctl print gui/$(id -u)/dev.hilo.hilod` with `last exit reason = OS_REASON_TCC` (and a `~/Library/Logs/DiagnosticReports/hilod-*.ips` with namespace TCC) means macOS aborted it for the Bluetooth permission: rebuild with the current `scripts/build-hilo-app.sh` and press Start. Start it from Setup or `hilo install`, never a terminal: there macOS checks the terminal app, which has no Bluetooth usage description |
| Hilo.app does not open (`open` fails with -600) or comes back after force-quit | An app built before 2026-10-29 had `hilod` in `Contents/MacOS`, so macOS took it for the app. Rebuild both (`scripts/build-hilod.sh`, `scripts/build-hilo-app.sh`) and run `hilo/.build/Hilo.app/Contents/MacOS/hilo install`, which points the LaunchAgent at `Contents/Helpers/hilod` |
| Buddy never connects | Bluetooth permission for `hilod` in System Settings › Privacy & Security › Bluetooth; `~/Library/Logs/Hilo/hilod.log` |
| No sessions in Hilo | Setup › Claude Code hooks must be green, and the session must have started after the hooks were added |
| `codesign` keeps asking for a password | Click "Always Allow" on the keychain prompt |
| `codesign` fails with `errSecInternalComponent` on the first build | The keychain could not show its prompt (e.g. an agent ran the script). Run `scripts/build-hilod.sh` from your own terminal once and answer "Always Allow" |

## Repository

| Path | What it is |
| :--- | :--- |
| [`AGENTS.md`](AGENTS.md) | Map for coding agents (`CLAUDE.md` mirrors it) |
| [`docs/`](docs/README.md) | Product, architecture, component specs, flows, security, open questions |
| [`shared/`](shared/README.md) | Event contract schema, fixtures and `buddy-emit` terminal tool |
| [`daemon/`](daemon/README.md) | `hilod` daemon and `hilo` CLI (Swift) |
| [`hilo/`](hilo/README.md) | Hilo macOS app (SwiftUI) |
| [`firmware/`](firmware/README.md) | Buddy firmware (ESP-IDF + LVGL 9) |
| [`prototypes/`](prototypes/README.md) | Approved UI references: device simulator and Hilo screens |
| [`scripts/`](scripts) | Builds, tests, `doctor.sh` and `desktop-shortcut.sh` |

## Development

```sh
scripts/swift-test.sh        # daemon and store tests
scripts/hilod-e2e.sh         # hook → buddy decision round trip, no board needed (needs Node)
pnpm install && pnpm test    # contract tests in shared/ (Node 24, pnpm)
scripts/firmware-test.sh     # firmware model on the host (needs ESP-IDF for cJSON)
```

Open `prototypes/buddy-sim.html` in a browser to see the device UI without a board.

## Weekly summary with Claude Code

Hilo stores no API keys. With the Hilo MCP server registered (`claude mcp add hilo -- <repo>/hilo/.build/Hilo.app/Contents/MacOS/hilo mcp`), ask Claude Code to "draft my Hilo week", or add this as `~/.claude/commands/hilo-week.md` and run `/hilo-week`:

```markdown
Read hilo_week_summary. For each project with activity, write one plain paragraph (what moved, what closed, what is next; no lists, under 120 words) and save it with hilo_save_week_summary using the week_start it printed. Then tell me which projects you drafted.
```

The drafts show in Hilo › Week, editable, and go into Export .md.

## Security model in one paragraph

The Mac pushes events; the buddy only displays them and returns decisions. The buddy never stores credentials. BLE requires authenticated pairing (LE Secure Connections with passkey). The buddy approves only what it shows whole, and high-risk actions need a 3 s hold plus a confirming tap, and every decision coming from the buddy is validated by the daemon. Details: [`docs/security/`](docs/security/README.md).

## Disclaimer

Independent hobby project. Not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.

## License

[MIT](LICENSE)
