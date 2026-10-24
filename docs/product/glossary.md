# Glossary

| Term | Meaning |
| :--- | :--- |
| **Buddy** | The physical device: ESP32-S3 + AMOLED inside a 3D-printed figure |
| **Pet** | The original pixel-art character drawn on the buddy and in Hilo |
| **Accessory** | Item worn by the pet (wizard hat, shades, headphones, crown, party hat, headband, heart eyes) |
| **Hilo** | The macOS app (UI, CLI `hilo`, MCP server) |
| **`hilod`** | The daemon on each Mac: hook ingestion, SQLite, BLE central, MCP, CLI backend |
| **Host** | The short name of the Mac that sent an event (e.g. `work`, `home`) |
| **Session** | One Claude Code session, identified by its Claude session id |
| **Request** | A pending permission or question, identified by `request_id` |
| **Remote decision** | An approval, denial or answer made on the buddy instead of the Mac |
| **Risk level** | `low` or `high`, assigned by the daemon's [risk policy](../security/risk-policy.md) |
| **`remote_allowed`** | Daemon flag: whether a request may be decided from the buddy |
| **Snapshot** | Full state message sent on (re)connect so the buddy never shows stale data |
| **Bonding** | BLE pairing whose keys are stored, so later connections are authenticated |
| **Agreement** | A decision recorded in Hilo (what, with whom, where), optionally linked to a task |
| **View** | One of the five rotating device screens: Home, Agents, Usage, Hilo, Music |
| **Sheet** | Detail panel that slides up on the device when you tap a row, ring or task |
| **Overlay / alert** | Full-screen device message (task done, error, usage warning, connection, battery) |
