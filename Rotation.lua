--------------------------------------------------------------------------------
-- DuoBox / warrior Rotation button: 1 press = 1 action, chosen by the game.
-- Its spells (DB.rotation, per character) are edited in the panel opened by
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
-- Kept out of DuoBox.lua: its main chunk is close to Lua 5.1's 200 locals.
--------------------------------------------------------------------------------

local _, ns = ...

local REFRESH = 30 -- seconds left under which a "once per fight" buff counts as missing
local MAX_STEPS = 10
local BATTLE_SHOUT = 6673
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Battle Shout once per fight, Overpower (after a dodge), Thunder Clap in multi-target mode, Heroic Strike
local DEFAULT = { { id = BATTLE_SHOUT, once = true }, { id = 7384 }, { id = 6343, when = "aoe" }, { id = 78 } }

local function DB() return ns.GetDB() end

local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local button        -- DuoBoxBtnRotation, given by ns.SetupRotation (warrior only)
local multi         -- DuoBoxBtnMulti: sets the Rotation macro to the multi-target one
local needed = {}   -- [spellID] = true: "once per fight" buff to cast (decided out of combat)
local seen = {}     -- [spellID] = true: buff seen during this fight (alert when it ends)
local press = 0     -- GetTime() of the last press
local panel, RefreshPanel -- created on first open

-- Steps of this character: { id = spellID, once = true (once per fight), off = true (disabled),
-- when = nil (always) / "aoe" (multi-target mode only) / "single" (single target only) }
local function Steps()
	local db = DB()
	if type(db.rotation) ~= "table" then
		db.rotation = {}
		for i, s in ipairs(DEFAULT) do db.rotation[i] = { id = s.id, once = s.once, when = s.when } end
	end
	return db.rotation
end

-- Name of the step's spell when it goes in the macro of that mode: enabled, learned, right mode
local function Usable(s, aoe)
	if s.when and (s.when == "aoe") ~= (aoe or false) then return nil end
	return not s.off and ns.Known(s.id) and (ns.SpellNameIcon(s.id)) or nil
end

