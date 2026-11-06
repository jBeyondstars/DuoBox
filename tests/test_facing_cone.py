"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, sent, prefixes, printed, tickers = {facingCone = false, coneHeight = 100}, {}, {}, {}, {}
clock, combat, partner, moveMode = 100, false, "party1", false
myFacing, zoom, sendResult = 0, 15, 0
cvars = {nameplateShowFriends = "1"}
positions = {player = {0, 0}, party1 = {5, 0}} -- UnitPosition order: y (north), x (west)
SECRET = {}
plates = {}   -- unit token -> nameplate frame
ns = {}
function ns.GetDB() return db end
function ns.PartnerUnit() return partner end
function ns.SendComm(msg, prefix) table.insert(sent, {msg = msg, prefix = prefix}); return sendResult end
function ns.FromPartner(body, sender) if sender == "Partner" then return body end end
function ns.Print(s) table.insert(printed, s) end
function ns.IsMoveMode() return moveMode end
function issecretvalue(v) return v == SECRET end
function GetTime() return clock end
function GetPlayerFacing() return myFacing end
function GetCameraZoom() return zoom end
function UnitPosition(u) local p = positions[u]; if p then return p[1], p[2], 0, 1 end end
function UnitIsUnit(a, b) return a == b end
function InCombatLockdown() return combat end
function IsInInstance() return false end
function date() return "12:00:00" end
C_CVar = {GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = v end}
C_NamePlate = {GetNamePlateForUnit = function(u) return plates[u] end}
C_ChatInfo = {RegisterAddonMessagePrefix = function(p) table.insert(prefixes, p) end}
C_Timer = {NewTicker = function(t, fn) table.insert(tickers, {every = t, fn = fn, at = clock + t}) end}

local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:RegisterEvent(name) self.events[name] = true end
function Methods:SetSize() end
function Methods:SetFrameStrata() end
function Methods:EnableMouse() end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:IsShown() return self.shown end
function Methods:ClearAllPoints() self.point = nil end
function Methods:SetPoint(p, rel, relP, x, y) self.point = {p, rel, relP, x, y} end
function Methods:GetHeight() return self.height or 0 end
local LineMethods = {}
function LineMethods:SetColorTexture() end
function LineMethods:SetThickness() end
function LineMethods:SetStartPoint(p, rel, x, y) self.from = {x, y} end
function LineMethods:SetEndPoint(p, rel, x, y) self.to = {x, y} end
function Methods:CreateLine()
    local l = setmetatable({}, {__index = LineMethods})
    table.insert(self.lines, l)
    return l
end
frames = {}
function CreateFrame(_, name)
    local f = setmetatable({scripts = {}, events = {}, lines = {}, shown = true}, {__index = Methods})
    table.insert(frames, f)
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame("Frame"); UIParent.height = 768

function event(name, ...) for _, f in ipairs(frames) do if f.scripts.OnEvent then f.scripts.OnEvent(f, name, ...) end end end
function wait(dt)
    local stop = clock + dt
    while true do
        local nextT
        for _, t in ipairs(tickers) do if not nextT or t.at < nextT.at then nextT = t end end
        if not nextT or nextT.at > stop + 1e-9 then break end
        clock = nextT.at
        nextT.at = nextT.at + nextT.every
        nextT.fn()
    end
    clock = stop
