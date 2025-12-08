local addonName, addon = ...
local L = addon.L
local Module = {}

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall
local tremove, tinsert, wipe = tremove, tinsert, wipe
local GetItemInfo, GetItemInfoInstant = GetItemInfo, GetItemInfoInstant
local UnitIsPlayer, UnitClass, UnitReaction, GetGuildInfo = UnitIsPlayer, UnitClass, UnitReaction, GetGuildInfo
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemLink = C_Container.GetContainerItemLink
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false
local hooksInitialized = false
local healthbarHooked = false

----------------------------------------------
-- Cached Settings (updated on change)
----------------------------------------------
local cachedClassColors = true
local cachedRarityBorder = true
local cachedShowTransmog = true
local cachedTransmogOverlay = true
local cachedTransmogCorner = "TOPRIGHT"
local cachedHideGuild = false
local cachedHidePvP = false
local cachedHideRealm = false
local cachedHideFaction = false
local cachedHideHealthbar = false
local cachedShowItemID = false
local cachedShowSpellID = false
local cachedAnchor = "DEFAULT"
local cachedMouseSide = "RIGHT"
local cachedMouseOffset = 20
local cachedScale = 100

local function UpdateCachedSettings()
    cachedClassColors = addon.GetDBBool("TooltipPlus_ClassColors")
    cachedRarityBorder = addon.GetDBBool("TooltipPlus_RarityBorder")
    cachedShowTransmog = addon.GetDBBool("TooltipPlus_ShowTransmog")
    cachedTransmogOverlay = addon.GetDBBool("TooltipPlus_TransmogOverlay")
    cachedTransmogCorner = addon.GetDBValue("TooltipPlus_TransmogCorner") or "TOPRIGHT"
    cachedHideGuild = addon.GetDBBool("TooltipPlus_HideGuild")
    cachedHidePvP = addon.GetDBBool("TooltipPlus_HidePvP")
    cachedHideRealm = addon.GetDBBool("TooltipPlus_HideRealm")
    cachedHideFaction = addon.GetDBBool("TooltipPlus_HideFaction")
    cachedHideHealthbar = addon.GetDBBool("TooltipPlus_HideHealthbar")
    cachedShowItemID = addon.GetDBBool("TooltipPlus_ShowItemID")
    cachedShowSpellID = addon.GetDBBool("TooltipPlus_ShowSpellID")
    cachedAnchor = addon.GetDBValue("TooltipPlus_Anchor") or "DEFAULT"
    cachedMouseSide = addon.GetDBValue("TooltipPlus_MouseSide") or "RIGHT"
    cachedMouseOffset = addon.GetDBValue("TooltipPlus_MouseOffset") or 20
    cachedScale = addon.GetDBValue("TooltipPlus_Scale") or 100
end

----------------------------------------------
-- Pre-cached constants
----------------------------------------------
local NINESLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge"
}

local CORNER_OFFSETS = {
    TOPLEFT = {"TOPLEFT", 2, -2},
    TOPRIGHT = {"TOPRIGHT", -2, -2},
    BOTTOMLEFT = {"BOTTOMLEFT", 2, 2},
    BOTTOMRIGHT = {"BOTTOMRIGHT", -2, 2}
}

