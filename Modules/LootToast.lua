-- Refactor Addon - Loot Toast Module
-- Displays looted items in elegant stacking toasts on the bottom-left

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Performance: Cache globals
----------------------------------------------
local pairs, ipairs, tonumber, type = pairs, ipairs, tonumber, type
local math_random, math_min = math.random, math.min
local table_insert, table_remove, wipe = table.insert, table.remove, wipe
local string_match = string.match
local GetTime = GetTime
local C_Item_GetItemInfo = C_Item.GetItemInfo
local C_CurrencyInfo_GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo
local UnitName = UnitName

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false
local activeToasts = {}
local toastPool = {}
local previewToasts = {}  -- Separate pool for edit mode previews
local containerFrame = nil

-- Sample items for edit mode preview
local PREVIEW_ITEMS = {
    {"Interface\\Icons\\INV_Sword_39", "Thunderfury, Blessed Blade", 1, 5},
    {"Interface\\Icons\\INV_Misc_Gem_Diamond_02", "Large Prismatic Shard", 3, 3},
    {"Interface\\Icons\\INV_Potion_51", "Major Healing Potion", 5, 2},
    {"Interface\\Icons\\INV_Fabric_Linen_01", "Linen Cloth", 20, 1},
    {"Interface\\Icons\\INV_Ingot_Eternium", "Enchanted Thorium Bar", 8, 1},
    {"Interface\\Icons\\INV_Misc_Rune_01", "Hearthstone", 1, 1},
    {"Interface\\Icons\\INV_Staff_30", "Atiesh, Greatstaff", 1, 5},
    {"Interface\\Icons\\INV_Misc_Coin_01", "Gold Coins", 100, 1},
}

----------------------------------------------
-- Pre-cached Colors (avoid CreateColor allocation)
----------------------------------------------
local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, -- Poor
    [1] = { 1.00, 1.00, 1.00 }, -- Common
    [2] = { 0.12, 1.00, 0.00 }, -- Uncommon
    [3] = { 0.00, 0.44, 0.87 }, -- Rare
    [4] = { 0.64, 0.21, 0.93 }, -- Epic
    [5] = { 1.00, 0.50, 0.00 }, -- Legendary
    [6] = { 0.90, 0.80, 0.50 }, -- Artifact
    [7] = { 0.00, 0.80, 1.00 }, -- Heirloom
    [8] = { 0.00, 0.80, 1.00 }, -- WoW Token
}

-- Pre-create gradient color objects (avoids allocation per-use)
local GRADIENT_NORMAL_START = CreateColor(0.2, 0.2, 0.2, 0.8)
local GRADIENT_NORMAL_END = CreateColor(0.2, 0.2, 0.2, 0)
local GRADIENT_HOVER_START = CreateColor(0.3, 0.3, 0.3, 0.9)
local GRADIENT_HOVER_END = CreateColor(0.3, 0.3, 0.3, 0)
local GRADIENT_CURRENCY_START = CreateColor(0.3, 0.3, 0.3, 0.8)
local GRADIENT_CURRENCY_END = CreateColor(0.3, 0.3, 0.3, 0)

-- Constants
local TOAST_HEIGHT = 40
local TOAST_WIDTH = 280
local TOAST_SPACING = 4
local TOAST_SLIDE_DURATION = 0.2
local TOAST_FADE_DURATION = 0.3

----------------------------------------------
-- Cached Settings
----------------------------------------------
local cachedDuration = 4
local cachedMaxVisible = 6
local cachedShowCurrency = true
local cachedShowQuantity = true

local function UpdateCachedSettings()
    cachedDuration = tonumber(addon.GetDBValue("LootToast_Duration")) or 4
    if cachedDuration < 1 then cachedDuration = 1 end
    cachedMaxVisible = addon.GetDBValue("LootToast_MaxVisible") or 6
    cachedShowCurrency = addon.GetDBBool("LootToast_ShowCurrency")
    cachedShowQuantity = addon.GetDBBool("LootToast_ShowQuantity")
