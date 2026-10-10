--------------------------------------------------------------------------------
-- DuoBox / melee light: a big green / red light on the partner's screen (the
-- priest) while the warrior (or rogue) fights: green = attacking its target in
-- melee range, red = too far, facing the wrong way, not attacking, or no enemy
-- target.
-- Melee side, every 0.2 s:
--   * range: the learned rank of Heroic Strike in the spellbook (ranks replace
--     each other on WoW Forever), asked by spell ID, then by spellbook slot,
--     then by name; plus the "out of range" / "too far" errors,
--   * facing: the game exposes no facing toward a mob, so it comes from the
--     "facing the wrong way" error of a failed swing or spell: red from the
--     first failed attack until a harmful spell lands, a new target, or 4 s,
--   * auto-attack: Attack (6603) not active while in combat.
-- The state goes to the partner as "ML:<code>" (on change, then every 1.5 s).
-- /duo move: drag the light, bottom-right corner to resize. /duo light debug:
-- what the client answers. Kept out of DuoBox.lua (Lua 5.1's 200 locals).
--------------------------------------------------------------------------------

local _, ns = ...

local MELEE_SPELL = { WARRIOR = 78, ROGUE = 1752 } -- Heroic Strike, Sinister Strike: melee range
local ATTACK = 6603
local FACING_HOLD = 4   -- s: longer than a slow weapon swing (the error comes back on each swing)
local FAR_HOLD = 1.5    -- s after an "out of range" error
local STALE = 4         -- s without news: the light hides (partner gone, disconnected)
local SIZE = 90         -- default size
local STATES = {
	G = { 0.1, 0.85, 0.1, "OK" },
	R = { 0.9, 0.1, 0.1, "TROP LOIN" },
	F = { 0.9, 0.1, 0.1, "MAL ORIENTE" },
	A = { 0.9, 0.1, 0.1, "N'ATTAQUE PAS" },
	T = { 0.9, 0.1, 0.1, "PAS DE CIBLE" },
}

local function DB() return ns.GetDB() end

local function Val(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Debug text of a value the client may hide
local function Show(v)
	if v == nil then return "nil" end
	if issecretvalue and issecretvalue(v) then return "SECRET" end
	return tostring(v)
end

local function Enabled()
	local db = DB()
	return db ~= nil and db.meleeLight ~= false
end

--------------------------------------------------------------------------------
-- Melee side: compute and send
--------------------------------------------------------------------------------

local class
local facingTime, farTime = 0, 0
local sentCode, sentTime = nil, 0

local FACING_ERRORS, FAR_ERRORS = {}, {}
for _, g in ipairs({ "ERR_BADATTACKFACING", "SPELL_FAILED_UNIT_NOT_INFRONT" }) do
	if _G[g] then FACING_ERRORS[_G[g]] = true end
end
-- "You are too far away!" (auto-attack), "Out of range" (spells)
for _, g in ipairs({ "ERR_BADATTACKPOS", "SPELL_FAILED_OUT_OF_RANGE", "ERR_OUT_OF_RANGE" }) do
	if _G[g] then FAR_ERRORS[_G[g]] = true end
end

-- Each range source: name, function(name, slot, bank, rankID) -> raw answer (true / false / 1 / 0 / nil)
local RANGE_SOURCES = {
	{ "par ID", function(_, _, _, rankID)
		if rankID and C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(rankID, "target") end
	end },
	{ "grimoire", function(_, slot, bank)
		if slot and C_SpellBook.IsSpellBookItemInRange then return C_SpellBook.IsSpellBookItemInRange(slot, bank, "target") end
	end },
	{ "par nom", function(name)
		if C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(name, "target") end
		if IsSpellInRange then return IsSpellInRange(name, "target") end
	end },
}

-- Name, spellbook slot and bank, and spell ID of the learned rank of the melee spell
local function MeleeSpell()
	local id = MELEE_SPELL[class]
	local name = id and ns.Known(id) and ns.SpellNameIcon(id)
	if not name then return nil end
	local slot, bank, rankID
	if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
		slot, bank = C_SpellBook.FindSpellBookSlotForSpell(name)
		if slot then rankID = select(3, C_SpellBook.GetSpellBookItemType(slot, bank)) end
	end
	return name, slot, bank, rankID
end

-- true / false, or nil when no source can tell (then no range red)
local function InRange()
	local name, slot, bank, rankID = MeleeSpell()
	if not name then return nil end
	for _, source in ipairs(RANGE_SOURCES) do
		local r = Val(source[2](name, slot, bank, rankID))
		if r ~= nil then return r == true or r == 1 end
	end
	return nil
end

-- Raw answer for Attack (6603): true while auto-attack runs
local function AttackRaw()
	local f = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
	if f then return f(ATTACK) end
end

local function Attacking()
	return Val(AttackRaw())
end

-- "N" = out of combat (light hidden), otherwise a STATES key
local function Code()
	if not Val(UnitAffectingCombat("player")) then return "N" end
	if not Val(UnitExists("target")) or Val(UnitIsDead("target")) then return "T" end
	local attack = UnitCanAttack("player", "target")
	if attack ~= nil and Val(attack) == nil then attack = true end -- secret in an instance: assume an enemy
	if not attack then return "T" end
	local now = GetTime()
	if InRange() == false or now - farTime < FAR_HOLD then return "R" end
	if now - facingTime < FACING_HOLD then return "F" end
	if Attacking() == false then return "A" end
	return "G"
end

local function SendTick()
	if not Enabled() or not ns.PartnerUnit() then return end
	local code, now = Code(), GetTime()
	if (code ~= sentCode and now - sentTime >= 0.2) or (code ~= "N" and now - sentTime > 1.5) then
		ns.SendComm("ML:" .. code)
		sentCode, sentTime = code, now
	end
end

--------------------------------------------------------------------------------
-- Partner side (the priest): the light
--------------------------------------------------------------------------------

local light = CreateFrame("Frame", "DuoBoxMeleeLight", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
light:SetSize(SIZE, SIZE)
light:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
light:SetMovable(true)
light:SetResizable(true)
if light.SetResizeBounds then
	light:SetResizeBounds(40, 40, 400, 400)
elseif light.SetMinResize then
	light:SetMinResize(40, 40)
	light:SetMaxResize(400, 400)
end
light:SetClampedToScreen(true)
light:EnableMouse(false) -- mouse only in move mode (/duo move): it must not block clicks in combat
light:RegisterForDrag("LeftButton")
light:SetScript("OnDragStart", light.StartMoving)
light:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self:SetUserPlaced(true) end)
if light.SetBackdrop then
	light:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 } })
