-- Refactor Addon - Settings Main Panel
-- Premium 2-column layout (Optimized)

local addonName, addon = ...
local L = addon.L
local Components = addon.SettingsUI
local C = addon.Constants

----------------------------------------------
-- Panel State
----------------------------------------------
local SettingsPanel = {}
addon.SettingsPanel = SettingsPanel

local frame, containers, tabs = nil, {}, {}

----------------------------------------------
-- Layout Constants
----------------------------------------------
local LAYOUT = {
    PANEL_WIDTH = 720, PANEL_HEIGHT = 660,
    LEFT_MARGIN = 20, RIGHT_MARGIN = 20,
    COLUMN_WIDTH = 320, COLUMN_GAP = 30,
    SECTION_SPACING = 18, ROW_HEIGHT = 24,
    SUB_OPTION_HEIGHT = 22, SUB_OPTION_INDENT = 22,
    HEADER_HEIGHT = 28, MODULE_HEIGHT = 26,
}

-- Precomputed column X positions
local COL_X = {
    LEFT = LAYOUT.LEFT_MARGIN,
    RIGHT = LAYOUT.LEFT_MARGIN + LAYOUT.COLUMN_WIDTH + LAYOUT.COLUMN_GAP,
}

----------------------------------------------
-- Smooth Scroll Constants
----------------------------------------------
local SCROLL_SPEED, SCROLL_SMOOTHNESS, SCROLL_THRESHOLD = 50, 0.22, 0.5
local SCROLL_STEP = 30

-- Dropdown options are defined in Core/Constants.lua (addon.Constants)

----------------------------------------------
-- Atlas Button Helper (3-Part Red Button)
-- Uses Left/Center/Right pieces for proper scaling
----------------------------------------------
local function StyleButtonWithAtlas(button)
    -- Hide default UIPanelButtonTemplate textures
    if button.Left then button.Left:Hide() end
    if button.Middle then button.Middle:Hide() end
    if button.Right then button.Right:Hide() end
    
    -- Create texture sets for each state
    -- Atlas dimensions: Left=114x128, Center=64x128 (tiling), Right=292x128
    local function CreateButtonTextures(suffix, layer)
        local btnHeight = button:GetHeight()
        -- Calculate scaled widths based on aspect ratio (original height is 128)
        local leftWidth = math.floor(114 * (btnHeight / 128) + 0.5)
        local rightWidth = math.floor(292 * (btnHeight / 128) + 0.5)
        
        local left = button:CreateTexture(nil, layer)
        left:SetAtlas("128-RedButton-Left" .. suffix, false)
        left:SetPoint("TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", 0, 0)
        left:SetWidth(leftWidth)
        
        local right = button:CreateTexture(nil, layer)
        right:SetAtlas("128-RedButton-Right" .. suffix, false)
        right:SetPoint("TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", 0, 0)
        right:SetWidth(rightWidth)
        
        local center = button:CreateTexture(nil, layer, nil, -1)
        center:SetAtlas("_128-RedButton-Center" .. suffix, false)
        center:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        center:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
        
        return { left = left, center = center, right = right }
    end
    
    -- Normal state
    button.normalTex = CreateButtonTextures("", "BACKGROUND")
    
    -- Pressed state (hidden by default)
    button.pushedTex = CreateButtonTextures("-Pressed", "BACKGROUND")
    button.pushedTex.left:Hide()
    button.pushedTex.center:Hide()
    button.pushedTex.right:Hide()
    
    -- Disabled state (hidden by default)
    button.disabledTex = CreateButtonTextures("-Disabled", "BACKGROUND")
    button.disabledTex.left:Hide()
    button.disabledTex.center:Hide()
    button.disabledTex.right:Hide()
    
    -- Highlight overlay
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("128-RedButton-Highlight", false)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    
    -- Helper functions to show/hide texture sets
    local function ShowTexSet(set)
        set.left:Show()
        set.center:Show()
        set.right:Show()
    end
    
    local function HideTexSet(set)
        set.left:Hide()
        set.center:Hide()
        set.right:Hide()
    end
    
    -- Handle button states via scripts
    button:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() then
            HideTexSet(self.normalTex)
            ShowTexSet(self.pushedTex)
        end
    end)
    
    button:HookScript("OnMouseUp", function(self)
        if self:IsEnabled() then
            HideTexSet(self.pushedTex)
            ShowTexSet(self.normalTex)
        end
    end)
    
    -- Reset state when leaving button while pressed
    button:HookScript("OnLeave", function(self)
        if self:IsEnabled() then
            HideTexSet(self.pushedTex)
            ShowTexSet(self.normalTex)
        end
    end)
    
    -- Handle disabled state
    button:HookScript("OnDisable", function(self)
        HideTexSet(self.normalTex)
        HideTexSet(self.pushedTex)
        ShowTexSet(self.disabledTex)
    end)
    
    button:HookScript("OnEnable", function(self)
        HideTexSet(self.disabledTex)
        HideTexSet(self.pushedTex)
        ShowTexSet(self.normalTex)
    end)
    
    -- Update text appearance for red button
    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
    button:SetPushedTextOffset(0, -2)
end

