#!/bin/sh
set -eu
cd "$(dirname "$0")/../daemon"
clt=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if xcode-select -p | grep -q CommandLineTools && [ -d "$clt/Testing.framework" ]; then
  # CLT ship Swift Testing outside the search path, with a broken Foundation overlay.
  exec swift test -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F"$clt" -Xlinker -F"$clt" -Xlinker -rpath -Xlinker "$clt" "$@"
fi
exec swift test "$@"
