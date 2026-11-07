--------------------------------------------------------------------------------
-- DuoBox / Rotation button, every class: 1 press = 1 action, chosen by the game.
-- Its spells (DB.rotation, per character and its class) are edited in the panel opened by
-- /duo rotation or a right-click on the button. Macros cannot test buffs,
-- cooldowns, rage or the number of enemies, so each step is either:
--   * "each press": /cast in list order, the game skips what is not usable
--     (Overpower after a dodge, Execute under 20%, cooldown, not enough rage),
--   * "once per fight" (own buffs such as Battle Shout): cast when the buff is
--     missing as the fight starts. Decided out of combat from the buff, since
--     the macro cannot change during a fight.
-- Multi-target mode: two macros are prepared out of combat, single target and
-- multi target (steps marked "multi only" / "single only"). The Multi button
-- (key or voice "multi") sets the Rotation macro to the multi-target one with
-- Blizzard's secure "attribute" action, the only way to change it in combat,
-- until the end of the fight (pressed out of combat: for the next fight, until
-- its end); its right-click goes back to single target.
-- The game runs only the first 255 characters of a button's macro (measured in game on
-- 2026-11-06: with 4 "once per fight" lines, Overpower and Heroic Strike were never tried).
-- So a press runs two macros of the same button: the attacks when the key goes down,
-- the "once per fight" buffs when it is released (Blizzard's press-and-hold release
-- action). A macro run by /click from another macro did nothing on this client
-- (tested 2026-11-06), hence no hidden button.
-- Kept out of DuoBox.lua: its main chunk is close to Lua 5.1's 200 locals.
--------------------------------------------------------------------------------

local _, ns = ...

local REFRESH = 30 -- seconds left under which a "once per fight" buff counts as missing
local MAX_STEPS = 10
local MAX_LEN = 255 -- characters of a button's macro the game runs, the rest is dropped
local RELEASE = "*macrotext1" -- macro of the key release (left button, any modifier)
-- One macro run tries only ONE spell on the global cooldown: the first of its lines that the
-- game tries, even when it fails or is skipped as unusable; spells off the global cooldown
-- (Heroic Strike, Cleave, Bloodrage) are tried anyway (combat log 2026-11-07: Overpower skipped
-- without a dodge, then a Slam line after it never tried, even with 53 rage; Rend failing for
-- rage on the release, then no Victory Rush). A priority list of such attacks cannot work, and
-- no code can pick one by the target's health at the press: the secure snippet that runs then
-- sees neither health nor usability (RestrictedEnvironment.lua). So the key down has one macro
-- per attack on the global cooldown, that attack first, then the spells off it, and a secure
-- snippet (SNIPPET) sends each press to the next one: Overpower, Execute, Slam... take turns, and
-- the game itself gates Overpower (after a dodge) and Execute (under 20%). Chosen by the user on
-- 2026-11-07. The key release, a run of its own, casts the buffs, then Victory Rush.
-- Spells a macro /cast never casts on WoW Forever: the client calls them unusable (Victory Rush
-- even during its "Victorious" buff, Slam in combat) and skips them without a word, while an
-- action-bar key sends them and the server accepts. The Rotation uses their action-bar slot
-- instead: "/click" on a hidden action button (tested in game 2026-11-06 with a /click
-- ActionButton5 macro). Such a click takes the run's turn even when the spell cannot be cast:
-- Victory Rush ends the key release, after the buffs; Slam leads a key-down macro of its own.
-- [spell ID] = { hidden button name, "release" (end of the key release) or "down" (key down) }
local VIA_BAR = {
	[402927] = { "DuoBoxRotVictoryRush", "release" }, -- Victory Rush (Season of Discovery spell)
	[1240193] = { "DuoBoxRotSlam", "down" },           -- Slam, WoW Forever's version, cast time
}
-- Spells off the global cooldown, tried on every press whatever comes before them (next-swing
-- attacks, Bloodrage): rank 1 IDs, compared by name (any rank)
local OFF_GCD = { 78, 845, 6807, 2973, 2687 } -- Heroic Strike, Cleave, Maul, Raptor Strike, Bloodrage
-- Secure snippet run on every click of the Rotation button, before it acts (SecureHandlerWrapScript,
-- restricted environment): sends a key going down to the next key-down macro of the mode,
-- "*macrotext-s<n>" (single target) or "*macrotext-a<n>" (multi target, set by the Multi button)
local SNIPPET = [[
	if not down or button ~= "LeftButton" then return end
	local mode = self:GetAttribute("rot-mode") == "aoe" and "a" or "s"
	local count = self:GetAttribute("rot-count-" .. mode) or 1
	local index = (self:GetAttribute("rot-index") or 0) % count + 1
	self:SetAttribute("rot-index", index)
	return mode .. index
]]
local BATTLE_SHOUT = 6673
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Default list of each class (empty for the others). Warrior: Battle Shout once per fight,
-- Thunder Clap in multi-target mode (above Overpower, which would otherwise take the press's
-- one try on the global cooldown), Overpower (after a dodge), Heroic Strike (off it)
local DEFAULTS = {
	WARRIOR = { { id = BATTLE_SHOUT, once = true }, { id = 6343, when = "aoe" }, { id = 7384 }, { id = 78 } },
}
local DEFAULT_TIP = { WARRIOR = "Cri de guerre (1x par combat), Coup de tonnerre (multi seulement), Fulgurance, Frappe heroique." }
-- Line after the target lines: auto attack for melee classes, the pet for pet classes, nothing for casters
local ATTACK = { WARRIOR = "/startattack", ROGUE = "/startattack", PALADIN = "/startattack", SHAMAN = "/startattack",
	DRUID = "/startattack", HUNTER = "/petattack", WARLOCK = "/petattack" }

