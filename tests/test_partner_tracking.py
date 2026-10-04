"""Run with python -m unittest discover -s tests (requires lupa with Lua 5.1)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
clock, online, grouped, combat, dead, inside, mouselook = 0, true, true, false, false, false, false
cursorX, cursorY, facing, rotate = 1000, 600, 0, "0"
frames, messages, printed, registrations = {}, {}, {}, {}
db = {tracking=false, partner="Partner"}
ns = {}
function ns.GetDB() return db end
function ns.PartnerUnit() if grouped then return "party1" end end
function ns.SendComm(msg) if grouped then table.insert(messages, msg) end end
function ns.Print(msg) table.insert(printed, msg) end
function ns.FromPartner(body, sender)
    if sender ~= "Partner" then return end
    local tag, content = body:match("^~(%x+)~(.*)$")
    if tag == "1234" then return end
    return content or body
end
function ns.Set(key, value) db[key] = value; ns.RefreshTracking() end
function GetTime() return clock end
function UnitIsConnected() return online end
function UnitGUID() return "partner-guid" end
function InCombatLockdown() return combat end
function UnitIsDeadOrGhost() return dead end
function IsInInstance() return inside end
function IsMouselooking() return mouselook end
function SpellIsTargeting() return false end
function GetCVar(key) return key == "rotateMinimap" and rotate or "0" end
function GetPlayerFacing() return facing end
function GetCursorPosition() return cursorX, cursorY end
function GetMouseFoci() return {focus} end
function wipe(t) for k in pairs(t) do t[k] = nil end end

local Frame = {}
Frame.__index = Frame
function Frame:SetSize(w,h) self.width,self.height=w,h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetZoom() return 0 end
function Frame:SetPoint(...) table.insert(self.points, {...}) end
function Frame:GetPoint(i) return unpack(self.points[i or 1]) end
function Frame:GetNumPoints() return #self.points end
function Frame:ClearAllPoints() self.points={} end
function Frame:GetCenter()
    local p=self.points[1]
    if p and p[1]=="CENTER" then return p[4],p[5] end
    return 1700,800
end
function Frame:GetChildren() return unpack(self.children) end
function Frame:SetAlpha(v)
    if self.failAlpha and v==0 then self.failAlpha=false; error("injected alpha failure") end
    self.alpha=v
end
function Frame:GetAlpha() return self.alpha end
function Frame:SetFrameStrata(v) self.strata=v end
function Frame:GetFrameStrata() return self.strata end
function Frame:SetFrameLevel(v) self.level=v end
function Frame:GetFrameLevel() return self.level end
function Frame:IsMouseClickEnabled() return self.click end
function Frame:IsMouseMotionEnabled() return self.motion end
function Frame:SetMouseClickEnabled(v) self.click=v end
function Frame:SetMouseMotionEnabled(v) self.motion=v end
function Frame:IsVisible() return self.shown end
function Frame:IsShown() return self.shown end
function Frame:Hide() self.shown=false end
function Frame:Show()
    self.shown=true
    for _,cb in ipairs(self.hooks.OnShow or {}) do cb(self) end
end
function Frame:SetScript(key, fn) self.scripts[key]=fn end
function Frame:HookScript(key, fn)
    self.hooks[key]=self.hooks[key] or {}; table.insert(self.hooks[key],fn)
end
function Frame:RegisterEvent(key) self.events[key]=true end
function Frame:GetEffectiveScale() return 1 end
function Frame:CreateTexture()
    return {SetAllPoints=function() end, SetTexture=function(self,v) self.asset=v end}
end
function Frame:SetOwner(v) self.owner=v end
function Frame:GetOwner() return self.owner end
function Frame:SetText(v) self.text=v end
function Frame:AddLine() end
function Frame:NumLines() return #tooltipLines end
function Frame:IsForbidden() return false end
function CreateFrame(_,_,parent)
    local f=setmetatable({points={},children={},alpha=1,strata="MEDIUM",level=1,
        click=true,motion=true,shown=true,scripts={},events={},hooks={},width=200,height=200},Frame)
    table.insert(frames,f)
    if parent then table.insert(parent.children,f) end
    return f
end
UIParent=CreateFrame("Frame")
Minimap=CreateFrame("Frame",nil,UIParent)
Minimap:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-25,-30)
Minimap:SetPoint("BOTTOMRIGHT",UIParent,"TOPRIGHT",-25,-230)
Minimap.alpha,Minimap.strata,Minimap.level,Minimap.click,Minimap.motion=0.7,"LOW",7,false,true
historic=CreateFrame("Frame",nil,Minimap)
historic.click,historic.motion=false,true
GameTooltip=CreateFrame("Frame")
GameTooltip.alpha=0.8
tooltipLines={}
function GameTooltip_Hide() GameTooltip:Hide() end
function tooltip(name,owner,mouseFocus)
    tooltipLines={name}
    GameTooltipTextLeft1={GetText=function() return name end}
    GameTooltip:SetOwner(owner or Minimap)
    focus=mouseFocus or Minimap
    GameTooltip:Show()
end

trackingInfo={spellID=2580,name="Find Minerals",texture=136025,active=true}
C_Minimap={GetNumTrackingTypes=function() return 1 end,
    GetTrackingInfo=function() return trackingInfo end}
function GetSpellInfo(id)
    if id==2580 then return "Find Minerals",nil,136025 end
    return "Find Herbs",nil,133939
end
hbd={GetPlayerWorldPosition=function() return 0,0,0 end,
    GetPlayerZonePosition=function() return 0.5,0.5,1429 end,
    GetWorldCoordinatesFromZone=function(_,x,y,map) return 25,-40,0 end}
pins={AddMinimapIconWorld=function(_,ref,frame,instance,x,y)
    registrations[frame]={instance,x,y}; frame:Show()
end, RemoveMinimapIcon=function(_,ref,frame) registrations[frame]=nil; frame:Hide() end}
function LibStub(name)
    if name=="HereBeDragons-2.0" then return hbd end
    if name=="HereBeDragons-Pins-2.0" then return pins end
end
nodes={{posX=0.5,posY=0.5,mapID=1429}}
GatherLite={IsLoaded=function() return true end,
    GetNearbyZoneNodes=function() return nodes end,
    GetObject=function(_,name)
        if name=="Copper Vein" or name=="Tin Vein" then return {type="ore"} end
        if name=="Peacebloom" then return {type="herb"} end
    end}
function tick(dt) clock=clock+dt; driver.scripts.OnUpdate(driver,dt) end
function event(key,...) driver.scripts.OnEvent(driver,key,...) end
function receive(body,sender,channel,prefix)
    event("CHAT_MSG_ADDON",prefix or "DUOBOX",body,channel or "PARTY",sender or "Partner")
end
function sentNodes()
    local count=0
    for _,msg in ipairs(messages) do if msg:match("^TN:") then count=count+1 end end
    return count
end
function countPins() local n=0; for _ in pairs(registrations) do n=n+1 end; return n end
'''


class PartnerTrackingTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute((ROOT / "PartnerTracking.lua").read_text(encoding="utf-8"), "DuoBox", self.lua.globals().ns)
        self.lua.execute("driver=frames[#frames]; event('PLAYER_LOGIN')")

    def run_lua(self, code):
        self.lua.execute(code)

    def assert_restored(self):
        self.run_lua('''
            assert(Minimap:GetNumPoints()==2)
            local p,r,rp,x,y=Minimap:GetPoint(1)
            assert(p=="TOPRIGHT" and r==UIParent and rp=="TOPRIGHT" and x==-25 and y==-30)
            assert(Minimap.alpha==0.7 and Minimap.strata=="LOW" and Minimap.level==7)
            assert(Minimap.click==false and Minimap.motion==true)
            assert(historic.click==false and historic.motion==true)
            assert(GameTooltip.alpha==0.8)
        ''')

    def test_default_disabled_does_not_scan_or_receive(self):
        self.run_lua('tick(10); receive("TN:0:25:-40:O:Copper Vein"); assert(countPins()==0 and sentNodes()==0)')
        self.assert_restored()

    def test_native_tooltip_confirms_live_node_and_restores_all_properties(self):
        self.run_lua('''
            ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(0.016)
            assert(Minimap.alpha==0 and not historic.motion)
            tooltip("Copper Vein"); tick(0.016)
            assert(sentNodes()==1)
            assert(messages[#messages]=="TN:0:25.00:-40.00:O:Copper Vein")
        ''')
        self.assert_restored()

    def test_historical_addon_pin_never_confirms_a_live_node(self):
        self.run_lua('''
            ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(0.016)
            tooltip("Copper Vein",historic,historic); tick(0.016)
            assert(sentNodes()==0)
        ''')
        self.assert_restored()

    def test_no_tooltip_and_wrong_kind_do_not_share(self):
        for tooltip_code in ('GameTooltip:Hide()', 'tooltip("Peacebloom")', 'tooltip("Auctioneer")'):
            with self.subTest(tooltip=tooltip_code):
                self.setUp()
                self.run_lua(f'ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(0.016); {tooltip_code}; tick(0.016); assert(sentNodes()==0)')
                self.assert_restored()

    def test_native_name_can_differ_from_database_spawn_type(self):
        self.run_lua('''
            ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(0.016)
            tooltip("Tin Vein"); tick(0.016)
            assert(messages[#messages]=="TN:0:25.00:-40.00:O:Tin Vein")
        ''')

    def test_receive_refresh_expiry_and_partner_stop(self):
        self.run_lua('''
            ns.TrackingCommand("on")
            receive("TN:0:25:-40:O:Copper Vein"); assert(countPins()==1)
            tick(10); receive("TN:0:25:-40:O:Copper Vein"); assert(countPins()==1)
            tick(10); assert(countPins()==1)
            tick(6); assert(countPins()==0)
            receive("TN:0:25:-40:H:Peacebloom"); assert(countPins()==1)
            receive("TR:0"); assert(countPins()==0)
        ''')

    def test_only_partner_party_messages_accepted_and_self_echo_ignored(self):
        self.run_lua('''
            ns.TrackingCommand("on")
            receive("TN:0:25:-40:O:Copper Vein","Stranger")
            receive("TN:0:25:-40:O:Copper Vein","Partner","WHISPER")
            receive("TN:0:25:-40:O:Copper Vein","Partner","PARTY","OTHER")
            receive("~1234~TN:0:25:-40:O:Copper Vein")
            assert(countPins()==0)
            receive("~abcd~TN:0:25:-40:O:Copper Vein"); assert(countPins()==1)
        ''')

    def test_malformed_and_other_instance_messages_are_ignored(self):
        self.run_lua('''
            ns.TrackingCommand("on")
            for _,body in ipairs({"TN:0:bad:-40:O:Copper Vein", "TN:0:1.2.3:-40:O:Copper Vein",
                "TN:0:10000000:-40:O:Copper Vein", "TN:1:25:-40:O:Copper Vein",
                "TN:0:25:-40:X:Unknown", "TN:0:25:-40:O:|Hbad|h", "TN:0:25:-40:O:"}) do receive(body) end
            assert(countPins()==0 and db.tracking==true)
        ''')

    def test_pin_limit(self):
        self.run_lua('''
            ns.TrackingCommand("on")
            for i=1,140 do receive("TN:0:"..i..":-40:O:Copper Vein") end
            assert(countPins()==128)
            receive("TR:0"); assert(countPins()==0)
        ''')

    def test_disabling_combat_disconnect_and_timeout_restore_minimap(self):
        for stop in ('ns.TrackingCommand("off")', 'combat=true; event("PLAYER_REGEN_DISABLED")',
                     'online=false; event("UNIT_CONNECTION")', 'tick(2)', 'event("PLAYER_LEAVING_WORLD")'):
            with self.subTest(stop=stop):
                self.setUp()
                self.run_lua(f'ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(0.016); {stop}')
                self.assert_restored()

    def test_error_restores_minimap_and_disables_feature(self):
        self.run_lua('''
            ns.TrackingCommand("on"); Minimap.failAlpha=true; ns.TrackingCommand("scan")
            assert(db.tracking==false and ns.TrackingState():find("injected alpha failure"))
        ''')
        self.assert_restored()

    def test_without_active_tracker_or_catalog_never_manipulates_minimap(self):
        for unavailable in ('trackingInfo.active=false', 'GatherLite=nil', 'mouselook=true', 'inside=true', 'combat=true'):
            with self.subTest(unavailable=unavailable):
                self.setUp()
                self.run_lua(f'{unavailable}; ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(1)')
                self.assert_restored()

    def test_receive_without_gatherlite_or_a_local_profession(self):
        self.run_lua('''
            GatherLite=nil; trackingInfo.active=false; ns.TrackingCommand("on")
            receive("TN:0:25:-40:O:Copper Vein"); assert(countPins()==1)
            assert(ns.TrackingState():find("Reception uniquement"))
        ''')

    def test_legacy_tracking_api_and_rotated_minimap(self):
        self.run_lua('''
            C_Minimap=nil
            GetNumTrackingTypes=function() return 1 end
            GetTrackingInfo=function() return "Find Minerals",136025,1 end
            rotate="1"; facing=math.pi/2
            ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(0.016)
            tooltip("Copper Vein"); tick(0.016); assert(sentNodes()==1)
        ''')
        self.assert_restored()

    def test_cursor_movement_does_not_attribute_a_stale_tooltip(self):
        self.run_lua('''
            ns.TrackingCommand("on"); ns.TrackingCommand("scan"); tick(0.016)
            tooltip("Copper Vein"); cursorX=cursorX+50; tick(0.016); assert(sentNodes()==0)
        ''')
        self.assert_restored()

    def test_low_fps_passes_resume_after_the_last_sample_checked(self):
        self.run_lua('''
            hbd.GetWorldCoordinatesFromZone=function(_,x,y,map) return 10,-x,0 end
            nodes={}
            for i=1,32 do nodes[i]={posX=i*2,posY=0.5,mapID=1429} end
            ns.TrackingCommand("on")
            for pass=1,2 do
                ns.TrackingCommand("scan")
                tick(0.25)
                for frame=1,6 do tooltip("Copper Vein"); tick(0.25) end
            end
            local unique={}
            for _,body in ipairs(messages) do if body:match("^TN:") then unique[body]=true end end
            local count=0; for _ in pairs(unique) do count=count+1 end
            assert(count>=10, "scan must advance instead of repeatedly checking the first nodes")
        ''')
        self.assert_restored()

    def test_ui_can_reenable_after_scan_failure(self):
        self.run_lua('''
            ns.TrackingCommand("on"); Minimap.failAlpha=true; ns.TrackingCommand("scan")
            ns.Set("tracking",true)
            assert(not ns.TrackingState():find("injected alpha failure"))
        ''')

    def test_all_addon_files_compile_in_lua51(self):
        compiler = self.lua.eval("function(source,name) local chunk,err=loadstring(source,name); assert(chunk,err) end")
        for path in ROOT.glob("*.lua"):
            with self.subTest(file=path.name):
                compiler(path.read_text(encoding="utf-8-sig"), path.name)


if __name__ == "__main__":
    unittest.main()