local ANCHOR_POSITIONS = {
    TOPLEFT = {"TOPLEFT", UIParent, "TOPLEFT", 20, -20},
    TOPRIGHT = {"TOPRIGHT", UIParent, "TOPRIGHT", -20, -20},
    BOTTOMLEFT = {"BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20},
    BOTTOMRIGHT = {"BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 20}
}

-- Transmog Overlay Pool
local overlayPool, activeOverlays = {}, {}

----------------------------------------------
-- Border Color Helpers
----------------------------------------------
local function SetTooltipBorderColor(tooltip, r, g, b)
    if not tooltip then return end
    if tooltip.SetBackdropBorderColor then
        pcall(tooltip.SetBackdropBorderColor, tooltip, r, g, b)
        return
    end
    if tooltip.NineSlice then
        if tooltip.NineSlice.SetBorderColor then
            pcall(tooltip.NineSlice.SetBorderColor, tooltip.NineSlice, CreateColor(r, g, b, 1))
        end
        for _, pieceName in ipairs(NINESLICE_PIECES) do
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
-- Unit Tooltip Functions
----------------------------------------------
local function ApplyBorderColor(tooltip, unit)
    if not cachedClassColors then return end
    
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local color = class and RAID_CLASS_COLORS[class]
        if color then
            SetTooltipBorderColor(tooltip, color.r, color.g, color.b)
        end
    else
        local reaction = UnitReaction(unit, "player")
        if reaction then
            if reaction >= 5 then
                SetTooltipBorderColor(tooltip, 0.1, 0.9, 0.1)
            elseif reaction == 4 then
                SetTooltipBorderColor(tooltip, 1, 0.8, 0)
            else
                SetTooltipBorderColor(tooltip, 0.9, 0.1, 0.1)
            end
        end
    end
end

local function ModifyTooltipText(tooltip, unit)
    if not unit then return end
    
    -- Use cached settings
    if not (cachedHideGuild or cachedHidePvP or cachedHideRealm or cachedHideFaction) then return end
    
    local guildName = GetGuildInfo(unit)
    local isPlayer = UnitIsPlayer(unit)
    local tooltipName = tooltip:GetName()
    
    for i = 1, tooltip:NumLines() do
        local leftLine = _G[tooltipName .. "TextLeft" .. i]
        local rightLine = _G[tooltipName .. "TextRight" .. i]
        
        if leftLine then
            local text = leftLine:GetText()
            if text then
                local shouldHide = false
                
                -- Realm removal (line 1, players only)
                if i == 1 and cachedHideRealm and isPlayer then
                    local cleanText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    if cleanText:find("%-") then
                        leftLine:SetText(text:gsub("%-[^|]+", ""))
                    end
                end
                
                -- Guild name (enclosed in < >)
                if cachedHideGuild and guildName and (text:find("^<.*>$") or text:find(guildName, 1, true)) then
                    shouldHide = true
                end
                
                -- PvP text
                if cachedHidePvP and (text == "PvP" or text == PVP_ENABLED or text == "PVP") then
                    shouldHide = true
                end
                
                -- Faction text
                if cachedHideFaction then
                    local factionText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                    if factionText == FACTION_ALLIANCE or factionText == FACTION_HORDE or
                       factionText == "Alliance" or factionText == "Horde" then
                        shouldHide = true
                    end
                end
                
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
    tooltip:Show()
end

local function ApplyClassColorToName(tooltip, unit)
    if not UnitIsPlayer(unit) then return end
    
    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS[class]
    if not color then return end
    
    local nameLine = _G[tooltip:GetName() .. "TextLeft1"]
    if nameLine then
        nameLine:SetTextColor(color.r, color.g, color.b)
    end
end

----------------------------------------------
-- Transmog Functions
----------------------------------------------
local function CanItemBeTransmogged(itemLink)
    if not itemLink then return false end
    
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if not itemType or (itemType ~= "Armor" and itemType ~= "Weapon") then
        return false
    end
    return itemSubType ~= "Miscellaneous" and itemSubType ~= "Fishing Poles"
end

local function IsTransmogCollected(itemLink)
    if not itemLink or not C_TransmogCollection then return nil end
    
    local itemID, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end
    
    local _, _, quality = GetItemInfo(itemLink)
    
    -- Artifact weapons: automatically collected when obtained
    if quality == 6 or quality == Enum.ItemQuality.Artifact then
        return true
    end
    
    -- Method 1: Direct check
    if C_TransmogCollection.PlayerHasTransmog(itemID) then
        return true
    end
    
    -- Method 2: Source info check
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if sourceID then
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if sourceInfo and sourceInfo.isCollected then return true end
    end
    
    -- Method 3: Check all appearance sources
    if appearanceID then
        local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
        if sources then
            for _, source in ipairs(sources) do
                if source.isCollected then return true end
            end
        end
    end
    
    -- Method 4: Legendaries via appearance system
    if quality == 5 then
        local allAppearances = C_TransmogCollection.GetAllAppearanceSources(itemID)
        if allAppearances then
            for _, srcID in ipairs(allAppearances) do
                local srcInfo = C_TransmogCollection.GetSourceInfo(srcID)
                if srcInfo and srcInfo.isCollected then return true end
            end
        end
    end
    
    -- Method 5: Item modified appearance (bonus ID variations)
    local modAppearanceID, modSourceID = C_TransmogCollection.GetItemInfo(itemID)
    if modSourceID and modSourceID ~= sourceID then
        local modSourceInfo = C_TransmogCollection.GetSourceInfo(modSourceID)
        if modSourceInfo and modSourceInfo.isCollected then return true end
    end
    
    return false
end

----------------------------------------------
-- Overlay System
----------------------------------------------

-- Size configuration
local ICON_SIZE = 16
local SHADOW_OFFSET = 1.5 -- Offset for each shadow layer

-- Shadow offsets for 8 directions (creates thick outline effect)
local SHADOW_OFFSETS = {
    {-SHADOW_OFFSET, 0},                    -- Left
    {SHADOW_OFFSET, 0},                     -- Right
    {0, -SHADOW_OFFSET},                    -- Down
    {0, SHADOW_OFFSET},                     -- Up
    {-SHADOW_OFFSET, -SHADOW_OFFSET},       -- Bottom-Left
    {SHADOW_OFFSET, -SHADOW_OFFSET},        -- Bottom-Right
    {-SHADOW_OFFSET, SHADOW_OFFSET},        -- Top-Left
    {SHADOW_OFFSET, SHADOW_OFFSET},         -- Top-Right
}

local function GetOverlayFrame(parent)
    local overlay = tremove(overlayPool)
    
    if not overlay then
        overlay = CreateFrame("Frame", nil, parent)
        overlay:SetFrameStrata("TOOLTIP")
        overlay:SetFrameLevel(100)
        overlay:SetSize(ICON_SIZE + SHADOW_OFFSET * 2, ICON_SIZE + SHADOW_OFFSET * 2)
        
        -- Create 8 shadow textures (one for each direction)
        overlay.shadows = {}
        for i, offset in ipairs(SHADOW_OFFSETS) do
            local shadow = overlay:CreateTexture(nil, "ARTWORK", nil, 1)
            shadow:SetSize(ICON_SIZE, ICON_SIZE)
            shadow:SetPoint("CENTER", overlay, "CENTER", offset[1], offset[2])
            shadow:SetVertexColor(0, 0, 0, 1) -- Pure black
            overlay.shadows[i] = shadow
        end
        
        -- Create main icon on top of shadows
        overlay.icon = overlay:CreateTexture(nil, "ARTWORK", nil, 7)
        overlay.icon:SetSize(ICON_SIZE, ICON_SIZE)
        overlay.icon:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    end
    
    -- Apply parent and show
    overlay:SetParent(parent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetFrameLevel(100)
    overlay:Show()
    
    return overlay
end

local function ReleaseOverlay(overlay)
    overlay:Hide()
    overlay:ClearAllPoints()
    if overlay.shadows then
        for _, shadow in ipairs(overlay.shadows) do
            shadow:Hide()
        end
    end
    if overlay.icon then
        overlay.icon:Hide()
    end
    tinsert(overlayPool, overlay)
end

local function ClearAllOverlays()
    for _, overlay in pairs(activeOverlays) do
        ReleaseOverlay(overlay)
    end
    wipe(activeOverlays)
end

local function UpdateButtonOverlay(button, itemLink)
    if not button then return end
    
    local key = tostring(button)
    
    if activeOverlays[key] then
        ReleaseOverlay(activeOverlays[key])
        activeOverlays[key] = nil
    end
    
    if not cachedTransmogOverlay or not itemLink then return end
    if not CanItemBeTransmogged(itemLink) then return end
    
    local isCollected = IsTransmogCollected(itemLink)
    if isCollected == nil then return end
    
    local overlay = GetOverlayFrame(button)
    activeOverlays[key] = overlay
    
    local corner = cachedTransmogCorner
    local offsets = CORNER_OFFSETS[corner] or CORNER_OFFSETS.BOTTOMRIGHT
    overlay:ClearAllPoints()
    overlay:SetPoint(offsets[1], button, offsets[1], offsets[2], offsets[3])
    
    if isCollected then
        -- Setup all 8 shadow textures with the same checkmark but black
        for _, shadow in ipairs(overlay.shadows) do
            shadow:SetTexture("Interface/Common/CommonIcons")
            shadow:SetTexCoord(0.126465, 0.251465, 0.000976562, 0.250977)
            shadow:SetDesaturated(true)
            shadow:SetBlendMode("BLEND") -- Reset blend mode
            shadow:SetVertexColor(0, 0, 0, 1) -- Pure black shadow
            shadow:Show()
        end
        -- Main icon (blue checkmark)
        overlay.icon:SetTexture("Interface/Common/CommonIcons")
        overlay.icon:SetTexCoord(0.126465, 0.251465, 0.000976562, 0.250977)
        overlay.icon:SetDesaturated(true)
        overlay.icon:SetBlendMode("BLEND") -- Normal blend
        overlay.icon:SetVertexColor(0.3, 0.7, 1) -- Saturated blue
        overlay.icon:Show()
    else
        -- Red X icon (using original color)
        for _, shadow in ipairs(overlay.shadows) do
            shadow:SetTexture("Interface/Common/CommonIcons")
            shadow:SetTexCoord(0.252441, 0.377441, 0.25293, 0.50293) -- Red X
            shadow:SetDesaturated(false)
            shadow:SetBlendMode("BLEND")
            shadow:SetVertexColor(0, 0, 0, 1) -- Pure black shadow
            shadow:Show()
        end
        
        -- Main icon (red X)
        overlay.icon:SetTexture("Interface/Common/CommonIcons")
        overlay.icon:SetTexCoord(0.252441, 0.377441, 0.25293, 0.50293) -- Red X
        overlay.icon:SetDesaturated(false)
        overlay.icon:SetBlendMode("BLEND")
        overlay.icon:SetVertexColor(1, 1, 1) -- Original red color
        overlay.icon:Show()
    end
end

----------------------------------------------
-- Container/Merchant/Loot Button Updates
----------------------------------------------
local function UpdateAllContainerButtons()
    if not cachedTransmogOverlay then
        ClearAllOverlays()
        return
    end
    
    for bagID = 0, 4 do
        for slotIndex = 1, C_Container.GetContainerNumSlots(bagID) do
            local itemLink = C_Container.GetContainerItemLink(bagID, slotIndex)
            local button = nil
            
            -- Combined bags frame
            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                local items = ContainerFrameCombinedBags.Items
                if items then
                    for _, btn in pairs(items) do
                        if btn and btn:IsShown() then
                            local btnBag = btn.GetBagID and btn:GetBagID()
                            if btnBag == bagID and btn:GetID() == slotIndex then
                                button = btn
                                break
                            end
                        end
                    end
                end
            end
            
            -- Individual container frames
            if not button then
                local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
                if containerFrame and containerFrame:IsShown() then
                    if containerFrame.Items then
                        for _, btn in pairs(containerFrame.Items) do
                            if btn and btn:GetID() == slotIndex then
                                button = btn
                                break
                            end
                        end
                    end
                    button = button or containerFrame["Item" .. slotIndex]
                end
            end
            
            -- Global button names (older UI)
            button = button or _G["ContainerFrame" .. (bagID + 1) .. "Item" .. slotIndex]
            
            if button and button:IsShown() then
                UpdateButtonOverlay(button, itemLink)
            end
        end
    end
end

local function UpdateMerchantButtons()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if not cachedTransmogOverlay then return end
    
    local numItems, perPage = GetMerchantNumItems(), MERCHANT_ITEMS_PER_PAGE or 10
    for i = 1, perPage do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button and button:IsShown() then
            local index = (MerchantFrame.page - 1) * perPage + i
            if index <= numItems then
                UpdateButtonOverlay(button, GetMerchantItemLink(index))
            end
        end
    end
end

local function UpdateLootButtons()
    if not LootFrame or not LootFrame:IsShown() then return end
    if not cachedTransmogOverlay then return end
    
    for i = 1, GetNumLootItems() do
        local button = _G["LootButton" .. i]
        if button and button:IsShown() then
            UpdateButtonOverlay(button, GetLootSlotLink(i))
        end
    end
end

-- Debounce state for performance
local pendingContainerUpdate = false
local lastContainerUpdate = 0
local CONTAINER_UPDATE_THROTTLE = 0.3 -- Max once per 0.3 seconds

local function ScheduleContainerUpdate()
    -- Skip during combat for performance
    if InCombatLockdown() then return end
    
    -- Debounce: if already pending, skip
    if pendingContainerUpdate then return end
    
    local now = GetTime()
    local timeSince = now - lastContainerUpdate
    
    if timeSince < CONTAINER_UPDATE_THROTTLE then
        -- Too soon, schedule for later
        pendingContainerUpdate = true
        C_Timer.After(CONTAINER_UPDATE_THROTTLE - timeSince, function()
            pendingContainerUpdate = false
            lastContainerUpdate = GetTime()
            UpdateAllContainerButtons()
        end)
    else
        -- Run immediately
        lastContainerUpdate = now
        UpdateAllContainerButtons()
    end
end

----------------------------------------------
-- Overlay Event Handler
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
        ScheduleContainerUpdate() -- Now debounced
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        if not InCombatLockdown() then
            C_Timer.After(0.1, UpdateMerchantButtons)
        end
    elseif event == "LOOT_OPENED" or event == "LOOT_SLOT_CLEARED" then
        C_Timer.After(0.1, UpdateLootButtons)
    elseif event == "LOOT_CLOSED" or event == "MERCHANT_CLOSED" or event == "BAG_CLOSED" then
        ClearAllOverlays()
        pendingContainerUpdate = false -- Cancel pending updates
    end
end)

-- Hook container frames
if ContainerFrameCombinedBags then
    ContainerFrameCombinedBags:HookScript("OnShow", ScheduleContainerUpdate)
end

for i = 1, 13 do
    local frame = _G["ContainerFrame" .. i]
    if frame then
        frame:HookScript("OnShow", ScheduleContainerUpdate)
    end
end

----------------------------------------------
-- Baganator Integration
----------------------------------------------
local function RegisterBaganatorWidget()
    if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end
    
    Baganator.API.RegisterCornerWidget(
        "Transmog Status", "refactor_transmog",
        function(widget, details)
            if not details.itemLink or not CanItemBeTransmogged(details.itemLink) then
                return false
            end
            local collected = IsTransmogCollected(details.itemLink)
            if collected == nil then return false end
            
            if collected then
                widget:SetTexture("Interface/Common/CommonIcons")
                widget:SetTexCoord(0.126465, 0.251465, 0.000976562, 0.250977)
                widget:SetDesaturated(true)
                widget:SetVertexColor(0.3, 0.7, 1)
            else
                widget:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                widget:SetTexCoord(0, 1, 0, 1)
                widget:SetDesaturated(false)
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

if C_AddOns and C_AddOns.IsAddOnLoaded("Baganator") then
    RegisterBaganatorWidget()
else
    local bagWaitFrame = CreateFrame("Frame")
    bagWaitFrame:RegisterEvent("ADDON_LOADED")
    bagWaitFrame:SetScript("OnEvent", function(self, event, loadedAddon)
        if loadedAddon == "Baganator" then
            self:UnregisterAllEvents()
            C_Timer.After(0.5, RegisterBaganatorWidget)
        end
    end)
end

----------------------------------------------
-- Tooltip Transmog Icon & Text
----------------------------------------------
local tooltipTransmogIcon
local tooltipTransmogText

local function GetTooltipTransmogElements()
    if not tooltipTransmogIcon then
        tooltipTransmogIcon = GameTooltip:CreateTexture(nil, "ARTWORK")
        tooltipTransmogIcon:SetSize(24, 24)
    end
    if not tooltipTransmogText then
        tooltipTransmogText = GameTooltip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    end
    return tooltipTransmogIcon, tooltipTransmogText
end

local function HideTooltipTransmogIcon()
    if tooltipTransmogIcon then
        tooltipTransmogIcon:Hide()
        tooltipTransmogIcon:ClearAllPoints()
    end
    if tooltipTransmogText then
        tooltipTransmogText:Hide()
        tooltipTransmogText:ClearAllPoints()
    end
end

----------------------------------------------
-- Tooltip Handlers
----------------------------------------------
local function OnTooltipSetUnit(tooltip)
    if not isEnabled or tooltip ~= GameTooltip then return end
    
    local _, unit = tooltip:GetUnit()
    if not unit then return end
    
    ApplyClassColorToName(tooltip, unit)
    ApplyBorderColor(tooltip, unit)
    ModifyTooltipText(tooltip, unit)
end

local function OnTooltipSetItem(tooltip)
    if not isEnabled or not tooltip.GetItem then return end
    
    local _, link = tooltip:GetItem()
    if not link then 
        HideTooltipTransmogIcon()
        return 
    end
    
    -- Rarity border (use cached setting)
    if cachedRarityBorder then
        local _, _, rarity = GetItemInfo(link)
        if rarity and rarity >= 0 then
            local color = ITEM_QUALITY_COLORS[rarity]
            if color then
                SetTooltipBorderColor(tooltip, color.r, color.g, color.b)
            end
        end
    end
    
    -- Remove Blizzard's default "You've collected this appearance" text
    if cachedShowTransmog then
        local tooltipName = tooltip:GetName()
        for i = 1, tooltip:NumLines() do
            local leftLine = _G[tooltipName .. "TextLeft" .. i]
            if leftLine then
                local text = leftLine:GetText()
                if text then
                    -- Match Blizzard's transmog text (may have icon prefix or various formats)
                    -- Use plain find (no pattern) for apostrophe handling
                    local plainText = text:gsub("|T.-|t", ""):gsub("|A.-|a", "") -- Strip inline textures/atlases
                    if plainText:find("collected this appearance", 1, true) or
                       plainText:find("You've collected", 1, true) or
                       plainText:find("You have collected", 1, true) or
                       (TRANSMOGRIFY_TOOLTIP_APPEARANCE_KNOWN and plainText:find(TRANSMOGRIFY_TOOLTIP_APPEARANCE_KNOWN:gsub("|T.-|t", ""):gsub("|A.-|a", ""), 1, true)) then
                        leftLine:SetText(nil)
                        leftLine:Hide()
                    end
                end
            end
        end
    end
    
    -- Transmog status (use cached setting) - displayed in bottom-right corner
    if cachedShowTransmog and CanItemBeTransmogged(link) then
        local isCollected = IsTransmogCollected(link)
        if isCollected ~= nil then
            local icon, text = GetTooltipTransmogElements()
            
            -- Position text in bottom-right corner
            text:ClearAllPoints()
            text:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", -8, 12)
            
            -- Position icon to the left of text
            icon:ClearAllPoints()
            icon:SetPoint("RIGHT", text, "LEFT", -2, 0)
            
            if isCollected then
                -- Blue checkmark (desaturated + tinted)
                icon:SetTexture("Interface/Common/CommonIcons")
                icon:SetTexCoord(0.126465, 0.251465, 0.000976562, 0.250977)
                icon:SetDesaturated(true)
                icon:SetVertexColor(0.3, 0.7, 1)
                text:SetText("Collected")
                text:SetTextColor(0.3, 0.7, 1)
            else
                -- Red X
                icon:SetTexture("Interface/Common/CommonIcons")
                icon:SetTexCoord(0.252441, 0.377441, 0.25293, 0.50293)
                icon:SetDesaturated(false)
                icon:SetVertexColor(1, 1, 1)
                text:SetText("Not Collected")
                text:SetTextColor(1, 0.4, 0.4)
            end
            
            icon:Show()
            text:Show()
        else
            HideTooltipTransmogIcon()
        end
    else
        HideTooltipTransmogIcon()
    end
    
    -- Item ID (use cached setting)
    if cachedShowItemID then
        local itemID = GetItemInfoInstant(link)
        if itemID then
            tooltip:AddLine("|cff808080Item ID: " .. itemID .. "|r", 0.5, 0.5, 0.5)
        end
    end
end

local function OnTooltipSetSpell(tooltip)
    if not isEnabled or not cachedShowSpellID then return end
    
    local _, id = tooltip:GetSpell()
    if id then
        tooltip:AddLine("|cff808080Spell ID: " .. id .. "|r", 0.5, 0.5, 0.5)
    end
end

----------------------------------------------
-- Healthbar, Scale, and Positioning
----------------------------------------------
local function HookHealthbar()
    if healthbarHooked or not GameTooltip.StatusBar then return end
    healthbarHooked = true
    
    GameTooltip.StatusBar:HookScript("OnShow", function(self)
        if isEnabled and cachedHideHealthbar then
            self:Hide()
        end
    end)
end

local function ApplyScale()
    GameTooltip:SetScale(cachedScale / 100)
end

local function SetupMousePositioning()
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not isEnabled or tooltip ~= GameTooltip then return end
        if cachedAnchor == "DEFAULT" then return end
        
        tooltip:ClearAllPoints()
        
        if cachedAnchor == "MOUSE" then
            if cachedMouseSide == "RIGHT" then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", cachedMouseOffset, 0)
            elseif cachedMouseSide == "LEFT" then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR_LEFT", -cachedMouseOffset, 0)
            elseif cachedMouseSide == "TOP" then
                tooltip:SetOwner(parent, "ANCHOR_CURSOR", 0, cachedMouseOffset)
            end
        else
            local pos = ANCHOR_POSITIONS[cachedAnchor]
            if pos then
                tooltip:SetOwner(parent, "ANCHOR_NONE")
                tooltip:SetPoint(pos[1], pos[2], pos[3], pos[4], pos[5])
            end
        end
    end)
end

----------------------------------------------
-- Hook Setup & Module Enable/Disable
----------------------------------------------
local function InitializeHooks()
    if hooksInitialized then return end
    hooksInitialized = true
    
    SetupMousePositioning()
    HookHealthbar()
    
    GameTooltip:HookScript("OnHide", function(self)
        if isEnabled then
            ResetTooltipBorderColor(self)
            HideTooltipTransmogIcon()
        end
    end)
    
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnTooltipSetSpell)
end

function Module:Enable()
    isEnabled = true
    InitializeHooks()
    ApplyScale()
    addon.Print("Tooltip Plus enabled")
end

function Module:Disable()
    isEnabled = false
    GameTooltip:SetScale(1)
    ResetTooltipBorderColor(GameTooltip)
    if GameTooltip.StatusBar then
        GameTooltip.StatusBar:Show()
    end
end

function Module:OnInitialize()
    -- Cache initial settings
    UpdateCachedSettings()
    
    if addon.GetDBBool("TooltipPlus") then
        self:Enable()
    end
    
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus", function(value)
        if value then Module:Enable() else Module:Disable() end
    end)
    
    -- Cache updates for all settings
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_Scale", function()
        UpdateCachedSettings()
        if isEnabled then ApplyScale() end
    end)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_ClassColors", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_RarityBorder", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_ShowTransmog", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_TransmogOverlay", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_TransmogCorner", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_HideGuild", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_HidePvP", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_HideRealm", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_HideFaction", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_HideHealthbar", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_ShowItemID", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_ShowSpellID", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_Anchor", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_MouseSide", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_MouseOffset", UpdateCachedSettings)
end

addon.RegisterModule("TooltipPlus", Module)
