-- Refactor Addon - Auto-Quest Module
-- Automatically accepts and turns in quests, skipping dialogue

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

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
        -- Check for available quests from NPC
        local availableQuests = C_GossipInfo.GetAvailableQuests()
        local activeQuests = C_GossipInfo.GetActiveQuests()
        
        -- Turn in first completable quest
        if #activeQuests > 0 and addon.GetDBBool("AutoQuest_TurnIn") then
            for _, quest in ipairs(activeQuests) do
                if quest.isComplete then
                    C_GossipInfo.SelectActiveQuest(quest.questID)
                    return
                end
            end
        end
        
        -- Accept first available quest
        if #availableQuests > 0 and addon.GetDBBool("AutoQuest_Accept") then
            C_GossipInfo.SelectAvailableQuest(availableQuests[1].questID)
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
    addon.Print("Auto-Quest enabled (hold Shift to pause)")
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
