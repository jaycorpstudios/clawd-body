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
| 3 | Requests vanish, and "answered on the Mac" shows late | Session B: signals verified, design proposed, build waits for OK |
| 4 | Longer commands and question notes on the buddy | **Done** (session B) |
| 5 | Pomodoro: choose work or break | **Done** (session B) |
| 6 | Session names (Claude's title, `/rename`, history) | Session C |
| 7 | Name, describe and file sessions from the app | Session C |
| 8 | Projects in the sidebar do nothing | Session D |

### 1. Request card (done)

Question and permission text was cut (command box 96 px, "why" 66 px) and buttons were small; a "Later" link sat right under Deny. Now the header and the Deny / Approve bar are fixed, everything else scrolls with a visible bar, buttons are 72 px, options ≥ 62 px with wrapping labels, and Details / Later are buttons at the end of the scroll. Spec: [device UI › request card](../components/device-ui.md#request-card-changed-2026-10-29-from-dogfooding).

### 2. High-risk approval (done)

Almost every real request was high (the low allowlist is tiny), so the buddy could approve nothing. Decided 2026-10-29: everything the buddy shows whole is approvable; high needs a 3 s hold plus a new tap within 4 s; a `detail` cut at 300 characters is Mac-only; `policy.json` `high_remote_approval: false` restores the old rule. Spec: [risk policy](../security/risk-policy.md). Follow-up: [device lock](open-questions.md#security) now matters more.

### 3. Requests vanish / late "answered" (session B: verified, design proposed)

- A held request goes back to the terminal after 10 s of input at the Mac, or at 600 s; the buddy then says "Answer it on the Mac".
- After the user answers in the terminal, the buddy keeps the session "waiting" until the next hook, which for an approved long command is `PostToolUse` when it ends (minutes).
- Build: find the earliest signal that the terminal prompt was answered (transcript writes, `Notification`, the status line refresh, `PreToolUse` of the next tool) and send a step at once; show handed-back sessions as "on the Mac", not "needs you". Verify each signal on a real session before relying on it; record findings in [Claude Code hooks](../architecture/claude-code-hooks.md).
- Later (design first): decide requests from Hilo.app too, so a request never has to leave the buddy while you are at the Mac.

Verified on a real session (2026-10-29, [Claude Code hooks › answering in the terminal](../architecture/claude-code-hooks.md#answering-in-the-terminal-verified-2026-10-29)):

- The status line refreshes 60–160 ms after any terminal answer (approve, deny, question) and not while a prompt waits; it is the earliest signal every time, and for an approval the only one until `PostToolUse`.
- The terminal prompt shows about 0.6 s into `PermissionRequest`, while `hilod` still holds it. An answer there does not end the hook (approve leaves it waiting; deny kills it), so today the buddy keeps showing a request that was already answered.
- A denial in the terminal fires no hook at all: the session stays "waiting" until the next prompt.
- When the `PreToolUse` hold on `AskUserQuestion` hands back, Claude Code sends `PermissionRequest` for `AskUserQuestion`, which `hilod` would hold again as a permission.

Proposed design (not built; waiting for the user's OK):

1. `hilo statusline` also sends the status line's `session_id` to `hilod`. A tick for a session counts as "the prompt was answered" when that session has a request held for 2 s or more, or one handed back: the 2 s skips the refresh Claude Code makes right after writing the tool call.
2. On such a tick, `hilod` looks at the transcript tail about 0.5 s later: a "doesn't want to proceed" `tool_result` means denied, otherwise approved (an approval writes nothing). A held request closes with `agent.request_resolved` `via:"mac"` and that outcome, and its waiting hook returns no decision (Claude Code already moved on). A handed-back session gets `agent.step` "Approved on the Mac" (working) or `agent.task_done` "Denied on the Mac" (the turn ended).
3. Fallbacks without the status line: the held hook's socket closing (a terminal deny kills the hook) closes the request as denied; any later hook for the session (`PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit`, `Stop`) closes a request still held for it.
4. "On the Mac", not "needs you": a request kept in the terminal because the user is at the Mac leaves the session `waiting` without a pending request (the buddy already reads that as "on the Mac"; today it turns `working`), sent in a snapshot so older firmware understands it; Hilo › Sessions shows "on the Mac" for that state instead of "needs you". No contract change.
5. `PermissionRequest` for `AskUserQuestion` passes straight through: the question flow owns it.

### 4. Longer detail and question notes (done, session B)

- Optional `detail_full` (up to ~2000 characters) next to `detail`; the card shows it and the 300-character cut stops making most long commands Mac-only. Firmware buffer in PSRAM.
- Optional option descriptions for questions (`AskUserQuestion` sends them; today they are dropped), shown under each option in the scroll.
- Maybe: a multi-select question, or several questions in one request (today those stay on the Mac).

Built 2026-10-29: `detail_full` (up to 2000 characters and 6000 bytes, line breaks kept) travels only when `detail` was cut; only a command longer than that is Mac-only now. `hilod` keeps every permission message under 8 KB (drops the diff, then `detail_full`), and a snapshot drops `detail_full` before whole sessions; either way the request turns Mac-only. The buddy keeps it in the model's PSRAM block (6001 bytes per request) and shows it on the card and in Details. `option_descriptions` (one per option, 200 characters) show under each option. Render `request-detail-full*`, `question-descriptions*`. **Old firmware would offer to approve the cut `detail`: flash the buddy before updating `hilod`.**

### 5. Pomodoro start choice (done, session B)

Today the next phase is fixed (work → break → work). Build: from stopped or paused, start either **Work** or **Break**; on the buddy (two start buttons while stopped), in Hilo › Focus and the `pomodoro` socket op. Additive: `PomodoroState.phase` already exists; a start with a chosen phase is a new optional field, older peers keep their order.

Built 2026-10-29: no wire change at all (a started phase is just `phase` + `running` with a new `updated_at`). The socket op takes `{"action":"toggle","phase":"break"}`; while running it pauses like any toggle, so an older `hilod` that ignores `phase` agrees. Buddy: **▶ Work** / **▶ Break** pills replace play while the next phase has not begun (stopped, or paused at full length after one ended). Hilo › Focus: **Start work** / **Start break**, plus Resume when paused mid-phase.

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
