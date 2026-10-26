# Buddy firmware

Visual and behavioral reference: `prototypes/buddy-sim.html` (approved). Views, states and sounds in detail: [device-ui.md](device-ui.md).

Stack: **ESP-IDF + LVGL 9**, BLE through NimBLE. Board bring-up uses the vendor BSP `waveshare/esp32_s3_touch_amoled_2_16` (pins: CO5300 QSPI on GPIO 4–7/12/38/39, I²C on 14/15, touch INT 11 / RST 40, I²S MCLK 42 · BCLK 9 · WS 45 · DOUT 8, PA enable 46, user button 18). Build notes: [`firmware/README.md`](../../firmware/README.md).

## Hardware

**Waveshare ESP32-S3-Touch-AMOLED-2.16**

- ESP32-S3R8 · 16 MB flash · 8 MB PSRAM
- 480×480 touch AMOLED (CO5300 display controller, CST9220 touch)
- 2.4 GHz WiFi and BLE 5 · QMI8658 IMU · PCF85063 RTC · AXP2101 PMU
- Audio: ES8311 codec and ES7210 ADC with 2 microphones (microphones unused)
- microSD · user button on GPIO18 (on the bare board, the third of the three buttons on the top edge; the UI calls it the side button) · 3.7 V 1000 mAh Li-ion battery

Spare parts available: PAM8403 amplifiers and 8 Ω 0.5 W speakers, in case the onboard audio is not loud enough.

## Functional requirements

1. **Five rotating views**: Home, Agents, Usage, Hilo and Music. Switched by swiping or with the side button.
2. **Animated pet** with states (idle, working, alert, happy, error, worried, sleep) and accessories. Each agent has its own hue and accessory.
3. **Full-screen alerts**: task done (confetti), error, usage warning at 80 %, limit at 100 %, connect and disconnect, low battery.
4. **Permission or question screen**: shows project, Mac, tool, command and reason.
   - Normal permission: **Deny** and **Hold to approve** (hold ~0.9 s).
   - High risk: **Deny** only, with the caption "High risk: Mac only".
   - Question: options as buttons.
   - **Later**: keeps it pending without losing it.
   - **View details**: opens a sheet with full information (diff, directory, risk).
5. **Detail sheets** opened by tapping: agent (recent activity, tokens, diff, error or summary), usage (per-session breakdown) and Hilo task (notes, agreements, linked sessions).
6. **Side button**: a click goes back, closes an alert or moves to the next view; with a permission open it means "Later". Holding it puts the screen to sleep.
7. **Idle**: after 60 s without activity (unless decisions are pending) shows a dimmed clock that moves every few seconds to avoid AMOLED burn-in.
8. **Reminder** for pending decisions every 25 s (Attention sound family).
9. **Multi-Mac**: bonded with one or two Macs. The top bar shows each link's state; sessions of a disconnected Mac are dimmed.
10. **Battery**: indicator in the top bar and an alert at 15 %.

## Non-functional requirements

- Zero secrets in flash or NVS, except the BLE bonding keys managed by the stack.
- Automatic reconnection and consistent state: on reconnect the Mac re-sends a full `snapshot` ([flow](../flows/reconnect-snapshot-flow.md)).
- 30 fps or more on the active view; off-screen pets are not drawn.
- Adjustable brightness and volume. Sound is off by default.

## Model behavior

The portable model (`firmware/components/buddy_model/`) holds all state and timing; `main/ui/` only draws it and forwards touch and button input. BLE lives in `main/ble/` (NimBLE peripheral, see [BLE transport](../architecture/ble-transport.md)); it reassembles frames on the NimBLE task and hands whole messages and link events to the UI task, which owns the model. With `CONFIG_BUDDY_DEMO` a scripted demo feed (`main/demo.c`) plays both Macs instead of BLE.

The portable model (`firmware/components/buddy_model/`) follows the prototype; where the prototype is silent:

- **Usage per Mac.** Each Mac's `usage.update` is kept separately; the Usage view shows one ring per Mac. Home stats, the pet and the Home "Limit reached" message use the connected Mac with the highest 5 h value. The 80 % warning fires once per Mac per crossing.
- **Clock from the envelope.** A `snapshot` sets the clock to its `ts`; any other message only moves it forward. The PCF85063 holds UTC: it is written every time a Mac sets the clock and read once at boot, so the clock is known before any Mac connects (an RTC with its oscillator-stop flag set, or a year before 2026, is ignored). The time zone is a build setting until [pending](../plans/open-questions.md#firmware).
- **Unknown fields are ignored** (minor-version rule), so `extra-envelope-field` and `window-reset-with-data` are accepted; every other invalid fixture is rejected.
- **Expired requests.** `outcome: expired` (or the local clock passing `expires_at`) removes the decision but keeps the session in "needs you": the Mac prompt still waits for the user.
- **Pending requests vs. status.** Reminders and the "no idle sleep" rule apply only to requests the buddy can answer; a "needs you" row with no request does neither.
- **Agent hue and accessory** are derived from a hash of the project name until [Project hue/accessory](../plans/open-questions.md#hilo) is resolved.

## Board drivers

`main/hw/` talks to the PMU and RTC over the BSP's I²C bus with the IDF `i2c_master` driver (no extra components):

- **AXP2101** (0x34): read only. Battery present, USB present, charge direction, fuel-gauge percent and battery voltage, polled every 5 s and fed to `bm_set_battery`, which owns the 15 % alert and the charging toast. The PMU's power-on defaults already enable the gauge and the battery ADC; nothing is written to it.
- **PCF85063** (0x51): time registers only, UTC, BCD.

## Out of scope for now

LED eyes, arms or moving parts, microphone and voice assistant. The simulator shell still draws eyes and arms; ignore them.

## Pending to define

See [open questions › firmware](../plans/open-questions.md#firmware): pin and driver confirmation against the Waveshare schematic, OTA (signed images only, if at all), sound playback, battery-life target, time zone.