local function DB() return ns.GetDB() end
local function Class() return (select(2, UnitClass("player"))) end

local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local button        -- DuoBoxBtnRotation, given by ns.SetupRotation
local multi         -- DuoBoxBtnMulti: sets the Rotation macro to the multi-target one
local needed = {}   -- [spellID] = true: "once per fight" buff to cast (decided out of combat)
local seen = {}     -- [spellID] = true: buff seen during this fight (alert when it ends)
local press = 0     -- GetTime() of the last press
local panel, RefreshPanel -- created on first open

-- Steps of this character: { id = spellID, once = true (once per fight), off = true (disabled),
-- when = nil (always) / "aoe" (multi-target mode only) / "single" (single target only) }
-- DB.rotationClass: class of the list. Before it existed only the warrior had a Rotation, so an
-- untagged list on another class came from a warrior profile: replaced by that class's default.
local function Steps()
	local db, class = DB(), Class()
	if db.rotationClass == nil and class == "WARRIOR" then db.rotationClass = class end
	if type(db.rotation) ~= "table" or db.rotationClass ~= class then
		db.rotation, db.rotationClass = {}, class
		for i, s in ipairs(DEFAULTS[class] or {}) do db.rotation[i] = { id = s.id, once = s.once, when = s.when } end
	end
	return db.rotation
end

-- Name of the step's spell when it goes in the macro of that mode: enabled, learned, right mode
local function Usable(s, aoe)
	if s.when and (s.when == "aoe") ~= (aoe or false) then return nil end
	return not s.off and ns.Known(s.id) and (ns.SpellNameIcon(s.id)) or nil
end

