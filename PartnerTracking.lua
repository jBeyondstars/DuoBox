--------------------------------------------------------------------------------
-- Live gathering detections shared with the partner. The client does not expose
-- tracking blip positions. Known GatherLite locations aim a tooltip scan; only
-- native minimap tooltips confirm a hit. No historical pin is sent as a detection.
-- Technique described at https://github.com/ThorbenP/wow-noderadar#how-it-works
-- This implementation keeps existing minimap textures and restores its UI state.
--------------------------------------------------------------------------------
local _, ns = ...
local INTERVAL, TTL, MAX_PINS, MAX_SAMPLES = 5, 15, 128, 32
local KIND = { [2580] = "O", [2383] = "H" }
local NODE_KIND = { O = "mining", H = "herbalism" }
local ICON = { O = "Interface\\Icons\\Spell_Nature_Earthquake", H = "Interface\\Icons\\INV_Misc_Flower_02" }
-- Minimap diameters in yards, as used by HereBeDragons on Classic clients.
local DIAMETER = { outdoor = { [0] = 1400 / 3, 400, 1000 / 3, 800 / 3, 200, 400 / 3 },
	indoor = { [0] = 300, 240, 180, 120, 80, 50 } }
local ev = CreateFrame("Frame")
local ready, held, queue, pending, peer
local received, pool, sent = {}, {}, {}
local hbd, pins, gather
local Safe
local pulse, nextScan, nextStatus, candidateOffset = 0, 0, 0, 0
local stats = { samples = 0, hits = 0, count = 0 }

