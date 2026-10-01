--------------------------------------------------------------------------------
-- DuoBox / partner quests: each client sends its quest log progress to the
-- partner (addon messages). Used for:
--   * RestedXP: each quest objective of the guide shows the partner's count,
--     and the step waits until the partner has finished it too (/duo rxp).
--   * Quest loot reminder: when the partner loots a quest item that you still
--     need and you do not loot yours within 10 s, both screens get an alert.
-- The partner only needs DuoBox: RestedXP is used on the client that shows it.
--------------------------------------------------------------------------------

local _, ns = ...

local PREFIX = "DUOBOX"
local MAX_MSG = 240    -- addon messages are limited to 255 characters (tag included)
local LOOT_WINDOW = 10 -- seconds to loot your copy of a quest item looted by the partner

local Print, Alert, SendComm, FromPartner, PartnerUnit = ns.Print, ns.Alert, ns.SendComm, ns.FromPartner, ns.PartnerUnit
local function DB() return ns.GetDB() end

local function Val(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

--------------------------------------------------------------------------------
-- Own quest log. Read like RestedXP does (quest log leaderboards) so objective
-- indexes match its guide steps. Sent as "C" (ready to turn in) or
-- "done/required,done/required,..." per quest.
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

-- Objective j of the quest at log index i: done, required, kind ("item", "monster"...), text
local function ReadObjective(i, j, questID)
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
	return done, required, kind, text
end

-- Returns the encoded states { [questID] = "C" | "d/r,..." } and the own
-- objectives { [questID] = "C" | { {done, required, kind, text}, ... } }
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
	local snap, own = {}, {}
	for i = 1, n do
		local questID, isHeader, _, isComplete = Entry(i)
		if questID and questID > 0 and not isHeader then
			if isComplete then
				snap[questID], own[questID] = "C", "C"
			else
				local list, objs = {}, {}
				for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0) do
					local done, required, kind, text = ReadObjective(i, j, questID)
					list[j] = done .. "/" .. required
					objs[j] = { done, required, kind, text }
				end
				snap[questID], own[questID] = table.concat(list, ","), objs
			end
		end
	end
	return snap, own
end

-- Count gained on each objective between two states ("C" or { {done, required}, ... })
local function Gains(old, new)
	local gains = {}
	if type(old) ~= "table" or new == nil then return gains end
	for j, o in ipairs(old) do
		local now = new == "C" and o[2] or (type(new) == "table" and new[j] and new[j][1])
		local gain = now and math.min(now, o[2]) - o[1] or 0
		if gain > 0 then gains[j] = gain end
	end
	return gains
end

--------------------------------------------------------------------------------
-- Partner's quest log and display name
--------------------------------------------------------------------------------

local partnerQuests = {} -- [questID] = "C" or { {done, required}, ... }
local synced = false     -- a full quest log was received from the partner
local ownQuests = {}     -- last own objectives read (Snapshot)

