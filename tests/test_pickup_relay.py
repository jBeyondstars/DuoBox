"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
db, sent, said, prefixes, frames, timers = {pickupRelay = true}, {}, {}, {}, {}, {}
clock, combat, partner = 100, false, "party1"
SECRET = {}
cursor = nil          -- world cursor tooltip data (C_TooltipInfo.GetWorldCursor)
soft = nil            -- name of what the interact key would take ("softinteract")
focus = nil           -- frame under the mouse (nil = the 3D world)
ctrl, shift, alt = true, false, false
binding = nil         -- what CTRL-SHIFT-F9 does: "INTERACTTARGET", "CLICK DuoBoxPickupIdle" or nil
ns = {}
function ns.GetDB() return db end
function ns.PartnerUnit() return partner end
function ns.SendComm(msg, prefix) table.insert(sent, {msg = msg, prefix = prefix}); return 0 end
function ns.FromPartner(body, sender) if sender == "Partner" then return body end end
function issecretvalue(v) return v == SECRET end
function GetTime() return clock end
function UnitName(u)
    if u == "softinteract" then return soft end
    if u == "party1" then return "Brother" end
end
function InCombatLockdown() return combat end
function IsControlKeyDown() return ctrl end
function IsShiftKeyDown() return shift end
function IsAltKeyDown() return alt end
WorldFrame = {}
function GetMouseFoci() return {focus or WorldFrame} end
Enum = {TooltipDataType = {Object = 4, Unit = 2}}
C_TooltipInfo = {GetWorldCursor = function() return cursor end}
C_ChatInfo = {RegisterAddonMessagePrefix = function(p) table.insert(prefixes, p) end}
C_Timer = {After = function(t, fn) table.insert(timers, {at = clock + t, fn = fn}) end}
UIErrorsFrame = {AddMessage = function(_, text) table.insert(said, text) end}
function ClearOverrideBindings() binding = nil end
function SetOverrideBinding(_, prio, key, action) assert(prio and key == "CTRL-SHIFT-F9"); binding = action end
function SetOverrideBindingClick(_, prio, key, button) assert(prio and key == "CTRL-SHIFT-F9"); binding = "CLICK " .. button end

local Methods = {}
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:RegisterEvent(name) self.events[name] = true end
function CreateFrame(_, name)
    local f = setmetatable({scripts = {}, events = {}}, {__index = Methods})
    table.insert(frames, f)
    if name then _G[name] = f end
    return f
end

function event(name, ...) frames[1].scripts.OnEvent(frames[1], name, ...) end
function wait(dt)
    clock = clock + dt
    local due = {}
    for i = #timers, 1, -1 do if timers[i].at <= clock then table.insert(due, 1, table.remove(timers, i)) end end
    for _, t in ipairs(due) do t.fn() end
