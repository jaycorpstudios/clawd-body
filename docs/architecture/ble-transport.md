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

## GATT layout

| Item | UUID | Properties | Direction |
| :--- | :--- | :--- | :--- |
| Service `hilo-buddy` | `B7369283-8B36-49C1-AAAB-83A726C961EB` | primary | — |
| `rx` | `FF7BD675-3612-48AF-9960-1F7338BF3623` | write with response; encrypted + authenticated | Mac → buddy |
| `tx` | `2076870D-85DF-42C8-9C4D-21589C44FC9F` | notify; encrypted + authenticated | buddy → Mac |

## Framing

Each contract message (compact JSON, at most **8 KB**) is split into frames of up to the negotiated write/notify size:

```
[seq u8][index u8][count u8][chunk …]
```

- `seq` increments per message (wraps at 255); `index` runs 0…`count`−1 in order.
- The receiver drops a partial message on any gap, repeated `seq` mismatch or malformed header; a frame with `index` 0 starts a new message.
- No extra CRC: the link layer already checks every packet (CRC + AES-CCM MIC on the encrypted link).
- 255 frames × (size − 3) must hold 8 KB, so the frame size must be at least 36 bytes; macOS and the ESP32-S3 negotiate far more.
- Implementations: `daemon/Sources/HiloCore/Framing.swift` (firmware port pending).

## Pending to define

> Gap → context → what to fill. Tracked in [open questions › BLE](../plans/open-questions.md#ble).

| Gap | Context | What to fill |
| :--- | :--- | :--- |
| Two simultaneous centrals | The buddy may be bonded to both Macs at once | Confirm the ESP32-S3 stack supports two concurrent links and the memory cost |
| Advertising policy | Buddy must be discoverable for pairing but quiet otherwise | When it advertises, interval, whether it uses directed advertising to bonded hosts |
| macOS pairing UX | CoreBluetooth triggers the system pairing dialog; apps do not control it | Verify how passkey entry looks on macOS and document the user steps |
