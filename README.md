# DuoBox

![DuoBox voice to action: say “heal”, VoiceKeys recognizes the phrase offline and sends F7 to the active Priest client to heal your partner. Two monitors show the Hunter and Priest clients side by side; the command examples are not exhaustive.](docs/assets/voice-to-action.png)

World of Warcraft Classic addon for duo-boxing a healer (priest) and a DPS (hunter or warrior) on two clients,
without any key broadcasting: **1 key press = 1 action in 1 client**.

**Voice to action:** say **“heal”** → offline **VoiceKeys** recognition → **F7** → heal your partner.
Bind F7 to Heal with `/duo keys`, then speak while the priest's WoW client is focused.
VoiceKeys is optional: **1 phrase = 1 key**, sent to the active client on the same PC.
The diagram shows a few examples; see the [VoiceKeys setup and full command list](GUIDE.md#6-voicekeys-voice-commands-optional) for more.

- Cross-client alerts (low health, aggro, OOM, follow lost, quest item not looted) with sound and taskbar flash
- Priest cast bar and facing hints on the hunter's screen
- Auto-accept invites, quests and resurrections from the partner; quest sharing and comparison
- RestedXP: each objective also shows the partner's progress, and the guide waits until both are done
- Options panel (`/duo` or the minimap button): every setting and action without typing commands
- Configuration profiles (`/duo profile`): save the settings under a name and load them on any character of the account
- Experimental partner minimap gathering detections: confirms native tooltips at known GatherLite locations, then shares recent mineral/herb sightings (`/duo tracking on` on both characters)
- Button bar with key bindings (`/duo keys`) and class macros (`/duo macros`)
- Warrior **Rotation** button: one key casts the first usable spell of a list you edit in game (`/duo rotation`)
- Optional **VoiceKeys**: offline voice commands (Vosk or Windows speech), one phrase = one key
- Optional hunter combat-exit notifications (feature flag disabled by default)

## Install
Copy the `DuoBox` folder into `World of Warcraft\_classic_\Interface\AddOns\` on both clients, then in game:
```
/duo partner <OtherCharacterName>
```
Type `/duo` (or click the minimap button) to open the options panel, `/duo help` for all commands. Full documentation: [GUIDE.md](GUIDE.md).
