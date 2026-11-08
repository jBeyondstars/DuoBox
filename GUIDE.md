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
  **One exception, outside the addon**: the optional DuoRelay tool ([section 7](#7-duorelay-ctrlclick-relayed-to-pc-2-optional-not-allowed-by-blizzard))
  makes a Ctrl+click on PC 1 press keys in the client on PC 2. That is input broadcasting, which this policy
  forbids. It is off unless you start it and switch it on.
- Always check the official multiboxing policy of the realm type you play on.

## 1. Windows / screens
1. Start the first client and log in with account A (hunter). Start a second client (click "Play" again in Battle.net,
   or run the client executable a second time, e.g. `_forever_\Wow.exe`) and log in with account B (priest).
2. Display mode: **Windowed (Fullscreen)** in both clients. Move the second window to the other screen with `Win+Shift+→`.
   In windowed fullscreen, a single **click** on the other screen switches focus (faster than alt+tab).
3. Type `/duo cvars` once: enables sound in the background (needed to hear the priest's alerts while playing the hunter)
   and auto loot.
4. If the background client drops to very low FPS: disable Windows Game Mode, set `Wow.exe` to "High performance"
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
  and the spells of the **Rotation** button, one list per class: saving the profile on the priest keeps the warrior's
  list in it, and each character loads only its own class's list. It does not hold the partner, the role, the tank or
  the frame positions: they stay those of the character. A profile without a list for your class keeps your Rotation.
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
- **Rotation** · **Multi** (every class, at the end of row 2; among the attacks for the warrior): the same one-button
  rotation with its own list per class (empty at first except for the warrior; see "Rotation panel"). It keeps your
  live enemy target or takes the partner's, stops following, then starts the auto-attack (warrior, rogue, paladin,
  shaman, druid) or sends the pet (hunter, warlock); priests and mages only cast. Mana, energy and "another action
  is in progress" failures of a press are hidden too.
- Fortitude / Shield / Renew / Heal / Dispel: click = partner, **Shift** = partner's pet, **Ctrl** = yourself.
- **Heal**, **Resurrection** and **Smite + Wait** stop following before casting (moving would interrupt the cast):
  follow again afterwards. **Wand** keeps following (use **Wait** first if the priest must stand still).
  Fortitude gets a golden border when a buff is missing or expires in less than 2 minutes (out of combat only).
- **Compare quests** shares your quests that the partner is missing and tells you which ones they have in addition
  (then click "Compare" on their window).

### Rotation panel (every class)
Right-click the **Rotation** button, `/duo rotation`, or **Sorts du bouton Rotation** in the options panel.
The list is saved per character, for its class (10 spells at most):
- **Add** a spell by dragging it from the spellbook onto the panel, or by typing its name and pressing Enter.
- **Order**: arrows up / down; the game reads the list from top to bottom on each press.
- **One spell on the global cooldown per press** (measured in game on 2026-11-07): a macro tries only the first
  spell of its list that is on the global cooldown, even when that spell is unusable and skipped without a word
  (Overpower without a dodge, Execute above 20% health); the spells on the global cooldown below it are not tried
  at all. Spells off the global cooldown (Heroic Strike, Cleave, Bloodrage) are always tried. No code can choose
  by the target's health at the press either: the only code that runs then is a Blizzard secure snippet, which
  sees neither health nor whether a spell is usable.
- **Attacks in turn**: so the key going down has one macro per attack on the global cooldown (that attack, then the
  spells off it, Heroic Strike), and a secure snippet sends each press to the next one: with Overpower, Execute and
  Slam, each is tried one press in three, in list order; the game itself skips Overpower without a dodge and
  Execute above 20% health. As the key is pressed several times a second, each one is tried about once a second.
  The release, a macro of its own, casts the "once per fight" buffs, then Victory Rush. The tooltip of the Rotation
  button and the panel show "1 appui sur N"; the panel shows every key-down macro. In multi-target mode the Multi
  button switches the set of macros (Thunder Clap then takes a turn too).
- **Mode** of each spell:
  - **Chaque appui** (each press): an attack off the global cooldown is tried on every press, one on it in turn
    (see above); the game gates some by itself: Overpower after a dodge, Execute under 20%, a cooldown, rage.
  - **1x par combat** (once per fight), for your own buffs (Battle Shout): cast when the key is released, just after
    the attacks, when the buff is missing, or ends within 30 s, as the fight starts. Macros cannot check buffs and cannot change during a fight,
    so this is decided out of combat and cast once (with 10 rage for Battle Shout); the icon shows the buff until then.
    The buff must have the spell's name. If it ends during the fight, an alert names it (with the Battle Shout key),
    only when the client can read auras in combat.
- **Cibles** (targets) of each spell: **Toujours** (always), **Multi seulement** (only after the Multi button, e.g.
  Thunder Clap) or **Mono seulement** (skipped in multi-target mode).
- **Actif** (enabled): unchecked keeps the spell in the list without casting it. Spells not learned yet are skipped.
- **PV min** (minimum health): a number in this column casts the spell only if the target has at least that much
  health when the fight starts; empty = always. Typed value saved with Enter or by clicking elsewhere. The macro
  cannot change during a fight, so this is decided once, at the start (out of combat: from your current target):
  your live enemy target, otherwise the partner's. Unreadable health (dungeon secrets, or a client that gives only
  percentages) casts the spell. Example: 850 for Rend, measured on 2026-11-06/07: on mobs under 1000 health, Rend
  did 2.2 of its 5 ticks on average (two in three Rends did 2 or fewer), against 3.2 on 1000-2000 health elites.
- **Victory Rush** (WoW Forever): the client always calls it unusable, even during its "Victorious" buff, and a macro
  skips an unusable spell without a word, while an action-bar key casts it. So the Rotation casts it through its
  action-bar slot (a hidden button it `/click`s): keep Victory Rush on any action bar. The tooltip of the Rotation
  button shows the slot used; the panel shows "a poser sur une barre" when it is on none. Whatever its place in the
  list, it is tried at the end of the key release, after the "once per fight" buffs: a macro tries only one spell
  on the global cooldown per press, and this click always takes that turn, even when Victory Rush cannot be cast,
  which left Overpower no turn when it was among the attacks. So it waits for a press whose key down did not just
  start a spell (Overpower, Slam's cast) and whose buffs are already cast.
- **Slam** (WoW Forever's version, with a cast time): in combat the client calls it unusable too, so the Rotation
  casts it through its action-bar slot as well, first in its own key-down macro. Keep it on an action bar. It needs
  the warrior to stand still: a pedal press (Click-to-Move) during the cast interrupts it.
- **Par defaut** restores Battle Shout (once per fight), Thunder Clap (multi only), Overpower, Heroic Strike for the
  warrior, and empties the list for the other classes.
- The bottom of the panel shows both macros, single and multi target, and under the single one what the key release
  casts. Changes made in combat apply at the end of the fight.
- **Two macros per press, 255 characters each**: the game runs only the first 255 characters of a button's macro
  and silently drops the rest (measured on 2026-11-06: with four "once per fight" spells in one macro, it reached 287
  characters and Overpower and Heroic Strike were never cast). So the key going down runs the attacks (target, auto
  attack, "each press" spells) and its release runs the "once per fight" buffs, each a `/castsequence` line in a
  fight. A buff marked **Multi seulement** or **Mono seulement** stays at the top of the key-down macro, the one the
  Multi button swaps. If one of the two macros of a fight is still over 255 characters, the panel warns in orange:
  remove a spell. (A macro run by `/click` from another macro did nothing on this client.)

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

### Event light (priest screen)
The icon of a reactive spell of the partner as soon as the game lights it up on the partner's client, so you press
the partner's key (pedal) in time; it disappears as soon as the spell goes out again (5 s window over, spell used,
target dead, end of the fight).
- Spells: warrior **Overpower** (after a dodge), **Revenge** (after a block, dodge or parry), **Execute** (target under
  20 % health), **Victory Rush** (20 s after a kill); rogue Riposte; hunter Counterattack and Mongoose Bite; paladin
  Hammer of Wrath. Only the learned ones.
- Victory Rush (WoW Forever): the client always calls it unusable, so it is lit by the game's glow on it or by its
  "Victorious" buff. The buff is hidden from addons in combat: in a fight only the glow can light it (whether the game
  glows it is not checked yet: `/duo proc debug` shows `lueur=` and `buff=`). It is the only one also reported out of
  combat, as its 20 s often start with the fight's last kill.
- **Gold and pulsing** = ready. **Grey** with "pas assez de rage" = lit but not enough rage (energy, mana) yet. Several
  lit at once: the first one of the list above is shown big, the others are written under the light.
- Choose the spells in the Alerts tab ("Voyant des evenements du partenaire"): one checkbox per spell of the partner's
  class (the partner must be in the group for the panel to know its class). Saved in profiles.
- How: every 0.1 s, during a fight, the partner's client asks the game whether each spell is usable (or only short of
  rage), glowing, and not on its own cooldown (the global cooldown is ignored), then sends the change at once on its
  own addon prefix. The game hides the combat log and the auras in combat from addons on this client, so buffs such as
  Clearcasting cannot be shown.
- Move and resize: like the warrior light (`/duo move`, bottom-right corner); `/duo proc reset`: default place and size.
- `/duo proc debug` on the warrior, during a fight: what the client answers for each spell (usable, short of rage,
  glow, cooldown) and what it sent; on the priest: the last state received.
- On by default on both characters (both need it: the warrior's client detects, the priest's displays),
  `/duo proc off` or the checkbox in the Alerts tab to hide it. No sound.

### Combat journal (measurement, off by default)
To measure what really costs the warrior time in hard fights (several enemies that move) before changing anything.
`/duo journal on`, or **Journal de combat** in the Display tab, on the warrior (and on the priest to also count its
key presses). The first time, restart the game completely (new file and new SavedVariables in the `.toc`).
- Each fight goes to `DuoBoxJournal`, in the character's SavedVariables file (written at `/reload` or logout):
  light state and reason, your target and the partner's (with dead / alive), every key press (action bar slot with its
  macro name, interact key, DuoBox buttons), `/assist` and `/target` lines, red error texts, spells cast, live enemies
  on the nameplates (show them with `V`), and flee emotes. Nothing is cast, targeted or sent to the partner.
