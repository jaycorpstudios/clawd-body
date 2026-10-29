# Claude Code hooks → contract

How `hilod` learns what Claude Code sessions do. Verified against the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) on 2026-10-25, and against a real session on 2026-10-29 ([answering in the terminal](#answering-in-the-terminal-verified-2026-10-29)).

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
| The terminal prompt shows about 0.6 s after `PermissionRequest` starts, while the hook still waits (verified 2026-10-29, below) | A request held for the buddy is also answerable in the terminal the whole time; a terminal answer takes effect at once and does not cancel the hook (an approval leaves it waiting), so `hilod` must notice it some other way |
| When the `PreToolUse` hook on `AskUserQuestion` returns no decision, Claude Code then sends `PermissionRequest` for `AskUserQuestion`, and the question shows in the terminal only from there (verified 2026-10-29) | The question is held twice: once as a question, then as a permission for `AskUserQuestion` |

## Mapping

| Hook event (matcher) | Blocking | Contract message |
| :--- | :---: | :--- |
| `SessionStart` | no | `session.start` (`task` from the linked Hilo task, else empty) |
| `SessionEnd` | no | `session.end` |
| `UserPromptSubmit` | no | `agent.step { kind: "plan" }` — the session is working again |
| `PostToolUse` | no | `agent.step` — `Read`/`Glob`/`Grep` → `read`, `Edit`/`Write` → `edit`, `Bash` → `run`, others → `plan` |
| `PostToolUseFailure` | no | `agent.step { kind: "err" }` |
| `PermissionRequest` | yes | `agent.needs_permission`; outcome → `agent.request_resolved` |
| `PermissionRequest` (`AskUserQuestion`) | no | Nothing: it follows the question's own `PreToolUse` hold, which already handed it back to the terminal |
| `PreToolUse` (`AskUserQuestion`) | yes | `agent.question` when it is one single-select question with 2–4 options; otherwise only `agent.step { kind: "ask" }` and the question stays on the Mac |
| `Stop` | no | `agent.task_done { summary }` from `last_assistant_message` (trimmed to 300 chars) |
| `StopFailure` | no | `agent.error { detail }` from `error` |
| `Notification` | no | Not forwarded; `PermissionRequest` already covers prompts. Its `permission_prompt` comes about 6 s after the prompt shows, so it says nothing about an answer |

The buddy infers session status from the stream: `session.start` and `agent.step` → working, a pending request → waiting, `agent.task_done` → done, `agent.error` → error.

## Answering in the terminal (verified 2026-10-29)

What reaches `hilod` when the user answers a prompt in the terminal. Claude Code 2.1.312, `--permission-mode default`, run under `expect` with a probe hook on every event (a `PermissionRequest` hook that waits 3–20 s and then returns no decision, like a hand-back), the status line command and a watcher on the transcript, all logging with millisecond timestamps. Each case ran once or twice; the order held every time.

| Answer | First signal | Then |
| :--- | :--- | :--- |
| Approve, after the hook handed back | status line refresh, +80 ms | nothing (no hook, no transcript line) until `PostToolUse` when the command ends (+15.7 s for a `sleep 15`) |
| Approve, while the hook still waits | status line refresh, +72 ms | the command runs at once; the hook is **not** killed and keeps waiting; its later answer is ignored |
| Deny (Esc), after the hand-back | status line refresh, +156 ms | a transcript `tool_result` "The user doesn't want to proceed…" +267 ms; **no hook at all** (no `PostToolUse*`, no `Stop`): the turn just ends |
| Deny (Esc), while the hook still waits | the hook process gets a signal, +100 ms; status line +114 ms | as above |
| Question answered in the terminal | `PostToolUse` (`AskUserQuestion`), +49 ms; status line +61 ms | transcript `tool_result` +226 ms, `Stop` when the turn ends |

Other observations:

- No status line refresh happened while a prompt sat unanswered (3–10 s in these runs). One does come about 0.3 s after Claude Code writes a tool call, i.e. right when a `PermissionRequest` or `PreToolUse` starts, before anyone could answer.
- Approving writes nothing to the transcript, so a transcript watcher cannot see it; a denial is visible there about 0.25 s later.
- `PreToolUse` for the next tool comes only after the approved tool ends, never earlier than `PostToolUse`.
- So the status line is the earliest signal for every answer, and the only one for an approval until the tool ends. It needs the status line to go through `hilo statusline` (Hilo › Setup), and its input carries `session_id`.

How `hilod` uses it (built 2026-10-29):

- `hilo statusline` sends `session_id` and `transcript_path` (socket op `status-tick`) before it forwards usage. A tick counts as "the prompt was answered" only for a session with a request held, or handed back, for 2 s or more, which skips the refresh right after the tool call is written.
- About 0.5 s after such a tick `hilod` reads the transcript tail: a rejected `tool_result` for that tool means denied, anything else approved. A held request closes with `agent.request_resolved` `via:"mac"`; its hook returns no decision. A handed-back session gets `agent.step` "Approved on the Mac" or "Denied on the Mac"; a denial also sets the session idle, since no hook follows.
- Without the status line: the held hook process dying (`LOCAL_PEERPID` + `kill(pid, 0)`) means a terminal deny; any later hook for the session (`PostToolUse*` approves, `UserPromptSubmit`, `Stop*`, `SessionEnd` deny) closes what is still open.
- A request kept in the terminal because the user is at the Mac leaves the session `waiting` without a pending request (a snapshot), so the buddy reads "on the Mac" in the info colour, not "needs you".

Usage (`usage.update`) has no hook source: it comes from the status line's `rate_limits` and, opt-in, the local transcripts ([daemon README › Usage](../../daemon/README.md#usage)).

## Transport

`command` hooks run `hilo hook`, which forwards stdin to `hilod` over a Unix socket (`~/Library/Application Support/Hilo/hilod.sock`, directory `0700`, socket `0600`); `hilod` also drops connections whose peer UID is not the owner's. If the socket is missing or the daemon does not answer, the command exits 0 with no output, which leaves Claude Code's normal flow untouched.

An `http` hook would remove the command, but a localhost port is reachable by every local user and process; the socket is limited to the owner by file permissions.
