-- Refactor Addon - Auto-Quest Module
-- Automatically accepts and turns in quests, with smart dialogue automation

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- NPC Blacklist (Creature IDs)
-- These NPCs should never have dialogue auto-selected
----------------------------------------------
local NPC_BLACKLIST = {
    -- Class Trainers (generic - will add specifics if needed)
    -- Talent/Spec NPCs
    -- Transmogrifiers
    [64515] = true,  -- Warpweaver Hashom (Transmog, Shrine)
    [93529] = true,  -- Warpweaver Dushar (Transmog, Horde Warspear)
    [93528] = true,  -- Warpweaver Fareeya (Transmog, Alliance Stormshield)
    
    -- Barbers
    [143926] = true, -- Barber (Generic)
    
    -- Void Storage
    [64517] = true,  -- Vaultkeeper Razhid (Horde)
    [64518] = true,  -- Vaultkeeper Sharadris (Alliance)
    
    -- Important Story NPCs (Dragonflight)
    [189901] = true, -- Nozdormu (various interactions)
    [187678] = true, -- Alexstrasza
    
    -- Reputation Vendors (might have multiple purchase options)
    -- Flight Masters on first visit handled by option type check
}

----------------------------------------------
-- Gossip Option Types to Skip
-- These types should not be auto-selected even with single option
----------------------------------------------
local SKIP_OPTION_TYPES = {
    ["vendor"] = true,
    ["trainer"] = true,
    ["binder"] = true,       -- Innkeepers
    ["taxi"] = true,         -- Flight masters
    ["banker"] = true,
    ["transmogrify"] = true,
    ["void-storage"] = true,
}

----------------------------------------------
-- Continue/Proceed Text Patterns
-- Options matching these are "continue" type dialogue
----------------------------------------------
local CONTINUE_PATTERNS = {
    "continue",
    "go on",
    "tell me more",
    "proceed",
    "next",
    "what else",
    "i'm ready",
    "i am ready",
    "let's go",
    "let us go",
    "i understand",
    "understood",
    "very well",
    "indeed",
    "of course",
}

----------------------------------------------
-- Helper Functions
----------------------------------------------
local function ShouldProcess()
    if not isEnabled then return false end
    
    -- Check if modifier key is held to pause automation
    local modKey = addon.GetDBValue("AutoQuest_ModifierKey")
    if modKey and modKey ~= "NONE" and addon.IsModifierKeyDown(modKey) then
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
    local lowerText = optionText:lower()
    
    for _, pattern in ipairs(CONTINUE_PATTERNS) do
        if lowerText:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

local function ShouldSkipOptionType(optionType)
    return optionType and SKIP_OPTION_TYPES[optionType:lower()]
end

local function IsQuestRelatedOption(option)
    -- Check flags for quest-related indicators
    if option.flags then
        -- Flags can indicate quest-giver or quest-related content
        if bit.band(option.flags, 0x02) > 0 then -- Quest flag
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
    
    -- Filter out options we shouldn't auto-select
    local validOptions = {}
    local continueOptions = {}
    local questOptions = {}
    
    for _, option in ipairs(options) do
        local optionType = option.type or ""
        
        -- Skip trainer/vendor/etc types
        if not ShouldSkipOptionType(optionType) then
            -- Categorize the option
            if IsQuestRelatedOption(option) then
                table.insert(questOptions, option)
            elseif IsContinueOption(option.name) then
                table.insert(continueOptions, option)
            else
                table.insert(validOptions, option)
            end
        end
    end
    
    -- Priority 1: Quest-related options
    if #questOptions > 0 then
        C_GossipInfo.SelectOption(questOptions[1].gossipOptionID)
        return true
    end
    
    -- Priority 2: Continue dialogue options
    if addon.GetDBBool("AutoQuest_ContinueDialogue") and #continueOptions > 0 then
        C_GossipInfo.SelectOption(continueOptions[1].gossipOptionID)
        return true
    end
    
    -- Priority 3: Single valid option remaining
    if addon.GetDBBool("AutoQuest_SingleOption") and #validOptions == 1 then
        -- Double-check it's not a risky option
        local option = validOptions[1]
        if not ShouldSkipOptionType(option.type) then
            C_GossipInfo.SelectOption(option.gossipOptionID)
            return true
        end
    end
    
    -- Priority 4: Only one option total and it's safe
    if addon.GetDBBool("AutoQuest_SingleOption") and #options == 1 then
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
    if not ShouldProcess() then return end
    if not addon.GetDBBool("AutoQuest_Accept") then return end
    
    -- Delay slightly to ensure frame is ready
    C_Timer.After(0.1, function()
        if QuestFrame and QuestFrame:IsShown() then
            AcceptQuest()
        end
    end)