- Switching it on also starts the game's combat log in advanced mode (`advancedCombatLogging` = 1: position and
  facing of every unit that acts, which no addon can read during a fight), in `_classic_beta_\Logs\WoWCombatLog*.txt`.
  Switching it off stops the combat log only if the journal started it.
- `/duo journal`: summary (entries, fights, red seconds per reason). `/duo journal clear`: empty it.
  `/duo journal cvars`: writes every targeting / interact / combat CVar of this client and its value to the file
  (`DuoBoxJournal.cvars`), e.g. to check whether `SoftTargetEnemy` exists.
- 40,000 entries at most (about 2 MB); the oldest are dropped.

**Measuring a change** (`tools\analyze_fights.py`, Python 3, standard library only):
1. Before playing, write down what counts as better, e.g. "red seconds per fight halved" or "melee uptime +15 points".
2. `/duo journal on` on the warrior (and the priest), nameplates shown.
3. Play at least 10 hard pulls, then `/reload` on the warrior so the file is written.
4. On the warrior's PC: `python tools\analyze_fights.py --json before.json`. It finds the journals under `WTF` and
   the logs under `Logs`. On another PC, give the files: `--journal <...\SavedVariables\DuoBox.lua>` (several allowed,
   e.g. the priest's file copied from PC 1) and `--combatlog <WoWCombatLog...txt>`.
5. After a change, the same kind of pulls: `--since "YYYY-MM-DD HH:MM" --json after.json`, then
   `python tools\analyze_fights.py --compare before.json after.json`.

The report gives, per fight, the duration, enemies, melee uptime, red seconds per reason, pedal presses and the time
from a kill to the next swing; then a Pareto of the red causes (with "after a kill", "pedal to a corpse", "partner
without a live target", "flee"), what each pedal press did to the target, and, with the advanced log, the real
distance at "too far" and the real angle at "facing the wrong way" (checks the light itself). Melee uptime comes from
the combat log (each swing covers 1.25 × the weapon speed), not from DuoBox's light. The journal and the combat log
are aligned on the spells found in both (the report shows the spread).

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
- This indirect scan needs an **in-game compatibility check on WoW Forever**, particularly
  in the background window. Automated tests cannot confirm how that client resolves native hover tooltips.

`/duo tracking` shows the state and counters; `/duo tracking scan` checks immediately. If a live scan raises a
Lua error, DuoBox restores the minimap and disables sharing; its diagnostic is shown in the panel and chat.
To verify in game, stand near a visible yellow resource dot, enable sharing on both clients, scan on the
gathering character, and check the counters and the other minimap. Repeat after switching to the other window.

### Moving and resizing
`/duo move` shows the cast bar, the facing text, the warrior light and the event light with sample content so you can drag them;
the bottom-right corner of the cast bar (or of a light) resizes it. Type `/duo move` again to save.

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

On the warrior (on by default for melee classes), DuoBox switches soft interaction off: the interact key then goes
to your target, starts the auto-attack and, with Click-to-Move enabled, walks to it. Meanwhile the interact icon
disappears from objects.
- **Out of combat**: while your target is a live enemy, or while the partner fights and its target is one.
  Once your enemy is dead (or you clear your target) and the fight is over, the key picks up loot and objects again,
  even if the partner already targets the next mob.
- **In combat**: off for the whole fight. The game refuses setting changes from an addon during a fight
  (`ADDON_ACTION_BLOCKED` in BugSack), so DuoBox switches it off as the fight starts, like Blizzard's gamepad
  targeting, and back after the fight. During a fight the key goes to your target only: it walks to a live enemy,
  loots a dead one, and does nothing without a target (assist first).
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
| D-Assist | take the partner's target (the tank's in dungeon mode) | `Shift+T` |
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

- 1 phrase = 1 key, sent only when WoW is the foreground window on that PC. No loops. One exception you configure
  yourself: a `key` written as a list (`"SHIFT-T, T"`) presses those keys once, in that order (used by "charge").
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
| charge spell | F12 | Charge (Battle Stance first if needed) | Wand |
| charge | Shift+T then T | Same as the foot pedal: the action bar button on Shift+T (partner's target), then Interact With Target (walks to it with Click-to-Move) | Shift+T, T as bound there |
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

## 7. DuoRelay: Ctrl+click relayed to PC 2 (optional, not allowed by Blizzard)
> **Warning.** One click acting in two game clients is **input broadcasting**. Blizzard forbids it whatever the
> transport: cable, local network or KVM switch. This is how ISBoxer worked across several PCs. Using it puts
> **both accounts** at risk. It is not part of DuoBox's "1 key press = 1 action in 1 client" design (section 0).

Two PCs on the same local network (Wi-Fi or Ethernet), priest on PC 1, warrior on PC 2. When the relay is ON,
a **Ctrl+left click** in the priest's WoW window (on a mob or an NPC) targets it on the priest, as usual.
DuoRelay then tells PC 2, which presses **Shift+T, then T** in the warrior's WoW, the same keys as the pedal:
take the partner's target, then the interact key. The warrior walks to the mob and attacks it, or talks to the NPC.

A **Ctrl+right click** on an object (ore vein, herb, quest object...) interacts with it on the priest, as usual,
and the warrior picks up **the same kind of object**. Needs the DuoBox option **DuoRelay > Ramassage relaye** (tab DuoRelay of the
options) on **both** characters (off by default):
- An object cannot be targeted, and this client gives no identifier for the object under the mouse (checked in
  game). The priest's DuoBox reads its **name** from the tooltip ("Copper Vein") and sends it to the warrior.
- PC 2 presses **Ctrl+Shift+F9**, 0.5 s after the click (`delayMs` of the `pickup` trigger), so the name arrives first.
  The warrior's DuoBox makes that key the interact key only while the warrior's own nearest object
  (soft interact target, `SoftTargetInteract` 3, range 50) has the same name, for 3 s. Otherwise it does nothing.
- The priest's screen says what happens: `<warrior> ramasse : Copper Vein`,
  `<warrior> : pas de Copper Vein a portee (il vise : Peacebloom)`, `... est en combat`, or `... ne repond pas`
  (option off on the warrior, or an old DuoBox).
- Same kind, not the same object: with two veins side by side, the warrior may take the other one.
  Out of combat only (key bindings cannot change in combat). Both games must use the same language (names).
- If the warrior is out of range at first, it still picks up when the object comes in range within the 3 s, but
  the key has already been pressed by then: Ctrl+right click again.
- Ctrl+Shift+F9 must not be bound to anything else on the warrior. With the option off, it falls back to F9's binding.

**Ctrl+mouse button 4** (the side button, "back") makes PC 2 press **F1** at once: the DuoBox **Follow** button
on the warrior. It follows the priest, or **stops following** if it already follows (press again to follow).
F1 must stay bound to the Follow button on the warrior (`/duo keys`), otherwise change `keys` of the `follow` trigger.
On the priest, Ctrl+button 4 also reaches WoW: if button 4 is bound there and Ctrl+button 4 is not, WoW runs
button 4's binding too. Mouse software (Logitech G Hub, Razer Synapse...) that turns the side button into a
keyboard key hides it from DuoRelay: keep it as a mouse button.

Folder `DuoBox\DuoRelay` (Windows PowerShell 5.1, nothing to install). Same folder and same `DuoRelay.json` on both PCs.

**Setup (once)**
1. PC 2: run `Setup-Firewall-PC2.bat`. It asks for PC 1's IP address (`ipconfig` on PC 1, "IPv4 Address" line).
   Enter it, or press Enter to accept any PC on the local network. Windows then asks for administrator rights
   to create the inbound rule `DuoRelay (UDP 47815)`.
2. If Windows shows a "Windows Security Alert" for PowerShell the first time a script starts, click **Allow**.
   "Cancel" creates a rule that blocks PowerShell, and the relay will not get through.

**Each session**
1. PC 2: run `Start-Relay-PC2.bat`. It shows PC 2's IP address. Then **click the warrior's WoW window**: keys are
   only pressed while WoW is the foreground window.
2. PC 1: run `Start-Relay-PC1.bat`. The first time, it asks for PC 2's address and saves it.
   A small label at the top of the screen shows the state. It ignores the mouse and never takes the focus.
3. **Ctrl+Alt+D** switches the relay ON / OFF. The relay is **OFF at start**.

| Label (PC 1) | Meaning |
|---|---|
| `Relais PC 2 : OFF (CTRL+ALT+D)` | Nothing is relayed |
| `Relais PC 2 : ON` | PC 2 answers and its WoW is the foreground window |
| `Relais PC 2 : ON - PC 2 injoignable` | No answer: PC 2 script not started, firewall, wrong address |
| `Relais PC 2 : ON - WoW pas actif sur PC 2` | Click the warrior's WoW window on PC 2 |
| `Relais -> PC 2 : OK` | PC 2 pressed the keys |
| `Relais PC 2 : ON (camera, deplacements)` | The priest's options ask for the warrior camera / moves (below) |

**What is relayed**
- Only a click in WoW on PC 1 with Ctrl and no other modifier. Left / right buttons (they turn the camera when
  dragged): a real click only, released within 0.5 s and the mouse moved 30 px at most (`maxClickMovePx`; a quick
  click on a moving mob easily moves 10–15 px with a sensitive mouse). WoW hides the cursor as
  soon as a button is held over the 3D world, even for a plain click, and keeps it in place while the camera
  turns: only the time tells a camera turn from a click. Middle and side buttons: relayed as soon as pressed.
- The PC 1 window lists every Ctrl+click that is not relayed while the relay is ON, with the reason
  (`mouse moved 9 px`, `held over 500 ms`, `WoW is not the foreground window`). Nothing listed
  at all: the script did not see the button (mouse software turning it into a key, see above).
- **Any** Ctrl+click in the WoW window counts, even on the interface (Ctrl+click on an item = dressing room)
  or on the ground. In that case the warrior assists the priest's current target. Switch the relay OFF when you don't need it.
- PC 2 waits `delayMs` (150 ms) before pressing the keys. The priest's new target has to reach the warrior's
  client through the game server first, otherwise `/assist` takes the previous target. If the warrior takes
  the old target, raise it to 400–500.
- One action per `minIntervalMs` (0.5 s): a double click presses the keys once.

**`DuoRelay.json`** (shared by both PCs; IP addresses go to `DuoRelay.local.json`, which is per PC and not in git)
- `triggers`: list of `{ name, label, modifier, button, keys, delayMs }`. `modifier`: `CTRL`, `ALT`, `SHIFT`, or a mix
  such as `CTRL-SHIFT` (required). `button`: `LEFT`, `RIGHT`, `MIDDLE`, `X1`, `X2`. `keys`: same format as
  VoiceKeys (`"SHIFT-T, T"`). `delayMs` (optional): this trigger's wait, instead of the global one.
  Default: `interact` (Ctrl+left, `SHIFT-T, T`), `pickup` (Ctrl+right, `CTRL-SHIFT-F9` after 500 ms) and
  `follow` (Ctrl+button 4 = `X1`, `F1` at once; button 5 is `X2`).
- `toggleKey` (`CTRL-ALT-D`), `startEnabled` (`false`), `port` (`47815`; run the firewall setup again if you change it).
- `delayMs`, `minIntervalMs`, `maxClickMovePx`, `maxClickMs`: timings above.
- `overlay` (label on/off), `overlayX` (`-1` = centered), `overlayY`; `sounds` (beep on ON/OFF, `false` by default).
- `processNames`: WoW executables that count as "WoW in the foreground".
- `moves`, `camera`, `maxHoldMs`, `maxCameraMs`, `streamTimeoutMs`: warrior moves and camera, see
  [Warrior camera and moves](#warrior-camera-and-moves-from-pc-1-keys-the-priest-never-gets).

PC 2 only accepts messages from PC 1 (`pc1Address`) or, without it, from a private network address. Messages
carry no password: anyone on your local network could make the warrior press the configured keys.

Test without network or key press: `powershell -ExecutionPolicy Bypass -File DuoRelay\DuoRelay.ps1 -SelfTest`.

### Warrior spell panel (click an icon on PC 1)
A row of the warrior's spell icons on the priest's screen. With the relay ON, a **left click** on an icon makes
PC 2 press that spell's **action-bar key** in the warrior's WoW: the warrior casts it. It is meant for the spells
the Rotation key handles badly: one macro run tries only one spell on the global cooldown, and Victory Rush and
Slam (WoW Forever) are only cast by an action-bar key, not by `/cast`.
- Priest only: **DuoRelay > Panneau des sorts du guerrier** (tab DuoRelay), or `/duo panneau` (off by default).
  PC 2 presses the warrior's own keys; the warrior's DuoBox only reports its casts for the cooldowns (below),
  nothing to switch on there.
- Above the icons, the warrior's **rage bar** with its value (mana for a hunter; `Guerrier` when no partner is in
  the group). Drag it to move the panel. The game may hide the partner's rage from addons in combat: the bar and
  its number are handed the game's values as they are (the game draws hidden values), so it still shows them.
  The icons are plain frames: a click on them does nothing in the priest's game, in or out of combat. The tooltip
  shows the spell and the icon's number; **DuoRelay > Infobulles des sorts** unchecked hides it
  (the click works the same).
- Default icons: **1** Victory Rush, **2** Slam, **3** Execute, **4** Thunder Clap, **5** Overpower,
  **6** Heroic Strike, **7** Cleave, **8** Hamstring, **9** Intimidating Shout, **10** Interagir (the warrior's
  interact key, T: not a spell, so no cooldown and no blink), **11** Challenging Shout. After a DuoBox update that
  adds icons, `/duo panneau defaut` on the priest takes the new list (the saved list is kept otherwise).
  `/duo panneau sorts Victory Rush, Slam, 5308, interact` replaces them (English names of the usual warrior spells,
  spell IDs, or `interact`; 12 at most), `/duo panneau sorts` lists them with their numbers, `/duo panneau defaut`
  restores them.
- **Show or hide icons**: at the bottom of the **DuoRelay** tab, "Icones du panneau des sorts du guerrier" has one box
  per icon of the list. Unticked, the icon leaves the panel and the others close the gap, but every icon keeps its
  number, so `DuoRelay.json` stays the same. `/duo panneau sorts` marks the hidden ones `(masque)`.
- **DuoRelay > Icones par rangee**: icons per row (1 to 12, 12 by default = one row);
  4 with 8 spells gives 2 rows of 4. Hidden icons take no place.
- **Blinking icons**: Overpower, Execute and Victory Rush (and Revenge if it is in the panel) blink as soon as the
  warrior's game lights them up, **yellow** when castable, **blue** when lit but short of rage. Same detection as
  the event light (section 3, "Event light"): its option must stay on on the warrior (on by default); the panel
  blinks even when the priest hides the event light.
- **Cooldowns on the icons (estimated)**: a swipe and a countdown as on the action bars (the numbers follow the
  game's own "show cooldown numbers" option). This client hides cooldowns from addons in combat (checked on the
  warrior 2026-11-07), and the priest's client sees the warrior's casts without their spell. So the warrior's
  DuoBox reports each of its own casts that starts a cooldown, while the panel is shown (the priest's DuoBox asks
  every 10 s), with its clock time; the priest's DuoBox converts it with the clock offset measured by these
  requests (the one with the shortest round trip), so the message's 0.1-0.3 s trip does not delay the swipe.
  Each icon shows its spell's own cooldown, or the global cooldown (1.5 s, after any warrior spell on it) when that
  one ends later. Heroic Strike and Cleave are off the global cooldown. The cooldown's length: read from the game
  when it shows it (out of combat), else the length read out of combat earlier in the session, the game's base
  value, the spell's tooltip, and last DuoBox's table (Overpower 5 s, Thunder Clap 4 s, Intimidating Shout 3 min,
  Challenging Shout 10 min).
  Not seen: resets and reductions in a fight (talents, procs), casts while the panel is hidden; addon messages
  may be blocked in some instances. Needs the same DuoBox version on both characters (`/reload` on both).
  `/duo panneau cd`: clock offset and round trip, last cast received and where its length came from.
- How DuoRelay knows the icon (a game addon cannot talk to another program): while the mouse is over icon N, DuoBox
  draws 4 small squares, 8 screen pixels each, in the top-left corner of the WoW window, colours that encode N.
  On a left press in WoW, DuoRelay reads those pixels and relays the trigger whose `"pixel"` is N. Each colour is
  followed by its complement, so the game's own picture does not pass for a code. A Ctrl+click on an icon counts as
  an icon click, not as a Ctrl+click interact.
- **WoW must run in Windowed or Windowed (Fullscreen) mode**: in exclusive fullscreen other programs cannot read
  the picture, and the clicks on the icons do nothing.
- The icon number is the `"pixel"` of a trigger in `DuoRelay.json`, which holds the key PC 2 presses: keep both
  lists in the same order. Default triggers, read from the warrior's key bindings and combat journal (Execute and
  Intimidating Shout: their bar slot told by the user; Challenging Shout: its key told by the user) on 2026-11-07:

| Icon | Spell | Key on PC 2 | Action bar slot |
|---|---|---|---|
| 1 | Victory Rush | `F4` | 78 (Battle Stance page of the main bar, button 6) |
| 2 | Slam | `F` | 63 (bottom left bar, button 3) |
| 3 | Execute | `5` | 77 (Battle Stance page of the main bar, button 5) |
| 4 | Thunder Clap | `C` | 79 (Battle Stance page of the main bar, button 7) |
| 5 | Overpower | `E` | 62 (bottom left bar, button 2) |
| 6 | Heroic Strike | `1` | 73 (Battle Stance page of the main bar, button 1) |
| 7 | Cleave | `Shift+C` | 80 (Battle Stance page of the main bar, button 8) |
| 8 | Hamstring | `4` | 76 (Battle Stance page of the main bar, button 4) |
| 9 | Intimidating Shout | `W` | 68 (Action Bar 2 = bottom left bar, button 8) |
| 10 | Interagir | `T` | none: the interact key (INTERACTTARGET), what it takes on the warrior (NPC, object, or its enemy target) |
| 11 | Challenging Shout | `Shift+3` | the button the user bound to Shift+3 (the warrior's saved bindings of 2026-11-06 had none on it) |

- Main bar keys (`F4`, `5`, `C`, `1`, `Shift+C`, `4`) press the Battle Stance page: in another stance they press
  that stance's button.
  If you move a spell on the warrior's bars, change its `keys`.
- A panel trigger: `{ "name": "slam", "label": "...", "pixel": 2, "keys": "F", "delayMs": 0 }`. No `button`
  and no `modifier`; `pixel` from 1 to 36; `delayMs` 0 = pressed at once. `pixelCell` (8, optional) is the
  square size in pixels and must match `CELL` in `RelayPanel.lua`.
- Same `DuoRelay.json` on both PCs (PC 1 reads the icon numbers, PC 2 the keys): after a change, copy it to the
  other PC and restart both scripts.
- `minIntervalMs` (0.5 s) still applies: an icon clicked less than 0.5 s after the previous relayed click is ignored.
- Label on PC 1: `Relais -> PC 2 : OK` as for the other clicks; `Relais : icone N sans touche (DuoRelay.json)`
  when no trigger has that number.
- To check the screen reading alone, without PC 2 and without pressing anything: on PC 1 run
  `powershell -ExecutionPolicy Bypass -File DuoRelay\DuoRelay.ps1 -PixelProbe`, click the WoW window and hover the
  icons. The window shows `icon 2 -> trigger slam, PC 2 would press F` and the colours read, or `no code`.
  `/duo panneau test [N]` draws icon N's code (2 by default) for 15 s without the mouse and says in the chat where
  it is (`coin a x=0 y=0 px, carres de 8 px`); keep the relay OFF meanwhile, a left click would relay it.
  `no code` with the game's colours during the test: the code is not where DuoRelay reads; send the chat line.

### Warrior camera and moves from PC 1 (keys the priest never gets)
With the relay ON, four keys held on PC 1 act **only in the warrior's game**: DuoRelay takes them before the
priest's game sees them.
- **Ctrl+Q** held: the warrior strafes left; **Ctrl+D**: strafes right; **Ctrl+S**: moves back. PC 2 holds the
  warrior's key while you hold yours and releases it when you let go.
- **Ctrl+Z** held + the mouse: the warrior's camera turns, as with a mouse plugged into PC 2. The priest's cursor
  stays where it is. Let go of Ctrl+Z (Z alone is enough) to stop.
- Priest only, tab **DuoRelay** of the options, off by default: **Camera du guerrier**, **Le guerrier tourne avec**
  (PC 2 holds the right button: the warrior turns with its camera; unticked: the left button, camera only) and
  **Deplacements du guerrier**.
- How the priest is kept out:
  - A keyboard hook on PC 1 takes the press at its first key down with exactly Ctrl (Ctrl+Shift+Q is not taken),
    then its repeats and its release. The priest's game never sees any part of it, neither as a key message nor
    as raw input (checked with the hook on 2026-11-08). A press that started without Ctrl (Q held, then Ctrl) stays
    the priest's. Ctrl itself reaches the priest: while you hold it, the priest's Ctrl macros target yourself.
  - Only while the relay is ON, WoW is the foreground window on PC 1 and the priest's DuoBox shows its **status
    code**: with one of these options ticked, DuoBox draws 4 small squares in the top-left corner (black, white and
    two colours) whenever no icon code is drawn, and DuoRelay reads them every 0.25 s. Options unticked, interface
    hidden (Alt+Z), exclusive fullscreen or relay OFF: these keys are the priest's again.
  - A mouse button pressed during Ctrl+Z ends the camera turn and goes to the priest: a hook cannot hide the mouse
    from a game that reads raw input (checked), so the camera never keeps the mouse while a button is down. For the
    same reason it does not start while a mouse button is held or while the priest's game turns its own camera
    (cursor hidden): the label says `Camera PC 2 : lacher les boutons de la souris avant`.
- Camera on PC 2: the mouse's raw movement arrives about 200 times a second. PC 2 puts its cursor over the game
  world (middle of the window, upper third), holds the button from the first movement on and moves its mouse by the
  same amounts. A turn that moved less than 12 px is topped up to 12 px before the button is released: a press and
  release without movement would be a click (interact, or a Click-to-Move walk).
- Safety: PC 1 confirms each held key every 100 ms and the camera at least every 100 ms. PC 2 releases what it no
  longer hears about after 0.4 s (`streamTimeoutMs`), and everything when its WoW leaves the foreground or when its
  script stops. A move held over 30 s (`maxHoldMs`) or a camera turn over 60 s (`maxCameraMs`) is released on PC 2:
  press again.
- On the warrior: Q = **Strafe Left** (bound), S = **Move Backward** (WoW's default key), and **Strafe Right** has no
  key: bind it to the **right arrow**, or change `hold` of `straferight` in `DuoRelay.json`. PC 2 holds bare keys,
  never Ctrl, so the pedal and the other relays keep working meanwhile.
- `DuoRelay.json`: `moves` = list of `{ name, label, key, hold }` (`key`: the chord taken on PC 1; `hold`: one key
  without modifier, held on PC 2; arrows are `LEFT`, `RIGHT`, `UP`, `DOWN`); `camera` = `{ key, label, speed }`
  (`speed` multiplies the movement, 1 by default). The same file on both PCs.
- Labels on PC 1: `Relais PC 2 : ON (camera, deplacements)` (what the priest's options ask for), `Deplacement -> PC 2`,
  `Camera -> PC 2`, or `... : WoW pas actif sur PC 2` / `... : PC 2 injoignable` while you hold the key.
- Checks: `DuoRelay.ps1 -PixelProbe` shows `status 4 -> warrior commands: camera only, moves` over WoW.
  `DuoRelay.ps1 -HookTest` checks the keyboard hook and the camera mode on the PC where it runs, with Ctrl+F13 /
  Ctrl+F14 and a few pixels of mouse (hands off for 3 s; nothing is sent).
