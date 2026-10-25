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
- Pairing is accepted only while the buddy is in pairing mode (hold the side button 5 s on Home; the window closes after 60 s, or 30 s after the passkey appears). Outside it a passkey request ends the connection, and a repeat pairing from a bonded Mac is ignored.
- A link that is not encrypted, authenticated and bonded within 10 s (45 s in pairing mode) is dropped. `rx` writes on such a link are refused.
- Each link is bound to the `host` of its first valid message; a later message naming another host, or a second link claiming a host that is already connected, is rejected (`BM_E_HOST_BOUND`).

## Advertising

| State | Flags | Interval | Notes |
| :--- | :--- | :--- | :--- |
| Pairing mode | general discoverable | 30–60 ms | Service UUID in the advertisement, name `Hilo Buddy` in the scan response |
| Otherwise | not discoverable, connectable | 1 s | Lets bonded Macs reconnect; stops while two links are up |

No directed advertising for now.

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
- Implementations: `daemon/Sources/HiloCore/Framing.swift` and `firmware/components/buddy_model/src/bm_frame.c` (the device reassembles in `firmware/main/ble/ble.c`); their tests (`FramingTests.swift`, `firmware/test/test_frame.c`) cover the same cases and change together.

## Pending to define

> Gap → context → what to fill. Tracked in [open questions › BLE](../plans/open-questions.md#ble).

| Gap | Context | What to fill |
| :--- | :--- | :--- |
| Two simultaneous centrals | NimBLE is configured for two links; reassembly buffers live in PSRAM | Confirm both links on the board and the memory cost |
| macOS pairing UX | CoreBluetooth triggers the system pairing dialog; apps do not control it | Verify how passkey entry looks on macOS and document the user steps |
