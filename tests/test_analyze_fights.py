"""Run with python -m unittest discover -s tests (standard library only)."""
import io
import json
import math
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import analyze_fights as af  # noqa: E402

EPOCH = datetime(2026, 11, 6, 20, 0, 0).timestamp()
T0 = 1000.0                    # GetTime() of the session start
LOCAL_OFF = EPOCH - T0         # journal: epoch = GetTime() + LOCAL_OFF
SKEW = 0.7                     # the combat log clock is 0.7 s ahead of the journal's edge
W, A, B = "Player-1-0000000W", "Creature-0-1-2-3-100-00000000A", "Creature-0-1-2-3-101-00000000B"


def stamp(t):
    """Combat log timestamp of a journal time."""
    dt = datetime.fromtimestamp(t + LOCAL_OFF + SKEW)
    return f"{dt.month}/{dt.day} {dt.hour:02d}:{dt.minute:02d}:{dt.second:02d}.{dt.microsecond // 1000:03d}"


def adv(guid, x, y, facing):
    return [guid, "0000000000000000", "100", "100", "0", "0", "0", "-1", "1", "50", "100", "0",
            f"{x:.2f}", f"{y:.2f}", "1429", f"{facing % (2 * math.pi):.4f}", "20"]


def cl(t, event, src, sname, dst, dname, *rest):
    fields = [event, src, f'"{sname}"', "0x511", "0x0", dst, f'"{dname}"', "0xa48", "0x0"] + [str(r) for r in rest]
    return f"{stamp(t)}  " + ",".join(fields)


SWING_SUFFIX = ["25", "0", "1", "0", "0", "0", "nil", "nil", "nil"]


def swing(t, dst, dname, wpos, facing):
    return cl(t, "SWING_DAMAGE", W, "Warrior-Realm", dst, dname, *(adv(W, *wpos, facing) + SWING_SUFFIX))


def mob_swing(t, mob, mname, mpos):
    return cl(t, "SWING_DAMAGE", mob, mname, W, "Warrior-Realm", *(adv(mob, *mpos, 0.0) + SWING_SUFFIX))


def cast(t, spell_id, name):
    return cl(t, "SPELL_CAST_SUCCESS", W, "Warrior-Realm", "0000000000000000", "nil", spell_id, f'"{name}"', "0x1",
              *adv(W, 0.0, 0.0, 0.0))


# One hard fight, every number known in advance (see test_full_fight)
JOURNAL = [
    (1000.0, "I|Warrior|WARRIOR|" + W + "|Priest|1.60.1"),
    (1000.5, f"S|local|{int(EPOCH + 1)}"),       # local edge: epoch(1000.5) = EPOCH + 0.5... rounded to the second edge
    (1010.0, "C|1"), (1010.0, f"T|{A}|Wolf|E"), (1010.0, f"P|{A}|Wolf|E"), (1010.0, "L|G"), (1010.0, "N|3"),
    (1010.5, "Q|S|6673|Battle Shout"), (1012.0, "Q|S|78|Heroic Strike"),
    (1015.0, "L|R"),
    (1016.0, "K|A|145|macro|D-ChargeP"), (1016.0, "X|AssistUnit|party1"), (1016.1, "K|I|anyinteract|0"),
    (1017.5, "L|G"), (1018.0, "Q|S|78|Heroic Strike"),
    (1020.0, f"T|{A}|Wolf|ED"), (1020.0, f"P|{A}|Wolf|ED"), (1020.0, "L|T"),
    (1021.0, "K|A|145|macro|D-ChargeP"), (1021.0, "X|AssistUnit|party1"), (1021.1, "K|I|anyinteract|3"),
    (1022.5, f"P|{B}|Boar|E"),
    (1023.0, "K|A|145|macro|D-ChargeP"), (1023.0, "X|AssistUnit|party1"), (1023.0, f"T|{B}|Boar|E"),
    (1023.1, "K|I|anyinteract|0"),
    (1024.0, "L|G"), (1025.0, "Q|S|78|Heroic Strike"),
    (1026.0, "L|F"), (1026.0, "E|F|You are facing the wrong way!"), (1027.0, "L|G"),
    (1030.0, "M|Boar|%s attempts to run away in fear!"), (1031.0, "L|R"), (1034.0, "L|G"),
    (1036.0, "L|N"), (1036.0, "C|0"),
]
SWINGS = [(1010.5, A), (1012.5, A), (1014.5, A), (1017.6, A), (1019.6, A), (1024.2, B), (1028.2, B), (1030.2, B), (1034.5, B)]


