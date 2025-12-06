-- Refactor Addon - Auto-Quest Module
-- Automatically accepts and turns in quests, with smart dialogue automation

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local tonumber = tonumber
local strsplit = strsplit
local bit_band = bit.band
local table_insert = table.insert
local string_lower = string.lower
local string_find = string.find

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Cached Settings (updated on change)
----------------------------------------------
local cachedModifierKey = "SHIFT"
local cachedAccept = true
local cachedTurnIn = true
local cachedSkipGossip = true
local cachedSingleOption = true
local cachedContinueDialogue = true

local function UpdateCachedSettings()
    cachedModifierKey = addon.GetDBValue("AutoQuest_ModifierKey") or "SHIFT"
    cachedAccept = addon.GetDBBool("AutoQuest_Accept")
    cachedTurnIn = addon.GetDBBool("AutoQuest_TurnIn")
    cachedSkipGossip = addon.GetDBBool("AutoQuest_SkipGossip")
    cachedSingleOption = addon.GetDBBool("AutoQuest_SingleOption")
    cachedContinueDialogue = addon.GetDBBool("AutoQuest_ContinueDialogue")
end

----------------------------------------------
-- NPC Blacklist (Creature IDs)
----------------------------------------------
local NPC_BLACKLIST = {
    [64515] = true,  -- Warpweaver Hashom (Transmog)
    [93529] = true,  -- Warpweaver Dushar (Transmog)
    [93528] = true,  -- Warpweaver Fareeya (Transmog)
    [143926] = true, -- Barber
    [64517] = true,  -- Vaultkeeper Razhid (Void Storage)
    [64518] = true,  -- Vaultkeeper Sharadris (Void Storage)
    [189901] = true, -- Nozdormu
    [187678] = true, -- Alexstrasza
}

----------------------------------------------
-- Gossip Option Types to Skip
----------------------------------------------
local SKIP_OPTION_TYPES = {
    vendor = true,
    trainer = true,
    binder = true,
    taxi = true,
    banker = true,
    transmogrify = true,
    ["void-storage"] = true,
}

----------------------------------------------
-- Continue/Proceed Text Patterns
----------------------------------------------
local CONTINUE_PATTERNS = {
    "continue", "go on", "tell me more", "proceed", "next",
    "what else", "i'm ready", "i am ready", "let's go",
    "let us go", "i understand", "understood", "very well",
    "indeed", "of course",
}

----------------------------------------------
-- Helper Functions
----------------------------------------------
local function ShouldProcess()
    if not isEnabled then return false end
    
    -- Use cached modifier key
    if cachedModifierKey and cachedModifierKey ~= "NONE" and addon.IsModifierKeyDown(cachedModifierKey) then
        return false
    end
    
    return true
end

local function GetNPCCreatureID()
    local guid = UnitGUID("npc")
    if not guid then return nil end
    
    local _, _, _, _, _, creatureID = strsplit("-", guid)
    return tonumber(creatureID)
end

local function IsBlacklistedNPC()
    local creatureID = GetNPCCreatureID()
    return creatureID and NPC_BLACKLIST[creatureID]
end

local function IsContinueOption(optionText)
    if not optionText then return false end
    local lowerText = string_lower(optionText)
    
    for i = 1, #CONTINUE_PATTERNS do
        if string_find(lowerText, CONTINUE_PATTERNS[i], 1, true) then
            return true
        end
    end
    return false
end

local function ShouldSkipOptionType(optionType)
    return optionType and SKIP_OPTION_TYPES[string_lower(optionType)]
end

local function IsQuestRelatedOption(option)
    if option.flags then
        if bit_band(option.flags, 0x02) > 0 then
            return true
        end
    end
    return false
end

