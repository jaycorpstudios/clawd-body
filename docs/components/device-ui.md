# Device UI (approved)

Reference prototype: `prototypes/buddy-sim.html`. Open it in a browser and use the console buttons to fire events. For any doubt about layout, color, timing or copy, **the prototype wins**: its code holds the exact values (`drawPet`, `drawAcc`, `SOUNDS`, `FAM` and the `.screen` CSS).

## Screen

- 480×480 AMOLED: pure black background and saturated accents.
- Top bar: time, link state of each Mac (Work and Home) and battery.
- View indicator (dots) at the bottom.
- Status palette: working `#ff9a52` · needs you `#ffc53d` · done `#5ee3a8` · failed `#ff5d62` · idle `#8b8f99` · info `#7cc8ff` · BLE `#5b8cff`.
- Prototype fonts: Pixelify Sans (titles) and JetBrains Mono (data). In firmware, convert them to LVGL fonts at fixed sizes of 15 px or more.

## Views

1. **Home**: large pet, a status message ("2 agents working", "<project> needs you"…), a summary line and three stats: 5 h session, week and reset.
2. **Agents**: up to 5 rows ordered: needs you, failed, working, done, idle. Each row has avatar, name, Mac and task, status and time. Tapping a row opens its detail.
3. **Usage**: 5 h window ring (orange; amber at 80 % or more; red at 100 %), countdown, weekly bar and token sparkline. Tapping the ring opens the breakdown.
4. **Hilo**: current task with a timer, next tasks and today's agreements. Tapping opens the detail.
5. **Music**: generated pixel-art cover, title, artist and progress.

## Pet

- Pixel art on a 32×32 grid: elliptical body with light and dark edge, antenna with a glowing tip in the status color, little feet and arms.
- States: **idle** breathes and blinks · **working** bounces, types, looks side to side and sparks · **alert** jumps, big eyes, "!" and arms up · **happy** ^^ eyes, bounce and blush · **error** X eyes and shake · **worried** sweat drop · **sleep** closed eyes and "z".
- **Accessories** (hats replace the antenna): wizard (stepped hat and star wand), pixel shades, headphones, crown, party hat, headband, heart eyes.
- Each agent or project has a fixed **hue** and **accessory**, identical on the buddy and in Hilo. Sample mapping used by the prototypes:

| Sample project | Hue | Accessory |
| :--- | ---: | :--- |
| payments-api | 200 | shades |
| acme-dashboard | 280 | headphones |
| clawd-firmware | 150 | wizard |
| hilo-app | 45 | crown |
| ledger-svc | 330 | party hat |
| infra-terraform | 100 | headband |
| research-notes | 260 | heart eyes |
| main pet | 22 | wizard (configurable) |

## Interaction

- Swipe left or right to change view. Tap to open details or close alerts.
- Side button: click = back, close or next view; with a permission open it means "Later". Hold ~650 ms to sleep the screen.
- Hold to approve: ~900 ms with a progress bar.
- Temporary alerts last 1.6–3.2 s. The 100 % limit alert is persistent.

## Sounds (four families)

| Family | Timbre | Shape | Events |
| :--- | :--- | :--- | :--- |
| Attention | triangle with vibrato | rising motif on A (880 Hz) | permission, question, high risk, reminder |
| Success | sine bell with overtone | rising C major arpeggio | task done, approved, connected, charging |
| Problem | low-passed square, low register | falling intervals | error, 80 % usage, limit, battery, disconnect |
| Info | short, high sine blips | 1 to 3 notes | new session, denied, song, button |

Exact notes and durations live in `SOUNDS` inside the prototype. On the firmware they play through the ES8311 codec — synthesis vs. short PCM samples is [pending to define](../plans/open-questions.md#firmware).