local function DB() return ns.GetDB() end
local function Value(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
local function Number(v)
	v = Value(v)
	return type(v) == "number" and v == v and math.abs(v) < 1000000 and v or nil
end
local function Dependencies()
	if LibStub then
		hbd = LibStub("HereBeDragons-2.0", true)
		pins = LibStub("HereBeDragons-Pins-2.0", true)
	end
	gather = _G.GatherLite
	return hbd and pins
end
local function Partner()
	if not DB().partner then return end
	local unit = ns.PartnerUnit()
	if not unit or not Value(UnitIsConnected(unit)) then return end
	return Value(UnitGUID(unit))
end
local function Tracking()
	local api = C_Minimap
	local count = (api and api.GetNumTrackingTypes) or GetNumTrackingTypes
	local info = (api and api.GetTrackingInfo) or GetTrackingInfo
	if not count or not info then return end
	for i = 1, count() do
		local name, texture, active = info(i)
		local spell
		if type(Value(name)) == "table" then
			spell, texture, active, name = Value(name.spellID), Value(name.texture), Value(name.active), Value(name.name)
		else
			name, texture, active = Value(name), Value(texture), Value(active)
		end
		if active == true or active == 1 then
			if KIND[spell] then return KIND[spell] end
			for id, kind in pairs(KIND) do
				local spellName, spellTexture
				if C_Spell and C_Spell.GetSpellInfo then
					local data = C_Spell.GetSpellInfo(id)
					if data then spellName, spellTexture = Value(data.name), Value(data.iconID) end
				elseif GetSpellInfo then
					local n, _, icon = GetSpellInfo(id)
					spellName, spellTexture = Value(n), Value(icon)
				end
				if (spellName and spellName == name) or (spellTexture and spellTexture == texture) then return kind end
			end
		end
	end
end
local function ClearPins()
	for key, record in pairs(received) do
		if pins then pins:RemoveMinimapIcon(ns, record.frame) end
		record.frame:Hide()
		pool[#pool + 1] = record.frame
		received[key] = nil
	end
	stats.count = 0
end
local function Release()
	queue, pending = nil, nil
	if not held then return end
	local saved = held
	-- Clear held first, including if an individual restoration operation fails.
	held = nil
	if saved.total then candidateOffset = (saved.offset + saved.consumed) % saved.total end
	pcall(Minimap.ClearAllPoints, Minimap)
	for _, point in ipairs(saved.points) do pcall(Minimap.SetPoint, Minimap, unpack(point)) end
	pcall(Minimap.SetAlpha, Minimap, saved.alpha)
	pcall(Minimap.SetFrameStrata, Minimap, saved.strata)
	pcall(Minimap.SetFrameLevel, Minimap, saved.level)
	pcall(Minimap.SetMouseClickEnabled, Minimap, saved.click)
	pcall(Minimap.SetMouseMotionEnabled, Minimap, saved.motion)
	for _, state in ipairs(saved.children) do
		pcall(state.frame.SetMouseClickEnabled, state.frame, state.click)
		pcall(state.frame.SetMouseMotionEnabled, state.frame, state.motion)
	end
	GameTooltip:Hide()
	GameTooltip:SetAlpha(saved.tooltipAlpha)
end
local function Blocked()
	return InCombatLockdown() or Value(UnitIsDeadOrGhost("player")) or IsInInstance()
		or (IsMouselooking and IsMouselooking()) or (SpellIsTargeting and SpellIsTargeting())
		or not Minimap:IsVisible()
end
local function Geometry()
	local x, y, instance = hbd:GetPlayerWorldPosition()
	x, y, instance = Number(x), Number(y), Number(instance)
	if not x or not y or not instance then return end
	local zoom = Number(Minimap:GetZoom())
	local size = DIAMETER[tonumber(GetCVar("minimapZoom")) == zoom and "outdoor" or "indoor"]
	local diameter = zoom and size[zoom]
	local radius = C_Minimap and C_Minimap.GetViewRadius and Number(C_Minimap.GetViewRadius())
	radius = radius or (diameter and diameter / 2)
	local width, height = Number(Minimap:GetWidth()), Number(Minimap:GetHeight())
	if not radius or radius <= 0 or not width or width <= 0 or not height or height <= 0 then return end
	local facing = 0
	if GetCVar("rotateMinimap") == "1" then
		facing = Number(GetPlayerFacing())
		if not facing then return end
	end
	return { x = x, y = y, instance = instance, radius = radius, width = width / 2, height = height / 2,
		sin = math.sin(facing), cos = math.cos(facing) }
end
local function Offset(g, x, y)
	local dx, dy = g.x - x, g.y - y
	return (dx * g.cos - dy * g.sin) * g.width / g.radius,
		-(dx * g.sin + dy * g.cos) * g.height / g.radius
end
local function NativeTooltip()
	if not GameTooltip:IsShown() or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return false end
	local owner = GameTooltip:GetOwner()
	if owner and owner ~= Minimap and owner ~= UIParent then return false end
	-- Historical addon pins must never be treated as live tracking blips.
	if GetMouseFoci then
		local foci = GetMouseFoci()
		return foci and foci[1] == Minimap
	elseif GetMouseFocus then
		return GetMouseFocus() == Minimap
	end
	return owner == Minimap
end
local function Clean(name)
	name = Value(name)
	if type(name) ~= "string" then return end
	name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
	if name == "" or #name > 96 or name:find("[|\r\n]") then return end
	return name
end
local function Confirm(point)
	stats.samples = stats.samples + 1
	if not NativeTooltip() then return end
	for i = 1, math.min(GameTooltip:NumLines(), 20) do
		local line = _G["GameTooltipTextLeft" .. i]
		local name = line and Clean(line:GetText())
		local object = name and gather:GetObject(name)
		local kind = object and (object.type == "ore" and "O" or object.type == "herb" and "H")
		if kind == point.kind then
			-- Positions are the aimed spawn locations, not object coordinates from an API.
			local key = ("%s:%d:%.0f:%.0f"):format(kind, point.instance, point.x, point.y)
			local now = GetTime()
			if not sent[key] or now - sent[key] >= 2 then
				ns.SendComm(("TN:%d:%.2f:%.2f:%s:%s"):format(point.instance, point.x, point.y, kind, name))
				sent[key] = now
				stats.hits = stats.hits + 1
			end
		end
	end
end
local function Hold()
	if Minimap:GetNumPoints() == 0 then return false end
	local saved = { points = {}, children = {}, alpha = Minimap:GetAlpha(), strata = Minimap:GetFrameStrata(),
		level = Minimap:GetFrameLevel(), click = Minimap:IsMouseClickEnabled(), motion = Minimap:IsMouseMotionEnabled(),
		tooltipAlpha = GameTooltip:GetAlpha(), started = GetTime() }
	for i = 1, Minimap:GetNumPoints() do saved.points[i] = { Minimap:GetPoint(i) } end
	-- Record every property before mutation so the error handler can restore it.
	held = saved
	Minimap:SetMouseClickEnabled(false)
	Minimap:SetMouseMotionEnabled(true)
	for _, child in ipairs({ Minimap:GetChildren() }) do
		if child.IsMouseClickEnabled and child.IsMouseMotionEnabled then
			local state = { frame = child, click = child:IsMouseClickEnabled(), motion = child:IsMouseMotionEnabled() }
			saved.children[#saved.children + 1] = state
			child:SetMouseClickEnabled(false)
			child:SetMouseMotionEnabled(false)
		end
	end
	Minimap:SetAlpha(0)
	Minimap:SetFrameStrata("TOOLTIP")
	Minimap:SetFrameLevel(1000)
	GameTooltip:Hide()
	GameTooltip:SetAlpha(0)
	return true
end
local function StartScan()
	nextScan = GetTime() + INTERVAL
	if held or not DB().tracking or not peer or not Dependencies() or Blocked() then return end
	if not (gather and gather.IsLoaded and gather:IsLoaded() and gather.GetNearbyZoneNodes and gather.GetObject) then return end
	if not (Minimap.SetMouseClickEnabled and Minimap.IsMouseClickEnabled and Minimap.SetMouseMotionEnabled and Minimap.IsMouseMotionEnabled) then return end
	local kind, g = Tracking(), Geometry()
	if not kind or not g then return end
	local zx, zy, map = hbd:GetPlayerZonePosition()
	zx, zy, map = Number(zx), Number(zy), Number(map)
	if not zx or not zy or not map then return end
	local candidates, seen = {}, {}
	local range = math.min(100, g.radius * 0.85)
	for _, node in ipairs(gather:GetNearbyZoneNodes(NODE_KIND[kind], map, g.instance, zx, zy, range)) do
		local x, y, instance = hbd:GetWorldCoordinatesFromZone(node.posX, node.posY, node.mapID)
		x, y, instance = Number(x), Number(y), Number(instance)
		if x and y and instance == g.instance then
			local distance = (g.x - x)^2 + (g.y - y)^2
			local key = ("%.0f:%.0f"):format(x, y)
			if distance <= range^2 and not seen[key] then
				seen[key] = true
				candidates[#candidates + 1] = { x = x, y = y, instance = instance, kind = kind, distance = distance }
			end
		end
	end
	table.sort(candidates, function(a, b) return a.distance < b.distance end)
	if #candidates == 0 then return end
	queue = {}
	for i = 1, math.min(MAX_SAMPLES, #candidates) do
		queue[i] = candidates[(candidateOffset + i - 1) % #candidates + 1]
	end
	stats.samples, stats.hits = 0, 0
	local start = candidateOffset
	if not Hold() then
		queue = nil
	else
		held.offset, held.total, held.consumed = start, #candidates, 0
	end
end
local function Step()
	if not DB().tracking or not peer or Blocked() or GetTime() - held.started > 1.5 then Release(); return end
	local g = Geometry()
	if not g then Release(); return end
	if pending then
		local scale = Minimap:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		local mx, my = Minimap:GetCenter()
		local ox, oy = Offset(g, pending.x, pending.y)
		-- Discard a stale tooltip after a cursor move, a turn, a teleport or lag.
		if pending.instance == g.instance and pending.kind == Tracking()
			and math.abs(cx / scale - mx - ox) <= 3
			and math.abs(cy / scale - my - oy) <= 3 then Confirm(pending) end
		held.consumed = held.consumed + 1
		pending = nil
		GameTooltip:Hide()
	end
	local point = table.remove(queue, 1)
	if not point then Release(); return end
	if point.instance ~= g.instance or point.kind ~= Tracking() then Release(); return end
	local ox, oy = Offset(g, point.x, point.y)
	if (ox / g.width)^2 + (oy / g.height)^2 > 0.85^2 then held.consumed = held.consumed + 1; return end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale - ox, cy / scale - oy)
	GameTooltip:SetAlpha(0)
	pending = point
end
local function Receive(body)
	if body == "TR:0" then ClearPins(); return end
	if not DB().tracking or not Dependencies() then return end
	local instance, x, y, kind, name = body:match("^TN:(%d+):([%d%.%-]+):([%d%.%-]+):([OH]):(.+)$")
	instance, x, y, name = Number(tonumber(instance)), Number(tonumber(x)), Number(tonumber(y)), Clean(name)
	if not instance or not x or not y or not name then return end
	local _, _, currentInstance = hbd:GetPlayerWorldPosition()
	if instance ~= Number(currentInstance) or IsInInstance() then return end
	local key = ("%s:%d:%.0f:%.0f"):format(kind, instance, x, y)
	local record = received[key]
	if not record then
		if stats.count >= MAX_PINS then return end
		local frame = table.remove(pool) or CreateFrame("Frame", nil, Minimap)
		if not frame.texture then
			frame:SetSize(14, 14)
			frame:SetFrameStrata("MEDIUM")
			frame:SetFrameLevel(Minimap:GetFrameLevel() + 10)
			frame:SetMouseClickEnabled(false)
			frame:SetMouseMotionEnabled(true)
			frame.texture = frame:CreateTexture(nil, "OVERLAY")
			frame.texture:SetAllPoints()
			frame:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(self.nodeName)
				GameTooltip:AddLine("Detection du partenaire (confirmation recente)", 0.55, 0.9, 0.85, true)
				GameTooltip:Show()
			end)
			frame:SetScript("OnLeave", GameTooltip_Hide)
		end
		frame.texture:SetTexture(ICON[kind])
		pins:AddMinimapIconWorld(ns, frame, instance, x, y, false)
		record = { frame = frame }
		received[key] = record
		stats.count = stats.count + 1
	end
	record.frame.nodeName, record.seen = name, GetTime()
end
local function Status()
	ns.SendComm(DB().tracking and "TR:1" or "TR:0")
	nextStatus = GetTime() + INTERVAL
end
function ns.RefreshTracking()
	Release()
	ClearPins()
	wipe(sent)
	stats.error = nil
	peer, nextScan = Partner(), 0
	Status()
end
function ns.TrackingState()
	if stats.error then return "|cffff9933Scan arrete : " .. stats.error .. "|r" end
	if not DB().tracking then return "Partage des detections desactive." end
	if not DB().partner then return "Definis le partenaire sur les deux persos." end
	if not peer then return "Partenaire absent ou hors ligne." end
	if not hbd or not pins then return "HereBeDragons requis (fourni par GatherLite, TomTom ou Questie)." end
	local kind = Tracking()
	local source = kind and (kind == "O" and "Minerais" or "Plantes") or "Reception uniquement"
	if kind and not (gather and gather.IsLoaded and gather:IsLoaded() and gather.GetNearbyZoneNodes) then
		source = source .. " : GatherLite requis pour scanner"
	elseif kind and Blocked() then source = source .. " : scan en pause" end
	return ("%s | %d repere(s) recus | dernier scan : %d/%d confirmation(s)")
		:format(source, stats.count, stats.hits, stats.samples)
end
function ns.TrackingCommand(arg)
	if arg == "on" or arg == "off" then
		stats.error = nil
		ns.Set("tracking", arg == "on")
	elseif arg == "scan" then Safe(StartScan) end
	ns.Print(ns.TrackingState())
end
Safe = function(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		Release()
		ClearPins()
		DB().tracking = false
		stats.error = tostring(err):sub(1, 180)
		ns.Print("scan des detections arrete : " .. stats.error)
		Status()
	end
end
GameTooltip:HookScript("OnShow", function(self) if held then self:SetAlpha(0) end end)
local function Update(dt)
	if not ready or not DB().tracking then return end
	if held then Step() end
	pulse = pulse + dt
	if pulse < 0.25 then return end
	pulse = 0
	Dependencies()
	local current = Partner()
	if current ~= peer then ns.RefreshTracking() end
	local now = GetTime()
	for key, record in pairs(received) do
		if now - record.seen >= TTL then
			pins:RemoveMinimapIcon(ns, record.frame)
			record.frame:Hide()
			pool[#pool + 1] = record.frame
			received[key] = nil
			stats.count = stats.count - 1
		end
	end
	for key, time in pairs(sent) do if now - time >= TTL then sent[key] = nil end end
	if not peer then return end
	if now >= nextStatus then Status() end
	if now >= nextScan and not held then StartScan() end
end
ev:SetScript("OnUpdate", function(_, dt) Safe(Update, dt) end)
local function Event(event, ...)
	if event == "PLAYER_LOGIN" then
		ready = true
		Dependencies()
		ns.RefreshTracking()
	elseif not ready then return
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, body, channel, sender = ...
		if prefix ~= "DUOBOX" or channel ~= "PARTY" or not Partner() then return end
		body = ns.FromPartner(body, sender)
		if type(body) ~= "string" then return end
		if body == "TR:1" then return end
		Receive(body)
	elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_CONNECTION" then
		if Partner() ~= peer then ns.RefreshTracking() end
	else
		Release()
		nextScan = 0
		if event == "MINIMAP_UPDATE_TRACKING" then wipe(sent); Status() end
		if event == "PLAYER_LEAVING_WORLD" then ClearPins() end
	end
end
for _, event in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION",
	"MINIMAP_UPDATE_TRACKING", "PLAYER_REGEN_DISABLED", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
	pcall(ev.RegisterEvent, ev, event)
end
ev:SetScript("OnEvent", function(_, event, ...) Safe(Event, event, ...) end)
