--------------------------------------------------------------------------------
-- DuoBox / dungeon mode: the assists take the main tank's target instead of the
-- partner's (attack buttons of the bar, Assist button, Rotation, /assist lines
-- of the D- macros). Follow, Talk and the priest's heals stay on the partner.
-- The tank: the name set with /duo tank <Name>, otherwise the group member whose
-- role is Tank (right-click a portrait > Role, or a role check). Roles can be
-- secret for addons inside instances: the last tank read stays in use.
-- No tank found, or you are the tank: the partner, as outside dungeon mode.
-- Kept out of DuoBox.lua: its main chunk is close to Lua 5.1's 200 locals.
--------------------------------------------------------------------------------

local _, ns = ...

local function DB() return ns.GetDB() end

local function Val(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Comparison key of a name: first name only, lowercase (same rule as the partner name)
local function Key(name)
	name = Val(name)
	if not name or name == "" then return nil end
	return (name:match("^[^%s%-]+") or name):lower()
end

local function UnitByName(name)
	local key = Key(name)
	if not key then return nil end
	for i = 1, 4 do
		local u = "party" .. i
		if Val(UnitExists(u)) and Key(UnitName(u)) == key then return u end
	end
end

local lastTank -- name of the last group member read with the Tank role

-- Group member with the Tank role (never you: party1..4 are the others)
local function RoleTank()
	local readable = true
	for i = 1, 4 do
		local u = "party" .. i
		if Val(UnitExists(u)) then
			local role = UnitGroupRolesAssigned and Val(UnitGroupRolesAssigned(u))
			if not role then
				readable = false -- secret in an instance: keep the last tank read
			elseif role == "TANK" then
				lastTank = Val(UnitName(u)) or lastTank
				return u
			end
		end
	end
	if readable then lastTank = nil end -- roles readable and nobody is the tank
	return UnitByName(lastTank)
end

-- The tank's unit and how it was found, or nil
local function Tank()
	local db = DB()
	if db.tank then
		local u = UnitByName(db.tank)
		return u, u and "nom saisi"
	end
	local u = RoleTank()
	return u, u and "role Tank"
end

-- Unit whose target the assists take: the tank in dungeon mode, otherwise the partner
function ns.AssistUnit()
	local db = DB()
	local tank = db and db.dungeon and Tank()
	return tank or ns.BarUnit()
end

function ns.DungeonStatus()
	local db = DB()
	if not db.dungeon then return "Mode donjon desactive : les assists prennent la cible du partenaire." end
	local tank, how = Tank()
	if tank then
		return ("Assists sur la cible de |cff40ff40%s|r (%s)."):format(Val(UnitName(tank)) or tank, how)
	elseif db.tank then
		return ("|cffffd040%s n'est pas dans le groupe|r : assists sur le partenaire."):format(db.tank)
	end
	return "|cffffd040Aucun tank|r (clic droit sur son portrait > Role > Tank, ou /duo tank <Nom>) : assists sur le partenaire."
end

-- /duo dungeon [on|off], /duo tank [<Name>|auto]
function ns.DungeonCommand(cmd, arg)
	local db = DB()
	if cmd == "tank" then
		if arg == "auto" then
			ns.Set("tank", nil)
		elseif arg ~= "" then
			ns.Set("tank", arg:match("^[^%-]+")) -- without the realm
		end
		ns.Print("tank = " .. (db.tank and ("|cffffd040" .. db.tank .. "|r") or "auto (role Tank)") .. ". " .. ns.DungeonStatus())
		return
	end
	local value
	if arg == "on" then value = true elseif arg == "off" then value = false else value = not db.dungeon end
	ns.Set("dungeon", value)
	ns.Print(("mode donjon = %s. %s"):format(value and "|cff40ff40on|r" or "|cffff4040off|r", ns.DungeonStatus()))
end

-- A role set or changed: the bar and the D- macros follow (out of combat; otherwise after it)
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function()
	if ns.UpdateBar and DB() then ns.UpdateBar() end
end)
