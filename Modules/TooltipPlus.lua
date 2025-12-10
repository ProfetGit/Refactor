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
    TOPLEFT = { "TOPLEFT", 2, -2 },
    TOPRIGHT = { "TOPRIGHT", -2, -2 },
    BOTTOMLEFT = { "BOTTOMLEFT", 2, 2 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", -2, 2 }
}

local ANCHOR_POSITIONS = {
    TOPLEFT = { "TOPLEFT", UIParent, "TOPLEFT", 20, -20 },
    TOPRIGHT = { "TOPRIGHT", UIParent, "TOPRIGHT", -20, -20 },
    BOTTOMLEFT = { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 20 }
}

-- Transmog Overlay Pool
local overlayPool, activeOverlays = {}, {}

----------------------------------------------
-- Transmog Icon Styling (centralized)
----------------------------------------------
local TRANSMOG_ICON_TEXTURE = "Interface/Common/CommonIcons"
local TRANSMOG_CHECKMARK_COORDS = { 0.126465, 0.251465, 0.000976562, 0.250977 }
local TRANSMOG_X_COORDS = { 0.252441, 0.377441, 0.25293, 0.50293 }
local TRANSMOG_COLLECTED_COLOR = { 0.3, 0.7, 1 }
local TRANSMOG_UNCOLLECTED_COLOR = { 1, 1, 1 }

local function ApplyTransmogIconStyle(texture, isCollected)
    texture:SetTexture(TRANSMOG_ICON_TEXTURE)
    if isCollected then
        texture:SetTexCoord(unpack(TRANSMOG_CHECKMARK_COORDS))
        texture:SetDesaturated(true)
        texture:SetVertexColor(unpack(TRANSMOG_COLLECTED_COLOR))
    else
        texture:SetTexCoord(unpack(TRANSMOG_X_COORDS))
        texture:SetDesaturated(false)
        texture:SetVertexColor(unpack(TRANSMOG_UNCOLLECTED_COLOR))
    end
end

-- For shadow textures (always black)
local function ApplyTransmogShadowStyle(texture, isCollected)
    texture:SetTexture(TRANSMOG_ICON_TEXTURE)
    if isCollected then
        texture:SetTexCoord(unpack(TRANSMOG_CHECKMARK_COORDS))
        texture:SetDesaturated(true)
    else
        texture:SetTexCoord(unpack(TRANSMOG_X_COORDS))
        texture:SetDesaturated(false)
    end
    texture:SetBlendMode("BLEND")
    texture:SetVertexColor(0, 0, 0, 1)
end

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
-- Ensemble Detection & Collection Status
-- Uses the proper WoW API: C_Item.GetItemLearnTransmogSet
----------------------------------------------

-- Cache for ensemble status to avoid repeated API calls
local ensembleStatusCache = {}
local CACHE_DURATION = 30 -- seconds (increased for performance)

----------------------------------------------
-- Housing Decor Detection & Collection Status
-- New collectible type added in recent patches
----------------------------------------------

-- Localized patterns for detecting Housing Decor items
-- These patterns handle different client languages
local DECOR_TYPE_PATTERNS = {
    "Housing Decor", -- enUS/enGB
    "Wohnungsdeko", -- deDE
    "Décor de logement", -- frFR
    "Decoración de casa", -- esES/esMX
    "Decoração de Casa", -- ptBR
    "Украшение жилища", -- ruRU
    "家居装饰", -- zhCN
    "家居裝飾", -- zhTW
    "주거 장식", -- koKR
}

-- Localized patterns for detecting "Owned: X" in tooltips
-- Format: pattern to match "Owned: number" or equivalent
local DECOR_OWNED_PATTERNS = {
    "Owned:%s*(%d+)", -- enUS/enGB
    "Besitz:%s*(%d+)", -- deDE
    "Possédé[es]?:%s*(%d+)", -- frFR
    "Poseído[as]?:%s*(%d+)", -- esES/esMX
    "Possuído[as]?:%s*(%d+)", -- ptBR
    "В наличии:%s*(%d+)", -- ruRU
    "拥有:%s*(%d+)", -- zhCN
    "擁有:%s*(%d+)", -- zhTW
    "보유:%s*(%d+)", -- koKR
}

-- Cache for decor item status (itemID -> {isDecor, isCollected, time})
local decorStatusCache = {}
local DECOR_CACHE_DURATION = 60 -- seconds

