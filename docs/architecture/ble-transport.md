# BLE transport

## Roles

| Side | Role | Notes |
| :--- | :--- | :--- |
| Mac (`hilod`) | GATT central | Discovers and connects only to bonded buddies |
| Buddy | GATT peripheral | May hold links with two Macs at the same time |

## Security

- LE Secure Connections with passkey on first pairing; see [pairing flow](../flows/ble-pairing-flow.md).
- Unbonded connections are rejected; characteristics require an encrypted, authenticated link.
- The only secrets on the buddy are the bonding keys managed by the BLE stack.
- Trusted devices are revocable from Hilo.

## Pending to define

> Gap → context → what to fill. Tracked in [open questions › BLE](../plans/open-questions.md#ble).

| Gap | Context | What to fill |
| :--- | :--- | :--- |
| GATT layout | No service or characteristic defined yet | Service UUID, one characteristic per direction (notify Mac → buddy, write buddy → Mac), properties and permissions |
| Framing over MTU | `snapshot` and `agent.needs_permission` with `diff` exceed a default MTU | Pick "write long" / long reads vs. own framing (length + CRC); max message size |
| Two simultaneous centrals | The buddy may be bonded to both Macs at once | Confirm the ESP32-S3 stack supports two concurrent links and the memory cost |
| Advertising policy | Buddy must be discoverable for pairing but quiet otherwise | When it advertises, interval, whether it uses directed advertising to bonded hosts |
| macOS pairing UX | CoreBluetooth triggers the system pairing dialog; apps do not control it | Verify how passkey entry looks on macOS and document the user steps |
