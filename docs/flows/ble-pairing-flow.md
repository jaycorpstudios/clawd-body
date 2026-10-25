# BLE pairing flow

```mermaid
sequenceDiagram
    actor U as User
    participant A as Hilo.app
    participant D as hilod (central)
    participant OS as macOS Bluetooth
    participant B as Buddy (peripheral)

    U->>B: hold the side button 5 s on Home (pairing mode, 60 s)
    B->>B: advertise as pairable
    U->>A: "Add buddy"
    A->>D: start discovery
    D->>B: connect
    D->>B: access protected characteristic
    B-->>OS: LE Secure Connections, passkey entry
    B->>U: display 6-digit passkey
    U->>OS: type passkey in system dialog
    OS-->>B: bond established (keys stored by both stacks)
    D->>D: add buddy to trusted devices
    D-->>B: snapshot
```

## Revocation

```mermaid
flowchart LR
    R([User removes buddy in Hilo]) --> F[hilod forgets device + disconnects]
    F --> OS[Remove bond from macOS]
    R2([User forgets a Mac on the buddy]) --> K[Buddy deletes that bond]
    K --> X([Next connection from that Mac is rejected])
```

## Notes

- Unbonded or unencrypted connections are always rejected.
- Bonding keys are the only secret on the buddy.
- **Pending to define** ([open questions › BLE](../plans/open-questions.md#ble)): how to forget a Mac from the device, exact macOS pairing UX (CoreBluetooth hands pairing to the system dialog), pairing a second Mac while the first stays connected.
