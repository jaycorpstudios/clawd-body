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
| `snapshot` | `{ sessions:[session], usage, hilo:{ current, next, agreements_today }, media?, face?, pomodoro? }`. Sent on connect and reconnect; replaces all state for that `host`. See below. |
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
| `media.now_playing` | `{ title, artist, length_s, position_s, playing?, cover? }`. `playing:false` = paused; absent means playing (older senders). `cover`: `{ hash }` of the track's cover, once the Mac has it; see [covers](#covers) |
| `settings.set` | `{ sound?, volume?, brightness? }`, at least one. Asks the buddy to apply device settings; it answers with `device.settings`. See [device settings](#device-settings) |
| `host.face` | `{ hash, format:"rgb565", w, h, index, count, data }`: one chunk of this Mac's profile picture. See [faces](#faces) |
| `pomodoro.state` | `pomodoro`: the timer as set on this Mac. See [pomodoro](#pomodoro) |
| `media.cover` | `{ hash, format:"rgb565", w, h, index, count, data }`: one chunk of the playing track's cover, only in answer to `device.cover_request`. See [covers](#covers) |

### `snapshot`

| Key | Shape |
| :--- | :--- |
| `sessions` | Up to 8 of `{ session, project, task, status, since, tokens?, summary?, error?, steps?, pending_permission? \| pending_question? }`. `status`: `working` `waiting` `done` `error` `idle`. `steps`: last 5 `{ ts, kind, text }`. A pending request uses the same payload as `agent.needs_permission` / `agent.question`, so the buddy can show it again after a reconnect. |
| `usage` | Same as `usage.update`. |
| `hilo` | `current` (a `hilo.task_changed` payload or `null`), `next` (up to 3 `{ title, project, jira? }`), `agreements_today` (up to 3 strings). |
| `media` | Same as `media.now_playing`; omitted when nothing plays. |
| `face` | `{ hash }` of this Mac's profile picture; omitted when it has none (the buddy then drops the face it holds for this host). |
| `pomodoro` | The Mac's pomodoro (same shape as `pomodoro.state`); omitted when it has never been set. |

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
| `device.settings` | `{ sound, volume, brightness }`: the values the buddy applied. Sent to a Mac when its link binds, and to every Mac after any change (panel or `settings.set`) |
| `device.face_request` | `{ hash }`: the buddy does not hold the face the snapshot named; the Mac answers with its `host.face` chunks |
| `device.pomodoro` | `pomodoro`: the buddy's timer, after a change on the buddy or when its copy is newer than the snapshot's |
| `media.control` | `{ action:"play_pause"\|"next"\|"previous" }`. Playback only; the daemon maps each action to one player command and nothing else |
| `device.cover_request` | `{ hash }`: the buddy does not hold the cover a `media` payload named; the Mac answers with its `media.cover` chunks if that track still plays |

Naming: commands from the buddy use the imperative (`approve`/`deny`); state reported by the Mac uses the past tense (`approved`/`denied`).

The simulator also logs `ble.connected` / `ble.disconnected`. Those are local link-state events on each side, **not** wire messages.

## Device settings

| Field | Range | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `sound` | boolean | `false` | Sound cues on or off |
| `volume` | 0–100 | 60 | Codec output volume |
| `brightness` | 10–100 | 100 | Panel brightness while awake (the sleep clock stays dimmer) |

The buddy owns the values (kept in its own NVS namespace, never next to the BLE keys). `settings.set` carries only what changed; the buddy clamps nothing silently: an out-of-range value fails validation and changes nothing. Its `device.settings` reply is the only source the Mac shows, so Hilo and the buddy's panel never disagree.

## Faces

A Mac's profile picture, shown by the buddy's idle rotation.

- Pixels: `w`×`h` (16–160 each; `hilod` sends 120×120), RGB565 little-endian, row-major from the top-left, no header: `w·h·2` bytes in total.
- `hash`: FNV-1a 64 over those bytes, 16 lowercase hex digits. Change detection only, not a security check (the link is already encrypted and bound to the host).
- The bytes are split into `count` chunks (at most 16), each base64 in `data` (≤ 6000 characters, so every message stays far below the 8 KB cap), sent in `index` order. A chunk with another `hash` or `w`/`h` restarts the transfer; the buddy keeps the face only when all chunks arrived and the hash matches.
- On every snapshot the buddy compares `face.hash` with what it holds for that host and sends `device.face_request` on a mismatch; a Mac also sends the chunks unasked right after the picture changes. No `face` in the snapshot removes the stored one. The buddy also drops a host's face when another Mac takes that host's slot.

## Covers

The playing track's cover art on the Music view. Same encoding as [faces](#faces) (RGB565, FNV-1a 64 `hash`, base64 chunks of ≤ 6000 characters), with these differences:

- `w`×`h` 16–96 each (`hilod` sends 96×96: 18 432 bytes in 5 chunks); at most 8 chunks.
- Pull only: `media` (in `media.now_playing` or a snapshot) names the cover by `hash`; the buddy asks with `device.cover_request` when it holds a different one and is not already receiving it, and the Mac answers only for the cover of the track playing now. A `media` without `cover` means the Mac has none yet (or the track has none).
- The buddy keeps one cover, not one per host: it is content-addressed, and the view shows it only while the playing host's `media.cover.hash` matches; otherwise it draws the generated pixel cover. A Mac taking another's slot drops a half-received cover from that slot.
- Where the picture comes from is the Mac's business (see [daemon](../components/daemon.md)); the buddy never fetches anything.

## Pomodoro

One timer per buddy, mirrored by each connected Mac.

| Field | Meaning |
| :--- | :--- |
| `state` | `stopped`, `running` or `paused` |
| `phase` | `work` or `break` |
| `ends_at` | Unix seconds when the running phase ends (only when `running`) |
| `left_s` | Seconds left in the phase (only when `paused`) |
| `work_min` / `break_min` | Durations, 1–90 and 1–60 min |
| `cycle` | Work phases completed since the last reset |
| `updated_at` | When a person last changed it (start, pause, reset, durations); not touched by phase changes |

Phase changes need no message: while `running` and `ends_at` has passed, both sides flip `phase` and add the new phase's duration to `ends_at` (a finished `work` adds one to `cycle`), so they agree after any time apart. A copy with a newer `updated_at` wins: the buddy adopts a newer `pomodoro.state` or snapshot `pomodoro` and broadcasts it as `device.pomodoro`; when its own copy is newer than a snapshot's, it answers that Mac with `device.pomodoro`. The buddy keeps counting while every link is down.

## Compatibility of the additions

Every message and field above was added in v1 as optional. A buddy built before them drops the new Mac → buddy types (`BM_E_TYPE`) and ignores the new snapshot and media fields; a `hilod` built before them logs and drops the new buddy → Mac types. Neither side depends on the other answering.

## Rules

- An **approval** for a request with `risk:"high"` or `remote_allowed:false` is never accepted from the buddy, even if it arrives. A **deny** is always honored (the device shows "Deny" on high-risk prompts).
- A decision for a `request_id` that is already resolved or expired is ignored; the daemon replies with `agent.request_resolved` carrying the real outcome.
- The buddy executes nothing. It only displays and answers.
- `media.control` maps to playback commands of a local player only; the daemon accepts nothing else from it.

Flows that use these messages: [remote decision](../flows/remote-decision-flow.md), [question](../flows/question-flow.md), [reconnect + snapshot](../flows/reconnect-snapshot-flow.md).

## Pending to define

See [open questions › contract](../plans/open-questions.md#contract): replay window for `ts`. Usage from two Macs is kept per Mac ([firmware model behavior](../components/firmware.md#model-behavior)).