----------------------------------------------
-- Helper: Create Scrollable Tab Container
-- Scrollbar uses Blizzard's minimal scrollbar style
----------------------------------------------
local function CreateTabContainer(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -16, 5)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    content:SetHeight(1000)
    scrollFrame:SetScrollChild(content)
    
    -- Scrollbar constants for Blizzard's minimal style
    local TRACK_WIDTH = 10
    local THUMB_WIDTH = 8
    local THUMB_MIN_SIZE = 18
    local STEPPER_RESERVE = 20
    local STEPPER_MARGIN_Y = 2
    local THUMB_MID_OFS_T = 8  -- Offset from thumb top texture
    local THUMB_MID_OFS_B = 10 -- Offset from thumb bottom texture
    
    -- Main scrollbar frame
    local scrollBar = CreateFrame("Frame", nil, container)
    scrollBar:SetWidth(TRACK_WIDTH)
    scrollBar:SetPoint("TOPRIGHT", -4, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", -4, 4)
    
    -- Up Arrow Button
    local upButton = CreateFrame("Button", nil, scrollBar)
    upButton:SetPoint("TOP", 0, -STEPPER_MARGIN_Y)
    
    local upNormal = upButton:CreateTexture(nil, "ARTWORK")
    upNormal:SetAtlas("minimal-scrollbar-arrow-top", true)
    upNormal:SetPoint("CENTER")
    upButton:SetSize(upNormal:GetSize())
    upButton:SetNormalTexture(upNormal)
    
    local upHighlight = upButton:CreateTexture(nil, "HIGHLIGHT")
    upHighlight:SetAtlas("minimal-scrollbar-arrow-top-over", true)
    upHighlight:SetPoint("CENTER")
    
    local upPushed = upButton:CreateTexture(nil, "ARTWORK")
    upPushed:SetAtlas("minimal-scrollbar-arrow-top-down", true)
    upPushed:SetPoint("CENTER", 0, -2) -- Push offset
    upButton:SetPushedTexture(upPushed)
    
    -- Down Arrow Button
    local downButton = CreateFrame("Button", nil, scrollBar)
    downButton:SetPoint("BOTTOM", 0, STEPPER_MARGIN_Y)
    
    local downNormal = downButton:CreateTexture(nil, "ARTWORK")
    downNormal:SetAtlas("minimal-scrollbar-arrow-bottom", true)
    downNormal:SetPoint("CENTER")
    downButton:SetSize(downNormal:GetSize())
    downButton:SetNormalTexture(downNormal)
    
    local downHighlight = downButton:CreateTexture(nil, "HIGHLIGHT")
    downHighlight:SetAtlas("minimal-scrollbar-arrow-bottom-over", true)
    downHighlight:SetPoint("CENTER")
    
    local downPushed = downButton:CreateTexture(nil, "ARTWORK")
    downPushed:SetAtlas("minimal-scrollbar-arrow-bottom-down", true)
    downPushed:SetPoint("CENTER", 0, 2) -- Push offset (opposite direction)
    downButton:SetPushedTexture(downPushed)
    
    -- Track (between arrows)
    local track = CreateFrame("Frame", nil, scrollBar)
    track:SetPoint("TOP", 0, -STEPPER_RESERVE)
    track:SetPoint("BOTTOM", 0, STEPPER_RESERVE)
    track:SetWidth(TRACK_WIDTH)
    
    -- Track textures - use natural atlas sizes
    local trackTop = track:CreateTexture(nil, "BACKGROUND")
    trackTop:SetAtlas("minimal-scrollbar-track-top", true)
    trackTop:SetPoint("TOP", 0, 1) -- Slight adjustment to connect with stepper
    
    local trackBot = track:CreateTexture(nil, "BACKGROUND")
    trackBot:SetAtlas("minimal-scrollbar-track-bottom", true)
    trackBot:SetPoint("BOTTOM", 0, -1)
    
    local trackMid = track:CreateTexture(nil, "BACKGROUND")
    trackMid:SetAtlas("!minimal-scrollbar-track-middle", true)
    trackMid:SetPoint("TOPLEFT", trackTop, "BOTTOMLEFT", 0, 0)
    trackMid:SetPoint("BOTTOMRIGHT", trackBot, "TOPRIGHT", 0, 0)
    
    -- Thumb
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(THUMB_WIDTH)
    thumb:SetHeight(THUMB_MIN_SIZE)
    
    -- Normal thumb textures (BACKGROUND layer)
    local thumbTop = thumb:CreateTexture(nil, "BACKGROUND")
    thumbTop:SetAtlas("minimal-scrollbar-thumb-top", true)
    thumbTop:SetPoint("TOP", 0, 0)
    
    local thumbBot = thumb:CreateTexture(nil, "BACKGROUND")
    thumbBot:SetAtlas("minimal-scrollbar-thumb-bottom", true)
    thumbBot:SetPoint("BOTTOM", 0, 0)
    
    local thumbMid = thumb:CreateTexture(nil, "BACKGROUND", nil, -1) -- Lower sublevel
    thumbMid:SetAtlas("minimal-scrollbar-thumb-middle", true)
    thumbMid:SetPoint("TOP", 0, -THUMB_MID_OFS_T)
    thumbMid:SetPoint("BOTTOM", 0, THUMB_MID_OFS_B)
    
    -- Hover thumb textures (HIGHLIGHT layer - auto-shown on hover)
    local thumbTopH = thumb:CreateTexture(nil, "HIGHLIGHT")
    thumbTopH:SetAtlas("minimal-scrollbar-thumb-top-over", true)
    thumbTopH:SetPoint("TOP", 0, 0)
    
    local thumbBotH = thumb:CreateTexture(nil, "HIGHLIGHT")
    thumbBotH:SetAtlas("minimal-scrollbar-thumb-bottom-over", true)
    thumbBotH:SetPoint("BOTTOM", 0, 0)
    
    local thumbMidH = thumb:CreateTexture(nil, "HIGHLIGHT")
    thumbMidH:SetAtlas("minimal-scrollbar-thumb-middle-over", true)
    thumbMidH:SetPoint("TOP", 0, -THUMB_MID_OFS_T)
    thumbMidH:SetPoint("BOTTOM", 0, THUMB_MID_OFS_B)
    
    -- Update scrollbar state
    local function UpdateScrollBar()
        local scrollRange = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
        local scrollValue = scrollFrame:GetVerticalScroll()
        local trackHeight = track:GetHeight()
        
        if scrollRange > 0 and trackHeight > 0 then
            local thumbHeight = math.max(THUMB_MIN_SIZE, (scrollFrame:GetHeight() / content:GetHeight()) * trackHeight)
            thumb:SetHeight(thumbHeight)
            
            local thumbPos = (scrollValue / scrollRange) * (trackHeight - thumbHeight)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -thumbPos)
            
            scrollBar:Show()
            upButton:SetEnabled(scrollValue > 0)
            downButton:SetEnabled(scrollValue < scrollRange)
        else
            scrollBar:Hide()
        end
    end
    
    -- Thumb dragging
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")
    
    thumb:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self.startY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        self.startScroll = scrollFrame:GetVerticalScroll()
    end)
    
    thumb:SetScript("OnDragStop", function(self) self.isDragging = false end)
    
    thumb:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end
        local currentY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local deltaY = self.startY - currentY
        local scrollRange = math.max(1, content:GetHeight() - scrollFrame:GetHeight())
        local trackTravel = track:GetHeight() - thumb:GetHeight()
        
        if trackTravel > 0 then
            local newScroll = math.max(0, math.min(scrollRange, self.startScroll + (deltaY / trackTravel) * scrollRange))
            scrollFrame:SetVerticalScroll(newScroll)
            UpdateScrollBar()
        end
    end)
    
    -- Arrow buttons
    upButton:SetScript("OnClick", function()
        scrollFrame:SetVerticalScroll(math.max(0, scrollFrame:GetVerticalScroll() - SCROLL_STEP))
        UpdateScrollBar()
    end)
    
    downButton:SetScript("OnClick", function()
        local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
        scrollFrame:SetVerticalScroll(math.min(maxScroll, scrollFrame:GetVerticalScroll() + SCROLL_STEP))
        UpdateScrollBar()
    end)
    
    -- Smooth scroll
    local targetScroll, isAnimating = 0, false
    local animFrame = CreateFrame("Frame", nil, scrollFrame)
    animFrame:Hide()
    
    animFrame:SetScript("OnUpdate", function(self)
        local currentScroll = scrollFrame:GetVerticalScroll()
        local diff = targetScroll - currentScroll
        
        if math.abs(diff) < SCROLL_THRESHOLD then
            scrollFrame:SetVerticalScroll(targetScroll)
            isAnimating = false
            self:Hide()
        else
            scrollFrame:SetVerticalScroll(currentScroll + diff * SCROLL_SMOOTHNESS)
        end
        UpdateScrollBar()
    end)
    
    local function OnMouseWheel(_, delta)
        local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
        targetScroll = math.max(0, math.min(maxScroll, targetScroll - delta * SCROLL_SPEED))
        if not isAnimating then
            isAnimating = true
            animFrame:Show()
        end
    end
    
    scrollFrame:SetScript("OnMouseWheel", OnMouseWheel)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta) OnMouseWheel(nil, delta) end)
    
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
        UpdateScrollBar()
    end)
    
    scrollFrame:SetScript("OnShow", function() C_Timer.After(0.1, UpdateScrollBar) end)
    
    container.scrollFrame, container.scrollBar, container.content = scrollFrame, scrollBar, content
    container.allControls = {}
    
    return container
