--- @module interface.allSpells
--- Purpose: a side panel beside the spellbook that lists every spell of your class, learned or not, with its level.
--- Requires: IsTradeskillTrainer, GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter,
---     GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine, GetTrainerServiceItemLink,
---     C_TooltipInfo.GetTrainerService, C_Trainer.GetTrainerType, Enum.TrainerType, Enum.SpellBookItemType,
---     Enum.SpellBookSpellBank, UnitClass, UnitLevel, C_Spell.GetSpellTexture, C_Spell.GetSpellName,
---     C_Spell.GetSpellSubtext, C_SpellBook.GetNumSpellBookSkillLines, C_SpellBook.GetSpellBookSkillLineInfo,
---     C_SpellBook.GetSpellBookItemInfo, C_SpellBook.GetSpellBookItemLevelLearned, C_SpellBook.IsSpellKnown,
---     C_AddOns.IsAddOnLoaded
--- Events: TRAINER_SHOW, TRAINER_CLOSED, TRAINER_UPDATE (only while a trainer is open), ADDON_LOADED (only
---     until the spellbook has loaded), SPELLS_CHANGED and LEARNED_SPELL_IN_SKILL_LINE (only while the panel
---     is shown). The unlearned spells are recorded at the class trainer, because no call lists them.
--- Hot: no
-- luacheck: read globals IsTradeskillTrainer GetTrainerServiceTypeFilter SetTrainerServiceTypeFilter
-- luacheck: read globals GetNumTrainerServices GetTrainerServiceInfo GetTrainerServiceSkillLine
-- luacheck: read globals GetTrainerServiceItemLink C_Trainer
local _, R = ...
local AllSpells = R:RegisterModule({
    id = "interface.allSpells", category = "Interface", nameKey = "ALL_SPELLS_NAME",
    descriptionKey = "ALL_SPELLS_DESC", detailKey = "ALL_SPELLS_DETAIL",
    requires = { "IsTradeskillTrainer", "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter",
        "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceSkillLine",
        "GetTrainerServiceItemLink", "C_TooltipInfo.GetTrainerService", "C_Trainer.GetTrainerType",
        "Enum.TrainerType", "Enum.SpellBookItemType", "Enum.SpellBookSpellBank", "UnitClass", "UnitLevel",
        "C_Spell.GetSpellTexture", "C_Spell.GetSpellName", "C_Spell.GetSpellSubtext",
        "C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookSkillLineInfo",
        "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.GetSpellBookItemLevelLearned",
        "C_SpellBook.IsSpellKnown", "C_AddOns.IsAddOnLoaded" },
    risk = "visible", defaultEnabled = false,
})

local SPELLBOOK_ADDON = "Blizzard_PlayerSpells"
-- The trainer window's three type filters. A list read through the player's own choice of them
-- leaves out whatever they have switched off, so all three are turned on for the read.
local FILTERS = { "available", "unavailable", "used" }
local THROTTLE = 0.5
-- The service list can still be empty when TRAINER_SHOW fires. Its first refreshes may then
-- switch the filters too, a few times at most, since each switch sends another refresh.
local VISIT_TRIES = 3
local MAX_LEVEL, MAX_LINE_NAME = 200, 64
local TABS = { all = true, toLearn = true, learned = true }

local function isOn(value)
    return value == true or value == 1
end

local function cleanLevel(value)
    if type(value) == "number" and value >= 0 and value <= MAX_LEVEL then
        return math.floor(value)
    end
    return 0
end

-- Saved data from an older build or a hand edit never reaches the panel as-is: a malformed class,
-- spell or field is dropped, and a table that is not a table becomes an empty one.
local function cleanClassSpells(raw)
    local clean = {}
    if type(raw) ~= "table" then
        return clean
    end
    for classFile, spells in pairs(raw) do
        if type(classFile) == "string" and type(spells) == "table" then
            local kept, any = {}, false
            for spellID, entry in pairs(spells) do
                if type(spellID) == "number" and spellID > 0 and spellID % 1 == 0 and type(entry) == "table"
                    and type(entry.level) == "number" and entry.level >= 0 and entry.level <= MAX_LEVEL then
                    kept[spellID] = { level = math.floor(entry.level),
                        line = type(entry.line) == "string" and entry.line:sub(1, MAX_LINE_NAME) or "" }
                    any = true
                end
            end
            if any then
                clean[classFile] = kept
            end
        end
    end
    return clean
