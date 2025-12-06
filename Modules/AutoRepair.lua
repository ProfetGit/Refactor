-- Refactor Addon - Auto-Repair Module
-- Automatically repairs gear when opening a repair vendor

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Repair Implementation
----------------------------------------------
function Module:Repair()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if not CanMerchantRepair() then return end
    
    local repairCost, canRepair = GetRepairAllCost()
    
    if not canRepair or repairCost == 0 then
        return -- Nothing to repair
    end
    
    local useGuildFunds = addon.GetDBBool("AutoRepair_UseGuild")
    local repaired = false
    local usedGuild = false
    
    -- Try guild funds first if enabled
    if useGuildFunds and IsInGuild() then
        local canUseGuildRepair = CanGuildBankRepair()
        if canUseGuildRepair then
            local guildBankMoney = GetGuildBankWithdrawMoney()
            -- guildBankMoney returns -1 if unlimited
            if guildBankMoney == -1 or guildBankMoney >= repairCost then
                RepairAllItems(true) -- true = use guild bank
                repaired = true
                usedGuild = true
            end
        end
    end
    
    -- Fall back to personal funds
    if not repaired then
        local playerMoney = GetMoney()
        if playerMoney >= repairCost then
            RepairAllItems(false) -- false = use personal funds
            repaired = true
        else
            addon.PrintIfEnabled("AutoRepair_ShowNotify",
                L.REPAIR_FAILED:format(addon.FormatMoney(repairCost)))
            return
        end
    end
    
    -- Show notification
    if repaired then
        if usedGuild then
            addon.PrintIfEnabled("AutoRepair_ShowNotify",
                L.REPAIRED_GUILD:format(addon.FormatMoney(repairCost)))
        else
            addon.PrintIfEnabled("AutoRepair_ShowNotify",
                L.REPAIRED_SELF:format(addon.FormatMoney(repairCost)))
        end
    end
end

----------------------------------------------
-- Event Handlers
----------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnMerchantShow()
    if not isEnabled then return end
    
    -- Small delay to ensure merchant frame is ready and after junk selling
    C_Timer.After(0.3, function()
        Module:Repair()
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        OnMerchantShow()
    end
end)

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    addon.Print("Auto-Repair enabled")
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("MERCHANT_SHOW")
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    -- Initial state
    if addon.GetDBBool("AutoRepair") then
        self:Enable()
    end
    
    -- Listen for setting changes
    addon.CallbackRegistry:Register("SettingChanged.AutoRepair", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("AutoRepair", Module)
