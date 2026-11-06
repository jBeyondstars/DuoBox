#!/usr/bin/env python3
"""Analyse des combats du duo : journal DuoBox (/duo journal on) + WoWCombatLog du jeu.

Mesure, par combat, le temps mort du guerrier et ses causes, a partir de deux
sources independantes :
  * DuoBoxJournal (SavedVariables du guerrier, et du pretre si copie) : voyant
    vert / rouge et sa raison, cibles, touches (pedale, interaction), erreurs ;
  * WoWCombatLog*.txt ecrit par le client : chaque coup du guerrier, chaque
    mort, et en mode avance la position et l'orientation des unites.
Le combat log sert de juge externe : l'uptime en melee y est compte sans passer
par la logique de DuoBox.

Usage :
  python tools/analyze_fights.py                  # cherche sous _classic_beta_ (WTF + Logs)
  python tools/analyze_fights.py --journal <...SavedVariables/DuoBox.lua> --combatlog <WoWCombatLog.txt>
  python tools/analyze_fights.py --until "2026-11-07 18:00" --json avant.json
  python tools/analyze_fights.py --since "2026-11-07 18:00" --json apres.json
  python tools/analyze_fights.py --compare avant.json apres.json
Python 3.8+, bibliotheque standard uniquement.
"""
import argparse
import bisect
import csv
import json
import math
import re
import statistics
import sys
from datetime import datetime
from pathlib import Path

RED = {"R": "TROP LOIN", "F": "MAL ORIENTE", "A": "N'ATTAQUE PAS", "T": "PAS DE CIBLE"}
MELEE = {"WARRIOR", "ROGUE"}
NEXT_SWING = {"Heroic Strike", "Cleave"}            # replace a white swing in the log
# One white swing = SWING_DAMAGE or SWING_MISSED. The Forever client also writes SWING_DAMAGE_LANDED for the same hit
# (its advanced fields describe the target): counting it would count every hit twice.
SWING_EVENTS = {"SWING_DAMAGE", "SWING_MISSED"}
GUID_RE = re.compile(r"^(?:Player|Creature|Pet|Vehicle|GameObject|Corpse)-|^0{16}$")
FLEE_RE = re.compile(r"run away|flee|fuir|s'enfuit", re.I)
PEDAL_GAP = 0.6      # s between the action key and the interact key of one pedal press
FIX_WINDOW = 3.0     # s after a press for the light to turn green
POS_TOL = 2.5        # s: a position this old still counts


# --------------------------------------------------------------------------- SavedVariables

_TOKEN = re.compile(r'''(?P<ws>\s+|--[^\n]*)|"(?P<str>(?:\\.|[^"\\])*)"|(?P<num>-?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?)'''
                    r'''|(?P<name>[A-Za-z_]\w*)|(?P<p>[\[\]{}=,;])''', re.S)
_ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = s[i + 1:i + 2]
        m = re.match(r"\d{1,3}", s[i + 1:])
        if m:
            out.append(chr(int(m.group())))
            i += 1 + len(m.group())
        else:
            out.append(_ESC.get(nxt, nxt))
            i += 2
    return "".join(out)


def _tokens(text, pos):
    toks = []
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"caractere inattendu a la position {pos}: {text[pos:pos + 20]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        if kind == "str":
            toks.append(("str", _unescape(m.group("str"))))
        elif kind == "num":
            v = m.group("num")
            toks.append(("num", float(v) if any(c in v for c in ".eE") else int(v)))
        else:
            toks.append((kind, m.group(kind)))
    return toks


def _value(toks, i):
    kind, v = toks[i]
    if kind in ("str", "num"):
        return v, i + 1
    if kind == "name":
        return {"true": True, "false": False, "nil": None}.get(v, v), i + 1
    if v != "{":
        raise ValueError(f"valeur attendue, trouve {v!r}")
    i += 1
    arr, d = [], {}
    while not (toks[i][0] == "p" and toks[i][1] == "}"):
        if toks[i] == ("p", "["):
            key, i = _value(toks, i + 1)
            i += 2  # "]" "="
            d[key], i = _value(toks, i)
        elif toks[i][0] == "name" and toks[i + 1] == ("p", "="):
            key = toks[i][1]
            d[key], i = _value(toks, i + 2)
        else:
            item, i = _value(toks, i)
            arr.append(item)
        if toks[i][0] == "p" and toks[i][1] in ",;":
            i += 1
    if not d:
        return arr, i + 1
    for n, item in enumerate(arr, 1):
        d[n] = item
    return d, i + 1


