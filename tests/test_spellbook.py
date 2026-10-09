"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
SPELLS = {
    [78] = "Heroic Strike", [284] = "Heroic Strike", [7384] = "Overpower", [6673] = "Battle Shout",
    [2050] = "Lesser Heal", [2054] = "Heal", [2055] = "Heal",
}
C_Spell = { GetSpellInfo = function(id) if SPELLS[id] then return {name = SPELLS[id], iconID = id} end end }
Enum = { SpellBookSpellBank = {Player = 0}, SpellBookItemType = {Spell = 1, FutureSpell = 2} }
-- Spellbook items: {type, name}; Heroic Strike rank 2 replaced rank 1, Overpower is a future spell
book = { {1, "Attack"}, {1, "Battle Shout"}, {1, "Heroic Strike"}, {2, "Overpower"} }
reads = 0
C_SpellBook = {}
function C_SpellBook.GetNumSpellBookSkillLines() return 1 end
function C_SpellBook.GetSpellBookSkillLineInfo(i) return {itemIndexOffset = 0, numSpellBookItems = #book} end
function C_SpellBook.GetSpellBookItemType(slot) reads = reads + 1; return book[slot] and book[slot][1] end
function C_SpellBook.GetSpellBookItemName(slot) return book[slot] and book[slot][2], "" end
function IsPlayerSpell(id) return id == 284 or id == 6673 end -- rank 1 (78) is no longer "known"

frames = {}
function CreateFrame()
    local f = {}
    function f:RegisterEvent(name) self.event = name end
    function f:SetScript(_, fn) self.handler = fn end
    table.insert(frames, f)
    return f
end
function event() frames[1].handler(frames[1], frames[1].event) end
ns = {}
'''


class SpellbookTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)

    def load(self, setup=""):
        self.lua.execute(setup)
        self.lua.execute((ROOT / "Spellbook.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)

    def run_lua(self, code):
        self.lua.execute(code)

    def test_rank_1_id_counts_when_rank_2_replaced_it(self):
        self.load()
        self.run_lua('''
            assert(ns.Known(78) == true and ns.Known(284) == true and ns.Known(6673) == true)
            assert(ns.Known(7384) == false) -- in the spellbook as a future spell only
            assert(ns.Known(999) == false) -- unknown spell ID
            local name, icon = ns.SpellNameIcon(78)
            assert(name == "Heroic Strike" and icon == 78)
        ''')

    def test_spellbook_is_read_again_after_spells_changed(self):
        self.load()
        self.run_lua('''
            assert(ns.Known(7384) == false)
            local before = reads
            assert(ns.Known(78)); assert(reads == before) -- cached
            book[4][1] = 1 -- Overpower learned
            assert(frames[1].event == "SPELLS_CHANGED")
            event()
            assert(ns.Known(7384) == true)
        ''')

    def test_heal_rank_1_counts_once_heal_rank_2_is_learned(self):
        self.load('book = { {1, "Lesser Heal"}, {1, "Heal"} }')
        self.run_lua('assert(ns.Known(2054) == true and ns.Known(2050) == true)')

    def test_empty_spellbook_is_not_cached(self):
        self.load('book = {}')
        self.run_lua('''
            assert(ns.Known(78) == false)
            book = { {1, "Heroic Strike"} }
            assert(ns.Known(78) == true) -- loaded later, no SPELLS_CHANGED needed
        ''')

    def test_classic_era_without_spellbook_api_uses_spell_ids(self):
        self.load('C_SpellBook = nil')
        self.run_lua('assert(ns.Known(284) == true and ns.Known(78) == false)')


if __name__ == "__main__":
    unittest.main()
