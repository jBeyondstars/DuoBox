"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, printed, calls, tickers, frames = {}, {}, {}, {}, {}
class, partner = "WARRIOR", "party1"
units = {}  -- unit -> {name=, enemy=bool, dead=bool}
combat = {} -- unit -> true while in combat
SECRET = {}
ns = {}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.PartnerUnit() return partner end
function ns.Set(key, value) db[key] = value; ns.RefreshInteract() end
function issecretvalue(v) return v == SECRET end
function UnitClass() return class, class end
function UnitName(u) return units[u] and units[u].name end
function UnitExists(u) return units[u] ~= nil end
function UnitCanAttack(_, u) return units[u] ~= nil and units[u].enemy end
function UnitIsDead(u) return units[u] ~= nil and (units[u].dead or false) end
function UnitAffectingCombat(u) return combat[u] or false end

base, temp, refuse, refuseRemove = "3", nil, false, false
C_CVar = {}
function C_CVar.GetCVar(name) assert(name == "SoftTargetInteract"); return temp or base end
function C_CVar.SetTempCVar(name, v) table.insert(calls, "set " .. v); if not refuse then temp = v end end
function C_CVar.RemoveTempCVar(name) table.insert(calls, "remove"); if not refuseRemove then temp = nil end end
C_Timer = { NewTicker = function(_, fn) table.insert(tickers, fn) end }

-- /assist party1 in a macro: the target changes, no event yet
function AssistUnit(u) units.target = units[u .. "target"] end
function hooksecurefunc(name, hook)
    local original = _G[name]
    _G[name] = function(...) original(...); hook(...) end
end

function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:RegisterUnitEvent() end
    function f:SetScript(_, fn) self.handler = fn end
    table.insert(frames, f)
    return f
end
function event(name, ...) frames[1].handler(frames[1], name, ...) end
function tick() for _, fn in ipairs(tickers) do fn() end end
function value() return C_CVar.GetCVar("SoftTargetInteract") end
'''


class InteractPriorityTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)

    def load(self, setup=""):
        self.lua.execute(setup)
        self.lua.execute((ROOT / "InteractPriority.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    def test_warrior_enemy_target_goes_before_soft_interact_until_it_dies(self):
        self.load()
        self.run_lua('''
            assert(db.interactEnemy == true and value() == "3")
            units.target = {enemy=true}; event("PLAYER_TARGET_CHANGED"); assert(value() == "0")
            units.target.dead = true; tick(); assert(value() == "3")
        ''')

    def test_partner_enemy_target_counts_only_in_combat(self):
        self.load()
        self.run_lua('''
            units.party1target = {enemy=true}; event("UNIT_TARGET", "party1"); assert(value() == "3")
            combat.party1 = true; tick(); assert(value() == "0")
            -- fight over, the priest already targets the next mob: loot and objects again
            combat.party1 = nil; event("PLAYER_REGEN_ENABLED"); assert(value() == "3")
        ''')

    def test_assist_turns_it_off_before_the_interact_key(self):
        self.load()
        self.run_lua('''
            units.party1target = {enemy=true}; tick(); assert(value() == "3")
            AssistUnit("party1"); assert(value() == "0")
        ''')

    def test_friendly_or_secret_targets_keep_soft_interact(self):
        self.load()
        self.run_lua('''
            units.target = {enemy=false}; event("PLAYER_TARGET_CHANGED"); assert(value() == "3")
            units.target = {enemy=SECRET}; event("PLAYER_TARGET_CHANGED"); assert(value() == "3")
            units.target = {enemy=true, dead=SECRET}; event("PLAYER_TARGET_CHANGED"); assert(value() == "0")
        ''')

    def test_option_off_restores_the_saved_value(self):
        self.load()
        self.run_lua('''
            units.target = {enemy=true}; event("PLAYER_TARGET_CHANGED"); assert(value() == "0")
            ns.InteractCommand("off"); assert(db.interactEnemy == false and value() == "3" and base == "3")
            local n = #calls; tick(); tick(); assert(#calls == n)
        ''')

    def test_refused_restore_is_retried(self):
        self.load()
        self.run_lua('''
            units.target = {enemy=true}; event("PLAYER_TARGET_CHANGED"); assert(value() == "0")
            refuseRemove = true; units.target = nil; event("PLAYER_TARGET_CHANGED"); tick()
            assert(value() == "0" and #printed == 1)
            refuseRemove = false; tick(); assert(value() == "3")
        ''')

    def test_soft_interact_already_off_is_left_alone(self):
        self.load('base = "0"')
        self.run_lua('''
            units.target = {enemy=true}; event("PLAYER_TARGET_CHANGED"); units.target = nil; tick()
            assert(value() == "0" and #calls == 1 and calls[1] == "remove" and #printed == 0)
        ''')

    def test_status_names_the_reason(self):
        self.load()
        self.run_lua('''
            units.party1target = {name="Kobold", enemy=true}; combat.player = true; tick()
            ns.InteractCommand(""); assert(printed[1]:find("Kobold") and printed[1]:find("= 0"))
        ''')

    def test_priest_is_off_by_default(self):
        self.load('class = "PRIEST"')
        self.run_lua('''
            assert(db.interactEnemy == false)
            units.target = {enemy=true}; event("PLAYER_TARGET_CHANGED"); assert(value() == "3")
        ''')

    def test_login_clears_a_temporary_value_left_by_a_reload(self):
        self.load('temp = "0"')
        self.run_lua('assert(value() == "3" and calls[1] == "remove")')

    def test_refused_change_warns_once_and_retries(self):
        self.load('refuse = true')
        self.run_lua('''
            units.target = {enemy=true}; event("PLAYER_TARGET_CHANGED"); tick(); tick()
            assert(value() == "3" and #printed == 1 and #calls == 3)
        ''')

    def test_client_without_temporary_cvars_stays_off(self):
        self.load('C_CVar.SetTempCVar = nil')
        self.run_lua('''
            assert(db.interactEnemy == false)
            db.interactEnemy = true; units.target = {enemy=true}; event("PLAYER_TARGET_CHANGED"); tick()
            assert(value() == "3" and #printed == 1)
        ''')


if __name__ == "__main__":
    unittest.main()
