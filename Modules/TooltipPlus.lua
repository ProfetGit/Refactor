local addonName, addon = ...
local L = addon.L
local Module = {}

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall
local tremove, tinsert, wipe = tremove, tinsert, wipe
local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
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
local cachedHideGuild = false
local cachedHidePvP = false
local cachedHideRealm = false
local cachedHideFaction = false
local cachedHideHealthbar = false
local cachedShowItemID = false
local cachedShowSpellID = false
local cachedAutoCompare = false
local cachedAnchor = "DEFAULT"
local cachedMouseSide = "RIGHT"
local cachedMouseOffset = 20
local cachedScale = 100

local function UpdateCachedSettings()
    cachedClassColors = addon.GetDBBool("TooltipPlus_ClassColors")
    cachedRarityBorder = addon.GetDBBool("TooltipPlus_RarityBorder")
    cachedShowTransmog = addon.GetDBBool("TooltipPlus_ShowTransmog")
    cachedHideGuild = addon.GetDBBool("TooltipPlus_HideGuild")
    cachedHidePvP = addon.GetDBBool("TooltipPlus_HidePvP")
    cachedHideRealm = addon.GetDBBool("TooltipPlus_HideRealm")
    cachedHideFaction = addon.GetDBBool("TooltipPlus_HideFaction")
    cachedHideHealthbar = addon.GetDBBool("TooltipPlus_HideHealthbar")
    cachedShowItemID = addon.GetDBBool("TooltipPlus_ShowItemID")
    cachedShowSpellID = addon.GetDBBool("TooltipPlus_ShowSpellID")
    cachedAutoCompare = addon.GetDBBool("TooltipPlus_AutoCompare")
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

-- Transmog Functions

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
    if tooltip:IsShown() then
        tooltip:Show()
    end
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

    -- Safely check if the unit token is restricted (throws "Secret values are only allowed...")
    if not pcall(UnitIsPlayer, unit) then return end

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

            local texPath = "Interface/Common/CommonIcons"
            -- Convert RGB percentage to 0-255 range for the color string
            local colorStr = string.format(":%d:%d:%d", r * 255, g * 255, b * 255)

            local iconStr
            if isCollected then
                -- Checkmark icon with coords
                iconStr = string.format("|T%s:14:14:0:0:512:512:65:128:0:128:255:255:255|t ", texPath)
            else
                -- X icon with coords
                iconStr = string.format("|T%s:14:14:0:0:512:512:129:193:258:386:255:255:255|t ", texPath)
            end

            -- Add spacing and the status text line (right-aligned)
            tooltip:AddLine(" ") -- Spacing line
            tooltip:AddDoubleLine(" ", iconStr .. statusText, 1, 1, 1, r, g, b)
            if tooltip:IsShown() then tooltip:Show() end -- Force tooltip to recalculate size

            -- Hide standalone icon if it was previously used
            HideTooltipTransmogIcon(tooltip)
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

            local texPath = "Interface/Common/CommonIcons"
            local iconStr
            if isCollected then
                iconStr = string.format("|T%s:14:14:0:0:512:512:65:128:0:128:255:255:255|t ", texPath)
            elseif ensembleStatus.isUnknown or ensembleStatus.collected > 0 then
                iconStr = string.format("|T%s:14:14:0:0:512:512:256:320:256:320:255:255:255|t ", texPath)
            else
                iconStr = string.format("|T%s:14:14:0:0:512:512:129:193:258:386:255:255:255|t ", texPath)
            end

            -- Add spacing and the status text line (right-aligned)
            tooltip:AddLine(" ") -- Spacing line
            tooltip:AddDoubleLine(" ", iconStr .. statusText, 1, 1, 1, r, g, b)
            if tooltip:IsShown() then tooltip:Show() end -- Force tooltip to recalculate size

            -- Hide standalone icon if it was previously used
            HideTooltipTransmogIcon(tooltip)
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
    ---@diagnostic disable-next-line: undefined-field
    if healthbarHooked or not GameTooltip.StatusBar then return end
    healthbarHooked = true

    ---@diagnostic disable-next-line: undefined-field
    GameTooltip.StatusBar:HookScript("OnShow", function(self)
        if isEnabled and cachedHideHealthbar then
            self:Hide()
        end
    end)
end

local function ApplyScale()
    GameTooltip:SetScale(cachedScale / 100)
end

local function ApplyAutoCompareCVar()
    local value = cachedAutoCompare and "1" or "0"
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("alwaysCompareItems", value)
    else
        SetCVar("alwaysCompareItems", value)
    end
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
    ApplyAutoCompareCVar()
end

function Module:Disable()
    isEnabled = false
    GameTooltip:SetScale(1)
    ResetTooltipBorderColor(GameTooltip)
    ---@diagnostic disable-next-line: undefined-field
    if GameTooltip.StatusBar then
        ---@diagnostic disable-next-line: undefined-field
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
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_AutoCompare", function()
        UpdateCachedSettings()
        if isEnabled then ApplyAutoCompareCVar() end
    end)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_Anchor", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_MouseSide", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.TooltipPlus_MouseOffset", UpdateCachedSettings)
end

addon.RegisterModule("TooltipPlus", Module)
