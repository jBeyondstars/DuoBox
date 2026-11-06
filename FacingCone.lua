--------------------------------------------------------------------------------
-- DuoBox / facing cone ("cone d'orientation"): on this screen, a yellow cone at
-- the partner's feet, pointing where the partner faces, so the main (the
-- priest) sees whether the warrior faces its mob. Optional, off by default.
-- An addon cannot draw in the 3D world: the cone is a flat drawing anchored to
-- the partner's nameplate, so friendly nameplates must be on (turned on with
-- the option, Shift+V hides them). Blizzard locks friendly nameplates for
-- addons in instances: no cone in dungeons.
-- Projection, estimated:
--   * no API gives the camera's direction: the camera is assumed behind this
--     character (true after a walk or a right-click turn, false while the
--     camera is turned with the left button),
--   * the depth camera -> partner (GetCameraZoom + the two positions, open
--     world only) sets the cone's size and how far under the nameplate the
--     feet are (DB.coneHeight, in %, corrects it); the camera pitch is a guess.
-- Facing: the partner's client sends GetPlayerFacing() as "CF:<milliradians>"
-- while this client asks for it ("CQ" every 2 s while the partner's nameplate
-- is there): only the side that shows the cone needs the option. Sent on a
-- 3 degree change, at most every 0.15 s, and every 2 s unchanged, on its own
-- prefix (its own addon message budget); a throttled send is retried.
-- /duo cone debug: what the client answers. Kept out of DuoBox.lua (Lua 5.1's
-- 200 locals).
--------------------------------------------------------------------------------

local _, ns = ...

local PREFIX = "DUOBOXC"
local TICK = 0.1          -- s: answering side
local DRAW_EVERY = 0.03   -- s between two redraws (the cone follows this character's turns)
local ASK_EVERY = 2       -- s between two requests while the cone is wanted
local ASK_HOLD = 6        -- s an answering client keeps sending after a request
local MIN_GAP = 0.15      -- s between two facing sends
local KEEPALIVE = 2       -- s: the facing is sent again even unchanged
local STEP = 0.05         -- rad (3 degrees): a smaller turn is not sent
local STALE = 5           -- s without a facing: the cone hides
local HALF = math.rad(45) -- half-angle of the cone
local LENGTH = 5          -- yards on the ground (melee reach)
local BODY = 2.4          -- yards from the feet up to the nameplate (DB.coneHeight scales it)
local PITCH_K = 0.5       -- ground foreshortening: sin of the camera pitch (about 30 degrees), a guess
local FOCAL = 0.9         -- UI units per yard at 1 yard of depth, per unit of UIParent's height (field of view guess)
local ZOOM = 15           -- yards: camera distance when GetCameraZoom is missing
local MIN_DEPTH = 2       -- yards
local MIN_LEN = 12        -- UI units: a far cone stays visible
local ARC = 6             -- segments of the cone's arc
local TWO_PI = 2 * math.pi
local COLOR = { 1, 0.82, 0, 0.9 }

local function DB() return ns.GetDB() end

-- The secret test comes first: comparing a secret value, even to nil, is refused
local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function Refused(r) return r == false or (type(r) == "number" and r ~= 0) end

-- This character's facing (radians, 0 = north, counterclockwise), nil if hidden
local function Facing()
	if not GetPlayerFacing then return nil end
	local ok, f = pcall(GetPlayerFacing)
	f = ok and Val(f) or nil
	return type(f) == "number" and f or nil
end

-- x = west, y = north, the convention of DuoBox.lua's WorldPos (facing f points to (sin f, cos f))
local function WorldPos(unit)
	if not UnitPosition then return nil end
	local ok, y, x = pcall(UnitPosition, unit)
	if not ok then return nil end
	y, x = Val(y), Val(x)
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

local function Zoom()
	if not GetCameraZoom then return nil end
	local ok, z = pcall(GetCameraZoom)
	z = ok and Val(z) or nil
	return type(z) == "number" and z or nil
end

local function AngleGap(a, b)
	local d = (a - b) % TWO_PI
	return math.min(d, TWO_PI - d)
end

--------------------------------------------------------------------------------
-- Answering side: send this character's facing while the partner asks for it
--------------------------------------------------------------------------------

local askedAt = -100       -- last request from the partner
local sentF, sentAt = nil, -100

local function Answer()
	local now = GetTime()
	if now - askedAt > ASK_HOLD or not ns.PartnerUnit() then return end
	local f = Facing()
	if not f then return end
	local changed = not sentF or AngleGap(f, sentF) >= STEP
	if (changed and now - sentAt >= MIN_GAP) or now - sentAt >= KEEPALIVE then
		if Refused(ns.SendComm(("CF:%d"):format(math.floor(f * 1000 + 0.5)), PREFIX)) then return end -- next tick
		sentF, sentAt = f, now
	end
end

--------------------------------------------------------------------------------
-- Showing side: the cone
--------------------------------------------------------------------------------

-- Screen offsets (UI units, x right, y up) from the partner's feet. rel: the
-- partner's facing minus this character's (radians, positive = the partner
-- faces left of where the camera looks); len: the cone's length on the ground
-- in UI units at the partner's depth; k: foreshortening of the ground's depth.
-- Returns the ARC + 1 points of the arc (right edge first) and the middle point.
function ns.ConeShape(rel, len, k)
	local function At(a) return { -math.sin(a) * len, math.cos(a) * len * k } end
	local arc = {}
	for i = 0, ARC do arc[#arc + 1] = At(rel - HALF + 2 * HALF * i / ARC) end
	return arc, At(rel)
end

local holder = CreateFrame("Frame", "DuoBoxFacingCone", UIParent)
holder:SetSize(1, 1)
holder:SetFrameStrata("BACKGROUND")
holder:EnableMouse(false)
holder:Hide()

-- 1-2: the edges, 3..ARC+2: the arc, last: the middle (thinner)
local lines = {}
for i = 1, ARC + 3 do
	local line = holder:CreateLine(nil, "ARTWORK")
	line:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], i == ARC + 3 and 0.6 or COLOR[4])
	line:SetThickness(i == ARC + 3 and 2 or 3)
	lines[i] = line