end

function AllSpells:ServiceSpellID(index)
    local data = C_TooltipInfo.GetTrainerService(index)
    local spellID = type(data) == "table" and data.id or nil
    if type(spellID) ~= "number" then
        local link = GetTrainerServiceItemLink(index)
        spellID = type(link) == "string" and tonumber(link:match("spell:(%d+)")) or nil
    end
    if type(spellID) == "number" and spellID > 0 then
        return spellID
    end
    return nil
end

function AllSpells:ReadServices()
    local spells, count = {}, 0
    for index = 1, GetNumTrainerServices() or 0 do
        local name, serviceType, _, level = GetTrainerServiceInfo(index)
        if name and serviceType ~= "header" then
            local spellID = self:ServiceSpellID(index)
            if spellID then
                local line = GetTrainerServiceSkillLine(index)
                spells[spellID] = { level = cleanLevel(level),
                    line = type(line) == "string" and line:sub(1, MAX_LINE_NAME) or "" }
                count = count + 1
            end
        end
    end
    return { spells = spells, count = count }
end

-- The trainer's list is the truth about this class, so each complete visit replaces the class's
-- table outright. That visit is the invalidation event for the record; nothing expires by time.
function AllSpells:Capture(mayChangeFilters)
    local previous, complete = {}, true
    for _, filter in ipairs(FILTERS) do
        previous[filter] = isOn(GetTrainerServiceTypeFilter(filter))
        complete = complete and previous[filter]
    end
    -- A refresh the client sent for a filter we restored is not a reason to touch them again.
    if not complete and not mayChangeFilters then
        return false
    end
    for _, filter in ipairs(FILTERS) do
        if not previous[filter] then
            SetTrainerServiceTypeFilter(filter, true)
        end
    end
    local ok, read = R:Try(self, self.ReadServices, "read trainer")
    for _, filter in ipairs(FILTERS) do
        if not previous[filter] then
            SetTrainerServiceTypeFilter(filter, false)
        end
    end
    local classFile = select(2, UnitClass("player"))
    if not ok or type(classFile) ~= "string" or read.count == 0 then
        return false
    end
    R.Settings.account.classSpells[classFile] = read.spells
    return true
end

function AllSpells:Record(mayChangeFilters)
    if self.recording or IsTradeskillTrainer() or C_Trainer.GetTrainerType() == Enum.TrainerType.Pet then
        return false
    end
    self.recording = true
    local _, stored = R:Try(self, self.Capture, "record trainer", mayChangeFilters)
    self.recording = false
    if stored and self.ui and self.ui.panel:IsShown() then
        self:Refresh()
    end
    return stored == true
end

function AllSpells:OnTrainerShow()
    R.Broker:Subscribe("TRAINER_UPDATE", self.OnTrainerUpdate, self, THROTTLE)
    self.visitTries = 1
    self.visitRecorded = self:Record(true)
end

function AllSpells:OnTrainerUpdate()
    local retry = not self.visitRecorded and (self.visitTries or 0) < VISIT_TRIES
    if retry then
        self.visitTries = self.visitTries + 1
    end
    if self:Record(retry) then
        self.visitRecorded = true
    end
end

function AllSpells:OnTrainerClosed()
    R.Broker:Unsubscribe("TRAINER_UPDATE", self)
end

local function describe(spellID, item)
    local name = C_Spell.GetSpellName(spellID) or item and item.name
    return type(name) == "string" and name or tostring(spellID),
        C_Spell.GetSpellTexture(spellID) or item and item.iconID or nil,
        C_Spell.GetSpellSubtext(spellID) or item and item.subName or ""
end

local function byLevelThenName(a, b)
    if a.level ~= b.level then
        return a.level < b.level
    end
    local left, right = a.name:lower(), b.name:lower()
    if left ~= right then
        return left < right
    end
    return a.spellID < b.spellID
end

