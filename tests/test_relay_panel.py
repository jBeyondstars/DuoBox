"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1).

RelayPanel.lua: the panel of the warrior's spells and the code it draws in the top-left corner for
DuoRelay. DuoRelay.ps1 -SelfTest checks the reading side with the same test vector (icon 10).
"""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db = {relayPanel = true, relayPanelSpells = "402927,1240193,5308,6343,7384"}
printed, frames, textures, templates = {}, {}, {}, {}
physical = {1920, 1080}
mouseOver = nil
SPELLS = {[402927] = {"Victory Rush", 132342}, [1240193] = {"Slam", 132340}, [5308] = {"Execute", 135358},
          [6343] = {"Thunder Clap", 136105}, [7384] = {"Overpower", 132223}, [78] = {"Heroic Strike", 132282},
          [845] = {"Cleave", 132338}, [1715] = {"Hamstring", 132316}, [7386] = {"Sunder Armor", 132363},
          [772] = {"Rend", 132155}, [355] = {"Taunt", 136080}}
ns = {DEFAULTS = {relayPanelSpells = "402927,1240193,5308,6343,7384"}}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.Set(key, value) db[key] = value; if ns.RefreshRelayPanel then ns.RefreshRelayPanel() end end
function ns.SpellNameIcon(id) local s = SPELLS[id]; if s then return s[1], s[2] end end
function GetPhysicalScreenSize() return physical[1], physical[2] end

local Region = {}
Region.__index = Region
function New(parent) return setmetatable({parent = parent, shown = true, scripts = {}, events = {}}, Region) end
function Region:SetPoint(...) self.point = {...} end
function Region:ClearAllPoints() self.point = nil end
function Region:SetAllPoints() end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:Show() self.shown = true end
function Region:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.shown end
function Region:IsVisible()
    local f = self
    while f do if not f.shown then return false end; f = f.parent end
    return true
end
function Region:IsMouseOver() return mouseOver == self end
function Region:GetEffectiveScale() return 1 end
function Region:SetColorTexture(r, g, b, a) self.color = {r, g, b, a} end
function Region:SetTexture(t) self.texture = t end
function Region:SetText(t) self.text = t end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:RegisterEvent(e) self.events[e] = true end
function Region:CreateTexture() local t = New(self); table.insert(textures, t); return t end
function Region:CreateFontString() return New(self) end
for _, m in ipairs({"SetFrameStrata", "SetFrameLevel", "SetMovable", "SetClampedToScreen", "EnableMouse",
    "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetUserPlaced", "SetHighlightTexture",
    "SetPushedTexture", "SetTexCoord"}) do
    Region[m] = function() end
end
UIParent = New(nil)
function CreateFrame(kind, name, parent, template)
    local f = New(parent)
    f.kind = kind
    if template then table.insert(templates, template) end
    table.insert(frames, f)
    if name then _G[name] = f end
    return f
end
tip = {lines = {}}
GameTooltip = {
    SetOwner = function(_, owner) tip.owner = owner; tip.lines = {} end,
    SetSpellByID = function(_, id) tip.spell = id end,
    SetText = function(_, t) table.insert(tip.lines, t) end,
    AddLine = function(_, t) table.insert(tip.lines, t) end,
    Show = function() tip.shown = true end,
    Hide = function() tip.shown = false end,
}

function login() for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.scripts.OnEvent(f, "PLAYER_LOGIN") end end end
function panel() return DuoBoxRelayPanel end
function signal() return DuoBoxRelaySignal end
-- Icon buttons of the panel, in order
function icons()
    local list = {}
    for _, f in ipairs(frames) do if f.kind == "Button" and f.parent == DuoBoxRelayPanel then table.insert(list, f) end end
    return list
end
function shownIcons() local n = 0; for _, b in ipairs(icons()) do if b.shown then n = n + 1 end end; return n end
function enter(i) local b = icons()[i]; mouseOver = b; b.scripts.OnEnter(b) end
function leave(i) local b = icons()[i]; mouseOver = nil; b.scripts.OnLeave(b) end
function tick() if signal().shown and signal().scripts.OnUpdate then signal().scripts.OnUpdate(signal(), 0.01) end end
-- The squares of the code, in order
function squares()
    local list = {}
    for _, t in ipairs(textures) do if t.parent == DuoBoxRelaySignal then table.insert(list, t) end end
    return list
end
-- Icon i's code: the squares as "rgb" bits ("001 110 001 110"), their size and x offsets
function codeOf(i)
    enter(i)
    local bits, xs, size = {}, {}, nil
    for _, t in ipairs(squares()) do
        bits[#bits + 1] = ("%d%d%d"):format(t.color[1], t.color[2], t.color[3])
        xs[#xs + 1] = t.point[2]
        size = t.w
    end
    leave(i)
    return table.concat(bits, " "), size, table.concat(xs, ",")
end
function last() return printed[#printed] end
'''


class RelayPanelTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)

    def load(self, setup=""):
        self.lua.execute(setup)
        self.lua.execute((ROOT / "RelayPanel.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("login()")

    def run_lua(self, code):
        self.lua.execute(code)

    def code_of(self, i):
        return self.lua.eval(f"codeOf({i})")

    def test_option_off_hides_the_panel(self):
        self.load("db.relayPanel = false")
        self.run_lua('''
            assert(not panel().shown)
            ns.Set("relayPanel", true); assert(panel().shown and shownIcons() == 5, shownIcons())
            ns.Set("relayPanel", false); assert(not panel().shown)
        ''')

    def test_icons_follow_the_spell_list(self):
        self.load()
        self.run_lua('''
            assert(panel().shown and shownIcons() == 5)
            local b = icons()
            assert(b[1].icon.texture == 132342 and b[2].icon.texture == 132340 and b[5].icon.texture == 132223)
            assert(panel().w == 5 * 36 + 4 * 4, panel().w)
            ns.Set("relayPanelSpells", "1240193"); assert(shownIcons() == 1 and icons()[1].icon.texture == 132340)
            ns.Set("relayPanelSpells", ""); assert(not panel().shown) -- no spell: no panel
        ''')

    def test_no_secure_frame_a_click_does_nothing_in_this_game(self):
        self.load()
        self.run_lua('''
            assert(#templates == 0, templates[1])
            for _, b in ipairs(icons()) do assert(b.scripts.OnClick == nil and b.scripts.PreClick == nil) end
        ''')

    def test_hover_draws_the_code_and_leave_clears_it(self):
        self.load()
        self.run_lua('''
            local sig = signal()
            assert(not sig.shown)
            enter(3)
            assert(sig.shown and sig.point[1] == "TOPLEFT" and sig.parent == nil) -- screen corner, own scale
            assert(tip.spell == 5308 and tip.lines[1]:find('"pixel": 3', 1, true), tip.lines[1])
            leave(3)
            assert(not sig.shown and not tip.shown)
        ''')

    def test_code_matches_the_duorelay_scheme(self):
        self.load('db.relayPanelSpells = "78,845,1715,7386,772,355,402927,1240193,5308,6343"')
        # icon 1: A=1 (blue), 7-A=6 (yellow), B=1, 7-B=6
        self.assertEqual(self.code_of(1)[0], "001 110 001 110")
        # icon 3: B=3 (green+blue), 7-B=4 (red)
        self.assertEqual(self.code_of(3)[0], "001 110 011 100")
        # icon 10, the test vector of DuoRelay.ps1 -SelfTest: green, magenta, red, cyan
        code, size, xs = self.code_of(10)
        self.assertEqual(code, "010 101 100 011")
        # 8 physical pixels per square at 1080 lines (768 UI units), in a row from the corner
        self.assertAlmostEqual(size, 8 * 768 / 1080)
        self.assertEqual([round(float(x), 3) for x in xs.split(",")], [round(i * 8 * 768 / 1080, 3) for i in range(4)])

    def test_square_size_follows_the_screen_height(self):
        self.load("physical = {2560, 1440}")
        self.assertAlmostEqual(self.code_of(1)[1], 8 * 768 / 1440)
        self.lua.execute("GetPhysicalScreenSize = nil")
        self.assertAlmostEqual(self.code_of(1)[1], 8 * 768 / 1080)

    def test_code_never_stays_drawn(self):
        self.load()
        self.run_lua('''
            enter(2); mouseOver = nil; tick()              -- left without OnLeave
            assert(not signal().shown)
            enter(2); ns.Set("relayPanel", false)          -- panel hidden under the mouse
            assert(not signal().shown)
            ns.Set("relayPanel", true)
            enter(5); ns.Set("relayPanelSpells", "402927") -- its icon removed
            tick(); assert(not signal().shown)
            enter(1); tick(); assert(signal().shown)       -- still over it: stays
        ''')

    def test_command_sets_the_spells_by_name_or_id(self):
        self.load()
        self.run_lua('''
            ns.RelayPanelCommand("sorts Victory Rush, slam ,6343")
            assert(db.relayPanelSpells == "402927,1240193,6343", db.relayPanelSpells)
            assert(shownIcons() == 3)
            assert(last():find("1 Victory Rush, 2 Slam, 3 Thunder Clap", 1, true), last())

            ns.RelayPanelCommand("sorts Slam, Frostbolt, 99999999")
            assert(db.relayPanelSpells == "402927,1240193,6343")   -- unchanged
            assert(last():find("Frostbolt, 99999999", 1, true), last())

            ns.RelayPanelCommand("sorts 78,845,1715,7386,772,355,402927,1240193,5308,6343,7384")
            assert(db.relayPanelSpells == "402927,1240193,6343" and last():find("10 sorts au plus"), last())

            ns.RelayPanelCommand("defaut")
            assert(db.relayPanelSpells == "402927,1240193,5308,6343,7384")
            ns.RelayPanelCommand("sorts"); assert(last():find("5 Overpower", 1, true), last())
        ''')

    def test_command_switches_the_panel(self):
        self.load("db.relayPanel = false")
        self.run_lua('''
            ns.RelayPanelCommand(""); assert(db.relayPanel == true and panel().shown)
            ns.RelayPanelCommand("off"); assert(db.relayPanel == false and not panel().shown)
            ns.RelayPanelCommand("on"); assert(db.relayPanel == true)
            ns.RelayPanelCommand("nimporte"); assert(last():find("/duo panneau", 1, true))
        ''')


if __name__ == "__main__":
    unittest.main()
