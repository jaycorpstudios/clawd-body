# Question flow

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant D as hilod
    participant B as Buddy

    CC->>D: question to the user (text + 2–4 options)
    D-->>B: agent.question {request_id, options, expires_at}
    B->>B: show options as buttons
    alt answered on the buddy
        B->>D: question.answer {request_id, choice_index, choice}
        D->>D: validate pending, not expired, single use, choice in options
        D-->>CC: deliver answer
    else answered on the Mac
        D-->>B: resolution message (pending to define)
    else snoozed
        B->>D: device.snooze {request_id}
    end
```

## Notes

- Questions have no risk level; any validated answer from a bonded buddy is accepted.
- **Pending to define** ([open questions › contract](../plans/open-questions.md#contract)): the message that tells the buddy a question was resolved elsewhere (today only `agent.permission_resolved` exists), and whether Claude Code hooks can inject an answer for a question at all — verify before committing to phase 4.
