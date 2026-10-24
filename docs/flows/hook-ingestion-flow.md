# Hook ingestion flow

```mermaid
sequenceDiagram
    participant CC as Claude Code session
    participant H as Hook command
    participant D as hilod
    participant DB as SQLite
    participant B as Buddy (0..2 links)

    CC->>H: hook fires (session start/end, tool use, stop, notification…)
    H->>D: forward payload over local IPC
    D->>D: normalize to contract event, add id/ts/host
    D->>DB: append session / session_step
    alt buddy linked
        D-->>B: event (notify)
    else no buddy
        D->>D: keep state for next snapshot
    end
    H-->>CC: exit (non-blocking hooks return immediately)
```

## Notes

- Permission and question hooks are **blocking**; they follow the [remote decision flow](remote-decision-flow.md).
- The daemon must work without any buddy linked; Hilo keeps capturing.
- Logs never store full diffs or environment variables.
- **Pending to define** ([open questions › daemon](../plans/open-questions.md#daemon)): IPC transport and its permissions (e.g. a user-only Unix socket), behavior when `hilod` is not running (hook must fail open to the normal Mac prompt, never block Claude Code), mapping table from each Claude Code hook event to contract types — verify against current Claude Code hook docs.
