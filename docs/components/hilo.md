# Hilo (macOS app, CLI and MCP)

Visual reference approved as direction: `prototypes/hilo/`. Dark theme only, with the same animated characters as the buddy: `PetView` ports `drawPet` and `drawAcc`, and a project's hue and accessory come from the same hash of its name as on the buddy (`PetLook`, matching `bm_project_look`).

## Decisions taken

- macOS only. Data **kept per machine**, no sync.
- **Window** UI (no menu-bar extra for now).
- **`hilo` CLI** and **MCP server** so Claude Code can read and write.
- **SQLite** as source of truth, with **Markdown export**.
- **Jira optional**, configured per project.
- Automatic capture: Claude Code sessions (via `hilod`), git (commits and branch) and active time (pauses after 5 min without activity).

## Stack (implemented)

- SwiftUI app in [`hilo/`](../../hilo/README.md), built with SwiftPM and bundled by `scripts/build-hilo-app.sh` (no Xcode project needed).
- **Window chrome**: the top bar is the title bar: drag it to move the window; a double click follows System Settings › Desktop & Dock ("double-click a window's title bar to": zoom, minimize or do nothing, read from `AppleActionOnDoubleClick`). Liquid Glass on the bar on macOS 26, `.ultraThinMaterial` on 14–15; content scrolling under the bar fades through a progressive blur (macOS 15+, where scroll position is observable). ⌘1…⌘7 jump to each section (shown in the sidebar tooltips), sections cross-fade, sidebar rows highlight on hover, the window remembers its size and position (`HiloMain` frame autosave) and supports full screen. `HILO_SNAPSHOT` captures flat colors instead of glass, which `cacheDisplay` cannot draw.
- One SQLite file per Mac, `~/Library/Application Support/Hilo/hilo.sqlite`, WAL mode, system `libsqlite3` (no third-party packages). `hilod` writes sessions and steps; the app and the CLI write tasks and agreements. Schema and queries live in `HiloStore` (`daemon/Sources/HiloStore`).
- **Automatic capture** (in `hilod`): each session remembers its git repo (from the hook's `cwd`). Every 60 s `hilod` runs `git log` on the current branch of the repos of the last week's sessions, keeping only commits by the repo's `user.email`, and stores new ones in `git_commit`; a new commit links to its project's task in progress when there is exactly one (same rule as sessions). **Active time** is kept per project in `activity` spans: every message for a session and every captured commit extends the project's last span, and a gap over 5 min starts a new one (the pause). Today shows active time in its summary and commits in the task detail; Week shows active time and commits per project; Resume lists recent commits.
- The buddy's Hilo card (`snapshot.hilo`) is built from the store: the most recently started task in progress, the next three tasks, and today's confirmed agreements.

## Screens

| Screen | Prototype | Contents |
| :--- | :--- | :--- |
| **Today** | `Main.dc.html` | Quick task capture; tasks grouped as *In progress*, *Next*, *Done today* (project, Jira ticket, meta); selected task detail: notes, linked sessions with avatar and status, branch commits, linked agreements |
| **Sessions** | `Sessions.dc.html` | Table of this Mac's sessions (avatar, status, linked task, Warp tab, duration, tokens — from the local transcripts when `tokens_from_transcripts` is on, otherwise "—" —, last action); banner when a session needs you; detail with timeline and `claude --resume <id>`; automatic-capture status panel |
| **Week** | `Week.dc.html` | Totals (active time, tasks closed, sessions, agreements); per-project summary drafted by Claude and editable; hours per project and per day; closed tasks; Markdown copy/export. **Implemented:** ‹ › (⌘[ ⌘]) walk back through past weeks, read with bounded queries (`weekReport(start:end:)`, active spans clipped at both ends); "Export .md" saves `week-YYYY-MM-DD.md` through a save panel, "Copy" keeps the clipboard path. The Claude-drafted summary is not built yet |
| **Agreements** | `Agreements.dc.html` | Log by date with project, context, origin (meeting, session, manual) and linked task; **To confirm** column with agreements Claude detected in sessions — nothing enters the log without confirmation |
| **Focus** | — (no prototype) | Pomodoro shared with the buddy through `hilod` (socket op `pomodoro`, state in `status`): the main pet, phase, time left, progress, Start/Pause (space) and Reset, work and break durations while stopped, and today's finished cycles. `hilod` flips phases on its own clock and records each finished work phase in `focus_cycle`, linked to the task in progress; the timer itself is saved in `focus_state` with those rows, so it survives a `hilod` restart without losing or repeating cycles. While Hilo.app runs it shows a macOS notification ("Break time" / "Back to work") at each phase end, with the buddy's alarm; a change made by hand and a phase that ended more than 30 s before the app saw it are not announced |
| **Resume context** | `Resume.dc.html` | Per project: where you left off, suggested next step, open threads, files touched, recent agreements, commands to get back in |
| **Setup** | — (no prototype) | Six steps: name this Mac (Work / Home presets or free text, normalized to the contract's `host` and saved in `config.json`; applied live through `hilod`'s socket op `host`, which drops the BLE link so the buddy rebinds it), run `hilod` (Start installs the LaunchAgent `dev.hilo.hilod` for the copy bundled in `Hilo.app`, so it also runs at login; Stop removes it; Restart reinstalls it; same code as `hilo install` / `uninstall`), pair the buddy (guided: hold 5 s, Start pairing, type the passkey in the macOS dialog; progress from socket ops `pair`, `pair-cancel` and `status`), usage (status line command to copy, transcript-token toggle), and the buddy's settings (sound, volume, brightness: the same controls as the buddy's top panel, sent with the socket op `settings` and shown from the buddy's own `device.settings`, so both always agree; disabled while the buddy is not connected), and this Mac's picture for the buddy's idle rotation (pick an image, zoom and drag it inside a square, saved as a ≤ 480 px PNG `face.png` next to `config.json`, never in the repo; socket op `face` makes `hilod` send it). Opens by itself when `config.json` does not exist yet |

Shared chrome: top bar with ⌘K search, buddy status with its pet, and the Mac's name; the Mac's name is the configured `host`; sidebar with a "Your buddy" card, sections, projects and the note "Data from this Mac only · SQLite".

## Data model (draft)

| Table | Columns |
| :--- | :--- |
| `project` | `id, name, color, jira_key?, repo_paths[]` |
| `task` | `id, project_id, title, notes, status[todo\|doing\|done], jira_ref?, created_at, done_at?` |
| `session` | `id, project_id, task_id?, claude_session_id, warp_tab?, started_at, ended_at?, status, tokens` |
| `session_step` | `session_id, ts, kind[plan\|read\|edit\|run\|ask\|ok\|deny\|err], text` |
| `git_commit` | `repo, hash, branch, message, ts, project_id?, task_id?` (implemented) |
| `agreement` | `id, project_id, task_id?, text, context, origin[meeting\|session\|manual], status[confirmed\|pending], ts` |
| `activity` | `project_id, ts_start, ts_end` (implemented; 5 min gap = pause) |
| `focus_cycle` | `id, ended_at, work_min, task_id?` (implemented; one row per finished Pomodoro work phase) |
| `focus_state` | `id = 1, json` (implemented; the current Pomodoro state as JSON, written with the cycles it finished) |

## CLI

`hilo today` · `hilo add "…" [-p project] [--start]` · `hilo start|done|todo <id>` · `hilo agree "…" [-p project]` · `hilo sessions` · `hilo link <session> <task>` · `hilo resume [project]` · `hilo week [--md]` · `hilo mcp` · `hilo install` / `uninstall`. Resume and the week summary are the same code as the MCP tools and Hilo › Week (`WeekReport` in `HiloStore`).

## MCP tools

`hilo mcp` serves these over stdio (MCP tool names cannot contain dots):

| Tool | Notes |
| :--- | :--- |
| `hilo_resume(project)` | Same content as the Resume context screen, as Markdown |
| `hilo_add_task(title, project?, start?)` | |
| `hilo_log_agreement(text, project?, context?)` | Always stored as `pending`; Claude only proposes, the user confirms in the app |
| `hilo_current_task()` | |
| `hilo_week_summary()` | Sessions, closed tasks and confirmed agreements per project |

Register it with Claude Code: `claude mcp add hilo -- <repo>/daemon/.build/release/hilo mcp`.

## Pending to define

See [open questions › Hilo](../plans/open-questions.md#hilo): app stack, automatic session ↔ task linking (by directory, branch or a prompt at start), how the weekly summary is drafted without storing API keys, Jira credential storage, project hue/accessory assignment, distribution and signing.
