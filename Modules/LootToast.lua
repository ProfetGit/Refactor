-- Refactor Addon - Loot Toast Module
-- Displays looted items in elegant stacking toasts on the bottom-left

local addonName, addon = ...


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
local previewPool = {}
local containerFrame = nil

-- Forward declarations
local ShowPreviewToasts, HidePreviewToasts

-- Sample items for edit mode preview
local PREVIEW_ITEMS = {
    {"Interface\\Icons\\INV_Sword_39", "Thunderfury, Blessed Blade of the Windseeker", 1, 5},
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

-- Loot Frame Atlas Texture Definitions
-- Format: {left, right, top, bottom}
local LOOT_ATLAS = "Interface/LootFrame/LootFrame"
local CYPHER_TEXTURE = "Interface\\Reforging\\CypherSetItemUpgrade"
local CYPHER_COORDS = {0.00195312, 0.162109, 0.572266, 0.757812}
local LOOT_HIGHLIGHT_COORDS = {0.00195312, 0.583984, 0.522461, 0.59668}     -- Looting_ItemCard_HighlightState
local LOOT_BG_COORDS = {0.00195312, 0.583984, 0.446289, 0.520508}            -- Looting_ItemCard_BG
local LOOT_STROKE_NORMAL_COORDS = {0.00195312, 0.583984, 0.674805, 0.749023} -- Looting_ItemCard_Stroke_Normal
local LOOT_STROKE_CLICK_COORDS = {0.00195312, 0.583984, 0.598633, 0.672852}  -- Looting_ItemCard_Stroke_ClickState

-- Constants (layout spacing - these control toast slot positions)
local TOAST_HEIGHT = 40  -- Slot height
local TOAST_WIDTH = 170  -- Slot width
local TOAST_SPACING = 8  -- Gap between toasts
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
    
    -- Highlight Layer (Looting_ItemCard_HighlightState) - shown on hover
    toast.highlight = toast:CreateTexture(nil, "BACKGROUND", nil, 1)
    toast.highlight:SetAllPoints()
    toast.highlight:SetTexture(LOOT_ATLAS)
    toast.highlight:SetTexCoord(LOOT_HIGHLIGHT_COORDS[1], LOOT_HIGHLIGHT_COORDS[2], LOOT_HIGHLIGHT_COORDS[3], LOOT_HIGHLIGHT_COORDS[4])
    toast.highlight:SetAlpha(0)
    
    -- Icon
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(36, 36)
    toast.icon:SetPoint("LEFT", 4, 0)
    toast.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    
    -- Icon Mask (round corners to fit within Cypher frame cutouts)
    toast.iconMask = toast:CreateMaskTexture()
    toast.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    toast.iconMask:SetAllPoints(toast.icon)
    toast.icon:AddMaskTexture(toast.iconMask)

    -- Icon Border (Cypher Atlas)
    toast.iconBorder = toast:CreateTexture(nil, "OVERLAY")
    toast.iconBorder:SetSize(45, 54)
    toast.iconBorder:SetPoint("CENTER", toast.icon, "CENTER", 0, 0)
    toast.iconBorder:SetTexture(CYPHER_TEXTURE)
    toast.iconBorder:SetTexCoord(CYPHER_COORDS[1], CYPHER_COORDS[2], CYPHER_COORDS[3], CYPHER_COORDS[4])
    
    -- Text Background (Rarity Gradient)
    toast.textBg = toast:CreateTexture(nil, "BACKGROUND")
    toast.textBg:SetHeight(36)
    toast.textBg:SetPoint("LEFT", toast.icon, "RIGHT", -2, 0)
    toast.textBg:SetPoint("RIGHT", 0, 0)
    toast.textBg:SetTexture(LOOT_ATLAS)
    toast.textBg:SetTexCoord(LOOT_BG_COORDS[1], LOOT_BG_COORDS[2], LOOT_BG_COORDS[3], LOOT_BG_COORDS[4])
    
    -- Border (Faint Mask)
    toast.border = toast:CreateTexture(nil, "BORDER")
    toast.border:SetAllPoints(toast.textBg)
    toast.border:SetTexture(LOOT_ATLAS)
    toast.border:SetTexCoord(LOOT_STROKE_NORMAL_COORDS[1], LOOT_STROKE_NORMAL_COORDS[2], LOOT_STROKE_NORMAL_COORDS[3], LOOT_STROKE_NORMAL_COORDS[4])
    toast.border:SetAlpha(0.2)
    
    toast.name = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toast.name:SetPoint("LEFT", toast.icon, "RIGHT", 6, 0)
    toast.name:SetWidth(104)  -- Reduced 20% from 130
    toast.name:SetJustifyH("LEFT")
    toast.name:SetWordWrap(true)
    toast.name:SetSpacing(2)
    toast.name:SetMaxLines(3)
    toast.name:SetShadowOffset(1, -1)
    
    -- Text: Quantity
    toast.quantity = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
        -- Show highlight on hover
        self.highlight:SetAlpha(1)
        
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    
    toast:SetScript("OnLeave", function(self)
        -- Hide highlight
        self.highlight:SetAlpha(0)
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
    
    -- Color border by rarity if desired? 
    -- For now stick to atlas default
    toast.iconBorder:SetVertexColor(color[1], color[2], color[3])
    
    -- Update Background Gradient (Fade from bottom to top depending on rarity)
    -- Bottom: More Visible, Top: Faint
    local cR, cG, cB = color[1], color[2], color[3]
    local minColor = CreateColor(cR, cG, cB, 0.7)
    local maxColor = CreateColor(cR, cG, cB, 0.15)
    toast.textBg:SetGradient("VERTICAL", minColor, maxColor)
    
    -- Update Border Mask (Very faint color mask)
    toast.border:SetVertexColor(cR, cG, cB)
    toast.border:SetAlpha(0.15)
    
    -- Use cached setting
    if cachedShowQuantity and quantity and quantity > 1 then
        toast.quantity:SetText("x" .. quantity)
        toast.quantity:Show()
    else
        toast.quantity:Hide()
    end
    
    -- Reset highlight state
    toast.highlight:SetAlpha(0)
    
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
-- Container Creation (using EditMode framework)
----------------------------------------------
local function CreateContainerFrame()
    if containerFrame then return containerFrame end
    
    containerFrame = addon.EditMode.CreateContainer({
        name = "LootToast",
        label = "Loot Toasts",
        defaultPos = {"RIGHT", -350, -80},  -- Right side, more left and slightly below center
        size = {TOAST_WIDTH, 220},
        dbPrefix = "LootToast",
        strata = "HIGH",
        settings = {
            {type = "scale", min = 50, max = 150, default = 100, label = "Frame Size"}
        },
        onEnterEditMode = function(container)
            ShowPreviewToasts()
        end,
        onExitEditMode = function(container)
            HidePreviewToasts()
        end
    })
    
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
    local toast = table_remove(previewPool)
    if not toast then
        toast = CreateFrame("Frame", nil, containerFrame)
        toast:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
        
        -- Icon (matches CreateToastFrame)
        toast.icon = toast:CreateTexture(nil, "ARTWORK")
        toast.icon:SetSize(36, 36)
        toast.icon:SetPoint("LEFT", 4, 0)
        toast.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        
        -- Icon Mask (round corners to fit within Cypher frame cutouts)
        toast.iconMask = toast:CreateMaskTexture()
        toast.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        toast.iconMask:SetAllPoints(toast.icon)
        toast.icon:AddMaskTexture(toast.iconMask)

        -- Icon Border (Cypher Atlas)
        toast.iconBorder = toast:CreateTexture(nil, "OVERLAY")
        toast.iconBorder:SetSize(45, 54)
        toast.iconBorder:SetPoint("CENTER", toast.icon, "CENTER", 0, 0)
        toast.iconBorder:SetTexture(CYPHER_TEXTURE)
        toast.iconBorder:SetTexCoord(CYPHER_COORDS[1], CYPHER_COORDS[2], CYPHER_COORDS[3], CYPHER_COORDS[4])
        
        -- Text Background (Rarity Gradient)
        toast.textBg = toast:CreateTexture(nil, "BACKGROUND")
        toast.textBg:SetHeight(36)
        toast.textBg:SetPoint("LEFT", toast.icon, "RIGHT", -2, 0)
        toast.textBg:SetPoint("RIGHT", 0, 0)
        toast.textBg:SetTexture(LOOT_ATLAS)
        toast.textBg:SetTexCoord(LOOT_BG_COORDS[1], LOOT_BG_COORDS[2], LOOT_BG_COORDS[3], LOOT_BG_COORDS[4])
        
        -- Border (Faint Mask)
        toast.border = toast:CreateTexture(nil, "BORDER")
        toast.border:SetAllPoints(toast.textBg)
        toast.border:SetTexture(LOOT_ATLAS)
        toast.border:SetTexCoord(LOOT_STROKE_NORMAL_COORDS[1], LOOT_STROKE_NORMAL_COORDS[2], LOOT_STROKE_NORMAL_COORDS[3], LOOT_STROKE_NORMAL_COORDS[4])
        toast.border:SetAlpha(0.2)
        
        -- Text: Name (matches CreateToastFrame)
        toast.name = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        toast.name:SetPoint("LEFT", toast.icon, "RIGHT", 6, 0)
        toast.name:SetWidth(104)
        toast.name:SetJustifyH("LEFT")
        toast.name:SetWordWrap(true)
        toast.name:SetSpacing(2)
        toast.name:SetMaxLines(3)
        toast.name:SetShadowOffset(1, -1)
        
        -- Text: Quantity (Create once, hide/show as needed)
        toast.quantity = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        toast.quantity:SetPoint("BOTTOMRIGHT", toast.icon, "BOTTOMRIGHT", 2, -2)
        toast.quantity:SetJustifyH("RIGHT")
        toast.quantity:SetTextColor(1, 1, 1)
    end

    toast:SetParent(containerFrame)
    toast.icon:SetTexture(icon)
    
    -- Color preview border by quality
    local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
    toast.iconBorder:SetVertexColor(color[1], color[2], color[3])
    
    -- Update Background Gradient for Preview
    local cR, cG, cB = color[1], color[2], color[3]
    local minColor = CreateColor(cR, cG, cB, 0.7)
    local maxColor = CreateColor(cR, cG, cB, 0.15)
    toast.textBg:SetGradient("VERTICAL", minColor, maxColor)
    
    -- Update Border Mask for Preview
    toast.border:SetVertexColor(cR, cG, cB)
    toast.border:SetAlpha(0.15)
    
    toast.name:SetText(name)
    toast.name:SetTextColor(color[1], color[2], color[3])
    
    -- Text: Quantity
    if cachedShowQuantity and quantity and quantity > 1 then
        toast.quantity:SetText("x" .. quantity)
        toast.quantity:Show()
    else
        toast.quantity:Hide()
    end
    
    -- Position
    local targetY = (index - 1) * (TOAST_HEIGHT + TOAST_SPACING)
    toast:ClearAllPoints()
    toast:SetPoint("BOTTOMLEFT", containerFrame, "BOTTOMLEFT", 0, targetY)
    
    return toast
end

ShowPreviewToasts = function()
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

HidePreviewToasts = function()
    for _, toast in ipairs(previewToasts) do
        toast:Hide()
        toast:ClearAllPoints()
        table_insert(previewPool, toast)
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
    
    -- Edit mode is handled by the EditMode framework via callbacks
    
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

function Module:IsInEditMode() 
    return containerFrame and containerFrame:IsInEditMode() or false 
end

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
