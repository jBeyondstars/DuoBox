"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, sent, printed, tickers, frames, prefixes, sets = {procLight = true, procOff = ""}, {}, {}, {}, {}, {}, {}
clock, class, combat, moveMode, partner, sendResult = 100, "WARRIOR", true, false, "party1", 0
SECRET = {}
-- learned spells: name -> rank ID; spell state by name: usable, short of power, glow (by spell ID), cooldown
NAMES = {[7384] = "Overpower", [6572] = "Revenge", [5308] = "Execute", [14251] = "Riposte"}
ICONS = {[7384] = "op.blp", [6572] = "rev.blp", [5308] = "exe.blp"}
learned = {Overpower = 7887, Execute = 20662} -- higher ranks: they replaced rank 1 in the spellbook
usable, noPower, glow, cooldown = {}, {}, {}, {}
ns = {}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.Set(key, value) db[key] = value; table.insert(sets, key); if ns.RefreshProcLight then ns.RefreshProcLight() end end
function ns.PartnerUnit() return partner end
function ns.SendComm(msg, prefix) table.insert(sent, {msg = msg, prefix = prefix}); return sendResult end
function ns.FromPartner(body, sender) if sender == "Partner" then return body end end
function ns.IsMoveMode() return moveMode end
function ns.SpellNameIcon(id) return NAMES[id], ICONS[id] end
function ns.Known(id) return learned[NAMES[id]] ~= nil end
function issecretvalue(v) return v == SECRET end
function GetTime() return clock end
function UnitClass() return class, class end
function UnitName(u) return u == "party1" and "Warrior" or nil end
function UnitPowerType() return 1 end
function UnitAffectingCombat() return combat end
C_Spell = {
    IsSpellUsable = function(name) return usable[name] or false, noPower[name] or false end,
    GetSpellCooldown = function(name)
        local c = cooldown[name]
        if c then return {startTime = c[1], duration = c[2], isEnabled = true, isActive = true, modRate = 1} end
        return {startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1}
    end,
}
C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return glow[id] or false end }
C_SpellBook = {
    FindSpellBookSlotForSpell = function(name) if learned[name] then return 10, 0 end end,
    GetSpellBookItemType = function(slot, bank) return 1, nil, lastRank end,
}
-- the slot lookup above returns the rank of the last name asked
local find = C_SpellBook.FindSpellBookSlotForSpell
C_SpellBook.FindSpellBookSlotForSpell = function(name) lastRank = learned[name]; return find(name) end
C_ChatInfo = { RegisterAddonMessagePrefix = function(p) table.insert(prefixes, p) end }
C_Timer = { NewTicker = function(t, fn) table.insert(tickers, {t = t, fn = fn}) end }

local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:RegisterEvent(name) self.events[name] = true end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetShown(v) self.shown = v and true or false end
function Methods:SetText(t) self.value = t end
function Methods:SetTexture(t) self.texture = t end
function Methods:SetDesaturated(v) self.grey = v end
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

function ev() return frames[3] end -- light, grip, events
function event(name, ...) ev().scripts.OnEvent(ev(), name, ...) end
-- every ticker runs at each step (the 0.1 s check, the 0.25 s display)
function tick(dt)
    clock = clock + (dt or 0.1)
    for _, t in ipairs(tickers) do t.fn() end
