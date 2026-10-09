--------------------------------------------------------------------------------
-- DuoBox / interact key: a live enemy target goes first.
-- With "Enable Interact Key" (CVar SoftTargetInteract), the interact key
-- (INTERACTTARGET = InteractUnit("anyinteract")) goes to the soft interact
-- target first: the nearest object, corpse or NPC, even when the target is an
-- enemy. "Assist the partner + interact key" then picked up loot or talked to
-- an NPC instead of walking to the enemy.
-- While your target is a live enemy, soft interaction is switched off with a
-- temporary CVar (never saved): the key then interacts with the target, i.e.
-- auto-attack and, with Click-to-Move, walking to it. Blizzard's gamepad
-- targeting does the same in combat (Blizzard_GamepadTargeting).
-- In combat the partner's target counts too, so the CVar is already off when
-- the interact key comes right after the assist key. Out of combat it does not:
-- the key must pick up loot and objects after the fight.
-- Kept out of DuoBox.lua: its main chunk is close to Lua 5.1's 200 locals.
--------------------------------------------------------------------------------

local _, ns = ...

local CVAR = "SoftTargetInteract"
local MELEE = { WARRIOR = true, ROGUE = true } -- on by default: walking to the enemy is what they want

local Print, PartnerUnit = ns.Print, ns.PartnerUnit
local function DB() return ns.GetDB() end

local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Temporary CVars exist on WoW Forever (1.60), not on Classic Era 1.15
local function Supported()
	return C_CVar ~= nil and C_CVar.SetTempCVar ~= nil and C_CVar.RemoveTempCVar ~= nil
end

local function LiveEnemy(unit)
	return UnitExists(unit) and Val(UnitCanAttack("player", unit)) and not Val(UnitIsDead(unit)) or false
end

-- Why the key should go to the target: nil, "player" (your target) or the partner unit (its target, in combat)
local function Reason()
	local db = DB()
	if not (db and db.interactEnemy) then return nil end
	if LiveEnemy("target") then return "player" end
	local unit = PartnerUnit()
	if unit and (Val(UnitAffectingCombat("player")) or Val(UnitAffectingCombat(unit))) and LiveEnemy(unit .. "target") then
		return unit
	end
end

local applied = false -- our temporary value is set
local warned = false

local function Warn(msg)
	if warned then return end
	warned = true
	Print("touche d'interaction : " .. msg)
end

-- Each change is read back: a refused one is tried again on the next update
local function Apply(off)
	if off == applied then return end
	if not Supported() then
		if off then Warn("ce client ne permet pas de couper le ciblage d'interaction (CVars temporaires absentes).") end
		return
	end
	if off then
		if C_CVar.GetCVar(CVAR) == "0" then return end -- already off: the key already goes to the target
		pcall(C_CVar.SetTempCVar, CVAR, "0")
		if C_CVar.GetCVar(CVAR) ~= "0" then
			Warn("le client refuse de couper " .. CVAR .. " (|cffffd040/duo interact off|r pour desactiver).")
			return
		end
	else
		pcall(C_CVar.RemoveTempCVar, CVAR)
		if C_CVar.GetCVar(CVAR) == "0" then
			Warn("le client refuse de retablir " .. CVAR .. ", nouvel essai automatique.")
			return
		end
	end
	applied = off
end

local function Refresh()
	Apply(Reason() ~= nil)
end
ns.RefreshInteract = Refresh

-- /duo interact [on|off]; without argument, shows the state and why
function ns.InteractCommand(arg)
	if arg == "on" or arg == "off" then ns.Set("interactEnemy", arg == "on") end
	local why = Reason()
	local detail = "normal"
	if why == "player" then
		detail = ("coupe, ta cible %s est un ennemi vivant"):format(Val(UnitName("target")) or "?")
	elseif why then
		detail = ("coupe, en combat la cible du partenaire (%s) est un ennemi vivant"):format(Val(UnitName(why .. "target")) or "?")
	end
	Print(("touche d'interaction : %s, objets / PNJ : %s (%s = %s)"):format(DB().interactEnemy and "|cff40ff40on|r" or "|cffff4040off|r",
		detail, CVAR, tostring(C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(CVAR))))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_TARGET", "party1", "party2")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		local db = DB()
		if db.interactEnemy == nil then
			local _, class = UnitClass("player")
			db.interactEnemy = MELEE[class] and Supported() or false
		end
		-- A /reload keeps the temporary value but forgets it was ours
		if Supported() and C_CVar.GetCVar(CVAR) == "0" then pcall(C_CVar.RemoveTempCVar, CVAR) end
		C_Timer.NewTicker(0.3, Refresh) -- deaths and combat end: no event for the partner's target
	end
	Refresh()
end)

-- Right after an assist / target line of a macro, before the interact key that follows it
for _, name in ipairs({ "AssistUnit", "TargetUnit" }) do
	if _G[name] then hooksecurefunc(name, Refresh) end
end
