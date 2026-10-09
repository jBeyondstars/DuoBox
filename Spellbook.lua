--------------------------------------------------------------------------------
-- DuoBox / spell helpers shared by DuoBox.lua and Rotation.lua (loaded first).
-- A spell is known when the spellbook holds a learned spell of the same name, so
-- any rank counts: on WoW Forever a new rank replaces the previous one, and
-- IsPlayerSpell(rank 1) turns false once rank 2 is learned (Heroic Strike,
-- Heal...).
--------------------------------------------------------------------------------

local _, ns = ...

function ns.SpellNameIcon(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if info then return info.name, info.iconID end
	end
	if GetSpellInfo then
		local name, _, icon = GetSpellInfo(id)
		return name, icon
	end
end

local names -- names of the learned spellbook spells; nil = to rebuild

local function SpellbookNames()
	if names then return names end
	local found, any = {}, false
	local bank = Enum.SpellBookSpellBank.Player
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				if C_SpellBook.GetSpellBookItemType(slot, bank) == Enum.SpellBookItemType.Spell then
					local name = C_SpellBook.GetSpellBookItemName(slot, bank)
					if name then found[name], any = true, true end
				end
			end
		end
	end
	if any then names = found end -- not loaded yet: read it again next time
	return found
end

-- Loaded before DuoBox.lua, so this runs before its SPELLS_CHANGED handler updates the bar
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:SetScript("OnEvent", function() names = nil end)

function ns.Known(id)
	if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo and Enum and Enum.SpellBookItemType then
		local name = ns.SpellNameIcon(id)
		return name ~= nil and SpellbookNames()[name] == true
	end
	-- Classic Era 1.15: lower ranks stay known
	if IsPlayerSpell then return IsPlayerSpell(id) end
	return IsSpellKnown ~= nil and IsSpellKnown(id) or false
end
