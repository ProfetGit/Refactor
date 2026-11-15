--- @module interface.levelUpSpells
--- Purpose: under the level-up banner, list the abilities that level unlocks.
--- Requires: UnitLevel, UnitClass, UnitFactionGroup, Enum.SpellBookItemType, Enum.SpellBookSpellBank,
---     C_Spell.GetSpellTexture, C_Spell.GetSpellName, C_Spell.GetSpellSubtext, C_SpellBook.GetNumSpellBookSkillLines,
---     C_SpellBook.GetSpellBookSkillLineInfo, C_SpellBook.GetSpellBookItemInfo,
---     C_SpellBook.GetSpellBookItemLevelLearned, C_SpellBook.IsSpellKnown
--- Events: PLAYER_LEVEL_UP, REFACTOR_LEVELUP_TEST. The unlearned abilities come from the class trainer
---     list that interface.allSpells records when there is one, else from Data/ClassSpells.lua.
--- Hot: no
local _, R = ...
local LevelUpSpells = R:RegisterModule({
    id = "interface.levelUpSpells", category = "Levelling", nameKey = "LEVELUP_SPELLS_NAME",
    descriptionKey = "LEVELUP_SPELLS_DESC", detailKey = "LEVELUP_SPELLS_DETAIL",
    requires = { "UnitLevel", "UnitClass", "UnitFactionGroup", "Enum.SpellBookItemType", "Enum.SpellBookSpellBank",
        "C_Spell.GetSpellTexture", "C_Spell.GetSpellName", "C_Spell.GetSpellSubtext",
        "C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookSkillLineInfo",
        "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.GetSpellBookItemLevelLearned",
        "C_SpellBook.IsSpellKnown" },
    risk = "visible", defaultEnabled = true,
})

local BANNER = "LevelUpDisplay"
-- Blizzard's banner reveals its text 1.5 s in over 0.7 s and fades it out from about 6.2 s. The strip
-- arrives as the text settles and leaves just before it does.
local SHOW_AFTER, HOLD = 2.2, 4.2
local FADE_OUT = 0.8

local function byLevelThenName(a, b)
    if a.level ~= b.level then
        return a.level < b.level
    end
    if a.name ~= b.name then
        return a.name < b.name
    end
    return a.spellID < b.spellID
end

local function describe(spellID, level)
    local name = C_Spell.GetSpellName(spellID)
    if type(name) ~= "string" then
        return nil
    end
    local known = C_SpellBook.IsSpellKnown(spellID) == true
    local detail
    if known then
        local sub = C_Spell.GetSpellSubtext(spellID)
        detail = type(sub) == "string" and sub ~= "" and sub or R.L.LEVELUP_SPELLS_LEARNED
    else
        detail = R.L.LEVELUP_SPELLS_TRAIN
    end
    return { spellID = spellID, name = name, icon = C_Spell.GetSpellTexture(spellID), level = level,
        detail = detail, ready = not known }
end

-- Every ability whose level is above `low` and no higher than `high`: the ones in the spellbook
-- (Retail lists the ones it teaches itself), then the ones only a trainer record or the shipped table knows. A
-- spell is keyed by its id, so a learned one and its trainer entry are one cell.
function LevelUpSpells:Gather(low, high)
    local found, seen = {}, {}
    local bank, types = Enum.SpellBookSpellBank.Player, Enum.SpellBookItemType
    for index = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(index)
        if type(info) == "table" and not info.shouldHide and not info.isGuild and not info.offSpecID then
            local offset = info.itemIndexOffset or 0
            for slot = offset + 1, offset + (info.numSpellBookItems or 0) do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                local spellID = type(item) == "table" and item.actionID
                if type(spellID) == "number" and not seen[spellID] and not item.isOffSpec
                    and (item.itemType == types.Spell or item.itemType == types.FutureSpell) then
                    local level = C_SpellBook.GetSpellBookItemLevelLearned(slot, bank)
                    if type(level) == "number" and level > low and level <= high then
                        seen[spellID] = true
                        found[#found + 1] = describe(spellID, level)
                    end
                end
            end
        end
    end
    local classFile = select(2, UnitClass("player"))
    for spellID, entry in pairs(R:ClassSpellList(classFile, UnitFactionGroup("player"))) do
        local level = entry.level
        if not seen[spellID] and level > low and level <= high then
            seen[spellID] = true
            found[#found + 1] = describe(spellID, level)
        end
    end
    table.sort(found, byLevelThenName)
    return found
end

function LevelUpSpells:Present(low, high)
    local list = self:Gather(low, high)
    if #list == 0 then
        return false
    end
    local max = R.UI.LEVELUP_SPELLS_MAX
    local shown = {}
    for index = 1, math.min(#list, max) do
        shown[index] = list[index]
    end
    R.UI:LevelUpSpellsAnchor(self.ui, R.Capabilities:Resolve(BANNER))
    R.UI:LevelUpSpellsSet(self.ui, shown, #list - #shown)
    R.UI:LevelUpSpellsShow(self.ui)
    R:After(self, HOLD, self.Leave)
    return true
end

function LevelUpSpells:Leave()
    R.UI:LevelUpSpellsFade(self.ui)
    R:After(self, FADE_OUT + 0.1, self.Clear)
end

function LevelUpSpells:Clear()
    R.UI:LevelUpSpellsHide(self.ui)
end

function LevelUpSpells:Show()
    local low, high = self.low, self.high
    self.low = nil
    if low and high then
        self:Present(low, high)
    end
end

function LevelUpSpells:OnLevelUp(_, level)
    if type(level) ~= "number" then
        return
    end
    -- A second level before the first was shown folds into one strip covering both.
    self.low = self.low or self.level or level - 1
    self.high, self.level = level, level
    R:CancelTimers(self)
    R.UI:LevelUpSpellsHide(self.ui)
    R:After(self, SHOW_AFTER, self.Show)
end

-- /refactor leveluptest: the most recent level at or below yours that has something to show.
function LevelUpSpells:Test()
    local level = UnitLevel("player") or 1
    R:CancelTimers(self)
    R.UI:LevelUpSpellsHide(self.ui)
    for at = level, 1, -1 do
        if self:Present(at - 1, at) then
            R:Print(string.format(R.L.CMD_LEVELUP_TEST_SHOWN, at))
            return
        end
    end
    R:Print(R.L.CMD_LEVELUP_TEST_NONE)
end

function LevelUpSpells:OnEnable()
    self.level, self.low, self.high = UnitLevel("player"), nil, nil
    self.ui = self.ui or R.UI:LevelUpSpellsCreate()
    R.Broker:Subscribe("PLAYER_LEVEL_UP", self.OnLevelUp, self)
    R.Broker:Subscribe("REFACTOR_LEVELUP_TEST", self.Test, self)
end

function LevelUpSpells:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    self.low, self.high = nil, nil
    if self.ui then
        R.UI:LevelUpSpellsHide(self.ui)
    end
end
