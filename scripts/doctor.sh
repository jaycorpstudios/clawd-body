#!/bin/bash
# Checks what this Mac needs to build and run Hilo. Read only: installs nothing. Exits 1 if a required item is missing.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
missing=0

ok()   { printf '  ok    %s\n' "$1"; }
need() { printf '  MISS  %s\n        → %s\n' "$1" "$2"; missing=1; }
warn() { printf '  --    %s\n        → %s\n' "$1" "$2"; }

version_at_least() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

echo "Required to build and run Hilo"
macos="$(sw_vers -productVersion)"
if version_at_least "$macos" 14.0; then ok "macOS $macos"; else need "macOS $macos" "Hilo needs macOS 14 or later"; fi
[ "$(uname -m)" = arm64 ] && ok "Apple silicon" || warn "$(uname -m) Mac" "only tested on Apple silicon"

if xcode-select -p >/dev/null 2>&1; then ok "developer tools at $(xcode-select -p)"
else need "Xcode or Command Line Tools" "xcode-select --install"; fi

swift_version="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9.]+).*/\1/p' | head -1)"
if [ -z "$swift_version" ]; then need "Swift" "comes with Xcode 26 or Command Line Tools 26 (xcode-select --install)"
elif version_at_least "$swift_version" 6.2; then ok "Swift $swift_version"
else need "Swift $swift_version" "the packages need Swift 6.2+: update Xcode or Command Line Tools to 26"; fi

for tool in git openssl codesign security launchctl; do
  command -v "$tool" >/dev/null 2>&1 && ok "$tool" || need "$tool" "ships with macOS and the developer tools"
done

echo
echo "Used by Hilo's setup"
command -v claude >/dev/null 2>&1 && ok "Claude Code CLI" \
  || warn "Claude Code CLI (claude) not on PATH" "Setup copies prompts you paste into a Claude Code session; install Claude Code first"

echo
echo "Build state"
if security find-certificate -c "Hilo Local Signing" >/dev/null 2>&1; then ok "signing identity 'Hilo Local Signing'"
else warn "no signing identity yet" "scripts/build-hilod.sh creates it (macOS asks for the login keychain password)"; fi
[ -x "$root/daemon/.build/release/hilod" ] && ok "hilod built" || warn "hilod not built" "scripts/build-hilod.sh"
[ -x "$root/hilo/.build/Hilo.app/Contents/Helpers/hilod" ] && ok "Hilo.app built" || warn "Hilo.app not built" "scripts/build-hilo-app.sh (after build-hilod.sh)"
launchctl list dev.hilo.hilod >/dev/null 2>&1 && ok "hilod running (LaunchAgent dev.hilo.hilod)" \
  || warn "hilod not running" "open Hilo.app › Setup › Run hilod › Start"

echo
echo "Optional (development only)"
node_version="$(node --version 2>/dev/null | tr -d v)"
if [ -n "$node_version" ] && version_at_least "$node_version" "$(cat "$root/.nvmrc")"; then ok "Node $node_version (contract tests)"
else warn "Node $(cat "$root/.nvmrc")+ not found" "only for pnpm test in shared/ and schema checks"; fi
command -v pnpm >/dev/null 2>&1 && ok "pnpm" || warn "pnpm not found" "only for pnpm test in shared/"
[ -f "${IDF_PATH:-$HOME/esp/esp-idf-v5.5.6}/export.sh" ] && ok "ESP-IDF" || warn "ESP-IDF 5.5.6 not found" "only to build or flash the buddy firmware (firmware/README.md)"

echo
[ "$missing" = 0 ] && echo "Ready to build: scripts/build-hilod.sh && scripts/build-hilo-app.sh" || echo "Fix the MISS items above first."
exit "$missing"
