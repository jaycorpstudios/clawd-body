# Remote decision flow (permissions)

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant H as Permission hook
    participant D as hilod
    participant B as Buddy
    participant M as Mac prompt

    CC->>H: permission request (tool, command, cwd)
    H->>D: forward and wait
    D->>D: classify with risk policy → risk, remote_allowed, expires_at
    D-->>B: agent.needs_permission
    B->>B: show screen (Hold to approve / Deny only if high risk)
    alt decided on the buddy
        B->>D: permission.decision {request_id, approve|deny}
        D->>D: validate (see below)
        D-->>H: allow / deny
        D-->>B: agent.request_resolved {outcome, via: buddy}
    else decided on the Mac first
        M->>D: resolved on the Mac
        D-->>B: agent.request_resolved {outcome, via: mac}
        Note over B,D: a late buddy decision is ignored
    else expires
        D-->>H: no decision → fall back to the Mac prompt
        D-->>B: agent.request_resolved {outcome: expired, via: timeout}
    end
    H-->>CC: result
```

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
- **Pending to define** ([open questions › daemon](../plans/open-questions.md#daemon)): how the hook learns that the user answered in the terminal, whether the Claude Code hook timeout allows a 10-minute wait, and the exact fallback on expiry.
