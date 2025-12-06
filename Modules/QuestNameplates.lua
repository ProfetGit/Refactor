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
local C_NamePlate_GetNamePlates = C_NamePlate.GetNamePlates
-- The KEY API: This is the authoritative source for quest-related units
local C_QuestLog_UnitIsRelatedToActiveQuest = C_QuestLog.UnitIsRelatedToActiveQuest
-- Modern tooltip API (Dragonflight+)
local C_TooltipInfo_GetUnit = C_TooltipInfo and C_TooltipInfo.GetUnit
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

----------------------------------------------
-- Quest Progress Detection (using proper APIs)
----------------------------------------------

-- Get quest progress for a unit using C_TooltipInfo (Dragonflight+ API)
-- Returns: progressText, objectiveType, objectiveCount, questID
local function GetQuestProgress(unitID)
    -- CRITICAL: This is the ONLY reliable gate for quest-related mobs
    -- If the game says this unit is NOT related to an active quest, do NOT show anything
    if not C_QuestLog_UnitIsRelatedToActiveQuest(unitID) then
        return nil
    end
    
    -- Use the modern tooltip API to get quest data
    if not C_TooltipInfo_GetUnit then
        -- Fallback for older clients (pre-Dragonflight)
        return nil
    end
    
    local tooltipData = C_TooltipInfo_GetUnit(unitID)
    if not tooltipData or not tooltipData.lines then
        return nil
    end
    
    local progressText = nil
    local objectiveCount = 0
    local questID = nil
    local hasItemObjective = false
    
    -- Scan tooltip lines for quest information
    for i = 3, #tooltipData.lines do
        local line = tooltipData.lines[i]
        
        -- Type 17 indicates a quest-related tooltip line
        if line.type == 17 and line.id then
            questID = line.id
            
            -- Get objective info from the quest
            local text, objectiveType, finished = GetQuestObjectiveInfo(line.id, 1, false)
            if text and not finished then
                -- Extract progress numbers
                local x, y = strmatch(text, "(%d+)/(%d+)")
                if x and y then
                    local numLeft = tonumber(y) - tonumber(x)
                    if numLeft > objectiveCount then
                        objectiveCount = numLeft
                    end
                    progressText = text
                else
                    -- Check for percentage format
                    local progress = tonumber(strmatch(text, "([%d%.]+)%%"))
                    if progress and progress <= 100 then
                        objectiveCount = ceil(100 - progress)
                        progressText = text
                    end
                end
                
                -- Check if this quest has item objectives (for icon type)
                for objIdx = 1, 10 do
                    local objText, objType, objFinished = GetQuestObjectiveInfo(questID, objIdx, false)
                    if not objText then break end
                    if not objFinished and (objType == "item" or objType == "object") then
                        hasItemObjective = true
                        break
                    end
                end
            end
        end
    end
    
    if progressText then
        return progressText, hasItemObjective and "item" or "monster", objectiveCount, questID
    end
    
    -- If we got here, the unit IS quest-related but we couldn't parse tooltip
    -- Return minimal data
    return "Quest Objective", "monster", 0, questID
end