-- fight = true: built on PLAYER_REGEN_DISABLED and kept for the whole fight. A plain /cast of
-- a buff would then fire on every press: /castsequence casts it once, and "null" (no such
-- spell) holds the sequence until reset=combat, at the end of the fight. Both modes share
-- the same line, so switching to multi target does not shout twice.
local function Macro(fight, aoe)
	local lines = {}
	for _, s in ipairs(Steps()) do
		local name = s.once and needed[s.id] and Usable(s, aoe)
		if name then
			lines[#lines + 1] = fight and ("/castsequence reset=combat %s, null"):format(name) or ("/cast " .. name)
		end
	end
	-- Keep your own live enemy target, otherwise take the partner's (the tank's in dungeon mode)
	lines[#lines + 1] = "/assist [noharm][dead] " .. ns.AssistUnit()
	lines[#lines + 1] = "/stopmacro [noharm][dead]"
	lines[#lines + 1] = ns.STOP_FOLLOW .. "/startattack"
	for _, s in ipairs(Steps()) do
		local name = not s.once and Usable(s, aoe)
		if name then lines[#lines + 1] = "/cast " .. name end
	end
	return table.concat(lines, "\n")
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

-- The Rotation macro is the multi-target one the Multi button set (and the two differ)
local function MultiActive()
	if not multi then return false end
	local aoe = multi:GetAttribute("attribute-value")
	return aoe ~= multi:GetAttribute("attribute-value2") and button:GetAttribute("macrotext") == aoe
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

-- ended = true on PLAYER_REGEN_ENABLED: the multi-target mode stops with the fight
local function Update(fight, ended)
	if not button or InCombatLockdown() then return end
	-- Multi pressed out of combat: kept for the next fight, until its end
	local armed = not ended and MultiActive()
	local single, aoe = Macro(fight, false), Macro(fight, true)
	local text = armed and aoe or single
	-- Compared with the attribute, not a copy: the Multi button changes it
	if button:GetAttribute("macrotext") ~= text then
		button:SetAttribute("macrotext", text)
		if panel and panel:IsShown() then RefreshPanel() end
	end
	SetIfChanged(multi, "attribute-value", aoe)     -- left click / key: multi target
	SetIfChanged(multi, "attribute-value2", single) -- right click: back to single target
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
-- dodge, global cooldown, not enough rage, a stance spell in the wrong stance.
-- Hidden, silent and not relayed to the partner (DuoBox.lua asks too).
--------------------------------------------------------------------------------

local EXPECTED = {}
for _, g in ipairs({ "SPELL_FAILED_CASTER_AURASTATE", "SPELL_FAILED_NOT_READY", "ERR_ABILITY_COOLDOWN",
		"ERR_SPELL_COOLDOWN", "ERR_OUT_OF_RAGE", "SPELL_FAILED_NO_POWER" }) do
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
-- Buttons (created by DuoBox.lua in the warrior row of the bar)
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	Check(event == "PLAYER_REGEN_DISABLED", event == "PLAYER_REGEN_ENABLED")
	if panel and panel:IsShown() then RefreshPanel() end -- "in combat" note
end)

local WHEN_LABEL = { aoe = "multi seulement", single = "mono seulement" }

local function StepLines(tt, aoe)
	for i, s in ipairs(Steps()) do
		local skipped = s.off or not ns.Known(s.id) or (aoe ~= nil and not Usable(s, aoe))
		local grey = skipped and 0.5 or 1
		local state = s.off and "desactive" or not ns.Known(s.id) and "pas appris"
			or (s.once and "1x par combat s'il manque" or "") .. (s.when and ((s.once and ", " or "") .. WHEN_LABEL[s.when]) or "")
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
	-- Right-click: a custom action type runs b.rotationpanel (SecureTemplates PerformAction)
	b:SetAttribute("type2", "rotationpanel")
	b.rotationpanel = function() ns.ToggleRotation() end
	b.extra = function(tt)
		StepLines(tt)
		if MultiActive() then tt:AddLine("Mode multi-cibles (bouton Multi)", 1, 0.45, 0.1) end
		tt:AddLine("Clic droit : choisir les sorts (/duo rotation)", 0.5, 0.8, 1)
	end
	b.glow = Glow(b)
	-- Multi: Blizzard's "attribute" action writes the Rotation macro, in combat too
	m:SetAttribute("attribute-frame", b)
	m:SetAttribute("attribute-name", "macrotext")
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

--------------------------------------------------------------------------------
-- Panel: the list in priority order, add / remove / move / mode, macro preview
--------------------------------------------------------------------------------

local WIDTH, ROW_H = 520, 26
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

local MODE_TIP = "|cffffd040Chaque appui|r : tente le sort a chaque appui ; le jeu le saute s'il n'est pas "
	.. "utilisable (Fulgurance apres une esquive, Execution sous 20 %, recharge, rage, posture).\n"
	.. "|cffffd0401x par combat|r : pour tes buffs (Cri de guerre). Lance avant les attaques s'il manque, ou "
	.. "finit dans moins de 30 s, quand le combat commence ; une seule fois, car la macro ne peut pas changer "
	.. "pendant un combat. Le buff doit porter le nom du sort. S'il expire en combat : alerte."
local WHEN_TIP = "|cffffd040Toujours|r : en mono-cible et en multi-cibles.\n"
	.. "|cffffd040Multi seulement|r : seulement en mode multi-cibles, apres le bouton Multi (touche ou voix 'multi'), "
	.. "jusqu'a la fin du combat. Ex. : Coup de tonnerre.\n"
	.. "|cffffd040Mono seulement|r : saute en mode multi-cibles."
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
	help:SetText("A chaque appui, le jeu lance le premier sort utilisable, de haut en bas. "
		.. "Pour ajouter un sort : glisse-le depuis le grimoire sur ce panneau, ou tape son nom.\n"
		.. "Bouton Multi (touche ou voix 'multi') : mode multi-cibles jusqu'a la fin du combat (hors combat : "
		.. "pour le prochain) ; clic droit sur Multi : retour mono-cible. Place les sorts multi au-dessus de "
		.. "Frappe heroique, sinon elle prend la rage.")
	TOP = -38 - math.ceil(help:GetStringHeight()) - 10

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
		"Cri de guerre (1x par combat), Fulgurance, Coup de tonnerre (multi seulement), Frappe heroique.")
	panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.status:SetJustifyH("LEFT")
	panel.status:SetWidth(WIDTH - 150)

	panel.macroTitle, panel.macro = Preview()
	panel.aoeTitle, panel.aoeMacro = Preview()

	panel:SetScript("OnShow", RefreshPanel)
	panel:Hide()
end

local function Count(text)
	return #text > 255 and ("|cffff8040%d car.|r"):format(#text) or ("%d car."):format(#text)
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
			row.name:SetText((name or ("#" .. s.id)) .. (known and "" or " |cff888888(pas appris)|r"))
			row.name:SetTextColor(grey, grey, grey)
			row.mode:SetText(s.once and "1x par combat" or "Chaque appui")
			row.when:SetText(WHEN_TEXT[s.when] or "Toujours")
			row.on:SetChecked(not s.off)
			row.up:SetEnabled(i > 1)
			row.down:SetEnabled(i < #steps)
		end
	end

	-- Controls below the last row
	local y = TOP - #steps * ROW_H - 6
	panel.drop:ClearAllPoints(); panel.drop:SetPoint("TOPLEFT", 15, y)
	panel.edit:ClearAllPoints(); panel.edit:SetPoint("TOPLEFT", 181, y - 1)
	panel.add:ClearAllPoints(); panel.add:SetPoint("TOPLEFT", 340, y)

	local single, aoe = Macro(false, false), Macro(false, true)
	y = y - 28
	panel.reset:ClearAllPoints(); panel.reset:SetPoint("TOPLEFT", 15, y)
	panel.status:ClearAllPoints(); panel.status:SetPoint("TOPLEFT", 135, y - 5)
	panel.status:SetText(InCombatLockdown() and "|cffffd040En combat : changements appliques a la fin du combat.|r"
		or #steps == 0 and "|cff999999Liste vide : le bouton attaque seulement en auto.|r"
		or math.max(#single, #aoe) > 255 and "|cffff8040Macro de plus de 255 caracteres : verifie en jeu que les derniers sorts partent.|r"
		or "")

	y = y - 32
	panel.macroTitle:ClearAllPoints(); panel.macroTitle:SetPoint("TOPLEFT", 16, y)
	panel.macroTitle:SetText(("Macro mono-cible, hors combat (%s)"):format(Count(single)))
	panel.macro:ClearAllPoints(); panel.macro:SetPoint("TOPLEFT", 20, y - 16)
	panel.macro:SetText(single)
	panel.aoeTitle:ClearAllPoints(); panel.aoeTitle:SetPoint("TOPLEFT", WIDTH / 2 + 6, y)
	panel.aoeTitle:SetText(("Macro multi-cibles (%s)"):format(Count(aoe)))
	panel.aoeMacro:ClearAllPoints(); panel.aoeMacro:SetPoint("TOPLEFT", WIDTH / 2 + 10, y - 16)
	panel.aoeMacro:SetText(aoe ~= single and aoe or "|cff999999Identique : aucun sort marque Multi ou Mono seulement.|r")
	local height = math.max(panel.macro:GetStringHeight(), panel.aoeMacro:GetStringHeight())
	panel:SetHeight(-(y - 16) + height + 18)
end

function ns.ToggleRotation()
	if not button then
		ns.Print("le bouton Rotation est reserve au guerrier.")
		return
	end
	if not panel then CreatePanel() end
	panel:SetShown(not panel:IsShown())
end
