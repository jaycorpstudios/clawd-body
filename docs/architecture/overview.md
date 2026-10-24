# Architecture overview

```mermaid
flowchart LR
    subgraph Mac["Mac (work or home)"]
        CC["Claude Code sessions<br/>(Warp)"] -- hooks --> D
        Git[git repos] -- watcher --> D
        Jira["Jira (optional)"] -- sync --> D
        D["hilod daemon<br/>· hook ingestion<br/>· risk policy<br/>· SQLite (this Mac only)<br/>· MCP server + CLI backend<br/>· BLE central"]
        App[Hilo.app] <--> D
        CLI[hilo CLI] <--> D
        CC -- MCP --> D
    end
    D <-- "BLE · bonded · LE Secure Connections" --> B
    subgraph Buddy["Buddy · ESP32-S3 · AMOLED 480×480"]
        B["views, pet, sounds<br/>low-risk decisions"]
    end
```

- The buddy may be bonded with both Macs at once. Every Mac → buddy event carries `host` to identify its origin.
- Each Mac has its own database. The buddy merges on screen what it receives from both; it never relays data between Macs.
- The buddy executes nothing. It displays state and returns decisions; the daemon decides whether to honor them.

## Repo layout (monorepo, proposed)

| Path | Contents |
| :--- | :--- |
| `firmware/` | ESP32-S3: display, BLE peripheral, audio |
| `daemon/` | `hilod`: hooks, BLE, SQLite, MCP, CLI |
| `hilo/` | macOS app UI |
| `shared/` | Event schema (single source) and generated types |
| `docs/` | This documentation |
| `prototypes/` | Approved visual references |

## Pending to define

- **Daemon and app stack** (native Swift vs. TypeScript/Node with Tauri/Electron, etc.). Criteria: stable BLE on macOS (CoreBluetooth), low power, easy packaging as a login item. See [open questions](../plans/open-questions.md#architecture).
- **Local IPC** between the hook command, the CLI, the app and `hilod`. See [hook ingestion](../flows/hook-ingestion-flow.md).
