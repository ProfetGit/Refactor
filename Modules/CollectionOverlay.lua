local addonName, addon = ...
local L = addon.L

local ModuleMethods = {}

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local pairs, ipairs, type, unpack = pairs, ipairs, type, unpack
local tremove, tinsert, wipe = tremove, tinsert, wipe
local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemLink = C_Container.GetContainerItemLink
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime


----------------------------------------------
-- Cached Settings
----------------------------------------------
local cachedTransmog = true
local cachedHousing = true
local cachedMounts = true
local cachedToys = true
local cachedPets = true
local cachedCorner = "TOPRIGHT"

local function UpdateCachedSettings()
    cachedTransmog = addon.GetDBBool("CollectionOverlay_Transmog")
    cachedHousing = addon.GetDBBool("CollectionOverlay_Housing")
    cachedMounts = addon.GetDBBool("CollectionOverlay_Mounts")
    cachedToys = addon.GetDBBool("CollectionOverlay_Toys")
    cachedPets = addon.GetDBBool("CollectionOverlay_Pets")
    cachedCorner = addon.GetDBValue("CollectionOverlay_Corner") or "TOPRIGHT"
end

----------------------------------------------
-- Pre-cached constants
----------------------------------------------
local CORNER_OFFSETS = {
    TOPLEFT = { "TOPLEFT", 2, -2 },
    TOPRIGHT = { "TOPRIGHT", -2, -2 },
    BOTTOMLEFT = { "BOTTOMLEFT", 2, 2 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", -2, 2 }
}

-- Transmog Overlay Pool
local overlayPool, activeOverlays = {}, {}

local ICON_SIZE = 16
local SHADOW_OFFSET = 1.5

local SHADOW_OFFSETS = {
    { -SHADOW_OFFSET, 0 }, { SHADOW_OFFSET,  0 },
    { 0, -SHADOW_OFFSET }, { 0, SHADOW_OFFSET },
    { -SHADOW_OFFSET, -SHADOW_OFFSET }, { SHADOW_OFFSET,  -SHADOW_OFFSET },
    { -SHADOW_OFFSET, SHADOW_OFFSET },  { SHADOW_OFFSET,  SHADOW_OFFSET }
}

----------------------------------------------
-- Icon Styling
----------------------------------------------
local ICON_TEXTURE = "Interface/Common/CommonIcons"
local CHECKMARK_COORDS = { 0.000488281, 0.125488, 0.504883, 0.754883 }
local X_COORDS = { 0.252441, 0.377441, 0.504883, 0.754883 }
local COLLECTED_COLOR = { 0.3, 0.7, 1 }
local UNCOLLECTED_COLOR = { 1, 1, 1 }

local function ApplyIconStyle(texture, isCollected)
    texture:SetTexture(ICON_TEXTURE)
    texture:SetDesaturated(false)
    texture:SetVertexColor(1, 1, 1) -- Reset to default (no tint)
    if isCollected then
        texture:SetTexCoord(unpack(CHECKMARK_COORDS))
    else
        texture:SetTexCoord(unpack(X_COORDS))
    end
end

local function ApplyShadowStyle(texture, isCollected)
    texture:SetTexture(ICON_TEXTURE)
    if isCollected then
        texture:SetTexCoord(unpack(CHECKMARK_COORDS))
        texture:SetDesaturated(true)
    else
        texture:SetTexCoord(unpack(X_COORDS))
        texture:SetDesaturated(false)
    end
    texture:SetBlendMode("BLEND")
    texture:SetVertexColor(0, 0, 0, 1)
end

----------------------------------------------
-- Overlay Management
----------------------------------------------
local function GetOverlayFrame(parent)
    local overlay = tremove(overlayPool)
    if not overlay then
        overlay = CreateFrame("Frame", nil, parent)
        overlay:SetFrameStrata("TOOLTIP")
        overlay:SetFrameLevel(100)
        overlay:SetSize(ICON_SIZE + SHADOW_OFFSET * 2, ICON_SIZE + SHADOW_OFFSET * 2)

        overlay.shadows = {}
        for i, offset in ipairs(SHADOW_OFFSETS) do
            local shadow = overlay:CreateTexture(nil, "ARTWORK", nil, 1)
            shadow:SetSize(ICON_SIZE, ICON_SIZE)
            shadow:SetPoint("CENTER", overlay, "CENTER", offset[1], offset[2])
            shadow:SetVertexColor(0, 0, 0, 1)
            overlay.shadows[i] = shadow
        end

        overlay.icon = overlay:CreateTexture(nil, "ARTWORK", nil, 7)
        overlay.icon:SetSize(ICON_SIZE, ICON_SIZE)
        overlay.icon:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    end

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
        for _, shadow in ipairs(overlay.shadows) do shadow:Hide() end
    end
    if overlay.icon then overlay.icon:Hide() end
    tinsert(overlayPool, overlay)
end

local function ClearAllOverlays()
    for _, overlay in pairs(activeOverlays) do
        ReleaseOverlay(overlay)
    end
    wipe(activeOverlays)
end

----------------------------------------------
-- Collection Detection Logic
----------------------------------------------
-- Caching
local ensembleStatusCache = {}
local decorStatusCache = {}
local DECOR_CACHE_DURATION = 60
local CACHE_DURATION = 30

----------------------------------------------
-- Housing Decor Detector API
----------------------------------------------
-- Decor items can be identified by tooltip text or by classID
-- We use C_TooltipInfo (headless, structured data) instead of hidden GameTooltip
local DECOR_OWNED_PATTERNS = {
    "Owned:%s*(%d+)", "Besitz:%s*(%d+)", "Possédé[es]?:%s*(%d+)", "Poseído[as]?:%s*(%d+)",
    "Possuído[as]?:%s*(%d+)", "В наличии:%s*(%d+)", "拥有:%s*(%d+)", "擁有:%s*(%d+)", "보유:%s*(%d+)",
}

local DECOR_TYPE_PATTERNS = {
    "Housing Decor", "Wohnungsdeko", "Décor de logement", "Decoración de casa",
    "Decoração de Casa", "Украшение жилища", "家居装饰", "家居裝飾", "주택 장식",
}

local function StripColorCodes(text)
    if not text then return text end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")   -- Legacy hex color: |cFFRRGGBB
    text = text:gsub("|cn[^:]*:", "")               -- Named color: |cnCOLOR_NAME:
    text = text:gsub("|r", "")                       -- Color reset
    return text:trim()
end

local function IsDecorItem(itemLink)
    if not itemLink then return false end
    
    local tooltipData = C_TooltipInfo and C_TooltipInfo.GetHyperlink(itemLink)
    if not tooltipData then return false end
    
    -- CRITICAL: Must call SurfaceArgs to populate leftText/rightText from nested args
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(tooltipData)
    end
    
    if tooltipData.lines then
        for i = 2, math.min(6, #tooltipData.lines) do
            local line = tooltipData.lines[i]
            if line and line.leftText then
                local cleaned = StripColorCodes(line.leftText)
                for _, pattern in ipairs(DECOR_TYPE_PATTERNS) do
                    if cleaned == pattern then
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

local function GetDecorOverlayStatus(itemLink, bagID, slotIndex, merchantIndex)
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end

    -- Quick check: is this even a decor item?
    if not IsDecorItem(itemLink) then return nil end

    local cached = decorStatusCache[itemID]
    if cached and (GetTime() - cached.time) < DECOR_CACHE_DURATION then
        return cached.isCollected
    end

    -- Get structured tooltip data from C_TooltipInfo
    local tooltipData
    if bagID and slotIndex and C_TooltipInfo.GetBagItem then
        tooltipData = C_TooltipInfo.GetBagItem(bagID, slotIndex)
    elseif merchantIndex and C_TooltipInfo.GetMerchantItem then
        tooltipData = C_TooltipInfo.GetMerchantItem(merchantIndex)
    elseif C_TooltipInfo.GetHyperlink then
        tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
    end
    
    if not tooltipData then return nil end
    
    -- CRITICAL: Must call SurfaceArgs to populate leftText/rightText from nested args
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(tooltipData)
    end
    
    if not tooltipData.lines or #tooltipData.lines == 0 then return nil end

    for _, line in ipairs(tooltipData.lines) do
        -- Check both leftText and rightText
        for _, text in ipairs({ line.leftText, line.rightText }) do
            if text then
                local cleaned = StripColorCodes(text)
                
                -- Check "Already known" (case-insensitive)
                local lowerText = cleaned:lower()
                if lowerText:find("already known") then
                    decorStatusCache[itemID] = { isCollected = true, time = GetTime() }
                    return true
                end
                
                -- Check for "Owned" with any number following (broad match)
                local ownedCount = cleaned:match("Owned:%s*(%d+)")
                if not ownedCount then
                    ownedCount = cleaned:match("Owned%s+(%d+)")
                end
                if ownedCount then
                    local count = tonumber(ownedCount)
                    local isCollected = count and count > 0
                    decorStatusCache[itemID] = { isCollected = isCollected, time = GetTime() }
                    return isCollected
                end
                
                -- Also try all localized patterns
                for _, pattern in ipairs(DECOR_OWNED_PATTERNS) do
                    local countMatch = cleaned:match(pattern)
                    if countMatch then
                        local count = tonumber(countMatch)
                        local isCollected = count and count > 0
                        decorStatusCache[itemID] = { isCollected = isCollected, time = GetTime() }
                        return isCollected
                    end
                end
            end
        end
    end

    -- Confirmed decor but no ownership info = uncollected  
    decorStatusCache[itemID] = { isCollected = false, time = GetTime() }
    return false
end

-- Transmog
local function CanItemBeTransmogged(itemLink)
    if not itemLink then return false end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if not itemType or (itemType ~= "Armor" and itemType ~= "Weapon") then return false end
    return itemSubType ~= "Miscellaneous" and itemSubType ~= "Fishing Poles"
end

local function IsTransmogCollected(itemLink)
    if not itemLink or not C_TransmogCollection then return nil end
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end
    local _, _, quality = GetItemInfo(itemLink)
    if quality == 6 or quality == Enum.ItemQuality.Artifact then return true end

    if C_TransmogCollection.PlayerHasTransmog(itemID) then return true end

    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if sourceID then
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if sourceInfo and sourceInfo.isCollected then return true end
    end

    if appearanceID then
        local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
        if sources then
            for _, source in ipairs(sources) do
                if source.isCollected then return true end
            end
        end
    end

    if quality == 5 then
        local allAppearances = C_TransmogCollection.GetAllAppearanceSources(itemID)
        if allAppearances then
            for _, srcID in ipairs(allAppearances) do
                local srcInfo = C_TransmogCollection.GetSourceInfo(srcID)
                if srcInfo and srcInfo.isCollected then return true end
            end
        end
    end

    local modAppearanceID, modSourceID = C_TransmogCollection.GetItemInfo(itemID)
    if modSourceID and modSourceID ~= sourceID then
        local modSourceInfo = C_TransmogCollection.GetSourceInfo(modSourceID)
        if modSourceInfo and modSourceInfo.isCollected then return true end
    end

    return false
end

-- Ensembles
local function GetEnsembleOverlayStatus(itemLink)
    if not itemLink then return nil end
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end

    local cached = ensembleStatusCache[itemID]
    if cached and (GetTime() - cached.time) < CACHE_DURATION then
        return cached.status.isFullyCollected
    end

    if not C_Item or not C_Item.GetItemLearnTransmogSet then return nil end
    local setID = C_Item.GetItemLearnTransmogSet(itemID)
    if not setID then return nil end

    if not C_Transmog or not C_Transmog.GetAllSetAppearancesByID then return nil end
    local setSources = C_Transmog.GetAllSetAppearancesByID(setID)
    if not setSources or #setSources == 0 then
        local status = { isFullyCollected = false }
        ensembleStatusCache[itemID] = { status = status, time = GetTime() }
        return false
    end

    local collectedCount = 0
    local totalCount = #setSources

    if C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
        for _, source in ipairs(setSources) do
            local sourceID = source.itemModifiedAppearanceID
            if sourceID and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
                collectedCount = collectedCount + 1
            end
        end
    end

    local status = { isFullyCollected = collectedCount >= totalCount }
    ensembleStatusCache[itemID] = { status = status, time = GetTime() }
    return status.isFullyCollected
end

-- Mounts
local function IsMountCollected(itemLink)
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end
    
    local mountID = C_MountJournal.GetMountFromItem(itemID)
    if not mountID then return nil end
    
    local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    return isCollected
end

-- Toys
local function IsToyCollected(itemLink)
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end
    
    if C_ToyBox.GetToyInfo(itemID) then
        return PlayerHasToy(itemID)
    end
    return nil
end

-- Pets
local function IsPetCollected(itemLink)
    if not itemLink then return nil end
    local speciesID

    -- Check if it is a caged battle pet link: |Hbattlepet:speciesID...
    if itemLink:find("Hbattlepet:") then
        speciesID = tonumber(itemLink:match("Hbattlepet:(%d+)"))
    end
    
    -- Check if it is a standard companion item scroll
    if not speciesID then
        local itemID = GetItemInfoInstant(itemLink)
        if itemID and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
            speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
        end
    end

    if speciesID and C_PetJournal and C_PetJournal.GetNumCollectedInfo then
        local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
        return numCollected and numCollected > 0
    end
    
    return nil
end



----------------------------------------------
-- Main Checker
----------------------------------------------
local function GetItemCollectionStatus(itemLink, bagID, slotIndex, merchantIndex)
    if not itemLink then return nil end

    if cachedTransmog then
        if CanItemBeTransmogged(itemLink) then
            return IsTransmogCollected(itemLink)
        end
        local ensembleStatus = GetEnsembleOverlayStatus(itemLink)
        if ensembleStatus ~= nil then
            return ensembleStatus
        end
    end

    if cachedHousing then
        local decorStatus = GetDecorOverlayStatus(itemLink, bagID, slotIndex, merchantIndex)
        if decorStatus ~= nil then return decorStatus end
    end

    if cachedMounts then
        local mountStatus = IsMountCollected(itemLink)
        if mountStatus ~= nil then return mountStatus end
    end

    if cachedToys then
        local toyStatus = IsToyCollected(itemLink)
        if toyStatus ~= nil then return toyStatus end
    end

    if cachedPets then
        local petStatus = IsPetCollected(itemLink)
        if petStatus ~= nil then return petStatus end
    end

    return nil
end

local function UpdateButtonOverlay(button, itemLink, bagID, slotIndex, merchantIndex)
    if not button then return end
    local key = tostring(button)

    if activeOverlays[key] then
        ReleaseOverlay(activeOverlays[key])
        activeOverlays[key] = nil
    end

    if not itemLink then return end

    local isCollected = GetItemCollectionStatus(itemLink, bagID, slotIndex, merchantIndex)
    if isCollected == nil then return end

    local overlay = GetOverlayFrame(button)
    activeOverlays[key] = overlay

    local corner = cachedCorner
    local offsets = CORNER_OFFSETS[corner] or CORNER_OFFSETS.BOTTOMRIGHT
    overlay:ClearAllPoints()
    overlay:SetPoint(offsets[1], button, offsets[1], offsets[2], offsets[3])

    for _, shadow in ipairs(overlay.shadows) do
        ApplyShadowStyle(shadow, isCollected)
        shadow:Show()
    end

    ApplyIconStyle(overlay.icon, isCollected)
    overlay.icon:SetBlendMode("BLEND")
    overlay.icon:Show()
end

----------------------------------------------
-- Container Updates
----------------------------------------------
local function UpdateAllContainerButtons()
    for bagID = 0, 4 do
        for slotIndex = 1, C_Container_GetContainerNumSlots(bagID) do
            local button = nil
            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() and ContainerFrameCombinedBags.Items then
                for _, btn in pairs(ContainerFrameCombinedBags.Items) do
                    if btn and btn:IsShown() and btn.GetBagID and btn:GetBagID() == bagID and btn:GetID() == slotIndex then
                        button = btn
                        break
                    end
                end
            end
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
            button = button or _G["ContainerFrame" .. (bagID + 1) .. "Item" .. slotIndex]

            if button and button:IsShown() then
                local itemLink = C_Container_GetContainerItemLink(bagID, slotIndex)
                UpdateButtonOverlay(button, itemLink, bagID, slotIndex, nil)
            end
        end
    end
end

local function UpdateMerchantButtons()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end

    local numItems, perPage = GetMerchantNumItems(), MERCHANT_ITEMS_PER_PAGE or 10
    for i = 1, perPage do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button and button:IsShown() then
            local index = (MerchantFrame.page - 1) * perPage + i
            if index <= numItems then
                UpdateButtonOverlay(button, GetMerchantItemLink(index), nil, nil, index)
            else
                UpdateButtonOverlay(button, nil)
            end
        else
            if button then UpdateButtonOverlay(button, nil) end
        end
    end
end

local function UpdateLootButtons()
    if not LootFrame or not LootFrame:IsShown() then return end

    for i = 1, GetNumLootItems() do
        local button = _G["LootButton" .. i]
        if button and button:IsShown() then
            UpdateButtonOverlay(button, GetLootSlotLink(i))
        end
    end
end

local pendingContainerUpdate = false
local lastContainerUpdate = 0
local CONTAINER_UPDATE_THROTTLE = 0.3

local function ScheduleContainerUpdate()
    if InCombatLockdown() or pendingContainerUpdate then return end

    local now = GetTime()
    local timeSince = now - lastContainerUpdate

    if timeSince < CONTAINER_UPDATE_THROTTLE then
        pendingContainerUpdate = true
        C_Timer.After(CONTAINER_UPDATE_THROTTLE - timeSince, function()
            pendingContainerUpdate = false
            lastContainerUpdate = GetTime()
            UpdateAllContainerButtons()
        end)
    else
        lastContainerUpdate = now
        UpdateAllContainerButtons()
    end
end

----------------------------------------------
-- Event Handlers
----------------------------------------------
function ModuleMethods:OnBagUpdate()
    ScheduleContainerUpdate()
end

function ModuleMethods:OnMerchantShow()
    if not InCombatLockdown() then
        C_Timer.After(0.1, UpdateMerchantButtons)
    end
end

function ModuleMethods:OnLootOpened()
    C_Timer.After(0.1, UpdateLootButtons)
end

function ModuleMethods:OnLootClosed()
    for i = 1, 10 do
        local button = _G["LootButton" .. i]
        if button then
            UpdateButtonOverlay(button, nil)
        end
    end
end

function ModuleMethods:OnMerchantClosed()
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    -- Standard UI has 10, some addons increase it. 20 is a safe cleanup buffer.
    for i = 1, math.max(20, perPage) do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then
            UpdateButtonOverlay(button, nil)
        end
    end
end

function ModuleMethods:OnItemInfoReceived()
    -- Throttle updates just slightly to let batch updates arrive
    if not InCombatLockdown() then
        ScheduleContainerUpdate()
        if MerchantFrame and MerchantFrame:IsShown() then
            C_Timer.After(0.1, UpdateMerchantButtons)
        end
        if LootFrame and LootFrame:IsShown() then
            C_Timer.After(0.1, UpdateLootButtons)
        end
    end
end

----------------------------------------------
-- Lifecycle
----------------------------------------------
function ModuleMethods:OnEnable()
    UpdateCachedSettings()
    
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", ScheduleContainerUpdate)
    end
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", ScheduleContainerUpdate)
        end
    end
    
    if MerchantFrame_Update then
        hooksecurefunc("MerchantFrame_Update", UpdateMerchantButtons)
    end
    
    if LootFrame_Update then
        hooksecurefunc("LootFrame_Update", UpdateLootButtons)
    end
    
    -- Trigger initial update if Bags/Merchant are open
    ScheduleContainerUpdate()
    if MerchantFrame and MerchantFrame:IsShown() then
        self:OnMerchantShow()
    end
    
    addon.CallbackRegistry:Register("SettingChanged.CollectionOverlay_Transmog", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.CollectionOverlay_Housing", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.CollectionOverlay_Mounts", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.CollectionOverlay_Toys", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.CollectionOverlay_Corner", UpdateCachedSettings)
end

function ModuleMethods:OnDisable()
    ClearAllOverlays()
    addon.CallbackRegistry:Unregister("SettingChanged.CollectionOverlay_Transmog", UpdateCachedSettings)
    addon.CallbackRegistry:Unregister("SettingChanged.CollectionOverlay_Housing", UpdateCachedSettings)
    addon.CallbackRegistry:Unregister("SettingChanged.CollectionOverlay_Mounts", UpdateCachedSettings)
    addon.CallbackRegistry:Unregister("SettingChanged.CollectionOverlay_Toys", UpdateCachedSettings)
    addon.CallbackRegistry:Unregister("SettingChanged.CollectionOverlay_Corner", UpdateCachedSettings)
end

----------------------------------------------
-- Module Initialization
----------------------------------------------
ModuleMethods.settingKey = "CollectionOverlay"
ModuleMethods.eventMap = {
    BAG_UPDATE_DELAYED = ModuleMethods.OnBagUpdate,
    MERCHANT_SHOW = ModuleMethods.OnMerchantShow,
    MERCHANT_UPDATE = ModuleMethods.OnMerchantShow,
    LOOT_OPENED = ModuleMethods.OnLootOpened,
    LOOT_SLOT_CLEARED = ModuleMethods.OnLootOpened,
    LOOT_CLOSED = ModuleMethods.OnLootClosed,
    MERCHANT_CLOSED = ModuleMethods.OnMerchantClosed,
    GET_ITEM_INFO_RECEIVED = ModuleMethods.OnItemInfoReceived,
}

local Module = addon:NewModule("CollectionOverlay", ModuleMethods)

----------------------------------------------
-- Baganator Integration
----------------------------------------------
local function RegisterBaganatorWidget()
    if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end

    Baganator.API.RegisterCornerWidget(
        "Collection Status", "refactor_collection",
        function(widget, details)
            if not Module.isEnabled then
                widget:Hide()
                return false
            end
            if not details.itemLink then
                widget:Hide()
                return false
            end

            local collected = GetItemCollectionStatus(details.itemLink)
            if collected == nil then
                widget:Hide()
                return false
            end

            for _, shadow in ipairs(widget.shadows) do
                ApplyShadowStyle(shadow, collected)
                shadow:Show()
            end

            ApplyIconStyle(widget.icon, collected)
            widget.icon:Show()
            widget:Show()
            return true
        end,
        function(itemButton)
            local frame = CreateFrame("Frame", nil, itemButton)
            frame:SetSize(ICON_SIZE + SHADOW_OFFSET * 2, ICON_SIZE + SHADOW_OFFSET * 2)
            frame:SetFrameLevel(itemButton:GetFrameLevel() + 10)

            frame.shadows = {}
            for i, offset in ipairs(SHADOW_OFFSETS) do
                local shadow = frame:CreateTexture(nil, "ARTWORK", nil, 1)
                shadow:SetSize(ICON_SIZE, ICON_SIZE)
                shadow:SetPoint("CENTER", frame, "CENTER", offset[1], offset[2])
                frame.shadows[i] = shadow
            end

            frame.icon = frame:CreateTexture(nil, "ARTWORK", nil, 7)
            frame.icon:SetSize(ICON_SIZE, ICON_SIZE)
            frame.icon:SetPoint("CENTER", frame, "CENTER", 0, 0)

            return frame
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
