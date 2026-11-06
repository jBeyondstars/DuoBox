--------------------------------------------------------------------------------
-- DuoBox / event light ("voyant des evenements"): on the partner's screen (the
-- priest), the icon of a reactive spell as soon as it lights up on the other
-- client: Overpower after a dodge, Revenge, Execute under 20 %, Riposte... so
-- the main presses the follower's key (pedal) in time. Hidden as soon as the
-- spell goes out again (window over, spell used, target dead, end of fight).
-- Detecting side (a class listed in PROCS), every 0.1 s and on the usable /
-- glow / cooldown events, in combat: the learned rank (by name: ranks replace
-- each other on WoW Forever) is usable, or lit but short of rage, or glowing,
-- and not on its own cooldown (the global cooldown does not count). Combat log
-- and auras in combat are restricted for addons on this client: not used.
-- Sent as "PR:<id><u|p>,..." (u = ready, p = lit, not enough rage / energy /
-- mana), in PROCS order, on its own prefix (its own addon message budget: a
-- lost message is a missed press). Sent at once when a spell lights up or goes
-- out, after 0.5 s for a ready / short-of-rage change, every 2 s while one is
-- lit; a throttled send is retried on the next tick.
-- Partner side: the first lit spell the options do not hide (DB.procOff, spell
-- IDs), the others listed under it; hidden after 3 s without news.
-- /duo move: drag it, bottom-right corner to resize. /duo proc debug: what the
-- client answers. Kept out of DuoBox.lua (Lua 5.1's 200 locals).
--------------------------------------------------------------------------------

local _, ns = ...

local PREFIX = "DUOBOXP"
local TICK = 0.1
local HEARTBEAT = 2   -- s between two sends while a spell stays lit
local SOFT_DELAY = 0.5 -- s before sending a change between ready and short of rage
local STALE = 3       -- s without news: the light hides (message lost, partner gone)
local GCD = 1.5       -- a cooldown this long or shorter is the global cooldown
local SIZE = 70       -- default size
local X, Y = 110, 160 -- default place: right of the warrior light
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Reactive spells of each class, in priority order (the first lit one is shown big).
-- hint: when the game lights it, shown in the options panel.
local PROCS = {
	WARRIOR = {
		{ id = 7384, hint = "apres une esquive" },                 -- Overpower
		{ id = 6572, hint = "apres blocage / esquive / parade" },  -- Revenge
		{ id = 5308, hint = "cible sous 20 % de vie" },            -- Execute
	},
	ROGUE = { { id = 14251, hint = "apres une parade" } },        -- Riposte
	HUNTER = {
		{ id = 19306, hint = "apres une parade" },                 -- Counterattack
		{ id = 1495, hint = "apres une esquive" },                 -- Mongoose Bite
	},
	PALADIN = { { id = 24275, hint = "cible sous 20 % de vie" } }, -- Hammer of Wrath
}
ns.PROCS = PROCS

local function DB() return ns.GetDB() end

-- The secret test comes first: comparing a secret value, even to nil, is refused
local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Debug text of a value the client may hide
local function Show(v)
	if issecretvalue and issecretvalue(v) then return "SECRET" end
	if v == nil then return "nil" end
	return tostring(v)
end

local function Enabled()
	local db = DB()
	return db ~= nil and db.procLight ~= false
end

-- Spell IDs hidden in the options: "7384,5308" (a string: profiles compare it as is)
function ns.ProcHidden(id)
	return ("," .. (DB().procOff or "") .. ","):find("," .. id .. ",", 1, true) ~= nil
end

function ns.SetProcHidden(id, hide)
	local ids = {}
	for x in (DB().procOff or ""):gmatch("%d+") do
		if tonumber(x) ~= id then ids[#ids + 1] = tonumber(x) end
	end
	if hide then ids[#ids + 1] = id end
	table.sort(ids)
	ns.Set("procOff", table.concat(ids, ","))
end

--------------------------------------------------------------------------------
-- Detecting side: compute and send
--------------------------------------------------------------------------------

local class
local spells -- learned PROCS of this class: { id, name, rankID }; nil = to rebuild
local sentCode, sentTime = "", 0

local function Learned()
	if spells then return spells end
	local list = {}
	for _, p in ipairs(PROCS[class] or {}) do
		local name = ns.Known(p.id) and ns.SpellNameIcon(p.id)
		if name then
			local rankID
			if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
				local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(name)
				if slot then rankID = select(3, C_SpellBook.GetSpellBookItemType(slot, bank)) end
			end
			list[#list + 1] = { id = p.id, name = name, rankID = rankID }
		end
	end
	if #list > 0 then spells = list end -- spellbook not loaded yet: read it again next time
	return list
end

local function UsableRaw(name)
	if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(name) end
	if IsUsableSpell then return IsUsableSpell(name) end
end

-- The game's glow on the spell (its action button), by the learned rank then the first one
local function GlowRaw(s)
	local f = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
	if not f then return nil end
	local glow = f(s.rankID or s.id)
	if Val(glow) ~= true and s.rankID and s.rankID ~= s.id then glow = f(s.id) end
	return glow
end

-- Seconds left on the spell's own cooldown (0: none, or only the global cooldown)
local function CooldownLeft(name)
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(name)
		if info then start, duration = info.startTime, info.duration end
	elseif GetSpellCooldown then
		start, duration = GetSpellCooldown(name)
	end
	start, duration = Val(start), Val(duration)
	if not start or not duration or duration <= GCD then return 0 end
	return math.max(0, start + duration - GetTime())
end

-- "u" = ready, "p" = lit but short of rage / energy / mana, nil = out
local function State(s)
	local usable, noPower = UsableRaw(s.name)
	usable, noPower = Val(usable), Val(noPower)
	local glow = Val(GlowRaw(s)) == true
	if not usable and not noPower and not glow then return nil end
	if CooldownLeft(s.name) > 0 then return nil end
	return noPower and "p" or "u"
end

local function Code()
	if not Val(UnitAffectingCombat("player")) then return "" end
	local parts = {}
	for _, s in ipairs(Learned()) do
		local state = State(s)
		if state then parts[#parts + 1] = s.id .. state end
	end
	return table.concat(parts, ",")
end

-- Sent, or nil when the game refused it (throttled: retried on the next tick)
local function Send(code)
	local r = ns.SendComm("PR:" .. code, PREFIX)
	if r == false or (type(r) == "number" and r ~= 0) then return nil end
	sentCode, sentTime = code, GetTime()
	return true
end

local function Ids(code) return (code:gsub("[up]", "")) end

local function Check()
	if not class or not Enabled() or not ns.PartnerUnit() then return end
	local code, now = Code(), GetTime()
	if code == sentCode then
		if code ~= "" and now - sentTime >= HEARTBEAT then Send(code) end
	elseif Ids(code) ~= Ids(sentCode) or now - sentTime >= SOFT_DELAY then
		Send(code)
	end
end

--------------------------------------------------------------------------------
-- Partner side (the priest): the light
--------------------------------------------------------------------------------

local light = CreateFrame("Frame", "DuoBoxProcLight", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
light:SetSize(SIZE, SIZE)
light:SetPoint("CENTER", UIParent, "CENTER", X, Y)
light:SetMovable(true)
light:SetResizable(true)
if light.SetResizeBounds then
	light:SetResizeBounds(32, 32, 300, 300)
elseif light.SetMinResize then
	light:SetMinResize(32, 32)
	light:SetMaxResize(300, 300)
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
light.icon = light:CreateTexture(nil, "ARTWORK")
light.icon:SetPoint("TOPLEFT", 4, -4)
light.icon:SetPoint("BOTTOMRIGHT", -4, 4)
light.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
light.name = light:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- partner, on top
light.name:SetPoint("BOTTOM", light, "TOP", 0, 2)
light.spell = light:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- spell, over the icon's bottom
light.spell:SetPoint("BOTTOM", 0, 6)
light.more = light:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- the other lit spells, under the light
light.more:SetPoint("TOP", light, "BOTTOM", 0, -2)
light:Hide()

-- Ready: the light pulses (stopped while short of rage)
local pulse = light.CreateAnimationGroup and light:CreateAnimationGroup()
if pulse then
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.3)
end

local function Pulse(on)
	if not pulse then return end
	if on and not pulse:IsPlaying() then pulse:Play() elseif not on and pulse:IsPlaying() then pulse:Stop() end
end

-- Texts follow the size
local function FitTexts(size)
	local font = GameFontNormalLarge and GameFontNormalLarge:GetFont()
	if font then
		light.spell:SetFont(font, math.max(9, math.floor(size * 0.17)), "OUTLINE")
		light.name:SetFont(font, math.max(8, math.floor(size * 0.13)), "OUTLINE")
		light.more:SetFont(font, math.max(8, math.floor(size * 0.15)), "OUTLINE")
	end
	-- wider than the icon: a long spell name overflows on both sides
	light.spell:SetWidth(size + 60)
	light.name:SetWidth(size + 60)
	light.more:SetWidth(size + 120)
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
	DB().procLightSize = size
end)
grip:Hide()

local received, receivedTime, receivedRaw = {}, 0, nil -- the partner's lit spells: { id, ready }
local wasMoving = false

local POWER = { [0] = "mana", [1] = "rage", [3] = "energie" }

local function Paint(icon, ready, name, spellText, moreText)
	light.icon:SetTexture(icon or QUESTION)
	light.icon:SetDesaturated(not ready)
	if light.SetBackdropBorderColor then
		if ready then light:SetBackdropBorderColor(1, 0.82, 0) else light:SetBackdropBorderColor(0.5, 0.5, 0.5) end
	end
	light.name:SetText(name or "")
	light.spell:SetText(spellText)
	light.more:SetText(moreText or "")
	light:Show()
end

local function Render()
	if ns.IsMoveMode() then return end
	local first, others = nil, {}
	if Enabled() then
		for _, p in ipairs(received) do
			if not ns.ProcHidden(p.id) then
				if first then others[#others + 1] = ns.SpellNameIcon(p.id) or tostring(p.id) else first = p end
			end
		end
	end
	if not first then
		Pulse(false)
		light:Hide()
		return
	end
	local unit = ns.PartnerUnit()
	local name, icon = ns.SpellNameIcon(first.id)
	name = name or tostring(first.id)
	local text = name
	if not first.ready then
		local power = unit and Val(UnitPowerType(unit))
		text = ("%s\n|cffbbbbbbpas assez de %s|r"):format(name, POWER[power] or "ressource")
	end
	Paint(icon, first.ready, unit and Val(UnitName(unit)), text, #others > 0 and ("+ " .. table.concat(others, ", ")) or "")
	Pulse(first.ready)
end

local function OnMessage(list)
	receivedRaw, receivedTime = list, GetTime()
	received = {}
	for id, state in list:gmatch("(%d+)([up])") do
		received[#received + 1] = { id = tonumber(id), ready = state == "u" }
	end
	Render()
end

local function DisplayTick()
	local moving = ns.IsMoveMode()
	light:EnableMouse(moving)
	grip:SetShown(moving)
	if moving then
		wasMoving = true
		Pulse(false)
		Paint(select(2, ns.SpellNameIcon(PROCS.WARRIOR[1].id)), true, "Voyant des evenements", "Glisse-moi")
		return
	end
	if wasMoving then
		wasMoving = false
		Render()
	end
	if #received > 0 and GetTime() - receivedTime > STALE then
		received = {}
		Render()
	end
end

function ns.RefreshProcLight()
	-- switched off on the detecting side: put the partner's light out now
	if class and not Enabled() and sentCode ~= "" and ns.PartnerUnit() then Send("") end
	Render()
	DisplayTick()
end

-- /duo proc debug|reset
function ns.ProcLightCommand(sub)
	if sub == "reset" then
		DB().procLightSize = nil
		light:ClearAllPoints()
		light:SetPoint("CENTER", UIParent, "CENTER", X, Y)
		light:SetSize(SIZE, SIZE)
		light:SetUserPlaced(false)
		ns.Print("voyant des evenements : position et taille par defaut.")
		return
	end
	ns.Print(("voyant des evenements : dernier etat recu = %s%s."):format(receivedRaw == nil and "aucun"
		or receivedRaw == "" and "rien d'allume" or receivedRaw,
		receivedTime > 0 and (" il y a %.1f s"):format(GetTime() - receivedTime) or " (jamais)"))
	if not class then return end
	spells = nil
	local list = Learned()
	if #list == 0 then
		ns.Print("aucun sort evenement appris pour l'instant.")
	end
	for _, s in ipairs(list) do
		local usable, noPower = UsableRaw(s.name)
		ns.Print(("%s (rang %s) : utilisable=%s manque de ressource=%s lueur=%s recharge=%.1f s -> %s"):format(s.name,
			tostring(s.rankID), Show(usable), Show(noPower), Show(GlowRaw(s)), CooldownLeft(s.name),
			State(s) == "u" and "allume" or State(s) == "p" and "allume, pas assez de ressource" or "eteint"))
	end
	ns.Print(("combat=%s ; envoye : %s"):format(Show(UnitAffectingCombat("player")),
		not ns.PartnerUnit() and "rien (pas de partenaire dans le groupe)"
		or sentCode == "" and "rien d'allume" or sentCode))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
elseif RegisterAddonMessagePrefix then
	RegisterAddonMessagePrefix(PREFIX)
end

-- Events after which a spell may light up or go out (the 0.1 s ticker catches the rest)
local CHECK_EVENTS = { "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN",
	"SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_TARGET_CHANGED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local isCheck = {}
for _, e in ipairs(CHECK_EVENTS) do isCheck[e] = true end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, body, channel, sender = ...
		if prefix ~= PREFIX or channel ~= "PARTY" then return end
		body = ns.FromPartner(body, sender)
		local list = type(body) == "string" and body:match("^PR:([%d,up]*)$")
		if list then OnMessage(list) end
	elseif isCheck[event] then
		Check()
	elseif event == "SPELLS_CHANGED" then
		spells = nil -- new rank, or spell learned
	elseif event == "PLAYER_LOGIN" then
		local size = DB() and DB().procLightSize
		if size then light:SetSize(size, size) end
		FitTexts(light:GetWidth())
		local _, myClass = UnitClass("player")
		if PROCS[myClass] then
			class = myClass
			ev:RegisterEvent("SPELLS_CHANGED")
			for _, e in ipairs(CHECK_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
			C_Timer.NewTicker(TICK, Check)
		end
		C_Timer.NewTicker(0.25, DisplayTick)
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
