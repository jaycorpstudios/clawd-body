# firmware fonts

Converts the prototype fonts into LVGL C fonts under [`firmware/main/fonts/`](../../main/fonts/). The generated `.c` files are committed, so building the firmware never needs Node.

```sh
pnpm install
pnpm -F @hilo-buddy/firmware-fonts build
```

Sizes and weights come from the `.screen` CSS of `prototypes/buddy-sim.html`. Sizes under 15 px are raised to 15 px ([device UI](../../../docs/components/device-ui.md#screen)). 4 bpp, uncompressed. The text fonts cover ASCII, Latin-1 and common punctuation. The 58 px and 92 px fonts carry digits, `:` and `%` only. JetBrains Mono has no ♪ glyph, so the toast font falls back to Montserrat 16, and the UI draws its audio and charge symbols from there.

## Sources

Static TTFs, SIL Open Font License 1.1 (licenses next to the files in `ttf/`). The git blob hash of each file matches the upstream tree at the pinned commit. Full hashes are in `ttf/SHA256SUMS` (`shasum -a 256 -c SHA256SUMS`).

| File | Upstream | Commit | SHA-256 |
| :--- | :--- | :--- | :--- |
| `PixelifySans-Medium.ttf` | `eifetx/Pixelify-Sans` `fonts/ttf/` | `39df74a` (the commit Google Fonts cites) | `5219b5ad…bfff69af` |
| `PixelifySans-Bold.ttf` | same | same | `3c3c203a…d668b293c` |
| `JetBrainsMono-Regular.ttf` | `JetBrains/JetBrainsMono` `fonts/ttf/` | `cd5227b` (tag v2.304) | `a0bf60ef…898d138f` |
| `JetBrainsMono-SemiBold.ttf` | same | same | `1b3bfa1e…b4e166a0` |
| `JetBrainsMono-Bold.ttf` | same | same | `5590990c…42479dcb` |

## Dependencies

| Package | Version | Why | Audit (2026-10-25) |
| :--- | :--- | :--- | :--- |
| `lv_font_conv` (dev) | 1.5.3 | LVGL's own TTF → C converter | Published 2024-06-10 by the LVGL maintainers, MIT. No install scripts. Bundled deps (argparse 2.0.1, bit-buffer 0.2.5, debug 4.3.4, ms 2.1.2, make-error 1.3.6, mkdirp 1.0.4, opentype.js 1.3.4, pngjs 6.0.0, tiny-inflate 1.0.3, string.prototype.codepointat 0.2.1) have no OSV advisories and predate the September 2025 `debug` 4.4.2 compromise. FreeType ships compiled to JS. It reads local TTFs only, with no network access. |
