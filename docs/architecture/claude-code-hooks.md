# Claude Code hooks → contract

How `hilod` learns what Claude Code sessions do. Verified against the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) on 2026-10-25.

## Facts the design relies on

| Fact | Consequence |
| :--- | :--- |
| Every hook input carries `session_id`, `cwd`, `transcript_path`, `hook_event_name` | `session` = `session_id`; `project` derives from `cwd` |
| `PermissionRequest` runs only when Claude Code is about to prompt; it answers with `hookSpecificOutput.decision.behavior` = `allow` \| `deny` | The permission hook is the single place where remote approvals enter |
| A `PermissionRequest` hook that exits 2 or returns no `decision` leaves the normal prompt flow unchanged | Fail-open: if `hilod` is down or nobody decides, the Mac prompt takes over |
| A `PermissionRequest` `allow` does not override a matching deny rule | Claude Code's own deny rules stay authoritative over the buddy |
| `PreToolUse` on `AskUserQuestion` can answer it: `permissionDecision: "allow"` plus `updatedInput` echoing `questions` and adding `answers: { "<question text>": "<label>" }` | Questions **can** be answered from the buddy |
| Default timeout for `command` and `http` hooks is 600 s, configurable per hook | Matches the 10-minute request expiry |
| Hook types include `command` and `http` (POST of the event JSON) | Both can reach `hilod`; see transport below |
| The docs only describe a race between hooks and `canUseTool` / `--permission-prompt-tool`, not the interactive prompt | **Unverified:** whether the terminal prompt shows while a `PermissionRequest` hook is still waiting. If not, a long wait hides the Mac prompt |

## Mapping

| Hook event (matcher) | Blocking | Contract message |
| :--- | :---: | :--- |
| `SessionStart` | no | `session.start` (`task` from the linked Hilo task, else empty) |
| `SessionEnd` | no | `session.end` |
| `UserPromptSubmit` | no | `agent.step { kind: "plan" }` — the session is working again |
| `PostToolUse` | no | `agent.step` — `Read`/`Glob`/`Grep` → `read`, `Edit`/`Write` → `edit`, `Bash` → `run`, others → `plan` |
| `PostToolUseFailure` | no | `agent.step { kind: "err" }` |
| `PermissionRequest` | yes | `agent.needs_permission`; outcome → `agent.request_resolved` |
| `PreToolUse` (`AskUserQuestion`) | yes | `agent.question` when it is one single-select question with 2–4 options; otherwise only `agent.step { kind: "ask" }` and the question stays on the Mac |
| `Stop` | no | `agent.task_done { summary }` from `last_assistant_message` (trimmed to 300 chars) |
| `StopFailure` | no | `agent.error { detail }` from `error` |
| `Notification` | no | Not forwarded; `PermissionRequest` already covers prompts |

The buddy infers session status from the stream: `session.start` and `agent.step` → working, a pending request → waiting, `agent.task_done` → done, `agent.error` → error.

Usage (`usage.update`) has no hook source; see [open questions › daemon](../plans/open-questions.md#daemon).

## Transport

`command` hooks run `hilo hook`, which forwards stdin to `hilod` over a Unix socket (`~/Library/Application Support/Hilo/hilod.sock`, directory `0700`, socket `0600`); `hilod` also drops connections whose peer UID is not the owner's. If the socket is missing or the daemon does not answer, the command exits 0 with no output, which leaves Claude Code's normal flow untouched.

An `http` hook would remove the command, but a localhost port is reachable by every local user and process; the socket is limited to the owner by file permissions.
