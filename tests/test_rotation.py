"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, printed, alerts, tickers, frames = {}, {}, {}, {}, {}
clock, lockdown, cursor, cleared = 100, false, nil, false
SPELLS = {
    [6673] = {"Battle Shout", "icon-shout"}, [7384] = {"Overpower", "icon-op"}, [6343] = {"Thunder Clap", "icon-tc"},
    [78] = {"Heroic Strike", "icon-hs"}, [5308] = {"Execute", "icon-exe"}, [2687] = {"Bloodrage", "icon-br"},
}
known = {[6673] = true, [7384] = true, [6343] = true, [78] = true, [5308] = true, [2687] = true}
buffs = {["Battle Shout"] = 100} -- seconds left; "unreadable" = auras blocked
SECRET = {}

ns = {}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.Alert(key, text) table.insert(alerts, text) end
ns.SOUND_NOTICE = 1
ns.STOP_FOLLOW = "/follow player\n"
function ns.AssistUnit() return "party1" end
function ns.Known(id) return known[id] end
function ns.SpellNameIcon(id) local s = SPELLS[id]; if s then return s[1], s[2] end end
function ns.BuffRemaining(unit, names)
    if buffs == "unreadable" then return nil end
    for name in pairs(names) do return buffs[name] or 0 end
end

function issecretvalue(v) return v == SECRET end
function GetTime() return clock end
playerClass = "WARRIOR"
function UnitClass() return "x", playerClass end
function InCombatLockdown() return lockdown end
function GetBindingKey(cmd) if cmd == "CLICK DuoBoxBtnShout:LeftButton" then return "F2" end end
function GetCursorInfo() if cursor then return "spell", 1, "spell", cursor end end
function ClearCursor() cursor, cleared = nil, true end
C_Timer = { NewTicker = function(_, fn) table.insert(tickers, fn) end }
C_Spell = { GetSpellInfo = function(name)
    for id, s in pairs(SPELLS) do if s[1] == name and known[id] then return {spellID = id} end end
end }
SPELL_FAILED_CASTER_AURASTATE = "You can't do that yet"
ERR_OUT_OF_RAGE = "Not enough rage"
SPELL_FAILED_OUT_OF_RANGE = "Out of range"
SPELL_FAILED_ONLY_SHAPESHIFT = "Must be in %s"
tinsert, UISpecialFrames = table.insert, {}

-- Permissive frame: tracked methods below, any other method does nothing
local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:GetScript(name) return self.scripts[name] end
function Methods:SetAttribute(k, v) self.attrs[k] = v end
function Methods:GetAttribute(k) return self.attrs[k] end
function Methods:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Methods:Hide() self.shown = false end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.shown end
function Methods:SetText(t) self.value = t end
function Methods:GetText() return self.value or "" end
function Methods:SetChecked(v) self.checked = v end
function Methods:GetChecked() return self.checked end
function Methods:SetTexture(t) self.texture = t end
function Methods:SetEnabled(v) self.enabled = v end
function Methods:GetStringHeight() return 12 end
function Obj()
    local o = {scripts = {}, attrs = {}, shown = true}
    return setmetatable(o, {__index = function(_, k) return Methods[k] or function() end end})
end
function Methods:CreateFontString() return Obj() end
function Methods:CreateTexture() return Obj() end
function CreateFrame(_, name) local f = Obj(); table.insert(frames, f); if name then _G[name] = f end; return f end
UIParent = Obj()

errorsShown = {}
UIErrorsFrame = Obj()
UIErrorsFrame.scripts.OnEvent = function(self, event, kind, msg) table.insert(errorsShown, msg) end
function uierror(msg) UIErrorsFrame.scripts.OnEvent(UIErrorsFrame, "UI_ERROR_MESSAGE", 50, msg) end