end

----------------------------------------------
-- 2-Column Layout Builder (Optimized)
----------------------------------------------
local function CreateTwoColumnLayout(parent)
    local layout = {
        parent = parent,
        columns = { LEFT = {}, RIGHT = {} },
        currentY = 0,
        allModules = {},
    }
    
    -- Generic column position helper
    local function getColumnY(colItems)
        local y = layout.currentY
        for _, item in ipairs(colItems) do
            y = y - (item:GetHeight() or LAYOUT.SUB_OPTION_HEIGHT)
        end
        return y
    end
    
    -- Add section header (spans both columns) - for single-column sections
    function layout:AddSection(text)
        self.currentY = self.currentY - LAYOUT.SECTION_SPACING
        local header = Components.CreateSectionHeader(self.parent, text)
        header:SetPoint("TOPLEFT", COL_X.LEFT, self.currentY)
        header:SetPoint("RIGHT", -LAYOUT.RIGHT_MARGIN, 0)
        self.currentY = self.currentY - LAYOUT.HEADER_HEIGHT
        self.columns.LEFT, self.columns.RIGHT = {}, {}
        return header
    end
    
    -- Add column-specific section headers (independent headers per column)
    function layout:AddColumnSections(leftText, rightText)
        self.currentY = self.currentY - LAYOUT.SECTION_SPACING
        
        -- Left column header
        local leftHeader = Components.CreateSectionHeader(self.parent, leftText)
        leftHeader:SetPoint("TOPLEFT", COL_X.LEFT, self.currentY)
        leftHeader:SetWidth(LAYOUT.COLUMN_WIDTH)
        
        -- Right column header (only if provided)
        local rightHeader
        if rightText then
            rightHeader = Components.CreateSectionHeader(self.parent, rightText)
            rightHeader:SetPoint("TOPLEFT", COL_X.RIGHT, self.currentY)
            rightHeader:SetWidth(LAYOUT.COLUMN_WIDTH)
        end
        
        self.currentY = self.currentY - LAYOUT.HEADER_HEIGHT
        self.columns.LEFT, self.columns.RIGHT = {}, {}
        return leftHeader, rightHeader
    end
    
    -- Generic add module (works for both columns)
    function layout:AddModule(col, label, moduleKey, tooltip)
        local toggle = Components.CreateModuleToggle(self.parent, label, moduleKey, tooltip)
        toggle:SetPoint("TOPLEFT", COL_X[col], self.currentY)
        toggle:SetWidth(LAYOUT.COLUMN_WIDTH)
        table.insert(self.columns[col], toggle)
        table.insert(self.allModules, toggle)
        return toggle
    end
    
    -- Convenience wrappers
    function layout:AddModuleLeft(l, k, t) return self:AddModule("LEFT", l, k, t) end
    function layout:AddModuleRight(l, k, t) return self:AddModule("RIGHT", l, k, t) end
    
    -- Generic sub-component adder
    local function addSubComponent(self, col, creator, ...)
        local y = getColumnY(self.columns[col])
        local widget = creator(self.parent, ...)
        widget:SetPoint("TOPLEFT", COL_X[col], y)
        widget:SetWidth(LAYOUT.COLUMN_WIDTH)
        table.insert(self.columns[col], widget)
        return widget
    end
    
    -- Sub-checkbox
    function layout:AddSubCheckbox(col, label, optionKey, tooltip, parentToggle)
        return addSubComponent(self, col, Components.CreateSubCheckbox, label, optionKey, tooltip, parentToggle)
    end
    function layout:AddSubCheckboxLeft(l, k, t, p) return self:AddSubCheckbox("LEFT", l, k, t, p) end
    function layout:AddSubCheckboxRight(l, k, t, p) return self:AddSubCheckbox("RIGHT", l, k, t, p) end
    
    -- Sub-slider
    function layout:AddSubSlider(col, label, optionKey, min, max, step, tooltip, parentToggle)
        return addSubComponent(self, col, Components.CreateSubSlider, label, optionKey, min, max, step, tooltip, parentToggle)
    end
    function layout:AddSubSliderLeft(l, k, mn, mx, s, t, p) return self:AddSubSlider("LEFT", l, k, mn, mx, s, t, p) end
    function layout:AddSubSliderRight(l, k, mn, mx, s, t, p) return self:AddSubSlider("RIGHT", l, k, mn, mx, s, t, p) end
    
    -- Sub-dropdown
    function layout:AddSubDropdown(col, label, optionKey, options, tooltip, parentToggle)
        return addSubComponent(self, col, Components.CreateSubDropdown, label, optionKey, options, tooltip, parentToggle)
    end
    function layout:AddSubDropdownLeft(l, k, o, t, p) return self:AddSubDropdown("LEFT", l, k, o, t, p) end
    function layout:AddSubDropdownRight(l, k, o, t, p) return self:AddSubDropdown("RIGHT", l, k, o, t, p) end
    
    -- Advance to next row
    function layout:NextRow()
        local leftH, rightH = 0, 0
        for _, item in ipairs(self.columns.LEFT) do leftH = leftH + (item:GetHeight() or LAYOUT.SUB_OPTION_HEIGHT) end
        for _, item in ipairs(self.columns.RIGHT) do rightH = rightH + (item:GetHeight() or LAYOUT.SUB_OPTION_HEIGHT) end
        self.currentY = self.currentY - math.max(leftH, rightH) - 8
        self.columns.LEFT, self.columns.RIGHT = {}, {}
    end
    
    function layout:Finalize() return math.abs(self.currentY) + 30 end
    
    function layout:RefreshAll()
        for _, module in ipairs(self.allModules) do
            if module.Refresh then module:Refresh() end
        end
    end
    
    return layout
