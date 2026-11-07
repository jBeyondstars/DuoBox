--------------------------------------------------------------------------------
-- DuoBox / combat journal: a measurement tool, off by default (/duo journal on).
-- Writes what happens in each fight to DuoBoxJournal (SavedVariables, per
-- character) with timestamps. tools/analyze_fights.py joins it with
-- WoWCombatLog.txt to measure the warrior's dead time (melee light red, by
-- reason), what each key press changed, and how long the next target takes.
-- Nothing is cast, targeted or sent to the partner: it only writes this file
-- (and, when switched on, turns on the game's own combat log).
-- One string per entry, "time|code|fields" (time = GetTime(), 3 decimals):
--   S|server|epoch / S|local|epoch  GetServerTime() / time() just changed (clock edges)
--   I|name|class|guid|partner|version  session start
--   C|1, C|0          combat start / end
--   T|guid|name|flags your target (flags: E enemy, D dead, F friendly, P player; "-" = none)
--   P|guid|name|flags the partner's target, as this client sees it
--   L|code            melee light computed here (warrior, rogue): G R F A T N
--   R|code            melee light received from the partner (priest)
--   E|kind|text       red error text, kind: F facing, R range, V line of sight, O other
--   K|A|slot|type|name   action bar key or click (UseAction): macro or spell name
--   K|B|button|mouse  DuoBox button (bar or key binding)
--   K|I|unit|cvar     interact key (InteractUnit) and SoftTargetInteract at that moment
--   X|func|unit       AssistUnit / TargetUnit / TargetNearestEnemy / TargetLastEnemy (macro lines)
--   Q|S/F/I|spellID|name  your spell succeeded / failed / was interrupted
--   N|count           live enemies in combat on the nameplates (on change)
--   M|name|text       monster emote in combat ("attempts to run away in fear")
-- Kept out of DuoBox.lua: its main chunk is close to Lua 5.1's 200 locals.
--------------------------------------------------------------------------------

local _, ns = ...

local VERSION = 1
local MAX = 40000      -- entries kept; the oldest fifth goes when it is reached
local POLL = 0.2       -- s: targets and light (deaths fire no target event)
local ENEMY_POLL = 1   -- s: nameplates, in combat only
local RED = { R = "trop loin", F = "mal oriente", A = "n'attaque pas", T = "sans cible" }

local function DB() return ns.GetDB() end

local function Val(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function On()
	local db = DB()
	return db ~= nil and db.journal == true
end

local function Store()
	if type(DuoBoxJournal) ~= "table" then DuoBoxJournal = {} end
	local j = DuoBoxJournal
	if type(j.entries) ~= "table" then j.entries = {} end
	j.version = VERSION
	return j
end

-- "|" separates the fields; WoW also uses it for escape codes
local function Clean(v)
	if v == nil then return "" end
	return (tostring(v):gsub("[|\r\n]", " "))
end

local function Add(...)
	if not On() then return end
	local parts = { ("%.3f"):format(GetTime()) }
	for i = 1, select("#", ...) do parts[#parts + 1] = Clean((select(i, ...))) end
	local j = Store()
	local e = j.entries
	e[#e + 1] = table.concat(parts, "|")
	if #e > MAX then
		local keep = {}
		for i = #e - math.floor(MAX * 0.8) + 1, #e do keep[#keep + 1] = e[i] end
		j.entries = keep
	end
end

-- guid, name, flags of a unit; "-" when it does not exist
local function Describe(unit)
	if not Val(UnitExists(unit)) then return "-", "", "" end
	local flags = (Val(UnitCanAttack("player", unit)) and "E" or "") .. (Val(UnitIsDead(unit)) and "D" or "")
		.. (Val(UnitIsFriend("player", unit)) and "F" or "") .. (Val(UnitIsPlayer(unit)) and "P" or "")
	return Val(UnitGUID(unit)) or "?", Val(UnitName(unit)) or "?", flags
end

local last = {} -- last value written per code, so only changes are logged

local function Track(code, unit)
	local guid, name, flags = Describe(unit)
	if last[code] == guid .. flags then return end
	last[code] = guid .. flags
	Add(code, guid, name, flags)
end

local function Changed(code, value)
	if value == nil or last[code] == value then return end
	last[code] = value
	Add(code, value)
end

local function Enemies()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then return nil end
	local n = 0
	for _, plate in ipairs(plates) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and Val(UnitCanAttack("player", unit)) and Val(UnitAffectingCombat(unit)) and not Val(UnitIsDead(unit)) then
			n = n + 1
		end
	end
	return n
end

local function Poll()
	if not On() then return end
	Track("T", "target")
	local partner = ns.PartnerUnit()
	if partner then Track("P", partner .. "target") end
	if ns.MeleeLightCode then Changed("L", ns.MeleeLightCode()) end
end

local enemyTime = 0
local function PollEnemies()
	if not On() or not Val(UnitAffectingCombat("player")) then return end
	local now = GetTime()
	if now - enemyTime < ENEMY_POLL then return end
	enemyTime = now
	local n = Enemies()
	if n then Changed("N", tostring(n)) end
end

--------------------------------------------------------------------------------
-- Clock edges: the frame where GetServerTime() / time() change gives the
-- epoch of a GetTime() value to the frame (time() alone is whole seconds).
--------------------------------------------------------------------------------

local clock = CreateFrame("Frame")
local function Calibrate()
	local started = GetTime()
	local server0, local0 = GetServerTime and GetServerTime(), time()
	local gotServer, gotLocal = server0 == nil, false
	clock:SetScript("OnUpdate", function(self)
		local s, l = GetServerTime and GetServerTime(), time()
		if not gotServer and s ~= server0 then gotServer = true; Add("S", "server", s) end
		if not gotLocal and l ~= local0 then gotLocal = true; Add("S", "local", l) end
		if (gotServer and gotLocal) or GetTime() - started > 2.5 then self:SetScript("OnUpdate", nil) end
	end)
end

--------------------------------------------------------------------------------
-- The game's combat log: positions and facing of every unit that acts
-- (advanced logging), which no addon can read during the fight.
--------------------------------------------------------------------------------

local startedLog = false
local logPending = false -- switched on or off in combat: applied when the fight ends

local function StartCombatLog()
	if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("advancedCombatLogging") == "0" then
		pcall(C_CVar.SetCVar, "advancedCombatLogging", "1")
		ns.Print("journal : journal de combat avance active (positions et orientation dans WoWCombatLog).")
	end
	if LoggingCombat and not LoggingCombat() then
		LoggingCombat(true)
		startedLog = true
	end
end

local function StopCombatLog()
	if startedLog and LoggingCombat then LoggingCombat(false) end
	startedLog = false
end

local function Session()
	local _, class = UnitClass("player")
	local version = GetBuildInfo and GetBuildInfo() or ""
	Add("I", Val(UnitName("player")) or "?", class or "?", Val(UnitGUID("player")) or "?", DB().partner or "", version)
	wipe(last)
	Calibrate()
	Poll()
end

-- The combat log and its CVar are not changed in combat: the client blocks CVar changes from addons there
local function ApplyCombatLog()
	if InCombatLockdown and InCombatLockdown() then
		logPending = true
		return
	end
	logPending = false
	if On() then StartCombatLog() else StopCombatLog() end
end

function ns.RefreshJournal()
	if On() then Session() end
	ApplyCombatLog()
end

--------------------------------------------------------------------------------
-- /duo journal [on|off|clear|cvars]
--------------------------------------------------------------------------------

-- Seconds of each red light state, from the L entries (warrior) or the R entries (priest)
local function RedSeconds(entries)
	local red, fights = {}, 0
	local lastCode, lastTime, source
	for _, s in ipairs(entries) do
		local t, code, a = s:match("^([%d%.]+)|(%u)|?([^|]*)")
		t = tonumber(t)
		if code == "C" and a == "1" then fights = fights + 1 end
		if code == "I" then lastCode, lastTime = nil, nil end -- new session: GetTime() may restart
		if t and (code == "L" or code == "R") and (source == nil or source == code) then
			source = code
			if lastCode and RED[lastCode] and t >= lastTime then red[lastCode] = (red[lastCode] or 0) + t - lastTime end
			lastCode, lastTime = a, t
		end
	end
	return red, fights
end

local CVAR_WORDS = { "target", "interact", "combatlog", "attack", "facing", "clicktomove", "autoloot" }

local function DumpCVars()
	if not ConsoleGetAllCommands then
		ns.Print("journal : ConsoleGetAllCommands absent sur ce client.")
		return
	end
	local out, n = {}, 0
	for _, c in ipairs(ConsoleGetAllCommands() or {}) do
		local name = type(c) == "table" and c.command
		if type(name) == "string" then
			local low = name:lower()
			for _, w in ipairs(CVAR_WORDS) do
				if low:find(w, 1, true) then
					local ok, v = pcall(C_CVar.GetCVar, name)
					out[name] = ok and v or "?"
					if not ok or v == nil then out[name] = "(commande)" end
					n = n + 1
					break
				end
			end
		end
	end
	Store().cvars = out
	ns.Print(("journal : %d CVars de ciblage / interaction / combat enregistrees (DuoBoxJournal.cvars, ecrit au /reload ou a la deconnexion)."):format(n))
	local shown = {}
	for _, name in ipairs({ "SoftTargetEnemy", "SoftTargetEnemyArc", "SoftTargetEnemyRange", "SoftTargetForce",
		"SoftTargetInteract", "autoInteract", "advancedCombatLogging" }) do
		if out[name] ~= nil then shown[#shown + 1] = name .. "=" .. tostring(out[name]) end
	end
	for name, v in pairs(out) do
		if name:lower():find("targetauto", 1, true) then shown[#shown + 1] = name .. "=" .. tostring(v) end
	end
	if #shown > 0 then ns.Print("  " .. table.concat(shown, ", ")) end
end

function ns.JournalCommand(arg)
	local sub = (arg or ""):match("^(%S*)")
	if sub == "on" or sub == "off" then
		ns.Set("journal", sub == "on")
	elseif sub == "clear" then
		Store().entries = {}
		ns.Print("journal : vide.")
		if On() then Session() end
		return
	elseif sub == "cvars" then
		DumpCVars()
		return
	end
	local entries = Store().entries
	local red, fights = RedSeconds(entries)
	local parts = {}
	for _, code in ipairs({ "R", "F", "A", "T" }) do
		if red[code] then parts[#parts + 1] = ("%s %.0f s"):format(RED[code], red[code]) end
	end
	local logging, advanced = false, false
	if LoggingCombat then logging = LoggingCombat() and true or false end
	if C_CVar and C_CVar.GetCVar then advanced = C_CVar.GetCVar("advancedCombatLogging") == "1" end
	ns.Print(("journal : %s, %d entrees, %d combats%s ; journal de combat du jeu : %s%s"):format(
		On() and "|cff40ff40on|r" or "|cffff4040off|r", #entries, fights,
		#parts > 0 and (" ; rouge : " .. table.concat(parts, ", ")) or "",
		logging and "on" or "off", advanced and " (avance)" or ""))
end

--------------------------------------------------------------------------------
-- Events and hooks (each one returns at once while the journal is off)
--------------------------------------------------------------------------------

local ERROR_KIND = {}
for g, kind in pairs({ ERR_BADATTACKFACING = "F", SPELL_FAILED_UNIT_NOT_INFRONT = "F", SPELL_FAILED_NOT_INFRONT = "F",
	ERR_BADATTACKPOS = "R", SPELL_FAILED_OUT_OF_RANGE = "R", ERR_OUT_OF_RANGE = "R", SPELL_FAILED_TOO_CLOSE = "R",
	SPELL_FAILED_LINE_OF_SIGHT = "V" }) do
	if type(_G[g]) == "string" then ERROR_KIND[_G[g]] = kind end
end

local SPELL_EVENTS = { UNIT_SPELLCAST_SUCCEEDED = "S", UNIT_SPELLCAST_FAILED = "F", UNIT_SPELLCAST_INTERRUPTED = "I" }

local hookedButtons = {}
local function HookButtons()
	for name, obj in pairs(_G) do
		if type(name) == "string" and name:sub(1, 9) == "DuoBoxBtn" and type(obj) == "table"
			and obj.HookScript and not hookedButtons[obj] then
			hookedButtons[obj] = true
			local key = name:sub(10)
			obj:HookScript("OnClick", function(self, mouse, down)
				-- Rotation acts on the key going down and on its release: one press, one entry
				if down == false and self:GetAttribute("pressAndHoldAction") then return end
				Add("K", "B", key, mouse)
			end)
		end
	end
end

local function Hook(tbl, name, fn)
	if tbl == _G and type(_G[name]) == "function" then
		hooksecurefunc(name, fn)
	elseif type(tbl) == "table" and type(tbl[name]) == "function" then
		hooksecurefunc(tbl, name, fn)
	end
end

Hook(_G, "UseAction", function(slot)
	if not On() then return end
	local kind, id = GetActionInfo(slot)
	local name = GetActionText and GetActionText(slot)
	if not name and kind == "macro" and GetMacroInfo then name = GetMacroInfo(id) end
	if not name and kind == "spell" then name = ns.SpellNameIcon(id) end
	Add("K", "A", slot, kind, name or id)
end)
Hook(C_PlayerInteractionManager, "InteractUnit", function(unit)
	if not On() then return end
	Add("K", "I", unit, C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("SoftTargetInteract"))
end)
for _, name in ipairs({ "AssistUnit", "TargetUnit", "TargetNearestEnemy", "TargetLastEnemy" }) do
	Hook(_G, name, function(unit) Add("X", name, type(unit) == "string" and unit or "") end)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		HookButtons()
		C_Timer.After(2, HookButtons) -- buttons built later (spells learned, class bars)
		C_Timer.NewTicker(POLL, function() Poll(); PollEnemies() end)
		if On() then ns.RefreshJournal() end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and logPending then ApplyCombatLog() end
	if not On() then return end
	if event == "PLAYER_REGEN_DISABLED" then
		Add("C", 1)
		wipe(last) -- write the targets and the light at the start of every fight
		enemyTime = 0
		Poll()
		PollEnemies()
	elseif event == "PLAYER_REGEN_ENABLED" then
		Poll()
		Add("C", 0)
	elseif event == "PLAYER_TARGET_CHANGED" then
		Track("T", "target")
	elseif event == "UNIT_TARGET" then
		local unit = ...
		if unit == ns.PartnerUnit() then Track("P", unit .. "target") end
	elseif event == "UI_ERROR_MESSAGE" then
		local a, b = ... -- (messageType, message) or (message) depending on the version
		local msg = Val(type(a) == "string" and a or b)
		if type(msg) == "string" then Add("E", ERROR_KIND[msg] or "O", msg) end
	elseif SPELL_EVENTS[event] then
		local _, _, spellID = ...
		spellID = Val(spellID)
		Add("Q", SPELL_EVENTS[event], spellID, spellID and ns.SpellNameIcon(spellID))
	elseif event == "CHAT_MSG_MONSTER_EMOTE" then
		if Val(UnitAffectingCombat("player")) then
			local text, name = ...
			Add("M", Val(name), Val(text))
		end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, body, channel, sender = ...
		if prefix ~= "DUOBOX" or channel ~= "PARTY" then return end
		body = ns.FromPartner(body, sender)
		local code = type(body) == "string" and body:match("^ML:(%u)$")
		if code then Changed("R", code) end
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")
-- UNIT_TARGET for every unit: RegisterUnitEvent takes two units, the partner can be party1..party4
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UI_ERROR_MESSAGE",
	"CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_ADDON", "UNIT_TARGET" }) do
	ev:RegisterEvent(event)
end
for event in pairs(SPELL_EVENTS) do pcall(ev.RegisterUnitEvent, ev, event, "player") end
