# hilo

The Hilo macOS app, in SwiftUI. Spec: [docs/components/hilo.md](../docs/components/hilo.md). Visual reference: [`prototypes/hilo/`](../prototypes/hilo/README.md).

A SwiftPM package (no Xcode project) that reads and writes the same SQLite store as `hilod` and the `hilo` CLI, through the `HiloStore` library in [`../daemon`](../daemon/README.md).

## Build and run

```sh
../scripts/build-hilod.sh         # first: the app bundles this signed hilod
../scripts/build-hilo-app.sh      # release build, bundled and signed as .build/Hilo.app
open .build/Hilo.app
```

`swift build` and `.build/debug/HiloApp` run it unbundled during development.

| Variable | Meaning |
| :--- | :--- |
| `HILO_DB` | Store path instead of `~/Library/Application Support/Hilo/hilo.sqlite` (scratch data) |
| `HILO_CONFIG` | Settings file instead of `~/Library/Application Support/Hilo/config.json` |
| `HILO_HILOD` | `hilod` to start instead of the copy bundled in the app |
| `HILO_SOCKET` | `hilod` socket instead of `~/Library/Application Support/Hilo/hilod.sock` (a scratch `hilod --socket`; keep it a short relative path) |
| `HILO_SNAPSHOT` | Directory: save a PNG of every section and quit (checks the layout without screen recording); a section taller than the window also gets `<section>-full.png` with its whole scroll content |

## What it shows

| Section | Source |
| :--- | :--- |
| Today | Tasks (in progress, next, done today), capture field, task detail with notes, linked sessions and agreements |
| Sessions | Sessions `hilod` recorded today, "needs you" banner, step timeline, `claude --resume` command, link to a task |
| Week | Session time, sessions and closed tasks per project; copy as Markdown |
| Agreements | Log by day and the "To confirm" column |
| Resume context | Per project: last session, its steps, open tasks, resume commands, recent agreements |
| Setup | Name this Mac, start/stop `hilod`, Claude Code hooks, guided buddy pairing, usage settings ([spec](../docs/components/hilo.md#screens)) |

The window polls the store every 2 s. After a change it asks `hilod` (socket op `hilo`) to send the buddy a fresh snapshot, so the buddy's Hilo card follows.

Commits and active time come from `hilod`'s automatic capture ([spec](../docs/components/hilo.md#stack-implemented)). Tokens per session come from the opt-in transcript scan. `scripts/build-hilo-app.sh` bundles JetBrains Mono (OFL, from `firmware/tools/fonts/ttf`) in `Contents/Resources/Fonts`; a plain `swift run` falls back to the system mono. Not yet: Bricolage Grotesque and Hanken Grotesk (titles and body use the system font), Warp tab, Jira, the Claude-drafted week summary, week navigation and `.md` export ([open questions](../docs/plans/open-questions.md#hilo)).
