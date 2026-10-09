--------------------------------------------------------------------------------
-- DuoBox / melee light: a big green / red light on the partner's screen (the
-- priest) while the warrior (or rogue) fights: green = in melee range and
-- attacking, red = too far, facing the wrong way, or no enemy target.
-- Melee side: range = "is the target in range of Heroic Strike" (asked every
-- 0.2 s). The game exposes no facing toward a mob: facing comes from the
-- "facing the wrong way" error of a failed swing or spell, so it shows at the
-- first failed attack and clears with a success, a new target, or after a few s.
-- The state goes to the partner as "ML:<code>" (on change, then every 1.5 s).
-- Kept out of DuoBox.lua: its main chunk is close to Lua 5.1's 200 locals.
--------------------------------------------------------------------------------

local _, ns = ...

local MELEE_SPELL = { WARRIOR = 78, ROGUE = 1752 } -- Heroic Strike, Sinister Strike: melee range
local FACING_HOLD = 4   -- s: longer than a slow weapon swing (the error comes back on each swing)
local FAR_HOLD = 1.5    -- s after a "too far" error
local STALE = 4         -- s without news: the light hides (partner gone, disconnected)
local STATES = {
	G = { 0.1, 0.85, 0.1, "OK" },
	R = { 0.9, 0.1, 0.1, "TROP LOIN" },
	F = { 0.9, 0.1, 0.1, "MAL ORIENTE" },
	T = { 0.9, 0.1, 0.1, "PAS DE CIBLE" },
}

local function DB() return ns.GetDB() end

local function Val(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function Enabled()
	local db = DB()
	return db ~= nil and db.meleeLight ~= false
end

--------------------------------------------------------------------------------
-- Melee side: compute and send
--------------------------------------------------------------------------------

local facingTime, farTime = 0, 0
local sentCode, sentTime = nil, 0

local FACING_ERRORS, FAR_ERRORS = {}, {}
for _, g in ipairs({ "ERR_BADATTACKFACING", "SPELL_FAILED_UNIT_NOT_INFRONT" }) do
	if _G[g] then FACING_ERRORS[_G[g]] = true end
end
for _, g in ipairs({ "ERR_BADATTACKPOS" }) do -- "You are too far away!" (auto-attack)
	if _G[g] then FAR_ERRORS[_G[g]] = true end
end

local function InRange(spellID)
	local name = spellID and ns.SpellNameIcon(spellID)
	if not name or not ns.Known(spellID) then return nil end
	local inRange
	if C_Spell and C_Spell.IsSpellInRange then
		inRange = Val(C_Spell.IsSpellInRange(name, "target"))
	elseif IsSpellInRange then
		local r = Val(IsSpellInRange(name, "target"))
		if r ~= nil then inRange = r == 1 end
	end
	return inRange -- nil = unknown (no range red then)
end

-- "N" = out of combat (light hidden), otherwise a STATES key
local function Code(class)
	if not Val(UnitAffectingCombat("player")) then return "N" end
	if not Val(UnitExists("target")) or Val(UnitIsDead("target")) then return "T" end
	local attack = UnitCanAttack("player", "target")
	if attack ~= nil and Val(attack) == nil then attack = true end -- secret in an instance: assume an enemy
	if not attack then return "T" end
	local now = GetTime()
	if InRange(MELEE_SPELL[class]) == false or now - farTime < FAR_HOLD then return "R" end
	if now - facingTime < FACING_HOLD then return "F" end
	return "G"
end

local function SendTick(class)
	if not Enabled() or not ns.PartnerUnit() then return end
	local code, now = Code(class), GetTime()
	if (code ~= sentCode and now - sentTime >= 0.2) or (code ~= "N" and now - sentTime > 1.5) then
		ns.SendComm("ML:" .. code)
		sentCode, sentTime = code, now
	end
end

--------------------------------------------------------------------------------
-- Partner side (the priest): the light
--------------------------------------------------------------------------------

local light = CreateFrame("Frame", "DuoBoxMeleeLight", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
light:SetSize(90, 90)
light:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
light:SetMovable(true)
light:SetClampedToScreen(true)
light:EnableMouse(false) -- mouse only in move mode (/duo move)
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
light.name:SetPoint("TOP", 0, -10)
light.text = light:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
light.text:SetPoint("CENTER", 0, -6)
light.text:SetWidth(84)
light:Hide()

local shownCode, receivedTime = nil, 0

local function Show(code, name)
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
		Show(shownCode, unit and Val(UnitName(unit)))
	else
		light:Hide()
	end
end

local function DisplayTick()
	if ns.IsMoveMode() then
		light:EnableMouse(true)
		Show("G", "Voyant du guerrier")
		light.text:SetText("Glisse-moi")
		return
	end
	light:EnableMouse(false)
	if not Enabled() or not shownCode or GetTime() - receivedTime > STALE then
		shownCode = nil
		light:Hide()
	end
end

function ns.RefreshMeleeLight()
	if not Enabled() then light:Hide() end
	DisplayTick()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

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
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "PLAYER_TARGET_CHANGED" then
		facingTime = 0 -- a spell landed, or a new target: the facing error is old news
	elseif event == "PLAYER_LOGIN" then
		local _, class = UnitClass("player")
		if MELEE_SPELL[class] then
			ev:RegisterEvent("UI_ERROR_MESSAGE")
			ev:RegisterEvent("PLAYER_TARGET_CHANGED")
			pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
			C_Timer.NewTicker(0.2, function() SendTick(class) end)
		end
		C_Timer.NewTicker(0.5, DisplayTick)
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
