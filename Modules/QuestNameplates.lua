-- Refactor Addon - Quest Nameplates Module
-- Shows quest progress icons on nameplates of quest-related mobs

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false
local nameplateFrames = {} -- Track our overlay frames per nameplate
-- Cache of GUIDs confirmed to be quest-related via tooltip scan
local tooltipQuestMobs = {}
local tooltipScanTime = {}
local TOOLTIP_CACHE_DURATION = 5 -- Seconds before re-scanning a mob's tooltip

----------------------------------------------
-- Quest Objective Cache
----------------------------------------------
local questObjectiveCache = {}
local questObjectiveByTarget = {} -- Pre-indexed by extracted target name (lowercase)
local cacheUpdateTime = 0
local CACHE_DURATION = 0.5 -- Refresh cache every 0.5 seconds

-- Create a scanning tooltip (hidden, just for data extraction)
local scanningTooltip = CreateFrame("GameTooltip", "RefactorQuestNameplateScanTooltip", nil, "GameTooltipTemplate")
scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function UpdateQuestObjectiveCache()
    local now = GetTime()
    if now - cacheUpdateTime < CACHE_DURATION then
        return questObjectiveCache
    end
    
    wipe(questObjectiveCache)
    wipe(questObjectiveByTarget)
    cacheUpdateTime = now
    
    -- Iterate through all quests in the quest log
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    
    for i = 1, numEntries do
        local questInfo = C_QuestLog.GetInfo(i)
        if questInfo and not questInfo.isHeader and not questInfo.isHidden then
            local questID = questInfo.questID
            local objectives = C_QuestLog.GetQuestObjectives(questID)
            
            if objectives then
                for objIndex, objective in ipairs(objectives) do
                    if not objective.finished then
                        local text = objective.text or ""
                        local objectiveType = objective.type -- "monster", "item", "object", etc.
                        
                        local objectiveData = {
                            questID = questID,
                            questTitle = questInfo.title,
                            numFulfilled = objective.numFulfilled or 0,
                            numRequired = objective.numRequired or 1,
                            objectiveType = objectiveType,
                            finished = objective.finished,
                            text = text,
                        }
                        
                        -- Store objective info by text
                        questObjectiveCache[text] = objectiveData
                        
                        -- Extract and index by target name for faster lookups
                        local targetName = Module.ExtractTargetFromObjective(text)
                        if targetName then
                            local lowerTarget = targetName:lower()
                            questObjectiveByTarget[lowerTarget] = objectiveData
                            
                            -- Also store the original case version for reference
                            objectiveData.extractedTarget = targetName
                        end
                        
                        -- For item quests, also index by item name
                        if objectiveType == "item" then
                            local itemName = text:match("^%d+/%d+%s+(.+)$") or text:match("^(.+):%s*%d+/%d+$")
                            if itemName then
                                questObjectiveCache["ITEM:" .. itemName:lower()] = objectiveData
                            end
                        end
                    end
                end
            end
        end
    end
    
    return questObjectiveCache
end

----------------------------------------------
-- Helper: Extract target name from objective text
-- Handles formats like:
--   "Creature Name slain: 0/10"
--   "0/10 Creature Name slain"
--   "0/10 Creature Name"
--   "Creature Name: 0/10"
----------------------------------------------
function Module.ExtractTargetFromObjective(text)
    if not text then return nil end
    
    -- Remove progress counters like "0/10" or "5/5"
    local cleaned = text:gsub("%d+/%d+", "")
    
    -- Remove common suffix words (case insensitive, but preserve case for output)
    cleaned = cleaned:gsub("%s+[Ss]lain%s*$", "")
    cleaned = cleaned:gsub("%s+[Kk]illed%s*$", "")
    cleaned = cleaned:gsub("%s+[Dd]efeated%s*$", "")
    cleaned = cleaned:gsub("%s+[Dd]estroyed%s*$", "")
    
    -- Remove leading/trailing colons and whitespace
    cleaned = cleaned:gsub("^[%s:]+", "")
    cleaned = cleaned:gsub("[%s:]+$", "")
    
    -- Trim any remaining whitespace
    cleaned = cleaned:match("^%s*(.-)%s*$")
    
    return cleaned ~= "" and cleaned or nil
end

