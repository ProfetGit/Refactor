--- @module nameplates.questProgress
--- Purpose: show how close each nameplate mob is to finishing your quest objective.
--- Requires: C_NamePlate.GetNamePlateForUnit, UnitGUID, UnitName, issecretvalue, IsInRaid, UnitExists,
---     UnitIsUnit, UnitClass, C_ClassColor.GetClassColor, and the data half's
---     C_QuestLog.UnitIsRelatedToActiveQuest, C_QuestLog.GetQuestObjectives, C_QuestLog.IsOnQuest,
---     IsInGroup, C_TooltipInfo.GetUnit, Enum.TooltipDataLineType.QuestTitle,
---     Enum.TooltipDataLineType.QuestObjective, Enum.TooltipDataLineType.QuestPlayer
--- Events: NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED,
---     QUEST_LOG_UPDATE (throttled), UNIT_QUEST_LOG_CHANGED (throttled), GROUP_ROSTER_UPDATE (throttled),
---     REFACTOR_SETTINGS_CHANGED
--- Hot: yes, see QuestProgress_Data.lua
local _, R = ...
local Theme, Data, Settings = R.Theme, R.QuestData, R.Settings

local QuestProgress = R:RegisterModule({
    id = "nameplates.questProgress",
    category = "Quest",
    nameKey = "NAMEPLATE_QUEST_NAME",
    descriptionKey = "NAMEPLATE_QUEST_DESC",
    detailKey = "NAMEPLATE_QUEST_DETAIL",
    -- The data half's symbols too: without any one of them nothing could ever show, and the
    -- row should say which one is missing rather than enable and stay blank.
    requires = { "C_NamePlate.GetNamePlateForUnit", "UnitGUID", "UnitName", "issecretvalue",
        "IsInRaid", "UnitExists", "UnitIsUnit", "UnitClass", "C_ClassColor.GetClassColor",
        "C_QuestLog.UnitIsRelatedToActiveQuest", "C_QuestLog.GetQuestObjectives", "C_QuestLog.IsOnQuest",
        "IsInGroup", "C_TooltipInfo.GetUnit", "Enum.TooltipDataLineType.QuestTitle",
        "Enum.TooltipDataLineType.QuestObjective", "Enum.TooltipDataLineType.QuestPlayer" },
    conflicts = { "Questie.nameplateObjectives", "Plater.questProgress" },
    risk = "visible",
    defaultEnabled = true,
})

local PLATE_BUDGET, POOL_SIZE, ANCHOR_GAP = 4, 20, 6
-- A party fits; past this a raid's members fold into "+N".
local GROUP_SHOWN = Theme.questGroupSlots
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local RAID_UNITS = {}
for index = 1, 40 do
    RAID_UNITS[index] = "raid" .. index
end

-- Class colours are the client's own and do not change while you are logged in, so each is
-- read once and kept. Permanent by design, keyed by the client's class string.
local classReds, classGreens, classBlues = {}, {}, {}

local function classColor(classFile)
    if not classFile then
        return nil
    end
    local red = classReds[classFile]
    if red == nil then
        local color = C_ClassColor.GetClassColor(classFile)
        if type(color) ~= "table" or type(color.GetRGB) ~= "function" then
            return nil
        end
        classReds[classFile], classGreens[classFile], classBlues[classFile] = color:GetRGB()
        red = classReds[classFile]
    end
    return red, classGreens[classFile], classBlues[classFile]
end

local function groupEntry()
    return { groupCount = 0, groupMember = {}, groupClass = {}, groupFulfilled = {}, groupRequired = {},
        groupRatio = {} }
end

-- The group arrays are kept across reuse; groupCount alone says how much of them is live.
local function resetEntry(entry)
    entry.groupCount = 0
end

function QuestProgress:Acquire(pool)
    -- Rule 11: frames exist before the first event. An exhausted pool skips a plate
    -- rather than building a frame while plates are streaming in.
    if #pool.free == 0 then
        return nil
    end
    return pool:Acquire()
end

