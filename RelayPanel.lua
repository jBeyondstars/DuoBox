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
-- Option DB.relayPanel (off by default); the spells, DB.relayPanelSpells, are
-- only shown here (icon, tooltip): their order is the "pixel" number of the
-- DuoRelay.json triggers. /duo panneau. Kept out of DuoBox.lua (Lua 5.1's 200
-- locals).
--------------------------------------------------------------------------------

local _, ns = ...

local MAX = 10      -- icons
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
	["mortal strike"] = 12294, bloodthirst = 23881, ["shield slam"] = 23922,
}

local function DB() return ns.GetDB() end

local function Say(msg) ns.Print(msg) end

-- Spell IDs of the panel, in order ("402927,1240193" in the settings)
local function Spells()
	local ids = {}
	for id in tostring(DB() and DB().relayPanelSpells or ""):gmatch("%d+") do
		if #ids < MAX then ids[#ids + 1] = tonumber(id) end
	end
	return ids
end

--------------------------------------------------------------------------------
-- The code in the top-left corner
--------------------------------------------------------------------------------

-- The CELLS values (0-7) that say icon n (1-36)
local function Code(n)
	local a, b = math.floor((n - 1) / 6) + 1, (n - 1) % 6 + 1
	return { a, 7 - a, b, 7 - b }
end
ns.RelayPanelCode = Code

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
local lit           -- icon whose code is drawn (nil: /duo panneau test)
local testUntil = 0 -- /duo panneau test: code drawn without the mouse until then

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

local function Off()
	lit, testUntil = nil, 0
	signal:Hide()
end

-- Draws the code of icon n; owner: the icon under the mouse
local function Light(n, owner)
	local size = CELL / PixelsPerUnit()
	signal:SetSize(size * CELLS, size)
	for i, v in ipairs(Code(n)) do
		local sq = squares[i]
		sq:ClearAllPoints()
		sq:SetSize(size, size)
		sq:SetPoint("TOPLEFT", (i - 1) * size, 0)
		sq:SetColorTexture(math.floor(v / 4) % 2, math.floor(v / 2) % 2, v % 2, 1)
	end
	lit, testUntil = owner, 0
	signal:Show()
end

-- Never left on: the icon hidden, or left without OnLeave; the test ends on time
signal:SetScript("OnUpdate", function()
	if testUntil > 0 then
		if GetTime() >= testUntil then Off() end
	elseif not (lit and lit:IsVisible() and lit:IsMouseOver()) then
		Off()
	end
end)

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

-- Drag strip: moves the panel (the icons themselves never move it, a click on
-- them must stay a click)
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
local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("LEFT", 2, 0)
title:SetText("Guerrier")
handle:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Sorts du guerrier (DuoRelay)")
	GameTooltip:AddLine("Glisser ici : deplacer le panneau. /duo panneau : options.", 1, 1, 1, true)
	GameTooltip:Show()
end)
handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function IconEnter(self)
	Light(self.index, self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if self.spell then GameTooltip:SetSpellByID(self.spell) end
	GameTooltip:AddLine(("Clic : le guerrier lance ce sort (DuoRelay, \"pixel\": %d)"):format(self.index), 0.4, 1, 0.4, true)
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
	b:Hide()
	icons[i] = b
end

local function Refresh()
	local ids = Spells()
	for i, b in ipairs(icons) do
		b.spell = ids[i]
		if ids[i] then
			local _, icon = ns.SpellNameIcon(ids[i])
			b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		end
		b:SetShown(ids[i] ~= nil)
	end
	local n = math.max(#ids, 1)
	panel:SetWidth(n * SIZE + (n - 1) * GAP)
	panel:SetShown(DB() ~= nil and DB().relayPanel == true and #ids > 0)
	if lit and not lit:IsShown() then Off() end
end
ns.RefreshRelayPanel = Refresh

--------------------------------------------------------------------------------
-- /duo panneau
--------------------------------------------------------------------------------

-- "Victory Rush, Slam, 5308" -> IDs, and the parts not understood
local function Parse(text)
	local ids, bad = {}, {}
	for part in text:gmatch("[^,;]+") do
		part = part:match("^%s*(.-)%s*$")
		if part ~= "" then
			local id = tonumber(part) or NAMES[part:lower()]
			if id and ns.SpellNameIcon(id) then ids[#ids + 1] = id else bad[#bad + 1] = part end
		end
	end
	return ids, bad
end

local function List()
	local parts = {}
	for i, id in ipairs(Spells()) do
		parts[#parts + 1] = ("%d %s"):format(i, ns.SpellNameIcon(id) or id)
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
				Say(("panneau : inconnu : %s. Noms anglais (Slam, Thunder Clap...) ou ID du sort ; rien de change.")
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
	elseif sub == "test" then
		local n = tonumber(rest) or 2
		if n < 1 or n > 36 or n % 1 ~= 0 then
			Say("panneau : /duo panneau test <numero d'icone, 1 a 36>")
			return
		end
		Test(n)
	else
		Say("/duo panneau [on|off] | sorts <noms ou ID, separes par des virgules> | defaut | test [numero]")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", Refresh)