----------------------------------------------
-- Helper: Check if unit's tooltip contains quest-related lines
-- This is the most reliable way to detect quest mobs
----------------------------------------------
local function IsUnitQuestRelatedByTooltip(unitId)
    local guid = UnitGUID(unitId)
    if not guid then return false, nil end
    
    -- Check cache first
    local now = GetTime()
    local cachedTime = tooltipScanTime[guid]
    if cachedTime and (now - cachedTime) < TOOLTIP_CACHE_DURATION then
        return tooltipQuestMobs[guid] ~= nil, tooltipQuestMobs[guid]
    end
    
    -- Scan the tooltip
    scanningTooltip:ClearLines()
    scanningTooltip:SetUnit(unitId)
    
    local foundQuestLine = false
    local questProgress = nil
    
    -- Scan tooltip lines for quest-related content
    -- Quest objectives typically show up with specific formatting
    for i = 2, scanningTooltip:NumLines() do
        local leftText = _G["RefactorQuestNameplateScanTooltipTextLeft" .. i]
        if leftText then
            local text = leftText:GetText()
            if text then
                -- Check for progress format like "0/8" or "3/5"
                local current, required = text:match("(%d+)%s*//%s*(%d+)")
                if not current then
                    current, required = text:match("(%d+)/(%d+)")
                end
                
                if current and required then
                    foundQuestLine = true
                    questProgress = {
                        numFulfilled = tonumber(current) or 0,
                        numRequired = tonumber(required) or 1,
                        tooltipLine = text,
                    }
                    break
                end
                
                -- Check for percentage format
                local percentage = text:match("(%d+)%%")
                if percentage then
                    foundQuestLine = true
                    questProgress = {
                        numFulfilled = tonumber(percentage) or 0,
                        numRequired = 100,
                        tooltipLine = text,
                        isPercentage = true,
                    }
                    break
                end
            end
        end
    end
    
    -- Cache the result
    tooltipScanTime[guid] = now
    if foundQuestLine then
        tooltipQuestMobs[guid] = questProgress
    else
        tooltipQuestMobs[guid] = nil
    end
    
    return foundQuestLine, questProgress
end

----------------------------------------------
-- Helper: Find matching quest objective for a unit
-- Uses STRICT matching to avoid false positives
----------------------------------------------
local function FindQuestObjective(unitName, unitId)
    if not unitName then return nil end
    
    UpdateQuestObjectiveCache()
    local lowerName = unitName:lower()
    
    -- PRIORITY 1: Exact match in pre-indexed target names
    local exactMatch = questObjectiveByTarget[lowerName]
    if exactMatch then
        return exactMatch, "exact"
    end
    
    -- PRIORITY 2: Check if UnitIsQuestBoss and we have a matching monster objective
    -- (Only match if the mob name appears in the objective text)
    if UnitIsQuestBoss(unitId) then
        for text, objectiveData in pairs(questObjectiveCache) do
            if not text:match("^ITEM:") then
                if objectiveData.objectiveType == "monster" then
                    -- Check if mob name appears in the objective text (case-insensitive)
                    if text:lower():find(lowerName, 1, true) then
                        return objectiveData, "questboss_match"
                    end
                end
            end
        end
    end
    
    -- PRIORITY 3: For mobs that are UnitIsQuestBoss, try tooltip verification
    -- This catches cases where the API knows it's a quest mob but name matching failed
    if UnitIsQuestBoss(unitId) then
        local hasQuestTooltip, tooltipData = IsUnitQuestRelatedByTooltip(unitId)
        if hasQuestTooltip and tooltipData then
            -- Find the best matching objective based on progress
            for text, objectiveData in pairs(questObjectiveCache) do
                if not text:match("^ITEM:") and not objectiveData.finished then
                    -- Match by progress numbers
                    if objectiveData.numFulfilled == tooltipData.numFulfilled and
                       objectiveData.numRequired == tooltipData.numRequired then
                        return objectiveData, "tooltip_progress"
                    end
                end
            end
            
            -- If we have tooltip data but no matching objective, return tooltip data as-is
            return {
                numFulfilled = tooltipData.numFulfilled,
                numRequired = tooltipData.numRequired,
                objectiveType = "monster",
                text = tooltipData.tooltipLine,
            }, "tooltip_only"
        end
    end
    
    -- NO FALLBACK: We specifically avoid loose matching to prevent false positives
    -- If we couldn't find a match through exact name, questboss + name, or tooltip,
    -- then we should NOT show anything on this mob.
    
    return nil, nil
end

