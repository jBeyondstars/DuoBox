--------------------------------------------------------------------------------
-- DuoBox / partner spell panel (with DuoRelay, PC 1 -> PC 2): icons of the
-- warrior's spells on this screen; a left click on one makes DuoRelay press
-- that spell's action-bar key in the warrior's game on PC 2.
-- An addon cannot talk to DuoRelay (no network, no file written while the game
-- runs). So while the mouse is over icon N, a tiny code is drawn in the
-- top-left corner of the game window; at a left click DuoRelay reads those
-- screen pixels and relays the DuoRelay.json trigger with "pixel": N, which
-- holds the key to press on PC 2. In this game the icons are plain frames: a
-- click on them does nothing here, in combat too.
-- Code: CELLS squares of CELL physical pixels in a row: A, 7-A, B, 7-B, each a
-- colour with every channel full or off (4 = red, 2 = green, 1 = blue), A and B
-- from 1 to 6, N = (A - 1) * 6 + B. The complements make a chance match with
-- the game's picture unlikely; full / off channels survive small colour shifts.
-- DuoRelay.ps1 reads the same scheme (ConvertFrom-PixelCells).
-- Status code, in the same squares whenever no icon code is drawn: 0 (black),
-- 7 (white), S, 7 - S, S = camera (0 off, 1 camera only, 2 camera and the warrior
-- turns) + 3 * moves (0 / 1), from the options DB.relayCamera, DB.relayCameraTurn
-- and DB.relayMoves (tab DuoRelay, off by default). DuoRelay reads it every
-- 0.25 s and only takes Ctrl+Z / Ctrl+Q / Ctrl+S / Ctrl+D from this game while
-- it says so (ConvertFrom-StatusCells).
-- Option DB.relayPanel (off by default); the spells, DB.relayPanelSpells, are
-- only shown here (icon, tooltip): their order is the "pixel" number of the
-- DuoRelay.json triggers. DB.relayPanelHidden: entries of that list whose icon
-- is hidden (Options > DuoRelay), the others keep their number. /duo
-- panneau. Kept out of DuoBox.lua (Lua 5.1's 200 locals).
-- Cooldowns on the icons, estimated: this client hides cooldowns from addons
-- in combat (C_Spell.GetSpellCooldown is SecretWhenCooldownsRestricted, seen in
-- game 2026-11-07), and the partner's cast events carry a hidden spell ID
-- (SecretWhenUnitSpellCastRestricted). But a client sees its own casts, so
-- while the panel side asks ("RT" clock pings, every 10 s), the warrior's
-- DuoBox reports each of its casts that starts a cooldown: "RC" with its own
-- clock times. The cooldown itself: read when the client shows it (out of
-- combat), else measured earlier, the game's base value, the tooltip, a table.
-- The panel side turns the times into its own clock (offset from the ping with
-- the shortest round trip) and draws the spell's cooldown, or the global
-- cooldown when it ends later, as an action bar does.
--------------------------------------------------------------------------------

local _, ns = ...

local MAX = 12      -- icons (the options page lists them in 2 columns of 6)
local SIZE = 36     -- icon size (UI units)
local GAP = 4
local HANDLE = 12   -- height of the drag strip above the icons
local CELL = 8      -- physical pixels per square of the code (DuoRelay.json "pixelCell")
local CELLS = 4

-- English names (this client's language) accepted by "/duo panneau sorts": the
-- priest's client cannot look up the warrior's spells by name, only by ID
local NAMES = {
	["victory rush"] = 402927, slam = 1240193, execute = 5308, ["thunder clap"] = 6343, overpower = 7384,
	["heroic strike"] = 78, cleave = 845, hamstring = 1715, ["sunder armor"] = 7386, rend = 772,
	["mocking blow"] = 694, bloodrage = 2687, ["battle shout"] = 6673, charge = 100, taunt = 355,
	retaliation = 20230, ["demoralizing shout"] = 1160, ["shield bash"] = 72, revenge = 6572,
	["shield block"] = 2565, disarm = 676, intercept = 20252, whirlwind = 1680, pummel = 6552,
	["berserker rage"] = 18499, ["intimidating shout"] = 5246, ["piercing howl"] = 12323,
	["mortal strike"] = 12294, bloodthirst = 23881, ["shield slam"] = 23922, ["challenging shout"] = 1161,
	["sweeping strikes"] = 12292,
}

-- Panel entries that are not spells: a key of the warrior's own all the same
-- (its "pixel" trigger in DuoRelay.json); no cooldown, no blink
local ACTIONS = {
	interact = { name = "Interagir", icon = "Interface\\CURSOR\\Interact",
		tip = "Le guerrier appuie sur sa touche d'interaction (T) : ce qu'elle prend chez lui (PNJ, objet, "
			.. "ou sa cible ennemie, option Touche d'interaction)." },
}
local ACTION_NAMES = { interact = "interact", interagir = "interact", interaction = "interact" }

local function DB() return ns.GetDB() end

local function Say(msg) ns.Print(msg) end

-- The secret test comes first: comparing a secret value, even to nil, is refused
local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Entries of the panel, in order: spell IDs, or ACTIONS keys ("402927,1240193,interact" in the settings)
local function Spells()
	local ids = {}
	for part in tostring(DB() and DB().relayPanelSpells or ""):gmatch("[^,]+") do
		part = part:match("^%s*(.-)%s*$")
		local entry = tonumber(part) or (ACTIONS[part] and part)
		if entry and #ids < MAX then ids[#ids + 1] = entry end
	end
	return ids
end

-- Entries hidden in the options (DB.relayPanelHidden, "1161,interact"): still in
-- the list, so every other icon keeps its number, the "pixel" of DuoRelay.json
local function Hidden()
	local set = {}
	for part in tostring(DB() and DB().relayPanelHidden or ""):gmatch("[^,]+") do
		part = part:match("^%s*(.-)%s*$")
		set[tonumber(part) or part] = true
	end
	return set
end

-- Name of an entry, for the lists
local function EntryName(entry)
	if ACTIONS[entry] then return ACTIONS[entry].name end
	return ns.SpellNameIcon(entry) or tostring(entry)
end

-- For Options.lua: { { entry, name, icon, hidden }, ... } in panel order
function ns.RelayPanelEntries()
	local list, hidden = {}, Hidden()
	for _, entry in ipairs(Spells()) do
		local icon = ACTIONS[entry] and ACTIONS[entry].icon or select(2, ns.SpellNameIcon(entry))
		list[#list + 1] = { entry = entry, name = EntryName(entry), icon = icon, hidden = hidden[entry] == true }
	end
	return list
end

-- Shows or hides an entry's icon (Options > DuoRelay)
function ns.SetRelayPanelHidden(entry, hide)
	local set, parts = Hidden(), {}
	set[entry] = hide and true or nil
	for _, e in ipairs(Spells()) do -- kept in panel order; entries no longer listed are dropped
		if set[e] then parts[#parts + 1] = tostring(e) end
	end
	ns.Set("relayPanelHidden", table.concat(parts, ","))
end
ns.RELAY_PANEL_MAX = MAX

--------------------------------------------------------------------------------
-- The code in the top-left corner
--------------------------------------------------------------------------------

-- The CELLS values (0-7) that say icon n (1-36)
local function Code(n)
	local a, b = math.floor((n - 1) / 6) + 1, (n - 1) % 6 + 1
	return { a, 7 - a, b, 7 - b }
end
ns.RelayPanelCode = Code

-- S of the status code, 0 = no option on (nothing drawn)
local function StatusValue()
	local db = DB()
	if not db then return 0 end
	local camera = db.relayCamera and (db.relayCameraTurn and 2 or 1) or 0
	return camera + (db.relayMoves and 3 or 0)
end
ns.RelayStatusValue = StatusValue

local function StatusCode(s) return { 0, 7, s, 7 - s } end

-- A child of UIParent like every visible frame (with no parent, DuoRelay did
-- not find the code in the corner, 2026-11-07; cause not proven), at its
-- top-left corner = the window's, above everything; sizes in physical pixels
-- through its effective scale
local signal = CreateFrame("Frame", "DuoBoxRelaySignal", UIParent)
signal:SetFrameStrata("TOOLTIP")
signal:SetFrameLevel(9000)
signal:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
signal:Hide()
local squares = {}
for i = 1, CELLS do
	squares[i] = signal:CreateTexture(nil, "OVERLAY")
end
local lit           -- icon whose code is drawn (nil: /duo panneau test, the status code or nothing)
local testUntil = 0 -- /duo panneau test: code drawn without the mouse until then
local status = 0    -- S of the status code drawn, 0 = none

local function PhysicalHeight()
	local _, height = 0, 0
	if GetPhysicalScreenSize then _, height = GetPhysicalScreenSize() end
	if not height or height <= 0 then height = 1080 end
	return height
end

-- Physical pixels per UI unit of the signal frame (768 units = the screen height at scale 1)
local function PixelsPerUnit()
	return PhysicalHeight() / 768 * signal:GetEffectiveScale()
end

-- Draws the 4 squares with these values (0-7)
local function Draw(values)
	local size = CELL / PixelsPerUnit()
	signal:SetSize(size * CELLS, size)
	for i, v in ipairs(values) do
		local sq = squares[i]
		sq:ClearAllPoints()
		sq:SetSize(size, size)
		sq:SetPoint("TOPLEFT", (i - 1) * size, 0)
		sq:SetColorTexture(math.floor(v / 4) % 2, math.floor(v / 2) % 2, v % 2, 1)
	end
	signal:Show()
end

-- No icon code: the status code if an option asks for it, else nothing
local function Off()
	lit, testUntil = nil, 0
	status = StatusValue()
	if status > 0 then Draw(StatusCode(status)) else signal:Hide() end
end

-- Draws the code of icon n; owner: the icon under the mouse
local function Light(n, owner)
	Draw(Code(n))
	lit, testUntil, status = owner, 0, 0
end

-- An icon code never stays: the icon hidden, or left without OnLeave; the test ends
-- on time. The status code stays (redrawn when an option or the screen changes).
signal:SetScript("OnUpdate", function()
	if testUntil > 0 then
		if GetTime() >= testUntil then Off() end
	elseif lit and not (lit:IsVisible() and lit:IsMouseOver()) then
		Off()
	elseif not lit and status == 0 then
		Off()
	end
end)

-- Options changed (DuoBox.lua Set), screen or UI scale changed: redraws the status code
function ns.RefreshRelayStatus()
	if not lit and testUntil == 0 then Off() end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local panel = CreateFrame("Frame", "DuoBoxRelayPanel", UIParent)
panel:SetSize(SIZE, SIZE + HANDLE + 2)
panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:Hide()
panel:SetScript("OnHide", Off)

-- Drag strip, the partner's rage bar: moves the panel (the icons themselves
-- never move it, a click on them must stay a click)
local handle = CreateFrame("Frame", nil, panel)
handle:SetPoint("TOPLEFT")
handle:SetPoint("TOPRIGHT")
handle:SetHeight(HANDLE)
handle:EnableMouse(true)
handle:RegisterForDrag("LeftButton")
handle:SetScript("OnDragStart", function() panel:StartMoving() end)
handle:SetScript("OnDragStop", function()
	panel:StopMovingOrSizing()
	panel:SetUserPlaced(true)
end)
local strip = handle:CreateTexture(nil, "BACKGROUND")
strip:SetAllPoints()
strip:SetColorTexture(0, 0, 0, 0.5)
-- The partner's power (rage for the warrior): the bar and the text take the
-- game's values as they are, hidden ones included, never read here
local power = CreateFrame("StatusBar", nil, handle)
power:SetAllPoints()
power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
power:SetStatusBarColor(1, 0, 0)
power:SetMinMaxValues(0, 1)
power:SetValue(0)
local powerText = power:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
powerText:SetPoint("CENTER", 0, 0)
powerText:SetText("Guerrier")
handle:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Rage du guerrier (DuoRelay)")
	GameTooltip:AddLine("Glisser ici : deplacer le panneau. /duo panneau : options.", 1, 1, 1, true)
	GameTooltip:Show()
end)
handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function IconEnter(self)
	Light(self.index, self) -- always: the click needs the code, with or without the tooltip
	if DB() and DB().relayPanelTooltip == false then return end -- Options: no spell tooltips
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local action = self.action and ACTIONS[self.action]
	if action then
		GameTooltip:SetText(action.name)
		GameTooltip:AddLine(action.tip, 1, 1, 1, true)
		GameTooltip:AddLine(("Clic : DuoRelay le fait faire au guerrier (\"pixel\": %d)"):format(self.index), 0.4, 1, 0.4, true)
	else
		if self.spell then GameTooltip:SetSpellByID(self.spell) end
		GameTooltip:AddLine(("Clic : le guerrier lance ce sort (DuoRelay, \"pixel\": %d)"):format(self.index), 0.4, 1, 0.4, true)
	end
	GameTooltip:Show()
end

local function IconLeave()
	Off()
	GameTooltip:Hide()
end

local icons = {}
for i = 1, MAX do
	local b = CreateFrame("Button", nil, panel)
	b:SetSize(SIZE, SIZE)
	b:SetPoint("TOPLEFT", (i - 1) * (SIZE + GAP), -(HANDLE + 2))
	b.index = i
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	b:SetScript("OnEnter", IconEnter)
	b:SetScript("OnLeave", IconLeave)
	-- Swipe and countdown, as on the action bars (numbers: the game's countdownForCooldowns option)
	local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
	if not ok or not cd then cd = CreateFrame("Cooldown", nil, b) end
	cd:SetAllPoints()
	if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
	b.cd = cd
	-- Blink of a spell the partner's game lights up (ProcLight.lua), above the swipe
	local glowFrame = CreateFrame("Frame", nil, b)
	glowFrame:SetAllPoints()
	glowFrame:SetFrameLevel((cd:GetFrameLevel() or 1) + 1)
	local glow = glowFrame:CreateTexture(nil, "OVERLAY")
	glow:SetPoint("TOPLEFT", -SIZE * 0.25, SIZE * 0.25)
	glow:SetPoint("BOTTOMRIGHT", SIZE * 0.25, -SIZE * 0.25)
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:Hide()
	local blink = glow:CreateAnimationGroup()
	blink:SetLooping("BOUNCE")
	local fade = blink:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.15)
	fade:SetDuration(0.35)
	b.glow, b.blink = glow, blink
	b:Hide()
	icons[i] = b
end

local UpdateCooldowns -- draws the icons' cooldowns (below)
local UpdatePower     -- the partner's rage bar (below)
local UpdateGlows     -- the blinks of the lit spells (below)

-- The shown icons (b.slot = 1, 2...) in rows of DB.relayPanelPerRow, left to
-- right then top to bottom; n of them
local function Layout(n)
	local perRow = math.floor(tonumber(DB() and DB().relayPanelPerRow) or MAX)
	perRow = math.max(1, math.min(MAX, perRow))
	for _, b in ipairs(icons) do
		if b.slot then
			local col, row = (b.slot - 1) % perRow, math.floor((b.slot - 1) / perRow)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", col * (SIZE + GAP), -(HANDLE + 2) - row * (SIZE + GAP))
		end
	end
	local cols, rows = math.min(n, perRow), math.ceil(n / perRow)
	panel:SetSize(cols * SIZE + (cols - 1) * GAP, HANDLE + 2 + rows * SIZE + (rows - 1) * GAP)
end

local function Refresh()
	local ids, hidden = Spells(), Hidden()
	local shown = 0
	for i, b in ipairs(icons) do
		local entry = ids[i]
		b.spell = type(entry) == "number" and entry or nil   -- cooldown, blink: spells only
		b.action = type(entry) == "string" and entry or nil
		if entry then
			local icon = b.action and ACTIONS[b.action].icon or select(2, ns.SpellNameIcon(entry))
			b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		end
		b.slot = nil
		if entry ~= nil and not hidden[entry] then
			shown = shown + 1
			b.slot = shown -- its place; b.index (its code) stays its number in the list
		end
		b:SetShown(b.slot ~= nil)
	end
	Layout(math.max(shown, 1))
	panel:SetShown(DB() ~= nil and DB().relayPanel == true and shown > 0)
	if lit and not lit:IsShown() then Off() end
	UpdateCooldowns()
	UpdatePower()
	UpdateGlows()
end
ns.RefreshRelayPanel = Refresh

--------------------------------------------------------------------------------
-- Cooldowns
--------------------------------------------------------------------------------

local CD_PREFIX = "DUOBOXR" -- its own addon message budget
local SYNC_FIRST = 1        -- s between the first clock pings
local SYNC_EVERY = 10       -- s between two pings afterwards (they also ask for the casts)
local FIRST_SAMPLES = 3     -- pings sent SYNC_FIRST apart
local SAMPLES = 8           -- clock samples kept: the shortest round trip gives the offset
local WANT_FOR = 30         -- s the reporting side keeps reporting after the last ping
local GCD = 1.5             -- s, the warrior's global cooldown
local GCD_SPELL = 61304     -- "Global Cooldown": read when the client shows it

-- Own cooldown (s) when the client gives none (Classic values, rank 1 IDs)
local BASE_CD = {
	[7384] = 5, [6343] = 4, [5246] = 180, [100] = 15, [355] = 10, [2687] = 60, [694] = 120, [72] = 12,
	[6572] = 5, [676] = 60, [20230] = 1800, [2565] = 5, [20252] = 30, [1680] = 10, [6552] = 10,
	[18499] = 30, [12294] = 6, [23881] = 6, [23922] = 6, [1161] = 600, [871] = 1800, [1719] = 1800,
	[12292] = 30,
}
-- Spells off the global cooldown (next melee swing, Bloodrage)
local OFF_GCD = { [78] = true, [845] = true, [2687] = true }

local byName = {} -- table -> { spell name -> value }
local function ByName(tbl, name)
	local map = byName[tbl]
	if not map then
		map = {}
		for id, v in pairs(tbl) do
			local n = ns.SpellNameIcon(id)
			if n then map[n] = v end
		end
		byName[tbl] = map
	end
	return map[name]
end

local function Ms(seconds) return math.floor((seconds or GetTime()) * 1000 + 0.5) end

local function Num(v)
	v = Val(v)
	return type(v) == "number" and v or nil
end

-- Start and duration (s) of a cooldown when this client shows it (out of combat), nil when hidden
local function ReadCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(spell)
		if Val(info) == nil or type(info) ~= "table" then return nil end
		local s, d = Num(info.startTime), Num(info.duration)
		if s and d then return s, d end
	elseif GetSpellCooldown then
		local s, d = GetSpellCooldown(spell)
		s, d = Num(s), Num(d)
		if s and d then return s, d end
	end
end

-- "5 sec cooldown" / "3 min cooldown" in the spell's tooltip (English client)
local function TooltipCooldown(id)
	local data = C_TooltipInfo and C_TooltipInfo.GetSpellByID and C_TooltipInfo.GetSpellByID(id)
	if type(Val(data)) ~= "table" or type(data.lines) ~= "table" then return nil end
	for _, line in ipairs(data.lines) do
		for _, text in pairs({ Val(line.leftText) or "", Val(line.rightText) or "" }) do
			local n, unit = tostring(text):match("([%d%.]+) (%a+) cooldown")
			n = tonumber(n)
			if n and unit == "sec" then return n end
			if n and unit == "min" then return n * 60 end
		end
	end
end

-- Global cooldown (s) a spell starts: the game's base value, else the table
local function SpellGcd(id, name)
	if GetSpellBaseCooldown then
		local ok, _, g = pcall(GetSpellBaseCooldown, id)
		g = ok and Num(g)
		if g then return g / 1000 end
	end
	return ByName(OFF_GCD, name) and 0 or GCD
end

local measured = {} -- spell name -> own cooldown (s) read on this client, for the fights where it is hidden

-- Own cooldown (s) of one of this client's spells and where it comes from:
-- m = measured here, b = game base value, t = tooltip, f = table
local function OwnCooldown(id, name)
	if measured[name] then return measured[name], "m" end
	if GetSpellBaseCooldown then
		local ok, c = pcall(GetSpellBaseCooldown, id)
		c = ok and Num(c)
		if c then return c / 1000, "b" end
	end
	local t = TooltipCooldown(id)
	if t then return t, "t" end
	return ByName(BASE_CD, name) or 0, "f"
end

--------------------------------------------------------------------------------
-- Reporting side (the warrior): its own casts, only while the panel side asks
--------------------------------------------------------------------------------

local wantUntil = 0   -- reports sent until then (WANT_FOR after the last ping)
local castStarted = {} -- cast GUIDs whose global cooldown was reported at the cast start

-- withGcd: the cast starts the global cooldown now (instant spell, or a cast time spell's start);
-- withOwn: the spell's own cooldown starts now (the cast succeeded)
local function Report(id, castMs, withGcd, withOwn)
	local name = ns.SpellNameIcon(id)
	if not name then return end
	local cdStart, cdDur, gStart, gDur, src = 0, 0, 0, 0, "-"
	if withOwn then
		local s, d = ReadCooldown(id)
		local gcd = SpellGcd(id, name)
		if s and d and d > gcd + 0.05 then -- the spell's own cooldown, as the game shows it
			cdStart, cdDur, src = Ms(s), Ms(d), "x"
			measured[name] = d
		else
			local own
			own, src = OwnCooldown(id, name)
			if own > 0 then cdStart, cdDur = castMs, Ms(own) end
		end
	end
	if withGcd then
		local gcd = SpellGcd(id, name)
		if gcd > 0 then
			local s, d = ReadCooldown(GCD_SPELL)
			if s and d and d > 0 and d <= 2 then gStart, gDur = Ms(s), Ms(d) else gStart, gDur = castMs, Ms(gcd) end
		end
	end
	if cdDur == 0 and gDur == 0 then return end
	ns.SendComm(("RC:%d:%d:%d:%d:%d:%d:%s"):format(id, Ms(), cdStart, cdDur, gStart, gDur, src), CD_PREFIX)
end

local function OnOwnCast(event, castGUID, spellID)
	spellID, castGUID = Num(spellID), Val(castGUID)
	if not spellID or GetTime() >= wantUntil then return end
	local castMs = Ms()
	local started = castGUID and castStarted[castGUID]
	if event == "UNIT_SPELLCAST_START" then
		if castGUID then
			if #castStarted > 50 then castStarted = {} end -- interrupted casts never succeed: forget them
			castStarted[castGUID] = true
			castStarted[#castStarted + 1] = castGUID
		end
	elseif castGUID then
		castStarted[castGUID] = nil
	end
	-- next frame: the game has started the cooldown by then
	C_Timer.After(0, function()
		if event == "UNIT_SPELLCAST_START" then
			Report(spellID, castMs, true, false)
		else
			Report(spellID, castMs, not started, true)
		end
	end)
end

--------------------------------------------------------------------------------
-- Panel side (the priest): clock offset and the icons' cooldowns
--------------------------------------------------------------------------------

local samples = {}  -- { rtt, offset } in ms: this client's clock = the partner's + offset
local offset, bestRtt
local nextPing = 0
local own = {}      -- spell name -> { start, dur } in s on this client's clock
local gcdState      -- { start, dur }
local last          -- last report: { name, src, at }

local function OnGcd(id)
	return SpellGcd(id, ns.SpellNameIcon(id)) > 0
end

UpdateCooldowns = function()
	local now = GetTime()
	for _, b in ipairs(icons) do
		local best
		local name = b.spell and ns.SpellNameIcon(b.spell)
		local o = name and own[name]
		if o and o.start + o.dur > now then best = o end
		local g = gcdState
		if g and b.spell and g.start + g.dur > now and OnGcd(b.spell) and (not best or g.start + g.dur > best.start + best.dur) then
			best = g
		end
		if best then
			b.cd:SetCooldown(best.start, best.dur)
		elseif b.cd.Clear then
			b.cd:Clear()
		else
			b.cd:SetCooldown(0, 0)
		end
	end
end

local function OnClockReply(t1, t2)
	local t3 = Ms()
	local rtt = t3 - t1
	if rtt < 0 or rtt > 5000 then return end
	table.insert(samples, { rtt = rtt, offset = (t1 + t3) / 2 - t2 })
	if #samples > SAMPLES then table.remove(samples, 1) end
	local best
	for _, s in ipairs(samples) do if not best or s.rtt < best.rtt then best = s end end
	offset, bestRtt = best.offset, best.rtt
end

local function OnCastReport(id, sent, cdStart, cdDur, gStart, gDur, src)
	local recv = Ms()
	-- the partner's clock (ms) -> this client's (s); without a ping answer yet, the message counts as instant
	local function Here(ms) return (offset and ms + offset or ms - sent + recv) / 1000 end
	local name = ns.SpellNameIcon(id)
	if not name then return end
	if cdDur > 0 then own[name] = { start = Here(cdStart), dur = cdDur / 1000 } end
	if gDur > 0 then gcdState = { start = Here(gStart), dur = gDur / 1000 } end
	last = { name = name, src = src, at = GetTime() }
	UpdateCooldowns()
end

local function Tick()
	C_Timer.After(1, Tick)
	if not (panel:IsShown() and ns.PartnerUnit()) then return end
	local now = GetTime()
	if now < nextPing then return end
	nextPing = now + (#samples < FIRST_SAMPLES and SYNC_FIRST or SYNC_EVERY)
	ns.SendComm("RT:" .. Ms(), CD_PREFIX)
end

local SOURCES = { x = "exacte", m = "mesuree hors combat", b = "valeur du jeu", t = "infobulle", f = "table DuoBox", ["-"] = "-" }

local function CooldownDebug()
	if offset then
		Say(("recharges : horloge du partenaire calee (aller-retour %d ms, decalage %d ms, %d mesures)")
			:format(bestRtt, offset, #samples))
	else
		Say("recharges : pas encore de reponse du partenaire (panneau affiche ? meme version de DuoBox sur les deux ?)")
	end
	if last then
		Say(("recharges : dernier sort recu : %s il y a %.0f s (recharge %s)"):format(last.name, GetTime() - last.at,
			SOURCES[last.src] or last.src))
	end
end

local cdEvents = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(CD_PREFIX)
elseif RegisterAddonMessagePrefix then
	RegisterAddonMessagePrefix(CD_PREFIX)
end
cdEvents:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, body, channel, sender = ...
		if prefix ~= CD_PREFIX or channel ~= "PARTY" then return end
		body = ns.FromPartner(body, sender)
		if type(body) ~= "string" then return end
		local t1 = body:match("^RT:(%d+)$")
		if t1 then -- the panel side asks: answer with this clock, report the casts for a while
			wantUntil = GetTime() + WANT_FOR
			ns.SendComm(("RU:%s:%d"):format(t1, Ms()), CD_PREFIX)
			return
		end
		local a, b = body:match("^RU:(%d+):(%d+)$")
		if a then OnClockReply(tonumber(a), tonumber(b)); return end
		local f = { body:match("^RC:(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):([%a%-])$") }
		if #f == 7 then
			OnCastReport(tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), f[7])
		end
	elseif event == "PLAYER_LOGIN" then
		C_Timer.After(1, Tick)
	else -- UNIT_SPELLCAST_START / _SUCCEEDED; another unit's payload can be secret: test it first
		local unit, castGUID, spellID = ...
		if Val(unit) == "player" then OnOwnCast(event, castGUID, spellID) end
	end
end)
for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_LOGIN" }) do
	pcall(cdEvents.RegisterEvent, cdEvents, e)
end
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
	if cdEvents.RegisterUnitEvent then
		pcall(cdEvents.RegisterUnitEvent, cdEvents, e, "player") -- only this character's casts
	else
		pcall(cdEvents.RegisterEvent, cdEvents, e)
	end
end

--------------------------------------------------------------------------------
-- Blinks: the spells the partner's game lights up (Overpower after a dodge,
-- Execute under 20 %, Victory Rush after a kill), from the event light's
-- messages (ProcLight.lua, the partner's "Voyant des evenements" option);
-- yellow when castable, blue when short of rage
--------------------------------------------------------------------------------

local procLit = {} -- spell name -> true (ready) / false (short of rage)

UpdateGlows = function()
	for _, b in ipairs(icons) do
		local name = b.spell and ns.SpellNameIcon(b.spell)
		local state = name and procLit[name]
		if state ~= nil and b:IsShown() then
			if state then b.glow:SetVertexColor(1, 0.9, 0.2) else b.glow:SetVertexColor(0.3, 0.55, 1) end
			b.glow:Show()
			if not b.blink:IsPlaying() then b.blink:Play() end
		else
			b.blink:Stop()
			b.glow:Hide()
		end
	end
end

-- list: { { id, ready }, ... }, empty when everything went out (or no news for 3 s)
ns.OnPartnerProcs = function(list)
	procLit = {}
	for _, p in ipairs(list or {}) do
		local name = ns.SpellNameIcon(p.id)
		if name then procLit[name] = p.ready and true or false end
	end
	UpdateGlows()
end

--------------------------------------------------------------------------------
-- The partner's rage bar (its power: mana for a hunter), in place of a title
--------------------------------------------------------------------------------

local POWER_COLOR = { [0] = { 0, 0.55, 1 }, [1] = { 1, 0, 0 }, [2] = { 1, 0.5, 0.25 }, [3] = { 1, 1, 0 } }

UpdatePower = function()
	local unit = ns.PartnerUnit()
	if not panel:IsShown() then return end
	if not unit or not Val(UnitExists(unit)) then
		power:SetMinMaxValues(0, 1)
		power:SetValue(0)
		powerText:SetText("Guerrier")
		return
	end
	local kind = Num(UnitPowerType(unit)) or 1
	local c = PowerBarColor and PowerBarColor[kind]
	if type(c) == "table" and c.r then
		power:SetStatusBarColor(c.r, c.g, c.b)
	else
		c = POWER_COLOR[kind] or POWER_COLOR[1]
		power:SetStatusBarColor(c[1], c[2], c[3])
	end
	-- possibly hidden values: handed to the bar and the text as they are, never compared
	power:SetMinMaxValues(0, UnitPowerMax(unit, kind))
	power:SetValue(UnitPower(unit, kind))
	powerText:SetFormattedText("%d", UnitPower(unit, kind))
end

local powerEvents = CreateFrame("Frame")
powerEvents:SetScript("OnEvent", function(_, event, unit)
	if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		UpdatePower()
	elseif Val(unit) ~= nil and Val(unit) == ns.PartnerUnit() then -- UNIT_POWER_*, UNIT_MAXPOWER, UNIT_DISPLAYPOWER
		UpdatePower()
	end
end)
for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	"GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
	pcall(powerEvents.RegisterEvent, powerEvents, e)
end

--------------------------------------------------------------------------------
-- /duo panneau
--------------------------------------------------------------------------------

-- "Victory Rush, Slam, 5308" -> IDs, and the parts not understood
local function Parse(text)
	local ids, bad = {}, {}
	for part in text:gmatch("[^,;]+") do
		part = part:match("^%s*(.-)%s*$")
		if part ~= "" then
			local action = ACTION_NAMES[part:lower()]
			local id = tonumber(part) or NAMES[part:lower()]
			if action then
				ids[#ids + 1] = action
			elseif id and ns.SpellNameIcon(id) then
				ids[#ids + 1] = id
			else
				bad[#bad + 1] = part
			end
		end
	end
	return ids, bad
end

local function List()
	local parts, hidden = {}, Hidden()
	for i, entry in ipairs(Spells()) do
		parts[#parts + 1] = ("%d %s%s"):format(i, EntryName(entry), hidden[entry] and " (masque)" or "")
	end
	return #parts > 0 and table.concat(parts, ", ") or "aucun sort"
end

-- /duo panneau test [n]: icon n's code drawn TEST s without the mouse, and
-- where it is in screen pixels, to check with DuoRelay.ps1 -PixelProbe
local TEST = 15
local function Test(n)
	Light(n)
	testUntil = GetTime() + TEST
	C_Timer.After(0.5, function() -- once drawn
		if testUntil == 0 then return end
		local ppu = PixelsPerUnit()
		local left, top, screenTop = signal:GetLeft(), signal:GetTop(), UIParent:GetTop()
		local function px(v) return v and ("%.0f"):format(v * ppu) or "?" end
		Say(("test : code de l'icone %d pendant %d s, %s, coin a x=%s y=%s px, carres de %s px (ecran de %d px, echelle %.2f). "
			.. "DuoRelay.ps1 -PixelProbe doit afficher \"icon %d\". Relais OFF pendant le test : un clic gauche le relaierait.")
			:format(n, TEST, signal:IsVisible() and "visible" or "|cffff4040invisible|r", px(left),
				px(top and screenTop and screenTop - top), px(signal:GetHeight()), PhysicalHeight(),
				signal:GetEffectiveScale(), n))
	end)
end

function ns.RelayPanelCommand(arg)
	local sub, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	sub = sub:lower()
	if sub == "" or sub == "on" or sub == "off" then
		local on = sub == "on" or (sub == "" and not DB().relayPanel)
		ns.Set("relayPanel", on)
		Say(("panneau de sorts du guerrier : %s%s"):format(on and "|cff40ff40on|r" or "|cffff4040off|r",
			on and " (glisser la bande du haut pour le deplacer)" or ""))
	elseif sub == "sorts" or sub == "spells" then
		if rest ~= "" then
			local ids, bad = Parse(rest)
			if #bad > 0 then
				Say(("panneau : inconnu : %s. Noms anglais (Slam, Thunder Clap...), ID du sort ou interact ; rien de change.")
					:format(table.concat(bad, ", ")))
				return
			elseif #ids > MAX then
				Say(("panneau : %d sorts au plus ; rien de change."):format(MAX))
				return
			end
			ns.Set("relayPanelSpells", table.concat(ids, ","))
		end
		Say("panneau : " .. List() .. " (numero = \"pixel\" du declencheur dans DuoRelay.json)")
	elseif sub == "defaut" or sub == "reset" then
		ns.Set("relayPanelSpells", ns.DEFAULTS.relayPanelSpells)
		Say("panneau : " .. List())
	elseif sub == "cd" or sub == "recharges" then
		CooldownDebug()
	elseif sub == "test" then
		local n = tonumber(rest) or 2
		if n < 1 or n > 36 or n % 1 ~= 0 then
			Say("panneau : /duo panneau test <numero d'icone, 1 a 36>")
			return
		end
		Test(n)
	else
		Say("/duo panneau [on|off] | sorts <noms, ID ou interact, separes par des virgules> | defaut | test [numero] | cd")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then Refresh() end
	ns.RefreshRelayStatus() -- the status code, at its size in screen pixels
end)
