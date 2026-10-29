#!/bin/bash
# Regenerates hilo/Resources/AppIcon.icns from the app's own pet drawing (AppIconArt). Run after changing it; the .icns is committed.
set -eu
cd "$(dirname "$0")/.."
(cd hilo && swift build -c release --product HiloApp)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
HILO_ICON="$work/icon.png" hilo/.build/release/HiloApp
set=$work/AppIcon.iconset
mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$work/icon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$work/icon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p hilo/Resources
iconutil -c icns "$set" -o hilo/Resources/AppIcon.icns
echo "wrote hilo/Resources/AppIcon.icns"
