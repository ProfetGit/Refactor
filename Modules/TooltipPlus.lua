-- Refactor Addon - Tooltip Plus Module
-- Comprehensive tooltip customization

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Helper: Set NineSlice Border Color
-- In modern WoW, we need to iterate through NineSlice pieces
----------------------------------------------
local function SetTooltipBorderColor(tooltip, r, g, b)
    if not tooltip then return end
    
    -- Method 1: Try SetBackdropBorderColor if available
    if tooltip.SetBackdropBorderColor then
        pcall(tooltip.SetBackdropBorderColor, tooltip, r, g, b)
        return
    end
    
    -- Method 2: NineSlice approach for modern tooltips
    if tooltip.NineSlice then
        -- Try the direct method first
        if tooltip.NineSlice.SetBorderColor then
            pcall(tooltip.NineSlice.SetBorderColor, tooltip.NineSlice, CreateColor(r, g, b, 1))
        end
        
        -- Also try to color individual pieces
        local pieces = {
            "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
            "TopEdge", "BottomEdge", "LeftEdge", "RightEdge"
        }
        for _, pieceName in ipairs(pieces) do
            local piece = tooltip.NineSlice[pieceName]
            if piece and piece.SetVertexColor then
                piece:SetVertexColor(r, g, b, 1)
            end
        end
    end
end

local function ResetTooltipBorderColor(tooltip)
    SetTooltipBorderColor(tooltip, 1, 1, 1)
end

----------------------------------------------
-- Apply Class/Reaction Border Colors
----------------------------------------------
local function ApplyBorderColor(tooltip, unit)
    if not addon.GetDBBool("TooltipPlus_ClassColors") then
        return
    end
    
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            local color = RAID_CLASS_COLORS[class]
            if color then
                SetTooltipBorderColor(tooltip, color.r, color.g, color.b)
                return
            end
        end
    else
        local reaction = UnitReaction(unit, "player")
        if reaction then
            if reaction >= 5 then -- Friendly
                SetTooltipBorderColor(tooltip, 0.1, 0.9, 0.1)
            elseif reaction == 4 then -- Neutral
                SetTooltipBorderColor(tooltip, 1, 0.8, 0)
            else -- Hostile
                SetTooltipBorderColor(tooltip, 0.9, 0.1, 0.1)
            end
            return
        end
    end
end

----------------------------------------------
-- Hide Elements from Tooltip Lines
----------------------------------------------
local function ModifyTooltipText(tooltip, unit)
    if not unit then return end
    
    local hideGuild = addon.GetDBBool("TooltipPlus_HideGuild")
    local hidePvP = addon.GetDBBool("TooltipPlus_HidePvP")
    local hideRealm = addon.GetDBBool("TooltipPlus_HideRealm")
    local hideFaction = addon.GetDBBool("TooltipPlus_HideFaction")
    
    -- Early exit if nothing to hide
    if not (hideGuild or hidePvP or hideRealm or hideFaction) then
        return
    end
    
    -- Get unit info safely
    local guildName, guildRank, guildIndex = GetGuildInfo(unit)
    local isPlayer = UnitIsPlayer(unit)
    
    -- Process each line
    local tooltipName = tooltip:GetName()
    local numLines = tooltip:NumLines()
    
    for i = 1, numLines do
        local leftLine = _G[tooltipName .. "TextLeft" .. i]
        local rightLine = _G[tooltipName .. "TextRight" .. i]
        
        if leftLine then
            local text = leftLine:GetText()
            if text then
                local shouldHide = false
                
                -- Line 1: Player name with realm
                if i == 1 and hideRealm and isPlayer then
                    -- Remove realm (after hyphen, handling color codes)
                    local cleanText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    if cleanText:find("%-") then
                        -- Extract just the name part before the server
                        local newText = text:gsub("%-[^|]+", "")
                        leftLine:SetText(newText)
                    end
                end
                
                -- Guild name (usually line 2 for players, enclosed in < >)
                if hideGuild and guildName then
                    if text:find("^<.*>$") or text:find(guildName, 1, true) then
                        shouldHide = true
                    end
                end
                
                -- PvP text
                if hidePvP then
                    if text == "PvP" or text == PVP_ENABLED or text == "PVP" then
                        shouldHide = true
                    end
                end
                
                -- Faction text
                if hideFaction then
                    local factionText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                    if factionText == FACTION_ALLIANCE or factionText == FACTION_HORDE or
                       factionText == "Alliance" or factionText == "Horde" then
                        shouldHide = true
                    end
                end
                
                -- Hide the line by making it invisible
                if shouldHide then
                    leftLine:SetText(nil)
                    leftLine:Hide()
                    if rightLine then
                        rightLine:SetText(nil)
                        rightLine:Hide()
                    end
                end
            end
        end
    end
    
    -- Force tooltip to resize after modifications
    tooltip:Show()
