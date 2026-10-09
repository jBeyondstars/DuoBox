"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, printed, updates, frames = {dungeon = false}, {}, 0, {}
SECRET = {}
-- party units: {name=, role=}; party1 = the priest partner, party2 = the tank
units = {
    party1 = {name = "Duobox Three", role = "HEALER"},
    party2 = {name = "Tanky", role = "TANK"},
    party3 = {name = "Rogue-Realm", role = "DAMAGER"},
}
ns = {}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.BarUnit() return "party1" end
function ns.Set(key, value) db[key] = value end
function ns.UpdateBar() updates = updates + 1 end
function issecretvalue(v) return v == SECRET end
function UnitExists(u) return units[u] ~= nil end
function UnitName(u) return units[u] and units[u].name end
function UnitGroupRolesAssigned(u) return units[u] and units[u].role or "NONE" end
function CreateFrame()
    local f = {}
    function f:RegisterEvent(name) self[name] = true end
    function f:SetScript(_, fn) self.handler = fn end
    table.insert(frames, f)
    return f
end
'''


class DungeonTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute((ROOT / "Dungeon.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)

    def run_lua(self, code):
        self.lua.execute(code)

    def test_off_assists_the_partner(self):
        self.run_lua('assert(ns.AssistUnit() == "party1" and ns.DungeonStatus():find("desactive"))')

    def test_on_assists_the_member_with_the_tank_role(self):
        self.run_lua('''
            db.dungeon = true
            assert(ns.AssistUnit() == "party2")
            assert(ns.DungeonStatus():find("Tanky") and ns.DungeonStatus():find("role Tank"))
        ''')

    def test_secret_roles_in_an_instance_keep_the_last_tank(self):
        self.run_lua('''
            db.dungeon = true
            assert(ns.AssistUnit() == "party2")
            for _, u in pairs(units) do u.role = SECRET end
            assert(ns.AssistUnit() == "party2")
            units.party2, units.party4 = nil, {name = "Tanky", role = SECRET} -- roster order changed
            assert(ns.AssistUnit() == "party4")
        ''')

    def test_no_tank_or_you_are_the_tank_falls_back_to_the_partner(self):
        self.run_lua('''
            db.dungeon = true
            assert(ns.AssistUnit() == "party2")
            units.party2.role = "DAMAGER" -- readable roles, nobody else is the tank
            assert(ns.AssistUnit() == "party1" and ns.DungeonStatus():find("Aucun tank"))
        ''')

    def test_name_set_by_hand_wins_and_matches_the_first_name(self):
        self.run_lua('''
            db.dungeon = true
            ns.DungeonCommand("tank", "Rogue-OtherRealm")
            assert(db.tank == "Rogue" and ns.AssistUnit() == "party3", tostring(ns.AssistUnit()))
            assert(ns.DungeonStatus():find("nom saisi"))
            ns.DungeonCommand("tank", "Nobody")
            assert(ns.AssistUnit() == "party1" and ns.DungeonStatus():find("Nobody n'est pas dans le groupe"))
            ns.DungeonCommand("tank", "auto")
            assert(db.tank == nil and ns.AssistUnit() == "party2")
        ''')

    def test_dungeon_command_toggles_and_role_events_refresh_the_bar(self):
        self.run_lua('''
            ns.DungeonCommand("dungeon", "")
            assert(db.dungeon == true and printed[#printed]:find("mode donjon"))
            ns.DungeonCommand("dungeon", "off")
            assert(db.dungeon == false)
            local f = frames[1]
            assert(f.PLAYER_ROLES_ASSIGNED and f.ROLE_CHANGED_INFORM)
            f.handler(f, "PLAYER_ROLES_ASSIGNED")
            assert(updates == 1)
        ''')


if __name__ == "__main__":
    unittest.main()
