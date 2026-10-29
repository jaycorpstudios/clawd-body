# Dogfooding feedback, 2026-10-29

A day of real use on the work Mac. Each item: what hurt, what we build, where it stands. Sessions are planned so each one ends with green tests and at most one flash of the buddy.

## Rules for every change from here on

- **Nothing breaks existing data.** SQLite changes are new entries in `Schema.migrations` (append only, `ALTER TABLE … ADD COLUMN` or new tables); no rewrite or drop of existing rows. Before applying a migration `hilod` copies the store (session C adds this).
- **Contract changes are additive.** New fields are optional; firmware ignores unknown keys. When a change makes old firmware drop a message (as `risk:"high"` with `remote_allowed:true` does), flash the buddy before updating `hilod` on any Mac.
- **Two Macs.** Hilo.app (with `hilod` inside) is also built on the work Mac. Any session that touches `daemon/` or `hilo/` ends with a reminder: `git pull`, `scripts/build-hilod.sh`, `scripts/build-hilo-app.sh`, restart `hilod` from Hilo › Setup.

## Items

| # | Item | Status |
| :--- | :--- | :--- |
| 1 | Request card readable and easy to hit | **Done** (session A) |
| 2 | High-risk approvable from the buddy | **Done** (session A) |
| 3 | Requests vanish, and "answered on the Mac" shows late | Session B |
| 4 | Longer commands and question notes on the buddy | Session B |
| 5 | Pomodoro: choose work or break | Session B |
| 6 | Session names (Claude's title, `/rename`, history) | Session C |
| 7 | Name, describe and file sessions from the app | Session C |
| 8 | Projects in the sidebar do nothing | Session D |

### 1. Request card (done)

Question and permission text was cut (command box 96 px, "why" 66 px) and buttons were small; a "Later" link sat right under Deny. Now the header and the Deny / Approve bar are fixed, everything else scrolls with a visible bar, buttons are 72 px, options ≥ 62 px with wrapping labels, and Details / Later are buttons at the end of the scroll. Spec: [device UI › request card](../components/device-ui.md#request-card-changed-2026-10-29-from-dogfooding).

### 2. High-risk approval (done)

Almost every real request was high (the low allowlist is tiny), so the buddy could approve nothing. Decided 2026-10-29: everything the buddy shows whole is approvable; high needs a 3 s hold plus a new tap within 4 s; a `detail` cut at 300 characters is Mac-only; `policy.json` `high_remote_approval: false` restores the old rule. Spec: [risk policy](../security/risk-policy.md). Follow-up: [device lock](open-questions.md#security) now matters more.

### 3. Requests vanish / late "answered" (session B)

- A held request goes back to the terminal after 10 s of input at the Mac, or at 600 s; the buddy then says "Answer it on the Mac".
- After the user answers in the terminal, the buddy keeps the session "waiting" until the next hook, which for an approved long command is `PostToolUse` when it ends (minutes).
- Build: find the earliest signal that the terminal prompt was answered (transcript writes, `Notification`, the status line refresh, `PreToolUse` of the next tool) and send a step at once; show handed-back sessions as "on the Mac", not "needs you". Verify each signal on a real session before relying on it; record findings in [Claude Code hooks](../architecture/claude-code-hooks.md).
- Later (design first): decide requests from Hilo.app too, so a request never has to leave the buddy while you are at the Mac.

### 4. Longer detail and question notes (session B)

- Optional `detail_full` (up to ~2000 characters) next to `detail`; the card shows it and the 300-character cut stops making most long commands Mac-only. Firmware buffer in PSRAM.
- Optional option descriptions for questions (`AskUserQuestion` sends them; today they are dropped), shown under each option in the scroll.
- Maybe: a multi-select question, or several questions in one request (today those stay on the Mac).

### 5. Pomodoro start choice (session B)

Today the next phase is fixed (work → break → work). Build: from stopped or paused, start either **Work** or **Break**; on the buddy (two start buttons while stopped), in Hilo › Focus and the `pomodoro` socket op. Additive: `PomodoroState.phase` already exists; a start with a chosen phase is a new optional field, older peers keep their order.

### 6. Session names (session C)

Claude Code writes `{"type":"ai-title","aiTitle":…}` (its own title) and `{"type":"custom-title","customTitle":…}` (`/rename`) into the session transcript, appending a new line on every change. `hilod` already reads the transcript (`TranscriptTokens`).

- Store: new `session_name` table (session, name, source `claude` / `rename` / `hilo`, ts) for the history, plus a display name on `session` (precedence: Hilo › rename > `/rename` > Claude's title > project).
- Read the newest title lines on each hook (tail only), record changes.
- Contract: optional `title` on `session.start` and snapshot sessions; the buddy shows it where it shows the project today (agents list, request card header).

### 7. Rename, describe and file sessions in the app (session C)

- Sessions view: edit the name (keeps `/rename` and Claude's names as history), a free-text description, and an optional manual project that overrides the repo-derived one.
- MCP: `hilo_session_describe` could let Claude fill the description; decide in session C.

### 8. Projects (session D)

Clicking a project in the sidebar does nothing. Build a Project view: its sessions (with the names from 6/7), tasks, agreements and active time this week; create a project by hand; move sessions between projects (item 7). Design the view as a prototype screen first and get it approved.

## Sessions

| Session | Scope | Components | Flash | Rebuild work Mac |
| :--- | :--- | :--- | :---: | :---: |
| A (2026-10-29) | Items 1, 2 | firmware, daemon, contract, docs | yes | yes |
| B | Items 3, 4, 5 | firmware, daemon, contract, Hilo › Focus | yes | yes |
| C | Items 6, 7 + store backup before migrations | daemon, store, contract, Hilo › Sessions, firmware (title) | yes | yes |
| D | Item 8 (prototype first) | Hilo, store | no | yes |
