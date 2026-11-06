"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, printed, frames, tickers, timers = {journal = false, partner = "Priest"}, {}, {}, {}, {}
clock, serverClock, localClock, combat, partner, lightCode, logging = 100, 5000, 4000, false, "party1", nil, false
cvars = {SoftTargetInteract = "3", advancedCombatLogging = "0"}
SECRET = {}
units = {} -- unit -> {guid, name, enemy, dead, friend, player}
actions = {[145] = {"macro", 7, "D-ChargeP"}, [3] = {"spell", 78}}
ERR_BADATTACKFACING = "You are facing the wrong way!"
ERR_BADATTACKPOS = "You are too far away!"
SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight"
ns = {}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.PartnerUnit() return partner end
function ns.Set(key, value) db[key] = value; if key == "journal" then ns.RefreshJournal() end end
function ns.SpellNameIcon(id) if id == 78 then return "Heroic Strike" end end
function ns.FromPartner(body, sender) if sender == "Priest" then return body end end
function ns.MeleeLightCode() return lightCode end
function issecretvalue(v) return v == SECRET end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return clock end
function GetServerTime() return serverClock end
function time() return localClock end
function GetBuildInfo() return "1.60.1" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitAffectingCombat(u) return combat end
local function U(u) return units[u] end
function UnitExists(u) return U(u) ~= nil end
function UnitGUID(u) return U(u) and U(u).guid end
function UnitName(u) return U(u) and U(u).name end
function UnitCanAttack(_, u) return U(u) and U(u).enemy end
function UnitIsDead(u) return U(u) and U(u).dead end
function UnitIsFriend(_, u) return U(u) and U(u).friend end
function UnitIsPlayer(u) return U(u) and U(u).player end
function GetActionInfo(slot) local a = actions[slot]; if a then return a[1], a[2] end end
function GetActionText(slot) local a = actions[slot]; return a and a[1] == "macro" and a[3] or nil end
function GetMacroInfo(id) return "?" end
function LoggingCombat(v) if v ~= nil then logging = v end return logging end
lockdown = false
function InCombatLockdown() return lockdown end
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, v) cvars[name] = v end,
}
C_Timer = {
    NewTicker = function(t, fn) table.insert(tickers, fn) end,
    After = function(t, fn) table.insert(timers, fn) end,
}
C_NamePlate = { GetNamePlates = function()
    local list = {}
    for i = 1, 5 do if units["nameplate" .. i] then table.insert(list, {namePlateUnitToken = "nameplate" .. i}) end end
    return list
end }
C_PlayerInteractionManager = { InteractUnit = function(unit) return true end }
function UseAction(slot) end
function AssistUnit(unit) end
function TargetUnit(unit) end
function ConsoleGetAllCommands()
    return {{command = "SoftTargetEnemy"}, {command = "TargetAutoEnemy"}, {command = "cameraZoomSpeed"},
        {command = "advancedCombatLogging"}, {command = "targetNearestFriend"}}
end
cvars.SoftTargetEnemy, cvars.TargetAutoEnemy, cvars.cameraZoomSpeed = "1", "0", "20"
function hooksecurefunc(a, b, c)
    local tbl, name, fn = _G, a, b
    if type(a) == "table" then tbl, name, fn = a, b, c end
    local orig = tbl[name]
    tbl[name] = function(...) local r = {orig(...)}; fn(...); return unpack(r) end
end

local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:HookScript(name, fn) self.hooks[name] = fn end
function Methods:RegisterEvent(name) self.events[name] = true end
function Methods:RegisterUnitEvent(name) self.events[name] = true end
function Obj()
    local o = {scripts = {}, hooks = {}, events = {}}
    return setmetatable(o, {__index = function(_, k) return Methods[k] or function() end end})
end
function CreateFrame(_, name) local f = Obj(); table.insert(frames, f); if name then _G[name] = f end; return f end
DuoBoxBtnAssist = Obj()

function ev() return frames[2] end -- clock, events
function event(name, ...) ev().scripts.OnEvent(ev(), name, ...) end
function tick(dt)
    clock = clock + (dt or 0.2)
    for _, fn in ipairs(tickers) do fn() end
    local upd = frames[1].scripts.OnUpdate
    if upd then upd(frames[1]) end
