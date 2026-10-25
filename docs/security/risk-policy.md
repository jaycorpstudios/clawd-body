# Risk policy (draft)

The daemon classifies every permission request before it reaches the buddy. The buddy never classifies.

| Level | Examples | From the buddy |
| :--- | :--- | :--- |
| low | `Read`, `Edit` inside the repo, `npm test`, `npm install <pkg>@<exact-version>`, `WebFetch` | approve or deny |
| high | `terraform apply`, `git push --force`, `rm -rf`, deployments, any command outside the repo, network to new hosts | deny only |
| question | `AskUserQuestion` or equivalent | answer with one option |

```mermaid
flowchart TD
    R([permission request]) --> A{matches project<br/>allowlist rule?}
    A -->|no| H[high · remote_allowed=false]
    A -->|yes| I{inside the repo<br/>and no new network host?}
    I -->|no| H
    I -->|yes| L[low · remote_allowed=true]
```

- When in doubt: **high**.
- The policy is an editable, versioned file with an allowlist per tool and command pattern, configurable per project.

## Built-in defaults (until the policy file exists)

Implemented in `daemon/Sources/HiloCore/RiskPolicy.swift`. Anything that does not match a rule is **high**.

| Tool | Low only when |
| :--- | :--- |
| `Read`, `Edit` | `file_path` is absolute and, after resolving `..`, inside the session's git repo |
| `Bash` | `cwd` is inside the repo and the command is exactly `npm test` or `npm install <pkg>@<x.y.z>`, with no shell syntax at all (`;` `&` `\|` `>` `$` backticks `=` quotes, newlines…) |
| `WebFetch` | `https` and the host is in the rule's host list — **empty by default**, so every fetch is high until hosts are configured |

`Write` is not allowlisted. Unknown repo root (not a git repo) means high.

## Pending to define

See [open questions › daemon](../plans/open-questions.md#daemon): file location and format (e.g. `~/.config/hilo/policy.toml`), rule syntax, how "inside the repo" is determined (cwd vs. resolved paths), and what counts as a "new" network host.