end

----------------------------------------------
-- Apply Compact Mode
----------------------------------------------
local function ApplyCompactMode(tooltip)
    if not addon.GetDBBool("TooltipPlus_Compact") then
        return
    end
    
    -- Reduce spacing between lines by adjusting font strings
    local tooltipName = tooltip:GetName()
    local numLines = tooltip:NumLines()
    
    for i = 2, numLines do
        local line = _G[tooltipName .. "TextLeft" .. i]
        if line then
            local point, relativeTo, relativePoint, x, y = line:GetPoint(1)
            if point and y then
                -- Reduce vertical spacing
                line:SetPoint(point, relativeTo, relativePoint, x, y + 2)
            end
        end
    end
end

----------------------------------------------
-- Unit Tooltip Handler
----------------------------------------------
local function OnTooltipSetUnit(tooltip)
    if not isEnabled then return end
    if tooltip ~= GameTooltip then return end
    
    local _, unit = tooltip:GetUnit()
    if not unit then return end
    
    -- Apply border color
    ApplyBorderColor(tooltip, unit)
    
    -- Modify text (hide elements)
    ModifyTooltipText(tooltip, unit)
    
    -- Apply compact mode
    ApplyCompactMode(tooltip)
end

----------------------------------------------
-- Helper: Check if item has a transmog appearance
----------------------------------------------
local function CanItemBeTransmogged(itemLink)
    if not itemLink then return false end
    
    -- Get item info
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if not itemType then return false end
    
    -- Only armor and weapons can be transmogged
    if itemType ~= "Armor" and itemType ~= "Weapon" then
        return false
    end
    
    -- Exclude non-transmoggable subtypes
    if itemSubType == "Miscellaneous" or itemSubType == "Fishing Poles" then
        return false
    end
    
    return true
end

----------------------------------------------
-- Helper: Check if transmog appearance is collected
-- Handles artifacts, equipped items, and edge cases
----------------------------------------------
local function IsTransmogCollected(itemLink)
    if not itemLink then return nil end
    if not C_TransmogCollection then return nil end
    
    -- Get item info
    local itemID, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end
    
    -- Check if this is an artifact weapon (quality 6 = Artifact)
    local _, _, quality = GetItemInfo(itemLink)
    
    -- ARTIFACT WEAPONS: If you have it in your inventory, you have the appearance
    -- Artifact appearances are automatically collected when you obtain the weapon
    if quality == 6 or (quality == Enum.ItemQuality.Artifact) then
        return true
    end
    
    -- Method 1: PlayerHasTransmog with just itemID
    local collected = C_TransmogCollection.PlayerHasTransmog(itemID)
    if collected == true then
        return true
    end
    
    -- Method 2: Try GetItemInfo to get appearanceID and sourceID
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    
    -- Method 3: Check source info
    if sourceID then
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if sourceInfo and sourceInfo.isCollected == true then
            return true
        end
    end
    
    -- Method 4: Check all sources for this appearance
    if appearanceID then
        local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
        if sources then
            for _, source in ipairs(sources) do
                if source.isCollected then
                    return true
                end
            end
        end
    end
    
    -- Method 5: For legendaries, check via appearance system
    if quality == 5 then  -- Legendary
        local allAppearances = C_TransmogCollection.GetAllAppearanceSources(itemID)
        if allAppearances then
            for _, srcID in ipairs(allAppearances) do
                local srcInfo = C_TransmogCollection.GetSourceInfo(srcID)
                if srcInfo and srcInfo.isCollected then
                    return true
                end
            end
        end
    end
    
    -- Method 6: Check by item modified appearance (for bonus ID variations)
    if C_TransmogCollection.GetItemInfo then
        local modAppearanceID, modSourceID = C_TransmogCollection.GetItemInfo(itemID)
        if modSourceID and modSourceID ~= sourceID then
            local modSourceInfo = C_TransmogCollection.GetSourceInfo(modSourceID)
            if modSourceInfo and modSourceInfo.isCollected == true then
                return true
            end
        end
    end
    
    -- If all checks return false, the appearance is not collected
    return false
