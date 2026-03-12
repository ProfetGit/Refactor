-- Refactor Addon - Auto-Sell Junk Module (Smart Vendor)
-- Automatically sells grey items and optionally low iLvl/known transmogs

local addonName, addon = ...
local L = addon.L
local Utils = addon.Utils

local Module = addon:NewModule("AutoSellJunk", {
    settingKey = "AutoSellJunk",
    eventMap = {
        ["MERCHANT_SHOW"] = function(self)
            -- Small delay to ensure merchant frame is ready
            C_Timer.After(0.1, function()
                self:SellJunk()
            end)
        end
    }
})

----------------------------------------------
-- Module State
----------------------------------------------
local isSelling = false
local sellQueue = {}
local sellTimer = nil

----------------------------------------------
-- Helper: Should sell this item?
----------------------------------------------
local function ShouldSellItem(bag, slot, itemInfo)
    -- Only sell grey ("Poor") items unconditionally
    if itemInfo.quality == Enum.ItemQuality.Poor then
        return true, "junk"
    end
    return false
end

----------------------------------------------
-- Queue Processor
----------------------------------------------
local function ProcessSellQueue()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        -- Vendor closed early
        Module:StopSelling()
        return
    end

    if #sellQueue == 0 then
        -- Finished
        Module:StopSelling()
        return
    end

    local item = table.remove(sellQueue, 1)
    
    -- Verify item is still there before selling
    local currentInfo = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if currentInfo and currentInfo.itemID == item.itemID then
        C_Container.UseContainerItem(item.bag, item.slot)
    end
end

----------------------------------------------
-- Sell Items Implementation
----------------------------------------------
function Module:StopSelling()
    if sellTimer then
        sellTimer:Cancel()
        sellTimer = nil
    end
    
    isSelling = false
    wipe(sellQueue)
end

function Module:SellJunk()
    if isSelling then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then return end

    isSelling = true
    wipe(sellQueue)

    -- Iterate through all bags and build queue
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo and itemInfo.itemID then
                local shouldSell, reason = ShouldSellItem(bag, slot, itemInfo)

                if shouldSell then
                    local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemInfo.itemID)
                    if sellPrice and sellPrice > 0 then
                        table.insert(sellQueue, {
                            bag = bag,
                            slot = slot,
                            itemID = itemInfo.itemID,
                            sellPrice = sellPrice,
                            stackCount = itemInfo.stackCount,
                            reason = reason
                        })
                    end
                end
            end
        end
    end

    -- Start queue processing if we have items
    if #sellQueue > 0 then
        -- 0.15s interval is the sweet spot for avoiding merchant throttling
        sellTimer = C_Timer.NewTicker(0.15, ProcessSellQueue)
    else
        isSelling = false
    end
end
