--------------------------------------------------------------------------------
-- DuoBox / relayed pickup (with DuoRelay, PC 1 -> PC 2): a Ctrl+right click on
-- an object (ore vein, herb, quest object...) makes the partner pick up the
-- same kind of object, not just whatever object is nearest to it.
-- Clicking side: on a Ctrl+right click (no other modifier) over the 3D world,
-- the name of the object under the cursor, read from the world cursor tooltip
-- (C_TooltipInfo.GetWorldCursor: type Object; this client gives no GUID for
-- it, checked in game 2026-11-06), is sent as "PK:<name>".
-- Partner side: DuoRelay presses KEY there. KEY is bound (override binding)
-- to the interact key (INTERACTTARGET) only while the soft interact target
-- (unit "softinteract", what the interact key would take) has that name, for
-- WINDOW seconds after the request; the rest of the time KEY does nothing
-- (bound to an empty button, so the game never falls back to the bare key:
-- an unbound CTRL-SHIFT-F9 would run F9's binding). Answers "PA:1:<name>",
-- "PA:0:<name seen>" or "PA:C:" (in combat) so the clicking side says what
-- happens.
-- Same kind of object, not the same one: with two veins side by side, the
-- partner may take the other one. Both clients must use the same language.
-- Bindings cannot change in combat: requests are refused then, and KEY goes
-- back to doing nothing as the fight starts (PLAYER_REGEN_DISABLED, the last
-- moment before the lockdown).
-- Off by default (DB.pickupRelay), to switch on on both characters.
-- Kept out of DuoBox.lua (Lua 5.1's 200 locals).
--------------------------------------------------------------------------------

local _, ns = ...

local PREFIX = "DUOBOXK"
local KEY = "CTRL-SHIFT-F9" -- pressed by DuoRelay (DuoRelay.json, trigger "pickup")
local WINDOW = 3            -- s during which KEY may pick up the requested object
local ANSWER_WAIT = 2       -- s before saying the partner did not answer
local OBJECT = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object or 4

local function DB() return ns.GetDB() end

-- The secret test comes first: comparing a secret value, even to nil, is refused
local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function Say(text, r, g, b)
	UIErrorsFrame:AddMessage(text, r, g, b)
end

local function PartnerName()
	local unit = ns.PartnerUnit()
	return unit and Val(UnitName(unit)) or "Le partenaire"
end

--------------------------------------------------------------------------------
-- Clicking side
--------------------------------------------------------------------------------

local asked, askedAt, gotAnswer = nil, 0, false -- last object asked for, when, answered yet

-- Mouse over the 3D world, not over a frame of the interface
local function OverWorld()
	local focus
	if GetMouseFoci then
		local foci = GetMouseFoci()
		focus = foci and foci[1]
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	return focus == nil or focus == WorldFrame
end

-- Name of the world object under the cursor, nil for a unit, the ground, a hidden name
local function ObjectUnderCursor()
	local data = C_TooltipInfo and C_TooltipInfo.GetWorldCursor and C_TooltipInfo.GetWorldCursor()
	if type(data) ~= "table" or Val(data.type) ~= OBJECT then return nil end
	local line = type(data.lines) == "table" and data.lines[1]
	local name = type(line) == "table" and Val(line.leftText)
	if type(name) == "string" and name ~= "" then return name end
end

local function OnMouseDown(button)
	if button ~= "RightButton" or not DB() or not DB().pickupRelay then return end
	if not IsControlKeyDown() or IsShiftKeyDown() or IsAltKeyDown() then return end
	if not ns.PartnerUnit() or not OverWorld() then return end
	local name = ObjectUnderCursor()
	if not name then return end
	ns.SendComm("PK:" .. name, PREFIX)
	asked, askedAt, gotAnswer = name, GetTime(), false
	local at = askedAt
	C_Timer.After(ANSWER_WAIT, function()
		if askedAt ~= at or gotAnswer then return end -- answered, or asked again since
		Say(("%s ne repond pas (option Ramassage relaye active sur les deux persos ?)"):format(PartnerName()), 1, 0.6, 0)
	end)
end

-- "0" may be followed by "1" when the partner's interact target changes within the window
local function OnAnswer(state, name)
	if not asked or GetTime() - askedAt > WINDOW + 1 then return end
	gotAnswer = true
	local wanted, who = asked, PartnerName()
	if state == "1" then
		Say(("%s ramasse : %s"):format(who, wanted), 0.3, 1, 0.3)
	elseif state == "C" then
		Say(("%s est en combat : pas de ramassage"):format(who), 1, 0.6, 0)
	elseif name ~= "" then
		Say(("%s : pas de %s a portee (il vise : %s)"):format(who, wanted, name), 1, 0.3, 0.3)
	else
		Say(("%s : pas de %s a portee"):format(who, wanted), 1, 0.3, 0.3)
	end
end

--------------------------------------------------------------------------------
-- Partner side
--------------------------------------------------------------------------------

local owner = CreateFrame("Frame")                    -- owns the override binding, and the events
local idle = CreateFrame("Button", "DuoBoxPickupIdle") -- KEY's target while it must do nothing
local want, wantUntil = nil, 0                        -- requested object name, until when
local bound                                           -- "interact", "idle" or nil (not bound)
local answered = true                                 -- the current request got a "1" answer

-- Name of what the interact key would take now (object or NPC), nil when hidden
local function SoftName()
	return Val(UnitName("softinteract"))
end

local function Matches()
	return want ~= nil and GetTime() < wantUntil and SoftName() == want
end

-- "1" once per request, as soon as KEY picks up the requested object
local function Answer()
	if answered or not want or GetTime() >= wantUntil or bound ~= "interact" then return end
	answered = true
	ns.SendComm("PA:1:" .. want, PREFIX)
end

-- KEY: the interact key while the soft target is the requested object, nothing
-- otherwise; left to the player's own bindings when the option is off
local function Apply()
	if InCombatLockdown() then return end
	local target
	if DB() and DB().pickupRelay then target = Matches() and "interact" or "idle" end
	if target ~= bound then
		ClearOverrideBindings(owner)
		if target == "interact" then
			SetOverrideBinding(owner, true, KEY, "INTERACTTARGET")
		elseif target == "idle" then
			SetOverrideBindingClick(owner, true, KEY, "DuoBoxPickupIdle")
		end
		bound = target
	end
	Answer()
end

local function OnRequest(name)
	if not (DB() and DB().pickupRelay) then return end
	if InCombatLockdown() then
		ns.SendComm("PA:C:", PREFIX)
		return
	end
	want, wantUntil, answered = name, GetTime() + WINDOW, false
	Apply() -- answers "1" when the interact target is already the right object
	if not answered then ns.SendComm("PA:0:" .. (SoftName() or ""), PREFIX) end
	C_Timer.After(WINDOW + 0.1, Apply)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
elseif RegisterAddonMessagePrefix then
	RegisterAddonMessagePrefix(PREFIX)
end

owner:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, body, channel, sender = ...
		if prefix ~= PREFIX or channel ~= "PARTY" then return end
		body = ns.FromPartner(body, sender)
		if type(body) ~= "string" then return end
		local name = body:match("^PK:(.+)$")
		if name then OnRequest(name); return end
		local state, seen = body:match("^PA:([01C]):(.*)$")
		if state then OnAnswer(state, seen) end
	elseif event == "GLOBAL_MOUSE_DOWN" then
		OnMouseDown(...)
	elseif event == "PLAYER_REGEN_DISABLED" then
		want = nil -- KEY back to nothing before the lockdown
		Apply()
	else -- PLAYER_SOFT_INTERACT_CHANGED, PLAYER_REGEN_ENABLED, PLAYER_LOGIN
		Apply()
	end
end)
for _, e in ipairs({ "CHAT_MSG_ADDON", "GLOBAL_MOUSE_DOWN", "PLAYER_SOFT_INTERACT_CHANGED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN" }) do
	pcall(owner.RegisterEvent, owner, e)
end

-- Options panel: switching the option on / off takes effect at once (out of combat)
ns.RefreshPickupRelay = Apply
