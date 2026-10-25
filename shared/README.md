# shared

The Mac ⇄ buddy event contract: [`events.schema.json`](events.schema.json) is the single source of truth. Prose and rules: [event contract](../docs/architecture/event-contract.md).

| Path | What it is |
| :--- | :--- |
| `events.schema.json` | JSON Schema 2020-12 for the envelope and all 21 payloads |
| `fixtures/valid/` | One valid message per type (plus a `snapshot` with a pending request) |
| `fixtures/invalid/` | `{ reason, event }` cases that must be rejected; each breaks exactly one rule |
| `src/` | Validator (`validateEvent`), envelope + ULID helpers, scenarios, `buddy-emit` CLI |
| `test/` | `node:test` suite: fixtures, type coverage, scenarios |

## Commands

Requires Node 24 (runs TypeScript directly, no build step).

```sh
pnpm install
pnpm test                                        # contract suite
pnpm -F @hilo-buddy/shared emit list             # available scenarios
pnpm -F @hilo-buddy/shared emit permission-low --host work --interval 1500
pnpm -F @hilo-buddy/shared emit day | node shared/src/cli.ts validate
```

`buddy-emit` prints one compact JSON message per line, validating each before printing. Mac → buddy messages carry `--host`; buddy → Mac messages have none.

## Changing the contract

Contract changes need maintainer approval ([approval policy](../docs/approval-policy.md)). Update the schema, add or adjust fixtures (a valid one for new shapes, an invalid one for each new rule), then the [event contract](../docs/architecture/event-contract.md) doc.

## Dependencies

Pinned exactly; `pnpm-workspace.yaml` enforces a 7-day minimum release age.

| Package | Version | Why | Audit (2026-10-25) |
| :--- | :--- | :--- | :--- |
| `ajv` | 8.20.0 | JSON Schema 2020-12 validation | No known compromise; past the `$data` ReDoS (CVE-2025-69873, ≤ 8.17.1), and `$data` is not used |
| `fast-uri` (via ajv) | 3.1.9 | Patches GHSA-w74x-v6f9-j3xg and GHSA-xhq7-xmqj-769h | Exempt from the release-age rule: npm tarball diffed identical to the `v3.1.9` GitHub tag; no install scripts, network or `fs` use |
| `typescript` (dev) | 7.0.2 | Typecheck only; Node runs the sources directly | No known incidents |

ULIDs, the test runner and argument parsing use Node built-ins instead of packages.
