-- Refactor Addon - Quest Nameplates Module
-- Shows quest progress icons on nameplates of quest-related mobs

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local pairs, ipairs, tonumber, ceil = pairs, ipairs, tonumber, math.ceil
local strmatch = strmatch or string.match
local GetTime = GetTime
local UnitIsDead = UnitIsDead

-- Cache the critical APIs
local C_NamePlate_GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
-- The KEY API: This is the authoritative source for quest-related units
local C_QuestLog_UnitIsRelatedToActiveQuest = C_QuestLog.UnitIsRelatedToActiveQuest
-- Modern tooltip API (Dragonflight+)
local C_TooltipInfo_GetUnit = C_TooltipInfo and C_TooltipInfo.GetUnit or nil
local GetQuestObjectiveInfo = GetQuestObjectiveInfo

----------------------------------------------
-- Cached Settings
----------------------------------------------
local cachedShowKillIcon = true
local cachedShowLootIcon = true

local function UpdateCachedSettings()
    cachedShowKillIcon = addon.GetDBBool("QuestNameplates_ShowKillIcon")
    cachedShowLootIcon = addon.GetDBBool("QuestNameplates_ShowLootIcon")
end

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false
local nameplateFrames = {} -- Track our overlay frames per nameplate
local unitQuestCache = {}  -- [unitToken] = { [questID] = true, ... } — cached quest IDs per unit
local activeUnits = {}     -- [unitToken] = true — tracks all visible nameplate units
local tooltipRetries = {}  -- [unitToken] = retryCount — tracks tooltip data async loading
local Enum_TooltipDataLineType_QuestTitle = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or 17

local ScheduleNameplateUpdate
local RefreshNameplate
local InvalidateQuestCache

----------------------------------------------
-- Quest Progress: Shared objective parser
-- Reads CURRENT data from GetQuestObjectiveInfo (quest log, not tooltip)
----------------------------------------------
local function ParseQuestObjectives(questIDs)
    local progressText = nil
    local maxLeft = 0
    local isPercent = false
    local hasItemObjective = false
    local foundAnyUnfinished = false
    local foundAnyFinished = false

    for questID in pairs(questIDs) do
        for objIdx = 1, 10 do
            local text, objectiveType, finished = GetQuestObjectiveInfo(questID, objIdx, false)
            if not text then break end

            if not finished then
                foundAnyUnfinished = true
                local x, y = strmatch(text, "(%d+)/(%d+)")
                if x and y then
                    local numLeft = tonumber(y) - tonumber(x)
                    if numLeft > maxLeft then
                        maxLeft = numLeft
                        progressText = text
                    end
                else
                    local progress = tonumber(strmatch(text, "([%d%.]+)%%"))
                    if progress and progress <= 100 then
                        local numLeft = ceil(100 - progress)
                        if numLeft > maxLeft then
                            maxLeft = numLeft
                            progressText = text
                            isPercent = true
                        end
                    end
                end

                if objectiveType == "item" or objectiveType == "object" then
                    hasItemObjective = true
                end
            else
                foundAnyFinished = true
            end
        end
    end

    if progressText then
        return progressText, hasItemObjective and "item" or "monster", maxLeft, next(questIDs), isPercent
    end

    if foundAnyUnfinished then
        return "Quest Objective", hasItemObjective and "item" or "monster", 0, next(questIDs), false
    end

    if foundAnyFinished then
        return nil
    end

    if next(questIDs) then
        return "Quest Objective", "monster", 0, next(questIDs), false
    end
    return nil
end

