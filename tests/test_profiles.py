"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import re
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
# The defaults table of DuoBox.lua, as written there
DEFAULTS = re.search(r"^local defaults = (\{.*?^\})", (ROOT / "DuoBox.lua").read_text(encoding="utf-8"),
                     re.S | re.M).group(1)
MOCK = r'''
printed, sets, lockdown, player = {}, {}, false, {"Duobox Four", "WARRIOR"}
ns = {DEFAULTS = DEFAULTS}
db = {}
for k, v in pairs(DEFAULTS) do db[k] = v end
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.Set(key, value) db[key] = value; table.insert(sets, key) end
function InCombatLockdown() return lockdown end
function UnitName() return player[1] end
function UnitClass() return player[2]:lower(), player[2] end
function last() return printed[#printed] end
'''


class ProfilesTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("DEFAULTS = " + DEFAULTS)
        self.lua.execute(MOCK)
        self.lua.execute((ROOT / "Profiles.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)

    def run_lua(self, code):
        self.lua.execute(code)

    def test_every_setting_is_in_profiles_or_excluded(self):
        keys = re.findall(r"^\s*(\w+)\s*=", DEFAULTS, re.M)
        self.assertIn("lightSound", keys)
        ns = self.lua.globals().ns
        listed = set(ns.PROFILE_KEYS.values())
        excluded = set(ns.PROFILE_EXCLUDED.keys())
        self.assertFalse(listed & excluded)
        self.assertEqual(sorted(set(keys) - listed - excluded), [], "add new settings to KEYS or EXCLUDED in Profiles.lua")
        self.assertEqual(sorted((listed | excluded) - set(keys)), [])

    def test_load_restores_the_settings_but_keeps_names_and_role(self):
        self.run_lua('''
            db.partner, db.tank, db.role, db.dungeon, db.hpPartner, db.leader = "Duobox Three", "Tanky", "dps", true, 40, "heal"
            ns.ProfileSave("Donjon")
            db.partner, db.tank, db.role, db.dungeon, db.hpPartner, db.leader = "Other", "Tank2", "heal", false, 60, nil
            assert(ns.ProfileLoad("Donjon"))
            assert(db.dungeon == true and db.hpPartner == 40 and db.leader == "heal")
            assert(db.partner == "Other" and db.tank == "Tank2" and db.role == "heal")
            assert(#sets == 3, #sets) -- only the changed settings go through ns.Set
            assert(last():find("3 reglages modifies"), last())
            assert(db.profile == "Donjon" and DuoBoxProfiles.Donjon.by == "Duobox Four")
        ''')

    def test_nil_auto_values_are_restored_and_missing_ones_use_the_default(self):
        self.run_lua('''
            db.leader = nil
            ns.ProfileSave("Auto")
            DuoBoxProfiles.Auto.values.sound = nil -- as if "sound" was added after the save
            db.leader, db.sound = "heal", false
            ns.ProfileLoad("Auto")
            assert(db.leader == nil and db.sound == true)
        ''')

    def test_rotation_is_copied_and_kept_when_the_profile_has_none(self):
        self.run_lua('''
            db.rotation = {{id = 6673, once = true}, {id = 78}}
            ns.ProfileSave("Guerrier")
            db.rotation[2].id = 7384 -- edits after the save do not change the profile
            assert(DuoBoxProfiles.Guerrier.rotation[2].id == 78)
            ns.ProfileLoad("Guerrier")
            assert(db.rotation[2].id == 78 and sets[#sets] == "rotation")
            db.rotation[1].once = nil
            assert(DuoBoxProfiles.Guerrier.rotation[1].once == true)

            db.rotation = nil
            ns.ProfileSave("Pretre") -- saved by a character without a rotation
            db.rotation = {{id = 78}}
            ns.ProfileLoad("Pretre")
            assert(db.rotation[1].id == 78)
        ''')

    def test_load_is_refused_in_combat(self):
        self.run_lua('''
            ns.ProfileSave("A")
            db.sound = false
            lockdown = true
            assert(not ns.ProfileLoad("A") and db.sound == false and last():find("hors combat"))
        ''')

    def test_names_ignore_the_case_and_replace_the_same_profile(self):
        self.run_lua('''
            ns.ProfileSave("Donjon")
            db.hpPartner = 30
            ns.ProfileSave("donjon")
            local names = ns.ProfileNames()
            assert(#names == 1 and names[1] == "Donjon" and DuoBoxProfiles.Donjon.values.hpPartner == 30)
            assert(ns.ProfileInfo("DONJON") == DuoBoxProfiles.Donjon)
            assert(not ns.ProfileLoad("Raid") and last():find("aucun profil"))
        ''')

    def test_active_profile_tracks_changes(self):
        self.run_lua('''
            assert(ns.ActiveProfile() == nil)
            ns.ProfileSave("A")
            local name, changed = ns.ActiveProfile()
            assert(name == "A" and changed == false)
            db.flash = false
            name, changed = ns.ActiveProfile()
            assert(name == "A" and changed == true)
            db.partner = "Someone" -- not in a profile
            db.flash = true
            assert(select(2, ns.ActiveProfile()) == false)
            assert(ns.ProfileDelete("a") and ns.ActiveProfile() == nil and db.profile == nil)
        ''')

    def test_command(self):
        self.run_lua('''
            ns.ProfileCommand("")
            assert(printed[#printed - 1]:find("aucun profil"))
            ns.ProfileCommand("save Quetes et donjons")
            assert(DuoBoxProfiles["Quetes et donjons"])
            db.sound = false
            ns.ProfileCommand("save") -- the active profile
            assert(DuoBoxProfiles["Quetes et donjons"].values.sound == false)
            db.sound = true
            ns.ProfileCommand("")
            assert(printed[#printed - 1]:find("actif, modifie"))
            ns.ProfileCommand("load quetes et donjons")
            assert(db.sound == false)
            ns.ProfileCommand("delete Quetes et donjons")
            assert(#ns.ProfileNames() == 0)
        ''')


if __name__ == "__main__":
    unittest.main()