-- Nameplate frames are restricted in this client: GetLeft, GetWidth and GetPoint on them
-- throw "Can't measure restricted regions", so the anchor is chosen by structure and by
-- what Blizzard shows, never by where it sits. Forever runs the modern layout (LevelFrame
-- hidden, modern bar background) but draws the mob level in a box past the bar's right
-- edge, in the frame Retail reserves for Plunderstorm's level difference. Anchoring to
-- the container or the background landed the indicator on that box.
function QuestProgress:AnchorFor(plate)
    local unitFrame = plate.UnitFrame
    if not unitFrame then
        return plate
    end
    local level = unitFrame.LevelFrame
    if level and level:IsShown() then
        return level
    end
    local diff = unitFrame.PlayerLevelDiffFrame
    if diff and diff:IsShown() then
        return diff
    end
    local container = unitFrame.HealthBarsContainer
    local healthBar = container and container.healthBar or unitFrame.healthBar
    local border = healthBar and healthBar.bgTexture
    if border then
        return border
    end
    return container or unitFrame
end

function QuestProgress:Place(indicator, plate)
    local anchor = self:AnchorFor(plate)
    indicator:ClearAllPoints()
    if Settings:GetOption("nameplateSide") == "LEFT" then
        indicator:SetPoint("RIGHT", anchor, "LEFT", -ANCHOR_GAP, 0)
    else
        indicator:SetPoint("LEFT", anchor, "RIGHT", ANCHOR_GAP, 0)
    end
end

function QuestProgress:DropIndicator(unit)
    local indicator = self.shown[unit]
    if indicator then
        self.shown[unit] = nil
        indicator:ResetIndicator()
        self.indicators:Release(indicator)
    end
end

function QuestProgress:DropGroup(unit)
    local row = self.rows[unit]
    if row then
        self.rows[unit] = nil
        row:ResetRow()
        self.groupRows:Release(row)
    end
end

function QuestProgress:Release(unit)
    self:DropIndicator(unit)
    self:DropGroup(unit)
    local dim = self.dimmed[unit]
    if dim then
        self.dimmed[unit] = nil
        dim:Hide()
        dim:ClearAllPoints()
        dim:SetParent(nil)
        self.dims:Release(dim)
    end
    self.progress[unit] = nil
    self.retried[unit] = nil
    self.open[unit] = nil
end

function QuestProgress:Dim(unit, plate, complete)
    local wanted = complete and Settings:GetOption("nameplateDimCompleted") == true
    local dim = self.dimmed[unit]
    if not wanted then
        if dim then
            self.dimmed[unit] = nil
            dim:Hide()
            dim:ClearAllPoints()
            dim:SetParent(nil)
            self.dims:Release(dim)
        end
        return
    end
    if not dim then
        dim = self:Acquire(self.dims)
        if not dim then
            return
        end
        self.dimmed[unit] = dim
    end
    local anchor = self:AnchorFor(plate)
    dim:SetParent(plate)
    dim:ClearAllPoints()
    dim:SetAllPoints(anchor)
    dim:Show()
end

-- groupCount is above zero only while group progress is on and someone in the group still
-- needs this mob. Dimming means nobody does: a mob the player finished stays bright while a
-- party member still has it open.
function QuestProgress:Apply(unit, plate, entry)
    local group = entry.groupCount or 0
    if not entry.ok and group == 0 then
        self:Release(unit)
        return
    end
    if entry.ok then
        self:ApplyOwn(unit, plate, entry, group == 0)
    else
        self:DropIndicator(unit)
        self:Dim(unit, plate, false)
        self.progress[unit], self.open[unit] = nil, nil
    end
    self:ApplyGroup(unit, plate, entry, group)
end

