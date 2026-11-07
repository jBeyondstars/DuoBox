"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1).

RelayPanel.lua: the panel of the warrior's spells and the code it draws in the top-left corner for
DuoRelay. DuoRelay.ps1 -SelfTest checks the reading side with the same test vector (icon 10).
CooldownTest runs two clients (priest and warrior, clocks 5000 s apart) joined by a message bus with a
delay, for the estimated cooldowns.
"""
from pathlib import Path
import re
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db = {relayPanel = true, relayPanelSpells = "402927,1240193,5308,6343,7384"}
printed, frames, textures, templates = {}, {}, {}, {}
physical = {1920, 1080}
mouseOver = nil
uiScale = 1           -- effective scale of UIParent's children
clock, timers = 100, {}
function GetTime() return clock end
C_Timer = {After = function(t, fn) table.insert(timers, {at = clock + t, fn = fn}) end}
function wait(dt)
    clock = clock + dt
    for i = #timers, 1, -1 do if timers[i].at <= clock then table.remove(timers, i).fn() end end
    if DuoBoxRelaySignal.shown and DuoBoxRelaySignal.scripts.OnUpdate then DuoBoxRelaySignal.scripts.OnUpdate(DuoBoxRelaySignal, dt) end
end
SPELLS = {[402927] = {"Victory Rush", 132342}, [1240193] = {"Slam", 132340}, [5308] = {"Execute", 135358},
          [6343] = {"Thunder Clap", 136105}, [7384] = {"Overpower", 132223}, [78] = {"Heroic Strike", 132282},
          [845] = {"Cleave", 132338}, [1715] = {"Hamstring", 132316}, [7386] = {"Sunder Armor", 132363},
          [772] = {"Rend", 132155}, [355] = {"Taunt", 136080}, [1161] = {"Challenging Shout", 132091}}
ns = {DEFAULTS = {relayPanelSpells = "402927,1240193,5308,6343,7384"}}
function ns.GetDB() return db end
function ns.Print(msg) table.insert(printed, msg) end
function ns.Set(key, value) db[key] = value; if ns.RefreshRelayPanel then ns.RefreshRelayPanel() end end
function ns.SpellNameIcon(id) local s = SPELLS[id]; if s then return s[1], s[2] end end
function GetPhysicalScreenSize() return physical[1], physical[2] end
sent, partner = {}, "party1"
function ns.SendComm(msg, prefix) table.insert(sent, {msg = msg, prefix = prefix}); return 0 end
function ns.FromPartner(body, sender) if sender == "Partner" then return body end end
function ns.PartnerUnit() return partner end
C_ChatInfo = {RegisterAddonMessagePrefix = function() end}
SECRET = {}
function issecretvalue(v) return v == SECRET end
restricted = false    -- combat addon restriction: cooldowns hidden
cooldowns = {}        -- spell -> {startTime, duration} as the game shows it
C_Spell = {GetSpellCooldown = function(spell)
    if restricted then return {startTime = SECRET, duration = SECRET} end
    return cooldowns[spell] or {startTime = 0, duration = 0}
end}
BASE = {[7384] = {5000, 1500}, [6343] = {4000, 1500}, [1240193] = {0, 1500}, [78] = {0, 0}, [845] = {0, 0},
        [402927] = {0, 1500}, [5308] = {0, 1500}, [1715] = {0, 1500}}
function GetSpellBaseCooldown(id) local b = BASE[id]; if b then return b[1], b[2] end end
function fromPartner(msg) for _, f in ipairs(frames) do
    if f.events.CHAT_MSG_ADDON then f.scripts.OnEvent(f, "CHAT_MSG_ADDON", "DUOBOXR", msg, "PARTY", "Partner") end
end end
function cast(event, spellID, guid, unit)
    for _, f in ipairs(frames) do
        if f.events[event] then f.scripts.OnEvent(f, event, unit or "player", guid or ("Cast-" .. tostring(spellID)), spellID) end
    end
end
-- Cooldown shown on icon i: "start/duration" or "none"
function cdOf(i)
    local c = icons()[i].cd
    if not c.cdStart or c.cdDur == 0 then return "none" end
    return ("%.3f/%.3f"):format(c.cdStart, c.cdDur)
end
-- Party units: power type (0 mana, 1 rage), power and its maximum
units = {party1 = {exists = true, ptype = 1, power = 45, max = 100}}
function UnitExists(u) return units[u] ~= nil and units[u].exists end
function UnitPowerType(u) return units[u] and units[u].ptype end
function UnitPower(u) return units[u] and units[u].power end
function UnitPowerMax(u) return units[u] and units[u].max end
function powerBar() for _, f in ipairs(frames) do if f.kind == "StatusBar" then return f end end end
function unitEvent(event, unit) for _, f in ipairs(frames) do
    if f.events[event] then f.scripts.OnEvent(f, event, unit) end
end end

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
function Region:GetEffectiveScale() return uiScale end
function Region:GetLeft() return 0 end
function Region:GetTop() return 768 / uiScale end
function Region:GetHeight() return self.h end
function Region:SetColorTexture(r, g, b, a) self.color = {r, g, b, a} end
function Region:SetTexture(t) self.texture = t end
function Region:SetText(t) self.text = t end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:RegisterEvent(e) self.events[e] = true end
function Region:RegisterUnitEvent(e, unit) self.events[e] = unit end
function Region:SetCooldown(start, dur) self.cdStart, self.cdDur = start, dur end
function Region:Clear() self.cdStart, self.cdDur = nil, nil end
function Region:SetHideCountdownNumbers(v) self.hideNumbers = v end
function Region:SetStatusBarTexture(t) self.barTexture = t end
function Region:SetStatusBarColor(r, g, b) self.barColor = ("%g,%g,%g"):format(r, g, b) end
function Region:SetMinMaxValues(a, b) self.minV, self.maxV = a, b end
function Region:SetValue(v) self.value = v end
-- the game formats hidden values itself; here they are only kept
function Region:SetFormattedText(fmt, v) self.text = issecretvalue(v) and v or fmt:format(v) end
function Region:CreateTexture() local t = New(self); table.insert(textures, t); return t end
function Region:CreateFontString() local t = New(self); table.insert(fontStrings, t); return t end
fontStrings = {}
function barText() for _, t in ipairs(fontStrings) do if t.parent == powerBar() then return t.text end end end
function Region:GetFrameLevel() return 1 end
function Region:SetBlendMode(m) self.blend = m end
function Region:SetVertexColor(r, g, b) self.vertex = ("%g,%g,%g"):format(r, g, b) end
function Region:CreateAnimationGroup() local g = New(self); g.playing = false; return g end
function Region:CreateAnimation() return New(self) end
function Region:SetLooping(l) self.looping = l end
function Region:Play() self.playing = true end
function Region:Stop() self.playing = false end
function Region:IsPlaying() return self.playing end
for _, m in ipairs({"SetFrameStrata", "SetFrameLevel", "SetMovable", "SetClampedToScreen", "EnableMouse",
    "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetUserPlaced", "SetHighlightTexture",
    "SetPushedTexture", "SetTexCoord", "SetFromAlpha", "SetToAlpha", "SetDuration"}) do
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

    def test_icons_per_row(self):
        self.load('db.relayPanelSpells = "402927,1240193,5308,6343,7384,78,845,1715"')
        self.run_lua('''
            -- no setting (old saved settings): one row
            assert(panel().w == 8 * 36 + 7 * 4 and panel().h == 14 + 36, panel().w .. "x" .. panel().h)
            ns.Set("relayPanelPerRow", 4)                       -- 2 rows of 4
            local b = icons()
            assert(panel().w == 4 * 36 + 3 * 4 and panel().h == 14 + 2 * 36 + 4, panel().w .. "x" .. panel().h)
            assert(b[4].point[2] == 3 * 40 and b[4].point[3] == -14, b[4].point[2] .. "," .. b[4].point[3])
            assert(b[5].point[2] == 0 and b[5].point[3] == -14 - 40, b[5].point[2] .. "," .. b[5].point[3])
            assert(b[8].point[2] == 3 * 40 and b[8].point[3] == -54)
            ns.Set("relayPanelPerRow", 3)                       -- 3 + 3 + 2
            assert(panel().w == 3 * 36 + 2 * 4 and panel().h == 14 + 3 * 36 + 2 * 4, panel().w .. "x" .. panel().h)
            assert(b[7].point[2] == 0 and b[7].point[3] == -14 - 80)
            ns.Set("relayPanelPerRow", 10); assert(panel().w == 8 * 36 + 7 * 4) -- fewer icons than the row: no gap
            ns.Set("relayPanelPerRow", 0); assert(panel().w == 36 and panel().h == 14 + 8 * 36 + 7 * 4) -- at least 1
        ''')

    def test_no_secure_frame_a_click_does_nothing_in_this_game(self):
        self.load()
        self.run_lua('''
            for _, t in ipairs(templates) do assert(t == "CooldownFrameTemplate", t) end -- the swipes only
            for _, b in ipairs(icons()) do assert(b.scripts.OnClick == nil and b.scripts.PreClick == nil) end
        ''')

    def test_hover_draws_the_code_and_leave_clears_it(self):
        self.load()
        self.run_lua('''
            local sig = signal()
            assert(not sig.shown)
            enter(3)
            assert(sig.shown and sig.parent == UIParent) -- UIParent's top-left corner = the window's
            assert(sig.point[1] == "TOPLEFT" and sig.point[2] == UIParent and sig.point[3] == "TOPLEFT")
            assert(tip.spell == 5308 and tip.lines[1]:find('"pixel": 3', 1, true), tip.lines[1])
            leave(3)
            assert(not sig.shown and not tip.shown)
        ''')

    def test_interact_entry_is_a_key_not_a_spell(self):
        self.load('db.relayPanelSpells = "7384,interact"')
        self.run_lua('''
            local b = icons()
            assert(shownIcons() == 2 and b[2].action == "interact" and b[2].spell == nil)
            assert(b[2].icon.texture == "Interface\\\\CURSOR\\\\Interact", b[2].icon.texture)
            enter(2)
            assert(signal().shown) -- its code is drawn like a spell's: DuoRelay presses T
            assert(tip.lines[1] == "Interagir" and tip.lines[3]:find('"pixel": 2', 1, true), tip.lines[3])
            leave(2)
            ns.OnPartnerProcs({{id = 7384, ready = true}})
            assert(b[1].glow.shown and not b[2].glow.shown) -- no blink, no cooldown for a key
            assert(cdOf(2) == "none")
            ns.RelayPanelCommand("sorts Slam, Interagir")
            assert(db.relayPanelSpells == "1240193,interact", db.relayPanelSpells)
            assert(last():find("1 Slam, 2 Interagir", 1, true), last())
        ''')

    def test_hidden_icons_keep_their_number(self):
        self.load('db.relayPanelSpells = "402927,1240193,5308,interact"')
        self.run_lua('''
            local b = icons()
            ns.SetRelayPanelHidden(1240193, true)                  -- Options > Automatisme, box 2 unticked
            assert(db.relayPanelHidden == "1240193", db.relayPanelHidden)
            assert(shownIcons() == 3 and not b[2].shown)
            assert(panel().w == 3 * 36 + 2 * 4, panel().w)        -- no hole
            assert(b[3].point[2] == 40 and b[4].point[2] == 80)   -- Execute takes Slam's place...
            enter(3)
            assert(tip.lines[1]:find('"pixel": 3', 1, true), tip.lines[1]) -- ...and stays icon 3 for DuoRelay
            leave(3)
            ns.SetRelayPanelHidden("interact", true)
            assert(db.relayPanelHidden == "1240193,interact", db.relayPanelHidden)
            local list = ns.RelayPanelEntries()
            assert(#list == 4 and list[4].name == "Interagir" and list[4].hidden and list[2].hidden and not list[1].hidden)
            assert(list[1].icon == 132342 and list[4].icon == "Interface\\\\CURSOR\\\\Interact")
            ns.RelayPanelCommand("sorts"); assert(last():find("2 Slam (masque), 3 Execute", 1, true), last())
            ns.SetRelayPanelHidden(1240193, false)
            assert(db.relayPanelHidden == "interact" and shownIcons() == 3 and b[2].shown and b[3].point[2] == 80)
            for _, id in ipairs({402927, 1240193, 5308}) do ns.SetRelayPanelHidden(id, true) end
            assert(not panel().shown)                              -- nothing left to show
            ns.Set("relayPanelSpells", "402927")                   -- entries gone from the list drop out
            ns.SetRelayPanelHidden(402927, false)
            assert(db.relayPanelHidden == "" and panel().shown and shownIcons() == 1)
        ''')

    def test_lit_spells_blink(self):
        self.load()
        self.run_lua('''
            local b = icons() -- 1 Victory Rush, 2 Slam, 3 Execute, 4 Thunder Clap, 5 Overpower
            assert(not b[5].glow.shown and not b[5].blink.playing)
            ns.OnPartnerProcs({{id = 7384, ready = true}, {id = 5308, ready = false}})
            assert(b[5].glow.shown and b[5].blink.playing and b[5].glow.vertex == "1,0.9,0.2") -- ready: yellow
            assert(b[3].glow.shown and b[3].glow.vertex == "0.3,0.55,1") -- short of rage: blue
            assert(not b[1].glow.shown and not b[2].glow.shown)
            ns.Set("relayPanelSpells", "7384,402927") -- list changed: the blink follows the spell
            assert(b[1].glow.shown and not b[2].glow.shown and not b[3].glow.shown)
            ns.OnPartnerProcs({{id = 402927, ready = true}})
            assert(b[2].blink.playing and not b[1].blink.playing and not b[1].glow.shown)
            ns.OnPartnerProcs({}) -- everything out
            assert(not b[2].glow.shown and not b[2].blink.playing)
        ''')

    def test_option_hides_the_spell_tooltips_but_keeps_the_code(self):
        self.load()
        self.run_lua('''
            db.relayPanelTooltip = false
            tip.spell, tip.shown = nil, false
            enter(2)
            assert(signal().shown) -- the click still works
            assert(not tip.shown and tip.spell == nil)
            leave(2)
            db.relayPanelTooltip = true
            enter(2); assert(tip.shown and tip.spell == 1240193)
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

    def test_square_size_follows_the_ui_scale(self):
        self.load("uiScale = 0.8")
        self.assertAlmostEqual(self.code_of(1)[1], 8 * 768 / 1080 / 0.8)

    def test_test_command_draws_a_code_without_the_mouse(self):
        self.load()
        self.run_lua('''
            ns.RelayPanelCommand("test")
            assert(signal().shown)
            wait(0.5)
            assert(last():find("test : code de l'icone 2 pendant 15 s, visible, coin a x=0 y=0 px, carres de 8 px", 1, true), last())
            assert(last():find("ecran de 1080 px", 1, true), last())
            local bits = {}
            for _, t in ipairs(squares()) do bits[#bits + 1] = ("%d%d%d"):format(t.color[1], t.color[2], t.color[3]) end
            assert(table.concat(bits, " ") == "001 110 010 101", table.concat(bits, " ")) -- icon 2
            wait(10); assert(signal().shown)          -- no mouse needed
            wait(5); assert(not signal().shown)       -- 15 s
            ns.RelayPanelCommand("test 7"); wait(0.5); assert(last():find("icone 7", 1, true), last())
            enter(1); leave(1); assert(not signal().shown) -- the mouse takes over and ends it
            ns.RelayPanelCommand("test 37"); assert(not signal().shown and last():find("1 a 36", 1, true), last())
        ''')

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

            ns.RelayPanelCommand("sorts 78,845,1715,7386,772,355,402927,1240193,5308,6343,7384,Challenging Shout,interact")
            assert(db.relayPanelSpells == "402927,1240193,6343" and last():find("12 sorts au plus"), last())
            ns.RelayPanelCommand("sorts 78,845,1715,7386,772,355,402927,1240193,5308,6343,7384,Challenging Shout")
            assert(shownIcons() == 12 and db.relayPanelSpells:find(",1161$"), db.relayPanelSpells)

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

    def test_rage_bar_in_place_of_the_title(self):
        self.load()
        self.run_lua('''
            local bar = powerBar()
            assert(bar.parent.parent == panel(), "the bar is the drag strip's")
            assert(bar.value == 45 and bar.minV == 0 and bar.maxV == 100, tostring(bar.value))
            assert(barText() == "45", barText())
            assert(bar.barColor == "1,0,0", bar.barColor) -- rage red
            units.party1.power = 70
            unitEvent("UNIT_POWER_FREQUENT", "target"); assert(bar.value == 45) -- another unit
            unitEvent("UNIT_POWER_FREQUENT", "party1"); assert(bar.value == 70 and barText() == "70")
        ''')

    def test_rage_hidden_values_are_handed_over(self):
        self.load()
        self.run_lua('''
            local bar = powerBar()
            units.party1.power, units.party1.max = SECRET, SECRET -- hidden in combat: never compared here
            unitEvent("UNIT_POWER_UPDATE", "party1")
            assert(bar.value == SECRET and bar.maxV == SECRET and barText() == SECRET)
            unitEvent("UNIT_POWER_UPDATE", SECRET) -- a hidden unit token: ignored, no error
        ''')

    def test_rage_bar_without_partner_and_for_a_hunter(self):
        self.load("partner = nil")
        self.run_lua('''
            local bar = powerBar()
            assert(bar.value == 0 and bar.maxV == 1 and barText() == "Guerrier")
            partner = "party1"; units.party1.ptype = 0 -- a hunter: mana, blue
            unitEvent("GROUP_ROSTER_UPDATE")
            assert(bar.value == 45 and bar.barColor == "0,0.55,1", bar.barColor)
        ''')



class Client:
    """One game client: its own Lua state and clock (clock_offset s ahead of the world time)."""

    def __init__(self, clock_offset, setup=""):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute(setup)
        self.lua.execute(f"clock = {100 + clock_offset}")
        self.lua.execute((ROOT / "RelayPanel.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("login()")

    def run(self, code):
        return self.lua.execute(code)

    def last(self):
        return self.lua.eval("last()")

    def outbox(self):
        msgs = [m.msg for m in self.lua.globals().sent.values() if m.prefix == "DUOBOXR"]
        self.lua.execute("sent = {}")
        return msgs


class CooldownTest(unittest.TestCase):
    LATENCY = 0.1  # s each way through the game server

    def setUp(self):
        # priest: panel shown; warrior: option off (the reporting side needs none), clock 5000 s ahead
        self.priest = Client(0)
        self.warrior = Client(5000, "db.relayPanel = false")
        self.t = 100.0
        self.queue = []  # (deliver at, client, message)

    def advance(self, seconds, step=0.01):
        end = self.t + seconds
        while self.t < end - 1e-9:
            self.t += step
            for c in (self.priest, self.warrior):
                c.run(f"wait({step})")
            for src, dst in ((self.priest, self.warrior), (self.warrior, self.priest)):
                for msg in src.outbox():
                    self.queue.append((self.t + self.LATENCY, dst, msg))
            due = [q for q in self.queue if q[0] <= self.t + 1e-9]
            self.queue = [q for q in self.queue if q[0] > self.t + 1e-9]
            for _, dst, msg in due:
                dst.run(f"fromPartner({msg!r})")

    def cd(self, i):
        """Start and duration of icon i's cooldown on the priest's screen, or None."""
        text = self.priest.lua.eval(f"cdOf({i})")
        return None if text == "none" else tuple(map(float, text.split("/")))

    def warrior_cast(self, spell, event="UNIT_SPELLCAST_SUCCEEDED", guid=None):
        g = f', "{guid}"' if guid else ""
        self.warrior.run(f'cast("{event}", {spell}{g})')

    def test_clock_sync_takes_the_shortest_round_trip(self):
        self.advance(4)
        self.priest.run("ns.RelayPanelCommand('cd')")
        line = self.priest.lua.eval("table.concat(printed, ' | ')")
        rtt, off = map(int, re.search(r"aller-retour (\d+) ms, decalage (-?\d+) ms", line).groups())
        self.assertTrue(200 <= rtt <= 220, line)  # 2 x 100 ms, plus the bus' 10 ms steps
        self.assertAlmostEqual(off, -5000000, delta=10)

    def test_cast_in_combat_starts_its_cooldown_and_the_global_one_on_the_priest_clock(self):
        self.advance(4)  # clocks synced
        self.warrior.run("restricted = true")  # in combat: the game hides cooldowns
        cast_at = self.t
        self.warrior_cast(7384)  # Overpower
        self.advance(0.5)
        start, dur = self.cd(5)  # icon 5 = Overpower: its own 5 s from the cast, latency removed
        self.assertAlmostEqual(start, cast_at, delta=0.02)
        self.assertEqual(dur, 5)
        start, dur = self.cd(2)  # icon 2 = Slam, on the global cooldown: 1.5 s
        self.assertAlmostEqual(start, cast_at, delta=0.02)
        self.assertEqual(dur, 1.5)
        self.priest.run('ns.Set("relayPanelSpells", "402927,1240193,5308,6343,7384,78")')
        self.assertIsNone(self.cd(6))  # Heroic Strike, off the global cooldown
        self.assertEqual(self.cd(5)[1], 5)  # kept after a list change
        self.priest.run("ns.RelayPanelCommand('cd')")
        self.assertRegex(self.priest.last(), r"Overpower il y a \d s \(recharge valeur du jeu\)")

    def test_the_later_end_wins(self):
        self.advance(4)
        self.warrior.run("restricted = true")
        first = self.t
        self.warrior_cast(7384)  # Overpower: 5 s
        self.advance(4)
        second = self.t
        self.warrior_cast(1715)  # Hamstring: global cooldown only, ends after Overpower's 5 s
        self.advance(0.3)
        self.assertGreater(second + 1.5, first + 5)
        start, dur = self.cd(5)
        self.assertAlmostEqual(start, second, delta=0.02)
        self.assertEqual(dur, 1.5)

    def test_exact_out_of_combat_then_measured_in_combat(self):
        self.advance(4)
        # out of combat the game shows Thunder Clap's real cooldown (6 s here, not the 4 s base value)
        self.warrior.run("cooldowns[6343] = {startTime = clock, duration = 6}")
        at = self.t
        self.warrior_cast(6343)
        self.advance(0.3)
        start, dur = self.cd(4)
        self.assertAlmostEqual(start, at, delta=0.02)
        self.assertEqual(dur, 6)
        self.priest.run("ns.RelayPanelCommand('cd')")
        self.assertIn("recharge exacte", self.priest.last())
        self.advance(7)
        self.warrior.run("restricted = true")
        self.warrior_cast(6343, guid="Cast-2")
        self.advance(0.3)
        self.assertEqual(self.cd(4)[1], 6)  # measured earlier, not the 4 s base value
        self.priest.run("ns.RelayPanelCommand('cd')")
        self.assertIn("recharge mesuree hors combat", self.priest.last())

    def test_cast_time_spell_starts_the_global_cooldown_at_its_start(self):
        self.advance(4)
        self.warrior.run("restricted = true")
        start_at = self.t
        self.warrior_cast(1240193, "UNIT_SPELLCAST_START", "Slam-1")  # Slam, cast time
        self.advance(1.5)
        self.warrior_cast(1240193, "UNIT_SPELLCAST_SUCCEEDED", "Slam-1")
        self.warrior.run("wait(0.01)")
        self.assertEqual(self.warrior.outbox(), [])  # no cooldown of its own, global one already sent
        start, dur = self.cd(2)
        self.assertAlmostEqual(start, start_at, delta=0.02)
        self.assertEqual(dur, 1.5)

    def test_fallbacks_tooltip_then_table(self):
        self.warrior.run("GetSpellBaseCooldown = nil; restricted = true")
        self.warrior.run("C_TooltipInfo = {GetSpellByID = function(id) if id == 7384 then return "
                         "{lines = {{leftText = 'Overpower'}, {leftText = '5 Rage', rightText = '7 sec cooldown'}}} end end}")
        self.advance(4)
        self.warrior_cast(7384)
        self.advance(0.3)
        self.assertEqual(self.cd(5)[1], 7)  # tooltip
        self.warrior_cast(6343)  # Thunder Clap: not in the tooltip mock -> DuoBox's table, 4 s
        self.advance(0.3)
        self.assertEqual(self.cd(4)[1], 4)
        self.priest.run("ns.RelayPanelCommand('cd')")
        self.assertIn("recharge table DuoBox", self.priest.last())

    def test_reports_only_while_asked(self):
        self.warrior_cast(7384)  # no ping received yet
        self.warrior.run("wait(0.01)")
        self.assertEqual(self.warrior.outbox(), [])
        self.advance(4)
        self.priest.run('ns.Set("relayPanel", false)')  # panel hidden: no more pings
        self.advance(31)
        self.warrior_cast(7384, guid="Cast-late")
        self.warrior.run("wait(0.01)")
        self.assertEqual(self.warrior.outbox(), [])

    def test_without_clock_sync_the_message_counts_as_instant(self):
        self.priest.run("partner = nil")  # the priest sends no ping...
        self.warrior.run('fromPartner("RT:1")')  # ...but asked earlier (before a /reload, say)
        self.warrior.outbox()
        sent_at = self.t
        self.warrior_cast(7384)
        self.advance(0.3)
        start, dur = self.cd(5)
        self.assertAlmostEqual(start, sent_at + self.LATENCY, delta=0.03)
        self.assertEqual(dur, 5)

    def test_another_units_secret_payload_is_ignored(self):
        self.advance(4)
        self.priest.run('cast("UNIT_SPELLCAST_SUCCEEDED", SECRET, SECRET, SECRET)')  # if one ever arrives
        self.priest.run("wait(0.01)")
        self.assertEqual(self.priest.outbox(), [])
        self.assertIsNone(self.cd(5))


if __name__ == "__main__":
    unittest.main()