def read_saved_variable(path, name="DuoBoxJournal"):
    """The value of a global in a WoW SavedVariables file, or None."""
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    m = re.search(rf"^{re.escape(name)}\s*=\s*", text, re.M)
    if not m:
        return None
    toks = _tokens(text, m.end())
    value, _ = _value(toks, 0)
    return value


# --------------------------------------------------------------------------- journal

class Entry:
    __slots__ = ("t", "code", "f")

    def __init__(self, t, code, f):
        self.t, self.code, self.f = t, code, f


class Session:
    def __init__(self, info):
        self.name, self.cls, self.guid, self.partner = (info + ["", "", "", ""])[:4]
        self.entries = []
        self.local_off = None   # epoch (PC clock) - GetTime()
        self.server_off = None  # epoch (server) - GetTime()
        self.by_code = {}

    def finish(self):
        for e in self.entries:
            self.by_code.setdefault(e.code, []).append(e)
            if e.code == "S" and len(e.f) >= 2 and e.f[1].lstrip("-").isdigit():
                off = int(e.f[1]) - e.t
                if e.f[0] == "local":
                    self.local_off = off
                elif e.f[0] == "server":
                    self.server_off = off
        self._times = {c: [e.t for e in es] for c, es in self.by_code.items()}

    def at(self, code, t):
        """The last entry of this code at or before t."""
        times = self._times.get(code)
        if not times:
            return None
        i = bisect.bisect_right(times, t)
        return self.by_code[code][i - 1] if i else None

    def between(self, code, t0, t1):
        times = self._times.get(code, [])
        return self.by_code.get(code, [])[bisect.bisect_left(times, t0):bisect.bisect_right(times, t1)]


def parse_journal(strings):
    sessions, cur, last_t = [], None, None
    for s in strings:
        parts = s.split("|")
        try:
            t = float(parts[0])
        except (ValueError, IndexError):
            continue
        code, f = (parts[1] if len(parts) > 1 else ""), parts[2:]
        if code == "I" or cur is None or (last_t is not None and t < last_t - 1):
            cur = Session(f if code == "I" else [])
            sessions.append(cur)
        cur.entries.append(Entry(t, code, f))
        last_t = t
    for s in sessions:
        s.finish()
    return sessions


def _flags(entry):
    return entry.f[2] if entry is not None and len(entry.f) > 2 else ""


def live_enemy(entry):
    return entry is not None and bool(entry.f) and entry.f[0] not in ("-", "") and "E" in _flags(entry) and "D" not in _flags(entry)


# --------------------------------------------------------------------------- combat log

_LINE = re.compile(r"^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\s+(\d{1,2}):(\d{2}):(\d{2})\.(\d{1,4})(?:[-+]\d+)?\s+(.*)$")


def _num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def _position(adv):
    """(x, y, facing) from the advanced fields, or None. The usual layout puts x at 12."""
    order = [12, 11, 13, 10, 14] + list(range(2, min(len(adv) - 3, 30)))
    for j in order:
        if j + 3 >= len(adv):
            continue
        x, y, mid, facing = _num(adv[j]), _num(adv[j + 1]), adv[j + 2], _num(adv[j + 3])
        if None in (x, y, facing) or not mid.isdigit() or int(mid) <= 0:
            continue
        if "." not in adv[j] or "." not in adv[j + 1] or not (-0.01 <= facing <= 6.30):
            continue
        if abs(x) > 50000 or abs(y) > 50000:
            continue
        return x, y, facing
    return None