end

----------------------------------------------
-- Tab 1: General
----------------------------------------------
local function SetupGeneralTab(parent)
    local container = CreateTabContainer(parent)
    local content = container.content
    
    local infoBox = Components.CreateInfoBox(content, L.ADDON_NAME, addon.VERSION, L.ADDON_DESCRIPTION)
    infoBox:SetPoint("TOP", 0, -10)
    infoBox:SetPoint("LEFT", 15, 0)
    infoBox:SetPoint("RIGHT", -15, 0)
    
    local layout = CreateTwoColumnLayout(content)
    layout.currentY = -95
    
    -- AUTOMATION SECTION
    layout:AddColumnSections(L.MODULE_AUTO_SELL, L.MODULE_AUTO_REPAIR)
    
    local sellToggle = layout:AddModuleLeft(L.MODULE_AUTO_SELL, "AutoSellJunk", L.TIP_SELL_NOTIFY)
    local repairToggle = layout:AddModuleRight(L.MODULE_AUTO_REPAIR, "AutoRepair", L.TIP_REPAIR_NOTIFY)
    layout:NextRow()
    
    layout:AddSubCheckboxLeft(L.SHOW_NOTIFICATIONS, "AutoSellJunk_ShowNotify", L.TIP_SELL_NOTIFY, sellToggle)
    layout:AddSubCheckboxLeft(L.SELL_KNOWN_TRANSMOG, "AutoSellJunk_SellKnownTransmog", L.TIP_SELL_KNOWN_TRANSMOG, sellToggle)
    layout:AddSubCheckboxLeft(L.KEEP_TRANSMOG, "AutoSellJunk_KeepTransmog", L.TIP_KEEP_TRANSMOG, sellToggle)
    layout:AddSubCheckboxLeft(L.SELL_LOW_ILVL, "AutoSellJunk_SellLowILvl", L.TIP_SELL_LOW_ILVL, sellToggle)
    layout:AddSubSliderLeft("Max iLvl", "AutoSellJunk_MaxILvl", 0, 700, 10, L.TIP_MAX_ILVL, sellToggle)
    
    layout:AddSubCheckboxRight(L.USE_GUILD_FUNDS, "AutoRepair_UseGuild", L.TIP_USE_GUILD_FUNDS, repairToggle)
    layout:AddSubCheckboxRight(L.SHOW_NOTIFICATIONS, "AutoRepair_ShowNotify", L.TIP_REPAIR_NOTIFY, repairToggle)
    layout:NextRow()
    
    -- QUESTING SECTION
    layout:AddColumnSections(L.MODULE_AUTO_QUEST, L.MODULE_SKIP_CINEMATICS)
    
    local questToggle = layout:AddModuleLeft(L.MODULE_AUTO_QUEST, "AutoQuest", L.TIP_AUTO_ACCEPT)
    local cinToggle = layout:AddModuleRight(L.MODULE_SKIP_CINEMATICS, "SkipCinematics", L.TIP_ALWAYS_SKIP)
    layout:NextRow()
    
    layout:AddSubCheckboxLeft(L.AUTO_ACCEPT, "AutoQuest_Accept", L.TIP_AUTO_ACCEPT, questToggle)
    layout:AddSubCheckboxLeft(L.AUTO_TURNIN, "AutoQuest_TurnIn", L.TIP_AUTO_TURNIN, questToggle)
    layout:AddSubCheckboxLeft(L.SKIP_GOSSIP, "AutoQuest_SkipGossip", L.TIP_SKIP_GOSSIP, questToggle)
    layout:AddSubCheckboxLeft(L.AUTO_SINGLE_OPTION, "AutoQuest_SingleOption", L.TIP_AUTO_SINGLE_OPTION, questToggle)
    layout:AddSubCheckboxLeft(L.AUTO_CONTINUE_DIALOGUE, "AutoQuest_ContinueDialogue", L.TIP_AUTO_CONTINUE_DIALOGUE, questToggle)
    layout:AddSubCheckboxLeft(L.DAILY_QUESTS_ONLY, "AutoQuest_DailyOnly", L.TIP_DAILY_ONLY, questToggle)
    layout:AddSubDropdownLeft(L.MODIFIER_KEY, "AutoQuest_ModifierKey", C.MODIFIER_OPTIONS, nil, questToggle)
    
    layout:AddSubCheckboxRight(L.ALWAYS_SKIP, "SkipCinematics_AlwaysSkip", L.TIP_ALWAYS_SKIP, cinToggle)
    layout:AddSubDropdownRight(L.MODIFIER_KEY, "SkipCinematics_ModifierKey", C.MODIFIER_OPTIONS, nil, cinToggle)
    layout:NextRow()
    
    -- LOOTING SECTION
    layout:AddColumnSections(L.MODULE_FAST_LOOT, L.MODULE_LOOT_TOAST)
    
    local lootToggle = layout:AddModuleLeft(L.MODULE_FAST_LOOT, "FastLoot", "Instantly loot all items.")
    local toastToggle = layout:AddModuleRight(L.MODULE_LOOT_TOAST, "LootToast", "Display loot notifications.")
    layout:NextRow()
    
    layout:AddSubSliderRight(L.LOOT_TOAST_DURATION, "LootToast_Duration", 2, 10, 1, L.TIP_LOOT_TOAST_DURATION, toastToggle)
    layout:AddSubSliderRight(L.LOOT_TOAST_MAX_VISIBLE, "LootToast_MaxVisible", 3, 10, 1, L.TIP_LOOT_TOAST_MAX, toastToggle)
    layout:AddSubCheckboxRight(L.LOOT_TOAST_SHOW_CURRENCY, "LootToast_ShowCurrency", L.TIP_LOOT_TOAST_CURRENCY, toastToggle)
    layout:AddSubCheckboxRight(L.LOOT_TOAST_SHOW_QUANTITY, "LootToast_ShowQuantity", L.TIP_LOOT_TOAST_QUANTITY, toastToggle)
    layout:NextRow()
    
    -- DISPLAY SECTION
    layout:AddColumnSections(L.MODULE_QUEST_NAMEPLATES, L.MODULE_COMBAT_FADE)
    
    local npToggle = layout:AddModuleLeft(L.MODULE_QUEST_NAMEPLATES, "QuestNameplates", L.TIP_QUEST_NAMEPLATES)
    local fadeToggle = layout:AddModuleRight(L.MODULE_COMBAT_FADE, "CombatFade", L.TIP_COMBAT_FADE)
    layout:NextRow()
    
    layout:AddSubCheckboxLeft(L.SHOW_KILL_ICON, "QuestNameplates_ShowKillIcon", nil, npToggle)
    layout:AddSubCheckboxLeft(L.SHOW_LOOT_ICON, "QuestNameplates_ShowLootIcon", nil, npToggle)
    
    layout:AddSubCheckboxRight(L.COMBAT_FADE_ACTION_BARS, "CombatFade_ActionBars", L.TIP_COMBAT_FADE_ACTION_BARS, fadeToggle)
    layout:AddSubSliderRight("Action Bar Opacity", "CombatFade_ActionBars_Opacity", 0, 100, 5, L.TIP_COMBAT_FADE_ACTION_BARS_OPACITY, fadeToggle)
    layout:AddSubCheckboxRight(L.COMBAT_FADE_PLAYER_FRAME, "CombatFade_PlayerFrame", L.TIP_COMBAT_FADE_PLAYER_FRAME, fadeToggle)
    layout:AddSubSliderRight("Player Frame Opacity", "CombatFade_PlayerFrame_Opacity", 0, 100, 5, L.TIP_COMBAT_FADE_PLAYER_FRAME_OPACITY, fadeToggle)
    layout:NextRow()
    
    -- CAMERA SECTION (single column, uses full-width section)
    layout:AddSection(L.MODULE_ACTIONCAM)
    
    local camToggle = layout:AddModuleLeft(L.MODULE_ACTIONCAM, "ActionCam", L.TIP_ACTIONCAM)
    layout:NextRow()
    
    layout:AddSubDropdownLeft(L.ACTIONCAM_MODE, "ActionCam_Mode", C.ACTIONCAM_MODE_OPTIONS, nil, camToggle)
    layout:NextRow()
    
    -- CONFIRMATIONS SECTION
    layout:AddColumnSections(L.MODULE_AUTO_CONFIRM, L.MODULE_AUTO_INVITE)
    
    local confirmToggle = layout:AddModuleLeft(L.MODULE_AUTO_CONFIRM, "AutoConfirm", "Auto-confirm ready checks, summons, etc.")
    local inviteToggle = layout:AddModuleRight(L.MODULE_AUTO_INVITE, "AutoInvite", "Accept invites from trusted sources.")
    layout:NextRow()
    
    layout:AddSubCheckboxLeft(L.CONFIRM_READY_CHECK, "AutoConfirm_ReadyCheck", L.TIP_READY_CHECK, confirmToggle)
    layout:AddSubCheckboxLeft(L.CONFIRM_SUMMON, "AutoConfirm_Summon", L.TIP_SUMMON, confirmToggle)
    layout:AddSubCheckboxLeft(L.CONFIRM_ROLE_CHECK, "AutoConfirm_RoleCheck", L.TIP_ROLE_CHECK, confirmToggle)
    layout:AddSubCheckboxLeft(L.CONFIRM_RESURRECT, "AutoConfirm_Resurrect", L.TIP_RESURRECT, confirmToggle)
    layout:AddSubCheckboxLeft(L.CONFIRM_BINDING, "AutoConfirm_Binding", L.TIP_BINDING, confirmToggle)
    layout:AddSubCheckboxLeft(L.CONFIRM_DELETE_GREY, "AutoConfirm_DeleteGrey", L.TIP_DELETE_GREY, confirmToggle)
    
    layout:AddSubCheckboxRight(L.INVITE_FRIENDS, "AutoInvite_Friends", L.TIP_INVITE_FRIENDS, inviteToggle)
    layout:AddSubCheckboxRight(L.INVITE_BNET, "AutoInvite_BNetFriends", L.TIP_INVITE_BNET, inviteToggle)
    layout:AddSubCheckboxRight(L.INVITE_GUILD, "AutoInvite_Guild", L.TIP_INVITE_GUILD, inviteToggle)
    layout:AddSubCheckboxRight(L.INVITE_GUILD_INVITES, "AutoInvite_GuildInvites", L.TIP_GUILD_INVITES, inviteToggle)
    layout:NextRow()
    
    -- AUTO-RELEASE SECTION (single column, uses full-width section)
    layout:AddSection(L.MODULE_AUTO_RELEASE)
    
    local releaseToggle = layout:AddModuleLeft(L.MODULE_AUTO_RELEASE, "AutoRelease", "Release spirit automatically.")
    layout:NextRow()
    
    layout:AddSubDropdownLeft(L.RELEASE_MODE, "AutoRelease_Mode", C.RELEASE_MODE_OPTIONS, nil, releaseToggle)
    layout:AddSubCheckboxLeft(L.SHOW_NOTIFICATIONS, "AutoRelease_Notify", L.TIP_RELEASE_NOTIFY, releaseToggle)
    layout:NextRow()
    
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    
    return container
