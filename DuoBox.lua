--------------------------------------------------------------------------------
-- DuoBox: helper for "alt+tab" duo-boxing (1 key = 1 action on 1 client).
-- The addon NEVER sends an action to the other client. It only:
--   * alerts (sound + taskbar flash + text) the background window
--     when you need to switch to it,
--   * accepts invites / quests / resurrections from the partner,
--   * shares accepted quests,
--   * creates class macros (/duo macros).
--------------------------------------------------------------------------------

local ADDON = ...
local PREFIX = "DUOBOX"

local defaults = {
	partner     = nil,    -- partner character name (without realm)
	role        = nil,    -- "heal" or "dps" (auto: PRIEST = heal)
	hpPartner   = 50,     -- partner health % that triggers the alert
	hpPet       = 35,     -- partner pet health % (healer side)
	manaPartner = 20,     -- partner mana % (dps side)
	sound       = true,
	flash       = true,
	autoInvite  = true,
	autoQuest   = true,
	autoShare   = true,
	autoRez     = true,
	autoNpc     = true,   -- D-Talk macro: accept / turn in the NPC's quests
	frame       = true,
	bar         = true,   -- Follow / Target / Trade button bar
	barScale    = 1,      -- bar scale (/duo scale)
	castbar     = true,   -- priest cast bar + errors on the hunter's screen
	facing      = true,   -- priest facing indicator
	facingInvert = false, -- swap left/right if the direction is wrong
	facingDist  = 25,     -- estimated hunter -> target distance (yards)
}

local DB
local f = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff8ee6deDuoBox|r: " .. msg)
end

-- Some values can be "secret" on this client: they are ignored.
local function Val(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function Pct(cur, max)
	cur, max = Val(cur), Val(max)
	if not cur or not max or max == 0 then return nil end
	return math.floor(cur * 100 / max)
end

-- Comparison key: first name only, lowercase.
-- Handles "Multi", "Multi Boxing" (first + last name) and "Multi-Realm".
local function ShortName(name)
	name = Val(name)
	if not name or name == "" then return nil end
	return (name:match("^[^%s%-]+") or name):lower()
end

local function IsPartnerName(name)
	local key = ShortName(name)
	return DB.partner ~= nil and key ~= nil and key == ShortName(DB.partner)
end

local function Role()
	if DB.role then return DB.role end
	local _, class = UnitClass("player")
	return class == "PRIEST" and "heal" or "dps"
end

-- Returns the partner unit token ("party1".."party4") and its index.
local function PartnerUnit()
	if not IsInGroup() then return nil end
	for i = 1, 4 do
		local u = "party" .. i
		if UnitExists(u) then
			if not DB.partner or IsPartnerName(UnitName(u)) then
				return u, i
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Alerts
--------------------------------------------------------------------------------

local SOUND_WARN   = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
local SOUND_NOTICE = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960

local lastAlert = {}

local function Alert(key, text, sound, repeatDelay)
	local now = GetTime()
	if lastAlert[key] and now - lastAlert[key] < (repeatDelay or 6) then return end
	lastAlert[key] = now

	if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
	else
		UIErrorsFrame:AddMessage(text, 1, 0.2, 0.2)
	end
	if DB.sound then PlaySound(sound or SOUND_WARN, "Master") end
	if DB.flash and FlashClientIcon then FlashClientIcon() end
end

local function Clear(key) lastAlert[key] = nil end

--------------------------------------------------------------------------------
-- /follow tracking (sent by the following client, received by the other)
--------------------------------------------------------------------------------

local partnerFollowing = nil -- nil = unknown, true/false otherwise
local selfFollowing = false

local function SendComm(msg)
	if not IsInGroup() then return end
	local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if send then send(PREFIX, msg, "PARTY") end
end

--------------------------------------------------------------------------------
-- Small status frame (movable with the mouse)
--------------------------------------------------------------------------------

local status = CreateFrame("Frame", "DuoBoxStatus", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
status:SetSize(170, 58)
status:SetPoint("TOP", UIParent, "TOP", 0, -120)
status:SetMovable(true)
status:EnableMouse(true)
status:RegisterForDrag("LeftButton")
status:SetScript("OnDragStart", status.StartMoving)
status:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self:SetUserPlaced(true) end)
status:SetClampedToScreen(true)
if status.SetBackdrop then
	status:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	status:SetBackdropColor(0, 0, 0, 0.6)
end
status.text = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status.text:SetPoint("TOPLEFT", 8, -7)
status.text:SetJustifyH("LEFT")
status:Hide()

local function FmtPct(p)
	if not p then return "|cff888888?|r" end
	local c = p < 30 and "ff4040" or p < 60 and "ffd040" or "40ff40"
	return ("|cff%s%d%%|r"):format(c, p)
end

local function UpdateStatus(unit)
	if not DB.frame or not unit then status:Hide(); return end
	local name = Val(UnitName(unit)) or "?"
	local hp = Pct(UnitHealth(unit), UnitHealthMax(unit))
	local mp = Pct(UnitPower(unit, 0), UnitPowerMax(unit, 0))
	local fol
	if Role() == "heal" then
		fol = selfFollowing and "|cff40ff40OUI|r" or "|cffff4040NON|r"
	else
		fol = partnerFollowing == nil and "|cff888888?|r" or partnerFollowing and "|cff40ff40OUI|r" or "|cffff4040NON|r"
	end
	status.text:SetText(("%s\nPV %s   Mana %s\nFollow: %s"):format(name, FmtPct(hp), FmtPct(mp), fol))
	status:Show()
end

--------------------------------------------------------------------------------
-- Periodic checks (also run while the window is in the background)
--------------------------------------------------------------------------------

local function Check()
	local unit, idx = PartnerUnit()
	UpdateStatus(unit)
	if not unit then return end

	local pname = Val(UnitName(unit)) or "Partenaire"

	if Val(UnitIsDeadOrGhost(unit)) then
		Alert("dead", pname .. " est MORT !", SOUND_WARN, 20)
		return
	end
	Clear("dead")

	local hp = Pct(UnitHealth(unit), UnitHealthMax(unit))

	if Role() == "heal" then
		-- Priest side: the hunter or their pet needs healing
		if hp and hp < DB.hpPartner then
			Alert("hp", ("%s : %d%% PV !"):format(pname, hp), SOUND_WARN, 4)
		end
		local pet = "partypet" .. idx
		if UnitExists(pet) and not Val(UnitIsDead(pet)) then
			local php = Pct(UnitHealth(pet), UnitHealthMax(pet))
			if php and php < DB.hpPet then
				Alert("pet", ("Familier : %d%% PV !"):format(php), SOUND_WARN, 5)
			end
		end
		-- Priest aggro is handled by AggroTickPriest (below)
	else
		-- Hunter side: the priest is in danger / OOM
		if hp and hp < DB.hpPartner then
			Alert("hp", ("%s : %d%% PV !"):format(pname, hp), SOUND_WARN, 4)
		end
		local mp = Pct(UnitPower(unit, 0), UnitPowerMax(unit, 0))
		if mp and mp < DB.manaPartner then
			Alert("mana", ("%s : %d%% mana"):format(pname, mp), SOUND_NOTICE, 20)
		end
		local threat = UnitThreatSituation and Val(UnitThreatSituation(unit))
		if threat and threat >= 2 then
			Alert("aggro", "AGGRO sur " .. pname .. " !", SOUND_WARN, 5)
		end
	end
end

--------------------------------------------------------------------------------
-- Priest facing toward their enemy target (Smite / wand)
-- The game does not expose mob positions, so it is estimated with:
--   1) the pet position if it attacks the same target (melee range),
--   2) otherwise a point DB.facingDist yards in front of the hunter
--      (the hunter must face their target to shoot).
-- The priest client computes it (it knows its own facing) and sends
-- the result to the hunter. Positions are unavailable in dungeons.
--------------------------------------------------------------------------------

local TWO_PI = 2 * math.pi
local hunterFacing, hunterFacingTime = nil, 0   -- received from the hunter (priest side)
local lastHF, lastHFTime = nil, 0               -- sent (hunter side)
local lastSentCode, lastSendTime = nil, 0       -- sent (priest side)
local lastFCRecv = 0                            -- received (hunter side)
local moveMode = false                          -- /duo move: frames can be moved

local facingFrame = CreateFrame("Frame", "DuoBoxFacing", UIParent)
facingFrame:SetSize(260, 26)
facingFrame:SetPoint("TOP", UIParent, "TOP", 0, -185)
facingFrame:SetMovable(true)
facingFrame:EnableMouse(false) -- mouse enabled only in move mode (/duo move)
facingFrame:RegisterForDrag("LeftButton")
facingFrame:SetScript("OnDragStart", facingFrame.StartMoving)
facingFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self:SetUserPlaced(true) end)
facingFrame:SetClampedToScreen(true)
facingFrame.text = facingFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
facingFrame.text:SetPoint("CENTER")
facingFrame:Hide()

