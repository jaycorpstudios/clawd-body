# Components

| Spec | Component | Code (planned) |
| :--- | :--- | :--- |
| [firmware.md](firmware.md) | Buddy firmware (ESP32-S3) | `firmware/` |
| [device-ui.md](device-ui.md) | Approved device UI: views, pet, interaction, sounds | `firmware/` |
| [daemon.md](daemon.md) | `hilod`: hook ingestion, BLE bridge, remote decisions | `daemon/` |
| [hilo.md](hilo.md) | Hilo: macOS app, CLI and MCP | `hilo/`, `daemon/` |

All components talk through the [event contract](../architecture/event-contract.md).
