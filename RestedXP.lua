--------------------------------------------------------------------------------
-- DuoBox / RestedXP: the partner's quest objectives in the RestedXP guide.
-- Each client sends its quest log progress to the partner (addon messages).
-- In RestedXP, each quest objective shows the partner's count, and the step
-- waits until the partner has finished the objective too (/duo rxp hold).
-- The partner only needs DuoBox: RestedXP is used on the client that shows it.
--------------------------------------------------------------------------------

local _, ns = ...

local PREFIX = "DUOBOX"
local MAX_MSG = 240 -- addon messages are limited to 255 characters

local Print, SendComm, IsPartnerName, PartnerUnit = ns.Print, ns.SendComm, ns.IsPartnerName, ns.PartnerUnit
local function DB() return ns.GetDB() end

local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

--------------------------------------------------------------------------------
-- Own quest log -> compact state per quest: "C" (ready to turn in) or
-- "done/required,done/required,...". Read like RestedXP does (quest log
-- leaderboards) so objective indexes match its guide steps.
--------------------------------------------------------------------------------

local function NumEntries()
	if GetQuestLogTitle and GetNumQuestLogEntries then return (GetNumQuestLogEntries()) end
	return C_QuestLog and C_QuestLog.GetNumQuestLogEntries and (C_QuestLog.GetNumQuestLogEntries()) or 0
end

-- Returns questID, isHeader, isCollapsed, isComplete
local function Entry(i)
	if GetQuestLogTitle then
		local _, _, _, isHeader, isCollapsed, isComplete, _, questID = GetQuestLogTitle(i)
		return questID, isHeader, isCollapsed, isComplete == 1 or isComplete == true
	end
	local info = C_QuestLog.GetInfo(i)
	if not info then return end
	local id = info.questID
	return id, info.isHeader, info.isCollapsed, id and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
end

local function Objectives(i, questID)
	local list = {}
	local n = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
	for j = 1, n do
		local text, kind, finished = GetQuestLogLeaderBoard(j, i)
		local done, required
		if kind == "progressbar" and GetQuestProgressBarPercent then
			done, required = math.floor(GetQuestProgressBarPercent(questID) or 0), 100
		elseif text then
			done, required = text:match("(%d+)/(%d+)")
			done, required = tonumber(done), tonumber(required)
		end
		if not (done and required) then
			done, required = finished and 1 or 0, 1
		elseif finished and done < required then
			done = required
		end
		list[j] = done .. "/" .. required
	end
	return table.concat(list, ",")
end

local function Snapshot()
	local n = NumEntries()
	for i = 1, n do
		local _, isHeader, isCollapsed = Entry(i)
		if isHeader and isCollapsed and ExpandQuestHeader then
			ExpandQuestHeader(0) -- collapsed headers hide their quests (RestedXP does the same)
			n = NumEntries()
			break
		end
	end
	local snap = {}
	for i = 1, n do
		local questID, isHeader, _, isComplete = Entry(i)
		if questID and questID > 0 and not isHeader then
			snap[questID] = isComplete and "C" or Objectives(i, questID)
		end
	end
	return snap
end

--------------------------------------------------------------------------------
-- Sending: "RXA" = send me your quest log, "RXF:..." = full quest log (the
-- receiver starts from scratch), "RXQ:..." = changes. Entries: id=state;id=X
--------------------------------------------------------------------------------

local lastSent = {}    -- [questID] = state last sent to the partner
local needFull = false -- the next send is a full quest log
local flushTimer
local lastAsk = 0

-- nil/true on old clients, Enum.SendAddonMessageResult on new ones (0 = success)
local function Sent(result)
	return result == nil or result == true or result == 0
end