-- code: "OK", "L<degrees>", "R<degrees>" ("~" suffix = rough estimate),
--       "U<reason>" (enemy target but cannot compute) or "N" (no target)
local UNKNOWN_REASONS = {
	F = "orientation illisible",
	P = "position illisible",
	T = "cible non localisee",
}

local function ShowFacing(code)
	if moveMode then return end
	if not DB.facing or not code or code == "N" then facingFrame:Hide(); return end
	local approx = code:sub(-1) == "~" and "  |cff999999(approx.)|r" or ""
	local deg = code:match("%d+")
	if code:sub(1, 1) == "U" then
		local why = UNKNOWN_REASONS[code:sub(2, 2)]
		facingFrame.text:SetText("|cff999999Pretre : orientation ?" .. (why and (" (" .. why .. ")") or "") .. "|r")
	elseif code:sub(1, 2) == "OK" then
		facingFrame.text:SetText("|cff40ff40Pretre oriente|r" .. approx)
	elseif code:sub(1, 1) == "L" then
		facingFrame.text:SetText(("|cffff4040<<<  Pretre : GAUCHE %s°|r"):format(deg) .. approx)
	else
		facingFrame.text:SetText(("|cffff4040Pretre : DROITE %s°  >>>|r"):format(deg) .. approx)
	end
	facingFrame:Show()
end

-- Same convention as HereBeDragons / TomTom
local function WorldPos(unit)
	if not UnitPosition then return nil end
	local ok, y, x = pcall(UnitPosition, unit)
	if not ok then return nil end
	y, x = Val(y), Val(x)
	if not x or not y then return nil end
	return x, y
end

local function ComputeFacing()
	if not UnitExists("target") or not UnitCanAttack("player", "target") or Val(UnitIsDead("target")) then return "N" end
	local unit, idx = PartnerUnit()
	if not unit then return "N" end
	local okF, facing = pcall(GetPlayerFacing or function() end)
	facing = okF and Val(facing) or nil
	if not facing then return "UF" end

	local sameTarget = UnitIsUnit(unit .. "target", "target")
	local hunterFresh = hunterFacing and GetTime() - hunterFacingTime < 2
	local rel, approx

	-- 1) With positions: real angle to the pet or to a point in front of the hunter
	local px, py = WorldPos("player")
	if px then
		local tx, ty
		local pet = "partypet" .. idx
		if UnitExists(pet) and UnitIsUnit(pet .. "target", "target") then
			tx, ty = WorldPos(pet)
		end
		if not tx and hunterFresh and sameTarget then
			local hx, hy = WorldPos(unit)
			if hx then
				tx = hx + DB.facingDist * math.sin(hunterFacing)
				ty = hy + DB.facingDist * math.cos(hunterFacing)
			end
		end
		if tx then rel = math.atan2(tx - px, ty - py) - facing end
	end

	-- 2) Without positions: the priest follows the hunter, so it is roughly behind them
	--    and should face the same way (the hunter faces the target).
	if not rel and hunterFresh and sameTarget then
		rel = hunterFacing - facing
		approx = true
	end

	if not rel then return px and "UT" or "UP" end

	rel = rel % TWO_PI
	if rel > math.pi then rel = rel - TWO_PI end
	if DB.facingInvert then rel = -rel end
	local deg = math.floor(math.abs(rel) * 18 / math.pi + 0.5) * 10 -- rounded to 10°
	local code = deg <= 70 and "OK" or ((rel > 0 and "L" or "R") .. deg) -- spells work up to 90°
	return approx and (code .. "~") or code
end

-- /duo facing debug (on the priest): shows what the client lets us read
-- Facing diagnostic. Printed to chat (unless silent) and saved to
-- DuoBoxDB.facingDebug (readable in WTF\...\SavedVariables\DuoBox.lua after /reload).
local lastFCCode = nil        -- last code received (hunter side)
local lastAutoDebug = 0

local function FacingDebug(silent)
	local out = {}
	local function add(s) out[#out + 1] = s end
	local function show(v)
		if v == nil then return "nil" end
		if issecretvalue and issecretvalue(v) then return "SECRET" end
		if type(v) == "number" then return ("%.2f"):format(v) end
		return tostring(v)
	end
	local unit, idx = PartnerUnit()
	add(("%s  role=%s  partenaire=%s  combat=%s"):format(date("%H:%M:%S"), Role(), tostring(unit), tostring(UnitAffectingCombat("player"))))
	add("cible ennemie=" .. tostring(UnitExists("target") and UnitCanAttack("player", "target")))
	if GetPlayerFacing then
		local ok, v = pcall(GetPlayerFacing)
		add("GetPlayerFacing=" .. (ok and show(v) or ("ERREUR " .. tostring(v))))
	else
		add("GetPlayerFacing ABSENT")
	end
	for _, u in ipairs({ "player", unit or "party1", "partypet" .. (idx or 1) }) do
		if not UnitPosition then add("UnitPosition ABSENT"); break end
		local ok, y, x = pcall(UnitPosition, u)
		add(("UnitPosition(%s)=%s"):format(u, ok and (show(x) .. ", " .. show(y)) or ("ERREUR " .. tostring(y))))
	end
	if unit then
		local ok1, same1 = pcall(UnitIsUnit, unit .. "target", "target")
		local ok2, same2 = pcall(UnitIsUnit, "partypet" .. idx .. "target", "target")
		add("partenaire vise ma cible=" .. (ok1 and show(same1) or "ERREUR"))
		add("familier vise ma cible=" .. (ok2 and show(same2) or "ERREUR"))
	end
	if Role() == "heal" then
		add("orientation chasseur recue=" .. (hunterFacing and ("il y a %.1fs"):format(GetTime() - hunterFacingTime) or "JAMAIS"))
		add("resultat=" .. ComputeFacing())
	else
		add("orientation envoyee au pretre=" .. (lastHF and ("il y a %.1fs"):format(GetTime() - lastHFTime) or "JAMAIS"))
		add("dernier code recu du pretre=" .. tostring(lastFCCode) .. (lastFCRecv > 0 and ("  (il y a %.1fs)"):format(GetTime() - lastFCRecv) or ""))
	end
	DB.facingDebug = out
	if not silent then
		Print("--- diagnostic orientation (enregistre, fais /reload pour le sauvegarder) ---")
		for _, s in ipairs(out) do Print(s) end
	end
end

-- Priest side: compute and send to the hunter (max 5/s). Only displayed on the hunter side.
local function FacingTickPriest()
	local code = DB.facing and ComputeFacing() or "N"
	local now = GetTime()
	-- Automatically capture the diagnostic when the computation fails
	if code:sub(1, 1) == "U" and now - lastAutoDebug > 15 then
		lastAutoDebug = now
		FacingDebug(true)
	end
	if (code ~= lastSentCode and now - lastSendTime >= 0.2) or (code ~= "N" and now - lastSendTime > 1.5) then
		SendComm("FC:" .. code)
		lastSentCode, lastSendTime = code, now
	end
end

-- Hunter side: send its facing during combat
local function FacingTickHunter()
	if not moveMode and GetTime() - lastFCRecv > 3 then facingFrame:Hide() end
	if not DB.facing or not PartnerUnit() then return end
	if not (UnitAffectingCombat("player") or (UnitExists("target") and UnitCanAttack("player", "target"))) then return end
	local okF, f = pcall(GetPlayerFacing or function() end)
	f = okF and Val(f) or nil
	if not f then return end
	local now = GetTime()
	if not lastHF or math.abs(f - lastHF) > 0.08 or now - lastHFTime > 1.5 then
		SendComm(("HF:%d"):format(math.floor(f * 1000)))
		lastHF, lastHFTime = f, now
	end
end

local function FacingTick()
	if Role() == "heal" then FacingTickPriest() else FacingTickHunter() end
end

--------------------------------------------------------------------------------
-- Priest cast bar on the hunter's screen
--   CS:<spellID>:<duration ms>:<channel 0/1>:<target>   cast start
--   CI:<spellID>:<target>                               instant spell cast
--   CE:<ok|fail|int>                                    cast end
--   ER:<text>                                           priest spell error
--------------------------------------------------------------------------------

local function SpellInfoById(id)
	id = tonumber(id)
	if not id then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if info then return info.name, info.iconID end
	end
	if GetSpellInfo then
		local name, _, icon = GetSpellInfo(id)
		return name, icon
	end
end

local cast = CreateFrame("StatusBar", "DuoBoxCastBar", UIParent)
cast:SetSize(230, 16)
cast:SetPoint("TOP", UIParent, "TOP", 0, -215)
cast:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
cast:SetMinMaxValues(0, 1)
cast:SetMovable(true)
cast:SetResizable(true)
if cast.SetResizeBounds then
	cast:SetResizeBounds(120, 10, 600, 60)
elseif cast.SetMinResize then
	cast:SetMinResize(120, 10)
	cast:SetMaxResize(600, 60)
end
cast:EnableMouse(false) -- mouse enabled only in move mode (/duo move)
cast:RegisterForDrag("LeftButton")
cast:SetScript("OnDragStart", cast.StartMoving)
cast:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self:SetUserPlaced(true) end)
cast:SetClampedToScreen(true)
cast.bg = cast:CreateTexture(nil, "BACKGROUND")
cast.bg:SetAllPoints()
cast.bg:SetColorTexture(0, 0, 0, 0.6)
cast.icon = cast:CreateTexture(nil, "ARTWORK")
cast.icon:SetSize(16, 16)
cast.icon:SetPoint("RIGHT", cast, "LEFT", -3, 0)
cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
cast.text = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cast.text:SetPoint("CENTER")
cast:Hide()