-- Action-bar slot holding a VIA_BAR spell, nil when it is on no bar (any slot works, whatever
-- the page or the stance shows: the hidden button uses the slot itself)
local function BarSlot(id)
	if not VIA_BAR[id] or not GetActionInfo then return nil end
	for slot = 1, 180 do
		local kind, actionID = GetActionInfo(slot)
		if kind == "spell" and actionID == id then return slot end
	end
	-- Same spell under another ID on the bar (a rank, WoW Forever's own version of a spell)
	local name = ns.SpellNameIcon(id)
	for slot = 1, 180 do
		local kind, actionID = GetActionInfo(slot)
		if kind == "spell" and name and ns.SpellNameIcon(actionID) == name then return slot end
	end
end

-- A VIA_BAR "each press" spell on a bar for the key release (for both modes: the Multi button
-- swaps only the key-down macro; for one mode only, it ends the key-down macro instead)
local function Late(s)
	return VIA_BAR[s.id] ~= nil and VIA_BAR[s.id][2] == "release" and not s.once and not s.when
		and BarSlot(s.id) ~= nil
end

local function Click(id) return "/click " .. VIA_BAR[id][1] end

local offGcdNames -- [name] = true, from OFF_GCD
local function OffGcd(id)
	if not offGcdNames then
		local names = {}
		for _, x in ipairs(OFF_GCD) do
			local name = ns.SpellNameIcon(x)
			if name then names[name] = true end
		end
		if not next(names) then return false end -- spell data not loaded yet: ask again later
		offGcdNames = names
	end
	local name = ns.SpellNameIcon(id)
	return name ~= nil and offGcdNames[name] == true
end

-- The macros of a press: the key going down, one per attack on the global cooldown (a list of
-- texts; target, auto attack, that attack, then the spells off the global cooldown), and its
-- release (the "once per fight" buffs to cast, then Victory Rush; "" if none). In mode aoe.
-- all = true: every buff, as if missing (the longest macros, for the panel).
-- fight = true: built on PLAYER_REGEN_DISABLED and kept for the whole fight. A plain /cast of
-- a buff would then fire on every press: /castsequence casts it once, and "null" (no such
-- spell) holds the sequence until reset=combat, at the end of the fight.
-- The Multi button swaps only the key-down macro, so a buff for one mode only ("multi only",
-- "single only") stays at its top; the release holds the buffs of both modes, the same in
-- both, so switching to multi target does not shout twice. A VIA_BAR spell for the release
-- comes after the buffs, on a live enemy target only (see VIA_BAR).
-- hp: health of the target (TargetHealth); a step with minHP above it stays out (Rend on a mob
-- about to die), decided as the fight starts since the macro cannot change during it.
local function Macro(fight, aoe, all, hp)
	local head, release, late, leads, extras = {}, {}, {}, {}, {}
	local function Use(s)
		if not all and s.minHP and hp and hp < s.minHP then return nil end
		return Usable(s, aoe)
	end
	for _, s in ipairs(Steps()) do
		local name = s.once and (all or needed[s.id]) and Use(s)
		if name then
			local lines = s.when and head or release
			lines[#lines + 1] = fight and ("/castsequence reset=combat %s, null"):format(name) or ("/cast " .. name)
		end
	end
	-- Keep your own live enemy target, otherwise take the partner's (the tank's in dungeon mode)
	head[#head + 1] = "/assist [noharm][dead] " .. ns.AssistUnit()
	head[#head + 1] = "/stopmacro [noharm][dead]"
	head[#head + 1] = ((ns.STOP_FOLLOW .. (ATTACK[Class()] or "")):gsub("\n$", ""))
	for _, s in ipairs(Steps()) do
		local name = not s.once and Use(s)
		if name and Late(s) then
			late[#late + 1] = Click(s.id)
		elseif name then
			local line = BarSlot(s.id) and Click(s.id) or ("/cast " .. name)
			if OffGcd(s.id) then extras[#extras + 1] = line else leads[#leads + 1] = line end
		end
	end
	local downs = {}
	if #leads == 0 then leads[1] = false end
	for _, lead in ipairs(leads) do
		local lines = { table.concat(head, "\n") }
		if lead then lines[#lines + 1] = lead end
		for _, line in ipairs(extras) do lines[#lines + 1] = line end
		downs[#downs + 1] = table.concat(lines, "\n")
	end
	if #late > 0 then
		release[#release + 1] = "/stopmacro [noharm][dead]"
		for _, line in ipairs(late) do release[#release + 1] = line end
	end
	return downs, table.concat(release, "\n")
end

-- Health of the enemy the Rotation is about to attack: your live enemy target, otherwise the
-- partner's (the tank's in dungeon mode). nil = no such enemy, or health unreadable (secret
-- values in instances, or only a percentage: a maximum of 100).
local function TargetHealth()
	if not (UnitExists and UnitHealth and UnitHealthMax) then return nil end
	for _, unit in ipairs({ "target", ns.AssistUnit() .. "target" }) do
		if Val(UnitExists(unit)) and Val(UnitCanAttack("player", unit)) and not Val(UnitIsDead(unit)) then
			local hp, max = Val(UnitHealth(unit)), Val(UnitHealthMax(unit))
			if type(hp) == "number" and type(max) == "number" and max > 100 then return hp end
			return nil
		end
	end
end

-- Icon of the next action: a buff still to cast, otherwise the first attack of the list
local function Icon(aoe)
	local attack
	for _, s in ipairs(Steps()) do
		if Usable(s, aoe) then
			if s.once and needed[s.id] then return select(2, ns.SpellNameIcon(s.id)) or QUESTION end
			if not s.once and not attack then attack = s.id end
		end
	end
	return attack and select(2, ns.SpellNameIcon(attack)) or QUESTION
end

local modesDiffer = false -- the multi-target macros differ from the single-target ones (Update)

-- Multi-target mode, set by the Multi button (and the macros of the two modes differ)
local function MultiActive()
	if not multi then return false end
	return modesDiffer and button:GetAttribute("rot-mode") == "aoe"
end

local shownMulti = false

local function ShowMode()
	local on = MultiActive()
	button.glow:SetShown(on)
	multi.glow:SetShown(on)
	button.icon:SetTexture(Icon(on))
	-- In the chat too: tells whether the key or the voice command reached this client
	if on ~= shownMulti then
		shownMulti = on
		ns.Print(not on and "rotation : retour mono-cible."
			or InCombatLockdown() and "rotation : |cffff7020multi-cibles|r jusqu'a la fin du combat."
			or "rotation : |cffff7020multi-cibles|r pour le prochain combat, jusqu'a sa fin.")
	end
end

local function SetIfChanged(frame, key, value)
	if frame:GetAttribute(key) ~= value then frame:SetAttribute(key, value) end
end

local barButtons = {} -- [spellID] = hidden action button of a VIA_BAR spell

-- Out of combat only: the hidden buttons the macros /click, on the current slot of their spell
local function SetBarButtons()
	for _, s in ipairs(Steps()) do
		local slot = BarSlot(s.id)
		if slot then
			local b = barButtons[s.id]
			if not b then
				-- Not anchored: never drawn nor under the mouse, /click still reaches it (a /click typed
				-- in the chat cast Victory Rush through it, 2026-11-07)
				b = CreateFrame("Button", VIA_BAR[s.id][1], UIParent, "SecureActionButtonTemplate")
				b:SetAttribute("type", "action")
				-- /click sends a release (down = false): act on it whatever ActionButtonUseKeyDown says
				b:SetAttribute("useOnKeyDown", false)
				b:RegisterForClicks("AnyUp")
				barButtons[s.id] = b
			end
			SetIfChanged(b, "action", slot)
		end
	end
end

-- ended = true on PLAYER_REGEN_ENABLED: the multi-target mode stops with the fight
local function Update(fight, ended)
	if not button or InCombatLockdown() then return end
	SetBarButtons() -- before the macros that /click them
	-- Out of combat: the target of now (every 0.3 s); on PLAYER_REGEN_DISABLED: kept for the fight
	local hp = TargetHealth()
	local singles, release = Macro(fight, false, nil, hp)
	local aoes = Macro(fight, true, nil, hp)
	modesDiffer = table.concat(singles, "\0") ~= table.concat(aoes, "\0")
	-- The Multi button sets "rot-mode"; pressed out of combat, it is kept for the next fight
	local mode = not ended and button:GetAttribute("rot-mode") == "aoe" and "aoe" or "single"
	SetIfChanged(button, "rot-mode", mode)
	local changed = button:GetAttribute(RELEASE) ~= release
	-- No buff: "" (Blizzard's no-op value) for both, so the release does not fall back on the
	-- key-down macro ("macrotext")
	SetIfChanged(button, "*typerelease1", release ~= "" and "macro" or "")
	SetIfChanged(button, RELEASE, release)
	-- The key-down macros SNIPPET takes turns between ("-s<n>" / "-a<n>" button names)
	for i, text in ipairs(singles) do
		if button:GetAttribute("*macrotext-s" .. i) ~= text then button:SetAttribute("*macrotext-s" .. i, text); changed = true end
	end
	for i, text in ipairs(aoes) do
		if button:GetAttribute("*macrotext-a" .. i) ~= text then button:SetAttribute("*macrotext-a" .. i, text); changed = true end
	end
	SetIfChanged(button, "rot-count-s", #singles)
	SetIfChanged(button, "rot-count-a", #aoes)
	-- Plain macro, the first one of the mode: a press SNIPPET does not route (no secure handlers)
	SetIfChanged(button, "macrotext", (mode == "aoe" and aoes or singles)[1])
	if changed and panel and panel:IsShown() then RefreshPanel() end
	ShowMode()
end

local buffNames = {} -- [spellID] = { [name] = true }, the set ns.BuffRemaining expects

local function BuffLeft(id)
	local name = ns.SpellNameIcon(id)
	if not name then return nil end
	buffNames[id] = buffNames[id] or { [name] = true }
	return ns.BuffRemaining("player", buffNames[id])
end

-- Every 0.3 s, and with fight = true on PLAYER_REGEN_DISABLED, which fires before
-- InCombatLockdown() turns true: the last chance to set the macros for the fight.
local function Check(fight, ended)
	if not button then return end
	local lockdown = InCombatLockdown()
	for _, s in ipairs(Steps()) do
		if s.once and not s.off and ns.Known(s.id) then
			local left = BuffLeft(s.id) -- nil = unreadable (in combat on this client)
			if not lockdown then
				seen[s.id] = nil
				if left then needed[s.id] = left < REFRESH or nil end
			elseif left and left > 0 then
				seen[s.id], needed[s.id] = true, nil -- the macro is frozen: needed only drives the icon now
			elseif left == 0 and seen[s.id] then
				local key = s.id == BATTLE_SHOUT and GetBindingKey("CLICK DuoBoxBtnShout:LeftButton")
				ns.Alert("rotation" .. s.id, ns.SpellNameIcon(s.id) .. " termine !" .. (key and (" (" .. key .. ")") or ""),
					ns.SOUND_NOTICE, 20)
			end
		end
	end
	if lockdown then ShowMode() else Update(fight, ended) end
end

ns.UpdateRotation = Update -- partner change (UpdateBar), new spell learned
ns.RotationMacro = Macro
ns.RotationSteps = Steps

--------------------------------------------------------------------------------
-- Failures expected from a press (the rotation is spammed): Overpower without a
-- dodge, global cooldown, not enough rage / mana / energy, a stance spell in the
-- wrong stance, a press during a cast.
-- Hidden, silent and not relayed to the partner (DuoBox.lua asks too).
--------------------------------------------------------------------------------

local EXPECTED = {}
for _, g in ipairs({ "SPELL_FAILED_CASTER_AURASTATE", "SPELL_FAILED_NOT_READY", "ERR_ABILITY_COOLDOWN",
		"ERR_SPELL_COOLDOWN", "ERR_OUT_OF_RAGE", "SPELL_FAILED_NO_POWER", "ERR_OUT_OF_MANA", "ERR_OUT_OF_ENERGY",
		"ERR_OUT_OF_FOCUS", "SPELL_FAILED_SPELL_IN_PROGRESS" }) do
	if _G[g] then EXPECTED[_G[g]] = true end
end
-- "Must be in %s": the stance part matches anything
local before, after = (SPELL_FAILED_ONLY_SHAPESHIFT or ""):match("^(.-)%%s(.*)$")
local STANCE = before and ("^" .. before:gsub("%p", "%%%0") .. ".+" .. after:gsub("%p", "%%%0") .. "$")

function ns.IsRotationError(msg)
	msg = Val(msg)
	if not msg or GetTime() - press > 0.2 then return false end
	if EXPECTED[msg] then return true end
	return STANCE ~= nil and msg:find(STANCE) ~= nil
end

--------------------------------------------------------------------------------
-- List changes (the panel, and the tests)
--------------------------------------------------------------------------------

local function Changed()
	Check() -- out of combat: the macros now; in combat: after the fight
	if panel and panel:IsShown() then RefreshPanel() end
end
ns.RotationChanged = Changed -- DB.rotation replaced by a profile (Profiles.lua)

-- Spell from a spell ID, a spell link or a name from your spellbook
function ns.RotationFind(text)
	text = (text or ""):match("^%s*(.-)%s*$")
	local id = tonumber(text) or tonumber(text:match("|Hspell:(%d+)") or "")
	if id then return ns.SpellNameIcon(id) and id or nil end
	if text == "" then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(text)
		return info and info.spellID
	end
	return GetSpellInfo and select(7, GetSpellInfo(text)) or nil
end

-- Returns true, or false and the reason
function ns.RotationAdd(id)
	local name = id and ns.SpellNameIcon(id)
	if not name then return false, "sort introuvable (il doit etre dans ton grimoire)" end
	local steps = Steps()
	if #steps >= MAX_STEPS then return false, ("%d sorts au maximum"):format(MAX_STEPS) end
	for _, s in ipairs(steps) do
		if ns.SpellNameIcon(s.id) == name then return false, name .. " est deja dans la liste" end
	end
	steps[#steps + 1] = { id = id }
	Changed()
	return true
end

function ns.RotationMove(i, delta)
	local steps = Steps()
	local j = i + delta
	if not steps[i] or not steps[j] then return end
	steps[i], steps[j] = steps[j], steps[i]
	Changed()
end

function ns.RotationRemove(i)
	if table.remove(Steps(), i) then Changed() end
end

-- key: "once" (true = once per fight), "off" (true = disabled) or "when" (nil, "aoe", "single")
function ns.RotationSet(i, key, value)
	local s = Steps()[i]
	if not s then return end
	s[key] = value or nil
	Changed()
end

function ns.RotationReset()
	DB().rotation = nil
	Changed()
end

--------------------------------------------------------------------------------
-- Buttons, row 2 of the bar: among the warrior attacks (DuoBox.lua), after the
-- class buttons for the other classes (at login)
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	Check(event == "PLAYER_REGEN_DISABLED", event == "PLAYER_REGEN_ENABLED")
	if panel and panel:IsShown() then RefreshPanel() end -- "in combat" note
end)

local WHEN_LABEL = { aoe = "multi seulement", single = "mono seulement" }

local function StepLines(tt, aoe)
	local turns = #(Macro(false, aoe or false)) -- key-down macros taking turns in this mode
	for i, s in ipairs(Steps()) do
		local skipped = s.off or not ns.Known(s.id) or (aoe ~= nil and not Usable(s, aoe))
		local grey = skipped and 0.5 or 1
		local state = s.off and "desactive" or not ns.Known(s.id) and "pas appris"
			or (s.once and "1x par combat s'il manque" or "") .. (s.when and ((s.once and ", " or "") .. WHEN_LABEL[s.when]) or "")
		if turns > 1 and Usable(s, aoe or false) and not s.once and not OffGcd(s.id) and not Late(s) then
			state = state .. (state ~= "" and ", " or "") .. ("1 appui sur %d"):format(turns)
		end
		if VIA_BAR[s.id] and not s.once and not s.off then
			local slot = BarSlot(s.id)
			state = state .. (state ~= "" and ", " or "")
				.. (not slot and "a poser sur une barre d'action"
					or Late(s) and ("au relachement de la touche, par la barre d'action, emplacement " .. slot)
					or ("par la barre d'action, emplacement " .. slot))
		end
		if s.minHP and not s.off then
			state = state .. (state ~= "" and ", " or "") .. ("si la cible a %d PV ou plus au debut du combat"):format(s.minHP)
		end
		tt:AddLine(("%d. %s%s"):format(i, ns.SpellNameIcon(s.id) or ("#" .. s.id), state ~= "" and (" (" .. state .. ")") or ""),
			grey, grey, grey)
	end
end

local function Glow(b)
	local g = b:CreateTexture(nil, "OVERLAY")
	g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	g:SetBlendMode("ADD")
	g:SetVertexColor(1, 0.45, 0.1)
	g:SetSize(64, 64)
	g:SetPoint("CENTER")
	g:Hide()
	return g
end

function ns.SetupRotation(b, m)
	button, multi = b, m
	b:SetScript("PreClick", function() press = GetTime() end)
	-- Two macros per press (SecureActionButton_OnClick): with pressAndHoldAction, the key going
	-- down runs "type" / "macrotext", and the release runs "*typerelease1" / RELEASE (set by
	-- Update). Same for a mouse click on this addon button. SNIPPET renames the key-down left
	-- button "s<n>" / "a<n>", which reads "*macrotext-s<n>" / "*macrotext-a<n>"; without it, the
	-- left button is renamed "main", which has no attribute of its own and reads "macrotext".
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetAttribute("pressAndHoldAction", true)
	b:SetAttribute("*downbutton1", "main")
	if SecureHandlerWrapScript then
		local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
		SecureHandlerWrapScript(b, "OnClick", header, SNIPPET)
	end
	-- Right-click: a custom action type runs b.rotationpanel (SecureTemplates PerformAction)
	b:SetAttribute("type2", "rotationpanel")
	b.rotationpanel = function() ns.ToggleRotation() end
	b.extra = function(tt)
		StepLines(tt)
		if MultiActive() then tt:AddLine("Mode multi-cibles (bouton Multi)", 1, 0.45, 0.1) end
		tt:AddLine("Clic droit : choisir les sorts (/duo rotation)", 0.5, 0.8, 1)
	end
	b.glow = Glow(b)
	-- Multi: Blizzard's "attribute" action sets the Rotation's mode, in combat too (SNIPPET reads it)
	m:SetAttribute("attribute-frame", b)
	m:SetAttribute("attribute-name", "rot-mode")
	m:SetAttribute("attribute-value", "aoe")     -- left click / key: multi target
	m:SetAttribute("attribute-value2", "single") -- right click: back to single target
	m.extra = function(tt)
		tt:AddLine(not MultiActive() and "Sorts en multi-cibles :" or InCombatLockdown() and "Actif jusqu'a la fin du combat"
			or "Actif pour le prochain combat, jusqu'a sa fin", 1, 0.45, 0.1)
		StepLines(tt, true)
		tt:AddLine("Clic droit : retour mono-cible", 0.5, 0.8, 1)
	end
	m.glow = Glow(m)
	-- Hides and silences the expected failures (the voice is played by the same handler)
	local onError = UIErrorsFrame:GetScript("OnEvent")
	if onError then
		UIErrorsFrame:SetScript("OnEvent", function(self, event, ...)
			if event == "UI_ERROR_MESSAGE" then
				local a, msg = ...
				if ns.IsRotationError(type(a) == "string" and a or msg) then return end
			end
			return onError(self, event, ...)
		end)
	end
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	C_Timer.NewTicker(0.3, function() Check() end)
	Check()
end

-- Creates Rotation and Multi once (icons: the warrior's; the others take the first spell's)
function ns.BuildRotationButtons(icon, multiIcon)
	if button then return end
	local rot = ns.MakeButton("Rotation", "Rotation", icon or QUESTION, true, 2)
	rot:SetAttribute("type", "macro")
	rot.noDesat = true
	rot.hint = "Garde ta cible ennemie, sinon prend celle du partenaire\nArrete le follow, "
		.. (ATTACK[Class()] == "/startattack" and "attaque auto, " or ATTACK[Class()] and "familier a l'attaque, " or "")
		.. "puis le premier sort utilisable de la liste"
	-- Multi-target mode until the end of the fight (key or voice "multi"): Blizzard's secure
	-- "attribute" action writes the Rotation macro, in combat too (values set by Update)
	local m = ns.MakeButton("Multi", "Multi-cibles", multiIcon or "Interface\\Icons\\Ability_Whirlwind", true, 2)
	m:SetAttribute("type", "attribute")
	m.noDesat = true
	m.hint = "Passe le bouton Rotation en multi-cibles jusqu'a la fin du combat, ou du prochain s'il est appuye "
		.. "hors combat (ne lance rien)"
	ns.SetupRotation(rot, m)
end

--------------------------------------------------------------------------------
-- Panel: the list in priority order, add / remove / move / mode, macro preview
--------------------------------------------------------------------------------

local WIDTH, ROW_H = 570, 26
local TOP = -92 -- y of the first row, set below the help text
local rows = {}

local function Tip(frame, title, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function IconButton(parent, x, texture, title, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(18, 18)
	b:SetPoint("LEFT", x, 0)
	b:SetNormalTexture(texture .. "-Up")
	b:SetPushedTexture(texture .. "-Down")
	if texture:find("ScrollBar") then b:SetDisabledTexture(texture .. "-Disabled") end
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnClick", onClick)
	Tip(b, title, tip)
	return b
end

local function TextButton(parent, width, label, onClick, title, tip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	Tip(b, title or label, tip)
	return b
end

local function Report(ok, err)
	if not ok then ns.Print("rotation : " .. err) end
	return ok
end

local function AddFromCursor()
	local kind, _, _, spellID = GetCursorInfo()
	if not kind then return end
	ClearCursor()
	if kind == "spell" and spellID then
		Report(ns.RotationAdd(spellID))
	else
		ns.Print("rotation : seuls les sorts du grimoire peuvent etre ajoutes.")
	end
end

local MODE_TIP = "|cffffd040Chaque appui|r : un appui ne peut tenter qu'UN sort soumis au temps de recharge "
	.. "global ; ces sorts (Fulgurance, Execution, Slam...) sont donc tentes chacun son tour, un appui sur N, "
	.. "dans l'ordre de la liste. Le jeu saute ceux qui ne sont pas utilisables (Fulgurance sans esquive, "
	.. "Execution au-dessus de 20 %) : l'appui suivant tente le suivant. Les sorts hors temps de recharge "
	.. "global (Frappe heroique, Enchainement) sont tentes a chaque appui.\n"
	.. "|cffffd0401x par combat|r : pour tes buffs (Cri de guerre, Armure de givre...). Lance au relachement de la touche, juste apres les attaques, s'il manque, ou "
	.. "finit dans moins de 30 s, quand le combat commence ; une seule fois, car la macro ne peut pas changer "
	.. "pendant un combat. Le buff doit porter le nom du sort. S'il expire en combat : alerte."
local WHEN_TIP = "|cffffd040Toujours|r : en mono-cible et en multi-cibles.\n"
	.. "|cffffd040Multi seulement|r : seulement en mode multi-cibles, apres le bouton Multi (touche ou voix 'multi'), "
	.. "jusqu'a la fin du combat. Ex. : Coup de tonnerre, Explosion des arcanes.\n"
	.. "|cffffd040Mono seulement|r : saute en mode multi-cibles."
local HP_TIP = "Le sort n'est lance que si la cible a au moins ce nombre de points de vie quand le combat "
	.. "commence (vide : toujours). Decide une fois par combat, car la macro ne peut pas changer pendant un "
	.. "combat ; hors combat, d'apres ta cible du moment. Points de vie illisibles (donjon) : lance. "
	.. "Ex. : 850 pour Pourfendre, inutile sur un monstre qui meurt en quelques secondes. Entree pour valider."
local WHEN_TEXT = { aoe = "Multi seulement", single = "Mono seulement" }
local WHEN_NEXT = { aoe = "single", single = false }

local function CreateRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetSize(WIDTH - 30, 24)
	row:SetPoint("TOPLEFT", 15, TOP - (i - 1) * ROW_H)
	row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.num:SetPoint("LEFT", 0, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 20, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", 46, 0)
	row.name:SetWidth(140)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.mode = TextButton(row, 104, "", function() ns.RotationSet(i, "once", not Steps()[i].once) end, "Mode", MODE_TIP)
	row.mode:SetPoint("LEFT", 190, 0)
	-- Always -> multi only -> single only -> always
	row.when = TextButton(row, 104, "", function()
		local when = Steps()[i].when
		ns.RotationSet(i, "when", when == nil and "aoe" or WHEN_NEXT[when])
	end, "Cibles", WHEN_TIP)
	row.when:SetPoint("LEFT", 298, 0)
	row.on = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.on:SetSize(24, 24)
	row.on:SetPoint("LEFT", 405, 0)
	row.on:SetScript("OnClick", function(self) ns.RotationSet(i, "off", not self:GetChecked()) end)
	Tip(row.on, "Actif", "Decoche : le sort reste dans la liste sans etre lance.")
	row.up = IconButton(row, 431, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton", "Monter",
		"Priorite plus haute : tente avant les sorts du dessous.", function() ns.RotationMove(i, -1) end)
	row.down = IconButton(row, 449, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton", "Descendre", nil,
		function() ns.RotationMove(i, 1) end)
	row.remove = IconButton(row, 471, "Interface\\Buttons\\UI-GroupLoot-Pass", "Retirer", nil,
		function() ns.RotationRemove(i) end)
	-- Minimum health of the target as the fight starts (empty: always), saved when the box loses focus
	row.hp = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.hp:SetSize(40, 20)
	row.hp:SetPoint("LEFT", 500, 0)
	row.hp:SetAutoFocus(false)
	row.hp:SetNumeric(true)
	row.hp:SetMaxLetters(6)
	row.hp:SetScript("OnEnterPressed", row.hp.ClearFocus)
	row.hp:SetScript("OnEscapePressed", function(self)
		local s = Steps()[i]
		self:SetText(s and s.minHP and tostring(s.minHP) or "")
		self:ClearFocus()
	end)
	row.hp:SetScript("OnEditFocusLost", function(self)
		local n = tonumber(self:GetText())
		local s = Steps()[i]
		if s and s.minHP ~= (n and n > 0 and n or nil) then ns.RotationSet(i, "minHP", n and n > 0 and n or nil) end
	end)
	Tip(row.hp, "PV min de la cible", HP_TIP)
	rows[i] = row
end

local function Preview()
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetJustifyH("LEFT")
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetWidth(WIDTH / 2 - 30)
	text:SetJustifyH("LEFT")
	return title, text
end

local function CreatePanel()
	panel = CreateFrame("Frame", "DuoBoxRotation", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetSize(WIDTH, 300)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:SetClampedToScreen(true)
	if panel.SetBackdrop then
		panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	end
	tinsert(UISpecialFrames, "DuoBoxRotation") -- Escape closes the panel
	-- A spell dropped anywhere on the panel (or clicked onto it) is added
	panel:SetScript("OnReceiveDrag", AddFromCursor)
	panel:SetScript("OnMouseUp", AddFromCursor)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("DuoBox - Rotation")
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 16, -38)
	help:SetWidth(WIDTH - 32)
	help:SetJustifyH("LEFT")
	help:SetText("Un appui ne tente qu'un sort soumis au temps de recharge global : ces sorts passent chacun son "
		.. "tour, un appui sur N ; les sorts hors temps de recharge global (Frappe heroique) a chaque appui. "
		.. "Pour ajouter un sort : glisse-le depuis le grimoire sur ce panneau, ou tape son nom.\n"
		.. "Bouton Multi (touche ou voix 'multi') : mode multi-cibles jusqu'a la fin du combat (hors combat : "
		.. "pour le prochain) ; clic droit sur Multi : retour mono-cible. "
		.. "Une liste par classe : celle de tes autres classes ne change pas.")
	TOP = -38 - math.ceil(help:GetStringHeight()) - 10 - 14 -- room for the column title

	local hpTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hpTitle:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 15 + 500 - 4, TOP + 2)
	hpTitle:SetText("PV min")

	for i = 1, MAX_STEPS do CreateRow(i) end

	panel.drop = TextButton(panel, 150, "Glisse un sort ici", AddFromCursor, "Ajouter un sort",
		"Glisse un sort depuis le grimoire (P) et lache-le ici.")
	panel.drop:SetScript("OnReceiveDrag", AddFromCursor)

	local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	edit:SetSize(150, 20)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(80)
	local function AddTyped()
		local text = edit:GetText()
		if Report(ns.RotationAdd(ns.RotationFind(text))) then edit:SetText("") end
		edit:ClearFocus()
	end
	edit:SetScript("OnEnterPressed", AddTyped)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	Tip(edit, "Nom du sort", "Nom exact d'un sort de ton grimoire, puis Entree ou Ajouter.")
	panel.edit = edit
	panel.add = TextButton(panel, 86, "Ajouter", AddTyped)

	panel.reset = TextButton(panel, 110, "Par defaut", function() ns.RotationReset() end, "Liste par defaut",
		DEFAULT_TIP[Class()] or "Vide la liste.")
	panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.status:SetJustifyH("LEFT")
	panel.status:SetWidth(WIDTH - 150)

	panel.macroTitle, panel.macro = Preview()
	panel.aoeTitle, panel.aoeMacro = Preview()

	panel:SetScript("OnShow", RefreshPanel)
	panel:Hide()
end

local function Count(text)
	return #text > MAX_LEN and ("|cffff8040%d car.|r"):format(#text) or ("%d car."):format(#text)
end

RefreshPanel = function()
	local steps = Steps()
	for i, row in ipairs(rows) do
		local s = steps[i]
		row:SetShown(s ~= nil)
		if s then
			local name, icon = ns.SpellNameIcon(s.id)
			local known = ns.Known(s.id)
			local grey = s.off and 0.5 or 1
			row.num:SetText(i .. ".")
			row.icon:SetTexture(icon or QUESTION)
			row.icon:SetDesaturated(s.off or not known)
			-- A VIA_BAR spell is cast through its action-bar slot: none, no cast
			local noSlot = known and VIA_BAR[s.id] and not s.once and not BarSlot(s.id)
			row.name:SetText((name or ("#" .. s.id)) .. (not known and " |cff888888(pas appris)|r"
				or noSlot and " |cffff8040(a poser sur une barre)|r" or ""))
			row.name:SetTextColor(grey, grey, grey)
			row.mode:SetText(s.once and "1x par combat" or "Chaque appui")
			row.when:SetText(WHEN_TEXT[s.when] or "Toujours")
			row.on:SetChecked(not s.off)
			if not row.hp:HasFocus() then row.hp:SetText(s.minHP and tostring(s.minHP) or "") end
			row.up:SetEnabled(i > 1)
			row.down:SetEnabled(i < #steps)
		end
	end

	-- Controls below the last row
	local y = TOP - #steps * ROW_H - 6
	panel.drop:ClearAllPoints(); panel.drop:SetPoint("TOPLEFT", 15, y)
	panel.edit:ClearAllPoints(); panel.edit:SetPoint("TOPLEFT", 181, y - 1)
	panel.add:ClearAllPoints(); panel.add:SetPoint("TOPLEFT", 340, y)

	local singles, release = Macro(false, false)
	local aoes = Macro(false, true)
	-- The limit applies to each macro of a fight with every buff missing, the longest ones
	local fightSingles, fightRelease = Macro(true, false, true)
	local longest = #fightRelease
	for _, list in ipairs({ fightSingles, (Macro(true, true, true)) }) do
		for _, text in ipairs(list) do longest = math.max(longest, #text) end
	end
	-- Key-down macros taking turns, one under the other
	local function Show(list)
		return table.concat(list, "\n|cff999999- appui suivant -|r\n")
	end
	local function Title(label, list)
		local most = 0
		for _, text in ipairs(list) do most = math.max(most, #text) end
		return ("%s (%s%s)"):format(label, #list > 1 and (#list .. " en alternance, ") or "", Count(("x"):rep(most)))
	end
	local single, aoe = Show(singles), Show(aoes)
	y = y - 28
	panel.reset:ClearAllPoints(); panel.reset:SetPoint("TOPLEFT", 15, y)
	panel.status:ClearAllPoints(); panel.status:SetPoint("TOPLEFT", 135, y - 5)
	panel.status:SetText(InCombatLockdown() and "|cffffd040En combat : changements appliques a la fin du combat.|r"
		or #steps == 0 and ("|cff999999Liste vide : le bouton %s seulement.|r"):format(
			ATTACK[Class()] == "/startattack" and "attaque en auto" or ATTACK[Class()] and "envoie le familier" or "prend la cible")
		or longest > MAX_LEN and ("|cffff8040Macro de combat : %d car., le jeu n'en lit que %d : "
			.. "les derniers sorts sautent. Retire un sort.|r"):format(longest, MAX_LEN)
		or "")

	y = y - 32
	panel.macroTitle:ClearAllPoints(); panel.macroTitle:SetPoint("TOPLEFT", 16, y)
	panel.macroTitle:SetText(Title("Mono-cible, hors combat", singles))
	panel.macro:ClearAllPoints(); panel.macro:SetPoint("TOPLEFT", 20, y - 16)
	panel.macro:SetText(single .. (release ~= "" and ("\n|cff999999Au relachement de la touche :|r\n" .. release) or ""))
	panel.aoeTitle:ClearAllPoints(); panel.aoeTitle:SetPoint("TOPLEFT", WIDTH / 2 + 6, y)
	panel.aoeTitle:SetText(Title("Multi-cibles", aoes))
	panel.aoeMacro:ClearAllPoints(); panel.aoeMacro:SetPoint("TOPLEFT", WIDTH / 2 + 10, y - 16)
	panel.aoeMacro:SetText(aoe ~= single and aoe or "|cff999999Identique : aucun sort marque Multi ou Mono seulement.|r")
	local height = math.max(panel.macro:GetStringHeight(), panel.aoeMacro:GetStringHeight())
	panel:SetHeight(-(y - 16) + height + 18)
end

function ns.ToggleRotation()
	if not button then
		ns.Print("le bouton Rotation n'est pas encore cree (attends la fin du chargement).")
		return
	end
	if not panel then CreatePanel() end
	panel:SetShown(not panel:IsShown())
end