end
function last() return sent[#sent] and sent[#sent].msg end
function msg(list, sender) event("CHAT_MSG_ADDON", "DUOBOXP", "PR:" .. list, "PARTY", sender or "Partner") end
'''


class ProcLightTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)

    def load(self, setup=""):
        self.lua.execute(setup)
        self.lua.execute((ROOT / "ProcLight.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("light, grip = DuoBoxProcLight, frames[2]; event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    def test_warrior_sends_lit_spells_at_once_on_its_own_prefix(self):
        self.load()
        self.run_lua('''
            assert(prefixes[1] == "DUOBOXP")
            tick(); assert(#sent == 0) -- nothing lit: nothing to send
            usable.Overpower = true; event("SPELL_UPDATE_USABLE") -- a dodge: sent on the event, before the tick
            assert(last() == "PR:7384u" and sent[1].prefix == "DUOBOXP", last())
            usable.Execute = true; tick(); assert(last() == "PR:7384u,5308u") -- PROCS order
            usable.Overpower = false; tick(); assert(last() == "PR:5308u")
            usable.Execute = false; tick(); assert(last() == "PR:") -- out: the light hides at once
            local n = #sent; tick(3); assert(#sent == n) -- no heartbeat while nothing is lit
        ''')

    def test_revenge_not_learned_and_overpower_checked_by_its_learned_rank(self):
        self.load('glow[7887] = true') # the game glows the learned rank of Overpower
        self.run_lua('''
            usable.Revenge = true; tick(); assert(last() == "PR:7384u", last()) -- Revenge not learned: ignored
        ''')

    def test_short_of_rage_cooldown_and_global_cooldown(self):
        self.load()
        self.run_lua('''
            noPower.Overpower = true; tick(); assert(last() == "PR:7384p") -- lit, not enough rage
            local n = #sent
            noPower.Overpower = false; usable.Overpower = true; tick(); assert(#sent == n) -- same spells: waits 0.5 s
            tick(0.4); assert(last() == "PR:7384u")
            cooldown.Overpower = {clock - 1, 5}; tick(); assert(last() == "PR:") -- on its own 5 s cooldown
            cooldown.Overpower = {clock, 1.5}; tick(); assert(last() == "PR:7384u") -- the global cooldown does not count
            cooldown.Overpower = {SECRET, SECRET}; tick(2); assert(last() == "PR:7384u") -- unreadable: no cooldown
        ''')

    def test_heartbeat_retry_after_throttle_and_only_in_combat_with_a_partner(self):
        self.load()
        self.run_lua('''
            usable.Execute = true; tick(); local n = #sent
            tick(1); assert(#sent == n)
            tick(1); assert(#sent == n + 1 and last() == "PR:5308u") -- every 2 s while lit
            usable.Overpower = true; sendResult = 3; tick() -- AddonMessageThrottle
            assert(#sent == n + 2); tick(); assert(#sent == n + 3) -- retried on the next tick
            sendResult = 0; tick(); assert(last() == "PR:7384u,5308u"); n = #sent
            tick(); assert(#sent == n)
            combat = false; tick(); assert(last() == "PR:") -- end of the fight
            combat = true; partner = nil; tick(3); assert(last() == "PR:")
        ''')

    def test_switching_it_off_on_the_warrior_puts_the_light_out(self):
        self.load()
        self.run_lua('''
            usable.Overpower = true; tick(); assert(last() == "PR:7384u")
            ns.Set("procLight", false); assert(last() == "PR:")
            local n = #sent; tick(3); assert(#sent == n)
        ''')

    def test_spell_learned_later_is_picked_up_after_spells_changed(self):
        self.load('learned = {}')
        self.run_lua('''
            usable.Overpower = true; tick(); assert(#sent == 0)
            learned.Overpower = 7384; tick(); assert(last() == "PR:7384u") -- the empty list was not kept
            learned.Revenge = 6572; usable.Revenge = true; tick(); assert(last() == "PR:7384u") -- list kept now
            event("SPELLS_CHANGED"); tick(); assert(last() == "PR:7384u,6572u")
        ''')

    def test_priest_shows_the_first_lit_spell_and_hides_when_it_goes_out(self):
        self.load('class = "PRIEST"')
        self.run_lua('''
            assert(not light.shown)
            msg("7384u,5308u")
            assert(light.shown and light.icon.texture == "op.blp" and not light.icon.grey)
            assert(light.spell.value == "Overpower" and light.more.value == "+ Execute" and light.name.value == "Warrior")
            msg("5308p")
            assert(light.icon.texture == "exe.blp" and light.icon.grey and light.spell.value:find("pas assez de rage"))
            assert(light.more.value == "")
            msg("7384u", "Stranger"); assert(light.icon.texture == "exe.blp") -- not the partner
            msg(""); assert(not light.shown) -- out: hidden at once
            msg("7384u"); assert(light.shown)
            tick(2); assert(light.shown); tick(1.1); assert(not light.shown) -- no news for 3 s
            assert(#sent == 0) -- the priest sends nothing
        ''')

    def test_spells_hidden_in_the_options_and_light_switched_off(self):
        self.load('class = "PRIEST"')
        self.run_lua('''
            ns.SetProcHidden(7384, true); assert(db.procOff == "7384")
            msg("7384u"); assert(not light.shown)
            msg("7384u,5308u"); assert(light.shown and light.spell.value == "Execute" and light.more.value == "")
            ns.SetProcHidden(5308, true); assert(db.procOff == "5308,7384" and not light.shown)
            assert(ns.ProcHidden(5308) and ns.ProcHidden(7384) and not ns.ProcHidden(538))
            ns.SetProcHidden(7384, false); assert(db.procOff == "5308" and light.shown and light.spell.value == "Overpower")
            ns.Set("procLight", false); assert(not light.shown)
            msg("7384u"); assert(not light.shown)
            ns.Set("procLight", true); assert(light.shown)
        ''')

    def test_move_mode_resize_and_reset(self):
        self.load('class = "PRIEST"; db.procLightSize = 120')
        self.run_lua('''
            assert(light.w == 120) -- saved size applied at login
            moveMode = true; tick()
            assert(light.shown and light.mouse and grip.shown and light.spell.value == "Glisse-moi")
            msg("5308u"); assert(light.spell.value == "Glisse-moi") -- move mode keeps the sample
            light.w, light.h = 150, 130 -- dragged by the grip
            grip.scripts.OnMouseUp(grip)
            assert(light.w == 150 and light.h == 150 and db.procLightSize == 150) -- kept square
            moveMode = false; tick()
            assert(not light.mouse and not grip.shown and light.spell.value == "Execute")
            msg(""); assert(not light.shown)
            ns.ProcLightCommand("reset")
            assert(light.w == 70 and db.procLightSize == nil)
        ''')

    def test_debug_prints_what_the_client_answers(self):
        self.load()
        self.run_lua('''
            usable.Overpower = true; noPower.Execute = true; tick()
            ns.ProcLightCommand("debug")
            local text = table.concat(printed, "\\n")
            assert(text:find("Overpower %(rang 7887%) : utilisable=true"), text)
            assert(text:find("Execute .*allume, pas assez de ressource"), text)
            assert(text:find("envoye : 7384u,5308p"), text)
        ''')

    def test_classes_without_reactive_spells_only_display(self):
        self.load('class = "MAGE"')
        self.run_lua('''
            assert(#tickers == 1) -- the display only
            assert(not ev().events.SPELL_UPDATE_USABLE)
        ''')

    VICTORY = '''
        NAMES[402927] = "Victory Rush"; learned["Victory Rush"] = 402927
        auras = {}
        C_UnitAuras = {GetPlayerAuraBySpellID = function(id) return auras[id] end}
    '''

    def test_victory_rush_lit_by_its_buff_out_of_combat(self):
        self.load(self.VICTORY + "combat = false")
        self.run_lua('''
            usable.Overpower = true; tick(); assert(#sent == 0, last()) -- out of combat: only Victory Rush
            auras[402975] = {spellId = 402975}; tick(); assert(last() == "PR:402927u", last())
            auras[402975] = nil; tick(); assert(last() == "PR:", last()) -- buff over (or spent)
        ''')

    def test_victory_rush_in_combat_hidden_buff_then_glow(self):
        self.load(self.VICTORY)
        self.run_lua('''
            auras[402975] = SECRET; tick(); assert(#sent == 0, last()) -- hidden in combat, never compared
            glow[402927] = true; tick(); assert(last() == "PR:402927u", last()) -- the game's glow on it
            usable.Overpower = true; tick(); assert(last() == "PR:7384u,402927u", last()) -- last in PROCS order
            event("CHAT_MSG_ADDON", "x", "y", "PARTY", "Partner") -- unrelated message
            ns.ProcLightCommand("debug")
            local found
            for _, p in ipairs(printed) do if p:find("Victory Rush", 1, true) and p:find("buff=SECRET", 1, true) then found = true end end
            assert(found, table.concat(printed, " | "))
        ''')

    def test_lit_list_goes_to_the_spell_panel(self):
        self.load()
        self.run_lua('''
            local got
            ns.OnPartnerProcs = function(list) got = list end
            msg("7384u,5308p")
            assert(#got == 2 and got[1].id == 7384 and got[1].ready and got[2].id == 5308 and not got[2].ready)
            tick(3.5); assert(#got == 0) -- 3 s without news: out
        ''')


if __name__ == "__main__":
    unittest.main()