-- state: "cast", "channel" or "hold" (frozen display until holdUntil)
cast:SetScript("OnUpdate", function(self)
	if self.unlocked then return end
	local now = GetTime()
	if self.state == "hold" then
		if now >= self.holdUntil then self:Hide() end
		return
	end
	local p = (now - self.start) / self.duration
	if p >= 1.3 then self:Hide(); return end -- end never received: clean up
	p = math.min(p, 1)
	self:SetValue(self.state == "channel" and 1 - p or p)
end)

-- Size: icon and text follow the bar height
local castFont = cast.text:GetFont() or STANDARD_TEXT_FONT
local function ApplyCastLayout()
	local w, h = DB.castW or 230, DB.castH or 16
	cast:SetSize(w, h)
	cast.icon:SetSize(h, h)
	cast.text:SetFont(castFont, math.max(8, math.floor(h * 0.7)), "OUTLINE")
end

-- Resize grip (bottom-right corner), shown in move mode
local grip = CreateFrame("Button", nil, cast)
grip:SetSize(14, 14)
grip:SetPoint("BOTTOMRIGHT", 2, -2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() cast:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function()
	cast:StopMovingOrSizing()
	cast:SetUserPlaced(true)
	DB.castW, DB.castH = math.floor(cast:GetWidth() + 0.5), math.floor(cast:GetHeight() + 0.5)
	ApplyCastLayout()
end)
cast:SetScript("OnSizeChanged", function(self, w, h)
	if self.unlocked then
		self.icon:SetSize(h, h)
		self.text:SetFont(castFont, math.max(8, math.floor(h * 0.7)), "OUTLINE")
	end
end)
grip:Hide()

local function CastLabel(spellID, target)
	local name, icon = SpellInfoById(spellID)
	cast.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	local label = "Pretre : " .. (name or "?")
	if target and target ~= "" then label = label .. "  >  " .. target end
	return label
end

local function CastHold(r, g, b, text, seconds)
	cast:SetStatusBarColor(r, g, b)
	cast:SetValue(1)
	if text then cast.text:SetText(text) end
	cast.state, cast.holdUntil = "hold", GetTime() + seconds
	cast:Show()
end

local function OnCastMessage(kind, payload)
	if not DB.castbar or cast.unlocked then return end
	if kind == "CS" then
		local id, dur, chan, target = payload:match("^(%d+):(%d+):(%d):(.*)$")
		if not id then return end
		cast.text:SetText(CastLabel(id, target))
		cast.start, cast.duration = GetTime(), math.max(tonumber(dur) / 1000, 0.1)
		cast.state = chan == "1" and "channel" or "cast"
		if chan == "1" then cast:SetStatusBarColor(0.3, 0.8, 1) else cast:SetStatusBarColor(1, 0.8, 0.2) end
		cast:Show()
	elseif kind == "CI" then
		local id, target = payload:match("^(%d+):(.*)$")
		if not id then return end
		cast.text:SetText(CastLabel(id, target))
		CastHold(0.3, 0.6, 1, nil, 1.5)
	elseif kind == "CE" then
		if not cast:IsShown() or cast.state == "hold" then return end
		if payload == "ok" then
			CastHold(0.2, 1, 0.2, nil, 0.6)
		else
			CastHold(1, 0.2, 0.2, "Pretre : " .. (payload == "int" and "INTERROMPU" or "ECHEC"), 1.2)
		end
	elseif kind == "ER" then
		cast.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		CastHold(1, 0.2, 0.2, "Pretre : " .. payload, 1.8)
	end
end

-- /duo move: shows the cast bar and the facing indicator with sample
-- content so they can be moved (and the cast bar resized)
local function ToggleMoveMode()
	moveMode = not moveMode
	cast.unlocked = moveMode
	cast:EnableMouse(moveMode)
	facingFrame:EnableMouse(moveMode)
	grip:SetShown(moveMode)
	if moveMode then
		cast.icon:SetTexture("Interface\\Icons\\Spell_Holy_LesserHeal")
		cast:SetStatusBarColor(1, 0.8, 0.2)
		cast:SetValue(0.6)
		cast.text:SetText("Pretre : Heal  >  Chasseur")
		cast:Show()
		facingFrame.text:SetText("|cffff4040<<<  Pretre : GAUCHE 90°|r")
		facingFrame:Show()
		Print("mode deplacement : glisse la barre de cast et le texte d'orientation, coin bas-droit de la barre pour la redimensionner. |cffffd040/duo move|r pour terminer.")
	else
		cast:Hide()
		facingFrame:Hide()
		ApplyCastLayout()
		Print("positions et taille enregistrees.")
	end
end

-- Priest side: track its own casts
local IGNORED_SPELLS = { [5019] = true, [75] = true, [6603] = true } -- Shoot (wand), Auto Shot, Attack
local castTarget, casting = "", false

local castEvents = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
	castEvents:RegisterUnitEvent(e, "player")
end
castEvents:SetScript("OnEvent", function(self, event, unit, a2, a3, a4)
	if not DB or not DB.castbar or Role() ~= "heal" or not PartnerUnit() then return end

	if event == "UNIT_SPELLCAST_SENT" then
		-- (unit, target, castGUID, spellID)
		castTarget = Val(a2) or ""
		return
	end
	local spellID = Val(a3) -- (unit, castGUID, spellID)
	if spellID and IGNORED_SPELLS[spellID] then return end

	if event == "UNIT_SPELLCAST_START" then
		local _, _, _, startMS, endMS = UnitCastingInfo("player")
		startMS, endMS = Val(startMS), Val(endMS)
		if not startMS or not endMS or not spellID then return end
		casting = true
		SendComm(("CS:%d:%d:0:%s"):format(spellID, endMS - startMS, castTarget))
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local _, _, _, startMS, endMS = UnitChannelInfo("player")
		startMS, endMS = Val(startMS), Val(endMS)
		if not startMS or not endMS or not spellID then return end
		casting = true
		SendComm(("CS:%d:%d:1:%s"):format(spellID, endMS - startMS, castTarget))
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if UnitChannelInfo("player") then return end -- channel start: handled by CHANNEL_START
		if casting then
			casting = false
			SendComm("CE:ok")
		elseif spellID then
			SendComm(("CI:%d:%s"):format(spellID, castTarget))
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if casting then casting = false; SendComm("CE:ok") end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if casting then
			casting = false
			SendComm(event == "UNIT_SPELLCAST_INTERRUPTED" and "CE:int" or "CE:fail")
		end
	end
end)

-- Priest spell errors relayed to the hunter (range, line of sight, mana...)
local RELAYED_ERRORS = {}
for _, g in ipairs({ "SPELL_FAILED_OUT_OF_RANGE", "ERR_OUT_OF_RANGE", "SPELL_FAILED_LINE_OF_SIGHT",
		"ERR_OUT_OF_MANA", "SPELL_FAILED_NO_POWER", "SPELL_FAILED_MOVING", "SPELL_FAILED_NOT_READY",
		"ERR_SPELL_COOLDOWN", "SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_BAD_TARGETS",
		"SPELL_FAILED_TARGETS_DEAD", "SPELL_FAILED_UNIT_NOT_INFRONT", "ERR_BADATTACKFACING",
		"SPELL_FAILED_INTERRUPTED", "SPELL_FAILED_SILENCED", "SPELL_FAILED_STUNNED" }) do
	if _G[g] then RELAYED_ERRORS[_G[g]] = true end
end
local lastErrSent = 0

--------------------------------------------------------------------------------
-- Aggro on the priest, detected on the priest side then relayed to the hunter:
--   1) threat API, 2) a mob targeting it (enemy nameplates
--   shown), 3) damage taken in combat.
--------------------------------------------------------------------------------

local lastHitTime, lastAggroSent = 0, 0

local function PriestHasAggro()
	local threat = UnitThreatSituation and Val(UnitThreatSituation("player"))
	if threat and threat >= 2 then return true end
	for i = 1, 40 do
		local np = "nameplate" .. i
		if UnitExists(np) and UnitCanAttack("player", np) and UnitIsUnit(np .. "target", "player") then
			return true
		end
	end
	return UnitAffectingCombat("player") and GetTime() - lastHitTime < 2
end

local function AggroTickPriest()
	if not PriestHasAggro() then return end
	Alert("aggro", "AGGRO sur le pretre !", SOUND_WARN, 5)
	local now = GetTime()
	if now - lastAggroSent > 2 then
		SendComm("AG")
		lastAggroSent = now
	end