end

----------------------------------------------
-- Helper Functions
----------------------------------------------
local function KillToast(toast)
    -- Remove from active list if present
    for i, t in ipairs(activeToasts) do
        if t == toast then
            table_remove(activeToasts, i)
            break
        end
    end
    
    -- Stop all animations/timers
    toast.slideAnim:Stop()
    toast.moveAnim:Stop()
    toast.fadeAnim:Stop()
    if toast.fadeTimer then toast.fadeTimer:Cancel() end
    toast.fadeTimer = nil
    
    -- Hide and reset
    toast:Hide()
    toast:ClearAllPoints()
    toast:SetAlpha(1)
    
    -- Return to pool
    table_insert(toastPool, toast)
    
    -- Trigger reposition of remaining toasts
    Module:RepositionToasts()
end

----------------------------------------------
-- Toast Frame Creation
----------------------------------------------
local function CreateToastFrame()
    local toast = CreateFrame("Frame", nil, containerFrame)
    toast:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    
    -- Background Gradient (use pre-cached colors)
    toast.bg = toast:CreateTexture(nil, "BACKGROUND")
    toast.bg:SetAllPoints()
    toast.bg:SetColorTexture(1, 1, 1, 1)
    toast.bg:SetGradient("HORIZONTAL", GRADIENT_NORMAL_START, GRADIENT_NORMAL_END)

    -- Icon
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(32, 32)
    toast.icon:SetPoint("LEFT", 4, 0)
    toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Text: Name
    toast.name = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toast.name:SetPoint("LEFT", toast.icon, "RIGHT", 10, 0)
    toast.name:SetPoint("RIGHT", -10, 0)
    toast.name:SetJustifyH("LEFT")
    toast.name:SetWordWrap(false)
    toast.name:SetShadowOffset(1, -1)
    
    -- Text: Quantity
    toast.quantity = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    toast.quantity:SetPoint("BOTTOMRIGHT", toast.icon, "BOTTOMRIGHT", 2, -2)
    toast.quantity:SetJustifyH("RIGHT")
    toast.quantity:SetTextColor(1, 1, 1)
    
    -- Animation: Slide In (Appear)
    toast.slideAnim = toast:CreateAnimationGroup()
    local fadeIn = toast.slideAnim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(TOAST_SLIDE_DURATION)
    fadeIn:SetSmoothing("OUT")
    
    local slideIn = toast.slideAnim:CreateAnimation("Translation")
    slideIn:SetOffset(40, 0)
    slideIn:SetDuration(TOAST_SLIDE_DURATION)
    slideIn:SetSmoothing("OUT")
    
    toast.slideAnim:SetScript("OnFinished", function()
        toast:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT", 0, toast.targetY)
        toast:SetAlpha(1)
    end)
    
    -- Animation: Move (Reposition)
    toast.moveAnim = toast:CreateAnimationGroup()
    local moveTrans = toast.moveAnim:CreateAnimation("Translation")
    toast.moveTrans = moveTrans
    moveTrans:SetDuration(TOAST_SLIDE_DURATION)
    moveTrans:SetSmoothing("OUT")
    
    toast.moveAnim:SetScript("OnFinished", function()
        toast:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT", 0, toast.targetY)
    end)

    -- Animation: Fade Out (Remove)
    toast.fadeAnim = toast:CreateAnimationGroup()
    local fadeOut = toast.fadeAnim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(TOAST_FADE_DURATION)
    fadeOut:SetSmoothing("OUT")
    
    toast.fadeAnim:SetScript("OnFinished", function()
        KillToast(toast)
    end)
    
    -- Interaction
    toast:EnableMouse(true)
    
    toast:SetScript("OnEnter", function(self)
        if self.fadeTimer then self.fadeTimer:Cancel() end
        self.bg:SetGradient("HORIZONTAL", GRADIENT_HOVER_START, GRADIENT_HOVER_END)
        
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    
    toast:SetScript("OnLeave", function(self)
        self.bg:SetGradient("HORIZONTAL", GRADIENT_NORMAL_START, GRADIENT_NORMAL_END)
        GameTooltip:Hide()
        
        self.fadeTimer = C_Timer.NewTimer(cachedDuration * 0.5, function() self.fadeAnim:Play() end)
    end)
    
    return toast
end

----------------------------------------------
-- Logic
----------------------------------------------
function Module:RepositionToasts()
    for i, toast in ipairs(activeToasts) do
        local targetY = (i - 1) * (TOAST_HEIGHT + TOAST_SPACING)
        
        if toast.targetY ~= targetY then
            local currentY = toast.targetY or targetY
            toast.targetY = targetY
            
            if not toast.slideAnim:IsPlaying() then
                toast.moveAnim:Stop()
                toast:ClearAllPoints()
                toast:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT", 0, currentY)
                
                toast.moveTrans:SetOffset(0, targetY - currentY)
                toast.moveAnim:Play()
            end
        end
    end
end

local function ShowToast(icon, name, quantity, quality, isCurrency, link)
    if not isEnabled or not containerFrame then return end
    
    -- Maintain Max Visible limit (use cached value)
    while #activeToasts >= cachedMaxVisible do
        KillToast(activeToasts[1])
    end
    
    -- Get/Create Toast
    local toast = table_remove(toastPool)
    if not toast then toast = CreateToastFrame() end
    
    -- Reset State
    toast.slideAnim:Stop()
    toast.moveAnim:Stop()
    toast.fadeAnim:Stop()
    if toast.fadeTimer then toast.fadeTimer:Cancel() end
    toast:SetAlpha(0)
    
    toast.link = link
    
    -- Content
    toast.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    
    local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
    toast.name:SetText(name or "Unknown")
    toast.name:SetTextColor(color[1], color[2], color[3])
    
    -- Use cached setting
    if cachedShowQuantity and quantity and quantity > 1 then
        toast.quantity:SetText("x" .. quantity)
        toast.quantity:Show()
    else
        toast.quantity:Hide()
    end
    
    -- Styling (use pre-cached gradient colors)
    if isCurrency then
       toast.bg:SetGradient("HORIZONTAL", GRADIENT_CURRENCY_START, GRADIENT_CURRENCY_END)
    else
       toast.bg:SetGradient("HORIZONTAL", GRADIENT_NORMAL_START, GRADIENT_NORMAL_END)
    end
    
    -- Position & Animation
    table_insert(activeToasts, toast)
    local index = #activeToasts
    local targetY = (index - 1) * (TOAST_HEIGHT + TOAST_SPACING)
    toast.targetY = targetY
    
    toast:ClearAllPoints()
    toast:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT", -40, targetY)
    toast:Show()
    toast.slideAnim:Play()
    
    -- Auto Fade Timer (use cached duration)
    toast.fadeTimer = C_Timer.NewTimer(cachedDuration, function()
        if toast:IsShown() then toast.fadeAnim:Play() end
    end)
end

----------------------------------------------
-- Event Handlers
----------------------------------------------
local function OnLootReceived(msg)
    if not isEnabled then return end
    
    local itemLink = string_match(msg, "(|c%x+|Hitem:.-|h%[.-%]|h|r)") or string_match(msg, "(|Hitem:.-|h%[.-%]|h)")
    if not itemLink then return end
    
    local quantity = tonumber(string_match(msg, "x%s*(%d+)") or 1)
    
    local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = C_Item_GetItemInfo(itemLink)
    if itemName then
        ShowToast(itemIcon, itemName, quantity, itemQuality, false, itemLink)
    else
        local item = Item:CreateFromItemLink(itemLink)
        item:ContinueOnItemLoad(function()
            local name, _, quality, _, _, _, _, _, _, icon = C_Item_GetItemInfo(itemLink)
            ShowToast(icon, name, quantity, quality, false, itemLink)
        end)
    end
end

local function OnCurrencyReceived(msg)
    if not isEnabled or not cachedShowCurrency then return end
    
    local currencyLink = string_match(msg, "|c%x+|Hcurrency:.-|h%[.-%]|h|r")
    if currencyLink then
        local id = tonumber(string_match(currencyLink, "currency:(%d+)"))
        if id then
            local info = C_CurrencyInfo_GetCurrencyInfo(id)
            if info then
                local quantity = tonumber(string_match(msg, "x(%d+)") or 1)
                ShowToast(info.iconFileID, info.name, quantity, 1, true, currencyLink)
            end
        end
    else
        -- Money
        local g = tonumber(string_match(msg, "(%d+) Gold") or string_match(msg, "(%d+)g") or 0)
        local s = tonumber(string_match(msg, "(%d+) Silver") or string_match(msg, "(%d+)s") or 0)
        local c = tonumber(string_match(msg, "(%d+) Copper") or string_match(msg, "(%d+)c") or 0)
        local total = (g * 10000) + (s * 100) + c
        if total > 0 then
            ShowToast("Interface\\Icons\\INV_Misc_Coin_01", addon.FormatMoney(total), nil, 1, true, nil)
        end
    end
end

----------------------------------------------
-- Container & Edit Mode
----------------------------------------------
local function CreateEditModeHighlight(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetAllPoints()
    h:SetFrameLevel(parent:GetFrameLevel() + 10)
    
    -- Nine-slice atlas configuration
    -- Atlas format: {width, height, left, right, top, bottom, horizTile, vertTile, scale}
    local CORNER_SIZE = 16
    local EDGE_SIZE = 16
    
    -- Atlas paths
    local ATLAS_MAIN = "Interface/Editmode/EditModeUI"
    local ATLAS_VERT = "Interface/Editmode/EditModeUIVertical"
    local ATLAS_HIGHLIGHT_BG = "Interface/Editmode/EditModeUIHighlightBackground"
    local ATLAS_SELECTED_BG = "Interface/Editmode/EditModeUISelectedBackground"
    
    -- Helper to create texture with atlas coords
    local function SetupAtlasTexture(tex, atlas, left, right, top, bottom, horizTile, vertTile)
        tex:SetTexture(atlas)
        tex:SetTexCoord(left, right, top, bottom)
        tex:SetHorizTile(horizTile)
        tex:SetVertTile(vertTile)
    end
    
    -- Create highlight nine-slice (shown when in edit mode)
    h.highlight = {}
    h.selected = {}
    
    -- Function to create nine-slice textures for a state
    local function CreateNineSlice(container, prefix, bgAtlas)
        local ns = {}
        
        -- Center (background) - fills the entire frame
        ns.center = h:CreateTexture(nil, "BACKGROUND")
        ns.center:SetAllPoints()
        SetupAtlasTexture(ns.center, bgAtlas, 0, 1, 0, 1, true, true)
        
        -- Corners (from main atlas) - offset outward to align visible border with frame edge
        local cornerCoords = prefix == "highlight" 
            and {0.03125, 0.53125, 0.285156, 0.347656}
            or {0.03125, 0.53125, 0.355469, 0.417969}
        
        local CORNER_OFFSET = 8  -- Offset to align the visible border with the frame edge
        
        ns.topleft = h:CreateTexture(nil, "BORDER")
        ns.topleft:SetSize(CORNER_SIZE, CORNER_SIZE)
        ns.topleft:SetPoint("TOPLEFT", -CORNER_OFFSET, CORNER_OFFSET)
        SetupAtlasTexture(ns.topleft, ATLAS_MAIN, cornerCoords[1], cornerCoords[2], cornerCoords[3], cornerCoords[4], false, false)
        
        ns.topright = h:CreateTexture(nil, "BORDER")
        ns.topright:SetSize(CORNER_SIZE, CORNER_SIZE)
        ns.topright:SetPoint("TOPRIGHT", CORNER_OFFSET, CORNER_OFFSET)
        SetupAtlasTexture(ns.topright, ATLAS_MAIN, cornerCoords[2], cornerCoords[1], cornerCoords[3], cornerCoords[4], false, false)
        
        ns.bottomleft = h:CreateTexture(nil, "BORDER")
        ns.bottomleft:SetSize(CORNER_SIZE, CORNER_SIZE)
        ns.bottomleft:SetPoint("BOTTOMLEFT", -CORNER_OFFSET, -CORNER_OFFSET)
        SetupAtlasTexture(ns.bottomleft, ATLAS_MAIN, cornerCoords[1], cornerCoords[2], cornerCoords[4], cornerCoords[3], false, false)
        
        ns.bottomright = h:CreateTexture(nil, "BORDER")
        ns.bottomright:SetSize(CORNER_SIZE, CORNER_SIZE)
        ns.bottomright:SetPoint("BOTTOMRIGHT", CORNER_OFFSET, -CORNER_OFFSET)
        SetupAtlasTexture(ns.bottomright, ATLAS_MAIN, cornerCoords[2], cornerCoords[1], cornerCoords[4], cornerCoords[3], false, false)
        
        -- Horizontal edges (top and bottom from main atlas, tiled horizontally)
        local topEdgeCoords = prefix == "highlight"
            and {0, 0.5, 0.0742188, 0.136719}
            or {0, 0.5, 0.214844, 0.277344}
        local bottomEdgeCoords = prefix == "highlight"
            and {0, 0.5, 0.00390625, 0.0664062}
            or {0, 0.5, 0.144531, 0.207031}
        
        ns.top = h:CreateTexture(nil, "BORDER")
        ns.top:SetHeight(EDGE_SIZE)
        ns.top:SetPoint("TOPLEFT", CORNER_SIZE - CORNER_OFFSET, CORNER_OFFSET)
        ns.top:SetPoint("TOPRIGHT", -(CORNER_SIZE - CORNER_OFFSET), CORNER_OFFSET)
        SetupAtlasTexture(ns.top, ATLAS_MAIN, topEdgeCoords[1], topEdgeCoords[2], topEdgeCoords[3], topEdgeCoords[4], true, false)
        
        ns.bottom = h:CreateTexture(nil, "BORDER")
        ns.bottom:SetHeight(EDGE_SIZE)
        ns.bottom:SetPoint("BOTTOMLEFT", CORNER_SIZE - CORNER_OFFSET, -CORNER_OFFSET)
        ns.bottom:SetPoint("BOTTOMRIGHT", -(CORNER_SIZE - CORNER_OFFSET), -CORNER_OFFSET)
        SetupAtlasTexture(ns.bottom, ATLAS_MAIN, bottomEdgeCoords[1], bottomEdgeCoords[2], bottomEdgeCoords[3], bottomEdgeCoords[4], true, false)
        
        -- Vertical edges (left and right from vertical atlas, tiled vertically)
        local leftEdgeCoords = prefix == "highlight"
            and {0.0078125, 0.132812, 0, 1}
            or {0.289062, 0.414062, 0, 1}
        local rightEdgeCoords = prefix == "highlight"
            and {0.148438, 0.273438, 0, 1}
            or {0.429688, 0.554688, 0, 1}
        
        ns.left = h:CreateTexture(nil, "BORDER")
        ns.left:SetWidth(EDGE_SIZE)
        ns.left:SetPoint("TOPLEFT", -CORNER_OFFSET, -(CORNER_SIZE - CORNER_OFFSET))
        ns.left:SetPoint("BOTTOMLEFT", -CORNER_OFFSET, CORNER_SIZE - CORNER_OFFSET)
        SetupAtlasTexture(ns.left, ATLAS_VERT, leftEdgeCoords[1], leftEdgeCoords[2], leftEdgeCoords[3], leftEdgeCoords[4], false, true)
        
        ns.right = h:CreateTexture(nil, "BORDER")
        ns.right:SetWidth(EDGE_SIZE)
        ns.right:SetPoint("TOPRIGHT", CORNER_OFFSET, -(CORNER_SIZE - CORNER_OFFSET))
        ns.right:SetPoint("BOTTOMRIGHT", CORNER_OFFSET, CORNER_SIZE - CORNER_OFFSET)
        SetupAtlasTexture(ns.right, ATLAS_VERT, rightEdgeCoords[1], rightEdgeCoords[2], rightEdgeCoords[3], rightEdgeCoords[4], false, true)
        
        container.parts = ns
        return ns
    end
    
    -- Create both states
    local highlightParts = CreateNineSlice(h.highlight, "highlight", ATLAS_HIGHLIGHT_BG)
    local selectedParts = CreateNineSlice(h.selected, "selected", ATLAS_SELECTED_BG)
    
    -- Initially show highlight, hide selected
    local function ShowParts(parts, show)
        for _, tex in pairs(parts) do
            if show then tex:Show() else tex:Hide() end
        end
    end
    
    ShowParts(selectedParts, false)
    
    -- Label (using larger font to match other edit mode components)
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.label:SetPoint("CENTER")
    h.label:SetText("Loot Toasts")
    h.label:SetTextColor(1, 1, 1)
    
    -- State tracking
    h.isDragging = false
    h.isHovered = false
    
    -- Helper to set alpha on all parts
    local function SetPartsAlpha(parts, alpha)
        for _, tex in pairs(parts) do
            tex:SetAlpha(alpha)
        end
    end
    
    -- Update visual state based on current flags
    local function UpdateState(self)
        if self.isDragging then
            -- Pressed/Dragging: Show yellow selected state
            ShowParts(highlightParts, false)
            ShowParts(selectedParts, true)
        elseif self.isHovered then
            -- Hover: Brighter blue (highlight with increased alpha)
            ShowParts(selectedParts, false)
            ShowParts(highlightParts, true)
            SetPartsAlpha(highlightParts, 1.0)
        else
            -- Normal: Default blue
            ShowParts(selectedParts, false)
            ShowParts(highlightParts, true)
            SetPartsAlpha(highlightParts, 0.7)
        end
    end
    
    -- Drag state (called from container)
    h.SetDragging = function(self, dragging)
        self.isDragging = dragging
        UpdateState(self)
    end
    
    -- Enable mouse for hover detection, but forward drag to parent
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    
    h:SetScript("OnEnter", function(self)
        self.isHovered = true
        UpdateState(self)
    end)
    h:SetScript("OnLeave", function(self)
        self.isHovered = false
        UpdateState(self)
    end)
    h:SetScript("OnDragStart", function(self)
        -- Forward drag to parent container
        local container = self:GetParent()
        if container and container.StartMoving then
            container:StartMoving()
            self:SetDragging(true)
        end
    end)
    h:SetScript("OnDragStop", function(self)
        -- Forward drag stop to parent container
        local container = self:GetParent()
        if container and container.StopMovingOrSizing then
            container:StopMovingOrSizing()
            self:SetDragging(false)
            -- Trigger save position
            local p, _, rp, x, y = container:GetPoint()
            addon.SetDBValue("LootToast_PosPoint", p)
            addon.SetDBValue("LootToast_PosRelPoint", rp)
            addon.SetDBValue("LootToast_PosX", x)
            addon.SetDBValue("LootToast_PosY", y)
        end
    end)
    
    h:Hide()
    return h
end

local function CreateContainerFrame()
    if containerFrame then return containerFrame end
    
    containerFrame = CreateFrame("Frame", "RefactorLootToastContainer", UIParent)
    containerFrame:SetSize(TOAST_WIDTH, 220)
    containerFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 200)
    containerFrame:SetFrameStrata("HIGH")
    containerFrame:SetClampedToScreen(true)
    containerFrame:SetMovable(true)
    containerFrame:RegisterForDrag("LeftButton")
    containerFrame:EnableMouse(false)
    
    containerFrame.editHighlight = CreateEditModeHighlight(containerFrame)
    
    local function SavePosition()
        local p, _, rp, x, y = containerFrame:GetPoint()
        addon.SetDBValue("LootToast_PosPoint", p)
        addon.SetDBValue("LootToast_PosRelPoint", rp)
        addon.SetDBValue("LootToast_PosX", x)
        addon.SetDBValue("LootToast_PosY", y)
    end
    
    containerFrame:SetScript("OnDragStart", function(self)
        if Module:IsInEditMode() then 
            self:StartMoving()
            self.editHighlight:SetDragging(true)
        end
    end)
    containerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.editHighlight:SetDragging(false)
        SavePosition()
    end)
    
    -- Load saved pos
    local p = addon.GetDBValue("LootToast_PosPoint")
    local x = addon.GetDBValue("LootToast_PosX")
    if p and x then
        containerFrame:ClearAllPoints()
        containerFrame:SetPoint(p, UIParent, addon.GetDBValue("LootToast_PosRelPoint") or p, x, addon.GetDBValue("LootToast_PosY"))
    end
    
    return containerFrame
