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
function macro() return button.attrs.macrotext end
function aoe() return multi.attrs["attribute-value"] end
function lines(text) local t = {}; for l in (text or macro()):gmatch("[^\n]+") do t[#t + 1] = l end; return t end
-- What Blizzard's secure "attribute" action does when the Multi button is pressed
function pressMulti(back)
    local value = multi.attrs[back and "attribute-value2" or "attribute-value"]
    multi.attrs["attribute-frame"]:SetAttribute(multi.attrs["attribute-name"], value)
end
ATTACK = "/assist [noharm][dead] party1\n/stopmacro [noharm][dead]\n/follow player\n/startattack\n"
SINGLE = ATTACK .. "/cast Overpower\n/cast Heroic Strike"
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
            assert(aoe() == ATTACK .. "/cast Overpower\\n/cast Thunder Clap\\n/cast Heroic Strike", aoe())
            assert(multi.attrs["attribute-value2"] == SINGLE)
            assert(multi.attrs["attribute-frame"] == button and multi.attrs["attribute-name"] == "macrotext")
            assert(button.icon.texture == "icon-op" and not button.glow.shown and not multi.glow.shown)
            assert(button.attrs.type2 == "rotationpanel" and type(button.rotationpanel) == "function")
        ''')

    def test_multi_button_switches_the_macro_until_the_end_of_the_fight(self):
        self.load()
        self.run_lua('''
            event("PLAYER_REGEN_DISABLED"); lockdown = true
            pressMulti(); tick()
            assert(macro() == aoe() and button.glow.shown and multi.glow.shown)
            tick() -- the ticker does not undo it during the fight
            assert(macro() == aoe())
            pressMulti(true); tick()
            assert(macro() == SINGLE and not button.glow.shown)
            pressMulti(); lockdown = false; event("PLAYER_REGEN_ENABLED")
            assert(macro() == SINGLE and not multi.glow.shown) -- fight over: back to single target
        ''')

    def test_multi_pressed_out_of_combat_is_kept_for_the_next_fight(self):
        self.load('buffs["Battle Shout"] = 0')
        self.run_lua('''
            pressMulti(); tick(); tick()
            assert(macro() == aoe() and lines()[1] == "/cast Battle Shout", macro()) -- not undone
            assert(button.glow.shown and printed[#printed]:find("prochain combat"))
            event("PLAYER_REGEN_DISABLED")
            assert(macro() == aoe() and lines()[1] == "/castsequence reset=combat Battle Shout, null", macro())
            lockdown = true; tick()
            assert(macro():find("/cast Thunder Clap"))
            lockdown = false; event("PLAYER_REGEN_ENABLED")
            assert(macro() == ATTACK:gsub("^", "/cast Battle Shout\\n") .. "/cast Overpower\\n/cast Heroic Strike", macro())
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
            assert(lines()[1] == "/cast Battle Shout" and button.icon.texture == "icon-shout")
            event("PLAYER_REGEN_DISABLED") -- just before the lockdown
            local cast = "/castsequence reset=combat Battle Shout, null"
            assert(lines()[1] == cast and lines(aoe())[1] == cast, macro())
            lockdown = true
            buffs["Battle Shout"] = 120; tick()
            assert(lines()[1] == cast) -- frozen
            assert(button.icon.texture == "icon-op")
            lockdown = false; tick()
            assert(macro() == SINGLE)
        ''')

    def test_buff_ending_soon_counts_as_missing(self):
        self.load('buffs["Battle Shout"] = 20')
        self.run_lua('assert(lines()[1] == "/cast Battle Shout")')

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
            assert(lines()[1] == "/cast Battle Shout")
            lockdown = true; tick()
            assert(#alerts == 0)
        ''')

    def test_list_changes_wait_for_the_end_of_the_fight(self):
        self.load()
        self.run_lua('''
            lockdown = true
            ns.RotationRemove(2) -- Overpower
            assert(macro() == SINGLE)
            lockdown = false; tick()
            assert(macro() == ATTACK .. "/cast Heroic Strike", macro())
        ''')

    def test_editing_the_list(self):
        self.load()
        self.run_lua('''
            assert(ns.RotationAdd(ns.RotationFind("Execute")))
            ns.RotationMove(5, -1); ns.RotationMove(4, -1); ns.RotationMove(3, -1)
            assert(macro() == ATTACK .. "/cast Execute\\n/cast Overpower\\n/cast Heroic Strike", macro())
            ns.RotationSet(3, "off", true)
            assert(macro() == ATTACK .. "/cast Execute\\n/cast Heroic Strike")
            local ok, err = ns.RotationAdd(5308)
            assert(not ok and err == "Execute est deja dans la liste")
            ok, err = ns.RotationAdd(ns.RotationFind("Mortal Strike"))
            assert(not ok and err:find("introuvable"))
            assert(ns.RotationFind("2687") == 2687)
            assert(ns.RotationFind("|cff71d5ff|Hspell:2687:0|h[Bloodrage]|h|r") == 2687)
            ns.RotationReset()
            assert(macro() == SINGLE)
            assert(#db.rotation == 4 and db.rotation[1].once and db.rotation[3].when == "aoe")
        ''')

    def test_single_only_and_always_targets(self):
        self.load()
        self.run_lua('''
            ns.RotationSet(4, "when", "single") -- Heroic Strike
            assert(macro() == SINGLE and aoe() == ATTACK .. "/cast Overpower\\n/cast Thunder Clap", aoe())
            ns.RotationSet(3, "when", nil) -- Thunder Clap always
            assert(macro() == ATTACK .. "/cast Overpower\\n/cast Thunder Clap\\n/cast Heroic Strike", macro())
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
            assert(lines()[1] == "/cast Bloodrage", macro())
            ns.RotationSet(5, "once", false)
            assert(lines()[#lines()] == "/cast Bloodrage")
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
            assert(panel.macro.value == macro() and panel.aoeMacro.value == aoe())
            cursor = 5308
            panel.scripts.OnReceiveDrag(panel)
            assert(cleared and #db.rotation == 5 and db.rotation[5].id == 5308)
            assert(panel.macro.value == macro() and macro():find("/cast Execute$"))
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
            local found = {}
            for _, f in ipairs(frames) do
                if f.value == "Toujours" then found[#found + 1] = f end
            end
            local click = found[2] -- Overpower
            click.scripts.OnClick(click) -- always -> multi only
            assert(db.rotation[2].when == "aoe" and macro() == ATTACK .. "/cast Heroic Strike")
            click.scripts.OnClick(click)
            assert(db.rotation[2].when == "single")
            click.scripts.OnClick(click)
            assert(db.rotation[2].when == nil)
        ''')

    def test_panel_is_warrior_only(self):
        self.lua.execute((ROOT / "Rotation.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.run_lua('''
            ns.ToggleRotation()
            assert(printed[1]:find("guerrier") and DuoBoxRotation == nil)
        ''')


if __name__ == "__main__":
    unittest.main()
