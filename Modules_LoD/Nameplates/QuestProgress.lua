--- @module nameplates.questProgress
--- Purpose: show how close each nameplate mob is to finishing your quest objective.
--- Requires: C_NamePlate.GetNamePlateForUnit, UnitGUID, UnitName, issecretvalue, and the data half's
---     C_QuestLog.UnitIsRelatedToActiveQuest, C_QuestLog.GetQuestObjectives, C_QuestLog.IsOnQuest,
---     IsInGroup, C_TooltipInfo.GetUnit, Enum.TooltipDataLineType.QuestTitle,
---     Enum.TooltipDataLineType.QuestObjective, Enum.TooltipDataLineType.QuestPlayer
--- Events: NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED,
---     QUEST_LOG_UPDATE (throttled), UNIT_QUEST_LOG_CHANGED (throttled), REFACTOR_SETTINGS_CHANGED
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
        "C_QuestLog.UnitIsRelatedToActiveQuest", "C_QuestLog.GetQuestObjectives", "C_QuestLog.IsOnQuest",
        "IsInGroup", "C_TooltipInfo.GetUnit", "Enum.TooltipDataLineType.QuestTitle",
        "Enum.TooltipDataLineType.QuestObjective", "Enum.TooltipDataLineType.QuestPlayer" },
    conflicts = { "Questie.nameplateObjectives", "Plater.questProgress" },
    risk = "visible",
    defaultEnabled = true,
})

local PLATE_BUDGET, POOL_SIZE, ANCHOR_GAP = 4, 20, 6

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

function QuestProgress:Release(unit)
    self:DropIndicator(unit)
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

function QuestProgress:Apply(unit, plate, entry)
    if not entry.ok then
        self:Release(unit)
        return
    end
    local previous = self.progress[unit]
    self.progress[unit] = entry.fulfilled
    self:Dim(unit, plate, entry.complete)
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
        if not entry.ok and not self.retried[unit] then
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

-- Side, icon, dim, +N and animation apply to the plates already up, from the cache. A
-- change with no key is a profile switch, which can carry any of them.
function QuestProgress:OnSettingsChanged(_, key)
    if key == nil or (type(key) == "string" and string.sub(key, 1, 9) == "nameplate") then
        self:Redraw()
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
    self.shown, self.dimmed, self.guids = {}, {}, {}
    self.progress, self.retried, self.queue, self.open = {}, {}, {}, {}
    self.scratch, self.draining, self.reported = {}, false, nil
    self.entries = R.Pools:CreateTablePool()
    self.indicators = R.Pools:Create(function() return Theme:QuestIndicator(nil) end)
    self.dims = R.Pools:Create(function() return Theme:PlateDim(nil) end)
    for _ = 1, POOL_SIZE do
        self.indicators:Acquire()
        self.dims:Acquire()
    end
    self.indicators:ReleaseAll()
    self.dims:ReleaseAll()
    R.Broker:Subscribe("NAME_PLATE_UNIT_ADDED", self.OnPlateAdded, self)
    R.Broker:Subscribe("NAME_PLATE_UNIT_REMOVED", self.OnPlateRemoved, self)
    R.Broker:Subscribe("QUEST_LOG_UPDATE", self.OnQuestChanged, self, 0.2)
    R.Broker:Subscribe("UNIT_QUEST_LOG_CHANGED", self.OnQuestChanged, self, 0.2)
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
    self.guids, self.progress, self.retried, self.open = nil, nil, nil, nil
    self.queue, self.draining, self.scratch, self.reported = nil, false, nil, nil
end