end
function fromPartner(msg, sender) event("CHAT_MSG_ADDON", "DUOBOXC", msg, "PARTY", sender or "Partner") end
function count(msg) local n = 0; for _, s in ipairs(sent) do if s.msg == msg then n = n + 1 end end; return n end
function lastMsg() return sent[#sent] and sent[#sent].msg end
function cone() return DuoBoxFacingCone end
function mid() local l = cone().lines[#cone().lines]; return l.to[1], l.to[2] end
function near(a, b) return math.abs(a - b) < 1e-6 end
'''


class FacingConeTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute((ROOT / "FacingCone.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    # Answering side (the warrior): no option needed

    def test_answers_a_request_with_its_facing_on_its_own_prefix(self):
        self.run_lua('''
            assert(prefixes[1] == "DUOBOXC")
            myFacing = 1.5708
            wait(1); assert(#sent == 0) -- nobody asks
            fromPartner("CQ"); wait(0.1)
            assert(lastMsg() == "CF:1571" and sent[1].prefix == "DUOBOXC", lastMsg())
            fromPartner("CQ", "Someone"); assert(#sent == 1)
        ''')

    def test_sends_on_a_3_degree_turn_and_every_2_s_unchanged(self):
        self.run_lua('''
            fromPartner("CQ"); wait(0.1); assert(#sent == 1)
            myFacing = math.rad(2); wait(1); assert(#sent == 1, lastMsg()) -- under 3 degrees
            myFacing = math.rad(4); wait(0.1); assert(#sent == 2 and lastMsg() == "CF:70", lastMsg())
            fromPartner("CQ"); wait(1.85); assert(#sent == 2) -- unchanged
            wait(0.3); assert(#sent == 3 and lastMsg() == "CF:70", lastMsg()) -- 2 s keepalive
            myFacing = 6.27; wait(0.3); assert(#sent == 4, lastMsg()) -- 4.8 degrees from 70 mrad, across north
        ''')

    def test_turn_across_north_is_small(self):
        self.run_lua('''
            myFacing = 6.27; fromPartner("CQ"); wait(0.1); assert(lastMsg() == "CF:6270")
            myFacing = 0.01; wait(0.5); assert(#sent == 1, lastMsg()) -- 1.3 degrees across 0
        ''')

    def test_stops_6_s_after_the_last_request_and_retries_a_throttled_send(self):
        self.run_lua('''
            fromPartner("CQ"); wait(6); local n = #sent
            myFacing = 1; wait(1); assert(#sent == n, lastMsg()) -- not asked any more
            sendResult = 3; fromPartner("CQ"); wait(0.1); assert(#sent == n + 1)
            wait(0.1); assert(#sent == n + 2) -- refused (throttled): sent again
            sendResult = 0; wait(0.1); assert(#sent == n + 3)
            wait(0.5); assert(#sent == n + 3)
        ''')

    # Showing side (the priest)

    def test_asks_every_2_s_only_with_the_option_and_the_partner_nameplate(self):
        self.run_lua('''
            plates.party1 = CreateFrame("Frame")
            wait(3); assert(count("CQ") == 0) -- option off
            db.facingCone = true; wait(0.05); assert(count("CQ") == 1 and sent[1].prefix == "DUOBOXC")
            wait(1.9); assert(count("CQ") == 1); wait(0.2); assert(count("CQ") == 2)
            plates.party1 = nil; wait(5); assert(count("CQ") == 2) -- no nameplate: no cone, no request
            assert(not cone():IsShown())
        ''')

    def test_cone_points_where_the_partner_faces_seen_from_behind_this_character(self):
        self.run_lua('''
            db.facingCone = true; plates.party1 = CreateFrame("Frame")
            fromPartner("CF:0"); wait(0.05)
            assert(cone():IsShown())
            local x, y = mid(); assert(near(x, 0) and y > 0, x .. " " .. y) -- same way as the camera: up
            fromPartner("CF:1571"); wait(0.05)
            x, y = mid(); assert(x < 0 and math.abs(y) < 0.1, x .. " " .. y) -- faces my left: left
            fromPartner("CF:3142"); wait(0.05)
            x, y = mid(); assert(math.abs(x) < 0.1 and y < 0, x .. " " .. y) -- faces the camera: down
            myFacing = 1.5708; positions.party1 = {0, 5}; fromPartner("CF:1571"); wait(0.05)
            x, y = mid(); assert(math.abs(x) < 0.1 and y > 0, x .. " " .. y) -- relative to my facing
            assert(#cone().lines == 9)
            local p = cone().point
            assert(p[1] == "CENTER" and p[2] == plates.party1 and p[3] == "BOTTOM" and p[5] < 0)
        ''')

    def test_feet_and_size_follow_the_depth_and_the_height_setting(self):
        self.run_lua('''
            db.facingCone = true; plates.party1 = CreateFrame("Frame"); fromPartner("CF:0"); wait(0.05)
            local feet, _ = cone().point[5]; local _, len = mid()
            -- depth = zoom 15 + 5 yards ahead = 20: 0.9 * 768 / 20 UI units per yard, 2.4 yards to the plate
            assert(near(feet, -2.4 * 0.9 * 768 / 20), feet)
            assert(near(len, 5 * 0.9 * 768 / 20 * 0.5), len)
            db.coneHeight = 200; wait(0.05); assert(near(cone().point[5], 2 * feet))
            db.coneHeight = 100; zoom = 35; wait(0.05); assert(near(cone().point[5], feet / 2))
            positions.party1 = nil; zoom = 20; wait(0.05); assert(near(cone().point[5], feet)) -- no position: zoom only
        ''')

    def test_hides_without_fresh_facing_option_or_with_a_secret_facing(self):
        self.run_lua('''
            db.facingCone = true; plates.party1 = CreateFrame("Frame")
            wait(0.05); assert(not cone():IsShown()) -- nothing received yet
            fromPartner("CF:100"); wait(0.05); assert(cone():IsShown())
            wait(5.1); assert(not cone():IsShown()) -- stale
            fromPartner("CF:100"); wait(0.05); assert(cone():IsShown())
            myFacing = SECRET; wait(0.05); assert(not cone():IsShown())
            myFacing = 0; wait(0.05); assert(cone():IsShown())
            moveMode = true; wait(0.05); assert(not cone():IsShown()); moveMode = false
            partner = nil; wait(0.05); assert(not cone():IsShown()); partner = "party1"
            db.facingCone = false; wait(0.05); assert(not cone():IsShown())
        ''')

    def test_finds_the_plate_through_its_nameplate_token(self):
        self.run_lua('''
            db.facingCone = true; fromPartner("CF:0")
            plates.nameplate4 = CreateFrame("Frame")
            local isUnit = UnitIsUnit
            UnitIsUnit = function(a, b) return a == "nameplate4" and b == "party1" end
            event("NAME_PLATE_UNIT_ADDED", "nameplate4")
            wait(0.05); assert(cone():IsShown() and cone().point[2] == plates.nameplate4)
            event("NAME_PLATE_UNIT_REMOVED", "nameplate4"); wait(0.05); assert(not cone():IsShown())
            UnitIsUnit = function() return SECRET end -- in instances: secret, skipped without error
            event("NAME_PLATE_UNIT_ADDED", "nameplate4"); wait(0.05); assert(not cone():IsShown())
        ''')

    def test_turning_the_option_on_shows_friendly_nameplates_out_of_combat_only(self):
        self.run_lua('''
            cvars.nameplateShowFriends = "0"; combat = true
            db.facingCone = true; ns.RefreshCone("facingCone")
            assert(cvars.nameplateShowFriends == "0" and printed[#printed]:find("Maj%+V"))
            combat = false; ns.RefreshCone("facingCone")
            assert(cvars.nameplateShowFriends == "1" and printed[#printed]:find("activees"))
            local n = #printed; ns.RefreshCone("facingCone"); assert(#printed == n) -- already on: quiet
        ''')

    def test_debug_prints_and_stores_its_lines(self):
        self.run_lua('''
            db.facingCone = true; plates.party1 = CreateFrame("Frame"); fromPartner("CF:0"); wait(0.05)
            ns.ConeCommand()
            assert(db.coneDebug[1]:find("cone : affiche"), db.coneDebug[1])
            assert(#printed == #db.coneDebug + 1)
            plates.party1 = nil; ns.ConeCommand()
            assert(db.coneDebug[1]:find("pas de barre de nom"), db.coneDebug[1])
        ''')

    def test_cone_shape(self):
        self.run_lua('''
            local arc, m = ns.ConeShape(0, 100, 0.5)
            assert(#arc == 7 and near(m[1], 0) and near(m[2], 50))
            assert(arc[1][1] > 0 and arc[7][1] < 0) -- right edge first, left edge last
            assert(near(arc[1][1], -arc[7][1]) and near(arc[1][2], arc[7][2]))
        ''')


if __name__ == "__main__":
    unittest.main()
