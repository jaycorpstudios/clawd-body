# Approval policy (for coding agents)

What an agent may do freely vs. what needs explicit approval from the maintainer.

## Allowed without approval

- Read code and docs; update docs.
- Non-destructive code changes inside one component.
- Local validation: lint, typecheck, test, build, firmware compile.
- Open the prototypes in a browser.
- Commit directly to `main` (no feature branches or PRs).

## Requires explicit approval

- Large changes or anything crossing components — propose a short plan first.
- Changing the event contract or the risk policy.
- Adding or upgrading a dependency: check for supply-chain incidents and recent CVEs, pin the exact version, record the reason.
- Reusing code from reference repos (`underactive/pixel-agents-esp32`, `sorryhumans/clawdmeter-plus`): only after auditing dependencies, network use, secret storage and OTA.
- Flashing firmware to the device, pairing changes, anything touching Bluetooth bonds.
- Git history rewrites, pushes, publishing.
- Generating 3D models of the figure (the physical design is done separately).

## Never

- Store credentials, tokens or API keys on the buddy or in the repo.
- Commit personal data, absolute paths, hostnames or real work project names.