class CombatLog:
    def __init__(self):
        self.swings = {}      # source guid -> [(t, dest guid)]
        self.casts = {}       # source guid -> [(t, spell id)]
        self.deaths = []      # [(t, guid)]
        self.positions = {}   # guid -> [(t, x, y, facing)]
        self.hostile = []     # [(t, creature guid)] in damage between a player and a creature
        self.advanced = None
        self.lines = 0

    def add_file(self, path, year):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                self._line(raw.rstrip("\n"), year)
        for lst in list(self.swings.values()) + list(self.casts.values()) + list(self.positions.values()):
            lst.sort()
        self.deaths.sort()
        self.hostile.sort()

    def _line(self, raw, year):
        m = _LINE.match(raw)
        if not m:
            return
        mo, da, yr, hh, mi, ss, frac, rest = m.groups()
        yr = int(yr) if yr else year
        if yr < 100:
            yr += 2000
        try:
            t = datetime(yr, int(mo), int(da), int(hh), int(mi), int(ss)).timestamp() + int(frac) / 10 ** len(frac)
        except ValueError:
            return
        if rest.startswith("COMBAT_LOG_VERSION"):
            f = rest.split(",")
            if "ADVANCED_LOG_ENABLED" in f:
                self.advanced = f[f.index("ADVANCED_LOG_ENABLED") + 1].strip() == "1"
            return
        if rest.startswith(("COMBATANT_INFO", "EMOTE", "ZONE_CHANGE", "MAP_CHANGE", "ENCOUNTER", "CHALLENGE")):
            return
        try:
            f = next(csv.reader([rest]))
        except (csv.Error, StopIteration):
            return
        if len(f) < 9:
            return
        self.lines += 1
        ev, src, dst = f[0], f[1], f[5]
        if ev == "UNIT_DIED":
            self.deaths.append((t, dst))
            return
        if ev.startswith("SWING"):
            prefix = 0
        elif ev.startswith(("SPELL", "RANGE")):
            prefix = 3
        elif ev.startswith("ENVIRONMENTAL"):
            prefix = 1
        else:
            return
        base = 9 + prefix
        if ev in SWING_EVENTS or (prefix == 3 and len(f) > 10 and f[10] in NEXT_SWING and ev in ("SPELL_DAMAGE", "SPELL_MISSED")):
            self.swings.setdefault(src, []).append((t, dst))
        if ev == "SPELL_CAST_SUCCESS" and len(f) > 9 and f[9].isdigit():
            self.casts.setdefault(src, []).append((t, int(f[9])))
        if ev.endswith(("_DAMAGE", "_MISSED")):
            if src.startswith("Player-") and dst.startswith("Creature-"):
                self.hostile.append((t, dst))
            elif src.startswith("Creature-") and dst.startswith("Player-"):
                self.hostile.append((t, src))
        if len(f) > base + 4 and GUID_RE.match(f[base]):
            pos = _position(f[base:])
            if pos:
                self.positions.setdefault(f[base], []).append((t,) + pos)

    def nearest(self, guid, t, tol=POS_TOL):
        lst = self.positions.get(guid)
        if not lst:
            return None
        i = bisect.bisect_left(lst, (t,))
        best = None
        for j in (i - 1, i):
            if 0 <= j < len(lst) and abs(lst[j][0] - t) <= tol and (best is None or abs(lst[j][0] - t) < abs(best[0] - t)):
                best = lst[j]
        return best


# --------------------------------------------------------------------------- clock join

def estimate_offset(journal_casts, log_casts, guess=None):
    """Seconds to add to a journal time to get the combat log time, from the same spells cast.

    journal_casts: [(GetTime, spell id)], log_casts: [(epoch, spell id)].
    Returns (offset, matches, spread) or (guess, 0, None)."""
    by_spell = {}
    for t, sid in log_casts:
        by_spell.setdefault(sid, []).append(t)
    diffs = []
    for tj, sid in journal_casts:
        for tc in by_spell.get(sid, ()):
            d = tc - tj
            if guess is None or abs(d - guess) < 5:
                diffs.append(d)
    if not diffs:
        return guess, 0, None
    diffs.sort()
    best, lo = (0, 0, 0), 0
    for hi in range(len(diffs)):
        while diffs[hi] - diffs[lo] > 0.25:
            lo += 1
        if hi - lo + 1 > best[0]:
            best = (hi - lo + 1, lo, hi)
    window = diffs[best[1]:best[2] + 1]
    return statistics.median(window), len(window), window[-1] - window[0]


# --------------------------------------------------------------------------- facing convention

def _wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


CONVENTIONS = [(swap, sa, sb) for swap in (False, True) for sa in (1, -1) for sb in (1, -1)]


def bearing(conv, dx, dy):
    swap, sa, sb = conv
    a, b = (dx, dy) if swap else (dy, dx)
    return math.atan2(sa * a, sb * b)


def calibrate_facing(log, warrior):
    """The axis convention that makes landed swings face their target, its median error, and the sample size."""
    pairs = []
    for t, dst in log.swings.get(warrior, ()):
        w, m = log.nearest(warrior, t, 0.05), log.nearest(dst, t, 1.0)
        if w and m and math.hypot(m[1] - w[1], m[2] - w[2]) > 0.3:
            pairs.append((w, m))
    if len(pairs) < 10:
        return None, None, len(pairs)
    best = None
    for conv in CONVENTIONS:
        err = statistics.median(abs(_wrap(bearing(conv, m[1] - w[1], m[2] - w[2]) - w[3])) for w, m in pairs)
        if best is None or err < best[1]:
            best = (conv, err)
    return best[0], best[1], len(pairs)