end

----------------------------------------------
-- Tab 2: Tooltip
----------------------------------------------
local function SetupTooltipTab(parent)
    local container = CreateTabContainer(parent)
    local content = container.content
    
    local layout = CreateTwoColumnLayout(content)
    layout.currentY = -15
    
    layout:AddSection(L.MODULE_TOOLTIP_PLUS)
    local tooltipToggle = layout:AddModuleLeft("Enable Tooltip+", "TooltipPlus", "Enhanced tooltip features")
    layout:NextRow()
    
    -- POSITIONING
    layout:AddSection("Positioning")
    
    -- Anchor dropdown (left column)
    local anchorFrame = CreateFrame("Frame", nil, content)
    anchorFrame:SetHeight(32)
    anchorFrame:SetPoint("TOPLEFT", COL_X.LEFT, layout.currentY)
    anchorFrame:SetWidth(LAYOUT.COLUMN_WIDTH)
    
    local anchorLabel = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    anchorLabel:SetPoint("LEFT", 0, 0)
    anchorLabel:SetText(L.TOOLTIP_ANCHOR)
    
    local anchorDropdown = CreateFrame("DropdownButton", nil, anchorFrame, "WowStyle1DropdownTemplate")
    anchorDropdown:SetWidth(140)
    anchorDropdown:SetPoint("LEFT", anchorLabel, "RIGHT", 10, 0)
    
    MenuUtil.CreateRadioMenu(anchorDropdown,
        function(value) return addon.GetDBValue("TooltipPlus_Anchor") == value end,
        function(value) addon.SetDBValue("TooltipPlus_Anchor", value, true) end,
        { L.ANCHOR_DEFAULT, "DEFAULT" }, { L.ANCHOR_MOUSE, "MOUSE" },
        { L.ANCHOR_TOPLEFT, "TOPLEFT" }, { L.ANCHOR_TOPRIGHT, "TOPRIGHT" },
        { L.ANCHOR_BOTTOMLEFT, "BOTTOMLEFT" }, { L.ANCHOR_BOTTOMRIGHT, "BOTTOMRIGHT" }
    )
    
    -- Mouse side dropdown (right column)
    local sideFrame = CreateFrame("Frame", nil, content)
    sideFrame:SetHeight(32)
    sideFrame:SetPoint("TOPLEFT", COL_X.RIGHT, layout.currentY)
    sideFrame:SetWidth(LAYOUT.COLUMN_WIDTH)
    
    local sideLabel = sideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sideLabel:SetPoint("LEFT", 0, 0)
    sideLabel:SetText(L.TOOLTIP_MOUSE_SIDE)
    
    local sideDropdown = CreateFrame("DropdownButton", nil, sideFrame, "WowStyle1DropdownTemplate")
    sideDropdown:SetWidth(100)
    sideDropdown:SetPoint("LEFT", sideLabel, "RIGHT", 10, 0)
    
    MenuUtil.CreateRadioMenu(sideDropdown,
        function(value) return addon.GetDBValue("TooltipPlus_MouseSide") == value end,
        function(value) addon.SetDBValue("TooltipPlus_MouseSide", value, true) end,
        { L.SIDE_RIGHT, "RIGHT" }, { L.SIDE_LEFT, "LEFT" }, { L.SIDE_TOP, "TOP" }
    )
    
    layout.currentY = layout.currentY - 40
    
    -- APPEARANCE
    layout:AddSection("Appearance")
    layout:AddSubCheckboxLeft(L.TOOLTIP_CLASS_COLORS, "TooltipPlus_ClassColors", "Color the tooltip border based on class (players) or reaction (NPCs).", tooltipToggle)
    layout:AddSubCheckboxLeft(L.TOOLTIP_RARITY_BORDER, "TooltipPlus_RarityBorder", "Color item tooltip borders based on item quality/rarity.", tooltipToggle)
    layout:AddSubCheckboxLeft(L.TOOLTIP_SHOW_TRANSMOG, "TooltipPlus_ShowTransmog", "Show whether an item's appearance is collected in the tooltip.", tooltipToggle)
    layout:NextRow()
    
    -- TRANSMOG OVERLAY
    layout:AddSection("Transmog Overlay")
    layout:AddSubCheckboxLeft(L.TOOLTIP_TRANSMOG_OVERLAY, "TooltipPlus_TransmogOverlay", "Show collection status icons on item buttons in bags, vendors, and loot windows.", tooltipToggle)
    layout:AddSubDropdownLeft(L.TOOLTIP_TRANSMOG_CORNER, "TooltipPlus_TransmogCorner", C.CORNER_OPTIONS, "Which corner to display the transmog collection icon.", tooltipToggle)
    layout:NextRow()
    
    -- HIDE ELEMENTS
    layout:AddSection("Hide Elements")
    layout:AddSubCheckboxLeft(L.TOOLTIP_HIDE_HEALTHBAR, "TooltipPlus_HideHealthbar", "Hide the health bar shown below unit tooltips.", tooltipToggle)
    layout:AddSubCheckboxLeft(L.TOOLTIP_HIDE_GUILD, "TooltipPlus_HideGuild", "Hide the guild name line from player tooltips.", tooltipToggle)
    layout:AddSubCheckboxLeft(L.TOOLTIP_HIDE_FACTION, "TooltipPlus_HideFaction", "Hide the faction (Alliance/Horde) line from unit tooltips.", tooltipToggle)
    layout:AddSubCheckboxRight(L.TOOLTIP_HIDE_PVP, "TooltipPlus_HidePvP", "Hide the 'PvP' text from player tooltips.", tooltipToggle)
    layout:AddSubCheckboxRight(L.TOOLTIP_HIDE_REALM, "TooltipPlus_HideRealm", "Hide the realm name from cross-realm player names.", tooltipToggle)
    layout:NextRow()
    
    -- EXTRA INFO
    layout:AddSection("Extra Info")
    layout:AddSubCheckboxLeft(L.TOOLTIP_SHOW_ITEM_ID, "TooltipPlus_ShowItemID", "Display the item's database ID at the bottom of item tooltips.", tooltipToggle)
    layout:AddSubCheckboxRight(L.TOOLTIP_SHOW_SPELL_ID, "TooltipPlus_ShowSpellID", "Display the spell's database ID at the bottom of spell tooltips.", tooltipToggle)
    layout:NextRow()
    
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    
    return container
