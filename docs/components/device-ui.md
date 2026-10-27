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
3. **Usage**: one ring per connected Mac (usage is kept per Mac): 5 h window ring (orange; amber at 80 % or more; red at 100 %), countdown, weekly bar and token sparkline. Tapping the ring opens the breakdown.
4. **Hilo**: current task with a timer, next tasks and today's agreements. Tapping opens the detail.
5. **Music**: generated pixel-art cover, title, artist and progress. Previous, play/pause and next are live (proposal: the prototype draws them but does nothing): they go to the Mac that is playing, play shows while paused, and they dim when that Mac is not connected.
6. **Focus** (proposal, below).

## Settings panel (proposal, not in the prototype)

`buddy-sim.html` has no settings screen (its only sound control is the console's Sound toggle), so this is a proposal in the simulator's style.

- **Open**: swipe down anywhere (not over a permission screen, a sheet or the pairing screen). **Close**: swipe up, tap below the panel, or the side button.
- **Look**: a 330 px sheet sliding from the top in 220 ms (ease-out) over the current view, background `#0d0c0b` with a `#1f1c19` bottom border and 28 px corners, like the agent rows; the rest of the screen dims to 60 % black. A 44×5 px grabber sits at its bottom edge.
- **Controls**, top to bottom: a full-width **Sound** button (speaker icon, "Sound", "On" in done green on a dark green fill, or "Off" in dim gray); **Volume** slider 0–100 (done green, half opacity while sound is off); **Brightness** slider 10–100 % (needs-you amber). Values show at the right of each label in JetBrains Mono.
- **Behavior**: each change applies at once (volume to the codec, brightness to the panel); the Macs get one `device.settings` once the finger rests for 400 ms. Turning sound on plays the Button cue as feedback. Values persist on the buddy across reboots; Hilo › Setup shows and changes the same three.

## Focus view (proposal, not in the prototype)

- Title "Focus" with "N done" (finished work phases) at the right, like the other titles.
- The main pet (hue 22, its accessory) at 96 px, beside the phase ("WORK" in working orange, "BREAK" in done green, "· PAUSED" appended, dim gray while stopped) and the time left in Pixelify 58 px.
- A full-width progress track in the phase color.
- While stopped: WORK and BREAK steppers (− value +, 5 min steps up to 90 for work, 1 min up to 60 for break). Hidden while running or paused.
- Round buttons: reset and a larger play/pause. Play dims until the buddy knows the time.
- Pet: working during work, happy during the break, idle when paused or stopped. A phase change shows a toast ("Break time" / "Back to work") and plays Success / Start when sound is on.
- Hilo › Focus shows the same timer with the same pet look.
- Checked against the host render (`scripts/firmware-render.sh`, 2026-10-27): every state above draws as described. Open: the buddy still sleeps after 60 s on a running timer ([open questions](../plans/open-questions.md#firmware)).

## Idle rotation (proposal, not in the prototype)

The prototype's sleep screen is the dimmed clock only. The rotation keeps its look and its 6 s anti burn-in shift.

- **Order**: every 8 s the sleep screen moves to the next card: clock → one card per registered Mac that has a picture (slot order) → clock. If no Mac has a picture, it alternates clock → computers.
- **Mac card**: the Mac's Setup name on top (JetBrains Mono bold 18, `#8a8178`), the picture at 240×240 with 28 px corners at 80 % opacity, and "connected 2 h ago" or "seen 3 h ago" below (JetBrains Mono 17, `#5c564f`, the clock's gray). A Mac without a picture has no card.
- **Computers card**: the clock's pet slot shows a 32×32 pixel monitor per known Mac (one when none), lit blue with a blinking prompt when connected, dark otherwise, and "1 Mac connected" / "2 Macs connected" / "no Mac connected" below.
- The panel stays at the sleep brightness on every card.
- Checked against the host render (2026-10-27) with a synthetic picture: card order, both "… ago" texts, the computers card with one lit and one dark monitor and "no Mac connected".

## Pet

- Pixel art on a 32×32 grid: elliptical body with light and dark edge, antenna with a glowing tip in the status color, little feet and arms.
- States: **idle** breathes and blinks · **working** bounces, types, looks side to side and sparks · **alert** jumps, big eyes, "!" and arms up · **happy** ^^ eyes, bounce and blush · **error** X eyes and shake · **worried** sweat drop · **sleep** closed eyes and "z".
- **Accessories** (hats replace the antenna): wizard (stepped hat and star wand), pixel shades, headphones, crown, party hat, headband, heart eyes.
- Each agent or project has a fixed **hue** and **accessory**, identical on the buddy and in Hilo. Sample mapping used by the prototypes:

| Sample project | Hue | Accessory |
| :--- | ---: | :--- |
| payments-api | 200 | shades |
| acme-dashboard | 280 | headphones |
| buddy-firmware | 150 | wizard |
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

Exact notes and durations live in `SOUNDS` inside the prototype. On the firmware `buddy_model/src/bm_synth.c` synthesizes the same notes, waveforms, envelopes, vibrato, bell overtone and low-pass filter at 22 050 Hz and plays them through the ES8311 codec. Sound is always built in and off by default; the settings panel (or Hilo) turns it on and sets the volume.
