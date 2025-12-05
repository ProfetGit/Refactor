-- Refactor Addon - Auto-Confirm Module
-- Automatically confirms common dialogs

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Static Popup Handling
----------------------------------------------
local confirmablePopups = {
    -- Ready check
    "READY_CHECK",
    -- Summoning
    "CONFIRM_SUMMON",
    -- Role check
    "LFG_ROLE_CHECK_POPUP",
    -- Dungeon/LFR
    "LFG_PROPOSAL_POPUP", -- This needs special handling
    -- Resurrect
    "RESURRECT_NO_TIMER",
    "RESURRECT",
    -- Loot rolls
    "CONFIRM_LOOT_ROLL",
    -- Teleports
    "CONFIRM_LEAVE_BATTLEFIELD",
    -- Item binding
    "LOOT_BIND",
    "EQUIP_BIND",
    "USE_BIND",
    -- Item deletion (handled separately with quality check)
}

local function ShouldConfirmPopup(which)
    if not isEnabled then return false end
    
    -- Ready check
    if which == "READY_CHECK" then
        return addon.GetDBBool("AutoConfirm_ReadyCheck")
    end
    
    -- Summon
    if which == "CONFIRM_SUMMON" then
        return addon.GetDBBool("AutoConfirm_Summon")
    end
    
    -- Role check
    if which == "LFG_ROLE_CHECK_POPUP" then
        return addon.GetDBBool("AutoConfirm_RoleCheck")
    end
    
    -- Resurrect
    if which == "RESURRECT" or which == "RESURRECT_NO_TIMER" then
        return addon.GetDBBool("AutoConfirm_Resurrect")
    end
    
    -- Binding confirmations
    if which == "LOOT_BIND" or which == "EQUIP_BIND" or which == "USE_BIND" then
        return addon.GetDBBool("AutoConfirm_Binding")
    end
    
    return false
end

----------------------------------------------
-- Hook Static Popups
----------------------------------------------
local function OnStaticPopupShow(dialog, which)
    if not isEnabled then return end
    if not which then return end
    
    if ShouldConfirmPopup(which) then
        -- Small delay to ensure popup is ready
        C_Timer.After(0.1, function()
            local popup = StaticPopup_FindVisible(which)
            if popup then
                -- Click the accept/yes button
                local button1 = popup.button1
                if button1 and button1:IsShown() and button1:IsEnabled() then
                    button1:Click()
                end
            end
        end)
    end
end

----------------------------------------------
-- Ready Check Handling
----------------------------------------------
local function OnReadyCheck()
    if not isEnabled then return end
    if not addon.GetDBBool("AutoConfirm_ReadyCheck") then return end
    
    C_Timer.After(0.1, function()
        if ReadyCheckFrame and ReadyCheckFrame:IsShown() then
            ConfirmReadyCheck(true)
            ReadyCheckFrame:Hide()
        end
    end)
end

----------------------------------------------
-- LFG Role Check
----------------------------------------------
local function OnLFGRoleCheck()
    if not isEnabled then return end
    if not addon.GetDBBool("AutoConfirm_RoleCheck") then return end
    
    C_Timer.After(0.2, function()
        if LFDRoleCheckPopup and LFDRoleCheckPopup:IsShown() then
            LFDRoleCheckPopupAcceptButton:Click()
        end
    end)
end

----------------------------------------------
-- Summon Confirm
----------------------------------------------
local function OnSummonConfirm()
    if not isEnabled then return end
    if not addon.GetDBBool("AutoConfirm_Summon") then return end
    
    C_Timer.After(0.1, function()
        C_SummonInfo.ConfirmSummon()
    end)
end

----------------------------------------------
-- Resurrection
----------------------------------------------
local function OnResurrect()
    if not isEnabled then return end
    if not addon.GetDBBool("AutoConfirm_Resurrect") then return end
    
    C_Timer.After(0.3, function()
        if StaticPopup_FindVisible("RESURRECT") then
            AcceptResurrect()
            StaticPopup_Hide("RESURRECT")
        elseif StaticPopup_FindVisible("RESURRECT_NO_TIMER") then
            AcceptResurrect()
            StaticPopup_Hide("RESURRECT_NO_TIMER")
        end
    end)
end

----------------------------------------------
-- Delete Item Confirmation (quality check)
----------------------------------------------
local function OnDeleteItem()
    if not isEnabled then return end
    if not addon.GetDBBool("AutoConfirm_DeleteGrey") then return end
    
    local popup = StaticPopup_FindVisible("DELETE_ITEM")
    if not popup then return end
    
    -- Check item quality from the cursor
    local cursorType, _, itemLink = GetCursorInfo()
    if cursorType == "item" and itemLink then
        local _, _, quality = GetItemInfo(itemLink)
        -- Only auto-confirm for Poor (0) and Common (1) quality
        if quality and quality <= 1 then
            C_Timer.After(0.1, function()
                local p = StaticPopup_FindVisible("DELETE_ITEM")
                if p and p.editBox then
                    p.editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
                    p.button1:Click()
                end
            end)
        end
    end
end

----------------------------------------------
-- Event Frame
----------------------------------------------
local eventFrame = CreateFrame("Frame")

local function RegisterEvents()
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
    eventFrame:RegisterEvent("CONFIRM_SUMMON")
    eventFrame:RegisterEvent("RESURRECT_REQUEST")
end

local function UnregisterEvents()
    eventFrame:UnregisterAllEvents()
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "READY_CHECK" then
        OnReadyCheck()
    elseif event == "LFG_ROLE_CHECK_SHOW" then
        OnLFGRoleCheck()
    elseif event == "CONFIRM_SUMMON" then
        OnSummonConfirm()
    elseif event == "RESURRECT_REQUEST" then
        OnResurrect()
    end
end)

----------------------------------------------
-- Hook StaticPopup
----------------------------------------------
local hookedPopups = false

local function HookPopups()
    if hookedPopups then return end
    hookedPopups = true
    
    hooksecurefunc("StaticPopup_Show", function(which)
        if which == "DELETE_ITEM" or which == "DELETE_GOOD_ITEM" then
            OnDeleteItem()
        else
            OnStaticPopupShow(nil, which)
        end
    end)
end

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    RegisterEvents()
    HookPopups()
end

function Module:Disable()
    isEnabled = false
    UnregisterEvents()
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    if addon.GetDBBool("AutoConfirm") then
        self:Enable()
    end
    
    addon.CallbackRegistry:Register("SettingChanged.AutoConfirm", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("AutoConfirm", Module)