end

----------------------------------------------
-- Transmog Overlay System
-- Shows icons on item buttons in bags/vendors
----------------------------------------------
local overlayPool = {}
local activeOverlays = {}

local function GetOverlayFrame(parent)
    local overlay = tremove(overlayPool)
    if not overlay then
        overlay = CreateFrame("Frame", nil, parent)
        overlay:SetSize(16, 16)
        overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
        overlay.icon:SetAllPoints()
    end
    overlay:SetParent(parent)
    overlay:Show()
    return overlay
end

local function ReleaseOverlay(overlay)
    overlay:Hide()
    overlay:ClearAllPoints()
    tinsert(overlayPool, overlay)
end

local function ClearAllOverlays()
    for _, overlay in pairs(activeOverlays) do
        ReleaseOverlay(overlay)
    end
    wipe(activeOverlays)
end

local function GetCornerPoint(corner)
    if corner == "TOPLEFT" then
        return "TOPLEFT", 2, -2
    elseif corner == "TOPRIGHT" then
        return "TOPRIGHT", -2, -2
    elseif corner == "BOTTOMLEFT" then
        return "BOTTOMLEFT", 2, 2
    else -- BOTTOMRIGHT default
        return "BOTTOMRIGHT", -2, 2
    end
end

local function UpdateButtonOverlay(button, itemLink)
    if not button then return end
    
    local key = tostring(button)
    
    -- Remove existing overlay for this button
    if activeOverlays[key] then
        ReleaseOverlay(activeOverlays[key])
        activeOverlays[key] = nil
    end
    
    -- Check if overlay is enabled
    if not addon.GetDBBool("TooltipPlus_TransmogOverlay") then return end
    if not itemLink then return end
    
    -- Check if item can be transmogged
    if not CanItemBeTransmogged(itemLink) then return end
    
    -- Check collection status
    local isCollected = IsTransmogCollected(itemLink)
    if isCollected == nil then return end
    
    -- Create/reuse overlay
    local overlay = GetOverlayFrame(button)
    activeOverlays[key] = overlay
    
    -- Position overlay
    local corner = addon.GetDBValue("TooltipPlus_TransmogCorner") or "TOPRIGHT"
    local point, xOff, yOff = GetCornerPoint(corner)
    overlay:ClearAllPoints()
    overlay:SetPoint(point, button, point, xOff, yOff)
    overlay:SetFrameLevel(button:GetFrameLevel() + 10)
    
    -- Set icon with color
    if isCollected then
        -- Blue checkmark for collected
        overlay.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        overlay.icon:SetVertexColor(0, 0.8, 1)  -- Cyan/Blue
    else
        -- Red X for not collected
        overlay.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        overlay.icon:SetVertexColor(1, 1, 1)  -- Default red
    end
end

----------------------------------------------
-- Hook Container (Bag) Buttons
----------------------------------------------
local function UpdateContainerButton(button)
    if not button then return end
    
    local bag = button:GetParent():GetID()
    local slot = button:GetID()
    
    if bag and slot then
        local itemLink = C_Container.GetContainerItemLink(bag, slot)
        UpdateButtonOverlay(button, itemLink)
    end
end