# --------------------------------------------------------------------------- fights

def _segments(sess, start, end):
    """[(t0, t1, light code)] inside the fight."""
    first = sess.at("L", start)
    pts = [(start, first.f[0] if first and first.f else "?")]
    pts += [(e.t, e.f[0] if e.f else "?") for e in sess.between("L", start + 1e-9, end)]
    out = []
    for i, (t, code) in enumerate(pts):
        t1 = pts[i + 1][0] if i + 1 < len(pts) else end
        if t1 > t:
            out.append((t, t1, code))
    return out


def _presses(sess, start, end):
    """Key presses: pedal (action key then interact key), interact, bar and DuoBox buttons."""
    ks = sess.between("K", start, end)
    out, used = [], set()
    for i, e in enumerate(ks):
        if i in used:
            continue
        kind = e.f[0] if e.f else ""
        if kind == "A":
            name = (e.f[3] if len(e.f) > 3 and e.f[3] else (e.f[1] if len(e.f) > 1 else "?"))
            j = next((j for j in range(i + 1, len(ks)) if ks[j].t - e.t <= PEDAL_GAP and ks[j].f and ks[j].f[0] == "I"), None)
            if j is not None:
                used.add(j)
                out.append((e.t, "pedale", name))
            else:
                out.append((e.t, "barre", name))
        elif kind == "I":
            out.append((e.t, "interaction", ""))
        elif kind == "B":
            out.append((e.t, "bouton", e.f[1] if len(e.f) > 1 else "?"))
    return out


def _outcome(before, after):
    if live_enemy(after):
        if live_enemy(before):
            return "garde sa cible" if before.f[0] == after.f[0] else "quitte une cible vivante pour une autre"
        return "trouve une cible vivante"
    if after is not None and after.f and after.f[0] not in ("-", "") and "D" in _flags(after):
        return "cible un cadavre"
    return "reste sans cible ennemie"


def _green_within(segs, t, window):
    return any(code == "G" and t0 <= t + window and t1 > t for t0, t1, code in segs)