end
light.color = light:CreateTexture(nil, "BACKGROUND")
light.color:SetPoint("TOPLEFT", 4, -4)
light.color:SetPoint("BOTTOMRIGHT", -4, 4)
light.name = light:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
light.name:SetPoint("TOP", 0, -8)
light.text = light:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
light.text:SetPoint("CENTER", 0, -4)
light:Hide()

-- Texts follow the size
local function FitTexts(size)
	local font = GameFontNormalLarge and GameFontNormalLarge:GetFont()
	if font then
		light.text:SetFont(font, math.max(10, math.floor(size * 0.16)), "OUTLINE")
		light.name:SetFont(font, math.max(8, math.floor(size * 0.11)), "OUTLINE")
	end
	light.text:SetWidth(size - 8)
	light.name:SetWidth(size - 8)
end
light:SetScript("OnSizeChanged", function(self, w) FitTexts(w) end)

-- Resize grip (bottom-right corner), shown in move mode; the light stays square
local grip = CreateFrame("Button", nil, light)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() light:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function()
	light:StopMovingOrSizing()
	local size = math.floor(math.max(light:GetWidth(), light:GetHeight()) + 0.5)
	light:SetSize(size, size)
	light:SetUserPlaced(true)
	DB().meleeLightSize = size
end)
grip:Hide()

local shownCode, receivedTime = nil, 0

local function Paint(code, name)
	local s = STATES[code]
	light.color:SetColorTexture(s[1], s[2], s[3], 0.85)
	light.text:SetText(s[4])
	light.text:SetTextColor(1, 1, 1)
	light.name:SetText(name or "")
	light:Show()
end

local function OnMessage(code)
	receivedTime = GetTime()
	shownCode = STATES[code] and code or nil
	if not Enabled() or ns.IsMoveMode() then return end
	if shownCode then
		local unit = ns.PartnerUnit()
		Paint(shownCode, unit and Val(UnitName(unit)))
	else
		light:Hide()
	end
