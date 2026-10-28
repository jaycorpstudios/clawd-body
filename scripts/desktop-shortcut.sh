#!/bin/bash
# Puts a Hilo link on the Desktop that points at the repo's build, so it keeps working after every rebuild.
# Usage: desktop-shortcut.sh [remove]
set -eu
app="$(cd "$(dirname "$0")/.." && pwd)/hilo/.build/Hilo.app"
link="$HOME/Desktop/Hilo.app"

if [ "${1:-}" = remove ]; then
  [ -L "$link" ] && rm "$link" && echo "removed $link"
  exit 0
fi
[ -d "$app" ] || { echo "no $app yet: run scripts/build-hilod.sh and scripts/build-hilo-app.sh" >&2; exit 1; }
if [ -e "$link" ] && [ ! -L "$link" ]; then echo "$link exists and is not a link; leaving it alone" >&2; exit 1; fi
ln -sfn "$app" "$link"
echo "linked $link → $app"