----------------------------------------------
-- Quest Progress: Full discovery via tooltip
-- Used on NAME_PLATE_UNIT_ADDED for first-time quest ID discovery
----------------------------------------------
local function GetQuestProgress(unitID)
    if not C_TooltipInfo_GetUnit then return nil end
    local tooltipData = C_TooltipInfo_GetUnit(unitID)

    local uniqueQuestIDs = {}
    local foundAny = false

    if tooltipData and tooltipData.lines and #tooltipData.lines >= 2 then
        if TooltipUtil and TooltipUtil.SurfaceArgs then
            TooltipUtil.SurfaceArgs(tooltipData)
        end
        for i = 2, #tooltipData.lines do
            local line = tooltipData.lines[i]
            if TooltipUtil and TooltipUtil.SurfaceArgs then
                TooltipUtil.SurfaceArgs(line)
            end
            ---@diagnostic disable-next-line: undefined-field
            if line.type == Enum_TooltipDataLineType_QuestTitle and line.id then
                ---@diagnostic disable-next-line: undefined-field
                uniqueQuestIDs[line.id] = true
                foundAny = true
            end
        end
    end

    if not foundAny then
        -- Only retry if the game strongly hints it's a quest mob, but the tooltip is missing data
        if C_QuestLog_UnitIsRelatedToActiveQuest(unitID) then
            if not tooltipRetries[unitID] then
                tooltipRetries[unitID] = 0
            end
            if tooltipRetries[unitID] < 4 then
                tooltipRetries[unitID] = tooltipRetries[unitID] + 1
                C_Timer.After(0.2 * tooltipRetries[unitID], function()
                    if activeUnits[unitID] and not unitQuestCache[unitID] then
                        UpdateNameplate(unitID) -- Re-run the full update flow
                    end
                end)
            end
        else
            tooltipRetries[unitID] = nil
        end
        return nil -- Return nil so we don't show a false positive '!'
    end

    -- Success
    tooltipRetries[unitID] = nil
    unitQuestCache[unitID] = uniqueQuestIDs

    return ParseQuestObjectives(uniqueQuestIDs)
end

----------------------------------------------
-- Quest Progress: Fast refresh using cached quest IDs
-- Bypasses tooltip cache — reads directly from quest log
----------------------------------------------
local function RefreshQuestProgress(unitID)
    -- We bypass C_QuestLog.UnitIsRelatedToActiveQuest check here to support World Quests
    -- and other tracked objectives that the API sometimes misses.

    local cachedQuestIDs = unitQuestCache[unitID]
    if cachedQuestIDs then
        return ParseQuestObjectives(cachedQuestIDs)
    end

    -- No cache yet — fall back to full tooltip discovery
    return GetQuestProgress(unitID)
end

----------------------------------------------
-- Helper: Find the visual Health Bar
----------------------------------------------
local function FindHealthBar(nameplate)
    local unitFrame = nameplate.UnitFrame or nameplate.unitFrame
    if unitFrame then
        if unitFrame.healthBar then return unitFrame.healthBar end
        if unitFrame.Health then return unitFrame.Health end
    end
    -- Fallback: aggressively search for a StatusBar to bypass invisible clicking frames
    local framesToCheck = { nameplate, unitFrame }
    for _, parent in pairs(framesToCheck) do
        if parent and parent.GetChildren then
            for _, child in pairs({ parent:GetChildren() }) do
                if child.GetObjectType and child:GetObjectType() == "StatusBar" then
                    return child
                end
            end
        end
    end
    return unitFrame or nameplate
end

