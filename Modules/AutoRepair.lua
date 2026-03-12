-- Refactor Addon - Auto-Repair Module
-- Automatically repairs gear when opening a repair vendor

local addonName, addon = ...
local L = addon.L
local Utils = addon.Utils

local Module = addon:NewModule("AutoRepair", {
    settingKey = "AutoRepair"
})

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
                L.REPAIR_FAILED:format(Utils.FormatMoney(repairCost)))
            return
        end
    end

    -- Show notification
    if repaired then
        if usedGuild then
            addon.PrintIfEnabled("AutoRepair_ShowNotify",
                L.REPAIRED_GUILD:format(Utils.FormatMoney(repairCost)))
        else
            addon.PrintIfEnabled("AutoRepair_ShowNotify",
                L.REPAIRED_SELF:format(Utils.FormatMoney(repairCost)))
        end
    end
end

local function OnMerchantShow()
    -- Small delay to ensure merchant frame is ready and after junk selling
    C_Timer.After(0.3, function()
        Module:Repair()
    end)
end

Module.eventMap = {
    ["MERCHANT_SHOW"] = function() OnMerchantShow() end
}
