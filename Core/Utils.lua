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

----------------------------------------------
-- UI Fade Mixin
----------------------------------------------
Utils.FadeMixin = {}

function Utils.FadeMixin:FadeTo(target)
    if not target then return end
    
    -- If we're already at target, stop fading
    if math.abs(self:GetAlpha() - target) <= 0.001 then 
        self.isFadingIn = false
        self.isFadingOut = false
        if self.fadeUpdateFrame then self.fadeUpdateFrame:Hide() end
        return 
    end
    
    self.targetAlpha = target
    self.isFadingIn = target > self:GetAlpha()
    self.isFadingOut = target < self:GetAlpha()
    
    if not self.fadeUpdateFrame then
        self.fadeUpdateFrame = CreateFrame("Frame")
        self.fadeUpdateFrame:SetScript("OnUpdate", function(_, elapsed)
            local current = self:GetAlpha()
            local t = self.targetAlpha or 1
            local diff = t - current
            
            if math.abs(diff) <= 0.001 then
                self:SetAlpha(t)
                self.isFadingIn = false
                self.isFadingOut = false
                self.fadeUpdateFrame:Hide()
                return
            end
            
            local speed = self.fadeSpeed or 5
            local change = speed * elapsed
            
            if diff > 0 then
                local newAlpha = current + change
                if newAlpha > t then newAlpha = t end
                self:SetAlpha(newAlpha)
            else
                local newAlpha = current - change
                if newAlpha < t then newAlpha = t end
                self:SetAlpha(newAlpha)
            end
        end)
    end
    
    self.fadeUpdateFrame:Show()
end

function Utils.FadeMixin:FadeIn()
    -- Only fade in if not already fading in
    if self.isFadingIn then return end
    self:FadeTo(self.fadeInAlpha or 1)
end

function Utils.FadeMixin:FadeOut()
    -- Only fade out if not already fading out
    if self.isFadingOut then return end
    self:FadeTo(self.fadeOutAlpha or 0)
end

function Utils.FadeMixin:SetFadeInAlpha(alpha)
    self.fadeInAlpha = alpha
end

function Utils.FadeMixin:SetFadeOutAlpha(alpha)
    self.fadeOutAlpha = alpha
end

function Utils.FadeMixin:SetFadeSpeed(speed)
    self.fadeSpeed = speed
end

function Utils.MakeFadingObject(obj)
    if not obj then return end
    Mixin(obj, Utils.FadeMixin)
    obj:SetFadeOutAlpha(0)
    obj:SetFadeInAlpha(1)
    obj:SetFadeSpeed(5)
end