def analyze_fight(sess, start, end, log=None, offset=None, warrior=None, conv=None, speed=None, priest=None):
    segs = _segments(sess, start, end)
    light = {}
    for t0, t1, code in segs:
        light[code] = light.get(code, 0) + t1 - t0

    # red episodes: consecutive non-green states
    episodes = []
    for t0, t1, code in segs:
        if code in RED:
            if episodes and abs(episodes[-1]["end"] - t0) < 1e-6:
                ep = episodes[-1]
                ep["end"] = t1
            else:
                ep = {"start": t0, "end": t1, "first": code, "by": {}}
                episodes.append(ep)
            ep["by"][code] = ep["by"].get(code, 0) + t1 - t0

    presses = _presses(sess, start, end)
    pedal = []
    fixes = [t for t, kind, _ in presses if kind in ("pedale", "interaction")]
    for t, kind, name in presses:
        if kind != "pedale":
            continue
        before, after = sess.at("T", t - 1e-3), sess.at("T", t + PEDAL_GAP)
        # green only counts for this press if it comes before the next one
        window = min([FIX_WINDOW] + [n - t for n in fixes if n > t])
        pedal.append({"t": t, "name": name, "outcome": _outcome(before, after), "green": _green_within(segs, t, window)})

    deaths_j = []
    if log is not None and offset is not None:
        deaths_j = [(t - offset, g) for t, g in log.deaths if start - 5 <= t - offset <= end + 1]

    for ep in episodes:
        ep["reason"] = max(ep["by"], key=ep["by"].get)
        ep["seconds"] = ep["end"] - ep["start"]
        press = next(((t, kind) for t, kind, _ in presses if ep["start"] - 0.05 <= t <= ep["end"] + 0.05
                      and kind in ("pedale", "interaction")), None)
        ep["reaction"] = press[0] - ep["start"] if press else None
        ep["fix"] = ep["end"] - press[0] if press else None
        ep["tag"] = ""
        tgt = sess.at("T", ep["start"] - 1e-3)
        if ep["reason"] == "T":
            corpse = any(p["outcome"] == "cible un cadavre" and ep["start"] - 0.7 <= p["t"] <= ep["start"] + 0.3 for p in pedal)
            died = tgt is not None and (
                any(e.f and e.f[0] == tgt.f[0] and "D" in _flags(e) for e in sess.between("T", ep["start"] - 2.5, ep["start"] + 0.3))
                or any(g == tgt.f[0] and ep["start"] - 2.5 <= t <= ep["start"] + 0.3 for t, g in deaths_j))
            partner = sess.at("P", ep["start"])
            if corpse:
                ep["tag"] = "pedale vers un cadavre"
            elif died:
                ep["tag"] = "apres un kill"
            elif not live_enemy(partner):
                ep["tag"] = "pretre sans cible vivante"
        elif ep["reason"] == "R":
            name = tgt.f[1] if tgt is not None and len(tgt.f) > 1 else None
            if name and any(len(e.f) > 1 and e.f[0] == name and FLEE_RE.search(e.f[1])
                            for e in sess.between("M", ep["start"] - 8, ep["start"] + 1)):
                ep["tag"] = "fuite"
        # positions from the combat log
        ep["distance"] = ep["angle"] = None
        if log is not None and offset is not None and warrior and tgt is not None and tgt.f[0] not in ("-", ""):
            w, m = log.nearest(warrior, ep["start"] + offset), log.nearest(tgt.f[0], ep["start"] + offset)
            if w and m:
                ep["distance"] = math.hypot(m[1] - w[1], m[2] - w[2])
                if conv is not None:
                    ep["angle"] = abs(math.degrees(_wrap(bearing(conv, m[1] - w[1], m[2] - w[2]) - w[3])))

    fight = {
        "start": start, "end": end, "duration": end - start,
        "epoch": start + sess.local_off if sess.local_off is not None else None,
        "light": light, "red": {c: light.get(c, 0) for c in RED}, "episodes": episodes,
        "presses": presses, "pedal": pedal,
        "enemies": max([int(e.f[0]) for e in sess.between("N", start, end) if e.f and e.f[0].isdigit()] or [0]),
        "uptime": None, "uptime_source": None, "kill_gaps": [], "priest_presses": None, "priest_casts": None,
    }
    fight["red_total"] = sum(fight["red"].values())
    seen = fight["light"].get("G", 0) + fight["red_total"]
    if seen > 0:
        fight["uptime"], fight["uptime_source"] = fight["light"].get("G", 0) / seen, "voyant"

    if log is not None and offset is not None and warrior:
        swings = [(t - offset, g) for t, g in log.swings.get(warrior, ()) if start - 0.5 <= t - offset <= end]
        hostile = {g for t, g in log.hostile if start <= t - offset <= end}
        fight["enemies"] = max(fight["enemies"], len(hostile))
        if speed:
            covered, edge = 0.0, start
            for t, _ in swings:
                a, b = max(t, edge), min(t + 1.25 * speed, end)
                if b > a:
                    covered += b - a
                    edge = b
            fight["uptime"], fight["uptime_source"] = covered / fight["duration"] if fight["duration"] > 0 else None, "combat log"
        for td, g in deaths_j:
            if not (start <= td <= end) or not any(sg == g and td - 15 <= st <= td for st, sg in swings):
                continue
            nxt = next((st for st, sg in swings if st > td and sg != g), None)
            fight["kill_gaps"].append({"seconds": (nxt if nxt is not None else end) - td, "censored": nxt is None})

    if priest is not None:
        psess, shift = priest  # priest GetTime = warrior GetTime - shift
        p0, p1 = start - shift, end - shift
        fight["priest_presses"] = len(psess.between("K", p0, p1))
        fight["priest_casts"] = len([e for e in psess.between("Q", p0, p1) if e.f and e.f[0] == "S"])
        for ep in episodes:
            ep["priest_presses"] = len(psess.between("K", ep["start"] - shift, ep["end"] - shift))
    return fight


def weapon_speed(log, warrior):
    times = [t for t, _ in log.swings.get(warrior, ())]
    gaps = [b - a for a, b in zip(times, times[1:]) if 1.0 <= b - a <= 4.5]
    return statistics.median(gaps) if len(gaps) >= 5 else (2.6 if times else None)


# --------------------------------------------------------------------------- report

def _q(values):
    v = sorted(x for x in values if x is not None)
    if not v:
        return None
    if len(v) == 1:
        return v[0], v[0], v[0]
    q = statistics.quantiles(v, n=4, method="inclusive")
    return q[0], statistics.median(v), q[2]


