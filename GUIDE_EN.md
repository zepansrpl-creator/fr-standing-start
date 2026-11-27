# FR Standing Start – setup guide

**FR Standing Start** adds an F1-style standing start to Assetto Corsa multiplayer races: a formation lap, a marked grid box for every car, start lights and jump-start detection.

It is a **CSP online script**. Server admins only add a few lines to the server config. **Drivers install nothing**: the script is downloaded automatically when they join the server. They only need Custom Shaders Patch (CSP).

---

## What happens in a race

1. **The game's own race start begins the formation lap.** At that moment the script records every car's grid slot. Slot numbers come from the cars' positions on the grid (nearest the line = P1), not from the race order, so a car moved to the pits doesn't take P1.
2. **Formation lap.** A speed limit is optional. Drivers see their grid slot number on screen.
3. **Lining up.** About 300 m before the slot, a countdown appears, e.g. `P3 · ↑ 42 m`. The slot is marked on the tarmac with a glowing box and a 1.5 m gate with the slot number above the front line:
   - blue: approaching,
   - yellow: close / not quite right,
   - green: correct,
   - red: penalty.

   Arrows show where to move: `↑ move up`, `↓ too far`, `← LEFT / RIGHT →`.
4. **Start lights.** The admin starts the lights, or they start automatically once everyone has stopped. Five red lights come on, then go out after a random delay. They go out at the same moment for every driver (network ping is compensated).
5. **Jump starts and grid infringements** are penalised automatically when the lights go out and announced in chat.
6. **Reaction times.** Each driver sees their own reaction time. The admin gets a list of all drivers, ready to paste into Discord.

### Default rules