local function Parse(state)
	if state == "C" then return "C" end
	local list = {}
	for done, required in state:gmatch("(%d+)/(%d+)") do
		list[#list + 1] = { tonumber(done), tonumber(required) }
	end
	return list
end

-- Class name ("Pretre"), clearer than the first name when both characters share it
local function PartnerLabel()
	local unit = PartnerUnit()
	local label = unit and (Val(UnitClass(unit)) or Val(UnitName(unit)))
	if not label and DB().partner then label = DB().partner:match("^[^%s%-]+") end
	return label or "Partenaire"
end

--------------------------------------------------------------------------------
-- Quest loot reminder. Quest items drop for each character on the quest, so
-- LOOT_WINDOW seconds after the partner loots one, your count of that item
-- should have caught up with theirs. A gap that existed before their loot
-- does not count, and a gap is only reported once.
--------------------------------------------------------------------------------

local alerted = {} -- ["questID:obj"] = gap already reported

local function ItemName(text)
	local name = (text or ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
	return name ~= "" and name or (text or "?")
end

-- Own item objective still in progress: done, required, text (nil otherwise)
local function OwnItem(questID, j)
	local own = ownQuests[questID]
	local o = type(own) == "table" and own[j]
	if o and o[3] == "item" and o[1] < o[2] then return o[1], o[2], o[4] end
end

local function PartnerDone(questID, j)
	local q = partnerQuests[questID]
	if q == "C" then return math.huge end -- quest complete: every objective done
	local o = type(q) == "table" and q[j]
	return o and o[1]
end

local function CheckLoot(questID, j, before)
	local done, required, text = OwnItem(questID, j)
	local partner = PartnerDone(questID, j)
	if not (done and partner and DB().lootAlert) then return end
	local key = questID .. ":" .. j
	local gap = math.min(partner, required) - done
	if gap <= math.max(before, alerted[key] or 0) then return end
	alerted[key] = gap
	local item = ItemName(text)
	Alert("loot", "Objet de quete a looter : " .. item, ns.SOUND_NOTICE, 3)
	Print("|cffffd040objet de quete pas loot|r : " .. item)
	SendComm("LM:" .. item:sub(1, 200))
end

-- The partner's count of objective j went up from partnerBefore
local function PartnerLoot(questID, j, partnerBefore)
	local done = OwnItem(questID, j)
	if not done then return end -- not an item you still need
	local before = math.max(partnerBefore - done, 0)
	C_Timer.After(LOOT_WINDOW, function() CheckLoot(questID, j, before) end)
end

--------------------------------------------------------------------------------
-- Sending: "RXA" = send me your quest log, "RXF:..." = full quest log (the
-- receiver starts from scratch), "RXQ:..." = changes. Entries: id=state;id=X
-- "LM:item" = I did not loot this quest item.
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
	local snap, own = Snapshot()
	for questID, old in pairs(ownQuests) do
		for j, gain in pairs(Gains(old, own[questID])) do
			local key = questID .. ":" .. j
			if alerted[key] then alerted[key] = alerted[key] > gain and alerted[key] - gain or nil end
		end
	end
	ownQuests = own

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

-- Applies "id=state;..." entries; with trackLoot, partner item loots start the reminder
local function Apply(payload, trackLoot)
	for entry in payload:gmatch("[^;]+") do
		local id, state = entry:match("^(%d+)=(.*)$")
		id = tonumber(id)
		if id then
			local old, new = partnerQuests[id], state ~= "X" and Parse(state) or nil
			if trackLoot then
				for j in pairs(Gains(old, new)) do PartnerLoot(id, j, old[j][1]) end
			end
			partnerQuests[id] = new
		end
	end
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
	local name = PartnerLabel()
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
	wipe(alerted)
	synced = false
	lastSent, ownQuests = {}, {}
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
		if prefix ~= PREFIX then return end
		msg = FromPartner(msg, sender)
		if not msg then return end
		local kind, payload = msg:match("^(%u%u%u?):?(.*)$")
		if kind == "RXA" then
			needFull = true
			ScheduleFlush(0.2)
		elseif kind == "RXF" then
			wipe(partnerQuests)
			synced = true
			Apply(payload, false)
			RefreshRXP()
		elseif kind == "RXQ" then
			if not synced then AskPartner(); return end
			Apply(payload, true)
			RefreshRXP()
		elseif kind == "LM" and DB().lootAlert then
			Alert("loot", ("%s n'a pas loot : %s"):format(PartnerLabel(), payload), ns.SOUND_NOTICE, 3)
			Print(("|cffffd040%s n'a pas loot|r : %s"):format(PartnerLabel(), payload))
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

	Print(("RestedXP : objectifs du partenaire %s, attente du partenaire %s. %s")
		:format(OnOffText(db.rxp), OnOffText(db.rxpHold), ns.RXPState()))
	RefreshRXP()
end

-- Sync state, shown by /duo rxp and the options panel
function ns.RXPState()
	local count = 0
	for _ in pairs(partnerQuests) do count = count + 1 end
	if not HookRXP() then
		return C_MISSING .. "RestedXP non detecte sur ce perso.|r"
	elseif not PartnerUnit() then
		return "Partenaire absent du groupe."
	elseif synced then
		return ("%d quetes du partenaire recues."):format(count)
	end
	return "En attente du partenaire (DuoBox a jour sur les 2 persos ?)."
end

ns.RefreshRXP = RefreshRXP
