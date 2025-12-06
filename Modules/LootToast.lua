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
local table_insert, table_remove = table.insert, table.remove
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
local containerFrame = nil

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
    
    local function CreateLine(point1, point2, w, h_val)
        local t = h:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0.6, 1, 1)
        t:SetPoint(point1)
        t:SetPoint(point2)
        if w then t:SetWidth(w) else t:SetHeight(h_val) end
        return t
    end
    
    CreateLine("TOPLEFT", "TOPRIGHT", nil, 2)
    CreateLine("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    CreateLine("TOPLEFT", "BOTTOMLEFT", 2, nil)
    CreateLine("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
    
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetColorTexture(0, 0.6, 1, 0.2)
    h.bg:SetAllPoints()
    
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.label:SetPoint("CENTER", 0, 6)
    h.label:SetText("Loot Toasts")
    h.label:SetTextColor(1, 1, 1)
    
    h.sub = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.sub:SetPoint("CENTER", 0, -10)
    h.sub:SetText("Drag to move")
    h.sub:SetTextColor(0.8, 0.8, 0.8, 0.9)
    
    h.SetSelected = function(self, s) self.bg:SetColorTexture(0, 0.6, 1, s and 0.4 or 0.2) end
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
        if Module:IsInEditMode() then self:StartMoving() end
    end)
    containerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
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
        end)
        EventRegistry:RegisterCallback("EditMode.Exit", function() 
            Module.inEditMode = false
            containerFrame:EnableMouse(false)
            containerFrame.editHighlight:Hide()
        end)
    end
    
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        Module.inEditMode = true 
        containerFrame:EnableMouse(true)
        containerFrame.editHighlight:Show()
    end
    
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
end

function Module:Disable()
    isEnabled = false
    eventFrame:UnregisterAllEvents()

    while #activeToasts > 0 do KillToast(activeToasts[1]) end
    
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