-- Check if an item is a Housing Decor item
local function IsDecorItem(itemLink)
    if not itemLink then return false end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return false end

    -- Check cache first
    local cached = decorStatusCache[itemID]
    if cached and cached.isDecor ~= nil and (GetTime() - cached.time) < DECOR_CACHE_DURATION then
        return cached.isDecor
    end

    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if not itemSubType then return false end

    -- Check against all localized patterns
    for _, pattern in ipairs(DECOR_TYPE_PATTERNS) do
        if itemSubType == pattern then
            -- Cache the result
            decorStatusCache[itemID] = decorStatusCache[itemID] or {}
            decorStatusCache[itemID].isDecor = true
            decorStatusCache[itemID].time = GetTime()
            return true
        end
    end

    -- Not a decor item
    decorStatusCache[itemID] = decorStatusCache[itemID] or {}
    decorStatusCache[itemID].isDecor = false
    decorStatusCache[itemID].time = GetTime()
    return false
end

-- Get the collection status of a Housing Decor item from tooltip text
-- Returns: true (owned >= 1), false (owned == 0), nil (couldn't determine)
local function GetDecorCollectionStatus(tooltip, itemLink)
    if not tooltip or not itemLink then return nil end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end

    -- Check cache first (for overlay system to reuse tooltip-parsed data)
    local cached = decorStatusCache[itemID]
    if cached and cached.isCollected ~= nil and (GetTime() - cached.time) < DECOR_CACHE_DURATION then
        return cached.isCollected
    end

    -- Scan tooltip lines for "Owned: X" pattern
    local tooltipName = tooltip:GetName()
    for i = 1, tooltip:NumLines() do
        local leftLine = _G[tooltipName .. "TextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text then
                -- Try all localized patterns
                for _, pattern in ipairs(DECOR_OWNED_PATTERNS) do
                    local owned = text:match(pattern)
                    if owned then
                        local count = tonumber(owned)
                        local isCollected = count and count > 0

                        -- Cache the result
                        decorStatusCache[itemID] = decorStatusCache[itemID] or {}
                        decorStatusCache[itemID].isCollected = isCollected
                        decorStatusCache[itemID].time = GetTime()

                        return isCollected
                    end
                end
            end
        end
    end

    return nil -- Couldn't determine
end

-- Get cached decor collection status (for overlay system without tooltip access)
local function GetDecorOverlayStatus(itemLink)
    if not itemLink then return nil end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end

    -- Only return from cache - don't parse tooltip here
    local cached = decorStatusCache[itemID]
    if cached and cached.isCollected ~= nil and (GetTime() - cached.time) < DECOR_CACHE_DURATION then
        return cached.isCollected
    end

    return nil -- Not cached, will be populated when tooltip is shown
end

-- Check if an item is an Ensemble using the proper API
local function IsEnsembleItem(itemLink)
    if not itemLink then return false end
    if not C_Item or not C_Item.GetItemLearnTransmogSet then return false end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return false end

    local setID = C_Item.GetItemLearnTransmogSet(itemID)
    return setID ~= nil
end

-- Get the collection status of an ensemble using the proper API
-- Returns: { collected = number, total = number, isFullyCollected = bool } or nil
local function GetEnsembleCollectionStatus(itemLink)
    if not itemLink then return nil end

    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return nil end

    -- Check cache first
    local cached = ensembleStatusCache[itemID]
    if cached and (GetTime() - cached.time) < CACHE_DURATION then
        return cached.status
    end

    -- Check if it's an ensemble
    if not C_Item or not C_Item.GetItemLearnTransmogSet then return nil end

    local setID = C_Item.GetItemLearnTransmogSet(itemID)
    if not setID then return nil end

    -- Get all appearances in the set
    if not C_Transmog or not C_Transmog.GetAllSetAppearancesByID then return nil end

    local setSources = C_Transmog.GetAllSetAppearancesByID(setID)
    if not setSources or #setSources == 0 then
        -- Ensemble exists but no sources found (possibly broken vendor data)
        local status = {
            collected = 0,
            total = 0,
            isFullyCollected = false,
            isUnknown = true
        }
        ensembleStatusCache[itemID] = { status = status, time = GetTime() }
        return status
    end

    -- Count collected appearances
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

    local status = {
        collected = collectedCount,
        total = totalCount,
        isFullyCollected = collectedCount >= totalCount
    }

    -- Cache the result
    ensembleStatusCache[itemID] = { status = status, time = GetTime() }

    return status
end

-- Get collection status for overlay purposes (returns: true = collected, false = not collected, nil = N/A)
local function GetEnsembleOverlayStatus(itemLink)
    local status = GetEnsembleCollectionStatus(itemLink)
    if not status then return nil end
    return status.isFullyCollected
end

----------------------------------------------
-- Overlay System
----------------------------------------------

-- Size configuration
local ICON_SIZE = 16
local SHADOW_OFFSET = 1.5 -- Offset for each shadow layer

-- Shadow offsets for 8 directions (creates thick outline effect)
local SHADOW_OFFSETS = {
    { -SHADOW_OFFSET, 0 },              -- Left
    { SHADOW_OFFSET,  0 },              -- Right
    { 0,              -SHADOW_OFFSET }, -- Down
    { 0,              SHADOW_OFFSET },  -- Up
    { -SHADOW_OFFSET, -SHADOW_OFFSET }, -- Bottom-Left
    { SHADOW_OFFSET,  -SHADOW_OFFSET }, -- Bottom-Right
    { -SHADOW_OFFSET, SHADOW_OFFSET },  -- Top-Left
    { SHADOW_OFFSET,  SHADOW_OFFSET },  -- Top-Right
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

    -- Check for regular transmog items first
    local isCollected = nil
    if CanItemBeTransmogged(itemLink) then
        isCollected = IsTransmogCollected(itemLink)
    else
        -- Check for Ensemble items
        isCollected = GetEnsembleOverlayStatus(itemLink)
    end

    if isCollected == nil then return end

    local overlay = GetOverlayFrame(button)
    activeOverlays[key] = overlay

    local corner = cachedTransmogCorner
    local offsets = CORNER_OFFSETS[corner] or CORNER_OFFSETS.BOTTOMRIGHT
    overlay:ClearAllPoints()
    overlay:SetPoint(offsets[1], button, offsets[1], offsets[2], offsets[3])

    -- Apply shadow styling (always black)
    for _, shadow in ipairs(overlay.shadows) do
        ApplyTransmogShadowStyle(shadow, isCollected)
        shadow:Show()
    end

    -- Apply main icon styling
    ApplyTransmogIconStyle(overlay.icon, isCollected)
    overlay.icon:SetBlendMode("BLEND")
    overlay.icon:Show()
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
            if not cachedTransmogOverlay then
                widget:Hide()
                return false
            end
            if not details.itemLink then
                widget:Hide()
                return false
            end

            -- Check for regular transmog items first, then Ensemble items
            local collected = nil
            if CanItemBeTransmogged(details.itemLink) then
                collected = IsTransmogCollected(details.itemLink)
            else
                collected = GetEnsembleOverlayStatus(details.itemLink)
            end

            if collected == nil then
                widget:Hide()
                return false
            end

            -- Apply shadow styling
            for _, shadow in ipairs(widget.shadows) do
                ApplyTransmogShadowStyle(shadow, collected)
                shadow:Show()
            end

            -- Apply main icon styling
            ApplyTransmogIconStyle(widget.icon, collected)
            widget.icon:Show()
            widget:Show()
            return true
        end,
        function(itemButton)
            -- Create a frame with shadows (matching our overlay system)
            local frame = CreateFrame("Frame", nil, itemButton)
            frame:SetSize(ICON_SIZE + SHADOW_OFFSET * 2, ICON_SIZE + SHADOW_OFFSET * 2)
            frame:SetFrameLevel(itemButton:GetFrameLevel() + 10)

            -- Create 8 shadow textures
            frame.shadows = {}
            for i, offset in ipairs(SHADOW_OFFSETS) do
                local shadow = frame:CreateTexture(nil, "ARTWORK", nil, 1)
                shadow:SetSize(ICON_SIZE, ICON_SIZE)
                shadow:SetPoint("CENTER", frame, "CENTER", offset[1], offset[2])
                frame.shadows[i] = shadow
            end

            -- Create main icon on top of shadows
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

----------------------------------------------
-- Tooltip Transmog Icon (positioned next to text line)
----------------------------------------------
local tooltipTransmogIcons = {} -- Cache icons per tooltip

local function GetTooltipTransmogIcon(tooltip)
    local tooltipName = tooltip:GetName()
    if not tooltipTransmogIcons[tooltipName] then
        tooltipTransmogIcons[tooltipName] = tooltip:CreateTexture(nil, "OVERLAY", nil, 7)
        tooltipTransmogIcons[tooltipName]:SetSize(14, 14)
    end
    return tooltipTransmogIcons[tooltipName]
end

local function HideTooltipTransmogIcon(tooltip)
    local tooltipName = tooltip and tooltip:GetName()
    if tooltipName and tooltipTransmogIcons[tooltipName] then
        tooltipTransmogIcons[tooltipName]:Hide()
        tooltipTransmogIcons[tooltipName]:ClearAllPoints()
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
    if not link then return end

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

    -- Transmog status (use cached setting) - displayed as its own line at the bottom
    -- Check for regular transmog items
    if cachedShowTransmog and CanItemBeTransmogged(link) then
        local isCollected = IsTransmogCollected(link)
        if isCollected ~= nil then
            local r, g, b
            local statusText

            if isCollected then
                r, g, b = unpack(TRANSMOG_COLLECTED_COLOR)
                statusText = "Collected"
            else
                r, g, b = 1, 0.4, 0.4 -- Red-ish for not collected
                statusText = "Not Collected"
            end

            -- Add spacing and the status text line (right-aligned)
            tooltip:AddLine(" ") -- Spacing line
            tooltip:AddDoubleLine(" ", statusText, 1, 1, 1, r, g, b)
            tooltip:Show()       -- Force tooltip to recalculate size

            -- Position the icon next to the text on the last line
            local icon = GetTooltipTransmogIcon(tooltip)
            ApplyTransmogIconStyle(icon, isCollected)

            -- Find the last right-side text line and position icon to the left of the actual text
            local tooltipName = tooltip:GetName()
            local lastRightLine = _G[tooltipName .. "TextRight" .. tooltip:NumLines()]

            if lastRightLine and lastRightLine:GetText() then
                -- Get the text width to position icon immediately to its left
                local textWidth = lastRightLine:GetStringWidth()
                icon:ClearAllPoints()
                -- Anchor to RIGHT of the text line, offset by text width + small gap + icon width
                icon:SetPoint("RIGHT", lastRightLine, "RIGHT", -(textWidth + 4), 0)
                icon:Show()
            end
        else
            HideTooltipTransmogIcon(tooltip)
        end
        -- Check for Ensemble items
    elseif cachedShowTransmog then
        local ensembleStatus = GetEnsembleCollectionStatus(link)
        if ensembleStatus then
            local r, g, b
            local statusText
            local isCollected = ensembleStatus.isFullyCollected

            if isCollected then
                r, g, b = unpack(TRANSMOG_COLLECTED_COLOR)
                statusText = "Collected"
            elseif ensembleStatus.isUnknown then
                -- Couldn't determine collection status from tooltip
                r, g, b = 0.7, 0.7, 0.7 -- Gray for unknown
                statusText = "Unknown"
            elseif ensembleStatus.collected > 0 then
                -- Partially collected - show progress
                r, g, b = 1, 0.8, 0.3 -- Yellow-ish for partial
                statusText = string.format("%d/%d", ensembleStatus.collected, ensembleStatus.total)
            else
                r, g, b = 1, 0.4, 0.4 -- Red-ish for not collected
                statusText = "Not Collected"
            end

            -- Add spacing and the status text line (right-aligned)
            tooltip:AddLine(" ") -- Spacing line
            tooltip:AddDoubleLine(" ", statusText, 1, 1, 1, r, g, b)
            tooltip:Show()       -- Force tooltip to recalculate size

            -- Position the icon next to the text on the last line
            local icon = GetTooltipTransmogIcon(tooltip)
            ApplyTransmogIconStyle(icon, isCollected)

            -- Find the last right-side text line and position icon to the left of the actual text
            local tooltipName = tooltip:GetName()
            local lastRightLine = _G[tooltipName .. "TextRight" .. tooltip:NumLines()]

            if lastRightLine and lastRightLine:GetText() then
                -- Get the text width to position icon immediately to its left
                local textWidth = lastRightLine:GetStringWidth()
                icon:ClearAllPoints()
                -- Anchor to RIGHT of the text line, offset by text width + small gap + icon width
                icon:SetPoint("RIGHT", lastRightLine, "RIGHT", -(textWidth + 4), 0)
                icon:Show()
            end
        else
            HideTooltipTransmogIcon(tooltip)
        end
    else
        HideTooltipTransmogIcon(tooltip)
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
            HideTooltipTransmogIcon(self)
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