local function UpdateAllContainerButtons()
    if not addon.GetDBBool("TooltipPlus_TransmogOverlay") then
        ClearAllOverlays()
        return
    end
    
    -- Iterate through all bags (0 = backpack, 1-4 = bags)
    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotIndex = 1, numSlots do
            local itemLink = C_Container.GetContainerItemLink(bagID, slotIndex)
            
            -- Find the button for this slot
            -- Try multiple ways to find the button
            local button = nil
            
            -- Method 1: Combined bags frame
            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                -- In combined mode, need to find the right button
                local items = ContainerFrameCombinedBags.Items
                if items then
                    for _, btn in pairs(items) do
                        if btn and btn:IsShown() then
                            local btnBag = nil
                            if btn.GetBagID then
                                btnBag = btn:GetBagID()
                            end
                            local btnSlot = btn:GetID()
                            if btnBag == bagID and btnSlot == slotIndex then
                                button = btn
                                break
                            end
                        end
                    end
                end
            end
            
            -- Method 2: Individual container frames
            if not button then
                local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
                if containerFrame and containerFrame:IsShown() then
                    -- Try Items table
                    if containerFrame.Items then
                        for _, btn in pairs(containerFrame.Items) do
                            if btn and btn:GetID() == slotIndex then
                                button = btn
                                break
                            end
                        end
                    end
                    -- Try direct child lookup
                    if not button then
                        button = containerFrame["Item" .. slotIndex]
                    end
                end
            end
            
            -- Method 3: Global button names (older UI)
            if not button then
                button = _G["ContainerFrame" .. (bagID + 1) .. "Item" .. slotIndex]
            end
            
            -- Update overlay if we found a valid button
            if button and button:IsShown() then
                UpdateButtonOverlay(button, itemLink)
            end
        end
    end
end

----------------------------------------------
-- Hook Merchant Frame Buttons
----------------------------------------------
local function UpdateMerchantButtons()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if not addon.GetDBBool("TooltipPlus_TransmogOverlay") then return end
    
    local numItems = GetMerchantNumItems()
    for i = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
        local button = _G["MerchantItem"..i.."ItemButton"]
        if button and button:IsShown() then
            local index = (MerchantFrame.page - 1) * (MERCHANT_ITEMS_PER_PAGE or 10) + i
            if index <= numItems then
                local itemLink = GetMerchantItemLink(index)
                UpdateButtonOverlay(button, itemLink)
            end
        end
    end
end

----------------------------------------------
-- Hook Loot Frame Buttons
----------------------------------------------
local function UpdateLootButtons()
    if not LootFrame or not LootFrame:IsShown() then return end
    if not addon.GetDBBool("TooltipPlus_TransmogOverlay") then return end
    
    local numItems = GetNumLootItems()
    for i = 1, numItems do
        local button = _G["LootButton"..i]
        if button and button:IsShown() then
            local itemLink = GetLootSlotLink(i)
            UpdateButtonOverlay(button, itemLink)
        end
    end
end

----------------------------------------------
-- Register Overlay Hooks
----------------------------------------------
local overlayFrame = CreateFrame("Frame")
overlayFrame:RegisterEvent("BAG_UPDATE")
overlayFrame:RegisterEvent("BAG_UPDATE_DELAYED")
overlayFrame:RegisterEvent("MERCHANT_SHOW")
overlayFrame:RegisterEvent("MERCHANT_UPDATE")
overlayFrame:RegisterEvent("LOOT_OPENED")
overlayFrame:RegisterEvent("LOOT_SLOT_CLEARED")
overlayFrame:RegisterEvent("LOOT_CLOSED")
overlayFrame:RegisterEvent("MERCHANT_CLOSED")
overlayFrame:RegisterEvent("BAG_OPEN")
overlayFrame:RegisterEvent("BAG_CLOSED")

overlayFrame:SetScript("OnEvent", function(self, event)
    if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "BAG_OPEN" then
        C_Timer.After(0.1, UpdateAllContainerButtons)
        C_Timer.After(0.3, UpdateAllContainerButtons)  -- Second pass for slow loading
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        C_Timer.After(0.1, UpdateMerchantButtons)
    elseif event == "LOOT_OPENED" or event == "LOOT_SLOT_CLEARED" then
        C_Timer.After(0.1, UpdateLootButtons)
    elseif event == "LOOT_CLOSED" or event == "MERCHANT_CLOSED" or event == "BAG_CLOSED" then
        ClearAllOverlays()
    end
end)

-- Hook bag frame show events
if ContainerFrameCombinedBags then
    ContainerFrameCombinedBags:HookScript("OnShow", function()
        C_Timer.After(0.1, UpdateAllContainerButtons)
        C_Timer.After(0.3, UpdateAllContainerButtons)
    end)
end

-- Hook individual container frames
for i = 1, 13 do
    local frame = _G["ContainerFrame" .. i]
    if frame then
        frame:HookScript("OnShow", function()
            C_Timer.After(0.1, UpdateAllContainerButtons)
            C_Timer.After(0.3, UpdateAllContainerButtons)
        end)
    end
