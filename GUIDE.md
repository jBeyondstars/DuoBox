# DuoBox: duo-boxing a Dwarf Priest + Night Elf Hunter (WoW Classic / WoW Forever)

DuoBox is a World of Warcraft Classic addon (plus an optional voice tool) for playing two characters at once:
the hunter is played normally, the priest follows and heals. A warrior can take the hunter's place
(warrior buttons, macros and voice commands below).
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
| **RXPGuides** | leveling guide: enable it on the hunter (the leader) only; DuoBox adds the priest's objective progress to it ([details](#restedxp-partner-objectives)) |
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
Everything in this guide can be done from the **options panel**: type `/duo` or click the DuoBox minimap button
(left click: panel, right click: key bindings, drag: move the button; `/duo minimap off` hides it). It is also listed in
the game options under AddOns → DuoBox. Tabs: General (partner, role, actions such as macros, key bindings, alert test,
CVars, move mode), Alerts (sound, flash, thresholds), Automation, Display, RestedXP, Profiles. `/duo help` lists the equivalent commands.
```
/duo partner PriestName      (on the hunter)
/duo partner HunterName      (on the priest)
/duo macros                  (creates the D-xxx macros in the character tab of /macro)
/duo test                    (switch to the other window: this one must beep and flash)
```
Only the first name matters (`Multi`, `Multi Boxing` and `Multi-Realm` all match). Both characters may share the same
first name (`Duo Box` and `Duo Boxtwo`): each client ignores its own messages.
The role is automatic (priest = heal, hunter = dps; `/duo role heal|dps|auto` to force it). Thresholds: `/duo hp 50`, `/duo pet 35`, `/duo mana 20`.
`/duo status` shows the current settings and the detected partner unit (it must be `party1`).