----------------------------------------------
-- Smart Gossip Selection
----------------------------------------------
local function ProcessGossipOptions()
    if IsBlacklistedNPC() then return false end
    
    local options = C_GossipInfo.GetOptions()
    if not options or #options == 0 then return false end
    
    local validOptions = {}
    local continueOptions = {}
    local questOptions = {}
    
    for i = 1, #options do
        local option = options[i]
        local optionType = option.type or ""
        
        if not ShouldSkipOptionType(optionType) then
            if IsQuestRelatedOption(option) then
                table_insert(questOptions, option)
            elseif IsContinueOption(option.name) then
                table_insert(continueOptions, option)
            else
                table_insert(validOptions, option)
            end
        end
    end
    
    -- Priority 1: Quest-related options
    if #questOptions > 0 then
        C_GossipInfo.SelectOption(questOptions[1].gossipOptionID)
        return true
    end
    
    -- Priority 2: Continue dialogue (use cached setting)
    if cachedContinueDialogue and #continueOptions > 0 then
        C_GossipInfo.SelectOption(continueOptions[1].gossipOptionID)
        return true
    end
    
    -- Priority 3: Single valid option (use cached setting)
    -- No need to re-check ShouldSkipOptionType - validOptions already filtered
    if cachedSingleOption and #validOptions == 1 then
        C_GossipInfo.SelectOption(validOptions[1].gossipOptionID)
        return true
    end
    
    -- Priority 4: Only one option total
    if cachedSingleOption and #options == 1 then
        local option = options[1]
        if not ShouldSkipOptionType(option.type) then
            C_GossipInfo.SelectOption(option.gossipOptionID)
            return true
        end
    end
    
    return false
end
----------------------------------------------
-- Quest Detail (Accept Quest)
----------------------------------------------
local function OnQuestDetail()
    if not ShouldProcess() or not cachedAccept then return end
    
    -- Skip if Blizzard's auto-accept is already handling this quest
    if QuestGetAutoAccept() then return end
    
    -- Accept immediately - no delay needed
    AcceptQuest()
end

----------------------------------------------
-- Quest Progress
----------------------------------------------
local function OnQuestProgress()
    if not ShouldProcess() or not cachedTurnIn then return end
    
    -- Complete immediately if quest is ready
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

----------------------------------------------
-- Quest Complete
----------------------------------------------
local function OnQuestComplete()
    if not ShouldProcess() or not cachedTurnIn then return end
    
    local numChoices = GetNumQuestChoices()
    
    -- Turn in immediately if no reward choice needed
    if numChoices <= 1 then
        GetQuestReward(numChoices)
    end
end

----------------------------------------------
-- Gossip Frame
----------------------------------------------
local function OnGossipShow()
    if not ShouldProcess() or not cachedSkipGossip then return end
    
    local availableQuests = C_GossipInfo.GetAvailableQuests()
    local activeQuests = C_GossipInfo.GetActiveQuests()
    
    -- Priority 1: Turn in completed quests
    if cachedTurnIn then
        for i = 1, #activeQuests do
            local quest = activeQuests[i]
            if quest.isComplete then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                return
            end
        end
    end
    
    -- Priority 2: Accept available quests
    if cachedAccept and #availableQuests > 0 then
        C_GossipInfo.SelectAvailableQuest(availableQuests[1].questID)
        return
    end
    
    -- Priority 3: Process gossip options
    ProcessGossipOptions()
end

----------------------------------------------
-- Quest Greeting
----------------------------------------------
local function OnQuestGreeting()
    if not ShouldProcess() then return end
    
    -- Priority 1: Turn in completed quests
    if cachedTurnIn then
        local numActiveQuests = GetNumActiveQuests()
        for i = 1, numActiveQuests do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end
    
    -- Priority 2: Accept available quests
    if cachedAccept then
        local numAvailableQuests = GetNumAvailableQuests()
        if numAvailableQuests > 0 then
            SelectAvailableQuest(1)
        end
    end
end

----------------------------------------------
-- Event Frame
----------------------------------------------
local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "QUEST_DETAIL" then
        OnQuestDetail()
    elseif event == "QUEST_PROGRESS" then
        OnQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        OnQuestComplete()
    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "QUEST_GREETING" then
        OnQuestGreeting()
    end
end)

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    UpdateCachedSettings()
    eventFrame:RegisterEvent("QUEST_DETAIL")
    eventFrame:RegisterEvent("QUEST_PROGRESS")
    eventFrame:RegisterEvent("QUEST_COMPLETE")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("QUEST_GREETING")
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterAllEvents()
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    UpdateCachedSettings()
    
    if addon.GetDBBool("AutoQuest") then
        self:Enable()
    end
    
    -- Listen for setting changes
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest", function(value)
        if value then Module:Enable() else Module:Disable() end
    end)
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest_ModifierKey", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest_Accept", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest_TurnIn", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest_SkipGossip", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest_SingleOption", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest_ContinueDialogue", UpdateCachedSettings)
end

addon.RegisterModule("AutoQuest", Module)
