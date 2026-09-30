# DuoBox: duo-boxing a Dwarf Priest + Night Elf Hunter (WoW Classic / WoW Forever)

DuoBox is a World of Warcraft Classic addon (plus an optional voice tool) for playing two characters at once:
the hunter is played normally, the priest follows and heals.
Everything is designed around **"one key press = one action in one game client"**.

> In-game text (chat messages, tooltips, panels) is currently in French.

## 0. Blizzard rules in short
- **Allowed**: two accounts (two licenses), two windows, switching by hand (alt+tab or clicking the other screen),
  in-game macros (`/follow`, `/assist`, `[@target]`…), addons that only display information, raise alerts or accept invites and quests.
- **Not allowed**: any software or hardware that sends **one key press to several windows** (ISBoxer broadcasting,
  "multi-window" AutoHotkey scripts, gaming keyboards targeting several clients…) or that automates actions.
  Simple rule: **1 key press = 1 action in 1 client**.
- DuoBox follows this: it only raises alerts, never sends an action to the other client and never restarts follow by itself.
- Always check the official multiboxing policy of the realm type you play on.

## 1. Windows / screens
1. Start the first client and log in with account A (hunter). Start a second client (click "Play" again in Battle.net,
   or run the client executable a second time, e.g. `_classic_beta_\WowB.exe` on the beta) and log in with account B (priest).
2. Display mode: **Windowed (Fullscreen)** in both clients. Move the second window to the other screen with `Win+Shift+→`.
   In windowed fullscreen, a single **click** on the other screen switches focus (faster than alt+tab).