end

----------------------------------------------
-- Tab 3: Chat
----------------------------------------------
local function SetupChatTab(parent)
    local container = CreateTabContainer(parent)
    local content = container.content
    
    local layout = CreateTwoColumnLayout(content)
    layout.currentY = -15
    
    layout:AddSection(L.MODULE_CHAT_PLUS or "Chat Plus")
    local chatToggle = layout:AddModuleLeft("Enable Chat+", "ChatPlus", "Enhanced chat features")
    layout:NextRow()
    
    layout:AddSection("Features")
    
    local wowheadCb = layout:AddSubCheckboxLeft(L.CHAT_WOWHEAD_LOOKUP or "Wowhead Lookup", "ChatPlus_WowheadLookup", nil, chatToggle)
    
    local wowheadHint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    wowheadHint:SetPoint("TOPLEFT", wowheadCb, "BOTTOMLEFT", LAYOUT.SUB_OPTION_INDENT, -2)
    wowheadHint:SetText("Shift+Click on links to get Wowhead URL")
    wowheadHint:SetTextColor(0.5, 0.5, 0.5)
    wowheadHint:SetWidth(LAYOUT.COLUMN_WIDTH - LAYOUT.SUB_OPTION_INDENT)
    wowheadHint:SetJustifyH("LEFT")
    
    layout:AddSubCheckboxLeft(L.CHAT_CLICKABLE_URLS or "Clickable URLs", "ChatPlus_ClickableURLs", nil, chatToggle)
    layout:AddSubCheckboxLeft(L.CHAT_COPY_BUTTON or "Show Copy Button", "ChatPlus_CopyButton", nil, chatToggle)
    layout:NextRow()
    
    content:SetHeight(math.max(layout:Finalize(), 300))
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    
    return container