local function SendEntries(kind, entries)
	local ok, chunk, size = true, {}, #kind + 1
	for _, e in ipairs(entries) do
		if #chunk > 0 and size + #e + 1 > MAX_MSG then
			ok = Sent(SendComm(kind .. ":" .. table.concat(chunk, ";"))) and ok
			kind, chunk, size = "RXQ", {}, 4
		end
		chunk[#chunk + 1] = e
		size = size + #e + 1
	end
	return Sent(SendComm(kind .. ":" .. table.concat(chunk, ";"))) and ok
end

local ScheduleFlush

local function Flush()
	if not PartnerUnit() then return end
	local snap = Snapshot()
	local entries = {}
	for id, state in pairs(snap) do
		if needFull or lastSent[id] ~= state then entries[#entries + 1] = id .. "=" .. state end
	end
	if not needFull then
		for id in pairs(lastSent) do
			if snap[id] == nil then entries[#entries + 1] = id .. "=X" end
		end
		if #entries == 0 then return end
	end
	if SendEntries(needFull and "RXF" or "RXQ", entries) then
		lastSent, needFull = snap, false
	else
		ScheduleFlush(2) -- throttled by the game: try again
	end
end

ScheduleFlush = function(delay)
	if flushTimer then return end
	flushTimer = C_Timer.NewTimer(delay, function()
		flushTimer = nil
		Flush()
	end)
end

local function AskPartner()
	if GetTime() - lastAsk < 5 then return end
	lastAsk = GetTime()
	SendComm("RXA")
end

local function StartSync()
	if not PartnerUnit() then return end
	needFull = true
	ScheduleFlush(1)
	AskPartner()
end

--------------------------------------------------------------------------------
-- Partner's quest log
--------------------------------------------------------------------------------

local partnerQuests = {} -- [questID] = "C" or { {done, required}, ... }
local synced = false     -- a full quest log was received from the partner

local function Parse(state)
	if state == "C" then return "C" end
	local list = {}
	for done, required in state:gmatch("(%d+)/(%d+)") do
		list[#list + 1] = { tonumber(done), tonumber(required) }
	end
	return list
end

local function Apply(payload)
	for entry in payload:gmatch("[^;]+") do
		local id, state = entry:match("^(%d+)=(.*)$")
		id = tonumber(id)
		if id then partnerQuests[id] = state ~= "X" and Parse(state) or nil end
	end
end

local function PartnerName()
	local unit = PartnerUnit()
	local name = unit and Val(UnitName(unit)) or DB().partner
	return name and name:match("^[^%s%-]+") or "Partenaire"
end

--------------------------------------------------------------------------------
-- RestedXP hooks. RestedXP recomputes each ".complete" objective of the guide
-- in UpdateQuestCompletionData, which ends with SetElementComplete (done) or
-- SetElementIncomplete (not done). The wrapper appends the partner's count to
-- the objective text and, while the partner is not done, turns "complete" into
-- "incomplete" so the step does not move on. Ticking the box by hand still
-- skips the objective, as usual in RestedXP.
--------------------------------------------------------------------------------

local rxp, hooked
local current, holding, reached -- RestedXP objective being updated

local C_DONE, C_TODO, C_MISSING = "|cff40ff40", "|cffffd040", "|cffff9933"

local function PartnerQuest(id)
	local q = partnerQuests[id]
	if q ~= nil then return q end
	-- RestedXP "mirror" quests: the same quest under several IDs
	local guide = rxp.currentGuide
	local mirror = guide and guide.mirrorID and guide.mirrorID[id]
	if type(mirror) == "table" then
		for _, alt in pairs(mirror) do
			if partnerQuests[alt] ~= nil then return partnerQuests[alt] end
		end
	end
end

-- Returns done (true / false / nil = unknown, never blocks) and the text shown after the objective
local function PartnerObjective(element)
	local name = PartnerName()
	local q = PartnerQuest(element.questId)
	if q == nil then
		return nil, (" %s[%s : pas la quete]|r"):format(C_MISSING, name)
	elseif q == "C" then
		return true, (" %s[%s OK]|r"):format(C_DONE, name)
	end
	local o = q[element.obj]
	if not o then
		return false, (" %s[%s en cours]|r"):format(C_TODO, name)
	end
	local done, required = o[1], o[2]
	if element.objMax then required = math.min(required, element.objMax) end
	if done >= required then
		return true, (" %s[%s %d/%d]|r"):format(C_DONE, name, required, required)
	end
	return false, (" %s[%s %d/%d]|r"):format(C_TODO, name, done, required)
end

local function Active()
	if not (hooked and synced and DB().rxp) then return false end
	local unit = PartnerUnit()
	local connected = unit and Val(UnitIsConnected(unit))
	return connected == true or connected == 1
end

local function HookRXP()
	if hooked then return true end
	rxp = _G.RXP -- RestedXP's internal table
	if type(rxp) ~= "table" then return false end
	local origUpdate, origComplete, origIncomplete =
		rxp.UpdateQuestCompletionData, rxp.SetElementComplete, rxp.SetElementIncomplete
	if type(origUpdate) ~= "function" or type(origComplete) ~= "function"
		or type(origIncomplete) ~= "function" or type(rxp.UpdateStepText) ~= "function" then
		return false
	end
	hooked = true

	rxp.SetElementComplete = function(self, ...)
		if self ~= nil and self == current then
			reached = true
			if holding then return origIncomplete(self) end
		end
		return origComplete(self, ...)
	end

	rxp.SetElementIncomplete = function(self, ...)
		if self ~= nil and self == current then reached = true end
		return origIncomplete(self, ...)
	end

	-- A held objective must not restart its step timer on every update
	local origTimer = rxp.StartTimer
	if type(origTimer) == "function" then
		rxp.StartTimer = function(...)
			if current and holding then return end
			return origTimer(...)
		end
	end

	rxp.UpdateQuestCompletionData = function(self, ...)
		local element = type(self) == "table" and self.element
		if not (element and element.tag == "complete" and element.questId and Active()) then
			return origUpdate(self, ...)
		end
		local normal = (element.flags or 0) % 2 == 0 -- odd flags mark "skip this step" checks: left alone
		local done, label = PartnerObjective(element)
		local c, h, r = current, holding, reached
		current, holding, reached = self, normal and done == false and DB().rxpHold, false
		local ok, err = pcall(origUpdate, self, ...)
		local fresh = reached -- false while RestedXP is still retrieving the quest data
		current, holding, reached = c, h, r
		if not ok then error(err, 0) end
		if fresh and normal and type(element.text) == "string" and element.text:find("%S") then
			element.text = element.text .. label
			if type(element.tooltipText) == "string" then element.tooltipText = element.tooltipText .. label end
			rxp.UpdateStepText(self)
		end
	end
	return true
end

-- Recompute the objectives of the current RestedXP steps
local function RefreshRXP()
	if not hooked then return end
	local steps = rxp.RXPFrame and rxp.RXPFrame.activeSteps
	if type(steps) ~= "table" or type(rxp.updateActiveQuest) ~= "table" then return end
	for _, step in ipairs(steps) do
		for _, element in ipairs(step.elements or {}) do
			if element.tag == "complete" and element.frame then
				rxp.updateActiveQuest[element.frame] = rxp.UpdateQuestCompletionData
			end
		end
	end
end

local function ResetPartner()
	wipe(partnerQuests)
	synced = false
	lastSent = {}
	RefreshRXP()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local partnerPresent = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("CHAT_MSG_ADDON")
pcall(ev.RegisterEvent, ev, "UNIT_CONNECTION")

ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		HookRXP()
		partnerPresent = PartnerUnit() ~= nil
		C_Timer.After(3, StartSync)

	elseif event == "GROUP_ROSTER_UPDATE" then
		local present = PartnerUnit() ~= nil
		if present and not partnerPresent then
			C_Timer.After(2, StartSync)
		elseif not present and partnerPresent then
			ResetPartner()
		end
		partnerPresent = present

	elseif event == "UNIT_CONNECTION" then
		RefreshRXP()

	elseif event == "QUEST_LOG_UPDATE" then
		if partnerPresent then ScheduleFlush(0.5) end

	elseif event == "CHAT_MSG_ADDON" then
		local prefix, msg, _, sender = ...
		if prefix ~= PREFIX or type(msg) ~= "string" or msg:sub(1, 2) ~= "RX" or not IsPartnerName(sender) then return end
		local kind, payload = msg:match("^(RX%u):?(.*)$")
		if kind == "RXA" then
			needFull = true
			ScheduleFlush(0.2)
		elseif kind == "RXF" then
			wipe(partnerQuests)
			synced = true
			Apply(payload)
			RefreshRXP()
		elseif kind == "RXQ" then
			if not synced then AskPartner(); return end
			Apply(payload)
			RefreshRXP()
		end
	end
end)

--------------------------------------------------------------------------------
-- /duo rxp [on|off|hold [on|off]|sync]
--------------------------------------------------------------------------------

local function OnOffText(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end

function ns.RXPCommand(arg)
	local db = DB()
	local sub, val = (arg or ""):lower():match("^(%S*)%s*(%S*)")
	if sub == "on" or sub == "off" then
		db.rxp = sub == "on"
	elseif sub == "hold" then
		if val == "on" or val == "off" then db.rxpHold = val == "on" else db.rxpHold = not db.rxpHold end
	elseif sub == "sync" then
		ResetPartner()
		lastAsk = 0
		StartSync()
	end

	local count = 0
	for _ in pairs(partnerQuests) do count = count + 1 end
	local state
	if not HookRXP() then
		state = C_MISSING .. "RestedXP non detecte sur ce perso.|r"
	elseif not PartnerUnit() then
		state = "Partenaire absent du groupe."
	elseif synced then
		state = ("%d quetes du partenaire recues."):format(count)
	else
		state = "En attente du partenaire (DuoBox a jour sur les 2 persos ?)."
	end
	Print(("RestedXP : objectifs du partenaire %s, attente du partenaire %s. %s")
		:format(OnOffText(db.rxp), OnOffText(db.rxpHold), state))
	RefreshRXP()
end