### Leader: which character is the main
By default the hunter or warrior (dps) leads and the priest follows. To play the priest as the main with the hunter following it,
type `/duo lead heal` (`/duo lead dps` or `auto` to go back), or use "Meneur" in the General tab of the options panel.
The setting is sent to the partner when it is in the group (otherwise type it on both characters). It decides:
- who gets the **"stopped following you"** alert and which follow state the status frame shows (the leader watches the follower);
- the direction of the **"quest not taken"** reminder (the follower must take the leader's quests);
- the **cast bar** (the follower's spells and errors on the leader's screen, e.g. the hunter's "out of range");
- the **priest facing indicator**, which only runs while the priest follows.

Health, mana, pet and aggro alerts do not change: they depend on the role (heal / dps).

### Configuration profiles
A profile is a named copy of the settings, for example `Quetes` and `Donjon`, to switch between them in one click.
Profils tab of the options panel: type a name, **Enregistrer**; each saved profile has **Charger** and **Supprimer**.
- A profile holds every setting of the panel (alerts, thresholds, automation, display, RestedXP, leader, dungeon mode)
  and the spells of the warrior's **Rotation** button. It does not hold the partner, the role, the tank or the frame
  positions: they stay those of the character. A profile saved by a character without a Rotation list keeps the
  Rotation of the character that loads it.
- Profiles are saved per WoW account on this PC (`WTF/Account/<account>/SavedVariables/DuoBox.lua`): all characters of
  the account see them, the characters of another account or of the other PC have their own.
- Loading replaces the character's settings (out of combat). Later changes are not saved in the profile until you save
  it again: the tab shows "modifie depuis" and the name field is filled with the active profile.
- `/duo profile` lists them, `/duo profile save <name>` (alone: the active profile), `/duo profile load <name>`,
  `/duo profile delete <name>`. Names ignore the case.

### Dungeon mode: assist the tank
In a group with a tank, `/duo dungeon on` (or the Automation tab of the options panel), on both characters:
the attack buttons of the bar, the **Assist** button, **Rotation** and the `/assist` lines of the D- macros take the
**tank's target** instead of the partner's. Follow, Talk and the priest's heals stay on the partner.
- The tank is the group member whose role is **Tank**: right-click their portrait > Role > Tank, or a role check.
  Inside instances the client may hide roles from addons: DuoBox keeps the last tank it read.
- `/duo tank <Name>` (or "Ma cible" in the options) sets it by hand, before the role; `/duo tank auto` goes back to the role.
- No tank found, or you are the tank: the partner, as outside dungeon mode. The warrior's attacks still keep its
  own live enemy target first; the row 1 Assist button always takes the tank's (or partner's) target.
- The D- macros now name the partner's and the tank's unit (party1..party4), not party1 only: DuoBox rewrites the
  existing D- macros when these units change (group of 5, dungeon mode on or off, new tank), out of combat.

### Alerts
- **On the priest client**: hunter below 50% health, pet below 35%, hunter dead, aggro on the priest.
- **On the hunter client**: priest below 50% health, priest mana below 20%, aggro on the priest, priest dead.
- **On the leader's client** (the hunter by default): **the partner stopped following you**.
- **On both clients: quest not turned in.** When one character turns in a quest that the other still has in its log,
  the other gets 15 s to turn it in too (D-Talk / "talk"); after that both screens get an alert with the quest name
  ("(pas terminee)" when it is not complete yet). `/duo turnin off` disables it.
- **On both clients: quest not taken by the follower.** When the leader accepts a quest, the follower gets 10 s to have it
  too (automatic share, or D-Talk / "talk" when the quest cannot be shared); after that both screens get an alert with
  the quest name. `/duo accept off` disables it.
- **On both clients: quest item not looted.** When one character loots a quest item that the other still needs
  (quest items drop for each character on the quest), the other gets 10 s to loot its copy; after that both screens
  get an alert with the item name. Looting before the partner is fine too. Only objectives that need a single item
  (`0/1`) are checked: objectives like `0/8` drift apart during farming and are left out. `/duo loot off` disables it.
- A small movable status frame shows the partner's health, mana and follow state.
- **Aggro on the priest** is detected from threat, from a mob targeting the priest (enemy nameplates must be shown, `V` key)
  or from damage taken, and triggers a sound alert on both screens.

### Button bar
Always shown, semi-transparent, opaque on mouse-over. Shift+drag to move it, `/duo bar off` to hide it,
`/duo scale 1.3` to resize it. Icons are greyed out when the partner is not in the group.

- **Row 1**: **Follow** (toggle: follows the partner, or stops following if already following) · **Target** · **Assist** · **Talk** (same as the D-Talk macro) · **Sit** (`/sit`) · **Trade** · **Invite** · **Compare quests** · **Share last quest** · **Key bindings** (gear).
- **Row 2 (priest only)**: **Fortitude** · **Shield** · **Renew** · **Heal** (Lesser Heal, then Heal once learned) · **Dispel** ·
  **Resurrection** · **Smite**, **Smite + Wait**, **Shadow Word: Pain** and **Wand** (assist the hunter + spell) · **Wait** (stop following) · **Drink** (best drink in your bags for your level).
- **Row 2 (hunter only)**, for when the hunter follows the priest: **Auto Shot**, **Serpent Sting**, **Arcane Shot**,
  **Concussive Shot**, **Raptor Strike** (assist the priest + pet attacks + shot) · **Melee** (assist + pet attacks + melee auto-attack) · **Wait** (stop following).
  **Auto Shot** stops following first (it does not fire while moving) and does not toggle it off if already active.
  **Arcane Shot** and **Concussive Shot** also stop following, so Auto Shot keeps firing after them.
  **Arcane Shot** casts Serpent Sting first on a new target (or after combat), then Arcane Shot; the 3rd Arcane Shot
  (~18 s) loops back to Serpent Sting (lasts 15 s). It always takes the priest's target, so it follows the priest's
  target switches in combat. It does not see the real debuff (resist, dispel).
- **Row 2 (warrior only)**: **Battle Shout** · **Charge** · **Melee** · **Rotation** · **Multi** · **Heroic Strike**, **Rend**, **Sunder Armor**,
  **Thunder Clap**, **Hamstring**, **Overpower**, **Execute**, **Taunt**, **Kick** · **Wait** (stop following).
  The warrior usually leads, so its attacks **keep its own enemy target** and only take the partner's when it has none
  (no target, a friendly or a dead one); the **Assist** button of row 1 forces the partner's target.
  Every attack stops following (the follow would drag the warrior away from its target) and starts the melee auto-attack;
  Battle Shout keeps following.
  **Charge** switches to Battle Stance first when needed (first press, out of combat only) and charges on the next press;
  in combat, where Charge cannot be used, it switches to the partner's target instead (only a live enemy one);
  **Taunt** does the same with Defensive Stance (a stance must be active before the game allows the spell, hence the
  two presses). **Kick** interrupts: Shield Bash with a shield equipped (the game allows it in Battle or Defensive
  Stance), Pummel without a shield or in Berserker Stance (the game allows Pummel in Berserker Stance only).
  **Melee** attacks the target and, with Click-to-Move enabled
  (Interface options → Mouse), walks to it like the Talk button; it does nothing without an enemy target.
  **Rotation** is a one-button attack for a pedal or a single key, with the same target and follow rules as the other
  attacks: each press casts the first usable spell of your list, from top to bottom (default: Battle Shout when it is
  missing, otherwise Overpower when the game allows it, otherwise Heroic Strike). The game itself skips what is not
  usable, so 1 press = 1 action; see "Rotation panel" below to change the list.
  The expected failures of a press (Overpower not ready, global cooldown, not enough rage, wrong stance) are hidden,
  silent and not relayed to the partner.
  **Multi** (key, or the voice command "multi") switches Rotation to its multi-target spells until the end of the
  fight, for example Thunder Clap on a pack; it casts nothing itself. Pressed out of combat, it is kept for the next
  fight, until its end. Rotation and Multi glow while it is on, and the chat says when it starts and stops;
  right-click Multi to go back to single target. Put the multi-target spells above Heroic Strike in the list (or mark
  Heroic Strike "Mono seulement"): queued on every press, it spends the rage Thunder Clap needs. A macro cannot count enemies and an addon cannot change it during a
  fight: Blizzard's secure "attribute" action, triggered by your press, is what writes the multi-target macro.
- Fortitude / Shield / Renew / Heal / Dispel: click = partner, **Shift** = partner's pet, **Ctrl** = yourself.
- **Heal**, **Resurrection** and **Smite + Wait** stop following before casting (moving would interrupt the cast):
  follow again afterwards. **Wand** keeps following (use **Wait** first if the priest must stand still).
  Fortitude gets a golden border when a buff is missing or expires in less than 2 minutes (out of combat only).
- **Compare quests** shares your quests that the partner is missing and tells you which ones they have in addition
  (then click "Compare" on their window).

### Rotation panel (warrior)
Right-click the **Rotation** button, `/duo rotation`, or **Sorts du bouton Rotation** in the options panel.
The list is saved per character (10 spells at most):
- **Add** a spell by dragging it from the spellbook onto the panel, or by typing its name and pressing Enter.
- **Order**: arrows up / down; the game tries the spells from top to bottom on each press.
- **Mode** of each spell:
  - **Chaque appui** (each press): tried on every press, skipped by the game when it is not usable. This fits the
    attacks the game gates by itself: Overpower after a dodge, Execute under 20%, a cooldown, not enough rage.
    A spell that is always usable (Rend, Sunder Armor) would be cast on every press and block the spells below it.
  - **1x par combat** (once per fight), for your own buffs (Battle Shout): cast before the attacks when the buff is
    missing, or ends within 30 s, as the fight starts. Macros cannot check buffs and cannot change during a fight,
    so this is decided out of combat and cast once (with 10 rage for Battle Shout); the icon shows the buff until then.
    The buff must have the spell's name. If it ends during the fight, an alert names it (with the Battle Shout key),
    only when the client can read auras in combat.
- **Cibles** (targets) of each spell: **Toujours** (always), **Multi seulement** (only after the Multi button, e.g.
  Thunder Clap) or **Mono seulement** (skipped in multi-target mode).
- **Actif** (enabled): unchecked keeps the spell in the list without casting it. Spells not learned yet are skipped.
- **Par defaut** restores Battle Shout (once per fight), Overpower, Thunder Clap (multi only), Heroic Strike.
- The bottom of the panel shows both macros, single and multi target. Changes made in combat apply at the end of the
  fight.

### Partner cast bar (leader screen)
Yellow while casting, blue for an instant spell, green on success, red when interrupted / failed.
It also shows the follower's spell errors (out of range, line of sight, not enough mana or rage, wrong facing,
wrong stance…).
By default the priest follows, so this is the priest's cast bar on the hunter's screen (see `/duo lead`).
`/duo castbar off` to hide it.

