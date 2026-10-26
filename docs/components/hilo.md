# Hilo (macOS app, CLI and MCP)

Visual reference approved as direction: `prototypes/hilo/`. Dark theme only, with the same animated characters as the buddy.

## Decisions taken

- macOS only. Data **kept per machine**, no sync.
- **Window** UI (no menu-bar extra for now).
- **`hilo` CLI** and **MCP server** so Claude Code can read and write.
- **SQLite** as source of truth, with **Markdown export**.
- **Jira optional**, configured per project.
- Automatic capture: Claude Code sessions (via `hilod`), git (commits and branch) and active time (pauses after 5 min without activity).

## Stack (implemented)

- SwiftUI app in [`hilo/`](../../hilo/README.md), built with SwiftPM and bundled by `scripts/build-hilo-app.sh` (no Xcode project needed).
- One SQLite file per Mac, `~/Library/Application Support/Hilo/hilo.sqlite`, WAL mode, system `libsqlite3` (no third-party packages). `hilod` writes sessions and steps; the app and the CLI write tasks and agreements. Schema and queries live in `HiloStore` (`daemon/Sources/HiloStore`).
- The buddy's Hilo card (`snapshot.hilo`) is built from the store: the most recently started task in progress, the next three tasks, and today's confirmed agreements.

## Screens

| Screen | Prototype | Contents |
| :--- | :--- | :--- |
| **Today** | `Main.dc.html` | Quick task capture; tasks grouped as *In progress*, *Next*, *Done today* (project, Jira ticket, meta); selected task detail: notes, linked sessions with avatar and status, branch commits, linked agreements |
| **Sessions** | `Sessions.dc.html` | Table of this Mac's sessions (avatar, status, linked task, Warp tab, duration, tokens, last action); banner when a session needs you; detail with timeline and `claude --resume <id>`; automatic-capture status panel |
| **Week** | `Week.dc.html` | Totals (active time, tasks closed, sessions, agreements); per-project summary drafted by Claude and editable; hours per project and per day; closed tasks; Markdown copy/export |
| **Agreements** | `Agreements.dc.html` | Log by date with project, context, origin (meeting, session, manual) and linked task; **To confirm** column with agreements Claude detected in sessions — nothing enters the log without confirmation |
| **Resume context** | `Resume.dc.html` | Per project: where you left off, suggested next step, open threads, files touched, recent agreements, commands to get back in |

Shared chrome: top bar with ⌘K search, buddy status with its pet, and the Mac's name; sidebar with a "Your buddy" card, sections, projects and the note "Data from this Mac only · SQLite".

## Data model (draft)

| Table | Columns |
| :--- | :--- |
| `project` | `id, name, color, jira_key?, repo_paths[]` |
| `task` | `id, project_id, title, notes, status[todo\|doing\|done], jira_ref?, created_at, done_at?` |
| `session` | `id, project_id, task_id?, claude_session_id, warp_tab?, started_at, ended_at?, status, tokens` |
| `session_step` | `session_id, ts, kind[plan\|read\|edit\|run\|ask\|ok\|deny\|err], text` |
| `commit` | `repo, hash, branch, msg, ts, task_id?` |
| `agreement` | `id, project_id, task_id?, text, context, origin[meeting\|session\|manual], status[confirmed\|pending], ts` |
| `activity` | `ts_start, ts_end, project_id?` |

## CLI (draft)

`hilo add "…" [-p project]` · `hilo done <id>` · `hilo agree "…"` · `hilo resume <project>` · `hilo week [--md]` · `hilo link <session> <task>`

## MCP tools (draft)

| Tool | Notes |
| :--- | :--- |
| `hilo.resume(project)` | Same content as the Resume context screen |
| `hilo.add_task(...)` | |
| `hilo.log_agreement(..., status="pending")` | Claude only proposes; the user confirms |
| `hilo.current_task()` | |
| `hilo.week_summary(week)` | |

## Pending to define

See [open questions › Hilo](../plans/open-questions.md#hilo): app stack, automatic session ↔ task linking (by directory, branch or a prompt at start), how the weekly summary is drafted without storing API keys, Jira credential storage, project hue/accessory assignment, distribution and signing.
