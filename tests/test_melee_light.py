"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, sent, tickers, frames = {meleeLight = true}, {}, {}, {}
clock, class, combat, moveMode, partner = 100, "WARRIOR", true, false, "party1"
target = {enemy = true, dead = false, inRange = true} -- nil = no target
SECRET = {}
ERR_BADATTACKFACING = "You are facing the wrong way!"
ERR_BADATTACKPOS = "You are too far away!"
ns = {}
function ns.GetDB() return db end
function ns.PartnerUnit() return partner end
function ns.SendComm(msg) table.insert(sent, msg) end
function ns.FromPartner(body, sender) if sender == "Partner" then return body end end
function ns.IsMoveMode() return moveMode end
function ns.SpellNameIcon(id) if id == 78 then return "Heroic Strike" end end
function ns.Known(id) return id == 78 end
function issecretvalue(v) return v == SECRET end
function GetTime() return clock end
function UnitClass() return class, class end
function UnitName(u) return u == "party1" and "Warrior" or nil end
function UnitAffectingCombat() return combat end
function UnitExists(u) return u == "target" and target ~= nil end
function UnitIsDead() return target and target.dead end
function UnitCanAttack() return target and target.enemy end
C_Spell = { IsSpellInRange = function(name, unit) assert(name == "Heroic Strike" and unit == "target"); return target.inRange end }
C_Timer = { NewTicker = function(t, fn) table.insert(tickers, {t = t, fn = fn}) end }

local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:RegisterEvent(name) self.events[name] = true end
function Methods:RegisterUnitEvent(name) self.events[name] = true end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetText(t) self.value = t end
function Methods:SetColorTexture(r, g, b) self.rgb = {r, g, b} end
function Methods:EnableMouse(v) self.mouse = v end
function Obj()
    local o = {scripts = {}, events = {}, shown = true}
    return setmetatable(o, {__index = function(_, k) return Methods[k] or function() end end})
end
function Methods:CreateTexture() return Obj() end
function Methods:CreateFontString() return Obj() end
function CreateFrame(_, name) local f = Obj(); table.insert(frames, f); if name then _G[name] = f end; return f end
UIParent = Obj()

light = nil
function ev() return frames[2] end
function event(name, ...) ev().scripts.OnEvent(ev(), name, ...) end
function tick(dt)
    clock = clock + (dt or 0.25)
    for _, t in ipairs(tickers) do t.fn() end
end
function last() return sent[#sent] end
'''


class MeleeLightTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)

    def load(self, setup=""):
        self.lua.execute(setup)
        self.lua.execute((ROOT / "MeleeLight.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("light = DuoBoxMeleeLight; event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    def test_warrior_sends_range_facing_and_target_states(self):
        self.load()
        self.run_lua('''
            tick(); assert(last() == "ML:G", last())
            target.inRange = false; tick(); assert(last() == "ML:R")
            target.inRange = true
            event("UI_ERROR_MESSAGE", 50, "You are facing the wrong way!"); tick(); assert(last() == "ML:F")
            event("UNIT_SPELLCAST_SUCCEEDED", "player"); tick(); assert(last() == "ML:G")
            event("UI_ERROR_MESSAGE", 50, "You are facing the wrong way!"); tick(); assert(last() == "ML:F")
            tick(4.1); assert(last() == "ML:G") -- the error is old news
            event("UI_ERROR_MESSAGE", 50, "You are too far away!"); tick(); assert(last() == "ML:R")
            tick(2); assert(last() == "ML:G")
            target = nil; tick(); assert(last() == "ML:T")
            combat = false; tick(); assert(last() == "ML:N")
        ''')

    def test_warrior_resends_every_second_and_a_half_and_only_with_a_partner(self):
        self.load()
        self.run_lua('''
            tick(); local n = #sent
            tick(0.5); assert(#sent == n)
            tick(1.1); assert(#sent == n + 1 and last() == "ML:G")
            partner = nil; tick(2); assert(#sent == n + 1)
        ''')

    def test_secret_values_in_an_instance_do_not_turn_the_light_red(self):
        self.load('target.enemy = SECRET; target.inRange = SECRET')
        self.run_lua('tick(); assert(last() == "ML:G", last())')

    def test_priest_shows_the_light_and_hides_it_when_stale_or_out_of_combat(self):
        self.load('class = "PRIEST"')
        self.run_lua('''
            assert(not light.shown)
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Partner")
            assert(light.shown and light.text.value == "TROP LOIN" and light.color.rgb[1] > 0.5)
            assert(light.name.value == "Warrior")
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:G", "PARTY", "Partner")
            assert(light.text.value == "OK" and light.color.rgb[2] > 0.5)
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Stranger") -- not the partner
            assert(light.text.value == "OK")
            tick(4.5); assert(not light.shown) -- no news
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:F", "PARTY", "Partner"); assert(light.shown)
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:N", "PARTY", "Partner"); assert(not light.shown)
            assert(#sent == 0) -- the priest sends nothing
        ''')

    def test_disabled_and_move_mode(self):
        self.load('class = "PRIEST"')
        self.run_lua('''
            db.meleeLight = false
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Partner")
            assert(not light.shown)
            db.meleeLight = true; moveMode = true; tick()
            assert(light.shown and light.mouse and light.text.value == "Glisse-moi")
            moveMode = false; tick()
            assert(not light.mouse)
        ''')


if __name__ == "__main__":
    unittest.main()