### Priest facing indicator (hunter screen)
For Smite and the wand the priest must face their target. When the priest has an enemy target, the hunter screen shows
which way to turn (left / right with the angle) or that the priest is facing correctly.
- The game does not expose mob positions, so the target position is estimated from the pet (if it attacks the same target)
  or from a point in front of the hunter. If positions are blocked, it falls back to "face the same direction as the hunter"
  (shown as *approx.*).
- With a warrior partner the point is taken 3 yd in front of it, since it stands next to its target
  (the distance setting only applies to the hunter).
- Does not work in dungeons (positions are blocked there). The priest's "wrong facing" error still triggers an alert.
- `/duo facing invert` if left/right are swapped, `/duo facing dist 30` to change the estimated distance,
  `/duo facing off` to hide it, `/duo facing debug` to see which values the client can read.

### Warrior light (priest screen)
While the warrior (or a rogue) fights, a big light on the partner's screen: **green** = attacking its target in melee
range, **red** with the reason = **TROP LOIN** (too far), **MAL ORIENTE** (facing the wrong way), **N'ATTAQUE PAS**
(auto-attack off) or **PAS DE CIBLE** (in combat without an enemy target). Hidden out of combat.
- Range: every 0.2 s the warrior's client asks whether its target is in range of the learned rank of Heroic Strike
  (by spell ID, then by spellbook slot, then by name), plus the "out of range" / "too far" errors.
