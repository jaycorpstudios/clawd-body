# Hilo Buddy

A desk companion that shows what your Claude Code sessions are doing, plus **Hilo**, a local macOS app that keeps track of tasks, sessions, agreements and weekly history.

- **Buddy**: an ESP32-S3 board with a 480×480 AMOLED inside a 3D-printed figure (the screen is its belly). It shows session status, usage and extras, and lets you approve or deny low-risk permission prompts.
- **Hilo**: a macOS app with a CLI and an MCP server. It includes `hilod`, the daemon that receives Claude Code hooks and talks to the buddy over BLE.

> **Status:** phase 3 in progress. Contract in [`shared/`](shared/README.md); `hilod` handles Claude Code hooks and remote decisions in [`daemon/`](daemon/README.md), BLE not yet. Firmware boots the display; app not started.

## Repository

| Path | What it is |
| :--- | :--- |
| [`AGENTS.md`](AGENTS.md) | Map for coding agents (`CLAUDE.md` mirrors it) |
| [`docs/`](docs/README.md) | Product, architecture, component specs, flows, security, open questions |
| [`shared/`](shared/README.md) | Event contract schema, fixtures and `buddy-emit` terminal tool |
| [`daemon/`](daemon/README.md) | `hilod` daemon and `hilo` CLI (Swift) |
| [`firmware/`](firmware/README.md) | Buddy firmware (ESP-IDF + LVGL 9) |
| [`prototypes/`](prototypes/README.md) | Approved UI references: device simulator and Hilo screens |

## See the device UI

Open `prototypes/buddy-sim.html` in a browser. The console on the right fires the events a Mac would send over BLE; the screen and sounds react the way the firmware should.

## Weekly summary with Claude Code

Hilo stores no API keys. With the Hilo MCP server registered (`claude mcp add hilo -- <repo>/daemon/.build/release/hilo mcp`), ask Claude Code to "draft my Hilo week", or add this as `~/.claude/commands/hilo-week.md` and run `/hilo-week`:

```markdown
Read hilo_week_summary. For each project with activity, write one plain paragraph (what moved, what closed, what is next; no lists, under 120 words) and save it with hilo_save_week_summary using the week_start it printed. Then tell me which projects you drafted.
```

The drafts show in Hilo › Week, editable, and go into Export .md.

## Security model in one paragraph

The Mac pushes events; the buddy only displays them and returns decisions. The buddy never stores credentials. BLE requires authenticated pairing (LE Secure Connections with passkey). High-risk actions can only be approved on the Mac, and every decision coming from the buddy is validated by the daemon. Details: [`docs/security/`](docs/security/README.md).

## Disclaimer

Independent hobby project. Not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.

## License

[MIT](LICENSE)

---

Hilo Buddy is an independent project. It is not affiliated with or endorsed by Anthropic.