end

local hitEvents = CreateFrame("Frame")
hitEvents:RegisterUnitEvent("UNIT_COMBAT", "player")
hitEvents:SetScript("OnEvent", function(self, event, unit, action, _, amount)
	action, amount = Val(action), Val(amount)
	if action == "WOUND" and amount and amount > 0 then lastHitTime = GetTime() end
end)

--------------------------------------------------------------------------------
-- Quests: automatic sharing
--------------------------------------------------------------------------------

local justReceivedFromPartner = false

-- Compatibility: classic API (GetQuestLogTitle...) or modern API (C_QuestLog)
local function NumQuestEntries()
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
		return (C_QuestLog.GetNumQuestLogEntries())
	end
	return GetNumQuestLogEntries and (GetNumQuestLogEntries()) or 0
end

-- Returns questID, title (or nil for a header)
local function QuestEntry(i)
	if C_QuestLog and C_QuestLog.GetInfo then
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then return info.questID, info.title end
		return nil
	end
	local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
	if not isHeader and id then return id, title end
end

-- Quest log entries: { [questID] = title }
local function MyQuests()
	local list = {}
	for i = 1, NumQuestEntries() do
		local id, title = QuestEntry(i)
		if id then list[id] = title or ("#" .. id) end
	end
	return list
end

local function QuestLogIndex(questID)
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local i = C_QuestLog.GetLogIndexForQuestID(questID)
		if i and i > 0 then return i end
	end
	for i = 1, NumQuestEntries() do
		if QuestEntry(i) == questID then return i end
	end
end

local function QuestCompleted(questID)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(questID) end
	if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(questID) end
end

-- Share a quest with the group (it must be selected before the "shareable" check)
local function PushQuest(questID)
	local idx = QuestLogIndex(questID)
	if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
	if idx and SelectQuestLogEntry then SelectQuestLogEntry(idx) end

	local pushable = C_QuestLog and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questID)
	if not pushable and GetQuestLogPushable then pushable = GetQuestLogPushable() end
	if not pushable then return false end

	if C_QuestLog and C_QuestLog.ShareQuest then
		C_QuestLog.ShareQuest(questID)
	elseif QuestLogPushQuest then
		QuestLogPushQuest()
	else
		return false
	end
	return true
end

local function ShareQuest(questID)
	if not DB.autoShare or not PartnerUnit() then return end
	PushQuest(questID)
end

--------------------------------------------------------------------------------
-- Quest comparison with the partner
--   A clicks  -> "QREQ:<ids of A>"
--   B replies -> "QRES:<ids of A that B lacks (and has not completed)>;<ids of B that A lacks>"
--   A shares the missing quests one by one (B accepts them through DuoBox).
-- Each client only shares ITS OWN quests: no action is triggered
-- remotely on the other client.
--------------------------------------------------------------------------------

local compareTimer