-- A member level with the player's own count gets the diamond alone: the number beside the
-- player's own already says it, twice would only crowd the plate.
function QuestProgress:ApplyGroup(unit, plate, entry, group)
    if group == 0 then
        self:DropGroup(unit)
        return
    end
    local row = self.rows[unit]
    if not row then
        row = self:Acquire(self.groupRows)
        if not row then
            return
        end
        self.rows[unit] = row
        row:ResetRow()
    end
    row:SetParent(plate)
    local open = entry.ok and not entry.complete
    local shown = math.min(group, GROUP_SHOWN)
    for slot = 1, shown do
        local fulfilled, required = entry.groupFulfilled[slot], entry.groupRequired[slot]
        local level = open and fulfilled == entry.fulfilled and required == entry.required
        local red, green, blue = classColor(entry.groupClass[slot])
        row:SetMember(slot, red, green, blue, string.format(R.L.NAMEPLATE_GROUP_COUNT, fulfilled, required), level)
    end
    row:SetMemberCount(shown, group > shown and string.format(R.L.NAMEPLATE_GROUP_MORE, group - shown) or nil)
    row:ClearAllPoints()
    local indicator = self.shown[unit]
    local left = Settings:GetOption("nameplateSide") == "LEFT"
    if indicator then
        row:SetPoint("TOPLEFT", indicator.valueHolder, "BOTTOMLEFT", 0, 1)
    elseif left then
        row:SetPoint("RIGHT", self:AnchorFor(plate), "LEFT", -ANCHOR_GAP, 0)
    else
        row:SetPoint("LEFT", self:AnchorFor(plate), "RIGHT", ANCHOR_GAP, 0)
    end
    row:Show()
end

function QuestProgress:ApplyOwn(unit, plate, entry, dimWhenDone)
    local previous = self.progress[unit]
    self.progress[unit] = entry.fulfilled
    self:Dim(unit, plate, entry.complete and dimWhenDone)
    local indicator = self.shown[unit]
    -- The checkmark is for the kill that finished the objective, seen on this plate. A mob
    -- already finished when its plate appeared gets the dim alone: replayed on every quest
    -- log update, the check would flash across every finished mob after any loot. One still
    -- fading from the kill that finished it is left to end.
    if entry.complete and not self.open[unit] then
        if indicator and not indicator:IsFading() then
            self:DropIndicator(unit)
        end
        return
    end
    self.open[unit] = not entry.complete
    if not indicator then
        indicator = self:Acquire(self.indicators)
        if not indicator then
            return
        end
        self.shown[unit] = indicator
        indicator:SetParent(plate)
        -- A recycled frame must never inherit the previous unit's numbers.
        indicator:ResetIndicator()
        indicator:SetParent(plate)
    end
    self:Place(indicator, plate)
    local reduce = Settings:GetOption("nameplateReduceAnimation") == true
    indicator:SetIconKind(entry.kind)
    indicator:SetIconShown(Settings:GetOption("nameplateShowIcon") ~= false and not entry.complete)
    indicator:SetProgress(entry.fulfilled, entry.required, entry.lastOne)
    indicator:SetComplete(entry.complete)
    if entry.plus > 0 and Settings:GetOption("nameplateShowMore") == true then
        indicator:SetCountText(tostring(entry.fulfilled),
            string.format(R.L.NAMEPLATE_TOTAL_PLUS, entry.required, entry.plus))
    else
        indicator:SetCountText(tostring(entry.fulfilled), string.format(R.L.NAMEPLATE_TOTAL, entry.required))
    end
    indicator:Show()
    if previous and previous ~= entry.fulfilled then
        indicator:Pop(reduce)
    end
    if entry.complete then
        indicator:FadeOut(reduce)
    end
end