-- The display list: a header, then that line's spells, for each skill line in spellbook order and
-- then the lines only the trainer knows. A spell is keyed by its base spell id, which is the id the
-- trainer lists, so a learned spell and its trainer entry are one row.
function AllSpells:BuildList()
    local groups, byName, seen = {}, {}, {}
    local function group(name)
        local found = byName[name]
        if not found then
            found = { name = name, spells = {} }
            byName[name] = found
            groups[#groups + 1] = found
        end
        return found
    end
    local recorded = R.Settings.account.classSpells[select(2, UnitClass("player"))] or {}
    local playerLevel = UnitLevel("player") or 1
    local bank, types = Enum.SpellBookSpellBank.Player, Enum.SpellBookItemType
    for index = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(index)
        if type(info) == "table" and type(info.name) == "string" and not info.shouldHide
            and not info.isGuild and not info.offSpecID then
            local lineGroup = group(info.name)
            local offset = info.itemIndexOffset or 0
            for slot = offset + 1, offset + (info.numSpellBookItems or 0) do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                local spellID = type(item) == "table" and item.actionID
                if type(spellID) == "number" and not seen[spellID] and not item.isOffSpec
                    and (item.itemType == types.Spell or item.itemType == types.FutureSpell) then
                    seen[spellID] = true
                    local level = C_SpellBook.GetSpellBookItemLevelLearned(slot, bank)
                    if type(level) ~= "number" or level < 1 then
                        level = recorded[spellID] and recorded[spellID].level or 0
                    end
                    local name, icon, sub = describe(spellID, item)
                    local known = C_SpellBook.IsSpellKnown(spellID) == true
                    lineGroup.spells[#lineGroup.spells + 1] = { spellID = spellID, name = name, icon = icon,
                        sub = sub, level = level, known = known,
                        trainable = not known and level >= 1 and level <= playerLevel }
                end
            end
        end
    end
    local bookLines = #groups
    for spellID, entry in pairs(recorded) do
        if not seen[spellID] then
            seen[spellID] = true
            local name, icon, sub = describe(spellID)
            local lineGroup = group(entry.line ~= "" and entry.line or R.L.ALL_SPELLS_OTHER)
            local known = C_SpellBook.IsSpellKnown(spellID) == true
            lineGroup.spells[#lineGroup.spells + 1] = { spellID = spellID, name = name, icon = icon, sub = sub,
                level = entry.level, known = known,
                trainable = not known and entry.level >= 1 and entry.level <= playerLevel }
        end
    end
    -- pairs() has no order, so the lines only the trainer knows are put in one.
    local trainerOnly = {}
    for index = bookLines + 1, #groups do
        trainerOnly[#trainerOnly + 1] = groups[index]
    end
    table.sort(trainerOnly, function(a, b) return a.name:lower() < b.name:lower() end)
    for index, entry in ipairs(trainerOnly) do
        groups[bookLines + index] = entry
    end
    local list = {}
    for _, entry in ipairs(groups) do
        if #entry.spells > 0 then
            table.sort(entry.spells, byLevelThenName)
            local learned = 0
            for _, spell in ipairs(entry.spells) do
                if spell.known then learned = learned + 1 end
            end
            list[#list + 1] = { header = entry.name, learned = learned, total = #entry.spells }
            for _, spell in ipairs(entry.spells) do
                list[#list + 1] = spell
            end
        end
    end
    return list, next(recorded) ~= nil
end

-- The learned count, the total, and the lowest-level spell still above the player's level.
function AllSpells:Summary(list)
    local level = UnitLevel("player") or 1
    local learned, total, upcoming = 0, 0, nil
    for _, entry in ipairs(list) do
        if not entry.header then
            total = total + 1
            if entry.known then
                learned = learned + 1
            elseif entry.level > level and (not upcoming or entry.level < upcoming.level) then
                upcoming = entry
            end
        end
    end
    return learned, total, upcoming
end

-- The tab and the search narrow the built list without asking the client again. A header whose
-- spells were all filtered out is dropped with them.
function AllSpells:Filter()
    local tab = R.Settings.character.allSpellsTab
    local query = self.ui.search:GetText():lower()
    local rows, header = {}, nil
    for _, entry in ipairs(self.list) do
        if entry.header then
            header = entry
        elseif (tab == "all" or (tab == "learned") == entry.known)
            and (query == "" or entry.name:lower():find(query, 1, true)) then
            if header then
                rows[#rows + 1] = header
                header = nil
            end
            rows[#rows + 1] = entry
        end
    end
    return rows
end

function AllSpells:Apply(reset)
    if self.ui and self.list then
        R.UI:AllSpellsSetRows(self.ui, self:Filter(), reset)
    end
end

function AllSpells:Refresh()
    if not self.ui then
        return
    end
    local list, hasRecord = self:BuildList()
    self.list = list
    local learned, total, upcoming = self:Summary(list)
    R.UI:AllSpellsSetSummary(self.ui, learned, total, upcoming, not hasRecord)
    self:Apply(false)
end

function AllSpells:OnPanelShown()
    if not self.active then
        return
    end
    R.Broker:Subscribe("SPELLS_CHANGED", self.Refresh, self, THROTTLE)
    R.Broker:Subscribe("LEARNED_SPELL_IN_SKILL_LINE", self.Refresh, self, THROTTLE)
    self:Refresh()
end

function AllSpells:OnPanelHidden()
    R.Broker:Unsubscribe("SPELLS_CHANGED", self)
    R.Broker:Unsubscribe("LEARNED_SPELL_IN_SKILL_LINE", self)
end

function AllSpells:OnTab(key)
    if TABS[key] then
        R.Settings.character.allSpellsTab = key
        R.UI:AllSpellsSetTab(self.ui, key)
        self:Apply(true)
    end
end

local function frameField(parent, key)
    local value = parent[key]
    if type(value) == "table" and type(value.GetFrameLevel) == "function" then
        return value
    end
    return nil
end

-- Read off the spellbook by structure and checked at every step: this layout is Blizzard's to change.
-- Only the window is required, since the panel docks to its side. The book, when there is one,
-- is what the panel is parented to, so it leaves with the spellbook tab and not only the window.
function AllSpells:FindHost()
    local window = R.Capabilities:Resolve("PlayerSpellsFrame")
    if type(window) ~= "table" or type(window.GetFrameLevel) ~= "function" then
        return nil
    end
    return window, frameField(window, "SpellBookFrame")
end

function AllSpells:Attach()
    local window, book = self:FindHost()
    if window then
        R.UI:AllSpellsAttach(self.ui, window, book)
    end
    return window ~= nil
end

function AllSpells:OnAddonLoaded()
    if C_AddOns.IsAddOnLoaded(SPELLBOOK_ADDON) then
        R.Broker:Unsubscribe("ADDON_LOADED", self)
        self:Attach()
    end
end

function AllSpells:OnEnable()
    local account, character = R.Settings.account, R.Settings.character
    account.classSpells = cleanClassSpells(account.classSpells)
    -- Left over from the in-book toggle button, which is gone: the feature switch is the toggle.
    character.allSpellsShown = nil
    if not TABS[character.allSpellsTab] then
        character.allSpellsTab = "all"
    end
    self.active, self.recording = true, false
    if not self.ui then
        local function handler(method, context)
            return function(...) R:SafeCall(self, method, context, ...) end
        end
        self.ui = R.UI:AllSpellsCreate({
            onShow = handler(self.OnPanelShown, "all spells panel shown"),
            onHide = handler(self.OnPanelHidden, "all spells panel hidden"),
            onTab = handler(self.OnTab, "all spells tab"),
            onSearch = function() R:SafeCall(self, self.Apply, "all spells search", true) end,
        })
    end
    R.UI:AllSpellsSetTab(self.ui, character.allSpellsTab)
    R.Broker:Subscribe("TRAINER_SHOW", self.OnTrainerShow, self)
    R.Broker:Subscribe("TRAINER_CLOSED", self.OnTrainerClosed, self)
    if not self:Attach() and not C_AddOns.IsAddOnLoaded(SPELLBOOK_ADDON) then
        R.Broker:Subscribe("ADDON_LOADED", self.OnAddonLoaded, self)
    end
end

function AllSpells:OnDisable()
    self.active, self.recording = false, false
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    if self.ui then
        R.UI:AllSpellsDetach(self.ui)
    end
end
