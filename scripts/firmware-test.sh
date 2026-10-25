#!/bin/sh
# Host tests for the portable firmware model; cJSON comes from the ESP-IDF tree, as on the device.
# SANITIZE=address,undefined adds ASan; it is not the default because it hangs at startup with some Command Line Tools.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
idf="${IDF_PATH:-$HOME/esp/esp-idf-v5.5.6}"
cjson="$idf/components/json/cJSON"
[ -f "$cjson/cJSON.c" ] || { echo "cJSON not found under $idf (set IDF_PATH)" >&2; exit 1; }

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
model="$root/firmware/components/buddy_model"

san="-fsanitize=${SANITIZE:-undefined} -fno-sanitize-recover=all -fno-omit-frame-pointer"
clang -std=c11 -g -O1 -w $san -c "$cjson/cJSON.c" -o "$out/cJSON.o"
clang -std=c11 -g -O1 -Wall -Wextra -Werror $san \
  -DFIXTURES_DIR="\"$root/shared/fixtures\"" \
  -I"$model/include" -I"$model/src" -I"$cjson" -I"$root/firmware/test" \
  "$model"/src/*.c "$root"/firmware/test/*.c "$out/cJSON.o" -lm -o "$out/model-tests"

"$out/model-tests" --emit "$out/outgoing.jsonl" "$@"

if command -v node >/dev/null 2>&1; then
  node "$root/shared/src/cli.ts" validate < "$out/outgoing.jsonl"
else
  echo "node not found: skipped schema check of outgoing messages" >&2
fi
