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

1. **Seven rotating views**: Face (Claudio's eyes, first; the buddy returns to it 20 s after the last touch), Home, Agents, Usage, Hilo, Music and Focus (Pomodoro, a proposal: see [device UI](device-ui.md#focus-view-proposal-not-in-the-prototype)). Switched by swiping or with the side button. Music's previous / play-pause / next send `media.control` to the Mac that is playing; Focus runs on the buddy's clock, so it keeps going with every link down and re-syncs through `pomodoro.state` / `device.pomodoro` (newer `updated_at` wins).
2. **Animated pet** with states (idle, working, alert, happy, error, worried, sleep) and accessories. Each agent has its own hue and accessory.
3. **Full-screen alerts**: task done (confetti), error, usage warning at 80 %, limit at 100 %, connect and disconnect, low battery.
4. **Permission or question screen**: shows project, Mac, tool, command and reason.
   - Normal permission: **Deny** and **Hold to approve** (hold ~0.9 s).
   - High risk: **Hold 3 s to approve**, then **Tap to confirm** within 4 s (since 2026-10-29). A Mac-only request (`remote_allowed:false`): **Deny** only, with the caption "Approve on the Mac".
   - Question: options as buttons.
   - **Later**: keeps it pending without losing it.
   - **View details**: opens a sheet with full information (diff, directory, risk).
5. **Detail sheets** opened by tapping: agent (recent activity, tokens, diff, error or summary), usage (per-session breakdown) and Hilo task (notes, agreements, linked sessions).
6. **Side button**: a click goes back, closes an alert or moves to the next view; with a permission open it means "Later". Holding it puts the screen to sleep.
7. **Idle**: after 60 s without activity (unless decisions are pending) shows a dimmed clock that moves every few seconds to avoid AMOLED burn-in. The panel drops to `CONFIG_BUDDY_SLEEP_BRIGHTNESS` (20 %, build option) on the sleep clock, or to the brightness setting if that is lower, and returns to the brightness setting on wake. While asleep it rotates the clock with a card per Mac that sent a picture (name, picture, "connected/seen … ago") or, if none did, a pixel computers card counting connected Macs ([device UI](device-ui.md#idle-rotation-proposal-not-in-the-prototype)). Pictures arrive as `host.face` chunks and live only in PSRAM, so after a reboot each Mac sends its own again when it reconnects; forgetting a Mac drops its picture with the slot. The Music view's cover works the same way (`media.cover`, asked for with `device.cover_request`, one 96×96 cover kept in PSRAM and drawn pre-scaled from a 150 px PSRAM buffer).
8. **Reminder** for pending decisions every 25 s (Attention sound family).
9. **Multi-Mac**: bonded with one or two Macs. The top bar shows each link's state; sessions of a disconnected Mac are dimmed.
10. **Battery**: indicator in the top bar and an alert at 15 %.
11. **Settings panel**: swipe down for sound on/off, volume, brightness and time zone ([device UI](device-ui.md#settings-panel-proposal-not-in-the-prototype)). Kept in NVS under the namespace `buddy_ui` (a 6-byte blob with a version byte, saved 2 s after the last change; the older 4-byte blob without a time zone still loads, with the default offset); NimBLE's bonds stay in `nimble_bond`, untouched. Hilo changes them with `settings.set`; the buddy answers every change, and every Mac link that binds, with `device.settings`.

## Non-functional requirements

- Zero secrets in flash or NVS, except the BLE bonding keys managed by the stack.
- Automatic reconnection and consistent state: on reconnect the Mac re-sends a full `snapshot` ([flow](../flows/reconnect-snapshot-flow.md)).
- 30 fps or more on the active view; off-screen pets are not drawn.
- Adjustable brightness and volume. Sound is off by default.

## Model behavior

The portable model (`firmware/components/buddy_model/`) holds all state and timing; `main/ui/` only draws it and forwards touch and button input. BLE lives in `main/ble/` (NimBLE peripheral, see [BLE transport](../architecture/ble-transport.md)); it reassembles frames on the NimBLE task and hands whole messages and link events to the UI task, which owns the model. With `CONFIG_BUDDY_DEMO` a scripted demo feed (`main/demo.c`) plays both Macs instead of BLE.

The portable model (`firmware/components/buddy_model/`) follows the prototype; where the prototype is silent:

- **Two host slots.** A message from a third host name takes the slot of a disconnected Mac (its sessions are dropped), so renaming a Mac in Hilo does not lock a slot until the next reboot; with both Macs connected it is rejected. The slot's picture and any half-received one go with it, so the new Mac never shows the old one's picture. A link that comes up before the buddy knows the time (first boot without a valid RTC) gets its "connected" time when the first Mac message or the RTC sets the clock.
- **Usage per Mac.** Each Mac's `usage.update` is kept separately; the Usage view shows one ring per Mac. Home stats, the pet and the Home "Limit reached" message use the connected Mac with the highest 5 h value. The 80 % warning fires once per Mac per crossing.
- **Clock from the envelope.** A `snapshot` sets the clock to its `ts`; any other message only moves it forward. The PCF85063 holds UTC: it is written every time a Mac sets the clock and read once at boot, so the clock is known before any Mac connects (an RTC with its oscillator-stop flag set, or a year before 2026, is ignored). The time zone is a build setting until [pending](../plans/open-questions.md#firmware).
- **Unknown fields are ignored** (minor-version rule), so `extra-envelope-field` and `window-reset-with-data` are accepted; every other invalid fixture is rejected.
- **Expired requests (hand-back).** `outcome: expired` (the user came back to the Mac, or the local clock passed `expires_at`) removes the decision but keeps the session waiting: the Mac prompt still waits for the user. Such a session reads "on the Mac" in its row and sheet chip, the sheet says "Answer it on the Mac.", and Home shows "Answer it on the Mac" with "<project> · handed back" (a session with a request the buddy can answer comes first); tapping opens the sheet, never a prompt. The next `agent.step` for that session puts it back to working, as `hilod` does; `hilod` keeps a handed-back session `waiting` without a pending request in its snapshots, so a reconnect shows the same (#19, 2026-10-27).
- **Pending requests vs. status.** Reminders and the "no idle sleep" rule apply only to requests the buddy can answer; a "needs you" row with no request does neither.
- **Snapshots keep what only the buddy knows.** A `snapshot` rebuilds that Mac's sessions, so the open sheet, the open request, the overlay's session and each request's Later / ack flags follow their session or `request_id` into the new list; a sheet whose session is gone closes, and a permission sheet closes once its request is gone. A pet picked on the buddy wins over snapshots carrying another accessory for 5 s (`BM_LOOK_ECHO_MS`), so quick ‹ › taps never bounce back while the Mac echoes earlier picks; the first snapshot that carries the pick, or the 5 s, ends that.
- **Claudio's eyes.** `bm_eyes.c` (portable) turns the mood derived from the main pet into beats, blinks, gaze, reactions, sparkles and "z", and rasterises each eye shape into a cell mask (`bm_eye_cells`); `bm_tick` runs it, so its timing is covered by the host tests. `main/ui/ui_eyes.c` turns the masks into small pre-scaled images for the Face view, the alert tile and the sleep screen ([device UI](device-ui.md#claudios-face)).
- **Agent hue and accessory** are derived from a hash of the project name until [Project hue/accessory](../plans/open-questions.md#hilo) is resolved.

## Board drivers

`main/hw/` talks to the PMU and RTC over the BSP's I²C bus with the IDF `i2c_master` driver (no extra components):

- **AXP2101** (0x34): read only. Battery present, USB present, charge direction, fuel-gauge percent and battery voltage, polled every 5 s and fed to `bm_set_battery`, which owns the 15 % alert and the charging toast. The PMU's power-on defaults already enable the gauge and the battery ADC; nothing is written to it.
- **PCF85063** (0x51): time registers only, UTC, BCD.
- **ES8311** (through the BSP's `bsp_audio_codec_speaker_init` and `esp_codec_dev`): an audio task renders each cue the model queues into PSRAM and writes it to I²S at the volume setting; cues are dropped while the sound setting is off. The codec (and its power amplifier) closes after 2 s without sound. The cue renderer is portable and covered by the host tests.

## Out of scope for now

LED eyes, arms or moving parts, microphone and voice assistant. The simulator shell still draws eyes and arms; ignore them.

## Pending to define

See [open questions › firmware](../plans/open-questions.md#firmware): pin and driver confirmation against the Waveshare schematic, OTA (signed images only, if at all), sound playback, battery-life target, time zone.
