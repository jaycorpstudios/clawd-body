# Device UI (approved)

Reference prototype: `prototypes/buddy-sim.html`. Open it in a browser and use the console buttons to fire events. For any doubt about layout, color, timing or copy, **the prototype wins**: its code holds the exact values (`drawPet`, `drawAcc`, `SOUNDS`, `FAM` and the `.screen` CSS).

## Screen

- 480×480 AMOLED: pure black background and saturated accents.
- Top bar: time, link state of each Mac (Work and Home) and battery.
- View indicator (dots) at the bottom.
- Status palette: working `#ff9a52` · needs you `#ffc53d` · done `#5ee3a8` · failed `#ff5d62` · idle `#8b8f99` · info `#7cc8ff` · BLE `#5b8cff`.
- Prototype fonts: Pixelify Sans (titles) and JetBrains Mono (data). In firmware, convert them to LVGL fonts at fixed sizes of 15 px or more.

## Views

1. **Face** (decided 2026-10-27): Claudio's eyes on the case orange, no top bar; first view, see [Claudio's face](#claudios-face).
1. **Home**: large pet, a status message ("2 agents working", "<project> needs you"…), a summary line and three stats: 5 h session, week and reset.
1. **Agents**: up to 5 rows ordered: needs you, failed, working, done, idle. Each row has avatar, name, Mac and task, status and time. Tapping a row opens its detail. Each session's pet wears its own `look` from the Mac: its project's colour family (the hue nudged per session) and its own accessory; the detail has a "Pet" row (‹ name ›) that changes the accessory at once and sends `device.session_look` to that session's Mac. Sessions without a `look` (older daemon) keep the project's look until one is picked. Checked in the host render (`looks-*`).
1. **Usage**: one ring per connected Mac (usage is kept per Mac): 5 h window ring (orange; amber at 80 % or more; red at 100 %), countdown, weekly bar and token sparkline. Tapping the ring opens the breakdown.
1. **Hilo**: current task with a timer, next tasks and today's agreements. Tapping opens the detail.
1. **Music**: Hidden (view and dot, skipped by swipes) when every Mac the buddy knows sent `media_enabled:false`; if it was on screen the buddy moves to Focus. the track's cover from the Mac (`media.cover`, 96 px scaled to 150 px with rounded corners) or, until it arrives or when there is none, a generated pixel-art cover (150 px). While a named cover is on its way the pixel cover "regenerates": a light band sweeps it diagonally and a few cells swap with a neighbour, 10 steps a second, only while the Music view is on screen; it stops when the real cover arrives or 8 s after the buddy asked for it, and then shows the still pixel cover. Then the title, artist and progress. Previous, play/pause and next are live (proposal: the prototype draws them but does nothing) and drawn as round buttons like Focus: play/pause 96 px, previous and next 72 px, 28 px apart. They go to the Mac that is playing, play shows while paused, and they dim when that Mac is not connected or nothing plays. Checked against the host render (`scripts/firmware-render.sh`, 2026-10-27: nothing playing, playing, paused, Mac disconnected).
1. **Focus** (proposal, below).

## Claudio's face

Reference: [`prototypes/claudio-eyes/`](../../prototypes/claudio-eyes/index.html) (geometry decided 2026-10-27; its numbers and shapes are what the firmware uses).

- **Where**: the Face view, first of the seven. The buddy goes back to it 20 s after the last touch (not while a sheet, the settings panel, a request, pairing or the Focus alarm is open); swiping or the side button leave it as usual. The 5 s pairing hold works on Face and Home.
- **Look**: orange `#d97757` background, ink `#1d0f08`, 8 px cells. Eyes 9 × 16 cells centred at x 100 / 380 px, y 176 px; every stroke two cells, diagonals one cell per step, no slanted lids; gaze moves in whole cells. The top bar is hidden on this view; the dots stay.
- **Moods** follow the main pet: idle; working (agents working); waiting (a request, an error or a warning); done (task done, approved, a Mac connected: held at least 4 s, ^ ^ with a bounce and six sparkles); sleep (the 100 % limit, and the sleep screen).
- **Beats**: each mood picks a random beat from its pool and never the same one twice in a row: idle 8 (looks left / right / up, sweeps the room, double blink, curious, calm ▪ ▪, rests), working 7 (reading line by line, deep focus □ □, pushing through &gt; &lt;, thinking, typing, tracking ▪ ▪, slow blink), waiting 5, done 4 (bounce, wink, hearts, sparkles), sleep 3 (peek, three "z", dream). Gaps and blink intervals are the prototype's (`GAPS`, `BLINK`).
- **Alerts** take the whole screen as before; the corner slot shows an 80 px orange tile with small worried eyes (16 × 16 cells of 5 px) that blink and glance aside every 1.7 s. The prototype draws a 128 px tile; 80 px keeps the approved permission layout (it was 76 px).
- **Reactions** when a request closes: happy ^ ^ for 1.1 s after an approval, an answer or a resolution on the Mac; a blink after Deny; a glance aside for 0.9 s after Later or a hand-back to the Mac. They start 340 ms later, or when the "Approved" / "Denied" overlay closes.
- **Sleep screen**: ember `#1e0d06` background, the eyes on top in orange (4 × 7 cells at x 160 / 320, y 100, gaze at 0.55 of the face's), closed ‿ ‿ eyes that breathe one cell, an occasional peek and "z"; the clock and the Mac / computers cards below (y 200–460, orange text, the picture at 160 px), all moving with the usual 6 s drift.
- **Drawing**: each eye is a pre-scaled RGB565 image the size of its box (72 × 128 px, 18 KB, in PSRAM), redrawn only when its cells change and moved with `lv_obj_set_pos`; there is no full-screen canvas.
- Checked in the host render (`face-*`, 2026-10-27).

## Settings panel (proposal, not in the prototype)

`buddy-sim.html` has no settings screen (its only sound control is the console's Sound toggle), so this is a proposal in the simulator's style.

- **Open**: swipe down anywhere (not over a permission screen, a sheet or the pairing screen). **Close**: swipe up, tap below the panel, or the side button.
- **Look**: a 336 px sheet sliding from the top in 220 ms (ease-out) over the current view, background `#0d0c0b` with a `#1f1c19` bottom border and 28 px corners, like the agent rows; the rest of the screen dims to 60 % black. A 44×5 px grabber sits at its bottom edge.
- **Controls**, top to bottom: a full-width **Sound** button (speaker icon, "Sound", "On" in done green on a dark green fill, or "Off" in dim gray); **Volume** slider 0–100 (done green, half opacity while sound is off); **Brightness** slider 10–100 % (needs-you amber); **Time zone** with − and + round buttons (1 h steps, 44 px) around the offset ("UTC−6", "UTC+5:45"). Values show at the right of each label in JetBrains Mono.
- **Behavior**: each change applies at once (volume to the codec, brightness to the panel); the Macs get one `device.settings` once the finger rests for 400 ms. Turning sound on plays the Button cue as feedback. Values persist on the buddy across reboots; Hilo › Setup shows and changes the same four. The time zone moves the top bar clock, the sleep clock and the Hilo view's date. Checked against the host render (2026-10-27, `panel-tz-*`).

## Focus view (proposal, not in the prototype)

- Title "Focus" with "N done" (finished work phases) at the right, like the other titles.
- The main pet (hue 22, its accessory) at 96 px, beside the phase ("WORK" in working orange, "BREAK" in done green, "· PAUSED" appended, dim gray while stopped) and the time left in Pixelify 58 px.
- A full-width progress track in the phase color.
- While stopped: WORK and BREAK steppers (− value +, 5 min steps up to 90 for work, 1 min up to 60 for break). Hidden while running or paused.
- Round buttons: reset and a larger play/pause. Play dims until the buddy knows the time.
- Pet: working during work, happy during the break, idle when paused or stopped. A phase change shows a toast ("Break time" / "Back to work") and rings the **end-of-phase alarm** (decided 2026-10-27): the buddy wakes on the Focus view at full brightness, a 124 px ring in the new phase's colour pulses around the pet (1.1 s), and the Success cue plays in bursts of three 1 s apart, every 5 s, for 30 s or until a touch anywhere or the side button (that touch does nothing else; a change from a Mac also silences it). It follows the sound setting (silent when sound is off) and plays at volume 60 at least while it rings. A phase that ended more than 30 s ago (a clock that jumped) flips without ringing. Hilo.app shows a macOS notification at the same time.
- Hilo › Focus shows the same timer with the same pet look.
- Checked against the host render (`scripts/firmware-render.sh`, 2026-10-27): every state above draws as described. Open: the buddy still sleeps after 60 s on a running timer ([open questions](../plans/open-questions.md#firmware)).

## Idle rotation (proposal, not in the prototype)

The rotation keeps the 6 s anti burn-in shift. Since 2026-10-27 it sits under Claudio's sleeping eyes on an ember background ([Claudio's face](#claudios-face)): the cards fill y 200–460 and use the case orange.

- **Order**: every 8 s the sleep screen moves to the next card: clock → one card per registered Mac that has a picture (slot order) → clock. If no Mac has a picture, it alternates clock → computers.
- **Mac card**: the Mac's Setup name on top (JetBrains Mono bold 18, `#8a8178`), the picture at 160×160 with 28 px corners at 80 % opacity, and "connected 2 h ago" or "seen 3 h ago" below (JetBrains Mono 17, `#5c564f`, the clock's gray). A Mac without a picture has no card.
- **Computers card**: shows a 32×32 pixel monitor per known Mac (one when none), lit blue with a blinking prompt when connected, dark otherwise, and "1 Mac connected" / "2 Macs connected" / "no Mac connected" below.
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