end

----------------------------------------------
-- Baganator Integration
-- Register transmog icon as a corner widget
----------------------------------------------
if C_AddOns and C_AddOns.IsAddOnLoaded("Baganator") then
    -- Baganator is loaded, register our widget
    if Baganator and Baganator.API and Baganator.API.RegisterCornerWidget then
        Baganator.API.RegisterCornerWidget(
            "Transmog Status",           -- Label shown in Baganator settings
            "refactor_transmog",         -- Unique ID
            function(widget, details)
                -- Check if item can be transmogged
                if not details.itemLink then return false end
                if not CanItemBeTransmogged(details.itemLink) then
                    return false
                end
                
                -- Check collection status
                local collected = IsTransmogCollected(details.itemLink)
                if collected == nil then
                    return false
                end
                
                -- Set icon based on status
                if collected then
                    widget:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    widget:SetVertexColor(0, 0.8, 1)  -- Blue for collected
                else
                    widget:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                    widget:SetVertexColor(1, 1, 1)    -- Red for not collected
                end
                return true
            end,
            function(itemButton)
                -- Create the icon texture
                local icon = itemButton:CreateTexture(nil, "OVERLAY")
                icon:SetSize(16, 16)
                return icon
            end,
            { corner = "top_right", priority = 5 }
        )
    end
else
    -- Baganator might load later, wait for it
    local bagWaitFrame = CreateFrame("Frame")
    bagWaitFrame:RegisterEvent("ADDON_LOADED")
    bagWaitFrame:SetScript("OnEvent", function(self, event, loadedAddon)
        if loadedAddon == "Baganator" then
            self:UnregisterAllEvents()
            C_Timer.After(0.5, function()
                if Baganator and Baganator.API and Baganator.API.RegisterCornerWidget then
                    Baganator.API.RegisterCornerWidget(
                        "Transmog Status",
                        "refactor_transmog",
                        function(widget, details)
                            if not details.itemLink then return false end
                            if not CanItemBeTransmogged(details.itemLink) then
                                return false
                            end
                            local collected = IsTransmogCollected(details.itemLink)
                            if collected == nil then
                                return false
                            end
                            if collected then
                                widget:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                                widget:SetVertexColor(0, 0.8, 1)
                            else
                                widget:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                                widget:SetVertexColor(1, 1, 1)
                            end
                            return true
                        end,
                        function(itemButton)
                            local icon = itemButton:CreateTexture(nil, "OVERLAY")
                            icon:SetSize(16, 16)
                            return icon
                        end,
                        { corner = "top_right", priority = 5 }
                    )
                end
            end)
        end
    end)
end

----------------------------------------------
-- Item Tooltip Handler - Add Item ID & Rarity Border & Transmog Status
----------------------------------------------
local function OnTooltipSetItem(tooltip)
    if not isEnabled then return end
    
    -- Not all tooltips have GetItem (e.g., ShoppingTooltip1)
    if not tooltip.GetItem then return end
    
    local _, link = tooltip:GetItem()
    if not link then return end
    
    -- Apply rarity border color
    if addon.GetDBBool("TooltipPlus_RarityBorder") then
        local _, _, rarity = GetItemInfo(link)
        if rarity and rarity >= 0 then
            local color = ITEM_QUALITY_COLORS[rarity]
            if color then
                SetTooltipBorderColor(tooltip, color.r, color.g, color.b)
            end
        end
    end
    
    -- Show Transmog Collection Status (Integrated into tooltip lines)
    if addon.GetDBBool("TooltipPlus_ShowTransmog") then
        if CanItemBeTransmogged(link) then
            local isCollected = IsTransmogCollected(link)
            if isCollected ~= nil then
                -- Add a blank line for spacing if needed
                -- tooltip:AddLine(" ")
                
                if isCollected then
                    -- Blue checkmark + text
                    tooltip:AddDoubleLine("Appearance:", "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t Collected", 1, 0.82, 0, 0.3, 0.7, 1)
                else
                    -- Orange X + text
                    tooltip:AddDoubleLine("Appearance:", "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14:0:0|t Not Collected", 1, 0.82, 0, 1, 0.5, 0)
                end
                tooltip:Show()
            end
        end
    end
    
    -- Show Item ID
    if addon.GetDBBool("TooltipPlus_ShowItemID") then
        local itemID = GetItemInfoInstant(link)
        if itemID then
            tooltip:AddLine("|cff808080Item ID: " .. itemID .. "|r", 0.5, 0.5, 0.5)
        end
    end
