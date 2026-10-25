# Testing strategy

> **Pending to define.** Fill per component once stacks are chosen. The safety rules (no remote high-risk approval, single-use decisions) must have automated tests before phase 4 ships.

```mermaid
flowchart LR
    C[Contract: schema fixtures] --> U[Unit: policy, validation, rendering logic]
    U --> I[Integration: hook → daemon → fake BLE peer]
    I --> H[Hardware-in-the-loop: real buddy]
```

| Layer | What to test | Tool | Run |
| :--- | :--- | :--- | :--- |
| Contract | Valid fixture per type passes; each invalid fixture fails; scenarios emit only valid events | `node:test` + ajv | `pnpm test` |
| Unit (daemon) | Risk policy classification; decision validation (pending, expiry, single use, high-risk approve rejected); Swift types vs. shared fixtures | Swift Testing | `scripts/swift-test.sh` |
| Unit (firmware) | View state machine, sort order, timers (idle 60 s, reminder 25 s, hold 900 ms) | {{tool}} | {{cmd}} |
| Integration | Hook payload → event → fake peripheral; reconnect sends `snapshot` | Swift Testing (`Coordinator` with fake link, clock, presence); manual run in `daemon/README.md` | `scripts/swift-test.sh` |
| Visual parity | Firmware screens vs. `prototypes/buddy-sim.html` | {{tool}} | {{cmd}} |
| Hardware | Pairing, two Macs, range loss, battery alerts | manual checklist | — |
