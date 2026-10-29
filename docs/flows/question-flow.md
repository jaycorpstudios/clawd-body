# Question flow

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant D as hilod
    participant B as Buddy

    CC->>D: question to the user (text + 2–4 options)
    D-->>B: agent.question {request_id, options, option_descriptions?, expires_at}
    B->>B: show options as buttons, each with its description
    alt answered on the buddy
        B->>D: question.answer {request_id, choice_index, choice}
        D->>D: validate pending, not expired, single use, choice in options
        D-->>CC: deliver answer
        D-->>B: agent.request_resolved {outcome: answered, via: buddy}
    else answered on the Mac
        D-->>B: agent.request_resolved {outcome: answered, via: mac}
    else snoozed
        B->>D: device.snooze {request_id}
    else expires
        D-->>B: agent.request_resolved {outcome: expired, via: timeout}
    end
```

## Notes

- Questions have no risk level; any validated answer from a bonded buddy is accepted.
- The answer goes back through the `PreToolUse` hook: `permissionDecision: "allow"` and `updatedInput` echoing the questions plus `answers: { "<question>": "<label>" }` (see [Claude Code hooks](../architecture/claude-code-hooks.md)). Covered by `CoordinatorPhase4Tests` and `scripts/hilod-e2e.sh`; a real session taking the answer is still on the [hardware checklist](../plans/testing-strategy.md#remote-decisions-phase-4).
- Only one single-select question with 2–4 options reaches the buddy; anything else stays on the Mac.