end

local eventFrame = CreateFrame("Frame")
local playerName = nil

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_LOOT" then
        local msg, _, _, _, msgPlayerName = ...
        -- Cache player name on first use
        if not playerName then playerName = UnitName("player") end
        if not msgPlayerName or msgPlayerName == "" or msgPlayerName == playerName or string.find(msgPlayerName, playerName, 1, true) then
            OnLootReceived(msg)
        end
    elseif event == "CHAT_MSG_CURRENCY" or event == "CHAT_MSG_MONEY" then
        OnCurrencyReceived(...)
    end
end)

----------------------------------------------
-- Edit Mode Preview Toasts
----------------------------------------------
local function CreatePreviewToast(index, icon, name, quantity, quality)
    local toast = CreateFrame("Frame", nil, containerFrame)
    toast:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    
    -- Background Gradient
    toast.bg = toast:CreateTexture(nil, "BACKGROUND")
    toast.bg:SetAllPoints()
    toast.bg:SetColorTexture(1, 1, 1, 1)
    toast.bg:SetGradient("HORIZONTAL", GRADIENT_NORMAL_START, GRADIENT_NORMAL_END)
    
    -- Icon
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(32, 32)
    toast.icon:SetPoint("LEFT", 4, 0)
    toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    toast.icon:SetTexture(icon)
    
    -- Text: Name
    toast.name = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toast.name:SetPoint("LEFT", toast.icon, "RIGHT", 10, 0)
    toast.name:SetPoint("RIGHT", -10, 0)
    toast.name:SetJustifyH("LEFT")
    toast.name:SetWordWrap(false)
    toast.name:SetShadowOffset(1, -1)
    toast.name:SetText(name)
    
    local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
    toast.name:SetTextColor(color[1], color[2], color[3])
    
    -- Text: Quantity
    if cachedShowQuantity and quantity and quantity > 1 then
        toast.quantity = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
        toast.quantity:SetPoint("BOTTOMRIGHT", toast.icon, "BOTTOMRIGHT", 2, -2)
        toast.quantity:SetJustifyH("RIGHT")
        toast.quantity:SetTextColor(1, 1, 1)
        toast.quantity:SetText("x" .. quantity)
    end
    
    -- Position
    local targetY = (index - 1) * (TOAST_HEIGHT + TOAST_SPACING)
    toast:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT", 0, targetY)
    
    return toast