----------------------------------------------
-- Helper: Create overlay frame for nameplate
----------------------------------------------
local function CreateNameplateOverlay(nameplate)
    local frame = CreateFrame("Frame", nil, nameplate)
    frame:SetSize(1, 1) -- 1x1 anchor point

    local healthBar = FindHealthBar(nameplate)

    -- Anchor exactly to the top-right corner of the physical red bar.
    -- X offset: 2 (pulls it slightly right), Y offset: -2 (pushes it slightly down to sit on the stroke)
    frame:SetPoint("CENTER", healthBar, "TOPRIGHT", 12, 0)

    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(10)

    -- Kill indicator icon (sword, shown for kill objectives)
    frame.killIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.killIcon:SetSize(16, 16)
    frame.killIcon:SetPoint("BOTTOMRIGHT", frame, "CENTER", 0, 0)
    frame.killIcon:SetTexture("Interface\\CURSOR\\Attack")
    frame.killIcon:SetTexCoord(0, 1, 0, 1)
    frame.killIcon:Hide()

    -- Loot indicator icon (bag, shown for item objectives)
    frame.lootIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.lootIcon:SetSize(16, 16)
    frame.lootIcon:SetPoint("BOTTOMRIGHT", frame, "CENTER", 0, 0)
    frame.lootIcon:SetAtlas("Banker")
    frame.lootIcon:Hide()

    -- Progress count text (anchored to the right of whichever icon is shown)
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.text:SetPoint("LEFT", frame.killIcon, "RIGHT", 2, 0)
    frame.text:SetTextColor(1, 0.82, 0) -- WoW quest yellow
    frame.text:SetShadowOffset(1, -1)
    frame.text:SetShadowColor(0, 0, 0, 1)

    frame:Hide()
    return frame
end

----------------------------------------------
-- Helper: Get or create overlay for nameplate
----------------------------------------------
local function GetNameplateOverlay(nameplate)
    if not nameplateFrames[nameplate] then
        nameplateFrames[nameplate] = CreateNameplateOverlay(nameplate)
    end
    return nameplateFrames[nameplate]
end

----------------------------------------------
-- Shared display logic for overlays
----------------------------------------------
local function ApplyOverlay(overlay, progressText, objectiveType, objectiveCount, isPercent)
    if not progressText then
        overlay:Hide()
        return
    end

    local isItemObjective = (objectiveType == "item" or objectiveType == "object")

    if isItemObjective and not cachedShowLootIcon then
        overlay:Hide()
        return
    elseif not isItemObjective and not cachedShowKillIcon then
        overlay:Hide()
        return
    end

    if isItemObjective then
        overlay.lootIcon:Show()
        overlay.killIcon:Hide()
    else
        overlay.killIcon:Show()
        overlay.lootIcon:Hide()
    end

    if objectiveCount > 0 then
        if isPercent then
            overlay.text:SetFont("Fonts\\FRIZQT__.TTF", objectiveCount == 100 and 10 or 11, "OUTLINE")
            overlay.text:SetText(objectiveCount .. "%")
        else
            overlay.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            overlay.text:SetText(objectiveCount)
        end
    else
        overlay.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        overlay.text:SetText("!")
    end

    overlay:Show()
end

----------------------------------------------
-- Update nameplate overlay (full tooltip discovery)
----------------------------------------------
local function UpdateNameplate(unitId)
    if not isEnabled then return end

    local nameplate = C_NamePlate_GetNamePlateForUnit(unitId)
    if not nameplate then return end

    local overlay = GetNameplateOverlay(nameplate)

    local progressText, objectiveType, objectiveCount, questID, isPercent = GetQuestProgress(unitId)

    if UnitIsDead(unitId) and objectiveType ~= "item" then
        overlay:Hide()
        return
    end

    ApplyOverlay(overlay, progressText, objectiveType, objectiveCount, isPercent)
end

----------------------------------------------
-- Refresh nameplate overlay (fast path, no tooltip)
----------------------------------------------
RefreshNameplate = function(unitId)
    if not isEnabled then return end

    local nameplate = C_NamePlate_GetNamePlateForUnit(unitId)
    if not nameplate then return end

    local overlay = GetNameplateOverlay(nameplate)

    local progressText, objectiveType, objectiveCount, questID, isPercent = RefreshQuestProgress(unitId)

    if UnitIsDead(unitId) and objectiveType ~= "item" then
        overlay:Hide()
        return
    end

    ApplyOverlay(overlay, progressText, objectiveType, objectiveCount, isPercent)
end

----------------------------------------------
-- Clear nameplate overlay
----------------------------------------------
local function ClearNameplate(unitId)
    local nameplate = C_NamePlate_GetNamePlateForUnit(unitId)
    if nameplate and nameplateFrames[nameplate] then
        nameplateFrames[nameplate]:Hide()
    end
    unitQuestCache[unitId] = nil