----------------------------------------------
-- Helper: Create overlay frame for nameplate
----------------------------------------------
local function CreateNameplateOverlay(nameplate)
    local frame = CreateFrame("Frame", nil, nameplate)
    frame:SetSize(60, 18)
    
    -- Anchor to nameplate, positioned just above the health bar area
    local anchorFrame = nameplate.UnitFrame or nameplate
    frame:SetPoint("BOTTOM", anchorFrame, "TOP", 0, -8)
    frame:SetFrameStrata("HIGH")
    
    -- Progress text (centered)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.text:SetPoint("CENTER", frame, "CENTER", 6, 0)
    frame.text:SetTextColor(1, 0.82, 0) -- Gold color
    
    -- Icon texture (left of text)
    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetSize(14, 14)
    frame.icon:SetPoint("RIGHT", frame.text, "LEFT", -2, 0)
    
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
-- Update a single nameplate
----------------------------------------------
local function UpdateNameplate(unitId)
    if not isEnabled then return end
    
    local nameplate = C_NamePlate.GetNamePlateForUnit(unitId)
    if not nameplate then return end
    
    local overlay = GetNameplateOverlay(nameplate)
    
    -- Get unit name first
    local unitName = UnitName(unitId)
    if not unitName then
        overlay:Hide()
        return
    end
    
    -- Skip dead units
    if UnitIsDead(unitId) then
        overlay:Hide()
        return
    end
    
    -- Skip friendly units (NPCs we can't attack usually aren't quest targets)
    if not UnitCanAttack("player", unitId) and not UnitIsQuestBoss(unitId) then
        overlay:Hide()
        return
    end
    
    -- Try to find a matching quest objective
    local objectiveData, matchType = FindQuestObjective(unitName, unitId)
    
    -- If no match found, hide the overlay
    if not objectiveData then
        overlay:Hide()
        return
    end
    
    -- Get display preferences
    local showKillIcon = addon.GetDBBool("QuestNameplates_ShowKillIcon")
    local showLootIcon = addon.GetDBBool("QuestNameplates_ShowLootIcon")
    
    local objectiveType = objectiveData.objectiveType or "monster"
    
    -- Determine icon and whether to show based on objective type
    if objectiveType == "monster" then
        if not showKillIcon then
            overlay:Hide()
            return
        end
        -- Use swords icon for kill objectives
        overlay.icon:SetTexture("Interface\\CURSOR\\Attack")
        overlay.icon:SetTexCoord(0, 1, 0, 1)
        overlay.icon:SetVertexColor(1, 1, 1) -- White/normal
    else
        -- item, object, or other types - use bag/loot icon
        if not showLootIcon then
            overlay:Hide()
            return
        end
        overlay.icon:SetTexture("Interface\\Minimap\\Tracking\\Banker")
        overlay.icon:SetTexCoord(0, 1, 0, 1)
        overlay.icon:SetVertexColor(1, 0.85, 0.1) -- Gold tint for loot
    end
    
    -- Set progress text
    local progressText = string.format("%d/%d", 
        objectiveData.numFulfilled, 
        objectiveData.numRequired
    )
    overlay.text:SetText(progressText)
    overlay:Show()
end

----------------------------------------------
-- Clear nameplate overlay
----------------------------------------------
local function ClearNameplate(unitId)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unitId)
    if nameplate and nameplateFrames[nameplate] then
        nameplateFrames[nameplate]:Hide()
    end
end

----------------------------------------------
-- Update all visible nameplates
----------------------------------------------
local function UpdateAllNameplates()
    if not isEnabled then return end
    
    -- Clear the cache to force refresh
    cacheUpdateTime = 0
    
    -- Update all visible nameplates
    local nameplates = C_NamePlate.GetNamePlates()
    if nameplates then
        for _, nameplate in ipairs(nameplates) do
            local unitId = nameplate.namePlateUnitToken
            if unitId then
                UpdateNameplate(unitId)
            end
        end
    end
end

----------------------------------------------
-- Periodic cache cleanup (prevent memory leaks)
----------------------------------------------
local function CleanupTooltipCache()
    local now = GetTime()
    local expireTime = now - TOOLTIP_CACHE_DURATION * 2
    
    for guid, time in pairs(tooltipScanTime) do
        if time < expireTime then
            tooltipScanTime[guid] = nil
            tooltipQuestMobs[guid] = nil
        end
    end
end

----------------------------------------------
-- Event Handler
----------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local unitId = ...
        UpdateNameplate(unitId)
        
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unitId = ...
        ClearNameplate(unitId)
        
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or 
           event == "QUEST_REMOVED" or event == "QUEST_POI_UPDATE" then
        -- Quest data changed, update all nameplates
        cacheUpdateTime = 0 -- Force cache refresh
        C_Timer.After(0.1, UpdateAllNameplates)
        
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        -- Specific quest progress changed
        cacheUpdateTime = 0 -- Force cache refresh
        C_Timer.After(0.1, UpdateAllNameplates)
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
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("QUEST_POI_UPDATE")
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    
    -- Set up periodic cache cleanup
    C_Timer.NewTicker(30, CleanupTooltipCache)
    
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
    
    -- Clear caches
    wipe(tooltipQuestMobs)
    wipe(tooltipScanTime)
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
    -- Register for setting changes
    addon.CallbackRegistry:Register("SettingChanged.QuestNameplates", OnSettingChanged)
    
    -- Check initial state
    if addon.GetDBBool("QuestNameplates") then
        EnableModule()
    end
end

----------------------------------------------
-- Register Module
----------------------------------------------
addon.RegisterModule("QuestNameplates", Module)
