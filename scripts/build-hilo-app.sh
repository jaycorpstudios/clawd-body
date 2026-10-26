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
cp .build/release/HiloApp "$app/Contents/MacOS/Hilo"
# The app starts hilod from its own bundle; build-hilod.sh signs it, and that signature is kept here.
hilod="../daemon/.build/release/hilod"
if [ -x "$hilod" ]; then cp "$hilod" "$app/Contents/MacOS/hilod"; else echo "note: no $hilod yet, run scripts/build-hilod.sh first"; fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.hilo.app</string>
  <key>CFBundleName</key><string>Hilo</string>
  <key>CFBundleExecutable</key><string>Hilo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
if security find-certificate -c "$identity" >/dev/null 2>&1; then sign="$identity"; else sign="-"; fi
codesign --force --sign "$sign" "$app"
echo "built $PWD/$app"