end

----------------------------------------------
-- Tab Configuration
----------------------------------------------
local TabSetups = {
    { name = L.SETTINGS_GENERAL, callback = SetupGeneralTab },
    { name = L.SETTINGS_TOOLTIP, callback = SetupTooltipTab },
    { name = L.SETTINGS_CHAT, callback = SetupChatTab },
}

----------------------------------------------
-- Session State Management
----------------------------------------------
local sessionStartValues = {}

local function SaveSessionState()
    sessionStartValues = {}
    if RefactorDB then
        for k, v in pairs(RefactorDB) do sessionStartValues[k] = v end
    end
end

local function RestoreSessionState()
    if RefactorDB and next(sessionStartValues) then
        for k, v in pairs(sessionStartValues) do RefactorDB[k] = v end
        if addon.ReloadModules then addon.ReloadModules() end
    end
end

local function ResetToDefaults()
    if addon.DEFAULT_SETTINGS and RefactorDB then
        for k, v in pairs(addon.DEFAULT_SETTINGS) do
            RefactorDB[k] = v
            addon.SetDBValue(k, v, true)
        end
        if frame and containers then
            for _, c in ipairs(containers) do
                if c.layout and c.layout.RefreshAll then c.layout:RefreshAll() end
            end
        end
        print("|cff00ff00Refactor:|r All settings reset to defaults.")
    end