def _fmt_q(values, fmt="{:.1f}"):
    q = _q(values)
    return "-" if q is None else (fmt.format(q[1]) + " [" + fmt.format(q[0]) + "-" + fmt.format(q[2]) + "]")


def _pct(x):
    return "-" if x is None else f"{100 * x:.0f}%"


def _sec(x):
    return "-" if x is None else f"{x:.1f}s"


def _label(ep):
    return RED[ep["reason"]] + (f" ({ep['tag']})" if ep["tag"] else "")


def report(fights, meta, hard_min, out=sys.stdout):
    w = out.write
    w("Analyse des combats DuoBox\n==========================\n")
    for line in meta["notes"]:
        w(f"- {line}\n")
    hard = [f for f in fights if f["enemies"] >= hard_min]
    w(f"- {len(fights)} combats, dont {len(hard)} difficiles (>= {hard_min} ennemis)\n\n")
    if not fights:
        return

    w("Par combat\n----------\n")
    w(f"{'#':>3} {'debut':<16} {'duree':>6} {'enn.':>4} {'uptime':>7} {'rouge':>6} {'loin':>5} {'orient':>6} {'n att':>5} "
      f"{'s cib':>5} {'pedale':>6} {'kill->coup':>10}\n")
    for i, f in enumerate(fights, 1):
        when = datetime.fromtimestamp(f["epoch"]).strftime("%m-%d %H:%M:%S") if f["epoch"] else f"t={f['start']:.0f}"
        gaps = [g["seconds"] for g in f["kill_gaps"]]
        w(f"{i:>3} {when:<16} {f['duration']:>5.0f}s {f['enemies']:>4} {_pct(f['uptime']):>7} {f['red_total']:>5.1f}s "
          f"{f['red']['R']:>5.1f} {f['red']['F']:>6.1f} {f['red']['A']:>5.1f} {f['red']['T']:>5.1f} {len(f['pedal']):>6} "
          f"{_sec(statistics.median(gaps) if gaps else None):>10}\n")
    w("(uptime : " + ", ".join(sorted({f['uptime_source'] or '-' for f in fights})) + ")\n\n")

    scope = hard or fights
    w(f"Pareto des causes du rouge ({'combats difficiles' if hard else 'tous les combats'})\n" + "-" * 52 + "\n")
    causes = {}
    for f in scope:
        for ep in f["episodes"]:
            causes.setdefault(_label(ep), []).append(ep)
    total = sum(ep["seconds"] for eps in causes.values() for ep in eps) or 1
    w(f"{'cause':<44} {'sec':>7} {'%':>5} {'cumul':>6} {'n':>4} {'duree med':>9} {'reaction med':>12} {'sans appui':>10}\n")
    cum = 0
    for label, eps in sorted(causes.items(), key=lambda kv: -sum(e["seconds"] for e in kv[1])):
        sec = sum(e["seconds"] for e in eps)
        cum += sec
        react = [e["reaction"] for e in eps if e["reaction"] is not None]
        w(f"{label:<44} {sec:>7.1f} {100 * sec / total:>4.0f}% {100 * cum / total:>5.0f}% {len(eps):>4} "
          f"{statistics.median(e['seconds'] for e in eps):>8.1f}s "
          f"{_sec(statistics.median(react) if react else None):>12} "
          f"{100 * sum(e['reaction'] is None for e in eps) / len(eps):>9.0f}%\n")
    w("\n")

    pedals = [p for f in scope for p in f["pedal"]]
    if pedals:
        w(f"Effet de la pedale ({len(pedals)} appuis)\n" + "-" * 30 + "\n")
        outcomes = {}
        for p in pedals:
            outcomes.setdefault(p["outcome"], []).append(p)
        for name, ps in sorted(outcomes.items(), key=lambda kv: -len(kv[1])):
            w(f"{name:<44} {len(ps):>4} ({100 * len(ps) / len(pedals):.0f}%), vert en {FIX_WINDOW:.0f} s apres : "
              f"{100 * sum(p['green'] for p in ps) / len(ps):.0f}%\n")
        names = {}
        for p in pedals:
            names[p["name"]] = names.get(p["name"], 0) + 1
        w("macro(s) sur la pedale : " + ", ".join(f"{k} x{v}" for k, v in names.items()) + "\n\n")

    eps = [ep for f in scope for ep in f["episodes"]]
    dists = [ep["distance"] for ep in eps if ep["reason"] == "R" and ep["distance"] is not None]
    angles = [ep["angle"] for ep in eps if ep["reason"] == "F" and ep["angle"] is not None]
    if dists or angles:
        w("Positions (combat log avance)\n-----------------------------\n")
        if dists:
            w(f"TROP LOIN : distance au debut, mediane [Q1-Q3] {_fmt_q(dists)} m ; < 5 m (voyant douteux) : "
              f"{sum(d < 5 for d in dists)}/{len(dists)}\n")
        if angles:
            w(f"MAL ORIENTE : angle vers la cible, median [Q1-Q3] {_fmt_q(angles, '{:.0f}')} deg ; < 45 deg (douteux) : "
              f"{sum(a < 45 for a in angles)}/{len(angles)}\n")
        w("\n")

    w("Indicateurs (median [Q1-Q3] par combat)\n---------------------------------------\n")
    for key, label, values in _indicators(scope):
        w(f"{label:<40} {_fmt_q(values)}\n")


