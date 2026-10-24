# Hilo prototype (macOS UI)

The five screens approved as visual direction.

| File | Screen |
| :--- | :--- |
| `Main.dc.html` | Today |
| `Sessions.dc.html` | Sessions |
| `Week.dc.html` | Week |
| `Agreements.dc.html` | Agreements |
| `Resume.dc.html` | Resume context |

- **Format**: the `*.dc.html` files are the source of each screen in a design-canvas format. They do not run on their own in a browser (they depend on the canvas runtime), but they are the exact reference for layout, colors, copy and sample data.
  - Markup lives inside `<x-dc>…</x-dc>`. `{{…}}` are values returned by `renderVals()` and `<sc-for>` is a loop.
  - `drawPet` and `drawAcc` in the `Component` class draw the pets. They are the same as in `../buddy-sim.html`.

## Dark theme tokens

| Use | Color |
| :--- | :--- |
| Outer background | `#0c0b0a` |
| Window | `#161412` |
| Top bar | `#1c1a17` |
| Sidebar | `#12100e` |
| Cards | `#1e1b18` |
| Soft panels | `#201d19` |
| Lines | `#2a2723` / `#36322d` |
| Text | `#efe9df` |
| Secondary text | `#9c958a` |
| Accent (teal) | `#0e7c72` (buttons) · `#5fd0c3` (links) · `#173a36` (selected) |
| Status chips | working `#3a2210`/`#ffb07a` · needs you `#3a2c0c`/`#ffd27a` · done `#0f3324`/`#7ee2b0` · failed `#3a1416`/`#ff9a9d` |
| Sample projects | acme `#5b8cff` · clawd-buddy `#0e7c72` · research `#b98ae0` |

Fonts: Bricolage Grotesque (titles), Hanken Grotesk (body) and JetBrains Mono (commands, hashes, times).
