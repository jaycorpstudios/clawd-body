#!/bin/bash
# Release build of the Hilo macOS app, bundled as hilo/.build/Hilo.app (no Xcode needed).
# Signed with the identity scripts/build-hilod.sh creates; ad-hoc if it does not exist yet.
set -eu
identity="Hilo Local Signing"
cd "$(dirname "$0")/../hilo"

swift build -c release --product HiloApp
app=".build/Hilo.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
# Not "Hilo": APFS is case-insensitive and the hilo CLI below would overwrite it.
cp .build/release/HiloApp "$app/Contents/MacOS/HiloApp"
# The app starts hilod from its own bundle; build-hilod.sh signs it, and that signature is kept here.
hilod="../daemon/.build/release/hilod"
if [ -x "$hilod" ]; then cp "$hilod" "$app/Contents/MacOS/hilod"; else echo "note: no $hilod yet, run scripts/build-hilod.sh first"; fi
# The CLI too, so Setup can point Claude Code's status line at a stable path.
[ -x "../daemon/.build/release/hilo" ] && cp "../daemon/.build/release/hilo" "$app/Contents/MacOS/hilo"
# JetBrains Mono (OFL) from the firmware font sources; Bricolage Grotesque and Hanken Grotesk are not in the repo yet.
fonts="../firmware/tools/fonts/ttf"
mkdir -p "$app/Contents/Resources/Fonts"
cp "$fonts"/JetBrainsMono-{Regular,SemiBold,Bold}.ttf "$fonts/OFL-JetBrainsMono.txt" "$app/Contents/Resources/Fonts/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.hilo.app</string>
  <key>CFBundleName</key><string>Hilo</string>
  <key>CFBundleExecutable</key><string>HiloApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>NSAppleEventsUsageDescription</key><string>Hilo asks Spotify and Music what is playing so the buddy can show it.</string>
  <!-- The bundled hilod reads this plist, not its embedded one: without the key macOS kills it on first Bluetooth use. -->
  <key>NSBluetoothAlwaysUsageDescription</key><string>hilod talks to your Hilo Buddy over Bluetooth.</string>
</dict>
</plist>
PLIST
if security find-certificate -c "$identity" >/dev/null 2>&1; then sign="$identity"; else sign="-"; fi
codesign --force --sign "$sign" "$app"
echo "built $PWD/$app"