end
function last() return sent[#sent] and sent[#sent].msg end
function heard() return said[#said] end
function fromPartner(msg, sender) event("CHAT_MSG_ADDON", "DUOBOXK", msg, "PARTY", sender or "Partner") end
function object(name) return {type = 4, lines = {{leftText = name}}} end
function click(button) event("GLOBAL_MOUSE_DOWN", button or "RightButton") end
'''


class PickupRelayTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)

    def load(self, setup=""):
        self.lua.execute(setup)
        self.lua.execute((ROOT / "PickupRelay.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    def test_ctrl_right_click_on_an_object_sends_its_name_on_its_own_prefix(self):
        self.load()
        self.run_lua('''
            assert(prefixes[1] == "DUOBOXK")
            cursor = object("Copper Vein"); click()
            assert(last() == "PK:Copper Vein" and sent[1].prefix == "DUOBOXK", last())
        ''')

    def test_other_clicks_send_nothing(self):
        self.load()
        self.run_lua('''
            cursor = object("Copper Vein")
            click("LeftButton")
            shift = true; click(); shift = false            -- Ctrl+Shift
            alt = true; click(); alt = false                -- Ctrl+Alt
            ctrl = false; click(); ctrl = true              -- no Ctrl
            focus = {}; click(); focus = nil                -- over a frame of the interface
            cursor = {type = 2, lines = {{leftText = "Kobold"}}}; click() -- a unit, not an object
            cursor = nil; click()                           -- the ground
            cursor = object(SECRET); click()                -- hidden name
            cursor = object("Copper Vein"); partner = nil; click(); partner = "party1"
            db.pickupRelay = false; click()
            assert(#sent == 0, last())
        ''')

    def test_clicking_side_says_what_the_partner_does(self):
        self.load()
        self.run_lua('''
            cursor = object("Copper Vein"); click()
            fromPartner("PA:1:Copper Vein"); assert(heard() == "Brother ramasse : Copper Vein", heard())
            wait(2.5); assert(#said == 1) -- answered: no "does not answer"

            click(); fromPartner("PA:0:Peacebloom")
            assert(heard() == "Brother : pas de Copper Vein a portee (il vise : Peacebloom)", heard())
            fromPartner("PA:1:Copper Vein"); assert(heard() == "Brother ramasse : Copper Vein") -- in range later

            click(); fromPartner("PA:0:"); assert(heard() == "Brother : pas de Copper Vein a portee", heard())
            click(); fromPartner("PA:C:"); assert(heard() == "Brother est en combat : pas de ramassage", heard())
            fromPartner("PA:1:Copper Vein", "Someone"); assert(heard() == "Brother est en combat : pas de ramassage")
        ''')

    def test_no_answer_and_late_answer(self):
        self.load()
        self.run_lua('''
            cursor = object("Copper Vein"); click()
            wait(2); assert(heard() == "Brother ne repond pas (option Ramassage relaye active sur les deux persos ?)", heard())
            local n = #said
            wait(3); fromPartner("PA:1:Copper Vein"); assert(#said == n) -- 5 s later: not this click's answer any more
        ''')

    def test_key_picks_up_only_the_requested_kind_of_object(self):
        self.load()
        self.run_lua('''
            assert(binding == "CLICK DuoBoxPickupIdle", binding) -- does nothing, never the bare F9
            soft = "Copper Vein"; fromPartner("PK:Copper Vein")
            assert(binding == "INTERACTTARGET" and last() == "PA:1:Copper Vein" and sent[1].prefix == "DUOBOXK", last())
            event("PLAYER_SOFT_INTERACT_CHANGED"); assert(#sent == 1) -- one answer per request
            wait(3.2); assert(binding == "CLICK DuoBoxPickupIdle", binding) -- window over
        ''')

    def test_other_object_then_the_right_one_in_range(self):
        self.load()
        self.run_lua('''
            soft = "Peacebloom"; fromPartner("PK:Copper Vein")
            assert(binding == "CLICK DuoBoxPickupIdle" and last() == "PA:0:Peacebloom", last())
            soft = "Copper Vein"; wait(1); event("PLAYER_SOFT_INTERACT_CHANGED")
            assert(binding == "INTERACTTARGET" and last() == "PA:1:Copper Vein", last())
            soft = "Tin Vein"; event("PLAYER_SOFT_INTERACT_CHANGED"); assert(binding == "CLICK DuoBoxPickupIdle")
            soft = SECRET; fromPartner("PK:Copper Vein"); assert(binding == "CLICK DuoBoxPickupIdle" and last() == "PA:0:", last())
        ''')

    def test_combat_refuses_and_the_fight_start_clears_the_key(self):
        self.load()
        self.run_lua('''
            soft = "Copper Vein"; fromPartner("PK:Copper Vein"); assert(binding == "INTERACTTARGET")
            event("PLAYER_REGEN_DISABLED"); assert(binding == "CLICK DuoBoxPickupIdle", binding) -- before the lockdown
            combat = true
            fromPartner("PK:Copper Vein"); assert(last() == "PA:C:" and binding == "CLICK DuoBoxPickupIdle", last())
            combat = false; event("PLAYER_REGEN_ENABLED"); assert(binding == "CLICK DuoBoxPickupIdle")
        ''')

    def test_option_off_leaves_the_key_alone(self):
        self.load('db.pickupRelay = false')
        self.run_lua('''
            assert(binding == nil)
            soft = "Copper Vein"; fromPartner("PK:Copper Vein"); assert(#sent == 0 and binding == nil)
            db.pickupRelay = true; ns.RefreshPickupRelay(); assert(binding == "CLICK DuoBoxPickupIdle")
            db.pickupRelay = false; ns.RefreshPickupRelay(); assert(binding == nil) -- switched off: the player's own binding
            fromPartner("PK:Copper Vein", "Someone"); assert(#sent == 0)
        ''')


if __name__ == "__main__":
    unittest.main()