----------------------------------------------
-- Helper: Create overlay frame for nameplate
----------------------------------------------
local function CreateNameplateOverlay(nameplate)
    local frame = CreateFrame("Frame", nil, nameplate)
    frame:SetSize(24, 24)
    
    -- Anchor to nameplate frame
    local anchorFrame = nameplate.UnitFrame or nameplate
    
    -- Position to the left of the nameplate (offset to center the visual)
    frame:SetPoint("RIGHT", anchorFrame, "LEFT", 2, -2)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(10)
    
    -- Modern button background (Dragonflight style)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetSize(24, 24)
    frame.bg:SetPoint("CENTER")
    frame.bg:SetAtlas("common-button-square-gray-down")
    frame.bg:SetVertexColor(1, 0.85, 0.3, 1) -- Gold tint
    
    -- Progress count text (centered on the atlas visual)
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    frame.text:SetPoint("CENTER", 0, 0)
    frame.text:SetTextColor(1, 0.82, 0) -- WoW quest yellow
    frame.text:SetShadowOffset(1, -1)
    frame.text:SetShadowColor(0, 0, 0, 1)
    
    -- Kill indicator icon (sword, shown for kill objectives)
    frame.killIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.killIcon:SetSize(14, 14)
    frame.killIcon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    frame.killIcon:SetTexture("Interface\\CURSOR\\Attack")
    frame.killIcon:SetTexCoord(1, 0, 0, 1) -- Flip horizontally
    frame.killIcon:Hide()
    
    -- Loot indicator icon (bag, shown for item objectives)
    frame.lootIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.lootIcon:SetSize(12, 12)
    frame.lootIcon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    frame.lootIcon:SetAtlas("Banker")
    frame.lootIcon:Hide()
    
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
-- Update nameplate overlay
----------------------------------------------
local function UpdateNameplate(unitId)
    if not isEnabled then return end
    
    local nameplate = C_NamePlate_GetNamePlateForUnit(unitId)
    if not nameplate then return end
    
    local overlay = GetNameplateOverlay(nameplate)
    
    -- Skip dead units
    if UnitIsDead(unitId) then
        overlay:Hide()
        return
    end
    
    -- Get quest progress using the proper API
    local progressText, objectiveType, objectiveCount, questID = GetQuestProgress(unitId)
    
    -- If no quest progress, hide overlay
    if not progressText then
        overlay:Hide()
        return
    end
    
    -- Determine if this is an item/loot objective
    local isItemObjective = (objectiveType == "item" or objectiveType == "object")
    
    -- Check settings
    if isItemObjective and not cachedShowLootIcon then
        overlay:Hide()
        return
    elseif not isItemObjective and not cachedShowKillIcon then
        overlay:Hide()
        return
    end
    
    -- Show appropriate indicator icon
    if isItemObjective then
        overlay.lootIcon:Show()
        overlay.killIcon:Hide()
    else
        overlay.killIcon:Show()
        overlay.lootIcon:Hide()
    end
    
    -- Set progress count text
    if objectiveCount > 0 then
        overlay.text:SetText(objectiveCount)
    else
        overlay.text:SetText("!")
    end
    
    overlay:Show()
end

----------------------------------------------
-- Clear nameplate overlay
----------------------------------------------
local function ClearNameplate(unitId)
    local nameplate = C_NamePlate_GetNamePlateForUnit(unitId)
    if nameplate and nameplateFrames[nameplate] then
        nameplateFrames[nameplate]:Hide()
    end
end

----------------------------------------------
-- Update all visible nameplates (with throttling)
----------------------------------------------
local pendingNameplateUpdate = false
local lastNameplateUpdate = 0
local NAMEPLATE_UPDATE_THROTTLE = 0.2

local function UpdateAllNameplates()
    if not isEnabled then return end
    
    local nameplates = C_NamePlate_GetNamePlates()
    if nameplates then
        for _, nameplate in ipairs(nameplates) do
            local unitId = nameplate.namePlateUnitToken
            if unitId then
                UpdateNameplate(unitId)
            end
        end
    end
end

local function ScheduleNameplateUpdate()
    if pendingNameplateUpdate then return end
    
    local now = GetTime()
    local timeSince = now - lastNameplateUpdate
    
    if timeSince < NAMEPLATE_UPDATE_THROTTLE then
        pendingNameplateUpdate = true
        C_Timer.After(NAMEPLATE_UPDATE_THROTTLE - timeSince + 0.05, function()
            pendingNameplateUpdate = false
            lastNameplateUpdate = GetTime()
            UpdateAllNameplates()
        end)
    else
        lastNameplateUpdate = now
        C_Timer.After(0.1, UpdateAllNameplates)
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
        -- Quest data changed, update all nameplates (throttled)
        ScheduleNameplateUpdate()
        
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        -- Specific quest progress changed (throttled)
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
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("QUEST_POI_UPDATE")
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    
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