def _indicators(fights):
    def per_min(f, n):
        return n / (f["duration"] / 60) if f["duration"] > 0 else None
    return [
        ("uptime", "uptime melee (%)", [100 * f["uptime"] if f["uptime"] is not None else None for f in fights]),
        ("red_total", "rouge (s par combat)", [f["red_total"] for f in fights]),
        ("red_per_min", "rouge (s par minute)", [per_min(f, f["red_total"]) for f in fights]),
        ("pedal_per_min", "appuis pedale par minute", [per_min(f, len(f["pedal"])) for f in fights]),
        ("kill_gap", "kill -> coup suivant (s)", [statistics.median([g["seconds"] for g in f["kill_gaps"]]) if f["kill_gaps"] else None
                                                   for f in fights]),
        ("priest_presses_per_min", "appuis du pretre par minute",
         [per_min(f, f["priest_presses"]) if f["priest_presses"] is not None else None for f in fights]),
    ]


def summary(fights, hard_min):
    hard = [f for f in fights if f["enemies"] >= hard_min]
    return {"hard_min": hard_min, "fights": len(fights), "hard": len(hard),
            "indicators": {key: [v for v in values if v is not None] for key, _, values in _indicators(hard or fights)},
            "scope": "difficiles" if hard else "tous"}


def compare(a_path, b_path, out=sys.stdout):
    a, b = (json.loads(Path(p).read_text(encoding="utf-8")) for p in (a_path, b_path))
    w = out.write
    w(f"Avant : {a_path} ({a['hard']} combats {a['scope']})\nApres : {b_path} ({b['hard']} combats {b['scope']})\n\n")
    w(f"{'indicateur':<32} {'avant':>22} {'apres':>22} {'ecart med':>10}\n")
    for key, label, _ in _indicators([]):
        va, vb = a["indicators"].get(key, []), b["indicators"].get(key, [])
        qa, qb = _q(va), _q(vb)
        delta = "-" if not (qa and qb) or qa[1] == 0 else f"{100 * (qb[1] - qa[1]) / abs(qa[1]):+.0f}%"
        w(f"{label:<32} {_fmt_q(va):>22} {_fmt_q(vb):>22} {delta:>10}\n")
    if min(a["hard"], b["hard"]) < 10:
        w("\nMoins de 10 combats d'un cote : ecart a confirmer avec plus de combats.\n")


# --------------------------------------------------------------------------- main

def discover(root):
    journals = []
    for path in sorted(root.glob("WTF/Account/*/*/*/SavedVariables/DuoBox.lua")):
        try:
            if "DuoBoxJournal" in path.read_text(encoding="utf-8", errors="replace"):
                journals.append(path)
        except OSError:
            pass
    logs = sorted(root.glob("Logs/WoWCombatLog*.txt"), key=lambda p: p.stat().st_mtime)
    return journals, logs


def load_sessions(path):
    value = read_saved_variable(path)
    if not isinstance(value, dict):
        return []
    entries = value.get("entries") or []
    if isinstance(entries, dict):
        entries = [entries[k] for k in sorted(k for k in entries if isinstance(k, int))]
    return parse_journal([e for e in entries if isinstance(e, str)])


def parse_when(s):
    return datetime.strptime(s, "%Y-%m-%d %H:%M" if len(s) <= 16 else "%Y-%m-%d %H:%M:%S").timestamp()


