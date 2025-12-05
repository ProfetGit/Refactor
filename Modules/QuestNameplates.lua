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

----------------------------------------------
-- Quest Objective Cache
----------------------------------------------
local questObjectiveCache = {}
local cacheUpdateTime = 0
local CACHE_DURATION = 0.5 -- Refresh cache every 0.5 seconds

local function UpdateQuestObjectiveCache()
    local now = GetTime()
    if now - cacheUpdateTime < CACHE_DURATION then
        return questObjectiveCache
    end
    
    wipe(questObjectiveCache)
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
                        
                        -- Store objective info by text
                        questObjectiveCache[text] = {
                            questID = questID,
                            questTitle = questInfo.title,
                            numFulfilled = objective.numFulfilled or 0,
                            numRequired = objective.numRequired or 1,
                            objectiveType = objectiveType,
                            finished = objective.finished,
                            text = text,
                        }
                        
                        -- Try to extract creature/item names from objective text
                        -- Common formats: "Creature Name slain: 0/10" or "0/10 Item Name"
                        -- For item quests, extract the item name
                        if objectiveType == "item" then
                            -- Format is usually "0/8 Item Name" or "Item Name: 0/8"
                            local itemName = text:match("^%d+/%d+%s+(.+)$") or text:match("^(.+):%s*%d+/%d+$")
                            if itemName then
                                questObjectiveCache["ITEM:" .. itemName:lower()] = questObjectiveCache[text]
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
-- Helper: Check if unit is related to any quest
-- Uses multiple detection methods
----------------------------------------------
local function IsUnitQuestRelated(unitId)
    -- Method 1: Direct API check
    if UnitIsQuestBoss(unitId) then
        return true, "questboss"
    end
    
    -- Method 2: Check unit's quest icon via widget (if visible)
    local guid = UnitGUID(unitId)
    if guid then
        local mobId = select(6, strsplit("-", guid))
        if mobId and tonumber(mobId) then
            -- Some quest mobs have specific markers we can detect later
        end
    end
    
    -- Method 3: Check if unit has quest-related classification
    local classification = UnitClassification(unitId)
    -- questboss classification is a hint but not definitive
    
    return false, nil
end

----------------------------------------------
-- Helper: Find matching quest objective for a unit
-- More flexible matching for item-drop quests
----------------------------------------------
local function FindQuestObjective(unitName, unitId)
    if not unitName then return nil end
    
    local objectives = UpdateQuestObjectiveCache()
    local lowerName = unitName:lower()
    
    -- Method 1: Search for the unit name in objective text
    for text, objectiveData in pairs(objectives) do
        -- Skip the ITEM: prefixed entries for direct name matching
        if not text:match("^ITEM:") then
            local lowerText = text:lower()
            -- Check if the unit name appears in the objective text
            if lowerText:find(lowerName, 1, true) then
                return objectiveData
            end
        end
    end
    
    -- Method 2: Check if ANY word from mob name (4+ chars) appears in objective
    for word in lowerName:gmatch("%w+") do
        if #word >= 4 then
            for text, objectiveData in pairs(objectives) do
                if not text:match("^ITEM:") then
                    local lowerText = text:lower()
                    if lowerText:find(word, 1, true) then
                        return objectiveData
                    end
                end
            end
        end
    end
    
    -- Method 3: Check if ANY word from objective (4+ chars) appears in mob name
    for text, objectiveData in pairs(objectives) do
        if not text:match("^ITEM:") then
            local lowerText = text:lower()
            for word in lowerText:gmatch("%w+") do
                if #word >= 4 and lowerName:find(word, 1, true) then
                    return objectiveData
                end
            end
        end
    end
    
    return nil
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
    
    -- Check if this unit is quest-related using MULTIPLE methods:
    -- 1. UnitIsQuestBoss() API
    -- 2. Unit name matches quest objective text
    
    local isQuestMob = UnitIsQuestBoss(unitId)
    
    -- Try to find a matching objective by name
    local objectiveData = FindQuestObjective(unitName, unitId)
    
    -- FALLBACK: For item-drop quests where UnitIsQuestBoss doesn't work
    -- Check if this is an attackable enemy and we have any item objectives
    local itemFallback = nil
    if not isQuestMob and not objectiveData then
        -- Is this an attackable enemy?
        local isEnemy = UnitCanAttack("player", unitId) and not UnitIsDead(unitId)
        if isEnemy then
            local objectives = UpdateQuestObjectiveCache()
            local lowerName = unitName:lower()
            
            -- Find item objective where quest title matches mob name
            for text, data in pairs(objectives) do
                if not text:match("^ITEM:") and data.objectiveType == "item" and not data.finished then
                    -- Check if quest title has any word (4+ chars) matching mob name
                    if data.questTitle then
                        local lowerTitle = data.questTitle:lower()
                        for word in lowerTitle:gmatch("%w+") do
                            if #word >= 4 and lowerName:find(word, 1, true) then
                                itemFallback = data
                                break
                            end
                        end
                        if itemFallback then break end
                    end
                end
            end
            -- No fallback to random item quests - only show when title matches
        end
    end
    
    -- If no detection method works, hide
    if not isQuestMob and not objectiveData and not itemFallback then
        overlay:Hide()
        return
    end
    
    -- If UnitIsQuestBoss is true but no name match, try to find ANY item objective
    if not objectiveData and isQuestMob then
        local objectives = UpdateQuestObjectiveCache()
        for text, data in pairs(objectives) do
            if not text:match("^ITEM:") and data.objectiveType == "item" and not data.finished then
                objectiveData = data
                break
            end
        end
        -- Still no match? Try any incomplete objective
        if not objectiveData then
            for text, data in pairs(objectives) do
                if not text:match("^ITEM:") and not data.finished then
                    objectiveData = data
                    break
                end
            end
        end
    end
    
    -- Use itemFallback if we still don't have objective data
    if not objectiveData and itemFallback then
        objectiveData = itemFallback
    end
    
    local showKillIcon = addon.GetDBBool("QuestNameplates_ShowKillIcon")
    local showLootIcon = addon.GetDBBool("QuestNameplates_ShowLootIcon")
    
    if objectiveData then
        local objectiveType = objectiveData.objectiveType
        
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
    else
        -- Quest mob detected but couldn't find specific objective
        -- Show a generic indicator
        if showLootIcon then
            overlay.icon:SetTexture("Interface\\Minimap\\Tracking\\Banker")
            overlay.icon:SetVertexColor(1, 0.82, 0) -- Gold
            overlay.text:SetText("?")
            overlay:Show()
        elseif showKillIcon then
            overlay.icon:SetTexture("Interface\\CURSOR\\Attack")
            overlay.icon:SetVertexColor(1, 0.82, 0) -- Gold
            overlay.text:SetText("?")
            overlay:Show()
        else
            overlay:Hide()
        end
    end
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
        C_Timer.After(0.1, UpdateAllNameplates)
        
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        -- Specific quest progress changed
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