def combat_log():
    lines = [f"{stamp(1000.0)}  COMBAT_LOG_VERSION,20,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,1.60.1,PROJECT_ID,2"]
    events = [(t, swing(t, dst, "Wolf" if dst == A else "Boar", (0.0, 0.0), 0.0)) for t, dst in SWINGS]
    events += [(1014.8, mob_swing(1014.8, A, "Wolf", (12.0, 0.0)))]   # Wolf 12 yd away when the light turns red
    events += [(1020.0, cl(1020.0, "UNIT_DIED", "0000000000000000", "nil", A, "Wolf", "0"))]
    events += [(t, cast(t, sid, name)) for t, sid, name in
               [(1010.5, 6673, "Battle Shout"), (1012.0, 78, "Heroic Strike"), (1018.0, 78, "Heroic Strike"),
                (1025.0, 78, "Heroic Strike")]]
    events += [(1024.5, cl(1024.5, "SWING_DAMAGE", W, "Warrior-Realm", B, "Boar", *SWING_SUFFIX))]  # no advanced block
    # the same hit again, as the Forever client writes it (advanced fields = the target): not a second swing
    events += [(1024.5, cl(1024.5, "SWING_DAMAGE_LANDED", W, "Warrior-Realm", B, "Boar", *(adv(B, 1.0, 0.0, 3.1) + SWING_SUFFIX)))]
    events += [(1029.0, cl(1029.0, "SPELL_DAMAGE", "Player-1-0000000P", "Priest-Realm", B, "Boar", "585", '"Smite"', "0x2",
                           *(adv("Player-1-0000000P", 0, 0, 0) + SWING_SUFFIX)))]
    events += [(1029.5, cl(1029.5, "SPELL_DAMAGE", "Player-1-0000000P", "Priest-Realm", "Creature-0-1-2-3-102-00000000C",
                           "Kobold", "585", '"Smite"', "0x2", *SWING_SUFFIX))]
    events.sort()
    return "\n".join(lines + [e for _, e in events]) + "\n"