| Situation | Result |
|---|---|
| Within 0.5 m of the slot line | OK |
| Overshot by 0.5–10 m | warning only, can reverse back into the slot |
| Overshot by more than 10 m | **drive-through** (reversing does not cancel it) |
| More than 0.5 m to the side of the slot | warning with arrow and yellow guide line on the tarmac |
| More than 2 m to the side when the lights come on | **drive-through** |
| Moving more than 0.5 m before the lights go out | **jump start → drive-through** |
| Pit start (car in the pits at the game's start, entering the pit lane during the formation lap, or joining during the start procedure) | may drive the formation lap but must be back in the pit lane before the lights; may leave only on the **green pit exit light**, shown once the whole field has passed a point 300 m past P1's slot (≈ turn 1), or after 30 s |
| Pit start: leaving the pit lane before the green light | **drive-through** |
| Pit start: not in the pit lane when the lights come on | **drive-through** |
| Not moving off for the formation lap | counted as ready, admin decides |
| Not in your grid slot when the first light comes on, within 20 m | **drive-through** |
| Not in your grid slot when the first light comes on, more than 20 m away | **stop & go 10 s** (stop in your pit box; the car is held on the brakes until the time is up) |

A **stop & go** is served by stopping in your own pit box for 10 s; the car is held on the brakes and a countdown is shown. A **drive-through** must be served within 3 laps by driving through the pit lane **without stopping**. A pit stop does not count. The driver sees how many laps are left. Serving (or not serving) the penalty is shown on screen and in chat.

Drivers who join during the start procedure see that they start from the pits.

All values can be changed (see [All settings](#all-settings)).

---

## Requirements

- An Assetto Corsa server with CSP online scripts. Tested with **Assetto Corsa Server Manager (ACSM)**. Any server that lets you edit the CSP extra options works.
- **Custom Shaders Patch** for all drivers. Set a minimum CSP version on the server; tested with 0.2.x (build 3749).
- Drivers without CSP can still race, but they won't see the script and won't take part in the procedure.

---

## Server setup (ACSM)

### 1. Add the script to the race

Open your event (Custom Race, Race Weekend or Championship) and go to the field for **CSP extra options**. In ACSM it is called **Extra Options**; enable "Enable Extra Custom Shaders Patch Options" in the server options if you don't see it. Paste this **at the end**, keeping your existing options:

```ini
[SCRIPT_...]
SCRIPT = "https://raw.githubusercontent.com/zepansrpl-creator/fr-standing-start/v0.2.1/fr_standing_start.lua"

[FR_STANDING_START]
LANGUAGE = EN
FORMATION_SPEED_KMH = 0
OVERSHOOT_PENALTY = DRIVE_THROUGH
JUMP_START_PENALTY = DRIVE_THROUGH
AUTO_LIGHTS = 0
```

- Type `[SCRIPT_...]` **exactly like this, with three dots**. CSP numbers the section itself. A custom name such as `[SCRIPT_MY_START]` will **not** be loaded.
- The address contains a version number (`v0.2.1`), so your races always use that exact version. To update, change the number. The list of versions is on the [Releases page](https://github.com/zepansrpl-creator/fr-standing-start/releases).

### 2. Set the start rule

Set **Start Rule** to **"Car is Locked Until Start"**. The game's start only launches the formation lap, so cars must not get a game penalty for moving off.

### 3. Lap count

The formation lap is added to lap 1 in the results, so **add one lap** to a lap-based race. Check this on your server in a test race. For a timed race, add roughly one lap's worth of time.

### 4. Real Penalty (optional)

FR Standing Start works alongside Real Penalty:
- **Do not enable Real Penalty's "race start behind safety car"** (rolling start), because the two start procedures would clash.
- Real Penalty's jump-start check runs at the game's start, when cars are locked, so it does not interfere.
- Real Penalty keeps handling track limits, pit lane speeding and everything else. Note that it also counts cuts on the formation lap; above its minimum speed, 40 km/h by default.

### 5. Restart the event

Save the event and start it again.

---

## Running the start (admin)

1. **Log in as admin.** Type `/admin <admin password>` in the chat. The server replies "You are now Admin".
2. **Open the admin panel.** Open the new CSP **Chat** app, click the **online extras** icon next to the message box and choose **"FR Standing Start – admin"**.
3. **The panel shows:**
   - **Start lights**: works during the formation lap,
   - **Abort start (extra formation lap)**: switches the lights off and sends everyone round again. Pending grid penalties are dropped,
   - **Skip formation (test)**: treats everyone as having completed the formation lap. Useful for testing alone,
   - **a list of all cars** with grid slot, status and distance from the slot, plus a **Cancel penalty** button (works before the lights go out),
   - after the start, **all reaction times** and a **Copy reaction times (Discord)** button. Paste with Ctrl+V.

Chat commands (admin only, hidden from other drivers):

| Command | Action |
|---|---|
| `!frss lights` | start the lights |
| `!frss abort` | abort the start (extra formation lap) |
| `!frss skip` | skip the formation lap (test) |
| `!frss reactions` | copy the reaction time list to the clipboard |

**Automatic lights:** with `AUTO_LIGHTS = 1`, the admin's game starts the lights once every car has been stationary for 5 s, or 60 s after the first car stopped in its slot. An admin must be connected for this to work.

---

## For drivers

- **Nothing to install.** You only need CSP.
- In the CSP Chat app, under online extras, open **"FR Standing Start – settings"** to:
  - switch the language (EN/PL),
  - move and resize the distance messages, with sliders or by dragging the preview with the mouse. Your settings are saved on your PC.
- Drive to the glowing box with the gate, stop with the front of the car on the white line, and wait for the lights.

---

## All settings

All settings go into the `[FR_STANDING_START]` section. Anything you leave out uses the default.

| Key | Default | Description |
|---|---|---|
| `LANGUAGE` | `PL` | `EN` or `PL` (drivers can switch locally) |
| `FORMATION_SPEED_KMH` | `80` | speed limit on the formation lap, `0` = no limit |
| `APPROACH_ZONE_M` | `300` | distance from which the slot and countdown are shown |
| `GRID_TOLERANCE_M` | `0.5` | allowed distance from the slot line |
| `GRID_WARNING_M` | `10.0` | overshoot above this = penalty |
| `LATERAL_TOLERANCE_M` | `0.5` | allowed sideways offset |
| `LATERAL_PENALTY_M` | `2.0` | sideways offset at the first light above this = penalty |
| `ALLOW_REVERSE` | `0` | `1` = reversing also cancels a large overshoot |
| `OVERSHOOT_PENALTY` | `DRIVE_THROUGH` | `DRIVE_THROUGH`, `STOP_GO`, `TELEPORT` or `WARNING` |
| `JUMP_START_PENALTY` | `DRIVE_THROUGH` | same options |
| `LATE_PENALTY` | `DRIVE_THROUGH` | not in your slot when the lights come on |
| `LATE_FAR_M` | `20` | ...and further than this from the slot: |
| `LATE_FAR_PENALTY` | `STOP_GO` | penalty when far from the slot |
| `STOP_GO_SECONDS` | `10` | stop time for a stop & go |
| `PIT_RELEASE_M` | `300` | pit starters: green light once the field passes this far past P1's slot |
| `PIT_RELEASE_MAX_S` | `30` | ...or this long after lights out |
| `PENALTY_LAPS` | `3` | laps allowed to serve a drive-through |
| `TELEPORT_SECONDS` | `10` | time held in the pits for `TELEPORT` |
| `JUMP_START_M` | `0.5` | movement before lights out that counts as a jump start |
| `LIGHTS_COUNT` | `5` | number of lights (1–10) |
| `LIGHTS_INTERVAL_MS` | `1000` | time between lights |
| `LIGHTS_LEAD_MS` | `3000` | time from the command to the first light |
| `HOLD_MIN_MS` / `HOLD_MAX_MS` | `200` / `3000` | random delay before lights out |
| `AUTO_LIGHTS` | `0` | `1` = start the lights automatically |
| `AUTO_DELAY_S` | `5` | how long everyone must be stopped |
| `AUTO_TIMEOUT_S` | `60` | lights start anyway this long after the first car stopped |
| `REPORT_REACTION` | `1` | show each driver their reaction time in chat |
| `CHAT_PREFIX` | `FRSS>` | prefix of the script's chat messages |

---

## Troubleshooting

**Is the script loaded?** In game, open the CSP **Lua Debug** app. There should be an extra **"Server Script: SCRIPT_…"** entry with values starting with `FRSS` (version, phase, state) and a log line `[FRSS] v… start`.

**The script doesn't appear at all.** Check that:
- the section is exactly `[SCRIPT_...]`,
- the event was restarted after saving,
- the address opens in a browser.

**No admin panel in online extras.** Log in with `/admin <password>` and open the menu again. The chat commands work too.

**Something else is wrong.** Send the CSP log, which is overwritten on every game launch, so copy it before restarting AC:
`Documents\Assetto Corsa\logs\custom_shaders_patch.log`
Look for lines containing `[FRSS]`.

Bug reports and ideas: [GitHub Issues](https://github.com/zepansrpl-creator/fr-standing-start/issues).

---

MIT licence – free to use and modify, keeping the author notice. © 2026 Maciej Szczepaniak
