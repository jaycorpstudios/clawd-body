# Threat model

> Draft. Review it before phase 3 (daemon + BLE) and again before phase 4 (remote decisions).

## Assets

| Asset | Where it lives |
| :--- | :--- |
| Ability to approve Claude Code actions | `hilod` (decides), buddy (requests) |
| Hilo history (tasks, sessions, agreements, commits) | SQLite on each Mac |
| BLE bonding keys | Buddy NVS and macOS Bluetooth stack |
| Jira credentials (optional) | Mac only — storage pending to define |

## Adversaries

| Adversary | Capability |
| :--- | :--- |
| Nearby attacker | Scans, connects, sniffs or replays BLE traffic |
| Person with physical access to the buddy | Taps the screen while it is in range of a bonded Mac |
| Other local process on the Mac | Talks to the daemon's IPC, CLI or MCP endpoint |
| Compromised dependency | Code from npm/PyPI/firmware libraries, or the reference repos |

## Threats and mitigations

| Threat | Mitigation | Status |
| :--- | :--- | :--- |
| Spoofed buddy or Mac | Bonding required; LE Secure Connections with passkey; unbonded links rejected | Specified |
| Pairing MITM | Passkey entry (no "Just Works") | Specified |
| Replay of a decision | Unique `id`, `ts`, single-use `request_id`, expiry | Specified; replay window pending |
| Approving high-risk work from the device | Daemon allowlist; approvals for `high` / `remote_allowed:false` rejected even if received | Specified |
| Secret exfiltration from the buddy | No secrets sent to or stored on the buddy | Specified |
| Physical access approves low-risk actions | Hold-to-approve only; reach limited by BLE range | **Pending**: device lock / PIN, auto-lock when away |
| Local process forges hook input or decisions | User-only IPC permissions | **Pending**: IPC transport and auth |
| Sensitive data in logs | No full diffs, no environment variables | Specified |
| Malicious firmware update | OTA disabled unless images are signed | **Pending**: OTA decision |
| Supply-chain compromise | Pin versions, check CVEs, audit reference repos (deps, network, secret storage, OTA) before reuse | Process; see [approval policy](../approval-policy.md) |

Open items are tracked in [open questions › security](../plans/open-questions.md#security).