end

local function ShowPreviewToasts()
    if not containerFrame then return end
    
    -- Clear any existing previews
    for _, toast in ipairs(previewToasts) do
        toast:Hide()
        toast:SetParent(nil)
    end
    wipe(previewToasts)
    
    -- Get the number of items to show from settings
    local numToShow = cachedMaxVisible or 6
    
    -- Create preview toasts
    for i = 1, numToShow do
        local itemData = PREVIEW_ITEMS[((i - 1) % #PREVIEW_ITEMS) + 1]
        local toast = CreatePreviewToast(i, itemData[1], itemData[2], itemData[3], itemData[4])
        toast:Show()
        table_insert(previewToasts, toast)
    end
    
    -- Resize container to fit the previews
    local totalHeight = numToShow * (TOAST_HEIGHT + TOAST_SPACING) - TOAST_SPACING
    containerFrame:SetHeight(totalHeight)
end

local function HidePreviewToasts()
    for _, toast in ipairs(previewToasts) do
        toast:Hide()
        toast:SetParent(nil)
    end
    wipe(previewToasts)
    
    -- Reset container to default height
    if containerFrame then
        containerFrame:SetHeight(220)
    end
end

----------------------------------------------
-- Module Interface
----------------------------------------------
function Module:Enable()
    isEnabled = true
    UpdateCachedSettings()
    CreateContainerFrame()
    containerFrame:Show()
    
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() 
            Module.inEditMode = true 
            containerFrame:EnableMouse(true)
            containerFrame.editHighlight:Show()
            ShowPreviewToasts()
        end)
        EventRegistry:RegisterCallback("EditMode.Exit", function() 
            Module.inEditMode = false
            containerFrame:EnableMouse(false)
            containerFrame.editHighlight:Hide()
            HidePreviewToasts()
        end)
    end
    
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        Module.inEditMode = true 
        containerFrame:EnableMouse(true)
        containerFrame.editHighlight:Show()
        ShowPreviewToasts()
    end
    
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterAllEvents()

    while #activeToasts > 0 do KillToast(activeToasts[1]) end
    HidePreviewToasts()
    
    if containerFrame then containerFrame:Hide() end
end

function Module:IsInEditMode() return Module.inEditMode end

function Module:ResetPosition()
    if containerFrame then
        containerFrame:ClearAllPoints()
        containerFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 200)
        local p, _, rp, x, y = containerFrame:GetPoint()
        addon.SetDBValue("LootToast_PosPoint", p)
        addon.SetDBValue("LootToast_PosRelPoint", rp)
        addon.SetDBValue("LootToast_PosX", x)
        addon.SetDBValue("LootToast_PosY", y)
        addon.Print("Loot Toast position reset.")
    end
