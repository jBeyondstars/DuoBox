"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, sent, printed, tickers, frames = {meleeLight = true}, {}, {}, {}, {}
clock, class, combat, moveMode, partner, attacking = 100, "WARRIOR", true, false, "party1", true
-- range answers of each source: by rank spell ID, by spellbook slot, by name (nil = cannot tell)
target = {enemy = true, dead = false, byID = true, bySlot = true, byName = true} -- nil = no target
SECRET = {}
ERR_BADATTACKFACING = "You are facing the wrong way!"
ERR_BADATTACKPOS = "You are too far away!"
SPELL_FAILED_OUT_OF_RANGE = "Out of range."
HARMFUL = {[284] = true, [772] = true} -- Heroic Strike rank 2, Rend
ns = {}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.PartnerUnit() return partner end
function ns.SendComm(msg) table.insert(sent, msg) end
function ns.FromPartner(body, sender) if sender == "Partner" then return body end end
function ns.IsMoveMode() return moveMode end
function ns.SpellNameIcon(id) if id == 78 or id == 284 then return "Heroic Strike" end end
function ns.Known(id) return id == 78 end
function issecretvalue(v) return v == SECRET end
function GetTime() return clock end
function UnitClass() return class, class end
function UnitName(u) return u == "party1" and "Warrior" or nil end
function UnitAffectingCombat() return combat end
function UnitExists(u) return u == "target" and target ~= nil end
function UnitIsDead() return target and target.dead end
function UnitCanAttack() return target and target.enemy end
C_Spell = {
    IsSpellInRange = function(spell, unit)
        assert(unit == "target")
        if spell == 284 then return target.byID end
        assert(spell == "Heroic Strike"); return target.byName
    end,
    IsCurrentSpell = function(id) assert(id == 6603); return attacking end,
    IsSpellHarmful = function(id) return HARMFUL[id] or false end,
}
C_SpellBook = {
    FindSpellBookSlotForSpell = function(name) assert(name == "Heroic Strike"); return 7, 0 end,
    GetSpellBookItemType = function(slot, bank) assert(slot == 7 and bank == 0); return 1, 78, 284 end,
    IsSpellBookItemInRange = function(slot, bank, unit) assert(slot == 7 and unit == "target"); return target.bySlot end,
}
C_Timer = { NewTicker = function(t, fn) table.insert(tickers, {t = t, fn = fn}) end }

local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:RegisterEvent(name) self.events[name] = true end
function Methods:RegisterUnitEvent(name) self.events[name] = true end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetShown(v) self.shown = v and true or false end
function Methods:SetText(t) self.value = t end
function Methods:SetColorTexture(r, g, b) self.rgb = {r, g, b} end
function Methods:EnableMouse(v) self.mouse = v end
function Methods:SetSize(w, h) self.w, self.h = w, h; if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end end
function Methods:GetWidth() return self.w or 0 end
function Methods:GetHeight() return self.h or 0 end
function Methods:SetUserPlaced(v) self.placed = v end
function Obj()
    local o = {scripts = {}, events = {}, shown = true}
    return setmetatable(o, {__index = function(_, k) return Methods[k] or function() end end})
end
function Methods:CreateTexture() return Obj() end
function Methods:CreateFontString() return Obj() end
function CreateFrame(_, name) local f = Obj(); table.insert(frames, f); if name then _G[name] = f end; return f end
UIParent = Obj()

