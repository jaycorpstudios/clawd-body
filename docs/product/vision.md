# Vision

## Problem

A developer works on several projects at once, with several Claude Code sessions open across two Macs (work and home). It is easy to lose track of which session needs attention, how much usage is left, and where each task was left off.

## Solution

| Piece | Role |
| :--- | :--- |
| **Buddy** | Physical desk device that shows at a glance what the agents are doing, who needs you and how much usage is left. Can be carried to another room while the Mac keeps working. |
| **Hilo** | macOS app that keeps history (tasks, sessions, commits, agreements) and helps you pick up context again. |
| **`hilod`** | Daemon on each Mac: receives Claude Code hooks, feeds Hilo and talks to the buddy over BLE. |

## Users and environment

- One developer, two Macs (work and home), Claude Code running in Warp (no tmux).
- The buddy travels between home and office and may be paired with one or both Macs at the same time.
- Each Mac keeps its own data; nothing syncs between them.
- The daemon must be acceptable under a typical corporate IT policy (local only, no cloud relay).

## Scope

- **In**: five rotating device views, animated pet, full-screen alerts, low-risk approvals and question answers from the device, multi-Mac pairing, Hilo (Today, Sessions, Week, Agreements, Resume context), `hilo` CLI and MCP server.
- **Out (for now)**: LED eyes, arms or moving parts, microphone and voice assistant, cloud sync, Windows/Linux support, 3D models of the figure (designed separately).

## Success criteria

| Target | Value | How it is checked |
| :--- | :--- | :--- |
| Hook to buddy screen | < 500 ms | Timestamp at `hilo hook` vs. render on the device (phase 3 hardware test) |
| Battery | ≥ 8 h of normal use per charge | Manual run on the 1000 mAh cell |
| `hilod` idle | < 1 % CPU, < 30 MB RAM | Activity Monitor / `top` with no session activity |
| Remote approval only of what the buddy shows whole | A cut or Mac-only request can never be approved from the buddy; high-risk needs a 3 s hold plus a confirming tap | Automated: `scripts/swift-test.sh` (registry, mapper and coordinator tests), `scripts/firmware-test.sh` (hold and confirm) |
