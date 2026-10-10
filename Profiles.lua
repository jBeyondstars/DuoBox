--------------------------------------------------------------------------------
-- Configuration profiles: named copies of the settings, saved for the whole WoW
-- account (DuoBoxProfiles) so every character of the account can load them.
-- Loading goes through ns.Set (same side effects as the options panel); later
-- changes stay on the character until the profile is saved again.
-- Not in a profile: the names (partner, tank), the role and the positions.
-- /duo profile [save|load|delete <name>], Profils tab of the options panel.
--------------------------------------------------------------------------------

local _, ns = ...

local function DB() return ns.GetDB() end
local Print = ns.Print

-- Settings copied by a profile: the defaults of DuoBox.lua, minus EXCLUDED
-- (tests check that every default is in one of the two lists).
-- DB.rotation (warrior Rotation button) is copied too, see Save / Load.
local KEYS = {
	"leader", "hpPartner", "hpPet", "manaPartner", "sound", "flash",
	"autoInvite", "autoQuest", "autoShare", "autoRez", "autoNpc", "interactEnemy",
	"turnin", "acceptAlert", "lootAlert", "frame", "bar", "barScale", "castbar", "combatMonitor",
	"facing", "facingInvert", "facingDist", "rxp", "rxpHold", "minimap", "tracking", "dungeon",
	"meleeLight", "lightSound",
}
-- Kept per character: who the partner and the tank are, this character's role, where its button sits
local EXCLUDED = { partner = true, tank = true, role = true, minimapAngle = true }
ns.PROFILE_KEYS, ns.PROFILE_EXCLUDED = KEYS, EXCLUDED

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, x in pairs(a) do
		if not Same(x, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function Trim(s) return ((s or ""):match("^%s*(.-)%s*$")) end

-- [name] = { values = { [key] = value }, rotation = steps or nil, by = character, class = "WARRIOR" }
local function Store()
	if type(DuoBoxProfiles) ~= "table" then DuoBoxProfiles = {} end
	return DuoBoxProfiles
end

-- Stored name of a profile, the case is ignored
local function Find(name)
	name = Trim(name)
	local store = Store()
	if store[name] then return name end
	name = name:lower()
	for k in pairs(store) do
		if k:lower() == name then return k end
	end
end

-- Missing value: the default (nil = auto, or a setting added after the profile was saved)
local function Value(profile, key)
	local v = profile.values[key]
	if v == nil then v = ns.DEFAULTS[key] end
	return v
end

-- Each setting the profile would change (rotation: only if the profile has one)
local function Diff(profile, fn)
	local db = DB()
	for _, key in ipairs(KEYS) do
		local v = Value(profile, key)
		if not Same(db[key], v) then fn(key, v) end
	end
	if profile.rotation and not Same(db.rotation, profile.rotation) then fn("rotation", profile.rotation) end
end

function ns.ProfileNames()
	local names = {}
	for k in pairs(Store()) do names[#names + 1] = k end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return names
end

-- Profile and its stored name
function ns.ProfileInfo(name)
	local key = Find(name)
	if key then return Store()[key], key end
end

-- Profile last saved or loaded on this character, and whether its settings changed since
function ns.ActiveProfile()
	local key = DB().profile
	local profile = key and Store()[key]
	if not profile then return nil end
	local changed = false
	Diff(profile, function() changed = true end)
	return key, changed
end

function ns.ProfileSave(name)
	name = Trim(name)
	if name == "" then
		Print("donne un nom au profil : /duo profile save <nom>.")
		return
	end
	name = Find(name) or name -- same name, other case: replaces it
	local db, values = DB(), {}
	for _, key in ipairs(KEYS) do values[key] = Copy(db[key]) end
	local _, class = UnitClass("player")
	Store()[name] = { values = values, rotation = type(db.rotation) == "table" and Copy(db.rotation) or nil,
		by = UnitName("player"), class = class }
	db.profile = name
	Print(("profil |cffffd040%s|r enregistre (commun aux persos de ce compte)."):format(name))
	return name
end

function ns.ProfileLoad(name)
	local key = Find(name)
	if not key then
		Print(("aucun profil |cffffd040%s|r. /duo profile : la liste."):format(Trim(name)))
		return
	end
	if InCombatLockdown() then
		Print("un profil se charge hors combat.")
		return
	end
	local count = 0
	Diff(Store()[key], function(k, v)
		ns.Set(k, Copy(v))
		count = count + 1
	end)
	DB().profile = key
	Print(("profil |cffffd040%s|r charge : %d reglage%s modifie%s."):format(key, count,
		count > 1 and "s" or "", count > 1 and "s" or ""))
	return true
end

function ns.ProfileDelete(name)
	local key = Find(name)
	if not key then
		Print(("aucun profil |cffffd040%s|r."):format(Trim(name)))
		return
	end
	Store()[key] = nil
	if DB().profile == key then DB().profile = nil end
	Print(("profil |cffffd040%s|r supprime."):format(key))
	return true
end

function ns.ProfileCommand(arg)
	local sub, name = (arg or ""):match("^(%S*)%s*(.-)%s*$")
	sub = sub:lower()
	if sub == "save" then
		ns.ProfileSave(name ~= "" and name or ns.ActiveProfile())
	elseif sub == "load" then
		ns.ProfileLoad(name)
	elseif sub == "delete" then
		ns.ProfileDelete(name)
	else
		local names = ns.ProfileNames()
		local active, changed = ns.ActiveProfile()
		for i, n in ipairs(names) do
			if n == active then names[i] = ("|cffffd040%s|r (%s)"):format(n, changed and "actif, modifie" or "actif") end
		end
		Print(#names > 0 and ("profils : " .. table.concat(names, ", ") .. ".") or "aucun profil enregistre.")
		Print("/duo profile save|load|delete <nom> (save seul : le profil actif).")
	end
end
