# Event contract (Mac ⇄ Buddy)

Single source: [`shared/events.schema.json`](../../shared/events.schema.json) (JSON Schema 2020-12). It was derived from the event log of the approved simulator (`prototypes/buddy-sim.html`). Fixtures and the `buddy-emit` tool live next to it — see [`shared/README.md`](../../shared/README.md).

## Envelope

```json
{ "v": 1, "id": "01K8F3Z9QW4Y6R2M7N5P8T0V1X", "ts": 1761330000, "host": "work", "type": "agent.task_done", "data": { } }
```

| Field | Rule |
| :--- | :--- |
| `v` | Contract version. Receivers reject unknown major versions. |
| `id` | Unique ULID per message. Receivers drop duplicates. |
| `ts` | Unix seconds at the sender. |
| `host` | Short name of the sending Mac (`^[a-z0-9-]{1,16}$`, e.g. `work`, `home`). **Required** on every Mac → buddy message; absent from buddy → Mac. |
| `type` / `data` | One of the types below and its payload. |

Compact JSON, one message per event. Fragmentation over BLE MTU: see [ble-transport.md](ble-transport.md).

Senders produce exactly the schema: no extra fields in the envelope or any payload. A new optional field is a minor change; receivers built for an older minor ignore fields they do not know.

## Mac → Buddy

| type | data |
| :--- | :--- |
| `snapshot` | `{ sessions:[session], usage, hilo:{ current, next, agreements_today }, media? }`. Sent on connect and reconnect; replaces all state for that `host`. See below. |
| `session.start` | `{ session, project, task }` |
| `session.end` | `{ session }` |
| `agent.needs_permission` | `{ request_id, session, project, tool, detail, why?, diff?, cwd, risk:"low"\|"high", remote_allowed, expires_at }`. `risk:"high"` implies `remote_allowed:false`. |
| `agent.question` | `{ request_id, session, project, detail, options:[2–4 strings], expires_at }` |
| `agent.request_resolved` | `{ request_id, session, kind:"permission"\|"question", outcome, via:"mac"\|"buddy"\|"timeout", choice_index? }`. Closes any pending request; see below. |
| `agent.task_done` | `{ session, summary }` |
| `agent.error` | `{ session, detail }` |
| `agent.step` | `{ session, kind, text }`. `kind`: `plan` `read` `edit` `run` `ask` `ok` `deny` `err`. Optional; feeds "recent activity". |
| `usage.update` | `{ session_pct, weekly_pct, reset_in_min, tokens_today? }` |
| `usage.window_reset` | `{}` |
| `hilo.task_changed` | `{ title, project, jira?, started_at }` |
| `media.now_playing` | `{ title, artist, length_s, position_s }` |

### `snapshot`

| Key | Shape |
| :--- | :--- |
| `sessions` | Up to 8 of `{ session, project, task, status, since, tokens?, summary?, error?, steps?, pending_permission? \| pending_question? }`. `status`: `working` `waiting` `done` `error` `idle`. `steps`: last 5 `{ ts, kind, text }`. A pending request uses the same payload as `agent.needs_permission` / `agent.question`, so the buddy can show it again after a reconnect. |
| `usage` | Same as `usage.update`. |
| `hilo` | `current` (a `hilo.task_changed` payload or `null`), `next` (up to 3 `{ title, project, jira? }`), `agreements_today` (up to 3 strings). |
| `media` | Same as `media.now_playing`; omitted when nothing plays. |

A snapshot must fit the 8 KB message cap ([framing](ble-transport.md#framing)). The daemon trims in this order until it fits: steps, then diffs, then `why` / `summary` / `error`, then whole sessions from the lowest priority (`waiting` > `error` > `working` > `done` > `idle`). The worst case (8 sessions, each with a pending permission) fits after the third step; see `SessionStoreTests`.

### `agent.request_resolved`

| `outcome` | `kind` | `via` | Meaning |
| :--- | :--- | :--- | :--- |
| `approved` / `denied` | `permission` | `mac` or `buddy` | Permission decided |
| `answered` | `question` | `mac` or `buddy` | Question answered; `choice_index` required |
| `expired` | either | `timeout` | No longer answerable from the buddy; the Mac prompt takes over |

## Buddy → Mac

| type | data |
| :--- | :--- |
| `permission.decision` | `{ request_id, decision:"approve"\|"deny" }`. The daemon validates policy, expiry and single use. |
| `question.answer` | `{ request_id, choice_index, choice }` |
| `device.ack` | `{ request_id, seen:true }` |
| `device.snooze` | `{ request_id }` ("Later" on the device) |
| `device.battery` | `{ pct, charging }` |
| `device.sleep` / `device.wake` | `{ by: "touch"\|"button"\|"long_press"\|"idle" }` |
| `device.pet_accessory` | `{ acc }`: `none` `wizard` `shades` `headphones` `crown` `party` `band` `heart` |

Naming: commands from the buddy use the imperative (`approve`/`deny`); state reported by the Mac uses the past tense (`approved`/`denied`).

The simulator also logs `ble.connected` / `ble.disconnected`. Those are local link-state events on each side, **not** wire messages.

## Rules

- An **approval** for a request with `risk:"high"` or `remote_allowed:false` is never accepted from the buddy, even if it arrives. A **deny** is always honored (the device shows "Deny" on high-risk prompts).
- A decision for a `request_id` that is already resolved or expired is ignored; the daemon replies with `agent.request_resolved` carrying the real outcome.
- The buddy executes nothing. It only displays and answers.

Flows that use these messages: [remote decision](../flows/remote-decision-flow.md), [question](../flows/question-flow.md), [reconnect + snapshot](../flows/reconnect-snapshot-flow.md).

## Pending to define

See [open questions › contract](../plans/open-questions.md#contract): replay window for `ts`, byte budget per message (depends on BLE framing), and usage across Macs.
