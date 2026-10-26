# firmware

ESP-IDF v5.5.6 + LVGL 9 for the Waveshare ESP32-S3-Touch-AMOLED-2.16. Spec: [docs/components/firmware.md](../docs/components/firmware.md).

Status: all five views, pet, alerts, permission screen, sheets and the pairing screen drawn with LVGL from the model. NimBLE peripheral with the contract GATT service, passkey pairing and two links; untested on the board. `CONFIG_BUDDY_DEMO` swaps BLE for a scripted demo Mac (`main/demo.c`). Sound, battery (AXP2101) and RTC are next.

## Layout

| Path | Role |
| :--- | :--- |
| `components/buddy_model/` | Portable C11 model, no ESP-IDF or LVGL includes: parses contract messages (cJSON), keeps per-Mac state, derives what each view shows, runs the timers and queues outgoing messages and sound cues. Also renders the 32×32 pet. |
| `main/` | Board bring-up, side button, link pump (`main.c`), the demo feed (`demo.c`, portable, also run by the host tests) and the LVGL allocator (`lv_mem_psram.c`) |
| `main/ui/` | LVGL drawing of the model: one file per area (views, overlay, permission screen, sheets, bar and sleep) |
| `main/ble/` | NimBLE peripheral: GATT service, pairing, advertising, per-link reassembly |
| `main/fonts/` | Generated LVGL fonts (do not edit) |
| `test/` | Host tests for `buddy_model` |
| `tools/fonts/` | Generates `main/fonts/` from the prototype fonts ([README](tools/fonts/README.md)) |

## Memory

Measured on the board (2026-10-25). The BSP keeps LVGL's draw buffers in PSRAM, so every flush copies its area (up to 48 KB) into an internal DMA buffer allocated on the spot; with NimBLE running, that allocation failed and the screen stopped updating. `main/lv_mem_psram.c` sends LVGL allocations under 1 KB (objects, styles) to PSRAM and keeps larger render-time buffers internal (all-PSRAM halved the frame rate).

| Build | Internal free after boot (low-water) | Frame rate |
| :--- | :--- | :--- |
| Demo | ~232 KB (168 KB) | ~60 fps, min 46 |
| BLE | ~133 KB (83 KB) | not measured (no perf monitor) |

## Host tests

```sh
scripts/firmware-test.sh   # clang + UBSan; uses cJSON from the ESP-IDF tree and the fixtures in shared/
```

The run also pipes every message the model emits through `buddy-emit validate`, so outgoing messages are checked against the schema.

## Build

```sh
scripts/idf.sh build        # from the repo root; loads ESP-IDF from ~/esp/esp-idf-v5.5.6 (override with IDF_PATH)
```

Demo variant (scripted Mac instead of BLE, LVGL frame rate logged every second), built apart from the main config:

```sh
scripts/idf.sh -B build-demo -D SDKCONFIG=build-demo/sdkconfig -D 'SDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.demo' build
```

Flashing (`scripts/idf.sh -p <port> flash monitor`) needs maintainer approval ([approval policy](../docs/approval-policy.md)).

## Toolchain setup (once)

```sh
git clone -b v5.5.6 --depth 1 --recursive --shallow-submodules https://github.com/espressif/esp-idf.git ~/esp/esp-idf-v5.5.6
cd ~/esp/esp-idf-v5.5.6
PATH="<dir with python3 -> Homebrew python3.12>:$PATH" ./install.sh esp32s3
PIP_UPLOADED_PRIOR_TO=P7D IDF_PIP_WHEELS_URL="" python3 tools/idf_tools.py install-python-env
python3 tools/idf_tools.py install cmake ninja
```

- Use Homebrew's Python, not the system one; the installer takes the first `python3` on `PATH`.
- `PIP_UPLOADED_PRIOR_TO=P7D` keeps anything published in the last 7 days out of the venv. Espressif's extra index has no upload times, so it is disabled with `IDF_PIP_WHEELS_URL=""` (PyPI has every wheel needed on macOS arm64).
- Toolchain archives are verified by ESP-IDF against the SHA-256 in its `tools.json`.

## Dependencies

Declared in [`main/idf_component.yml`](main/idf_component.yml), resolved versions locked in `dependencies.lock` (committed). `MINIMAL_BUILD` compiles only what `main` requires.

| Component | Version | Why | Audit (2026-10-25) |
| :--- | :--- | :--- | :--- |
| `waveshare/esp32_s3_touch_amoled_2_16` | 2.0.1 | Board bring-up (CO5300 QSPI panel, CST9217 touch, I²C, codec), tested by the vendor | Apache-2.0; no network, NVS or OTA code; pins match the vendor wiki |
| `lvgl/lvgl` | 9.6.0~1 | UI | Published 2026-09-17 |
| `espressif/zlib`, `espressif/libpng` | 1.3.2~1, 1.6.58~2 | Transitive (optional image decoders) | Pinned below releases newer than 7 days (1.3.2~2 on 2026-10-25, 1.6.59 on 2026-10-22) |
| Other `espressif/*` | see `dependencies.lock` | Transitive from the BSP | All published 2026-10-14 or earlier, none yanked |

Python tooling (local only, not on the device): 61 packages, none vetoed, no startup `.pth` beyond setuptools' own. Known advisories remain in versions capped by Espressif's constraints: `cryptography` 44.0.3 (< 45), `urllib3` 1.26.20 (< 2), `ecdsa` 0.19.2 (no fix). OSV flags `certifi` 2026.10.18 for GHSA-6q48-6c7w-9gw2, but that release is the one that removed every emSign root; the advisory text itself says "before 2026.10.18".