- Facing: the game tells no addon whether you face a mob, so it comes from the "facing the wrong way" error of a
  failed swing or spell: red from the first failed attack until a harmful spell lands (Heroic Strike, Rend...),
  a new target, or 4 s. Battle Shout or Bloodrage need no facing and do not clear it.
- Optional sound, off by default ("Son quand il reste rouge" in the Alerts tab, or `/duo lightsound on`): after 1 s
  of red, then every 3 s while it stays red, a sound per reason (too far, facing the wrong way, not attacking / no
  target). It also follows the Sound option. The answer is one press on the warrior's interact key: with
  Click-to-Move it runs back to its target, faces it and attacks (an addon cannot move or turn a character by itself).
- Move and resize: `/duo move` (or the "Deplacer" button of the options), drag the light, drag its bottom-right
  corner to resize it (it stays square); `/duo move` again to save. `/duo light reset`: default place and size.
- `/duo light debug` on the warrior, during a fight: what the client answers (combat, target, auto-attack, each
  range source, last errors) — useful if the light stays green when it should not.
- On by default on both characters, `/duo light off` or the Display tab to hide it.

### Partner gathering detections (experimental)

Enable **Partager les detections (experimental)** in `/duo` → **Affichage** on both characters,
or use `/duo tracking on`. This is disabled by default. Set each character's partner name and group together.
The gathering character must have **Find Minerals** or **Find Herbs** active. DuoBox shares only the active
gathering tracker; it does not activate a spell or give the other character a profession.

WoW does not expose the list or coordinates of native yellow tracking dots. DuoBox checks their **native
minimap tooltips automatically**, using known GatherLite spawn locations to aim the scan: it briefly moves
the minimap beneath the stationary cursor. You do not need to hover a resource manually or gather it first.
Only a tooltip naming a mineral or herb confirms a detection; GatherLite's historical icons are ignored.
The partner gets a mineral/herb icon on their minimap, with its name on hover.

- **GatherLite with its node database is required on the scanning character**, including its
  `GetNearbyZoneNodes` API. The receiver only needs HereBeDragons, supplied by GatherLite, TomTom or Questie.
- The positions are the known spawn locations confirmed by tooltip, so they are approximate. A spawn
  missing from GatherLite's database cannot be found by this scan.
- A pass starts every 5 seconds, samples up to 32 locations within 100 yards and lasts at most 1.5 seconds.
  Larger candidate lists continue across passes. Low background FPS reduces how many locations can be checked.
- The source minimap briefly disappears or flickers during a pass; native dots and the player arrow may remain
  visible under the cursor. DuoBox preserves existing textures and restores minimap anchors and mouse settings.
- Scanning pauses in combat, during camera rotation, while dead, in instances or when targeting a spell.
  Received markers expire after 15 seconds without confirmation, or when the partner disconnects or disables sharing.
- This indirect scan needs an **in-game compatibility check on WoW Forever / the beta client**, particularly
  in the background window. Automated tests cannot confirm how that client resolves native hover tooltips.

