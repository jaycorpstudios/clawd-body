# Daemon `hilod` (BLE bridge and ingestion)

Runs on each Mac as a login item. Connects Claude Code, Hilo and the buddy.

## Responsibilities

1. **Claude Code hook ingestion**: session start and end, permission request, question to the user, task done, error and tool use. Normalizes each one to the [event contract](../architecture/event-contract.md). Flow: [hook ingestion](../flows/hook-ingestion-flow.md).
2. **Usage**: 5 h window percentage, weekly percentage and tokens today. Never uses account credentials. Percentages and reset come from the `rate_limits` Claude Code gives its status line (`hilo statusline` forwards them); tokens today, opt-in, from the local transcripts. Details: [daemon README › Usage](../../daemon/README.md#usage).
3. **Persistence** in local SQLite, shared with Hilo ([hilo.md](hilo.md)).
4. **BLE bridge** (central on the Mac, the buddy is the peripheral):
   - Discovers and connects only to bonded buddies.
   - Sends events and, on reconnect, a full `snapshot`.
   - Receives decisions and device events.
5. **Remote decisions** ([flow](../flows/remote-decision-flow.md)):
   - Only for requests marked `remote_allowed: true` by the [risk policy](../security/risk-policy.md) (allowlist per tool and command pattern, configurable per project).
   - Validates pending `request_id`, expiry (default 10 min) and single use.
   - If the request was already resolved on the Mac, drops the decision and tells the buddy with `agent.request_resolved`.
   - Logs every decision in the session timeline with `via: "buddy"` or `via: "mac"`.
6. **MCP and CLI**: backend for Hilo ([hilo.md](hilo.md)).

## Security

- BLE with LE Secure Connections and passkey on first pairing. Trusted-device list revocable from Hilo.
- No secret ever travels to the buddy.
- Messages carry `id`, `ts` and `v`. The daemon rejects duplicates and stale messages.
- Local logs without sensitive content: no full diffs, no environment variables.

Threats and mitigations: [threat-model.md](../security/threat-model.md).

## Requirements

- Works without a buddy connected (Hilo keeps capturing).
- Low CPU and battery use when idle.
- Starts with the user session and recovers by itself if Bluetooth restarts.

## Implementation

Code, build and local run: [`daemon/README.md`](../../daemon/README.md). Done: hook ingestion, risk policy defaults, request registry, presence-based hold, Unix socket IPC, BLE central (verified on the board), SQLite store, MCP, usage. Not yet: revoking a buddy from Hilo.

## Pending to define

See [open questions › daemon](../plans/open-questions.md#daemon): policy file location and format, hook ↔ daemon IPC and blocking behavior, hook timeout vs. `expires_at`, answering questions from a hook.