end

local function DisplayTick()
	local moving = ns.IsMoveMode()
	light:EnableMouse(moving)
	grip:SetShown(moving)
	if moving then
		Paint("G", "Voyant du guerrier")
		light.text:SetText("Glisse-moi")
		return
	end
	if not Enabled() or not shownCode or GetTime() - receivedTime > STALE then
		shownCode = nil
		light:Hide()
	end
end

function ns.RefreshMeleeLight()
	if not Enabled() then light:Hide() end
	DisplayTick()
end

-- /duo light debug|reset
function ns.MeleeLightCommand(sub)
	if sub == "reset" then
		DB().meleeLightSize = nil
		light:ClearAllPoints()
		light:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
		light:SetSize(SIZE, SIZE)
		light:SetUserPlaced(false)
		ns.Print("voyant : position et taille par defaut.")
		return
	end
	if not class then
		ns.Print(("voyant : dernier etat recu = %s%s."):format(tostring(shownCode),
			receivedTime > 0 and (" il y a %.1f s"):format(GetTime() - receivedTime) or " (jamais)"))
		return
	end
	local now = GetTime()
	ns.Print(("voyant : combat=%s cible=%s ennemie=%s morte=%s attaque auto=%s"):format(Show(UnitAffectingCombat("player")),
		Show(UnitExists("target")), Show(UnitCanAttack("player", "target")), Show(UnitIsDead("target")), Show(AttackRaw())))
	local name, slot, bank, rankID = MeleeSpell()
	local parts = {}
	for _, source in ipairs(RANGE_SOURCES) do
		parts[#parts + 1] = source[1] .. "=" .. (name and Show(source[2](name, slot, bank, rankID)) or "-")
	end
	ns.Print(("portee (%s, emplacement %s, rang %s) : %s"):format(tostring(name), tostring(slot), tostring(rankID),
		table.concat(parts, " ")))
	ns.Print(("erreurs : orientation %s, trop loin %s ; etat %s, envoye : %s"):format(
		facingTime > 0 and ("il y a %.1f s"):format(now - facingTime) or "jamais",
		farTime > 0 and ("il y a %.1f s"):format(now - farTime) or "jamais",
		Code(), ns.PartnerUnit() and tostring(sentCode) or "rien (pas de partenaire dans le groupe)"))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function Harmful(spellID)
	if not spellID then return false end
	if C_Spell and C_Spell.IsSpellHarmful then return Val(C_Spell.IsSpellHarmful(spellID)) == true end
	local name = ns.SpellNameIcon(spellID)
	return name ~= nil and IsHarmfulSpell ~= nil and Val(IsHarmfulSpell(name)) and true or false
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, body, channel, sender = ...
		if prefix ~= "DUOBOX" or channel ~= "PARTY" then return end
		body = ns.FromPartner(body, sender)
		local code = type(body) == "string" and body:match("^ML:(%u)$")
		if code then OnMessage(code) end
	elseif event == "UI_ERROR_MESSAGE" then
		-- Depending on the version: (messageType, message) or (message)
		local a, b = ...
		local msg = Val(type(a) == "string" and a or b)
		if FACING_ERRORS[msg] then facingTime = GetTime() end
		if FAR_ERRORS[msg] then farTime = GetTime() end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- A harmful spell landed (Heroic Strike on the swing, Rend...): facing is fine again.
		-- Battle Shout or Bloodrage need no facing: they prove nothing.
		local _, _, spellID = ...
		if Harmful(Val(spellID)) then facingTime = 0 end
	elseif event == "PLAYER_TARGET_CHANGED" then
		facingTime, farTime = 0, 0 -- errors about the previous target
	elseif event == "PLAYER_LOGIN" then
		local size = DB() and DB().meleeLightSize
		if size then light:SetSize(size, size) end
		FitTexts(light:GetWidth())
		local _, myClass = UnitClass("player")
		if MELEE_SPELL[myClass] then
			class = myClass
			ev:RegisterEvent("UI_ERROR_MESSAGE")
			ev:RegisterEvent("PLAYER_TARGET_CHANGED")
			pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
			C_Timer.NewTicker(0.2, SendTick)
		end
		C_Timer.NewTicker(0.5, DisplayTick)
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
