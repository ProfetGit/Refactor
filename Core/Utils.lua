-- Refactor Addon - Shared Utilities
-- Centralized helper functions used across multiple modules

local addonName, addon = ...
local Utils = {}
addon.Utils = Utils

----------------------------------------------
-- Item Logic Helpers
----------------------------------------------
function Utils.IsEquipment(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    -- Armor (4) or Weapon (2)
    return classID == 2 or classID == 4
end

function Utils.IsTransmogKnown(itemLink)
    if not C_TransmogCollection then return false end

    local itemID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID then return false end

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

function Utils.IsSoulbound(bag, slot)
    local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if itemLocation and itemLocation:IsValid() then
        return C_Item.IsBound(itemLocation) == true
    end
    return false
end

----------------------------------------------
-- Formatting Helpers
----------------------------------------------
function Utils.FormatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperLeft = copper % 100

    local str = ""
    if gold > 0 then
        str = str .. "|cffffd700" .. gold .. "g|r "
    end
    if silver > 0 or gold > 0 then
        str = str .. "|cffc7c7cf" .. silver .. "s|r "
    end
    str = str .. "|cffeda55f" .. copperLeft .. "c|r"

    return str
end

----------------------------------------------
-- Input Helpers
----------------------------------------------
function Utils.IsModifierKeyDown(modifierKey)
    if modifierKey == "SHIFT" then
        return IsShiftKeyDown()
    elseif modifierKey == "CTRL" then
        return IsControlKeyDown()
    elseif modifierKey == "ALT" then
        return IsAltKeyDown()
    else
        return false
    end
end