`/duo tracking` shows the state and counters; `/duo tracking scan` checks immediately. If a live scan raises a
Lua error, DuoBox restores the minimap and disables sharing; its diagnostic is shown in the panel and chat.
To verify in game, stand near a visible yellow resource dot, enable sharing on both clients, scan on the
gathering character, and check the counters and the other minimap. Repeat after switching to the other window.

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

### Interact key: enemy target first
With "Enable Interact Key" (Options → Controls), WoW's interact key (Key Bindings → Targeting → Interact With Target)
goes to the **soft interact target** first: the object, corpse or NPC showing the interact icon, even when your target
is an enemy. "Assist the priest + interact key" then picked up a nearby object instead of walking to the enemy.

On the warrior (on by default for melee classes), DuoBox switches soft interaction off **while your target is a live
enemy, and in combat also while the partner's target is one**: the interact key then goes to your target, starts the
auto-attack and, with Click-to-Move enabled, walks to it. Meanwhile the interact icon disappears from objects.
Once your enemy is dead (or you clear your target) and the fight is over, the key picks up loot and objects again,
even if the partner already targets the next mob. In combat, while the partner targets an enemy and you have no
target, the key does nothing: assist first.
- The change is a temporary CVar (`SoftTargetInteract` = 0), never saved: your setting comes back by itself.
- `/duo interact on|off`, or the Automation tab of `/duo`; `/duo interact` alone tells whether objects are skipped
  and why. Needs WoW Forever: Classic Era 1.15 has no temporary CVars.

### RestedXP: partner objectives
RestedXP only tracks the quests of the character it runs on. DuoBox sends each character's quest progress to the partner,
so the guide also counts the partner:
- Each quest objective of the current step shows the partner's count after yours, for example
  `Kobold Vermin slain: 10/10 [Priest 6/10]` (the partner's class; yellow: in progress, green: done,
  orange: the partner does not have the quest).
- The objective is only checked once **both** characters have finished it, so the guide does not move on
  while the partner still needs kills or items. Ticking the objective's box by hand still skips it.
- DuoBox must be up to date on both characters; RestedXP is only needed on the character that shows the guide.
- If the partner does not have the quest, is offline or not in the group, the guide works as usual (it never blocks).
- Only quest objectives (`.complete` steps) are shared; item collection outside quests (`.collect`) stays per character.

`/duo rxp` shows the state, `/duo rxp off` / `on` hides or shows the partner's progress,
`/duo rxp hold` switches "wait for the partner" off or on, `/duo rxp sync` resends both quest logs.

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
Spells with a cast time (D-SmiteW, D-LHeal, D-Heal, D-Flash, D-Rez) stop following first (`/follow player`),
otherwise the follow moves the priest and interrupts the cast. Follow again afterwards (D-Follow / "follow").
D-Wand keeps following.

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
| D-Follow / D-Wait | `/follow` the priest / stop following (when the priest leads) |
| D-Shoot | assist the priest + stop following + pet attacks + Auto Shot |
| D-Serpent | assist the priest + pet attacks + Serpent Sting (keeps following) |
| D-Arcane | same as the Arcane Shot button: assist the priest + stop following + pet attacks + Serpent Sting on a new target, then Arcane Shot ×3 |
| D-Concussive | assist the priest + stop following + pet attacks + Concussive Shot (slow) |
| D-Raptor | assist the priest + pet attacks + melee attack + Raptor Strike |
| D-Melee | assist the priest + pet attacks + melee auto-attack |

### Warrior
Same targeting as the warrior buttons: keep your own enemy target, otherwise take the priest's.
The attacks stop following and start the melee auto-attack.

| Macro | Effect |
|---|---|
| D-Follow / D-Wait | `/follow` the priest / stop following (when the priest leads) |
| D-Talk | target the priest's target (NPC), talk to it, accept / turn in its quests |
| D-Charge | Battle Stance if needed (1st press, out of combat), then Charge; in combat (Charge is not usable there) it switches to the priest's live enemy target instead |
| D-ChargeP | always takes the priest's target (even with your own enemy target), starts the auto-attack, Battle Stance if needed then Charge; the next press after a Charge that succeeded queues Heroic Strike, once per fight (Charge rage arrives on impact, too late for the same press); out of combat also `/interact` (walks to the target with Click-to-Move); keeps following |
| D-Melee | melee auto-attack; walks to the target with Click-to-Move |
| D-Strike / D-Rend / D-Sunder | Heroic Strike / Rend / Sunder Armor |
| D-Clap / D-Hamstring | Thunder Clap / Hamstring |
| D-Overpower / D-Execute | Overpower / Execute (only when the game allows them) |
| D-Taunt | Defensive Stance if needed (1st press), then Taunt |
| D-Kick | same as the Kick button: Shield Bash with a shield, Pummel without one or in Berserker Stance |
| D-Invite | invite the priest |