end

----------------------------------------------
-- Create Main Frame
----------------------------------------------
local function CreateSettingsFrame()
    if frame then return frame end
    
    frame = CreateFrame("Frame", "RefactorSettingsDialog", UIParent, "SettingsFrameTemplate")
    frame:SetToplevel(true)
    frame:SetSize(LAYOUT.PANEL_WIDTH, LAYOUT.PANEL_HEIGHT)
    frame:SetPoint("CENTER", 0, 50)
    frame:SetFrameStrata("HIGH")
    frame:Raise()
    
    frame.NineSlice.Text:SetText(L.SETTINGS_TITLE)
    
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(5, 0, 0, 0)
    
    -- Drag handle
    local dragHandle = CreateFrame("Frame", nil, frame)
    dragHandle:SetPoint("TOPLEFT", 4, 0)
    dragHandle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -28, -24)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnEnter", function() SetCursor("Interface/CURSOR/UI-Cursor-Move.crosshair") end)
    dragHandle:SetScript("OnLeave", function() SetCursor(nil) end)
    dragHandle:SetScript("OnDragStart", function() frame:SetMovable(true); frame:StartMoving() end)
    dragHandle:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    frame:EnableMouse(true)
    frame:SetMouseClickEnabled(true)
    frame:SetMouseMotionEnabled(true)
    frame:SetScript("OnMouseWheel", function() end)
    
    -- Inner content area
    local innerFrame = CreateFrame("Frame", nil, frame)
    innerFrame:SetPoint("TOPLEFT", 10, -60)
    innerFrame:SetPoint("BOTTOMRIGHT", -10, 45)
    innerFrame:SetClipsChildren(true)
    
    local bgLeft = innerFrame:CreateTexture(nil, "BACKGROUND")
    bgLeft:SetAtlas("Options_InnerFrame")
    bgLeft:SetPoint("TOPLEFT", 0, 0)
    bgLeft:SetPoint("BOTTOMRIGHT", innerFrame, "BOTTOM", 0, 0)
    bgLeft:SetTexCoord(1, 0.64, 0, 1)
    
    local bgRight = innerFrame:CreateTexture(nil, "BACKGROUND")
    bgRight:SetAtlas("Options_InnerFrame")
    bgRight:SetPoint("TOPRIGHT", 0, 0)
    bgRight:SetPoint("BOTTOMLEFT", innerFrame, "BOTTOM", 0, 0)
    bgRight:SetTexCoord(0.64, 1, 0, 1)
    
    frame.InnerFrame = innerFrame
    
    -- Bottom buttons
    local defaultsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    defaultsBtn:SetSize(110, 24)
    defaultsBtn:SetPoint("BOTTOMLEFT", 15, 12)
    defaultsBtn:SetText(DEFAULTS or "Defaults")
    defaultsBtn:SetScript("OnClick", function()
        StaticPopupDialogs["REFACTOR_RESET_DEFAULTS"] = {
            text = "Reset all Refactor settings to their default values?",
            button1 = YES, button2 = NO,
            OnAccept = ResetToDefaults,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("REFACTOR_RESET_DEFAULTS")
    end)
    StyleButtonWithAtlas(defaultsBtn)
    
    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(110, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", -15, 12)
    cancelBtn:SetText(CANCEL or "Cancel")
    cancelBtn:SetScript("OnClick", function()
        RestoreSessionState()
        frame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)
    StyleButtonWithAtlas(cancelBtn)
    
    local okayBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okayBtn:SetSize(110, 24)
    okayBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -5, 0)
    okayBtn:SetText(OKAY or "Okay")
    okayBtn:SetScript("OnClick", function()
        frame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)
    StyleButtonWithAtlas(okayBtn)
    
    frame.DefaultsButton, frame.CancelButton, frame.OkayButton = defaultsBtn, cancelBtn, okayBtn
    
    table.insert(UISpecialFrames, frame:GetName())
    
    -- Create tabs
    local lastTab = nil
    for i, setup in ipairs(TabSetups) do
        local tabContainer = setup.callback(innerFrame)
        tabContainer:SetPoint("TOPLEFT", 5, -5)
        tabContainer:SetPoint("BOTTOMRIGHT", -5, 5)
        tabContainer:Hide()
        
        local tabButton = Components.CreateTab(frame, setup.name)
        if lastTab then
            tabButton:SetPoint("LEFT", lastTab, "RIGHT", 4, 0)
        else
            tabButton:SetPoint("BOTTOMLEFT", innerFrame, "TOPLEFT", 5, 0)
        end
        lastTab = tabButton
        tabContainer.button = tabButton
        
        tabButton:SetScript("OnClick", function()
            for _, c in ipairs(containers) do
                if c.button.Deselect then c.button:Deselect() end
                c:Hide()
            end
            if tabButton.Select then tabButton:Select() end
            tabContainer:Show()
        end)
        
        table.insert(tabs, tabButton)
        table.insert(containers, tabContainer)
    end
    
    frame.Tabs = tabs
    containers[1].button:Click()
    
    frame:SetScript("OnShow", SaveSessionState)
    frame:Hide()
    
    return frame
end

----------------------------------------------
-- Public Functions
----------------------------------------------
function SettingsPanel:Toggle()
    if not frame then CreateSettingsFrame() end
    frame:SetShown(not frame:IsShown())
end

function SettingsPanel:Show()
    if not frame then CreateSettingsFrame() end
    frame:Show()
end

function SettingsPanel:Hide()
    if frame then frame:Hide() end
end

----------------------------------------------
-- Initialize
----------------------------------------------
addon.CallbackRegistry:Register("AddonLoaded", function()
    C_Timer.After(1, CreateSettingsFrame)
end)