end

----------------------------------------------
-- Spell Tooltip Handler - Add Spell ID
----------------------------------------------
local function OnTooltipSetSpell(tooltip)
    if not isEnabled then return end
    if not addon.GetDBBool("TooltipPlus_ShowSpellID") then return end
    
    local _, id = tooltip:GetSpell()
    if id then
        tooltip:AddLine("|cff808080Spell ID: " .. id .. "|r", 0.5, 0.5, 0.5)
    end
end

----------------------------------------------
-- Healthbar Visibility
----------------------------------------------
local healthbarHooked = false

local function HookHealthbar()
    if healthbarHooked then return end
    if not GameTooltip.StatusBar then return end
    
    healthbarHooked = true
    
    GameTooltip.StatusBar:HookScript("OnShow", function(self)
        if isEnabled and addon.GetDBBool("TooltipPlus_HideHealthbar") then
            self:Hide()
        end
    end)
end

----------------------------------------------
-- Tooltip Scale
----------------------------------------------
local function ApplyScale()
    local scale = addon.GetDBValue("TooltipPlus_Scale") or 100
    GameTooltip:SetScale(scale / 100)
end

----------------------------------------------
-- Tooltip Positioning (Anchor to Mouse)
----------------------------------------------
local function SetupMousePositioning()
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not isEnabled then return end
        if tooltip ~= GameTooltip then return end
        
        local anchor = addon.GetDBValue("TooltipPlus_Anchor") or "DEFAULT"
        
        if anchor == "DEFAULT" then
            return -- Let WoW handle it
        end
        
        local side = addon.GetDBValue("TooltipPlus_MouseSide") or "RIGHT"
        local offset = addon.GetDBValue("TooltipPlus_MouseOffset") or 20
        
        tooltip:ClearAllPoints()
        
        if anchor == "MOUSE" then
            if side == "RIGHT" then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", offset, 0)
            elseif side == "LEFT" then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR_LEFT", -offset, 0)
            elseif side == "TOP" then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR", 0, offset)
            elseif side == "BOTTOM" then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR", 0, -offset)
            end
        elseif anchor == "TOPLEFT" then
            tooltip:SetOwner(parent, "ANCHOR_NONE")
            tooltip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
        elseif anchor == "TOPRIGHT" then
            tooltip:SetOwner(parent, "ANCHOR_NONE")
            tooltip:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
        elseif anchor == "BOTTOMLEFT" then
            tooltip:SetOwner(parent, "ANCHOR_NONE")
            tooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
        elseif anchor == "BOTTOMRIGHT" then
            tooltip:SetOwner(parent, "ANCHOR_NONE")
            tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 20)
        end
    end)
end

----------------------------------------------
-- Hook Setup (runs once)
----------------------------------------------
local hooksInitialized = false

local function InitializeHooks()
    if hooksInitialized then return end
    hooksInitialized = true
    
    -- Setup positioning
    SetupMousePositioning()
    
    -- Hook healthbar
    HookHealthbar()
    
    -- Hook OnHide to reset border color
    GameTooltip:HookScript("OnHide", function(self)
        if isEnabled then
            ResetTooltipBorderColor(self)
        end
    end)
    
    -- Register tooltip data processors
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnTooltipSetSpell)
end

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    InitializeHooks()
    ApplyScale()
    addon.Print("Tooltip Plus enabled")
end

function Module:Disable()
    isEnabled = false
    
    -- Reset scale
    GameTooltip:SetScale(1)
    
    -- Reset border
    ResetTooltipBorderColor(GameTooltip)
    
    -- Show healthbar
    if GameTooltip.StatusBar then
        GameTooltip.StatusBar:Show()
    end
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    if addon.GetDBBool("TooltipPlus") then
        self:Enable()
    end
    
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
    
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_Scale", function()
        if isEnabled then
            ApplyScale()
        end
    end)
end

-- Register the module
addon.RegisterModule("TooltipPlus", Module)