function QuestProgress:Resolve(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then
        self:Release(unit)
        return
    end
    local guid = self.guids[unit]
    local npcID = guid and Data:NPCID(guid)
    local entry = npcID and Data:Get(npcID)
    if not entry then
        entry = self.scratch
        Data:Resolve(unit, entry)
        if not entry.ok and entry.groupCount == 0 and not self.retried[unit] then
            -- One retry on the next frame: a plate can appear before its quest data does.
            self.retried[unit] = true
            self:Enqueue(unit)
            return
        end
        if npcID then
            local stored = self.entries:Acquire()
            stored.ok, stored.fulfilled, stored.required = entry.ok, entry.fulfilled, entry.required
            stored.plus, stored.kind = entry.plus, entry.kind
            stored.complete, stored.lastOne = entry.complete, entry.lastOne
            local count = entry.groupCount
            for slot = 1, count do
                stored.groupMember[slot], stored.groupClass[slot] = entry.groupMember[slot], entry.groupClass[slot]
                stored.groupFulfilled[slot] = entry.groupFulfilled[slot]
                stored.groupRequired[slot] = entry.groupRequired[slot]
                stored.groupRatio[slot] = entry.groupRatio[slot]
            end
            stored.groupCount = count
            Data:Put(npcID, stored)
            entry = stored
        end
    end
    self:Apply(unit, plate, entry)
end

function QuestProgress:Enqueue(unit)
    local queue = self.queue
    for index = 1, #queue do
        if queue[index] == unit then
            return
        end
    end
    queue[#queue + 1] = unit
    if not self.draining then
        self.draining = true
        R:After(self, 0, self.Drain)
    end
end

-- One plate that cannot be read (restricted tooltip data, a secret value) must not take
-- the rest with it: an error escaping the timer would fail the whole module, and every
-- plate would go blank until the player toggled it. It costs that plate only, and the
-- first such error is kept for /refactor errors.
--
-- Only what was queued before this pass is drained: a plate that asks for its retry while
-- being resolved waits for the next frame, which is the point of the retry.
function QuestProgress:Drain()
    local queue = self.queue
    for _ = 1, math.min(#queue, PLATE_BUDGET) do
        local unit = table.remove(queue, 1)
        if self.guids[unit] ~= nil then
            local ok, err = pcall(self.Resolve, self, unit)
            if not ok then
                if not self.reported then
                    self.reported = true
                    R:RecordError(self, err, "resolve")
                end
                pcall(self.Release, self, unit)
            end
        end
    end
    if #queue > 0 then
        R:After(self, 0, self.Drain)
    else
        self.draining = false
    end
end

function QuestProgress:OnPlateAdded(_, unit)
    if type(unit) ~= "string" then
        return
    end
    if not C_NamePlate.GetNamePlateForUnit(unit) then
        return
    end
    -- No GUID, or a secret one while unit identity is restricted, still gets the plate
    -- resolved, only without the NPC cache. false marks the unit as tracked.
    local guid = UnitGUID(unit)
    if guid == nil or issecretvalue(guid) then
        guid = false
    end
    self.guids[unit] = guid
    self.progress[unit], self.retried[unit], self.open[unit] = nil, nil, nil
    self:Enqueue(unit)
end

function QuestProgress:OnPlateRemoved(_, unit)
    if type(unit) == "string" then
        self.guids[unit] = nil
        self:Release(unit)
    end
end

-- Clearing the cache without redrawing what is on screen is the stale-number bug.
-- The visible set is the one we tracked from NAME_PLATE_UNIT_ADDED and REMOVED: the plate
-- frame itself exposes no unit token, so reading one off it silently redrew nothing.
function QuestProgress:OnQuestChanged()
    Data:Invalidate()
    self.entries:ReleaseAll()
    self:Redraw()
end

function QuestProgress:Redraw()
    for unit in pairs(self.guids) do
        self.retried[unit] = true
        self:Enqueue(unit)
    end
end

-- Side, icon, dim, +N and animation apply to the plates already up, from the cache. Group
-- progress changes what a resolve reads, so it empties the cache first. A change with no
-- key is a profile switch, which can carry any of them.
function QuestProgress:OnSettingsChanged(_, key)
    if key == nil or key == "nameplateShowGroup" then
        Data:SetTrackGroup(Settings:GetOption("nameplateShowGroup") == true)
        self:OnQuestChanged()
    elseif type(key) == "string" and string.sub(key, 1, 9) == "nameplate" then
        self:Redraw()
    end
end

-- Who is in the group, by the names a group tooltip heads their objectives with. The second
-- value of UnitName is a surname on Forever and a realm on Retail; the data half tries both
-- joins. A name the client hands over as a secret value is left out, never compared.
local function usable(value)
    return type(value) == "string" and value ~= "" and not issecretvalue(value)
end

function QuestProgress:RebuildRoster()
    local names, seconds, classes = self.rosterNames, self.rosterSeconds, self.rosterClasses
    local count = 0
    if IsInGroup() then
        local units = IsInRaid() and RAID_UNITS or PARTY_UNITS
        for index = 1, #units do
            local unit = units[index]
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local name, second = UnitName(unit)
                if usable(name) then
                    local _, classFile = UnitClass(unit)
                    count = count + 1
                    names[count] = name
                    seconds[count] = usable(second) and second or false
                    classes[count] = usable(classFile) and classFile or false
                end
            end
        end
    end
    for index = count + 1, #names do
        names[index], seconds[index], classes[index] = nil, nil, nil
    end
    Data:SetRoster(names, seconds, classes, count)
end

-- The roster is part of every cached entry's group slots, so a change empties the cache.
function QuestProgress:OnRosterChanged()
    self:RebuildRoster()
    if Settings:GetOption("nameplateShowGroup") == true then
        self:OnQuestChanged()
    end
end

function QuestProgress:OnEnable()
    local owner = R.Integrations:Owner(self.id)
    if owner then
        -- Deference is decided once. While deferring the module holds no handler at all.
        self.unavailableReasonKey = "NAMEPLATE_QUEST_DEFERRED"
        self.state = "unavailable"
        self.unavailableReason = string.format(R.L.NAMEPLATE_QUEST_DEFERRED, owner)
        R.Broker:Emit("REFACTOR_MODULE_CHANGED", self.id)
        return
    end
    -- Forever's second value is the surname, and its group tooltips head the player's
    -- section with both, joined by a space: "Profet Ashbringer" (seen 5 Nov 2026). Retail
    -- gives the player no second value.
    local name, surname = UnitName("player")
    Data:SetPlayerNames(name, type(surname) == "string" and surname ~= "" and name .. " " .. surname or nil)
    self.shown, self.dimmed, self.guids, self.rows = {}, {}, {}, {}
    self.progress, self.retried, self.queue, self.open = {}, {}, {}, {}
    self.scratch, self.draining, self.reported = groupEntry(), false, nil
    self.rosterNames, self.rosterSeconds, self.rosterClasses = {}, {}, {}
    self.entries = R.Pools:Create(groupEntry, resetEntry)
    self.indicators = R.Pools:Create(function() return Theme:QuestIndicator(nil) end)
    self.dims = R.Pools:Create(function() return Theme:PlateDim(nil) end)
    self.groupRows = R.Pools:Create(function() return Theme:QuestGroupRow(nil) end)
    for _ = 1, POOL_SIZE do
        self.indicators:Acquire()
        self.dims:Acquire()
        self.groupRows:Acquire()
    end
    self.indicators:ReleaseAll()
    self.dims:ReleaseAll()
    self.groupRows:ReleaseAll()
    self:RebuildRoster()
    Data:SetTrackGroup(Settings:GetOption("nameplateShowGroup") == true)
    R.Broker:Subscribe("NAME_PLATE_UNIT_ADDED", self.OnPlateAdded, self)
    R.Broker:Subscribe("NAME_PLATE_UNIT_REMOVED", self.OnPlateRemoved, self)
    R.Broker:Subscribe("QUEST_LOG_UPDATE", self.OnQuestChanged, self, 0.2)
    R.Broker:Subscribe("UNIT_QUEST_LOG_CHANGED", self.OnQuestChanged, self, 0.2)
    R.Broker:Subscribe("GROUP_ROSTER_UPDATE", self.OnRosterChanged, self, 0.2)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
end

function QuestProgress:OnDisable()
    self.unavailableReasonKey = nil
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    if self.guids then
        for unit in pairs(self.guids) do
            self:Release(unit)
        end
    end
    if self.entries then
        self.entries:ReleaseAll()
    end
    Data:Invalidate()
    Data:SetPlayerNames(nil, nil)
    Data:SetRoster(nil, nil, nil, 0)
    Data:SetTrackGroup(false)
    self.guids, self.progress, self.retried, self.open, self.rows = nil, nil, nil, nil, nil
    self.queue, self.draining, self.scratch, self.reported = nil, false, nil, nil
    self.rosterNames, self.rosterSeconds, self.rosterClasses = nil, nil, nil
end