end

local function SetLine(line, a, b)
	line:SetStartPoint("CENTER", holder, a[1], a[2])
	line:SetEndPoint("CENTER", holder, b[1], b[2])
end

local partnerF, partnerAt = nil, -100 -- received facing
local askAt = -100                    -- last request sent
local plateToken                      -- the partner's nameplate token, from NAME_PLATE_UNIT_ADDED
local anchoredTo, anchoredFeet
local state = "jamais calcule"        -- why the cone is hidden, for /duo cone debug
local last = {}                       -- last computation, for /duo cone debug

local function PartnerPlate(unit)
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	if not get then return nil end
	local ok, plate = pcall(get, unit)
	if ok and plate then return plate, "unite" end
	if plateToken then
		ok, plate = pcall(get, plateToken)
		if ok and plate then return plate, plateToken end
	end
end

local function Ask(now)
	if now - askAt < ASK_EVERY then return end
	if not Refused(ns.SendComm("CQ", PREFIX)) then askAt = now end
end

-- UI units per yard at the partner's depth (camera assumed behind this character)
local function Scale(unit, myF)
	local zoom = Zoom()
	local forward
	local px, py = WorldPos("player")
	local wx, wy = WorldPos(unit)
	if px and wx then forward = (wx - px) * math.sin(myF) + (wy - py) * math.cos(myF) end
	local depth = math.max(MIN_DEPTH, (zoom or ZOOM) + (forward or 0))
	last.zoom, last.forward, last.depth = zoom, forward, depth
	return FOCAL * UIParent:GetHeight() / depth
end

local function Hide(why)
	state = why
	if holder:IsShown() then holder:Hide() end
end

