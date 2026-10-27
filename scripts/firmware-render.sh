#!/bin/sh
# Renders buddy screens to PNG on the Mac: the real LVGL UI and model, driven through scripted scenes.
# Usage: scripts/firmware-render.sh [out-dir] [scene-filter]. Needs firmware/build/config/sdkconfig.h (scripts/idf.sh build).
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
fw="$root/firmware"
idf="${IDF_PATH:-$HOME/esp/esp-idf-v5.5.6}"
cjson="$idf/components/json/cJSON"
lvgl="$fw/managed_components/lvgl__lvgl"
sdk="$fw/build/config"
for f in "$cjson/cJSON.c" "$lvgl/lvgl.h" "$sdk/sdkconfig.h"; do
  [ -f "$f" ] || { echo "missing $f (run scripts/idf.sh build)" >&2; exit 1; }
done

out="${1:-$fw/build-render/shots}"
mkdir -p "$out"
cache="$fw/build-render/lvgl"
mkdir -p "$cache"

render="$fw/test/render"
flags="-std=c11 -O2 -w -DLV_CONF_KCONFIG_EXTERNAL_INCLUDE=\"lv_host_config.h\" -I$render -I$render/stub -I$sdk -I$lvgl"
export flags lvgl cache
find "$lvgl/src" -name '*.c' | xargs -P 8 -I{} sh -c '
  src="$1"; obj="$cache/$(printf %s "${src#$lvgl/}" | tr / _).o"
  [ "$obj" -nt "$src" ] && [ "$obj" -nt "$0" ] || clang $flags -c "$src" -o "$obj"
' "$render/lv_host_config.h" {}

model="$fw/components/buddy_model"
bin="$fw/build-render/render"
clang $flags -I"$model/include" -I"$model/src" -I"$cjson" -I"$fw/test" -I"$fw/main" -I"$fw/main/ui" \
  "$model"/src/*.c "$fw"/main/ui/*.c "$fw"/main/fonts/*.c "$render/render.c" "$fw/test/support.c" \
  "$cjson/cJSON.c" "$cache"/*.o -lm -o "$bin"
"$bin" "$out" "${2:-}"
