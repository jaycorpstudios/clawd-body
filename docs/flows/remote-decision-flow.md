# Remote decision flow (permissions)

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant H as Permission hook
    participant D as hilod
    participant B as Buddy

    CC->>H: permission request (tool, command, cwd)
    H->>D: forward and wait (user away, see mode below)
    D->>D: classify with risk policy → risk, remote_allowed, expires_at
    D-->>B: agent.needs_permission
    B->>B: show screen (Hold to approve / Deny only if high risk)
    alt decided on the buddy
        B->>D: permission.decision {request_id, approve|deny}
        D->>D: validate (see below)
        D-->>H: allow / deny
        D-->>B: agent.request_resolved {outcome, via: buddy}
    else user returns to the Mac, or expires
        D-->>H: no decision → terminal prompt appears
        D-->>B: agent.request_resolved {outcome: expired, via: timeout}
        Note over B,D: a late buddy decision is ignored
    end
    H-->>CC: result
```

## Remote-decision mode

The permission hook holds only while the user is away from the Mac. While it holds, Claude Code shows no terminal prompt.

```mermaid
flowchart TD
    R([PermissionRequest arrives]) --> P{User present at this Mac?<br/>input in the last N min, screen unlocked}
    P -->|yes| Show[send agent.step kind ask<br/>no actionable request] --> Now([hook returns no decision at once<br/>terminal prompt appears])
    P -->|no| Hold[send agent.needs_permission<br/>hook holds up to expires_at] --> W{first of}
    W -->|buddy decision, validated| Out([hook returns allow / deny])
    W -->|user returns to the Mac| Now
    W -->|expires| Now
```

- Present: nothing on the buddy can be decided, because the hook has already handed the prompt to the terminal. The buddy only logs the step.
- Away: the daemon polls presence while holding. Coming back to the Mac, or reaching `expires_at`, releases the hook to the terminal prompt and closes the request on the buddy with `agent.request_resolved { outcome: "expired", via: "timeout" }`. The session stays `waiting` with nothing to answer: the buddy says "Answer it on the Mac" until the next step from that session (#19). While the buddy shows the request (its `device.ack` came in the last 30 s), coming back means 10 s of continuous input on the Mac (input within every 3 s), so a mouse nudge while reaching for the buddy does not take the request away (#21, decided 2026-10-27).
- The same mode applies to questions (`PreToolUse` on `AskUserQuestion`).

## Daemon validation

```mermaid
flowchart TD
    In([permission.decision arrives]) --> Bonded{From a bonded,<br/>encrypted link?}
    Bonded -->|no| Drop([drop + log])
    Bonded -->|yes| Pending{request_id pending<br/>for this host?}
    Pending -->|no| Reply([reply agent.request_resolved<br/>with real state])
    Pending -->|yes| Exp{expired?}
    Exp -->|yes| Reply
    Exp -->|no| Used{already used?}
    Used -->|yes| Reply
    Used -->|no| Policy{remote_allowed<br/>and risk = low?}
    Policy -->|no, decision = deny| Deny([accept deny])
    Policy -->|no, decision = approve| Reject([reject + log])
    Policy -->|yes| Accept([accept decision, mark used,<br/>log via: buddy])
```

## Notes

- A **deny** from the buddy is always safe to honor, even for high-risk requests; an **approve** is honored only for `remote_allowed` + `low`.
- Default expiry: 10 min. "Later" on the device (`device.snooze`) keeps the request pending; the buddy reminds every 25 s.
- Every outcome is logged in the session timeline with `via`.
- **Pending to define** ([open questions › daemon](../plans/open-questions.md#daemon)): idle threshold for "away", and a hardware check that the terminal prompt stays hidden while the hook holds.