light, grip = nil, nil
function ev() return frames[3] end -- light, grip, events
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
        self.lua.execute("light, grip = DuoBoxMeleeLight, frames[2]; event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    def test_range_uses_the_learned_rank_then_the_spellbook_then_the_name(self):
        self.load()
        self.run_lua('''
            tick(); assert(last() == "ML:G", last())
            target.byID = false; tick(); assert(last() == "ML:R")
            target.byID = nil; tick(); assert(last() == "ML:G") -- spellbook slot says in range
            target.bySlot = SECRET; target.byName = false; tick(); assert(last() == "ML:R")
            target.byName = nil; tick(); assert(last() == "ML:G") -- nobody can tell: no false red
        ''')

    def test_facing_errors_and_what_clears_them(self):
        self.load()
        self.run_lua('''
            event("UI_ERROR_MESSAGE", 50, "You are facing the wrong way!"); tick(); assert(last() == "ML:F")
            event("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 6673); tick() -- Battle Shout: no facing needed
            assert(last() == "ML:F")
            event("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 284); tick(); assert(last() == "ML:G") -- Heroic Strike landed
            event("UI_ERROR_MESSAGE", 50, "You are facing the wrong way!"); tick(); assert(last() == "ML:F")
            event("PLAYER_TARGET_CHANGED"); tick(); assert(last() == "ML:G")
            event("UI_ERROR_MESSAGE", 50, "You are facing the wrong way!"); tick(4.1); assert(last() == "ML:G")
        ''')

    def test_out_of_range_errors_not_attacking_and_no_target(self):
        self.load()
        self.run_lua('''
            event("UI_ERROR_MESSAGE", 50, "Out of range."); tick(); assert(last() == "ML:R")
            tick(2); assert(last() == "ML:G")
            event("UI_ERROR_MESSAGE", 50, "You are too far away!"); tick(); assert(last() == "ML:R")
            tick(2)
            attacking = false; tick(); assert(last() == "ML:A")
            attacking = SECRET; tick(); assert(last() == "ML:G")
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
        self.load('target.enemy = SECRET; target.byID = SECRET; target.bySlot = SECRET; target.byName = SECRET')
        self.run_lua('tick(); assert(last() == "ML:G", last())')

    def test_priest_shows_the_light_and_hides_it_when_stale_or_out_of_combat(self):
        self.load('class = "PRIEST"')
        self.run_lua('''
            assert(not light.shown)
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Partner")
            assert(light.shown and light.text.value == "TROP LOIN" and light.color.rgb[1] > 0.5)
            assert(light.name.value == "Warrior")
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:A", "PARTY", "Partner")
            assert(light.text.value == "N'ATTAQUE PAS")
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:G", "PARTY", "Partner")
            assert(light.text.value == "OK" and light.color.rgb[2] > 0.5)
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Stranger") -- not the partner
            assert(light.text.value == "OK")
            tick(4.5); assert(not light.shown) -- no news
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:F", "PARTY", "Partner"); assert(light.shown)
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:N", "PARTY", "Partner"); assert(not light.shown)
            assert(#sent == 0) -- the priest sends nothing
        ''')

    def test_move_mode_resize_and_reset(self):
        self.load('class = "PRIEST"; db.meleeLightSize = 140')
        self.run_lua('''
            assert(light.w == 140) -- saved size applied at login
            db.meleeLight = false
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Partner")
            assert(not light.shown)
            db.meleeLight = true; moveMode = true; tick()
            assert(light.shown and light.mouse and grip.shown and light.text.value == "Glisse-moi")
            light.w, light.h = 180, 160 -- dragged by the grip
            grip.scripts.OnMouseUp(grip)
            assert(light.w == 180 and light.h == 180 and db.meleeLightSize == 180) -- kept square
            moveMode = false; tick()
            assert(not light.mouse and not grip.shown)
            ns.MeleeLightCommand("reset")
            assert(light.w == 90 and db.meleeLightSize == nil)
        ''')

    def test_debug_prints_what_the_client_answers(self):
        self.load('target.bySlot = SECRET')
        self.run_lua('''
            ns.MeleeLightCommand("debug")
            assert(#printed == 3, #printed)
            assert(printed[2]:find("rang 284") and printed[2]:find("grimoire=SECRET") and printed[2]:find("par ID=true"))
        ''')


if __name__ == "__main__":
    unittest.main()