end

----------------------------------------------
-- Update all visible nameplates
----------------------------------------------
local pendingNameplateUpdate = false

local function UpdateAllNameplates()
    if not isEnabled then return end

    for unitId in pairs(activeUnits) do
        RefreshNameplate(unitId)
    end
end

-- A robust debouncer: guarantees we never drop events that fire in quick succession
ScheduleNameplateUpdate = function()
    if pendingNameplateUpdate then return end

    pendingNameplateUpdate = true
    C_Timer.After(0.15, function()
        pendingNameplateUpdate = false
        UpdateAllNameplates()
    end)
end

InvalidateQuestCache = function()
    table.wipe(unitQuestCache)
    ScheduleNameplateUpdate()
end

----------------------------------------------
-- Event Handler
----------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local unitId = ...
        activeUnits[unitId] = true
        unitQuestCache[unitId] = nil -- Clear stale cache from previous mob on this token
        tooltipRetries[unitId] = nil
        UpdateNameplate(unitId)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unitId = ...
        activeUnits[unitId] = nil
        tooltipRetries[unitId] = nil
        ClearNameplate(unitId)
    elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        InvalidateQuestCache()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        local unitId = ...
        if unitId == "player" then
            InvalidateQuestCache()
        end
    elseif event == "QUEST_LOG_UPDATE" then
        ScheduleNameplateUpdate()
    elseif event == "UI_INFO_MESSAGE" then
        local messageType, text = ...
        if messageType == LE_INFO_MESSAGE_TYPE_QUEST_OBJECTIVE then
            ScheduleNameplateUpdate()
        end
    elseif event == "UNIT_HEALTH" then
        local unitId = ...
        if unitId and strmatch(unitId, "nameplate%d+") then
            if UnitIsDead(unitId) then
                ScheduleNameplateUpdate()
            end
        end
    else
        -- QUEST_POI_UPDATE, QUEST_WATCH_UPDATE
        ScheduleNameplateUpdate()
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

----------------------------------------------
-- Enable/Disable Module
----------------------------------------------
local function EnableModule()
    if isEnabled then return end
    isEnabled = true

    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    -- Quest Progress Events
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("QUEST_POI_UPDATE")
    eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    eventFrame:RegisterEvent("UI_INFO_MESSAGE")

    -- Fallback Combat Events
    eventFrame:RegisterEvent("UNIT_HEALTH")

    -- Update any currently visible nameplates
    UpdateAllNameplates()
end

local function DisableModule()
    if not isEnabled then return end
    isEnabled = false

    eventFrame:UnregisterAllEvents()

    -- Hide all overlays
    for _, frame in pairs(nameplateFrames) do
        frame:Hide()
    end
end

----------------------------------------------
-- Settings Callback
----------------------------------------------
local function OnSettingChanged(value, userInput)
    if value then
        EnableModule()
    else
        DisableModule()
    end
end

----------------------------------------------
-- Module Initialization
----------------------------------------------
function Module:OnInitialize()
    -- Cache initial settings
    UpdateCachedSettings()

    -- Register for setting changes
    addon.CallbackRegistry:Register("SettingChanged.QuestNameplates", OnSettingChanged)
    addon.CallbackRegistry:Register("SettingChanged.QuestNameplates_ShowKillIcon", function()
        UpdateCachedSettings()
        ScheduleNameplateUpdate()
    end)
    addon.CallbackRegistry:Register("SettingChanged.QuestNameplates_ShowLootIcon", function()
        UpdateCachedSettings()
        ScheduleNameplateUpdate()
    end)

    -- Check initial state
    if addon.GetDBBool("QuestNameplates") then
        EnableModule()
    end
end

----------------------------------------------
-- Register Module
----------------------------------------------
addon.RegisterModule("QuestNameplates", Module)