Battle Shout needs no target: use the button of the bar or the spellbook. WoW binds the stances to Ctrl+F1 / F2 / F3
by default (stance bar): keep those keys free on the warrior. The "defense" voice command sends Ctrl+F2 (Defensive Stance).

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
| follow / follow me | F1 (toggle: say it again to stop) | wait | S |
| buff | F2 | heal / heal me | F7 |
| buff pet | Shift+F2 | drink | F8 |
| assist | F3 | dispel | F9 |
| shield | F4 | resurrect | F10 |
| shield pet | Shift+F4 | smite | F11 |
| renew | F5 | wand | F12 |
| renew pet | Shift+F5 | interact | ² |
| talk | T (D-Talk macro) | dot | Shift+F6 (Shadow Word: Pain) |
| buff yourself | Ctrl+F2 | heal yourself | Ctrl+F7 |
| sit | F6 (Sit button) | smite wait | Shift+F11 (Smite + Wait) |

Hunter commands, for when the hunter follows the priest (`/duo lead heal`). Bind these keys on the hunter with `/duo keys`
(row 2 of the hunter), and speak while the hunter window is focused. They reuse the priest's attack keys (no Alt keys:
Alt+F4 closes the window and Alt+key is unreliable), so saying them on the priest window casts the priest's equivalent
(e.g. "shoot" = F12 = Wand). The shared commands (follow, wait, assist, talk, interact, sit) work on the hunter too
if you bind the same keys there.

| Phrase | Key | Hunter button | Same key on the priest |
|---|---|---|---|
| shoot | F12 | Auto Shot (assist + stop following + pet attack) | Wand |
| serpent | Shift+F6 | Serpent Sting | Shadow Word: Pain |
| arcane | F11 | Serpent Sting on a new target, then Arcane Shot (assist + stop following + pet attack) | Smite |
| slow | Shift+F10 | Concussive Shot (assist + stop following + pet attack) | (unused) |
| raptor | Ctrl+F11 | Raptor Strike | (unused) |
| melee | Shift+F12 | Melee auto-attack | (unused) |

Warrior commands: bind these keys on the warrior with `/duo keys` (row 2 of the warrior) and speak while the warrior
window is focused. Each spell answers to its name. Like the hunter, the main attacks reuse the priest's keys; the others
use keys unused on the priest. The priest phrases on the same keys work too ("buff" = Battle Shout, "dot" = Rend).
If "renew" ends up recognized as "rend" on the priest (Shadow Word: Pain instead of Renew), remove the "rend" phrase
and say "dot".

| Phrase | Key | Warrior button | Same key on the priest |
|---|---|---|---|
| shout / battle shout | F2 | Battle Shout | Fortitude |
| charge | F12 | Charge (Battle Stance first if needed) | Wand |
| heroic / heroic strike | F11 | Heroic Strike | Smite |
| rend | Shift+F6 | Rend | Shadow Word: Pain |
| melee | Shift+F12 | Melee (walks to the target with Click-to-Move) | (unused) |
| sunder | Ctrl+F11 | Sunder Armor | (unused) |
| thunder clap | Ctrl+F12 | Thunder Clap | (unused) |
| hamstring / slow | Shift+F10 | Hamstring | (unused) |
| overpower | Shift+F8 | Overpower | (unused) |
| execute | Shift+F3 | Execute | (unused) |
| taunt | Shift+F1 | Taunt (Defensive Stance first if needed) | (unused) |
| multi | Ctrl+F10 | Multi (Rotation in multi-target mode until the end of the fight) | (unused) |
| defense | Ctrl+F2 | Defensive Stance (WoW's stance bar, no DuoBox button to bind) | Fortitude on yourself |
| kick | Ctrl+F8 | Kick (Shield Bash with a shield, otherwise Pummel) | (unused) |

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