def saved_variables(entries):
    def q(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    body = "".join(f"{q(s)}, -- [{i}]\n" for i, s in enumerate(entries, 1))
    return ('\nDuoBoxDB = {\n["journal"] = true,\n["partner"] = "Priest",\n}\n'
            f'DuoBoxJournal = {{\n["entries"] = {{\n{body}}},\n["version"] = 1,\n}}\n')


def journal_strings():
    return [f"{t:.3f}|{rest}" for t, rest in JOURNAL]


class SavedVariablesTest(unittest.TestCase):
    def test_reads_wow_saved_variables(self):
        text = saved_variables(['1.000|E|O|Can\'t do "that" \\ here', "2.000|C|1"])
        text += 'Other = {\n[1] = 2.5,\n["x"] = {\ntrue, -- [1]\nnil, -- [2]\n},\n["n"] = -3,\n}\n'
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "DuoBox.lua"
            p.write_text(text, encoding="utf-8")
            j = af.read_saved_variable(p)
            self.assertEqual(j["entries"], ['1.000|E|O|Can\'t do "that" \\ here', "2.000|C|1"])
            self.assertEqual(j["version"], 1)
            other = af.read_saved_variable(p, "Other")
            self.assertEqual(other, {1: 2.5, "x": [True, None], "n": -3})
            self.assertIsNone(af.read_saved_variable(p, "Missing"))


class CombatLogTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "WoWCombatLog.txt"
        self.path.write_text(combat_log(), encoding="utf-8")
        self.log = af.CombatLog()
        self.log.add_file(self.path, 2026)

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_swings_casts_deaths_positions_and_enemies(self):
        self.assertTrue(self.log.advanced)
        self.assertEqual(len(self.log.swings[W]), len(SWINGS) + 1)
        self.assertEqual([s for _, s in self.log.casts[W]], [6673, 78, 78, 78])
        self.assertEqual(len(self.log.deaths), 1)
        t, x, y, facing = self.log.positions[A][0]
        self.assertEqual((x, y), (12.0, 0.0))
        self.assertAlmostEqual(t, 1014.8 + LOCAL_OFF + SKEW, places=2)
        self.assertEqual({g for _, g in self.log.hostile}, {A, B, "Creature-0-1-2-3-102-00000000C"})

    def test_clock_offset_from_the_same_spells(self):
        sess = af.parse_journal(journal_strings())[0]
        jcasts = [(e.t, int(e.f[1])) for e in sess.by_code["Q"]]
        offset, n, spread = af.estimate_offset(jcasts, self.log.casts[W], sess.local_off)
        self.assertEqual(n, 4)
        self.assertAlmostEqual(offset, LOCAL_OFF + SKEW, delta=0.01)
        self.assertLess(spread, 0.01)
        # no clock edge: the casts alone still find it
        offset2, n2, _ = af.estimate_offset(jcasts, self.log.casts[W])
        self.assertAlmostEqual(offset2, offset, delta=0.01)

    def test_position_layouts(self):
        self.assertEqual(af._position(adv(W, 1.5, -2.25, 3.0)), (1.5, -2.25, 3.0))
        shifted = adv(W, 1.5, -2.25, 3.0)
        del shifted[7]  # one field less before the position (older layout)
        self.assertEqual(af._position(shifted), (1.5, -2.25, 3.0))
        self.assertIsNone(af._position(["Player-1", "0", "100", "100"]))


class FightTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        self.sv, self.cl = d / "DuoBox.lua", d / "WoWCombatLog.txt"
        self.sv.write_text(saved_variables(journal_strings()), encoding="utf-8")
        self.cl.write_text(combat_log(), encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def run_analysis(self, **kw):
        out = io.StringIO()
        fights = af.run([self.sv], [self.cl], out=out, **kw)
        return fights, out.getvalue()

    def test_full_fight(self):
        fights, text = self.run_analysis()
        self.assertEqual(len(fights), 1)
        f = fights[0]
        self.assertAlmostEqual(f["duration"], 26.0)
        self.assertEqual(f["enemies"], 3)
        self.assertAlmostEqual(f["red"]["R"], 5.5)
        self.assertAlmostEqual(f["red"]["T"], 4.0)
        self.assertAlmostEqual(f["red"]["F"], 1.0)
        self.assertAlmostEqual(f["red_total"], 10.5)
        # combat log uptime: union of [swing, swing + 1.25 x 2.0 s] clipped to the fight:
        # 1010.5-1017.0, 1017.6-1022.1, 1024.2-1027.0, 1028.2-1032.7, 1034.5-1036.0 = 19.8 s of 26 s
        self.assertEqual(f["uptime_source"], "combat log")
        self.assertAlmostEqual(f["uptime"], 19.8 / 26, delta=0.01)
        # the Wolf died at 1020.0, next swing on the Boar at 1024.2
        self.assertEqual(len(f["kill_gaps"]), 1)
        self.assertAlmostEqual(f["kill_gaps"][0]["seconds"], 4.2, delta=0.01)

        eps = {(e["reason"], e["tag"]): e for e in f["episodes"]}
        far = eps[("R", "")]
        self.assertAlmostEqual(far["reaction"], 1.0)
        self.assertAlmostEqual(far["fix"], 1.5)
        self.assertAlmostEqual(far["distance"], 12.0, delta=0.01)
        kill = eps[("T", "apres un kill")]
        self.assertAlmostEqual(kill["seconds"], 4.0)
        self.assertAlmostEqual(kill["reaction"], 1.0)
        self.assertIsNone(eps[("F", "")]["reaction"])
        self.assertAlmostEqual(eps[("R", "fuite")]["seconds"], 3.0)

        self.assertEqual([(p["outcome"], p["green"]) for p in f["pedal"]], [
            ("garde sa cible", True), ("cible un cadavre", False), ("trouve une cible vivante", True)])
        self.assertIn("TROP LOIN (fuite)", text)
        self.assertIn("PAS DE CIBLE (apres un kill)", text)
        self.assertIn("D-ChargeP x3", text)
        self.assertIn("TROP LOIN : distance au debut", text)

    def test_without_combat_log_uses_the_light(self):
        out = io.StringIO()
        fights = af.run([self.sv], [], out=out)
        f = fights[0]
        self.assertEqual(f["uptime_source"], "voyant")
        self.assertAlmostEqual(f["uptime"], (26 - 10.5 - 0) / 26, delta=0.01)
        self.assertEqual(f["kill_gaps"], [])

    def test_time_filters_and_compare(self):
        fights, _ = self.run_analysis(until=EPOCH + 5)
        self.assertEqual(fights, [])
        d = Path(self.tmp.name)
        _, _ = self.run_analysis(json_path=str(d / "a.json"))
        summary = json.loads((d / "a.json").read_text(encoding="utf-8"))
        self.assertEqual((summary["fights"], summary["hard"]), (1, 1))
        self.assertAlmostEqual(summary["indicators"]["red_total"][0], 10.5)
        summary["indicators"]["red_total"] = [5.25]
        (d / "b.json").write_text(json.dumps(summary), encoding="utf-8")
        out = io.StringIO()
        af.compare(d / "a.json", d / "b.json", out)
        self.assertIn("-50%", out.getvalue())
        self.assertIn("Moins de 10 combats", out.getvalue())

    def test_priest_journal_on_the_server_clock(self):
        warrior = journal_strings()
        warrior.insert(2, "1000.700|S|server|%d" % int(EPOCH + 101))
        self.sv.write_text(saved_variables(warrior), encoding="utf-8")
        # the priest's GetTime() is 500 s behind; same server clock
        priest = ["500.000|I|Priest|PRIEST|Player-1-0000000P|Warrior|1.60.1", "500.700|S|server|%d" % int(EPOCH + 101),
                  "515.500|K|B|Heal|LeftButton", "516.000|Q|S|2054|Heal", "520.000|K|B|Renew|LeftButton",
                  "540.000|K|B|Heal|LeftButton"]
        psv = Path(self.tmp.name) / "Priest.lua"
        psv.write_text(saved_variables(priest), encoding="utf-8")
        out = io.StringIO()
        f = af.run([self.sv, psv], [self.cl], out=out)[0]
        self.assertEqual(f["priest_presses"], 2)
        self.assertEqual(f["priest_casts"], 1)
        far = next(e for e in f["episodes"] if e["reason"] == "R" and not e["tag"])
        self.assertEqual(far["priest_presses"], 1)


class FacingTest(unittest.TestCase):
    def test_calibration_finds_the_axis_convention(self):
        log = af.CombatLog()
        log.swings[W] = []
        for i in range(12):
            t = 100.0 + i
            ang = i * 0.5
            dx, dy = 3 * math.cos(ang), 3 * math.sin(ang)
            facing = math.atan2(-dx, dy) % (2 * math.pi)   # a convention other than atan2(dy, dx)
            mob = f"Creature-{i}"
            log.swings[W].append((t, mob))
            log.positions.setdefault(W, []).append((t, 0.0, 0.0, facing))
            log.positions[mob] = [(t + 0.2, dx, dy, 0.0)]
        conv, err, n = af.calibrate_facing(log, W)
        self.assertEqual(n, 12)
        self.assertEqual(conv, (True, -1, 1))
        self.assertLess(err, 1e-6)


if __name__ == "__main__":
    unittest.main()