end

-- Test functions (only loaded, not executed unless called)
function Module:TestToast()
    local t = {
        {"Interface\\Icons\\INV_Ingot_Eternium", "Enchanted Thorium Bar", 1, 1},
        {"Interface\\Icons\\INV_Sword_39", "Thunderfury", 1, 5},
        {"Interface\\Icons\\INV_Misc_Rune_01", "Hearthstone", 1, 1},
        {"Interface\\Icons\\INV_Fabric_Linen_01", "Linen Cloth", 20, 1},
        {"Interface\\Icons\\INV_Potion_51", "Major Healing Potion", 5, 1},
        {"Interface\\Icons\\INV_Misc_Gem_Diamond_02", "Large Prismatic Shard", 3, 3},
        {"Interface\\Icons\\INV_Staff_30", "Atiesh", 1, 5}
    }
    local item = t[math_random(#t)]
    ShowToast(item[1], item[2], item[3], item[4], false, "item:12640")
end

function Module:TestWaterfall()
    C_Timer.NewTicker(0.2, function()
        Module:TestToast()
    end, 6)
end

function Module:TestCurrency()
    local t = {
        {2032, "Redeemable Anima", 50},
        {1602, "Conquest", 25},
        {1792, "Honor", 150},
    }
    local c = t[math_random(#t)]
    ShowToast(C_CurrencyInfo_GetCurrencyInfo(c[1]).iconFileID, c[2], c[3], 1, true, "currency:"..c[1])
end

function Module:OnInitialize()
    if addon.GetDBBool("LootToast") then self:Enable() end
    addon.CallbackRegistry:Register("SettingChanged.LootToast", function(v) if v then self:Enable() else self:Disable() end end)
    addon.CallbackRegistry:Register("SettingChanged.LootToast_Duration", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.LootToast_MaxVisible", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.LootToast_ShowCurrency", UpdateCachedSettings)
    addon.CallbackRegistry:Register("SettingChanged.LootToast_ShowQuantity", UpdateCachedSettings)
end

addon.RegisterModule("LootToast", Module)