button, multi = Obj(), Obj()
button.icon = Obj()
function event(name) frames[1].scripts.OnEvent(frames[1], name) end
function tick() for _, fn in ipairs(tickers) do fn() end end
function macro() return button.attrs.macrotext end -- key going down
function release() return button.attrs["*macrotext1"] end -- key release: the buffs
function aoe() return button.attrs["*macrotext-a1"] end -- first multi-target key-down macro
-- Blizzard's SecureHandlerWrapScript keeps the snippet; down() runs it as a key going down does and
-- returns the key-down macro that press uses, and the button name the snippet gave
function SecureHandlerWrapScript(frame, script, header, body) wrapped = {frame = frame, script = script, body = body} end
function down(mouse)
    local run = assert(loadstring("local self, button, down = ...\n" .. wrapped.body))
    local name = run(button, mouse or "LeftButton", true)
    return name and button.attrs["*macrotext-" .. name] or macro(), name
end
function lines(text) local t = {}; for l in (text or macro()):gmatch("[^\n]+") do t[#t + 1] = l end; return t end
-- What Blizzard's secure "attribute" action does when the Multi button is pressed
function pressMulti(back)
    local value = multi.attrs[back and "attribute-value2" or "attribute-value"]
    multi.attrs["attribute-frame"]:SetAttribute(multi.attrs["attribute-name"], value)
end
ATTACK = "/assist [noharm][dead] party1\n/stopmacro [noharm][dead]\n/follow player\n/startattack\n"
SINGLE = ATTACK .. "/cast Overpower\n/cast Heroic Strike"
TC_HS = ATTACK .. "/cast Thunder Clap\n/cast Heroic Strike"
NEXT = "\n|cff999999- appui suivant -|r\n" -- between the key-down macros the panel shows
'''


class RotationTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)

    def load(self, setup=""):
        self.lua.execute(setup)
        self.lua.execute((ROOT / "Rotation.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("ns.SetupRotation(button, multi)")

    def run_lua(self, code):
        self.lua.execute(code)

    def test_default_list_single_and_multi_target(self):
        self.load()
        self.run_lua('''
            assert(macro() == SINGLE, macro())
            -- one key-down macro per attack on the global cooldown, Heroic Strike (off it) in each
            assert(button.attrs["rot-count-s"] == 1 and button.attrs["rot-count-a"] == 2)
            assert(aoe() == TC_HS and button.attrs["*macrotext-a2"] == SINGLE, aoe())
            assert(multi.attrs["attribute-frame"] == button and multi.attrs["attribute-name"] == "rot-mode")
            assert(multi.attrs["attribute-value"] == "aoe" and multi.attrs["attribute-value2"] == "single")
            assert(wrapped.frame == button and wrapped.script == "OnClick")
            assert(select(2, down("RightButton")) == nil) -- right click (panel): not routed
            assert(button.icon.texture == "icon-op" and not button.glow.shown and not multi.glow.shown)
            assert(button.attrs.type2 == "rotationpanel" and type(button.rotationpanel) == "function")
            -- no buff to cast: the release does nothing (Blizzard's no-op ""), not the key-down macro
            assert(release() == "" and button.attrs["*typerelease1"] == "")
            assert(button.attrs.pressAndHoldAction == true and button.attrs["*downbutton1"] == "main")
        ''')

    def test_multi_button_switches_the_macro_until_the_end_of_the_fight(self):
        self.load()
        self.run_lua('''
            event("PLAYER_REGEN_DISABLED"); lockdown = true
            assert(down() == SINGLE)
            pressMulti(); tick()
            assert(button.glow.shown and multi.glow.shown)
            -- each press takes the next multi-target macro (the count goes on from the last press):
            -- Overpower, Thunder Clap, Overpower...
            assert(down() == SINGLE and down() == TC_HS and down() == SINGLE)
            tick() -- the ticker does not undo it during the fight
            assert(button.attrs["rot-mode"] == "aoe" and down() == TC_HS)
            pressMulti(true); tick()
            assert(down() == SINGLE and down() == SINGLE and not button.glow.shown)
            pressMulti(); lockdown = false; event("PLAYER_REGEN_ENABLED")
            assert(button.attrs["rot-mode"] == "single" and down() == SINGLE and not multi.glow.shown) -- fight over
        ''')

    def test_multi_pressed_out_of_combat_is_kept_for_the_next_fight(self):
        self.load('buffs["Battle Shout"] = 0')
        self.run_lua('''
            pressMulti(); tick(); tick()
            assert(button.attrs["rot-mode"] == "aoe" and macro() == TC_HS, macro()) -- not undone
            assert(release() == "/cast Battle Shout")
            assert(button.attrs["*typerelease1"] == "macro")
            assert(button.glow.shown and printed[#printed]:find("prochain combat"))
            event("PLAYER_REGEN_DISABLED")
            assert(down() == TC_HS and release() == "/castsequence reset=combat Battle Shout, null", release())
            lockdown = true; tick()
            assert(down() == SINGLE and down() == TC_HS)
            lockdown = false; event("PLAYER_REGEN_ENABLED")
            assert(macro() == SINGLE and release() == "/cast Battle Shout", macro())
            assert(not button.glow.shown and printed[#printed]:find("mono%-cible"))
        ''')

    def test_right_click_cancels_multi_out_of_combat(self):
        self.load()
        self.run_lua('''
            pressMulti(); tick()
            pressMulti(true); tick()
            assert(macro() == SINGLE and not multi.glow.shown)
        ''')

    def test_missing_buff_is_cast_first_and_once_per_fight_in_both_modes(self):
        self.load('buffs["Battle Shout"] = 0')
        self.run_lua('''
            assert(release() == "/cast Battle Shout" and macro() == SINGLE and button.icon.texture == "icon-shout")
            event("PLAYER_REGEN_DISABLED") -- just before the lockdown
            local cast = "/castsequence reset=combat Battle Shout, null"
            assert(release() == cast and macro() == SINGLE, release()) -- the same release in both modes
            lockdown = true
            buffs["Battle Shout"] = 120; tick()
            assert(release() == cast) -- frozen
            assert(button.icon.texture == "icon-op")
            lockdown = false; tick()
            assert(macro() == SINGLE and release() == "")
        ''')

    def test_long_list_buffs_on_the_release_attacks_on_the_key_down(self):
        # The warrior's list of 2026-11-06: 287 characters in one fight macro, the game ran only the first 255
        self.load('''
            SPELLS[1259813] = {"Eureka!"}; SPELLS[6546] = {"Rend"}; known[1259813] = true; known[6546] = true
            buffs["Battle Shout"] = 0
            db.rotation, db.rotationClass = {{id = 6673, once = true}, {id = 2687, once = true},
                {id = 1259813, once = true}, {id = 6343, when = "aoe"}, {id = 7384}, {id = 78},
                {id = 6546, once = true}}, "WARRIOR"
        ''')
        self.run_lua('''
            local AOE = TC_HS
            assert(macro() == SINGLE and release() == "/cast Battle Shout\\n/cast Bloodrage\\n/cast Eureka!\\n/cast Rend")
            event("PLAYER_REGEN_DISABLED")
            assert(macro() == SINGLE and aoe() == AOE and button.attrs["*macrotext-a2"] == SINGLE, aoe())
            assert(release() == "/castsequence reset=combat Battle Shout, null\\n"
                .. "/castsequence reset=combat Bloodrage, null\\n/castsequence reset=combat Eureka!, null\\n"
                .. "/castsequence reset=combat Rend, null", release())
            assert(#macro() <= 255 and #aoe() <= 255 and #release() <= 255)
            lockdown = true; pressMulti(); tick()
            assert(down() == AOE and button.glow.shown and release():find("Battle Shout"))
            lockdown = false; event("PLAYER_REGEN_ENABLED")
            ns.ToggleRotation()
            assert(DuoBoxRotation.status.value == "", DuoBoxRotation.status.value)
            assert(DuoBoxRotation.macro.value == SINGLE .. "\\n|cff999999Au relachement de la touche :|r\\n" .. release())
        ''')

    def test_buff_for_one_mode_stays_in_its_key_down_macro(self):
        # The Multi button swaps only the key-down macro
        self.load('buffs.Bloodrage = 0')
        self.run_lua('''
            ns.RotationAdd(2687); ns.RotationSet(5, "once", true); ns.RotationSet(5, "when", "aoe")
            event("PLAYER_REGEN_DISABLED")
            assert(release() == "" and macro() == SINGLE, release())
            assert(aoe() == "/castsequence reset=combat Bloodrage, null\\n" .. TC_HS, aoe())
            assert(button.attrs["*macrotext-a2"] == "/castsequence reset=combat Bloodrage, null\\n" .. SINGLE)
        ''')

    def test_panel_warns_when_a_fight_macro_is_too_long(self):
        self.load('''
            db.rotation, db.rotationClass = {{id = 78}}, "WARRIOR"
            for id = 1, 6 do
                SPELLS[id] = {"Long buff name number " .. id}; known[id] = true
                table.insert(db.rotation, {id = id, once = true})
            end
        ''')
        self.run_lua('''
            ns.ToggleRotation()
            assert(DuoBoxRotation.status.value:find("le jeu n'en lit que 255"), DuoBoxRotation.status.value)
            ns.RotationRemove(7); ns.RotationRemove(6) -- 4 buffs: the release fits
            assert(DuoBoxRotation.status.value == "", DuoBoxRotation.status.value)
        ''')

    def test_a_long_list_of_attacks_fits_one_macro_each(self):
        self.load('''
            db.rotation, db.rotationClass = {}, "WARRIOR"
            for id = 1, 7 do
                SPELLS[id] = {"Very long attack name number " .. id}; known[id] = true
                db.rotation[id] = {id = id}
            end
        ''')
        self.run_lua('''
            ns.ToggleRotation()
            assert(DuoBoxRotation.status.value == "", DuoBoxRotation.status.value)
            assert(button.attrs["rot-count-s"] == 7 and #macro() <= 255)
            assert(DuoBoxRotation.macroTitle.value:find("7 en alternance"), DuoBoxRotation.macroTitle.value)
        ''')

    def test_buff_ending_soon_counts_as_missing(self):
        self.load('buffs["Battle Shout"] = 20')
        self.run_lua('assert(release() == "/cast Battle Shout")')

    def test_alert_when_the_buff_ends_during_the_fight(self):
        self.load()
        self.run_lua('''
            lockdown = true
            buffs["Battle Shout"] = 0; tick()
            assert(#alerts == 0) -- never seen in this fight: the macro casts it
            buffs["Battle Shout"] = 50; tick()
            buffs["Battle Shout"] = 0; tick()
            assert(alerts[1] == "Battle Shout termine ! (F2)", alerts[1])
        ''')

    def test_unreadable_auras_keep_the_previous_decision(self):
        self.load('buffs["Battle Shout"] = 0')
        self.run_lua('''
            buffs = "unreadable"; tick()
            assert(release() == "/cast Battle Shout")
            lockdown = true; tick()
            assert(#alerts == 0)
        ''')

    def test_list_changes_wait_for_the_end_of_the_fight(self):
        self.load()
        self.run_lua('''
            lockdown = true
            ns.RotationRemove(3) -- Overpower
            assert(macro() == SINGLE)
            lockdown = false; tick()
            assert(macro() == ATTACK .. "/cast Heroic Strike", macro())
        ''')

    def test_editing_the_list(self):
        self.load()
        self.run_lua('''
            assert(ns.RotationAdd(ns.RotationFind("Execute")))
            ns.RotationMove(5, -1); ns.RotationMove(4, -1); ns.RotationMove(3, -1)
            -- Execute (2nd) and Overpower (4th) take turns, Execute first
            assert(macro() == ATTACK .. "/cast Execute\\n/cast Heroic Strike", macro())
            assert(button.attrs["*macrotext-s2"] == SINGLE and down() == macro() and down() == SINGLE)
            ns.RotationSet(4, "off", true)
            assert(macro() == ATTACK .. "/cast Execute\\n/cast Heroic Strike" and button.attrs["rot-count-s"] == 1)
            local ok, err = ns.RotationAdd(5308)
            assert(not ok and err == "Execute est deja dans la liste")
            ok, err = ns.RotationAdd(ns.RotationFind("Mortal Strike"))
            assert(not ok and err:find("introuvable"))
            assert(ns.RotationFind("2687") == 2687)
            assert(ns.RotationFind("|cff71d5ff|Hspell:2687:0|h[Bloodrage]|h|r") == 2687)
            ns.RotationReset()
            assert(macro() == SINGLE)
            assert(#db.rotation == 4 and db.rotation[1].once and db.rotation[2].when == "aoe")
        ''')

    def test_single_only_and_always_targets(self):
        self.load()
        self.run_lua('''
            ns.RotationSet(4, "when", "single") -- Heroic Strike
            assert(macro() == SINGLE and aoe() == ATTACK .. "/cast Thunder Clap", aoe())
            assert(button.attrs["*macrotext-a2"] == ATTACK .. "/cast Overpower")
            ns.RotationSet(2, "when", nil) -- Thunder Clap always
            assert(macro() == TC_HS and button.attrs["*macrotext-s2"] == ATTACK .. "/cast Overpower\\n/cast Heroic Strike")
            ns.RotationSet(4, "when", nil)
            assert(aoe() == macro())
            pressMulti(); tick()
            assert(not button.glow.shown) -- same macro: no multi-target mode to show
        ''')

    def test_buff_mode_on_another_spell_and_unlearned_spells(self):
        self.load('known[7384] = nil; buffs.Bloodrage = 0')
        self.run_lua('''
            assert(macro() == ATTACK .. "/cast Heroic Strike", macro()) -- Overpower not learned yet
            ns.RotationAdd(2687); ns.RotationSet(5, "once", true)
            assert(release() == "/cast Bloodrage", release())
            ns.RotationSet(5, "once", false)
            assert(lines()[#lines()] == "/cast Bloodrage")
        ''')

    def test_victory_rush_goes_through_its_action_bar_slot(self):
        # The client never calls Victory Rush usable: a macro /cast skips it, its action-bar slot casts it
        self.load('''
            SPELLS[402927] = {"Victory Rush", "icon-vr"}; known[402927] = true
            bar = {[77] = 402927, [3] = 78}
            function GetActionInfo(slot) if bar[slot] then return "spell", bar[slot] end end
        ''')
        self.run_lua('''
            assert(ns.RotationAdd(402927)); ns.RotationMove(5, -1); ns.RotationMove(4, -1); ns.RotationMove(3, -1)
            -- Whatever its place in the list, it ends the key release: its click always takes the one
            -- spell-on-cooldown turn of a macro, which would leave Overpower and Slam no turn on the key down.
            -- Heroic Strike (slot 3) keeps its /cast.
            assert(macro() == SINGLE and aoe() == TC_HS and button.attrs["rot-count-a"] == 2, macro())
            assert(release() == "/stopmacro [noharm][dead]\\n/click DuoBoxRotVictoryRush", release())
            assert(button.attrs["*typerelease1"] == "macro")
            local b = DuoBoxRotVictoryRush.attrs
            assert(b.type == "action" and b.action == 77 and b.useOnKeyDown == false)
            local tip = {}
            button.extra({AddLine = function(_, text) tip[#tip + 1] = text end})
            assert(tip[2] == "2. Victory Rush (au relachement de la touche, par la barre d'action, emplacement 77)", tip[2])
            buffs["Battle Shout"] = 0; tick() -- after the buffs
            assert(release() == "/cast Battle Shout\\n/stopmacro [noharm][dead]\\n/click DuoBoxRotVictoryRush", release())
            bar = {[5] = 402927}; tick() -- moved on the bars: the button follows
            assert(DuoBoxRotVictoryRush.attrs.action == 5)
            bar = {}; tick() -- on no bar: back to a /cast among the attacks, which the game skips
            assert(macro():find("/cast Victory Rush\\n") and release() == "/cast Battle Shout", macro())
        ''')

    def test_overpower_execute_and_slam_take_turns(self):
        # The user's choice (2026-11-07): one key, the three attacks on the global cooldown in turn
        self.load('''
            SPELLS[1240193] = {"Slam", "icon-slam"}; known[1240193] = true
            SPELLS[402927] = {"Victory Rush", "icon-vr"}; known[402927] = true
            bar = {[63] = 1240193, [77] = 402927}
            function GetActionInfo(slot) if bar[slot] then return "spell", bar[slot] end end
            db.rotation, db.rotationClass = {{id = 6343, when = "aoe"}, {id = 402927}, {id = 7384}, {id = 5308},
                {id = 1240193}, {id = 78}}, "WARRIOR"
        ''')
        self.run_lua('''
            local OP, EXE, SLAM = SINGLE, ATTACK .. "/cast Execute\\n/cast Heroic Strike",
                ATTACK .. "/click DuoBoxRotSlam\\n/cast Heroic Strike"
            event("PLAYER_REGEN_DISABLED"); lockdown = true
            assert(button.attrs["rot-count-s"] == 3, button.attrs["rot-count-s"])
            assert(down() == OP and down() == EXE and down() == SLAM and down() == OP)
            assert(release() == "/stopmacro [noharm][dead]\\n/click DuoBoxRotVictoryRush", release())
            assert(DuoBoxRotSlam.attrs.action == 63)
            local tip = {}
            button.extra({AddLine = function(_, text) tip[#tip + 1] = text end})
            assert(tip[3] == "3. Overpower (1 appui sur 3)" and tip[6] == "6. Heroic Strike", tip[3] .. " / " .. tip[6])
            assert(tip[5] == "5. Slam (1 appui sur 3, par la barre d'action, emplacement 63)", tip[5])
            pressMulti(); tick() -- multi target: Thunder Clap takes a turn too
            assert(button.attrs["rot-count-a"] == 4)
        ''')

    def test_min_health_keeps_a_spell_out_of_the_fight(self):
        # Rend skipped on a mob about to die: decided as the fight starts, the macro is frozen during it
        self.load('''
            SPELLS[6546] = {"Rend", "icon-rend"}; known[6546] = true
            target = {exists = true, hp = 600, max = 900}
            function UnitExists(u) return u == "target" and target.exists end
            function UnitCanAttack(_, u) return u == "target" end
            function UnitIsDead() return false end
            function UnitHealth() return target.hp end
            function UnitHealthMax() return target.max end
        ''')
        self.run_lua('''
            assert(ns.RotationAdd(6546)); ns.RotationSet(5, "once", true)
            assert(release() == "/cast Rend", release()) -- no threshold yet
            ns.RotationSet(5, "minHP", 850)
            assert(release() == "", release()) -- 600 < 850
            target.hp = 900; tick()
            assert(release() == "/cast Rend")
            event("PLAYER_REGEN_DISABLED"); lockdown = true
            assert(release() == "/castsequence reset=combat Rend, null")
            target.hp = 100; tick()
            assert(release() == "/castsequence reset=combat Rend, null") -- frozen for the fight
            lockdown = false; event("PLAYER_REGEN_ENABLED")
            assert(release() == "")
            target.max = 100; tick() -- percentages only: unreadable, cast
            assert(release() == "/cast Rend")
            target.max = SECRET; tick() -- secret in an instance: cast
            assert(release() == "/cast Rend")
            target.max, target.exists = 900, false; tick() -- no enemy target: cast
            assert(release() == "/cast Rend")
            local tip = {}
            button.extra({AddLine = function(_, text) tip[#tip + 1] = text end})
            assert(tip[5]:find("850 PV ou plus"), tip[5])
            -- The panel's box: typed value saved when it loses focus, empty = no threshold
            ns.ToggleRotation()
            local boxes = {}
            for _, f in ipairs(frames) do if f.scripts.OnEditFocusLost then boxes[#boxes + 1] = f end end
            assert(boxes[5].value == "850", boxes[5].value)
            boxes[5]:SetText("700"); boxes[5].scripts.OnEditFocusLost(boxes[5])
            assert(db.rotation[5].minHP == 700)
            boxes[5]:SetText(""); boxes[5].scripts.OnEditFocusLost(boxes[5])
            assert(db.rotation[5].minHP == nil and boxes[5].value == "")
        ''')

    def test_ten_spells_at_most(self):
        self.load()
        self.run_lua('''
            for id = 1, 6 do SPELLS[id] = {"Spell" .. id}; known[id] = true; assert(ns.RotationAdd(id)) end
            SPELLS[7] = {"Spell7"}
            local ok, err = ns.RotationAdd(7)
            assert(not ok and err == "10 sorts au maximum")
        ''')

    def test_expected_errors_are_hidden_only_right_after_a_press(self):
        self.load()
        self.run_lua('''
            button.scripts.PreClick(button)
            uierror("You can't do that yet"); uierror("Not enough rage"); uierror("Must be in Battle Stance")
            uierror("Out of range")
            assert(#errorsShown == 1 and errorsShown[1] == "Out of range")
            assert(ns.IsRotationError("Not enough rage") and not ns.IsRotationError(SECRET))
            clock = clock + 1
            uierror("Not enough rage")
            assert(#errorsShown == 2 and not ns.IsRotationError("Not enough rage"))
        ''')

    def test_panel_lists_the_steps_and_takes_a_dropped_spell(self):
        self.load()
        self.run_lua('''
            ns.ToggleRotation()
            local panel = DuoBoxRotation
            assert(panel and panel:IsShown())
            assert(panel.macro.value == macro() and panel.aoeMacro.value == aoe() .. NEXT .. SINGLE)
            assert(panel.aoeTitle.value:find("2 en alternance"), panel.aoeTitle.value)
            cursor = 5308
            panel.scripts.OnReceiveDrag(panel)
            assert(cleared and #db.rotation == 5 and db.rotation[5].id == 5308)
            -- Execute takes turns with Overpower
            assert(panel.macro.value == SINGLE .. NEXT .. ATTACK .. "/cast Execute\\n/cast Heroic Strike", panel.macro.value)
            panel.drop.scripts.OnClick(panel.drop) -- empty cursor: nothing
            assert(#db.rotation == 5)
            ns.ToggleRotation()
            assert(not panel:IsShown())
        ''')

    def test_panel_target_button_cycles(self):
        self.load()
        self.run_lua('''
            ns.ToggleRotation()
            -- rows are not named: the "Toujours" buttons, in row order, are Battle Shout, Overpower, Heroic Strike
            -- (Thunder Clap, 2nd row, is "Multi seulement")
            local found = {}
            for _, f in ipairs(frames) do
                if f.value == "Toujours" then found[#found + 1] = f end
            end
            local click = found[2] -- Overpower
            click.scripts.OnClick(click) -- always -> multi only
            assert(db.rotation[3].when == "aoe" and macro() == ATTACK .. "/cast Heroic Strike")
            click.scripts.OnClick(click)
            assert(db.rotation[3].when == "single")
            click.scripts.OnClick(click)
            assert(db.rotation[3].when == nil)
        ''')

    def test_panel_needs_the_button(self):
        self.lua.execute((ROOT / "Rotation.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.run_lua('''
            ns.ToggleRotation()
            assert(printed[1]:find("pas encore cree") and DuoBoxRotation == nil)
        ''')

    def test_other_classes_start_empty_without_auto_attack(self):
        self.load('playerClass = "PRIEST"; SPELLS[585] = {"Smite", "icon-smite"}; known[585] = true')
        self.run_lua('''
            assert(#db.rotation == 0 and db.rotationClass == "PRIEST")
            assert(macro() == "/assist [noharm][dead] party1\\n/stopmacro [noharm][dead]\\n/follow player", macro())
            assert(ns.RotationAdd(585) and lines()[#lines()] == "/cast Smite")
            ns.RotationReset()
            assert(#db.rotation == 0)
        ''')

    def test_pet_classes_send_the_pet(self):
        self.load('playerClass = "HUNTER"')
        self.run_lua('assert(lines()[3] == "/follow player" and lines()[4] == "/petattack", macro())')

    def test_untagged_list_is_kept_by_the_warrior_and_replaced_on_other_classes(self):
        self.load('db.rotation = {{id = 78}}')
        self.run_lua('assert(db.rotationClass == "WARRIOR" and #db.rotation == 1 and db.rotation[1].id == 78)')
        self.setUp()
        # a warrior profile loaded on a priest before the lists were per class
        self.load('playerClass = "PRIEST"; db.rotation = {{id = 78}}')
        self.run_lua('assert(db.rotationClass == "PRIEST" and #db.rotation == 0)')

    def test_buttons_are_created_once(self):
        self.lua.execute((ROOT / "Rotation.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.run_lua('''
            playerClass = "MAGE"
            made = {}
            function ns.MakeButton(key, label, icon) local b = Obj(); b.icon = Obj(); made[#made + 1] = key; return b end
            ns.BuildRotationButtons()
            ns.BuildRotationButtons()
            assert(#made == 2 and made[1] == "Rotation" and made[2] == "Multi")
            assert(not ns.RotationMacro(false, false)[1]:find("startattack"))
        ''')


if __name__ == "__main__":
    unittest.main()
