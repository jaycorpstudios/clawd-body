# Buddy firmware

Visual and behavioral reference: `prototypes/buddy-sim.html` (approved). Views, states and sounds in detail: [device-ui.md](device-ui.md).

## Hardware

**Waveshare ESP32-S3-Touch-AMOLED-2.16**

- ESP32-S3R8 · 16 MB flash · 8 MB PSRAM
- 480×480 touch AMOLED (CO5300 display controller, CST9220 touch)
- 2.4 GHz WiFi and BLE 5 · QMI8658 IMU · PCF85063 RTC · AXP2101 PMU
- Audio: ES8311 codec and ES7210 ADC with 2 microphones (microphones unused)
- microSD · user button on GPIO18 · 3.7 V 1000 mAh Li-ion battery

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

## Out of scope for now

LED eyes, arms or moving parts, microphone and voice assistant. The simulator shell still draws eyes and arms; ignore them.

## Pending to define

See [open questions › firmware](../plans/open-questions.md#firmware): framework (ESP-IDF + LVGL vs. Arduino + LVGL) and pin/driver confirmation against the Waveshare schematic, OTA (signed images only, if at all), sound playback, battery-life target, clock source for the RTC.
