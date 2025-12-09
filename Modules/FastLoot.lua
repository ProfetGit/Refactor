-- Refactor Addon - Fast Loot Module
-- Instantly loots all items without showing the loot window

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Fast Loot Implementation
----------------------------------------------
local function OnLootReady(autoLoot)
    if not isEnabled then return end

    -- Get number of loot slots
    local numLootItems = GetNumLootItems()

    if numLootItems > 0 then
        -- Loot all items as fast as possible
        for i = numLootItems, 1, -1 do
            LootSlot(i)
        end
    end

    -- Close the loot window immediately if it's open
    if LootFrame and LootFrame:IsShown() then
        CloseLoot()
    end
end

----------------------------------------------
-- Event Frame
----------------------------------------------
local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LOOT_READY" then
        local autoLoot = ...
        OnLootReady(autoLoot)
    elseif event == "LOOT_OPENED" then
        -- Backup: also try to fast-loot when loot window opens
        if isEnabled then
            C_Timer.After(0, function()
                local numLootItems = GetNumLootItems()
                for i = numLootItems, 1, -1 do
                    LootSlot(i)
                end
            end)
        end
    end
end)

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    eventFrame:RegisterEvent("LOOT_READY")
    eventFrame:RegisterEvent("LOOT_OPENED")

    -- Also enable the built-in auto-loot for best results
    SetCVar("autoLootDefault", 1)
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("LOOT_READY")
    eventFrame:UnregisterEvent("LOOT_OPENED")
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    -- Initial state
    if addon.GetDBBool("FastLoot") then
        self:Enable()
    end

    -- Listen for setting changes
    addon.CallbackRegistry:Register("SettingChanged.FastLoot", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("FastLoot", Module)