local function Draw()
	local db = DB()
	if not db or not db.facingCone then return Hide("option desactivee") end
	if ns.IsMoveMode and ns.IsMoveMode() then return Hide("mode deplacement") end
	local unit = ns.PartnerUnit()
	if not unit then return Hide("pas de partenaire dans le groupe") end
	local plate = PartnerPlate(unit)
	if not plate then return Hide("pas de barre de nom du partenaire (barres amies : Maj+V ; bloquees en donjon)") end
	local now = GetTime()
	Ask(now)
	if not partnerF or now - partnerAt > STALE then
		return Hide("orientation du partenaire pas recue (DuoBox a jour sur son PC ?)")
	end
	local myF = Facing()
	if not myF then return Hide("ma propre orientation est illisible") end

	local scale = Scale(unit, myF)
	local feet = BODY * (db.coneHeight or 100) / 100 * scale
	if plate ~= anchoredTo or math.abs(feet - anchoredFeet) > 0.5 then
		holder:ClearAllPoints()
		holder:SetPoint("CENTER", plate, "BOTTOM", 0, -feet)
		anchoredTo, anchoredFeet = plate, feet
	end
	local rel = (partnerF - myF) % TWO_PI
	if rel > math.pi then rel = rel - TWO_PI end
	local arc, mid = ns.ConeShape(rel, math.max(MIN_LEN, LENGTH * scale), PITCH_K)
	local apex = { 0, 0 }
	SetLine(lines[1], apex, arc[1])
	SetLine(lines[2], apex, arc[#arc])
	for i = 1, ARC do SetLine(lines[i + 2], arc[i], arc[i + 1]) end
	SetLine(lines[ARC + 3], apex, mid)
	last.rel, last.scale, last.feet = rel, scale, feet
	state = "affiche"
	if not holder:IsShown() then holder:Show() end
end

local function CVarOn(name)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	return get and tostring(get(name)) == "1"
end

-- The cone needs the partner's nameplate: friendly ones on (a protected CVar: not in combat)
local function ShowFriendlyPlates()
	if CVarOn("nameplateShowFriends") then return end
	if InCombatLockdown() then
		ns.Print("cone : active les barres de nom amies (Maj+V), le cone en a besoin.")
		return
	end
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if set then pcall(set, "nameplateShowFriends", "1") end
	ns.Print("cone : barres de nom amies activees, le cone en a besoin (Maj+V pour les masquer).")
end

function ns.RefreshCone(key)
	if key == "facingCone" and DB().facingCone then ShowFriendlyPlates() end
	Draw()
end

-- /duo cone debug (on the side that shows the cone; the answering side's line tells
-- whether the partner asks)
function ns.ConeCommand()
	local out = {}
	local function add(s) out[#out + 1] = s end
	local function deg(r) return r and ("%d deg"):format(math.floor(math.deg(r) + 0.5)) or "nil" end
	local function num(v) return v and ("%.1f"):format(v) or "nil" end
	local now = GetTime()
	Draw()
	local unit = ns.PartnerUnit()
	local _, where = PartnerPlate(unit or "none")
	local inInstance = IsInInstance and Val((IsInInstance())) or nil
	add(("%s  cone : %s"):format(date and date("%H:%M:%S") or "", state))
	add(("barres de nom amies (nameplateShowFriends) = %s ; en instance = %s"):format(
		CVarOn("nameplateShowFriends") and "oui" or "non", tostring(inInstance)))
	add(("partenaire = %s ; sa barre de nom = %s"):format(tostring(unit), where and ("trouvee (" .. where .. ")") or "absente"))
	add(("orientation du partenaire = %s, recue %s"):format(deg(partnerF),
		partnerAt > 0 and ("il y a %.1f s"):format(now - partnerAt) or "jamais"))
	add(("mon orientation = %s ; angle relatif = %s"):format(deg(Facing()), deg(last.rel)))
	add(("zoom camera = %s ; partenaire devant = %s m ; profondeur = %s m ; echelle = %s ; pieds = %s"):format(
		num(last.zoom), num(last.forward), num(last.depth), num(last.scale), num(last.feet)))
	add(("cote partenaire : demande recue %s ; mon orientation envoyee %s"):format(
		askedAt > 0 and ("il y a %.1f s"):format(now - askedAt) or "jamais",
		sentAt > 0 and ("il y a %.1f s"):format(now - sentAt) or "jamais"))
	DB().coneDebug = out
	ns.Print("--- diagnostic du cone (fais /reload pour l'enregistrer) ---")
	for _, s in ipairs(out) do ns.Print(s) end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
elseif RegisterAddonMessagePrefix then
	RegisterAddonMessagePrefix(PREFIX)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, body, channel, sender = ...
		if prefix ~= PREFIX or channel ~= "PARTY" then return end
		body = ns.FromPartner(body, sender)
		if body == "CQ" then
			local now = GetTime()
			if now - askedAt > ASK_HOLD then sentF = nil end -- a new request: answer at once
			askedAt = now
			return
		end
		local mrad = type(body) == "string" and tonumber(body:match("^CF:(%d+)$"))
		if mrad then partnerF, partnerAt = mrad / 1000, GetTime() end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local token = ...
		local unit = ns.PartnerUnit()
		if unit and Val(UnitIsUnit(token, unit)) then plateToken = token end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		if ... == plateToken then plateToken = nil end
	elseif event == "PLAYER_LOGIN" then
		C_Timer.NewTicker(TICK, Answer)
		C_Timer.NewTicker(DRAW_EVERY, Draw)
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