end

----------------------------------------------
-- Quest Progress (Quest Requirements Check)
----------------------------------------------
local function OnQuestProgress()
    if not ShouldProcess() then return end
    if not addon.GetDBBool("AutoQuest_TurnIn") then return end
    
    -- Check if we can complete the quest (all objectives done)
    C_Timer.After(0.1, function()
        if IsQuestCompletable() then
            CompleteQuest()
        end
    end)
end

----------------------------------------------
-- Quest Complete (Turn-in with Rewards)
----------------------------------------------
local function OnQuestComplete()
    if not ShouldProcess() then return end
    if not addon.GetDBBool("AutoQuest_TurnIn") then return end
    
    -- Check number of reward choices
    local numChoices = GetNumQuestChoices()
    
    C_Timer.After(0.1, function()
        if numChoices <= 1 then
            -- No choice or only one - auto select
            GetQuestReward(numChoices)
        end
        -- If multiple choices, let player choose
    end)
end

----------------------------------------------
-- Gossip Frame (Quest Giver Dialogue)
----------------------------------------------
local function OnGossipShow()
    if not ShouldProcess() then return end
    if not addon.GetDBBool("AutoQuest_SkipGossip") then return end
    
    C_Timer.After(0.1, function()
        -- First, check for quest-related actions (highest priority)
        local availableQuests = C_GossipInfo.GetAvailableQuests()
        local activeQuests = C_GossipInfo.GetActiveQuests()
        
        -- Priority 1: Turn in completed quests
        if #activeQuests > 0 and addon.GetDBBool("AutoQuest_TurnIn") then
            for _, quest in ipairs(activeQuests) do
                if quest.isComplete then
                    C_GossipInfo.SelectActiveQuest(quest.questID)
                    return
                end
            end
        end
        
        -- Priority 2: Accept available quests
        if #availableQuests > 0 and addon.GetDBBool("AutoQuest_Accept") then
            C_GossipInfo.SelectAvailableQuest(availableQuests[1].questID)
            return
        end
        
        -- Priority 3: Process gossip options (single option, continue, etc.)
        if ProcessGossipOptions() then
            return
        end
    end)
end

----------------------------------------------
-- Quest Greeting (Multiple Quests from NPC)
----------------------------------------------
local function OnQuestGreeting()
    if not ShouldProcess() then return end
    
    C_Timer.After(0.1, function()
        -- Check for quests to turn in
        if addon.GetDBBool("AutoQuest_TurnIn") then
            local numActiveQuests = GetNumActiveQuests()
            for i = 1, numActiveQuests do
                local title, isComplete = GetActiveTitle(i)
                if isComplete then
                    SelectActiveQuest(i)
                    return
                end
            end
        end
        
        -- Check for quests to accept
        if addon.GetDBBool("AutoQuest_Accept") then
            local numAvailableQuests = GetNumAvailableQuests()
            if numAvailableQuests > 0 then
                SelectAvailableQuest(1)
                return
            end
        end
    end)
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
    eventFrame:RegisterEvent("QUEST_DETAIL")
    eventFrame:RegisterEvent("QUEST_PROGRESS")
    eventFrame:RegisterEvent("QUEST_COMPLETE")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("QUEST_GREETING")
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("QUEST_DETAIL")
    eventFrame:UnregisterEvent("QUEST_PROGRESS")
    eventFrame:UnregisterEvent("QUEST_COMPLETE")
    eventFrame:UnregisterEvent("GOSSIP_SHOW")
    eventFrame:UnregisterEvent("QUEST_GREETING")
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    -- Initial state
    if addon.GetDBBool("AutoQuest") then
        self:Enable()
    end
    
    -- Listen for setting changes
    addon.CallbackRegistry:Register("SettingChanged.AutoQuest", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("AutoQuest", Module)
