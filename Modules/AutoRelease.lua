-- Refactor Addon - Auto-Release Module
-- Automatically releases spirit on death with context awareness

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Instance Type Detection
----------------------------------------------
local function GetInstanceContext()
    local inInstance, instanceType = IsInInstance()
    
    if not inInstance then
        -- Check for War Mode
        if C_PvP.IsWarModeDesired() then
            return "warmode"
        end
        return "openworld"
    end
    
    -- Instance types: "party", "raid", "pvp", "arena", "scenario"
    if instanceType == "pvp" or instanceType == "arena" then
        return "pvp"
    elseif instanceType == "party" or instanceType == "raid" then
        return "pve"
    elseif instanceType == "scenario" then
        return "pve"
    end
    
    return "openworld"
end

local function ShouldAutoRelease()
    if not isEnabled then return false end
    
    local mode = addon.GetDBValue("AutoRelease_Mode") or "PVP"
    local context = GetInstanceContext()
    
    if mode == "ALWAYS" then
        return true
    elseif mode == "PVP" then
        -- PvP instances OR War Mode in open world
        return context == "pvp" or context == "warmode"
    elseif mode == "PVE" then
        return context == "pve"
    elseif mode == "OPENWORLD" then
        return context == "openworld" or context == "warmode"
    end
    
    return false
end

----------------------------------------------
-- Death Handler
----------------------------------------------
local releaseTimer = nil

local function OnPlayerDead()
    if not isEnabled then return end
    if not ShouldAutoRelease() then return end
    
    -- Cancel any existing timer
    if releaseTimer then
        releaseTimer:Cancel()
        releaseTimer = nil
    end
    
    local delay = addon.GetDBValue("AutoRelease_Delay") or 0.5
    
    releaseTimer = C_Timer.NewTimer(delay, function()
        -- Double-check we're still dead and should release
        if UnitIsDeadOrGhost("player") and not UnitIsGhost("player") then
            if ShouldAutoRelease() then
                RepopMe()
                
                if addon.GetDBBool("AutoRelease_Notify") then
                    addon.Print("Auto-released spirit.")
                end
            end
        end
        releaseTimer = nil
    end)
end

----------------------------------------------
-- Cancel on Resurrect
----------------------------------------------
local function OnResurrect()
    -- Cancel auto-release if we're being resurrected
    if releaseTimer then
        releaseTimer:Cancel()
        releaseTimer = nil
    end
end

----------------------------------------------
-- Event Frame
----------------------------------------------
local eventFrame = CreateFrame("Frame")

local function RegisterEvents()
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("RESURRECT_REQUEST")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
end

local function UnregisterEvents()
    eventFrame:UnregisterAllEvents()
    if releaseTimer then
        releaseTimer:Cancel()
        releaseTimer = nil
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_DEAD" then
        OnPlayerDead()
    elseif event == "RESURRECT_REQUEST" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        OnResurrect()
    end
end)

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    RegisterEvents()
end

function Module:Disable()
    isEnabled = false
    UnregisterEvents()
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    if addon.GetDBBool("AutoRelease") then
        self:Enable()
    end
    
    addon.CallbackRegistry:Register("SettingChanged.AutoRelease", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("AutoRelease", Module)