end
function entries() return DuoBoxJournal and DuoBoxJournal.entries or {} end
function codes()
    local out = {}
    for _, s in ipairs(entries()) do out[#out + 1] = s:match("^[%d%.]+|(.*)$") end
    return table.concat(out, "\n")
end
'''


class JournalTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute((ROOT / "Journal.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    def codes(self):
        return self.lua.eval("codes()").split("\n") if self.lua.eval("#entries()") > 0 else []

    def start(self):
        self.run_lua('ns.Set("journal", true)')

    def test_off_by_default_writes_nothing(self):
        self.run_lua('''
            combat = true; event("PLAYER_REGEN_DISABLED")
            units.target = {guid = "Creature-1", name = "Wolf", enemy = true}
            event("PLAYER_TARGET_CHANGED"); tick(); UseAction(145); C_PlayerInteractionManager.InteractUnit("anyinteract")
        ''')
        self.assertEqual(self.codes(), [])
        self.assertFalse(self.lua.eval("logging"))

    def test_on_starts_the_game_combat_log_in_advanced_mode_and_off_stops_it(self):
        self.start()
        self.assertTrue(self.lua.eval("logging"))
        self.assertEqual(self.lua.eval("cvars.advancedCombatLogging"), "1")
        self.assertEqual(self.codes()[0], "I|?|WARRIOR|?|Priest|1.60.1")
        self.run_lua('ns.Set("journal", false)')
        self.assertFalse(self.lua.eval("logging"))

    def test_switched_on_or_off_in_combat_the_combat_log_waits_for_the_end(self):
        self.run_lua('lockdown = true; combat = true; ns.Set("journal", true)')
        self.assertFalse(self.lua.eval("logging"))
        self.assertEqual(self.lua.eval("cvars.advancedCombatLogging"), "0")
        self.assertEqual(self.codes()[0][:2], "I|")  # the journal itself starts at once
        self.run_lua('lockdown = false; combat = false; event("PLAYER_REGEN_ENABLED")')
        self.assertTrue(self.lua.eval("logging"))
        self.assertEqual(self.lua.eval("cvars.advancedCombatLogging"), "1")
        self.run_lua('lockdown = true; ns.Set("journal", false)')
        self.assertTrue(self.lua.eval("logging"))
        self.run_lua('lockdown = false; event("PLAYER_REGEN_ENABLED")')
        self.assertFalse(self.lua.eval("logging"))

    def test_off_leaves_a_combat_log_the_player_started(self):
        self.run_lua('logging = true')
        self.start()
        self.run_lua('ns.Set("journal", false)')
        self.assertTrue(self.lua.eval("logging"))

    def test_a_fight_targets_light_and_deaths(self):
        self.start()
        self.run_lua('''
            combat = true
            units.target = {guid = "Creature-1", name = "Wolf", enemy = true}
            units.party1target = {guid = "Creature-2", name = "Boar", enemy = true}
            lightCode = "R"
            event("PLAYER_REGEN_DISABLED")
            tick(); tick()                       -- no change: nothing new
            lightCode = "G"; tick()
            units.target.dead = true; tick()     -- a death fires no target event: the poll sees it
            event("UNIT_TARGET", "party1")       -- same partner target: not written again
            units.party1target = nil; event("UNIT_TARGET", "party1")
            combat = false; lightCode = "N"; event("PLAYER_REGEN_ENABLED")
        ''')
        codes = self.codes()
        self.assertEqual(codes[1:3], ["T|-||", "P|-||"])  # the session start writes both targets
        got = [c for c in codes[codes.index("C|1"):] if c[0] in "CTPL"]
        self.assertEqual(got, [
            "C|1", "T|Creature-1|Wolf|E", "P|Creature-2|Boar|E", "L|R",
            "L|G", "T|Creature-1|Wolf|ED", "P|-||", "L|N", "C|0",
        ])

    def test_key_presses_interact_and_assist_lines(self):
        self.start()
        self.run_lua('''
            UseAction(145); UseAction(3); AssistUnit("party1")
            cvars.SoftTargetInteract = "0"; C_PlayerInteractionManager.InteractUnit("anyinteract")
            DuoBoxBtnAssist.hooks.OnClick(DuoBoxBtnAssist, "LeftButton")
        ''')
        got = [c for c in self.codes() if c[0] in "KX"]
        self.assertEqual(got, ["K|A|145|macro|D-ChargeP", "K|A|3|spell|Heroic Strike", "X|AssistUnit|party1",
                               "K|I|anyinteract|0", "K|B|Assist|LeftButton"])

    def test_errors_spells_emotes_and_enemy_count(self):
        self.start()
        self.run_lua('''
            combat = true; event("PLAYER_REGEN_DISABLED")
            event("UI_ERROR_MESSAGE", 50, ERR_BADATTACKFACING)
            event("UI_ERROR_MESSAGE", 51, "Not enough rage")
            event("UI_ERROR_MESSAGE", 52, SPELL_FAILED_LINE_OF_SIGHT)
            event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 78)
            event("UNIT_SPELLCAST_FAILED", "player", "cast-2", 78)
            event("CHAT_MSG_MONSTER_EMOTE", "%s attempts to run away in fear!", "Kobold")
            units.nameplate1 = {enemy = true}; units.nameplate2 = {enemy = true}; units.nameplate3 = {enemy = true, dead = true}
            tick(1.1)
        ''')
        codes = self.codes()
        for want in ["E|F|You are facing the wrong way!", "E|O|Not enough rage", "E|V|Target not in line of sight",
                     "Q|S|78|Heroic Strike", "Q|F|78|Heroic Strike", "M|Kobold|%s attempts to run away in fear!", "N|2"]:
            self.assertIn(want, codes)

    def test_priest_logs_the_light_it_receives_once_per_change(self):
        self.start()
        self.run_lua('''
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Priest")
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:R", "PARTY", "Priest")
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:G", "PARTY", "Stranger")
            event("CHAT_MSG_ADDON", "DUOBOX", "ML:G", "PARTY", "Priest")
        ''')
        self.assertEqual([c for c in self.codes() if c[0] == "R"], ["R|R", "R|G"])

    def test_secret_values_are_written_as_unknown(self):
        self.start()
        self.run_lua('''
            units.target = {guid = SECRET, name = SECRET, enemy = SECRET, dead = false}
            event("PLAYER_TARGET_CHANGED")
        ''')
        self.assertIn("T|?|?|", self.codes())

    def test_pipes_in_text_cannot_break_the_fields(self):
        self.start()
        self.run_lua('event("UI_ERROR_MESSAGE", 1, "a|b\\nc")')
        self.assertIn("E|O|a b c", self.codes())

    def test_clock_edges_give_the_epoch_of_get_time(self):
        self.start()
        self.run_lua('''
            tick(0.1)
            serverClock = serverClock + 1; tick(0.4)
            localClock = localClock + 1; tick(0.3)
            tick(0.2)
        ''')
        edges = [e for e in self.lua.eval("codes()").split("\n") if e.startswith("S|")]
        self.assertEqual(edges, ["S|server|5001", "S|local|4001"])
        raw = list(self.lua.eval("entries()").values())
        self.assertTrue(any(s.startswith("100.500|S|server") for s in raw))

    def test_oldest_entries_go_when_the_journal_is_full(self):
        self.start()
        self.run_lua('for i = 1, 40005 do UseAction(3) end; UseAction(145)')
        n = self.lua.eval("#entries()")
        self.assertLessEqual(n, 40000)
        self.assertGreater(n, 30000)
        self.assertEqual(self.codes()[-1], "K|A|145|macro|D-ChargeP")

    def test_summary_counts_fights_and_red_seconds(self):
        self.start()
        self.run_lua('''
            combat = true; lightCode = "G"; event("PLAYER_REGEN_DISABLED")
            lightCode = "R"; tick(0.2); clock = clock + 2; lightCode = "G"; tick(0.2)
            lightCode = "F"; tick(0.2); lightCode = "G"; tick(0.6)
            combat = false; lightCode = "N"; event("PLAYER_REGEN_ENABLED")
            ns.JournalCommand("")
        ''')
        msg = self.lua.eval("printed[#printed]")
        self.assertIn("1 combats", msg)
        self.assertIn("trop loin 2 s", msg)
        self.assertIn("mal oriente 1 s", msg)  # 0.6 s, rounded

    def test_cvar_dump_keeps_the_targeting_ones(self):
        self.run_lua('ns.JournalCommand("cvars")')
        cv = self.lua.eval("DuoBoxJournal.cvars")
        self.assertEqual(sorted(cv.keys()), ["SoftTargetEnemy", "TargetAutoEnemy", "advancedCombatLogging", "targetNearestFriend"])
        self.assertIn("SoftTargetEnemy=1", self.lua.eval("printed[#printed]"))
        self.assertIn("TargetAutoEnemy=0", self.lua.eval("printed[#printed]"))

    def test_clear_empties_and_restarts_a_session(self):
        self.start()
        self.run_lua('UseAction(3); ns.JournalCommand("clear")')
        self.assertEqual(self.codes()[0][:2], "I|")
        self.assertNotIn("K|A|3|spell|Heroic Strike", self.codes())


if __name__ == "__main__":
    unittest.main()
