-- Refactor Addon - Auto-Sell Junk Module (Smart Vendor)
-- Automatically sells grey items and optionally low iLvl/known transmogs

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false
local isSelling = false

----------------------------------------------
-- Helper: Check if item is soulbound equipment
----------------------------------------------
local function IsEquipment(itemID)
    local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
    -- Armor (4) or Weapon (2)
    return classID == 2 or classID == 4
end

----------------------------------------------
-- Helper: Check if transmog is already known
----------------------------------------------
local function IsTransmogKnown(itemLink)
    if not C_TransmogCollection then return false end
    
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return false end
    
    -- Get appearance ID for this item
    local appearanceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not appearanceID then return false end
    
    -- Check if we have this appearance from ANY source
    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
    if sources then
        for _, source in ipairs(sources) do
            if source.isCollected then
                return true
            end
        end
    end
    
    return false
end

----------------------------------------------
-- Helper: Get lowest equipped item level
----------------------------------------------
local equipSlots = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot"
}

local function GetLowestEquippedILvl()
    local lowestILvl = 9999
    
    for _, slotName in ipairs(equipSlots) do
        local slotID = GetInventorySlotInfo(slotName)
        local itemLink = GetInventoryItemLink("player", slotID)
        if itemLink then
            local _, _, _, itemLevel = GetItemInfo(itemLink)
            if itemLevel and itemLevel > 0 and itemLevel < lowestILvl then
                lowestILvl = itemLevel
            end
        end
    end
    
    return lowestILvl < 9999 and lowestILvl or 0
end

----------------------------------------------
-- Helper: Check if item is truly soulbound
----------------------------------------------
local function IsSoulbound(bag, slot)
    -- Use the proper C_Item API for reliable bound status
    local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if itemLocation and itemLocation:IsValid() then
        -- C_Item.IsBound returns true only for soulbound items
        local isBound = C_Item.IsBound(itemLocation)
        return isBound == true
    end
    return false
end

----------------------------------------------
-- Helper: Should sell this item?
----------------------------------------------
local function ShouldSellItem(bag, slot, itemInfo)
    local itemID = itemInfo.itemID
    local itemQuality = itemInfo.quality
    local stackCount = itemInfo.stackCount
    
    -- Grey items handling
    if itemQuality == Enum.ItemQuality.Poor then
        -- Grey EQUIPMENT can have transmog value - check if it's equipment
        if IsEquipment(itemID) then
            -- Only sell grey equipment if it's soulbound (can't be sold on AH anyway)
            local isBound = IsSoulbound(bag, slot)
            if isBound then
                return true, "junk"
            else
                -- Grey BoE equipment - keep for AH/transmog
                return false
            end
        else
            -- Grey non-equipment (vendor trash like "Broken Blade", food, etc.) - always sell
            return true, "junk"
        end
    end
    
    -- NEVER sell heirlooms - they're valuable even if "bound"
    if itemQuality == Enum.ItemQuality.Heirloom then
        return false
    end
    
    -- Use reliable soulbound check (NOT itemInfo.isBound which can be unreliable)
    local isBound = IsSoulbound(bag, slot)
    
    -- NEVER sell BoE items (not yet bound) - they may have AH value
    if not isBound then
        return false
    end
    
    -- From here on, we only deal with SOULBOUND equipment
    if not IsEquipment(itemID) then
        return false
    end
    
    local _, _, _, itemLevel = GetItemInfo(itemID)
    if not itemLevel then return false end
    
    -- Check for low item level selling (soulbound only)
    if addon.GetDBBool("AutoSellJunk_SellLowILvl") then
        local maxILvl = addon.GetDBValue("AutoSellJunk_MaxILvl") or 400
        
        -- Safety: Never sell items at or above the max threshold
        if itemLevel >= maxILvl then
            return false
        end
        
        -- Safety: Never sell items that could be an upgrade (equal or higher than lowest equipped)
        local lowestEquipped = GetLowestEquippedILvl()
        if lowestEquipped > 0 and itemLevel >= lowestEquipped then
            return false
        end
        
        -- Item is below max threshold and below our lowest equipped - safe to consider
        -- Check if we should keep for transmog
        if addon.GetDBBool("AutoSellJunk_KeepTransmog") then
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            if itemLink and not IsTransmogKnown(itemLink) then
                return false, "transmog_needed"
            end
        end
        
        return true, "low_ilvl"
    end
    
    -- Check for already-known transmog selling (soulbound only)
    if addon.GetDBBool("AutoSellJunk_SellKnownTransmog") then
        local maxILvl = addon.GetDBValue("AutoSellJunk_MaxILvl") or 400
        
        -- Safety: Still respect the max iLvl limit for transmog selling
        if itemLevel >= maxILvl then
            return false
        end
        
        local itemLink = C_Container.GetContainerItemLink(bag, slot)
        
        if itemLink then
            if itemQuality and itemQuality >= Enum.ItemQuality.Common then
                if IsTransmogKnown(itemLink) then
                    return true, "known_transmog"
                end
            end
        end
    end
    
    return false
end

----------------------------------------------
-- Sell Items Implementation
----------------------------------------------
function Module:SellJunk()
    if isSelling then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    
    isSelling = true
    
    local totalPrice = 0
    local junkCount = 0
    local ilvlCount = 0
    local transmogCount = 0
    
    -- Iterate through all bags
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo and itemInfo.itemID then
                local shouldSell, reason = ShouldSellItem(bag, slot, itemInfo)
                
                if shouldSell then
                    local itemName, itemLink, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemInfo.itemID)
                    if sellPrice and sellPrice > 0 then
                        totalPrice = totalPrice + (sellPrice * itemInfo.stackCount)
                        
                        if reason == "junk" then
                            junkCount = junkCount + 1
                        elseif reason == "low_ilvl" then
                            ilvlCount = ilvlCount + 1
                        elseif reason == "known_transmog" then
                            transmogCount = transmogCount + 1
                        end
                        
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
            end
        end
    end
    
    -- Show notification
    local totalCount = junkCount + ilvlCount + transmogCount
    if totalCount > 0 and addon.GetDBBool("AutoSellJunk_ShowNotify") then
        local msg = L.SOLD_JUNK:format(totalCount, addon.FormatMoney(totalPrice))
        
        -- Add breakdown if selling more than just junk
        local details = {}
        if junkCount > 0 then table.insert(details, junkCount .. " junk") end
        if ilvlCount > 0 then table.insert(details, ilvlCount .. " low iLvl") end
        if transmogCount > 0 then table.insert(details, transmogCount .. " known transmog") end
        
        if #details > 1 then
            msg = msg .. " (" .. table.concat(details, ", ") .. ")"
        end
        
        addon.Print(msg)
    end
    
    isSelling = false
end

----------------------------------------------
-- Event Handlers
----------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnMerchantShow()
    if not isEnabled then return end
    
    -- Small delay to ensure merchant frame is ready
    C_Timer.After(0.1, function()
        Module:SellJunk()
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
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("MERCHANT_SHOW")
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    if addon.GetDBBool("AutoSellJunk") then
        self:Enable()
    end
    
    addon.CallbackRegistry:Register("SettingChanged.AutoSellJunk", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("AutoSellJunk", Module)