def run(journal_paths, log_paths, since=None, until=None, hard_min=3, out=sys.stdout, json_path=None):
    melee, priests, notes = [], [], []
    for p in journal_paths:
        for s in load_sessions(p):
            (melee if s.cls in MELEE else priests).append(s)
        notes.append(f"journal : {p}")
    if not melee:
        out.write("Aucun journal de guerrier (ou voleur) : /duo journal on sur le guerrier, quelques combats, /reload.\n")
        return []
    years = [datetime.fromtimestamp(s.local_off + s.entries[0].t).year for s in melee if s.local_off is not None]
    log = None
    if log_paths:
        log = CombatLog()
        for p in log_paths:
            log.add_file(p, years[0] if years else datetime.now().year)
            notes.append(f"combat log : {p}")
        notes.append("combat log avance (positions) : " + {True: "oui", False: "NON (advancedCombatLogging = 0)", None: "inconnu"}[log.advanced])
    fights = []
    for s in melee:
        offset = conv = speed = None
        if log is not None and s.guid:
            jcasts = [(e.t, int(e.f[1])) for e in s.by_code.get("Q", []) if len(e.f) > 1 and e.f[0] == "S" and e.f[1].isdigit()]
            offset, n, spread = estimate_offset(jcasts, log.casts.get(s.guid, []), s.local_off)
            if n:
                notes.append(f"{s.name} : horloges alignees sur {n} sorts communs (dispersion {1000 * spread:.0f} ms)")
            elif offset is not None:
                notes.append(f"{s.name} : horloges alignees sur l'horloge du PC seulement (aucun sort commun)")
            else:
                notes.append(f"{s.name} : impossible d'aligner le journal et le combat log")
            if offset is not None:
                speed = weapon_speed(log, s.guid)
                conv, err, npairs = calibrate_facing(log, s.guid)
                if conv is not None:
                    ok = err < 0.5
                    notes.append(f"orientation calibree sur {npairs} coups portes : erreur mediane {math.degrees(err):.0f} deg"
                                 + ("" if ok else " (trop grande : angles ignores)"))
                    if not ok:
                        conv = None
        priest = None
        for ps in priests:
            if ps.server_off is not None and s.server_off is not None:
                shift = ps.server_off - s.server_off  # priest GetTime = warrior GetTime - shift
                if ps.entries[0].t - 5 <= s.entries[-1].t - shift and s.entries[0].t - shift <= ps.entries[-1].t + 5:
                    priest = (ps, shift)
                    break
        start = None
        for e in s.entries:
            if e.code == "C" and e.f and e.f[0] == "1":
                start = e.t
            elif e.code == "C" and e.f and e.f[0] == "0" and start is not None:
                f = analyze_fight(s, start, e.t, log, offset, s.guid, conv, speed, priest)
                start = None
                if f["duration"] < 2:
                    continue
                if since and (f["epoch"] is None or f["epoch"] < since):
                    continue
                if until and (f["epoch"] is None or f["epoch"] >= until):
                    continue
                fights.append(f)
    meta = {"notes": notes}
    report(fights, meta, hard_min, out)
    if json_path:
        Path(json_path).write_text(json.dumps(summary(fights, hard_min), indent=1), encoding="utf-8")
        out.write(f"\nresume ecrit dans {json_path} (pour --compare)\n")
    return fights


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wow", type=Path, default=Path(__file__).resolve().parents[4],
                    help="dossier _classic_beta_ (par defaut : celui de l'addon)")
    ap.add_argument("--journal", type=Path, action="append", help="SavedVariables/DuoBox.lua (plusieurs possibles)")
    ap.add_argument("--combatlog", type=Path, action="append", help="WoWCombatLog*.txt (plusieurs possibles)")
    ap.add_argument("--since", help='"AAAA-MM-JJ HH:MM" : combats a partir de cette heure')
    ap.add_argument("--until", help='"AAAA-MM-JJ HH:MM" : combats avant cette heure')
    ap.add_argument("--hard", type=int, default=3, help="ennemis minimum d'un combat difficile (3)")
    ap.add_argument("--json", help="ecrit un resume pour --compare")
    ap.add_argument("--compare", nargs=2, metavar=("AVANT", "APRES"), help="compare deux resumes --json")
    args = ap.parse_args(argv)
    if args.compare:
        compare(*args.compare)
        return 0
    journals, logs = discover(args.wow)
    journals = args.journal or journals
    logs = args.combatlog or logs
    run(journals, logs, parse_when(args.since) if args.since else None, parse_when(args.until) if args.until else None,
        args.hard, json_path=args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
