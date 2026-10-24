# Event contract (Mac ⇄ Buddy)

Single source (planned): `shared/events.schema.json`. Draft today: [events.schema.json](events.schema.json). It comes from the event log of the approved simulator (`prototypes/buddy-sim.html`).

## Envelope

```json
{ "v": 1, "id": "01JB…", "ts": 1761330000, "host": "work", "type": "agent.task_done", "data": { } }
```

| Field | Rule |
| :--- | :--- |
| `v` | Contract version. Receivers reject unknown major versions. |
| `id` | Unique ULID per message. Receivers drop duplicates. |
| `ts` | Unix seconds at the sender. |
| `host` | Short, user-configured name of the sending Mac (e.g. `work`, `home`). Set on every Mac → buddy message. |
| `type` / `data` | One of the types below and its payload. |

Compact JSON, one message per event. Fragmentation over BLE MTU: see [ble-transport.md](ble-transport.md).

## Mac → Buddy

| type | data |
| :--- | :--- |
| `snapshot` | `{ sessions:[...], usage:{...}, hilo:{...}, media?:{...} }`. Sent on connect and reconnect; replaces all state for that `host`. |
| `session.start` | `{ session, project, task }` |
| `session.end` | `{ session }` |
| `agent.needs_permission` | `{ request_id, session, project, tool, detail, why?, diff?, cwd, risk:"low"\|"high", remote_allowed, expires_at }` |
| `agent.question` | `{ request_id, session, project, detail, options:[string], expires_at }` |
| `agent.permission_resolved` | `{ request_id, session, decision:"approved"\|"denied", via:"mac"\|"buddy" }` |
| `agent.task_done` | `{ session, summary }` |
| `agent.error` | `{ session, detail }` |
| `agent.step` | `{ session, kind, text }`. Optional; feeds "recent activity". |
| `usage.update` | `{ session_pct, weekly_pct, reset_in_min, tokens_today }` |
| `usage.window_reset` | `{}` |
| `hilo.task_changed` | `{ title, project, jira?, started_at }` |
| `media.now_playing` | `{ title, artist, length_s, position_s }` |

## Buddy → Mac

| type | data |
| :--- | :--- |
| `permission.decision` | `{ request_id, decision:"approve"\|"deny" }`. The daemon validates policy, expiry and single use. |
| `question.answer` | `{ request_id, choice_index, choice }` |
| `device.ack` | `{ request_id, seen:true }` |
| `device.snooze` | `{ request_id }` ("Later" on the device) |
| `device.battery` | `{ pct, charging }` |
| `device.sleep` / `device.wake` | `{ by }` |
| `device.pet_accessory` | `{ acc }` |

Naming: commands from the buddy use the imperative (`approve`/`deny`); state reported by the Mac uses the past tense (`approved`/`denied`).

The simulator also logs `ble.connected` / `ble.disconnected`. Those are local link-state events on each side, **not** wire messages.

## Rules

- An **approval** for a request with `risk:"high"` or `remote_allowed:false` is never accepted from the buddy, even if it arrives. A **deny** is always honored (the device shows "Deny" on high-risk prompts).
- A decision for a `request_id` that is already resolved or expired is ignored; the daemon replies with `agent.permission_resolved` carrying the real outcome.
- The buddy executes nothing. It only displays and answers.

Flows that use these messages: [remote decision](../flows/remote-decision-flow.md), [reconnect + snapshot](../flows/reconnect-snapshot-flow.md).

## Pending to define

See [open questions › contract](../plans/open-questions.md#contract): `snapshot` payload shape, question resolution message, replay window for `ts`, payload size limits, and JSON Schema coverage for every type.
