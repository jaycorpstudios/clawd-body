#!/bin/bash
# Runs idf.py from firmware/ with ESP-IDF loaded. IDF_PATH defaults to ~/esp/esp-idf-v5.5.6.
set -eu
export IDF_PATH="${IDF_PATH:-$HOME/esp/esp-idf-v5.5.6}"
# The installer picks the first python3 on PATH; prefer Homebrew's 3.12 over the system one.
if [ -x /opt/homebrew/bin/python3.12 ]; then
  shim="$(mktemp -d)"
  ln -s /opt/homebrew/bin/python3.12 "$shim/python3"
  export PATH="$shim:$PATH"
fi
. "$IDF_PATH/export.sh" > /dev/null
cd "$(dirname "$0")/../firmware"
exec idf.py "$@"