3. Type `/duo cvars` once: enables sound in the background (needed to hear the priest's alerts while playing the hunter)
   and auto loot.
4. If the background client drops to very low FPS: disable Windows Game Mode, set `WowB.exe` to "High performance"
   in Windows graphics settings, and turn off the NVIDIA "Background Application Max Frame Rate".

## 2. Addons
| Addon | Role in the duo |
|---|---|
| **DuoBox** (this repo) | cross-client alerts, partner invites/quests/resurrection, quest sharing, button bar, key bindings, macros |
| **Leatrix Plus** | see settings below |
| **Questie** | shows the partner's quest progress in tooltips |
| **RXPGuides** | leveling guide: enable it on the hunter (the leader) only |
| ThreatClassic2 (optional) | threat meter: check that the pet keeps aggro |
| Clique (optional) | click-casting on the priest's party frames if you prefer the mouse |

**Leatrix Plus (on both characters)** → *Automation*:
- Accept party invites from friends (add the other character as a friend, or rely on DuoBox)
- Automate quests (accept / turn in)
- Accept summons and resurrections
- Auto repair, sell grey items
- *Interface*: Faster auto loot

Game options → Interface: **"Use Raid-Style Party Frames"** on the priest (large, readable frames).

## 3. DuoBox setup (on each character)
```
/duo partner PriestName      (on the hunter)
/duo partner HunterName      (on the priest)
/duo macros                  (creates the D-xxx macros in the character tab of /macro)
/duo test                    (switch to the other window: this one must beep and flash)
```
Only the first name matters (`Multi`, `Multi Boxing` and `Multi-Realm` all match).
The role is automatic (priest = heal, hunter = dps). Thresholds: `/duo hp 50`, `/duo pet 35`, `/duo mana 20`.
`/duo status` shows the current settings and the detected partner unit (it must be `party1`).

### Alerts
- **On the priest client**: hunter below 50% health, pet below 35%, hunter dead, aggro on the priest.
- **On the hunter client**: priest below 50% health, priest mana below 20%, aggro on the priest, priest dead,
  **the priest stopped following you**.
- **On both clients: quest not turned in.** When one character turns in a quest that the other still has in its log,
  the other gets 15 s to turn it in too (D-Talk / "talk"); after that both screens get an alert with the quest name
  ("(pas terminee)" when it is not complete yet). `/duo turnin off` disables it.
- A small movable status frame shows the partner's health, mana and follow state.
- **Aggro on the priest** is detected from threat, from a mob targeting the priest (enemy nameplates must be shown, `V` key)
  or from damage taken, and triggers a sound alert on both screens.

### Button bar
Always shown, semi-transparent, opaque on mouse-over. Shift+drag to move it, `/duo bar off` to hide it,
`/duo scale 1.3` to resize it. Icons are greyed out when the partner is not in the group.

- **Row 1**: **Follow** · **Target** · **Assist** · **Talk** (same as the D-Talk macro) · **Sit** (`/sit`) · **Trade** · **Invite** · **Compare quests** · **Share last quest** · **Key bindings** (gear).
- **Row 2 (priest only)**: **Fortitude** · **Shield** · **Renew** · **Heal** (Lesser Heal, then Heal once learned) · **Dispel** ·
  **Resurrection** · **Smite**, **Smite + Wait**, **Shadow Word: Pain** and **Wand** (assist the hunter + spell) · **Wait** (stop following) · **Drink** (best drink in your bags for your level).
- Fortitude / Shield / Renew / Heal / Dispel: click = partner, **Shift** = partner's pet, **Ctrl** = yourself.
- **Heal**, **Resurrection**, **Smite + Wait** and **Wand** stop following before casting (moving would interrupt the cast):
  follow again afterwards.
  Fortitude gets a golden border when a buff is missing or expires in less than 2 minutes (out of combat only).
- **Compare quests** shares your quests that the partner is missing and tells you which ones they have in addition
  (then click "Compare" on their window).

### Priest cast bar (hunter screen)
Yellow while casting, blue for an instant spell, green on success, red when interrupted / failed.
It also shows the priest's spell errors (out of range, line of sight, not enough mana, wrong facing…).
`/duo castbar off` to hide it.

### Priest facing indicator (hunter screen)
For Smite and the wand the priest must face their target. When the priest has an enemy target, the hunter screen shows
which way to turn (left / right with the angle) or that the priest is facing correctly.
- The game does not expose mob positions, so the target position is estimated from the pet (if it attacks the same target)
  or from a point in front of the hunter. If positions are blocked, it falls back to "face the same direction as the hunter"
  (shown as *approx.*).
- Does not work in dungeons (positions are blocked there). The priest's "wrong facing" error still triggers an alert.
- `/duo facing invert` if left/right are swapped, `/duo facing dist 30` to change the estimated distance,
  `/duo facing off` to hide it, `/duo facing debug` to see which values the client can read.

### Moving and resizing
`/duo move` shows the cast bar and the facing text with sample content so you can drag them;
the bottom-right corner of the cast bar resizes it. Type `/duo move` again to save.

### Key bindings
Gear button at the end of the bar, or `/duo keys`. Click a row, then press a key
(Shift/Ctrl/Alt modifiers and mouse buttons 3-5 are accepted); right-click a row to clear it. The key is shown on the button.
The same actions are also in the game menu: Key Bindings → AddOns → DuoBox.
For Fortitude / Shield / Renew / Heal / Dispel, DuoBox also routes Shift+key and Ctrl+key to the button
(WoW binds Ctrl+F1..F10 to the stance bar by default, which would swallow Ctrl+F2). A Shift/Ctrl+key you bound
yourself to another action is left alone.

## 4. Macros created by `/duo macros`
### Priest (target = hunter; **Shift** = pet, **Ctrl** = yourself)
| Macro | Effect | Suggested key |
|---|---|---|
| D-Follow | `/follow` the hunter | `F` |
| D-Wait | stop following (`/follow player`) | `G` |
| D-Talk | target the hunter's target (NPC), talk to it, accept / turn in its quests | `T` |
| D-Smite / D-SWP / D-Wand | assist the hunter then Smite / Shadow Word: Pain / Wand | `4` `5` `6` |
| D-SmiteW | assist the hunter, stop following, then Smite | |
| D-LHeal, D-Heal, D-Flash | heals | `1` `2` `3` |
| D-Renew | Renew | `Q` |
| D-Shield | Power Word: Shield | `E` |
| D-Fort | Power Word: Fortitude | `R` |
| D-Dispel / D-CureDis | Dispel Magic / Cure Disease | `Z` `X` |
| D-FearWard | Fear Ward (Dwarf racial) | `C` |
| D-Rez | Resurrection on the hunter | `V` |

Example: `Shift+E` = shield on the pet, `Ctrl+1` = heal yourself.
Spells with a cast time (D-SmiteW, D-Wand, D-LHeal, D-Heal, D-Flash, D-Rez) stop following first (`/follow player`),
otherwise the follow moves the priest and interrupts the cast. Follow again afterwards (D-Follow / "follow").

### Hunter
| Macro | Effect |
|---|---|
| D-Attack | pet attacks + Auto Shot (does not toggle it off if already active) |
| D-Mark | Hunter's Mark + pet attacks |
| D-Assist | take the priest's target + pet attacks (to peel a mob off the priest) |
| D-PetFollow / D-PetPassif | recall the pet / passive + recall |
| D-FD | recall the pet + Feign Death |
| D-Invite | invite the priest |
| D-Talk | target the priest's target (NPC), talk to it, accept / turn in its quests |

**D-Talk**: the macro targets the partner's target, arms DuoBox for 20 s (`/duo npc`) and interacts with the NPC (`/interact`).
While armed, DuoBox opens the NPC's quests, turns in completed ones first, accepts available ones, and takes the reward
when there is no choice (with a choice it alerts you and waits). Talking to an NPC by hand is never automated.
The **Talk** button of the bar does the same and can be bound with `/duo keys` (e.g. `T`, the key of the "talk" voice command),
so the macro does not need to be on an action bar.
You must be in interaction range (walk closer, or enable "Click-to-Move" so the interaction walks to the NPC).
DuoBox tells you in the chat when it fails: partner has no target, target is not a friendly NPC, or no window
opened after 1.5 s (too far: walk closer and press the interact key, "interact" / `²`, within the 20 s).
`/duo autonpc off` disables it.

Spell names are in English (enUS client). A spell not learned yet shows "?" and does nothing.
To cast a lower rank (saves mana), add `(Rank 2)` in the macro: `Lesser Heal(Rank 2)`.

## 5. Typical flow
1. The hunter leads: invites (D-Invite) and picks up quests → they are shared and auto-accepted by the priest.
2. Switch to the priest: Follow, Fortitude (then Shift for the pet). Switch back to the hunter.
3. The hunter shoots, the pet tanks. Stay on the hunter **as long as no alert sounds**.
4. "Low health" or "priest aggro" alert → switch to the priest, heal or shield (1 key = 1 spell), Follow again,
   switch back to the hunter.
5. Between fights: switch to the priest to drink, then Follow.

Tip: park the priest slightly behind before pulling (instead of a tight follow) to avoid extra adds.

## 6. VoiceKeys (voice commands, optional)
Folder `DuoBox\VoiceKeys`. Run it **only on the priest's PC / client**. Two engines share the same `commands.json`:

| Engine | Start | Notes |
|---|---|---|
| **Vosk** (recommended) | `Setup-VoiceKeys.bat` once, then `Start-VoiceKeys-Vosk.bat` | Offline, free (Apache 2.0). Restricted to the command list, so single words are recognized reliably. Needs Python 3. |
| Windows speech | `Lancer-VoiceKeys.bat` | Nothing to install (Windows PowerShell 5.1). Needs the en-US speech recognizer (Settings → Time & language → Language & region → add "English (United States)" with speech recognition). Less accurate. |

`Setup-VoiceKeys.bat` creates a Python virtual environment in `VoiceKeys\.venv`, installs `vosk` and `sounddevice`
and downloads the English model `vosk-model-small-en-us-0.15` (~40 MB) into `VoiceKeys\model`.

- 1 phrase = 1 key, sent only when WoW is the foreground window on that PC. No sequences, no loops.
- **Microphone**: `audioDevice` in `commands.json` selects it by name (e.g. `"G435"`), by index, or `null` for the
  Windows default. List devices with `Start-VoiceKeys-Vosk.bat --devices`. Check it: the Windows default is often a webcam.
- Keys F1 to F12 (this WoW client does not recognize F13-F24). Reserve them for the priest.
  To bind: click a row in `/duo keys`, then **say the phrase**: VoiceKeys sends the key and it gets recorded.
  Same for the D-xxx macros through the game's Key Bindings menu.
- The "pet" commands send Shift + the same key: Shift = pet on the DuoBox buttons and the D-xxx macros.
  "buff yourself" / "heal yourself" send Ctrl + the same key: Ctrl = yourself.
- With a single PC, the key goes to whichever WoW window is active: speak while the priest window is focused.

| Phrase | Key | Phrase | Key |
|---|---|---|---|
| follow / follow me | F1 | wait | F6 |
| buff | F2 | heal / heal me | F7 |
| buff pet | Shift+F2 | drink | F8 |
| assist | F3 | dispel | F9 |
| shield | F4 | resurrect | F10 |
| shield pet | Shift+F4 | smite | F11 |
| renew | F5 | wand | F12 |
| renew pet | Shift+F5 | interact | ² |
| talk | T (D-Talk macro) | dot | Y (Shadow Word: Pain) |
| buff yourself | Ctrl+F2 | heal yourself | Ctrl+F7 |
| sit | F6 (Sit button) | smite wait | Shift+F11 (Smite + Wait) |

Settings in `commands.json`:
- `commands`: key and phrases (several phrases per command are allowed).
- Keys: F1-F24, letters, digits, `NUMPAD0-9`, named keys, or any single character of your layout (e.g. `"²"` on AZERTY).
- `voskMinConfidence` (Vosk) / `minConfidence` (Windows): raise them if you get false triggers.
- `noiseGate` (Vosk): `"auto"` measures the background noise at startup (stay silent 1.5 s) and turns anything quieter
  than `noiseGateFactor` × that level into silence; a number sets a fixed level; `0` disables it.
  Without it, steady noise (fan, mic hiss, game sound) can end up matched to a command after ~30 s.
  `Start-VoiceKeys-Vosk.bat --level` shows the live microphone level to tune it.
- `maxUtteranceSec` (Vosk): a "phrase" longer than this is ignored (commands are short).
- `prefix`: e.g. `"priest"` → you must say "priest shield".
- `pausePhrases` / `resumePhrases`: "stop listening" / "start listening".
- Beeps: low = command not understood, double = WoW not in the foreground (`beepOnReject`, `beepOnNotFocused`);
  `beepOnSuccess` for a high beep on every command sent.
- `showIgnored`: shows what was heard but is not a command (useful to tune phrases).

Test without microphone or key presses: `Start-VoiceKeys-Vosk.bat --selftest` or `Lancer-VoiceKeys.bat -SelfTest`.

### Hunter combat-exit notifications in the terminal

This feature is disabled by default. To opt in, set `FEATURES.combatMonitor = true` in `DuoBox.lua`
and `combatMonitor.enabled = true` in `VoiceKeys/commands.json`, then reload the hunter's interface
(`/reload`) and run `/duo combatlog on`. The addon feature flag overrides previously saved settings:
when false, it hides the signal and stops combat-exit tracking.

Once enabled, DuoBox shows nine tiny colored squares near the top-left corner of the hunter's game area,
and `/duo combatlog off` hides it. This is DuoBox's screen signal, not WoW's `/combatlog` file logging command.

- **With Vosk**: start `Start-VoiceKeys-Vosk.bat` as usual. Notifications share its terminal with voice commands.
- **Without voice recognition**, or alongside the Windows speech engine: start `Start-CombatMonitor.bat`.
  It only needs Python 3 (uses the existing `.venv` if present), without a microphone, model or extra packages.
  Run just one combat monitor to avoid duplicate notifications in different terminals.

Run the reader on the hunter's PC. It automatically finds visible WoW windows, including on another monitor
and when the priest or terminal has focus. Keep the hunter in windowed/windowed fullscreen mode and keep
its colored squares visible: a minimized window, another window covering the squares, a hidden interface,
or some fullscreen/HDR capture configurations can prevent reading. The terminal reports a lost signal after
two seconds; when visible again, the counter recovers exits from the same interface session (up to 4095).
A `/reload` creates a new session and baseline. Exits before the first confirmed reading are not announced.

After the initial `Combat : hunter detecte` message, each `PLAYER_REGEN_ENABLED` event on the hunter produces:

```text
[18:42:07] HUNTER : sortie de combat (World of Warcraft, PID 1234).
```

This tracks the hunter leaving combat, including Feign Death when it actually clears combat; it does not
claim that all enemies are dead or that the priest/pet has left combat. Timestamps are the reader's local
detection time; recovered events share the recovery time. No keys or game actions are sent by the monitor.

In `commands.json`, `combatMonitor.enabled` turns the reader on/off and `combatMonitor.pollIntervalMs`
sets the interval (100 ms by default, 50–5000 ms accepted). `Start-VoiceKeys-Vosk.bat --no-combat-monitor`
disables it for one voice session. The Vosk `--selftest`, `--devices` and `--level` modes do not start it.