local function IdList(set)
	local t = {}
	for id in pairs(set) do t[#t + 1] = id end
	table.sort(t)
	return table.concat(t, ",")
end

local function ParseIds(s)
	local t = {}
	for id in (s or ""):gmatch("%d+") do t[#t + 1] = tonumber(id) end
	return t
end

local function RequestQuestCompare()
	if not PartnerUnit() then Print("le partenaire n'est pas dans le groupe."); return end
	SendComm("QREQ:" .. IdList(MyQuests()))
	if compareTimer then compareTimer:Cancel() end
	compareTimer = C_Timer.NewTimer(4, function()
		compareTimer = nil
		Print("pas de reponse du partenaire (DuoBox est-il active sur son perso ?).")
	end)
end

local function HandleQuestRequest(payload)
	local theirs, mine = {}, MyQuests()
	for _, id in ipairs(ParseIds(payload)) do theirs[id] = true end

	local iLack, theyLack = {}, {}
	for id in pairs(theirs) do
		if not mine[id] and not QuestCompleted(id) then iLack[id] = true end
	end
	for id in pairs(mine) do
		if not theirs[id] then theyLack[id] = true end
	end
	SendComm("QRES:" .. IdList(iLack) .. ";" .. IdList(theyLack))
end

local function HandleQuestResult(payload)
	if compareTimer then compareTimer:Cancel(); compareTimer = nil end
	local partnerLacks, partnerOnly = payload:match("^([^;]*);(.*)$")
	partnerLacks, partnerOnly = ParseIds(partnerLacks), ParseIds(partnerOnly)
	local mine = MyQuests()
	local pname = DB.partner or "Partenaire"

	if #partnerLacks == 0 and #partnerOnly == 0 then
		Print("|cff40ff40journaux de quetes synchronises.|r")
		return
	end

	if #partnerLacks > 0 then
		Print(("%d quete(s) a partager avec %s :"):format(#partnerLacks, pname))
		for n, id in ipairs(partnerLacks) do
			C_Timer.After((n - 1) * 2.5, function()
				local ok = PushQuest(id)
				Print(("  %s %s"):format(ok and "|cff40ff40partagee|r" or "|cffff4040non partageable|r", mine[id] or ("#" .. id)))
			end)
		end
	end

	if #partnerOnly > 0 then
		Print(("|cffffd040%d quete(s) que %s a et pas toi|r -> clique 'Comparer' sur sa fenetre pour qu'il te les partage.")
			:format(#partnerOnly, pname))
	end
end

--------------------------------------------------------------------------------
-- NPC quests: for a short time after the D-Talk macro (/duo npc), open, accept
-- and turn in the quests of the NPC you talk to. Talking to an NPC by hand is
-- never automated. Rewards with a choice are left to the player.
--------------------------------------------------------------------------------

local NPC_ARM_SECONDS = 20
local npcArmedUntil = 0

local function NpcArmed()
	return DB.autoNpc and GetTime() < npcArmedUntil
end

-- Gossip window: turn in completed quests first, then take available ones
local function HandleGossip()
	if not (C_GossipInfo and C_GossipInfo.GetActiveQuests) then return end
	for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
		if q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID); return end
	end
	local available = C_GossipInfo.GetAvailableQuests() or {}
	if available[1] then C_GossipInfo.SelectAvailableQuest(available[1].questID) end
end

-- Quest greeting window (NPC with several quests and no gossip text)
local function HandleGreeting()
	for i = 1, GetNumActiveQuests() do
		local _, isComplete = GetActiveTitle(i)
		if isComplete then SelectActiveQuest(i); return end
	end
	if GetNumAvailableQuests() > 0 then SelectAvailableQuest(1) end
end

local function HandleQuestComplete()
	local choices = GetNumQuestChoices()
	if choices <= 1 then
		GetQuestReward(choices)
	else
		Alert("reward", "Choisis ta recompense de quete", SOUND_NOTICE, 3)
	end
end

--------------------------------------------------------------------------------
-- Macros
--------------------------------------------------------------------------------

local function MacroList()
	local _, class = UnitClass("player")
	-- In a duo the partner is always party1 (a name with a space would break macros)
	local T = "party1"
	-- [mod:shift] = partner's pet, [mod:ctrl] = yourself, otherwise = partner
	local tgt = ("[mod:shift,@partypet1,help,nodead][mod:ctrl,@player][@%s,help,nodead]"):format(T)
	local function onTarget(spell)
		return ("#showtooltip %s\n/cast %s %s"):format(spell, tgt, spell)
	end

	if class == "PRIEST" then
		return {
			{ "D-Follow",  ("/follow %s"):format(T) },
			{ "D-Wait",    "/follow player" }, -- following yourself = stop following
			-- Talk to the partner's target (NPC) and accept / turn in its quests
			{ "D-Talk",    ("#showtooltip\n/assist %s\n/duo npc\n/interact"):format(T) },
			{ "D-Smite",   ("#showtooltip Smite\n/assist %s\n/cast [harm,nodead] Smite"):format(T) },
			{ "D-SWP",     ("#showtooltip Shadow Word: Pain\n/assist %s\n/cast [harm,nodead] Shadow Word: Pain"):format(T) },
			{ "D-Wand",    ("#showtooltip Shoot\n/assist %s\n/cast [harm,nodead] Shoot"):format(T) },
			{ "D-LHeal",   onTarget("Lesser Heal") },
			{ "D-Heal",    onTarget("Heal") },
			{ "D-Flash",   onTarget("Flash Heal") },
			{ "D-Renew",   onTarget("Renew") },
			{ "D-Shield",  onTarget("Power Word: Shield") },
			{ "D-Fort",    onTarget("Power Word: Fortitude") },
			{ "D-Dispel",  onTarget("Dispel Magic") },
			{ "D-CureDis", onTarget("Cure Disease") },
			{ "D-FearWard",onTarget("Fear Ward") },
			{ "D-Rez",     ("#showtooltip Resurrection\n/cast [@%s,dead] Resurrection"):format(T) },
		}
	elseif class == "HUNTER" then
		local list = {
			{ "D-Attack",  "#showtooltip Auto Shot\n/petattack\n/cast !Auto Shot" },
			{ "D-Mark",    "#showtooltip Hunter's Mark\n/cast Hunter's Mark\n/petattack" },
			{ "D-PetFollow","#showtooltip\n/petfollow" },
			{ "D-PetPassif","#showtooltip\n/petpassive\n/petfollow" },
			{ "D-FD",      "#showtooltip Feign Death\n/petfollow\n/cast Feign Death" },
			{ "D-Assist",  ("#showtooltip\n/assist %s\n/petattack"):format(T) },
			{ "D-Talk",    ("#showtooltip\n/assist %s\n/duo npc\n/interact"):format(T) },
		}
		if DB.partner then
			table.insert(list, { "D-Invite", ("/invite %s"):format(DB.partner) })
		end
		return list
	end
end

local function CreateMacros()
	if InCombatLockdown() then Print("impossible en combat."); return end
	local list = MacroList()
	if not list then Print("pas de macros predefinies pour cette classe."); return end
	if not DB.partner then
		Print("|cffffd040Attention|r : aucun partenaire defini, les macros ciblent 'party1'. Fais /duo partner <Nom> puis relance /duo macros.")
	end
	local created, updated, failed = 0, 0, 0
	for _, m in ipairs(list) do
		local name, body = m[1], m[2]
		local idx = GetMacroIndexByName(name)
		if idx and idx > 0 then
			EditMacro(idx, name, 134400, body)
			updated = updated + 1
		else
			local ok = pcall(CreateMacro, name, 134400, body, true)
			if ok then created = created + 1 else failed = failed + 1 end
		end
	end
	Print(("macros : %d creees, %d mises a jour%s. Ouvre /macro (onglet perso) et glisse-les sur tes barres.")
		:format(created, updated, failed > 0 and (", |cffff4040" .. failed .. " echec(s) (limite 18 macros perso ?)|r") or ""))
end

--------------------------------------------------------------------------------
-- Discreet button bar:
--   Follow / Target / Assist / Trade / Invite / Compare quests / Share last quest
--   + a second row of priest spells (priest only)
-- (1 click = 1 action on THIS client only)
-- Shift + drag to move it (out of combat).
--------------------------------------------------------------------------------

local BTN_SIZE, BTN_GAP = 34, 5
local bar = CreateFrame("Frame", "DuoBoxBar", UIParent)
bar:SetSize(BTN_SIZE, BTN_SIZE)
bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:SetAlpha(0.45)

local barPending = false
local buttons = {}

local function BarUnit()
	return PartnerUnit() or "party1"
end

local function BarTooltip(self)
	bar:SetAlpha(1)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local name = Val(UnitName(BarUnit())) or DB.partner or "aucun partenaire"
	GameTooltip:SetText(self.label .. " : |cffffd040" .. name .. "|r")
	if self.hint then GameTooltip:AddLine(self.hint, 1, 1, 1) end
	if self.bindable then
		local key = GetBindingKey("CLICK " .. self:GetName() .. ":LeftButton")
		GameTooltip:AddLine("Raccourci : " .. (key or "aucun (/duo keys)"), 0.5, 0.8, 1)
	end
	if self.extra then self.extra(GameTooltip) end
	GameTooltip:AddLine("Maj + glisser pour deplacer", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function BarLeave()
	bar:SetAlpha(0.45)
	GameTooltip:Hide()
end

-- Binding command of a button: "CLICK DuoBoxBtnFollow:LeftButton"
local function BindCommand(b)
	return "CLICK " .. b:GetName() .. ":LeftButton"
end

-- Short key text displayed on the button (e.g. "c-S", "M4")
local function ShortKey(key)
	if not key then return "" end
	key = key:gsub("ALT%-", "a-"):gsub("CTRL%-", "c-"):gsub("SHIFT%-", "s-")
	key = key:gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD")
	key = key:gsub("NUMPAD", "N")
	return key
end

-- row 1 = shared commands, row 2 = priest spells
local rowCounts = {}
local function MakeButton(key, label, icon, secure, row)
	row = row or 1
	local i = #buttons + 1
	rowCounts[row] = (rowCounts[row] or 0) + 1
	local col = rowCounts[row]
	local b = CreateFrame("Button", "DuoBoxBtn" .. key, bar, secure and "SecureActionButtonTemplate" or nil)
	b:SetSize(BTN_SIZE, BTN_SIZE)
	b:SetPoint("TOPLEFT", bar, "TOPLEFT", (col - 1) * (BTN_SIZE + BTN_GAP), -(row - 1) * (BTN_SIZE + BTN_GAP))
	if secure then
		-- One direction only (down OR up) so a key binding does not fire twice
		b:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
	else
		b:RegisterForClicks("AnyUp")
	end
	b.label = label
	b.bindable = true
	b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	b.hotkey:SetPoint("TOPRIGHT", -1, -2)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(icon)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function() if IsShiftKeyDown() and not InCombatLockdown() then bar:StartMoving() end end)
	b:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); bar:SetUserPlaced(true) end)
	b:SetScript("OnEnter", BarTooltip)
	b:SetScript("OnLeave", BarLeave)
	buttons[i] = b
	local cols, rows = 0, 0
	for r, n in pairs(rowCounts) do cols = math.max(cols, n); rows = math.max(rows, r) end
	bar:SetSize(cols * (BTN_SIZE + BTN_GAP) - BTN_GAP, rows * (BTN_SIZE + BTN_GAP) - BTN_GAP)
	return b
end

local function SpellNameIcon(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if info then return info.name, info.iconID end
	end
	if GetSpellInfo then
		local name, _, icon = GetSpellInfo(id)
		return name, icon
	end
end

-- Follow (secure macro)
local btnFollow = MakeButton("Follow", "Follow","Interface\\Icons\\Ability_Rogue_Sprint", true)
btnFollow:SetAttribute("type", "macro")

-- Target
local btnTarget = MakeButton("Target", "Cibler","Interface\\Icons\\Ability_Hunter_SniperShot", true)
btnTarget:SetAttribute("type", "target")

-- Assist (takes the partner's target)
local btnAssist = MakeButton("Assist", "Assister","Interface\\Icons\\Ability_DualWield", true)
btnAssist:SetAttribute("type", "macro")

-- Trade (not protected)
local btnTrade = MakeButton("Trade", "Echange","Interface\\Icons\\INV_Misc_Coin_01", false)
btnTrade:SetScript("OnClick", function()
	local unit = PartnerUnit()
	if unit then InitiateTrade(unit) else Print("aucun partenaire dans le groupe.") end
end)

-- Invite (not protected)
local btnInvite = MakeButton("Invite", "Inviter","Interface\\Icons\\INV_Misc_Note_01", false)
btnInvite.hint = "Invite le partenaire (grise si deja groupe)"
btnInvite:SetScript("OnClick", function()
	if PartnerUnit() and DB.partner then Print("deja en groupe avec " .. DB.partner .. "."); return end
	if not DB.partner then Print("definis d'abord ton partenaire : /duo partner <Nom>"); return end
	local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	invite(DB.partner)
end)

-- Compare quests (not protected)
local btnQuests = MakeButton("Quests", "Comparer les quetes","Interface\\Icons\\INV_Misc_Book_09", false)
btnQuests.hint = "Partage tes quetes qui manquent au partenaire"
btnQuests:SetScript("OnClick", RequestQuestCompare)

-- Share the last accepted quest (not protected)
local btnLastQuest = MakeButton("LastQuest", "Partager la derniere quete","Interface\\Icons\\INV_Scroll_03", false)
btnLastQuest.extra = function(tt)
	local id = DB.lastQuest
	local title = id and MyQuests()[id]
	if title then
		tt:AddLine(title, 1, 0.82, 0)
	else
		tt:AddLine(id and "Plus dans ton journal" or "Aucune quete prise pour l'instant", 0.8, 0.3, 0.3)
	end
end
btnLastQuest:SetScript("OnClick", function()
	local id = DB.lastQuest
	local title = id and MyQuests()[id]
	if not title then Print("aucune quete recente dans ton journal."); return end
	if not PartnerUnit() then Print("le partenaire n'est pas dans le groupe."); return end
	if PushQuest(id) then
		Print("quete partagee : |cffffd040" .. title .. "|r")
	else
		Print("|cffff4040non partageable|r : " .. title)
	end
end)

--------------------------------------------------------------------------------
-- Priest spells (second row), created at login
--------------------------------------------------------------------------------

local SPELL = {
	Shield = 17, Renew = 139, LesserHeal = 2050, Heal = 2054, Dispel = 527,
	Rez = 2006, Smite = 585, Shoot = 5019,
}

-- Drinks: { itemID, required level }; the best one found in the bags is used
local DRINKS = {
	{ 8079, 55 }, { 8078, 45 }, { 8766, 45 }, { 8077, 35 }, { 1645, 35 }, { 3772, 25 }, { 1708, 25 },
	{ 2136, 15 }, { 1205, 15 }, { 2288, 5 }, { 1179, 5 }, { 5350, 1 }, { 159, 1 },
}

local priestSpellButtons = {} -- "spell on partner" buttons (Shift = pet, Ctrl = self)
local btnHeal, btnRez, btnSmite, btnWand, btnDrink

local function ItemCount(id)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
	return GetItemCount and GetItemCount(id) or 0
end

local function ItemIcon(id)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	return GetItemIcon and GetItemIcon(id)
end

local function Known(id)
	if IsPlayerSpell then return IsPlayerSpell(id) end
	return IsSpellKnown and IsSpellKnown(id)
end

local function BestDrink()
	local level = UnitLevel("player")
	for _, d in ipairs(DRINKS) do
		if d[2] <= level and ItemCount(d[1]) > 0 then return d[1] end
	end
end

local BuildPriestSpellButtons -- called from BuildPriestButtons

-- Fortitude (priest only), created at login
local btnFort
local FORT_IDS = { 1243, 21562 } -- Power Word: Fortitude, Prayer of Fortitude
local fortNames = {}
local fortNeed = {}

local function BuildPriestButtons()
	local _, class = UnitClass("player")
	if class ~= "PRIEST" or btnFort then return end
	local name, icon = SpellNameIcon(FORT_IDS[1])
	for _, id in ipairs(FORT_IDS) do
		local n = SpellNameIcon(id)
		if n then fortNames[n] = true end
	end
	btnFort = MakeButton("Fort", name or "Power Word: Fortitude", icon or "Interface\\Icons\\Spell_Holy_WordFortitude", true, 2)
	btnFort.noDesat = true
	btnFort:SetAttribute("type", "spell")
	btnFort:SetAttribute("spell", name or "Power Word: Fortitude")
	btnFort:SetAttribute("ctrl-unit", "player")
	btnFort.hint = "Clic : partenaire - Maj : son familier - Ctrl : toi"
	btnFort.extra = function(tt)
		for who in pairs(fortNeed) do tt:AddLine("A rebuff : " .. who, 1, 0.8, 0.2) end
	end
	-- Glowing border when a buff is missing or about to expire
	local glow = btnFort:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.85, 0.2)
	glow:SetSize(BTN_SIZE * 1.9, BTN_SIZE * 1.9)
	glow:SetPoint("CENTER")
	glow:Hide()
	btnFort.glow = glow
	BuildPriestSpellButtons()
end

BuildPriestSpellButtons = function()
	local MOD_HINT = "Clic : partenaire - Maj : son familier - Ctrl : toi"

	-- Spell cast on the partner, with Shift = pet and Ctrl = yourself
	local function partnerSpell(key, spellID)
		local name, icon = SpellNameIcon(spellID)
		local b = MakeButton(key, name or key, icon or "Interface\\Icons\\INV_Misc_QuestionMark", true, 2)
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", name)
		b:SetAttribute("ctrl-unit", "player")
		b.hint = MOD_HINT
		b.noDesat = true
		priestSpellButtons[#priestSpellButtons + 1] = b
		return b
	end

	partnerSpell("Shield", SPELL.Shield)
	partnerSpell("Renew", SPELL.Renew)
	btnHeal = partnerSpell("Heal", SPELL.LesserHeal) -- switches to "Heal" once it is learned
	btnHeal.label = "Soin"
	partnerSpell("Dispel", SPELL.Dispel)

	local rezName, rezIcon = SpellNameIcon(SPELL.Rez)
	btnRez = MakeButton("Rez", rezName or "Resurrection", rezIcon or "Interface\\Icons\\Spell_Holy_Resurrection", true, 2)
	btnRez:SetAttribute("type", "spell")
	btnRez:SetAttribute("spell", rezName)

	-- Assist the partner then attack their target
	local function assistSpell(key, spellID)
		local name, icon = SpellNameIcon(spellID)
		local b = MakeButton(key, name or key, icon or "Interface\\Icons\\INV_Misc_QuestionMark", true, 2)
		b:SetAttribute("type", "macro")
		b.spellName = name
		b.hint = "Prend la cible du partenaire puis lance le sort"
		b.noDesat = true
		return b
	end
	btnSmite = assistSpell("Smite", SPELL.Smite)
	btnWand = assistSpell("Wand", SPELL.Shoot)
	btnWand.label = "Baguette"

	local bWait = MakeButton("Wait", "Wait (arreter le follow)", "Interface\\Icons\\Spell_Nature_Sleep", true, 2)
	bWait:SetAttribute("type", "macro")
	bWait:SetAttribute("macrotext", "/follow player")
	bWait.noDesat = true

	btnDrink = MakeButton("Drink", "Boire", "Interface\\Icons\\INV_Drink_07", true, 2)
	btnDrink:SetAttribute("type", "item")
	btnDrink.noDesat = true
	btnDrink.hint = "Meilleure boisson de tes sacs pour ton niveau"
	btnDrink.extra = function(tt)
		local id = BestDrink()
		if id then
			local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or ("objet " .. id)
			tt:AddLine(("%s (x%d)"):format(name, ItemCount(id)), 1, 0.82, 0)
		else
			tt:AddLine("Aucune boisson adaptee dans les sacs", 1, 0.3, 0.3)
		end
	end
end

-- Update priest spells / items (out of combat only)
local function UpdatePriestSpells(unit, pet)
	for _, b in ipairs(priestSpellButtons) do
		b:SetAttribute("unit", unit)
		b:SetAttribute("shift-unit", pet)
	end
	if btnHeal then
		local id = Known(SPELL.Heal) and SPELL.Heal or SPELL.LesserHeal
		local name, icon = SpellNameIcon(id)
		btnHeal:SetAttribute("spell", name)
		if icon then btnHeal.icon:SetTexture(icon) end
	end
	if btnRez then btnRez:SetAttribute("unit", unit) end
	for _, b in ipairs({ btnSmite, btnWand }) do
		if b and b.spellName then
			b:SetAttribute("macrotext", ("/assist %s\n/cast [harm,nodead] %s"):format(unit, b.spellName))
		end
	end
	if btnDrink then
		local id = BestDrink()
		btnDrink:SetAttribute("item", id and ("item:" .. id) or nil)
		btnDrink.icon:SetTexture(id and ItemIcon(id) or "Interface\\Icons\\INV_Drink_07")
		btnDrink.icon:SetDesaturated(not id)
	end
end

local function ReadBuff(unit, i)
	if UnitBuff then
		local name, _, _, _, _, expires = UnitBuff(unit, i)
		return name, expires
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local a = C_UnitAuras.GetBuffDataByIndex(unit, i)
		if a then return a.name, a.expirationTime end
	end
end

-- This client may forbid reading auras ("secret" error): do not crash.
-- Returns ok (false = unreadable), name, expires
local function GetBuff(unit, i)
	local ok, name, expires = pcall(ReadBuff, unit, i)
	if not ok then return false end
	return true, name, expires
end

-- Seconds left on Fortitude: 0 = missing, nil = unreadable
local function FortRemaining(unit)
	for i = 1, 40 do
		local ok, name, expires = GetBuff(unit, i)
		if not ok then return nil end
		if name == nil then return 0 end
		name, expires = Val(name), Val(expires)
		if not name then return nil end
		if fortNames[name] then
			if not expires or expires == 0 then return math.huge end
			return expires - GetTime()
		end
	end
	return 0
end

local function CheckFort()
	-- Auras are unreadable in combat on this client: keep the previous state
	if not btnFort or InCombatLockdown() then return end
	wipe(fortNeed)
	local unit, idx = PartnerUnit()
	local units = { player = "toi" }
	if unit then
		units[unit] = Val(UnitName(unit)) or "partenaire"
		units["partypet" .. idx] = "familier"
	end
	local any = false
	for u, label in pairs(units) do
		if UnitExists(u) and not Val(UnitIsDeadOrGhost(u)) then
			local left = FortRemaining(u)
			if left and left < 120 then fortNeed[label] = true; any = true end
		end
	end
	btnFort.glow:SetShown(any)
end

local function UpdateBar()
	local inGroup = PartnerUnit() ~= nil
	for _, b in ipairs(buttons) do
		if b == btnInvite then
			b.icon:SetDesaturated(inGroup)
		elseif b ~= btnFort and not b.noDesat then
			b.icon:SetDesaturated(not inGroup)
		end
	end
	-- Secure button attributes can only change out of combat
	if InCombatLockdown() then barPending = true; return end
	barPending = false
	local unit, idx = PartnerUnit()
	unit = unit or "party1"
	btnFollow:SetAttribute("macrotext", "/follow " .. unit)
	btnTarget:SetAttribute("unit", unit)
	btnAssist:SetAttribute("macrotext", "/assist " .. unit)
	if btnFort then
		btnFort:SetAttribute("unit", unit)
		btnFort:SetAttribute("shift-unit", "partypet" .. (idx or 1))
		UpdatePriestSpells(unit, "partypet" .. (idx or 1))
	end
	bar:SetScale(DB.barScale)
	bar:SetShown(DB.bar)
end

--------------------------------------------------------------------------------
-- Key bindings: /duo keys panel (or the gear button on the bar)
-- Bindings are also in the game menu: Key Bindings > AddOns > DuoBox
--------------------------------------------------------------------------------

local function UpdateHotkeys()
	for _, b in ipairs(buttons) do
		if b.bindable then b.hotkey:SetText(ShortKey(GetBindingKey(BindCommand(b)))) end
	end
end

local keys = CreateFrame("Frame", "DuoBoxKeys", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
keys:SetSize(320, 100)
keys:SetPoint("CENTER")
keys:SetFrameStrata("DIALOG")
keys:SetMovable(true)
keys:EnableMouse(true)
keys:RegisterForDrag("LeftButton")
keys:SetScript("OnDragStart", keys.StartMoving)
keys:SetScript("OnDragStop", keys.StopMovingOrSizing)
keys:SetClampedToScreen(true)
if keys.SetBackdrop then
	keys:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
end
keys:Hide()
tinsert(UISpecialFrames, "DuoBoxKeys") -- Escape closes the panel

keys.title = keys:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
keys.title:SetPoint("TOP", 0, -14)
keys.title:SetText("DuoBox - Raccourcis")

keys.help = keys:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
keys.help:SetPoint("BOTTOM", 0, 14)
keys.help:SetText("Clic : definir  -  Clic droit : effacer  -  Echap : annuler")

local close = CreateFrame("Button", nil, keys, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

local rows = {}
local capturing -- bar button waiting for a key
local RefreshKeys

local function StopCapture()
	capturing = nil
	keys:EnableKeyboard(false)
	keys:EnableMouseWheel(false)
end

local function ClearKeys(cmd)
	for _ = 1, 10 do
		local key = GetBindingKey(cmd)
		if not key then break end
		SetBinding(key)
	end
end

local function Bind(b, key)
	if InCombatLockdown() then Print("impossible en combat."); StopCapture(); RefreshKeys(); return end
	local cmd = BindCommand(b)
	local old = GetBindingAction(key)
	ClearKeys(cmd) -- one key per action
	if SetBindingClick(key, b:GetName(), "LeftButton") then
		SaveBindings(GetCurrentBindingSet())
		if old and old ~= "" and old ~= cmd then
			Print(("%s -> %s |cffff8040(remplace : %s)|r"):format(key, b.label, _G["BINDING_NAME_" .. old] or old))
		else
			Print(("%s -> %s"):format(key, b.label))
		end
	else
		Print("impossible d'utiliser la touche " .. key)
	end
	StopCapture()
	RefreshKeys()
end

local function Modifiers()
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
end

local IGNORED = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }

keys:SetScript("OnKeyDown", function(self, key)
	if not capturing then return end
	if IGNORED[key] then return end
	if key == "ESCAPE" then StopCapture(); RefreshKeys(); return end
	Bind(capturing, Modifiers() .. key)
end)

local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
keys:SetScript("OnMouseDown", function(self, button)
	if capturing and MOUSE[button] then Bind(capturing, Modifiers() .. MOUSE[button]) end
end)
keys:SetScript("OnMouseWheel", function(self, delta)
	if capturing then Bind(capturing, Modifiers() .. (delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")) end
end)

local function RowOnClick(self, button)
	if InCombatLockdown() then Print("impossible en combat."); return end
	if button == "RightButton" then
		ClearKeys(BindCommand(self.target))
		SaveBindings(GetCurrentBindingSet())
		StopCapture()
	else
		capturing = self.target
		keys:EnableKeyboard(true)
		keys:SetPropagateKeyboardInput(false)
		keys:EnableMouseWheel(true)
	end
	RefreshKeys()
end

RefreshKeys = function()
	local n = 0
	for _, b in ipairs(buttons) do
		if b.bindable then
			n = n + 1
			local row = rows[n]
			if not row then
				row = CreateFrame("Button", nil, keys, "UIPanelButtonTemplate")
				row:SetSize(130, 22)
				row:SetPoint("TOPRIGHT", -18, -40 - (n - 1) * 26)
				row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				row:SetScript("OnClick", RowOnClick)
				row.name = keys:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.name:SetPoint("LEFT", keys, "TOPLEFT", 18, -51 - (n - 1) * 26)
				rows[n] = row
			end
			row.target = b
			row.name:SetText(b.label)
			if capturing == b then
				row:SetText("|cffffd040Appuie sur une touche...|r")
			else
				row:SetText(GetBindingKey(BindCommand(b)) or "|cff888888non defini|r")
			end
			row:Show(); row.name:Show()
		end
	end
	for i = n + 1, #rows do rows[i]:Hide(); rows[i].name:Hide() end
	keys:SetHeight(40 + n * 26 + 36)
	UpdateHotkeys()
end

keys:SetScript("OnShow", RefreshKeys)
keys:SetScript("OnHide", StopCapture)

local function ToggleKeys()
	if keys:IsShown() then keys:Hide() else keys:Show() end
end

-- Gear button at the end of the bar (created at login, after the priest buttons)
local btnConfig
local function BuildConfigButton()
	if btnConfig then return end
	btnConfig = MakeButton("Config", "Raccourcis clavier", "Interface\\Icons\\Trade_Engineering", false)
	btnConfig.bindable = false
	btnConfig.noDesat = true
	btnConfig.hint = "Ouvre le panneau des raccourcis"
	btnConfig:SetScript("OnClick", ToggleKeys)
end

-- Names shown in the game Key Bindings menu (see Bindings.xml)
BINDING_HEADER_DUOBOX = "DuoBox"
for key, label in pairs({
	Follow = "Follow partenaire", Target = "Cibler partenaire", Assist = "Assister partenaire",
	Trade = "Echange avec partenaire", Invite = "Inviter partenaire", Quests = "Comparer les quetes",
	LastQuest = "Partager la derniere quete", Fort = "Robustesse (pretre)",
	Shield = "Bouclier (pretre)", Renew = "Renovation (pretre)", Heal = "Soin (pretre)",
	Dispel = "Dissipation (pretre)", Rez = "Resurrection (pretre)", Smite = "Chatiment + assist (pretre)",
	Wand = "Baguette + assist (pretre)", Wait = "Wait / stop follow (pretre)", Drink = "Boire (pretre)",
}) do
	_G["BINDING_NAME_CLICK DuoBoxBtn" .. key .. ":LeftButton"] = label
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PARTY_INVITE_REQUEST")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_ACCEPT_CONFIRM")
f:RegisterEvent("GOSSIP_SHOW")
f:RegisterEvent("QUEST_GREETING")
f:RegisterEvent("QUEST_PROGRESS")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("RESURRECT_REQUEST")
f:RegisterEvent("AUTOFOLLOW_BEGIN")
f:RegisterEvent("AUTOFOLLOW_END")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("UI_ERROR_MESSAGE")
-- New spell rank / drink / level: update the priest buttons
for _, e in ipairs({ "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP" }) do
	pcall(f.RegisterEvent, f, e)
end

f:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then return end
		DuoBoxDB = DuoBoxDB or {}
		for k, v in pairs(defaults) do
			if DuoBoxDB[k] == nil then DuoBoxDB[k] = v end
		end
		DB = DuoBoxDB

	elseif event == "PLAYER_LOGIN" then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
			C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		elseif RegisterAddonMessagePrefix then
			RegisterAddonMessagePrefix(PREFIX)
		end
		BuildPriestButtons()
		BuildConfigButton()
		ApplyCastLayout()
		UpdateHotkeys()
		C_Timer.NewTicker(0.3, function()
			Check()
			if Role() == "heal" and PartnerUnit() then AggroTickPriest() end
			CheckFort()
		end)
		C_Timer.NewTicker(0.1, FacingTick)
		UpdateBar()
		Print(("charge. Role: |cffffd040%s|r, partenaire: |cffffd040%s|r. /duo pour l'aide.")
			:format(Role(), DB.partner or "non defini"))

	elseif event == "PARTY_INVITE_REQUEST" then
		local inviter = ...
		if DB.autoInvite and IsPartnerName(inviter) then
			AcceptGroup()
			StaticPopup_Hide("PARTY_INVITE")
			StaticPopup_Hide("PARTY_INVITE_XREALM")
		end

	elseif event == "QUEST_DETAIL" then
		if DB.autoQuest and IsPartnerName(UnitName("questnpc")) then
			justReceivedFromPartner = true
			AcceptQuest()
		elseif NpcArmed() then
			if QuestGetAutoAccept and QuestGetAutoAccept() then CloseQuest() else AcceptQuest() end
		end

	elseif event == "GOSSIP_SHOW" then
		if NpcArmed() then HandleGossip() end

	elseif event == "QUEST_GREETING" then
		if NpcArmed() then HandleGreeting() end

	elseif event == "QUEST_PROGRESS" then
		if NpcArmed() and IsQuestCompletable() then CompleteQuest() end

	elseif event == "QUEST_COMPLETE" then
		if NpcArmed() then HandleQuestComplete() end

	elseif event == "QUEST_ACCEPT_CONFIRM" then
		-- escort quests started by the partner
		local who = ...
		if DB.autoQuest and IsPartnerName(who) then
			ConfirmAcceptQuest()
			StaticPopup_Hide("QUEST_ACCEPT")
		end

	elseif event == "QUEST_ACCEPTED" then
		-- Depending on the version: (questLogIndex, questID) or (questID)
		local a, b = ...
		local questID = b or a
		DB.lastQuest = questID
		if justReceivedFromPartner then
			justReceivedFromPartner = false -- avoids share ping-pong
			return
		end
		C_Timer.After(0.5, function() ShareQuest(questID) end)

	elseif event == "RESURRECT_REQUEST" then
		local who = ...
		if DB.autoRez and IsPartnerName(who) then
			AcceptResurrect()
			StaticPopup_Hide("RESURRECT")
			StaticPopup_Hide("RESURRECT_NO_SICKNESS")
			StaticPopup_Hide("RESURRECT_NO_TIMER")
		end

	elseif event == "AUTOFOLLOW_BEGIN" then
		selfFollowing = true
		SendComm("F1")

	elseif event == "AUTOFOLLOW_END" then
		selfFollowing = false
		SendComm("F0")

	elseif event == "CHAT_MSG_ADDON" then
		local prefix, msg, _, sender = ...
		if prefix ~= PREFIX or not IsPartnerName(sender) then return end
		local qcmd, payload = msg:match("^(Q%u+):(.*)$")
		if qcmd == "QREQ" then HandleQuestRequest(payload); return end
		if qcmd == "QRES" then HandleQuestResult(payload); return end
		local fcmd, fval = msg:match("^(%u%u):(.*)$")
		if fcmd == "HF" then
			hunterFacing, hunterFacingTime = (tonumber(fval) or 0) / 1000, GetTime()
			return
		elseif fcmd == "FC" then
			lastFCRecv, lastFCCode = GetTime(), fval
			ShowFacing(fval)
			if fval:sub(1, 1) == "U" and GetTime() - lastAutoDebug > 15 then
				lastAutoDebug = GetTime()
				FacingDebug(true)
			end
			return
		elseif fcmd == "CS" or fcmd == "CI" or fcmd == "CE" or fcmd == "ER" then
			OnCastMessage(fcmd, fval)
			return
		end
		if msg == "AG" then
			Alert("aggro", "AGGRO sur " .. (DB.partner or "le pretre") .. " !", SOUND_WARN, 3)
			return
		end
		if msg == "FW" then
			if DB.facing then Alert("facing", "Pretre mal oriente !", SOUND_NOTICE, 3) end
			return
		end
		if msg == "F1" then
			partnerFollowing = true
			Clear("follow")
		elseif msg == "F0" then
			partnerFollowing = false
			if Role() == "dps" then
				Alert("follow", (DB.partner or "Partenaire") .. " ne te suit plus !", SOUND_NOTICE, 3)
			end
		end

	elseif event == "GROUP_ROSTER_UPDATE" then
		if not PartnerUnit() then partnerFollowing = nil end
		UpdateBar()

	elseif event == "SPELLS_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LEVEL_UP" then
		if DB then UpdateBar() end

	elseif event == "PLAYER_REGEN_ENABLED" then
		if barPending then UpdateBar() end

	elseif event == "UI_ERROR_MESSAGE" then
		-- Depending on the version: (messageType, message) or (message)
		local a, b = ...
		local msg = type(a) == "string" and a or b
		msg = Val(msg)
		if Role() == "heal" and msg and PartnerUnit() then
			if msg == ERR_BADATTACKFACING or msg == SPELL_FAILED_UNIT_NOT_INFRONT then
				SendComm("FW")
			end
			if DB.castbar and RELAYED_ERRORS[msg] and GetTime() - lastErrSent > 0.8 then
				SendComm("ER:" .. msg:sub(1, 200))
				lastErrSent = GetTime()
			end
		end

	elseif event == "UPDATE_BINDINGS" then
		if keys:IsShown() then RefreshKeys() else UpdateHotkeys() end
	end
end)

--------------------------------------------------------------------------------
-- /duo commands
--------------------------------------------------------------------------------

local function OnOff(key, arg)
	if arg == "on" then DB[key] = true elseif arg == "off" then DB[key] = false else DB[key] = not DB[key] end
	Print(("%s = %s"):format(key, DB[key] and "|cff40ff40on|r" or "|cffff4040off|r"))
end

local toggles = { sound = "sound", flash = "flash", invite = "autoInvite", quest = "autoQuest", share = "autoShare", rez = "autoRez", frame = "frame", bar = "bar", castbar = "castbar", autonpc = "autoNpc" }

SLASH_DUOBOX1 = "/duo"
SlashCmdList.DUOBOX = function(input)
	local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()

	if cmd == "partner" and arg ~= "" then
		DB.partner = arg:match("^[^%-]+")
		Print("partenaire = |cffffd040" .. DB.partner .. "|r")
		UpdateBar()
	elseif cmd == "role" and (arg == "heal" or arg == "dps") then
		DB.role = arg
		Print("role = " .. arg)
	elseif (cmd == "hp" or cmd == "pet" or cmd == "mana") and tonumber(arg) then
		local key = cmd == "hp" and "hpPartner" or cmd == "pet" and "hpPet" or "manaPartner"
		DB[key] = tonumber(arg)
		Print(("%s = %d%%"):format(key, DB[key]))
	elseif cmd == "scale" and tonumber(arg) then
		DB.barScale = math.max(0.5, math.min(2, tonumber(arg)))
		UpdateBar()
		Print(("echelle de la barre = %.2f%s"):format(DB.barScale, InCombatLockdown() and " (appliquee a la sortie du combat)" or ""))
	elseif toggles[cmd] then
		OnOff(toggles[cmd], arg:lower())
		if cmd == "frame" then Check() end
		if cmd == "bar" then
			UpdateBar()
			if InCombatLockdown() then Print("sera applique a la sortie du combat.") end
		end
	elseif cmd == "facing" then
		local sub, val = arg:lower():match("^(%S*)%s*(.-)$")
		if sub == "debug" then
			FacingDebug()
		elseif sub == "invert" then
			DB.facingInvert = not DB.facingInvert
			Print("orientation : gauche/droite " .. (DB.facingInvert and "|cffffd040inverses|r" or "normaux"))
		elseif sub == "dist" and tonumber(val) then
			DB.facingDist = tonumber(val)
			Print(("orientation : distance estimee = %d m"):format(DB.facingDist))
		else
			OnOff("facing", sub)
			if not DB.facing then facingFrame:Hide() end
		end
	elseif cmd == "npc" then
		-- called by the D-Talk macro: arm NPC quest handling for a short time
		npcArmedUntil = GetTime() + NPC_ARM_SECONDS
	elseif cmd == "keys" then
		ToggleKeys()
	elseif cmd == "move" then
		ToggleMoveMode()
	elseif cmd == "macros" then
		CreateMacros()
	elseif cmd == "cvars" then
		SetCVar("Sound_EnableSoundWhenGameIsInBG", 1)
		SetCVar("autoLootDefault", 1)
		Print("CVars appliquees : son en arriere-plan ON, auto-loot ON.")
	elseif cmd == "test" then
		wipe(lastAlert)
		Alert("test", "DuoBox : test d'alerte", SOUND_WARN)
		Print("alerte de test envoyee (si la fenetre est en fond, elle doit clignoter/sonner).")
	elseif cmd == "status" then
		local unit = PartnerUnit()
		Print(("role=%s partenaire=%s (unit=%s) hp<%d pet<%d mana<%d | son=%s flash=%s invite=%s quest=%s share=%s rez=%s")
			:format(Role(), DB.partner or "-", unit or "aucun", DB.hpPartner, DB.hpPet, DB.manaPartner,
				tostring(DB.sound), tostring(DB.flash), tostring(DB.autoInvite), tostring(DB.autoQuest), tostring(DB.autoShare), tostring(DB.autoRez)))
	else
		Print("commandes :")
		Print("  /duo partner <Nom>   - nom du perso partenaire (a faire sur les 2 persos)")
		Print("  /duo role heal|dps   - force le role (auto : pretre = heal)")
		Print("  /duo macros          - cree/maj les macros de ta classe")
		Print("  /duo cvars           - son + FPS en arriere-plan, auto-loot")
		Print("  /duo test            - teste l'alerte")
		Print("  /duo hp|pet|mana <n> - seuils d'alerte en %")
		Print("  /duo bar [on|off]    - barre Follow / Cibler / Echange (Maj+glisser pour deplacer)")
		Print("  /duo scale <0.5-2>   - taille de la barre (1 = normal)")
		Print("  /duo keys            - raccourcis clavier des boutons de la barre")
		Print("  /duo move            - deplacer / redimensionner la barre de cast et l'orientation")
		Print("  /duo facing [on|off|invert|dist <m>] - indicateur d'orientation du pretre")
		Print("  /duo sound|flash|invite|quest|share|rez|frame|castbar|autonpc [on|off]")
		Print("  /duo status")
	end
end
