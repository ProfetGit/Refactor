-- Refactor Addon - Settings Main Panel
-- Sidebar navigation layout (WoW Game Menu style)

local addonName, addon = ...
local L = addon.L
local Components = addon.SettingsUI
local C = addon.Constants

----------------------------------------------
-- Panel State
----------------------------------------------
local SettingsPanel = {}
addon.SettingsPanel = SettingsPanel

local frame, sidebarButtons, contentPanels = nil, {}, {}
local selectedCategory = nil

----------------------------------------------
-- Layout Constants
----------------------------------------------
local LAYOUT = {
    PANEL_WIDTH = 820,
    PANEL_HEIGHT = 660,
    SIDEBAR_WIDTH = 180,
    CONTENT_MARGIN = 15,
    CATEGORY_HEIGHT = 24,
    SUBCATEGORY_HEIGHT = 22,
    SUBCATEGORY_INDENT = 16,
    SECTION_SPACING = 18,
    ROW_HEIGHT = 24,
    SUB_OPTION_HEIGHT = 22,
    SUB_OPTION_INDENT = 22,
    HEADER_HEIGHT = 28,
    MODULE_HEIGHT = 26,
}

----------------------------------------------
-- Smooth Scroll Constants
----------------------------------------------
local SCROLL_SPEED, SCROLL_SMOOTHNESS, SCROLL_THRESHOLD = 50, 0.22, 0.5
local SCROLL_STEP = 30

----------------------------------------------
-- Category Configuration
-- Organized into logical groups for intuitive navigation
----------------------------------------------
local CATEGORIES = {
    {
        name = "Gameplay",
        subcategories = {
            { key = "questing", name = "Questing" }, -- Auto Quest + Skip Cinematics
            { key = "looting",  name = "Looting" },  -- Fast Loot + Loot Toasts
            { key = "camera",   name = "Camera" },   -- Action Camera
        }
    },
    {
        name = "Automation",
        subcategories = {
            { key = "vendors",       name = "Vendors" },       -- Auto Sell + Auto Repair
            { key = "confirmations", name = "Confirmations" }, -- Ready check, summon, etc.
            { key = "social",        name = "Social" },        -- Auto Invite + Auto Release
        }
    },
    {
        name = "Interface",
        subcategories = {
            { key = "tooltips",   name = "Tooltips" },   -- Tooltip+
            { key = "nameplates", name = "Nameplates" }, -- Quest Nameplates
            { key = "frames",     name = "Frames" },     -- Combat Fade
        }
    },
}

----------------------------------------------
-- Atlas Button Helper (3-Part Red Button)
----------------------------------------------
local function StyleButtonWithAtlas(button)
    if button.Left then button.Left:Hide() end
    if button.Middle then button.Middle:Hide() end
    if button.Right then button.Right:Hide() end

    local function CreateButtonTextures(suffix, layer)
        local btnHeight = button:GetHeight()
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

    button.normalTex = CreateButtonTextures("", "BACKGROUND")
    button.pushedTex = CreateButtonTextures("-Pressed", "BACKGROUND")
    button.pushedTex.left:Hide()
    button.pushedTex.center:Hide()
    button.pushedTex.right:Hide()

    button.disabledTex = CreateButtonTextures("-Disabled", "BACKGROUND")
    button.disabledTex.left:Hide()
    button.disabledTex.center:Hide()
    button.disabledTex.right:Hide()

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("128-RedButton-Highlight", false)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")

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

    button:HookScript("OnLeave", function(self)
        if self:IsEnabled() then
            HideTexSet(self.pushedTex)
            ShowTexSet(self.normalTex)
        end
    end)

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

    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
    button:SetPushedTextOffset(0, -2)
end

----------------------------------------------
-- Helper: Create Scrollable Content Panel
----------------------------------------------
local function CreateScrollableContent(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -16, 5)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    content:SetHeight(1000)
    scrollFrame:SetScrollChild(content)

    -- Scrollbar constants
    local TRACK_WIDTH = 10
    local THUMB_WIDTH = 8
    local THUMB_MIN_SIZE = 18
    local STEPPER_RESERVE = 20
    local STEPPER_MARGIN_Y = 2
    local THUMB_MID_OFS_T = 8
    local THUMB_MID_OFS_B = 10

    local scrollBar = CreateFrame("Frame", nil, container)
    scrollBar:SetWidth(TRACK_WIDTH)
    scrollBar:SetPoint("TOPRIGHT", -4, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Up Arrow
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
    upPushed:SetPoint("CENTER", 0, -2)
    upButton:SetPushedTexture(upPushed)

    -- Down Arrow
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
    downPushed:SetPoint("CENTER", 0, 2)
    downButton:SetPushedTexture(downPushed)

    -- Track
    local track = CreateFrame("Frame", nil, scrollBar)
    track:SetPoint("TOP", 0, -STEPPER_RESERVE)
    track:SetPoint("BOTTOM", 0, STEPPER_RESERVE)
    track:SetWidth(TRACK_WIDTH)

    local trackTop = track:CreateTexture(nil, "BACKGROUND")
    trackTop:SetAtlas("minimal-scrollbar-track-top", true)
    trackTop:SetPoint("TOP", 0, 1)

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

    local thumbTop = thumb:CreateTexture(nil, "BACKGROUND")
    thumbTop:SetAtlas("minimal-scrollbar-thumb-top", true)
    thumbTop:SetPoint("TOP", 0, 0)

    local thumbBot = thumb:CreateTexture(nil, "BACKGROUND")
    thumbBot:SetAtlas("minimal-scrollbar-thumb-bottom", true)
    thumbBot:SetPoint("BOTTOM", 0, 0)

    local thumbMid = thumb:CreateTexture(nil, "BACKGROUND", nil, -1)
    thumbMid:SetAtlas("minimal-scrollbar-thumb-middle", true)
    thumbMid:SetPoint("TOP", 0, -THUMB_MID_OFS_T)
    thumbMid:SetPoint("BOTTOM", 0, THUMB_MID_OFS_B)

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

    container.scrollFrame = scrollFrame
    container.scrollBar = scrollBar
    container.content = content
    container.UpdateScrollBar = UpdateScrollBar
    container.allControls = {}

    return container
end

----------------------------------------------
-- Content Layout Builder
----------------------------------------------
local function CreateContentLayout(parent)
    local layout = {
        parent = parent,
        currentY = -15,
        allModules = {},
        allControls = {}, -- Track ALL controls for refresh
        settingKeys = {}, -- Track all setting keys for per-tab reset
    }

    -- Get content width for single-column layout
    local contentWidth = parent:GetParent():GetWidth() - 40

    function layout:AddSection(text)
        self.currentY = self.currentY - LAYOUT.SECTION_SPACING
        local header = Components.CreateSectionHeader(self.parent, text)
        header:SetPoint("TOPLEFT", 0, self.currentY)
        header:SetPoint("RIGHT", -10, 0)
        self.currentY = self.currentY - LAYOUT.HEADER_HEIGHT
        return header
    end

    function layout:AddModule(label, moduleKey, tooltip)
        local toggle = Components.CreateModuleToggle(self.parent, label, moduleKey, tooltip)
        toggle:SetPoint("TOPLEFT", 0, self.currentY)
        toggle:SetWidth(contentWidth)
        table.insert(self.allModules, toggle)
        table.insert(self.allControls, toggle)
        if moduleKey then table.insert(self.settingKeys, moduleKey) end
        self.currentY = self.currentY - LAYOUT.MODULE_HEIGHT - 4
        return toggle
    end

    function layout:AddSubCheckbox(label, optionKey, tooltip, parentToggle)
        local widget = Components.CreateSubCheckbox(self.parent, label, optionKey, tooltip, parentToggle)
        widget:SetPoint("TOPLEFT", 0, self.currentY)
        widget:SetWidth(contentWidth)
        table.insert(self.allControls, widget)
        if optionKey then table.insert(self.settingKeys, optionKey) end
        self.currentY = self.currentY - LAYOUT.SUB_OPTION_HEIGHT - 4
        return widget
    end

    function layout:AddSubSlider(label, optionKey, min, max, step, tooltip, parentToggle)
        local widget = Components.CreateSubSlider(self.parent, label, optionKey, min, max, step, tooltip, parentToggle)
        widget:SetPoint("TOPLEFT", 0, self.currentY)
        widget:SetWidth(contentWidth)
        table.insert(self.allControls, widget)
        if optionKey then table.insert(self.settingKeys, optionKey) end
        self.currentY = self.currentY - 32
        return widget
    end

    function layout:AddSubDropdown(label, optionKey, options, tooltip, parentToggle)
        local widget = Components.CreateSubDropdown(self.parent, label, optionKey, options, tooltip, parentToggle)
        widget:SetPoint("TOPLEFT", 0, self.currentY)
        widget:SetWidth(contentWidth)
        table.insert(self.allControls, widget)
        if optionKey then table.insert(self.settingKeys, optionKey) end
        self.currentY = self.currentY - 32
        return widget
    end

    function layout:AddSpacer(height)
        self.currentY = self.currentY - (height or 10)
    end

    function layout:Finalize()
        return math.abs(self.currentY) + 30
    end

    function layout:RefreshAll()
        -- Refresh all controls (modules, checkboxes, sliders, dropdowns)
        for _, control in ipairs(self.allControls) do
            if control.Refresh then control:Refresh() end
        end
        -- Update sub-options enabled state based on parent module state
        for _, module in ipairs(self.allModules) do
            if module.moduleKey and module.UpdateSubOptionsState then
                local enabled = addon.GetDBBool(module.moduleKey)
                module:UpdateSubOptionsState(enabled)
            end
        end
    end

    -- Reset only this tab's settings to defaults
    function layout:ResetToDefaults()
        if addon.DEFAULT_SETTINGS and RefactorDB then
            for _, key in ipairs(self.settingKeys) do
                local defaultValue = addon.DEFAULT_SETTINGS[key]
                if defaultValue ~= nil then
                    RefactorDB[key] = defaultValue
                    addon.SetDBValue(key, defaultValue, true)
                end
            end
            self:RefreshAll()
        end
    end

    -- Add a per-tab defaults button at the top right corner (fixed position, not in scroll)
    function layout:AddDefaultsButton(container)
        -- Parent to container so it's fixed, not scrolling with content
        local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        btn:SetSize(80, 20)
        btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -8)
        btn:SetText("Defaults")
        btn:SetNormalFontObject(GameFontNormalSmall)
        btn:SetHighlightFontObject(GameFontHighlightSmall)

        -- Store reference to layout for the click handler
        local layoutRef = self
        btn:SetScript("OnClick", function()
            layoutRef:ResetToDefaults()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)

        -- Tooltip explaining this only affects current tab
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Reset Tab Settings", 1, 0.82, 0)
            GameTooltip:AddLine("Reset only the settings on this tab to their default values.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self.defaultsButton = btn
        return btn
    end

    return layout
end

----------------------------------------------
-- Content Panel Setup Functions
----------------------------------------------

-- QUESTING
local function SetupQuestingContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    -- Auto Quest
    layout:AddSection(L.MODULE_AUTO_QUEST or "Auto Quest")
    local questToggle = layout:AddModule(L.MODULE_AUTO_QUEST or "Auto Quest", "AutoQuest", L.TIP_AUTO_ACCEPT)
    layout:AddSubCheckbox(L.AUTO_ACCEPT or "Auto Accept", "AutoQuest_Accept", L.TIP_AUTO_ACCEPT, questToggle)
    layout:AddSubCheckbox(L.AUTO_TURNIN or "Auto Turn In", "AutoQuest_TurnIn", L.TIP_AUTO_TURNIN, questToggle)
    layout:AddSubCheckbox(L.SKIP_GOSSIP or "Skip Gossip", "AutoQuest_SkipGossip", L.TIP_SKIP_GOSSIP, questToggle)
    layout:AddSubCheckbox(L.AUTO_SINGLE_OPTION or "Auto Select Single Option", "AutoQuest_SingleOption",
        L.TIP_AUTO_SINGLE_OPTION, questToggle)
    layout:AddSubCheckbox(L.AUTO_CONTINUE_DIALOGUE or "Auto Continue Dialogue", "AutoQuest_ContinueDialogue",
        L.TIP_AUTO_CONTINUE_DIALOGUE, questToggle)
    layout:AddSubCheckbox(L.DAILY_QUESTS_ONLY or "Daily Quests Only", "AutoQuest_DailyOnly", L.TIP_DAILY_ONLY,
        questToggle)
    layout:AddSubDropdown(L.MODIFIER_KEY or "Modifier Key", "AutoQuest_ModifierKey", C.MODIFIER_OPTIONS, nil, questToggle)

    layout:AddSpacer(10)

    -- Cinematics
    layout:AddSection(L.MODULE_SKIP_CINEMATICS or "Skip Cinematics")
    local cinToggle = layout:AddModule(L.MODULE_SKIP_CINEMATICS or "Skip Cinematics", "SkipCinematics", L
        .TIP_ALWAYS_SKIP)
    layout:AddSubCheckbox(L.ALWAYS_SKIP or "Always Skip", "SkipCinematics_AlwaysSkip", L.TIP_ALWAYS_SKIP, cinToggle)
    layout:AddSubDropdown(L.MODIFIER_KEY or "Modifier Key", "SkipCinematics_ModifierKey", C.MODIFIER_OPTIONS, nil,
        cinToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

-- LOOTING (Fast Loot + Loot Toasts)
local function SetupLootingContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    -- Fast Loot
    layout:AddSection(L.MODULE_FAST_LOOT or "Fast Loot")
    layout:AddModule(L.MODULE_FAST_LOOT or "Fast Loot", "FastLoot", "Instantly loot all items from corpses.")

    layout:AddSpacer(10)

    -- Loot Toasts
    layout:AddSection(L.MODULE_LOOT_TOAST or "Loot Toasts")
    local toastToggle = layout:AddModule(L.MODULE_LOOT_TOAST or "Loot Toasts", "LootToast",
        "Display loot notifications on screen.")
    layout:AddSubSlider(L.LOOT_TOAST_DURATION or "Duration", "LootToast_Duration", 2, 10, 1, L.TIP_LOOT_TOAST_DURATION,
        toastToggle)
    layout:AddSubSlider(L.LOOT_TOAST_MAX_VISIBLE or "Max Visible", "LootToast_MaxVisible", 3, 10, 1, L
        .TIP_LOOT_TOAST_MAX, toastToggle)
    layout:AddSubCheckbox(L.LOOT_TOAST_SHOW_CURRENCY or "Show Currency", "LootToast_ShowCurrency",
        L.TIP_LOOT_TOAST_CURRENCY, toastToggle)
    layout:AddSubCheckbox(L.LOOT_TOAST_SHOW_QUANTITY or "Show Quantity", "LootToast_ShowQuantity",
        L.TIP_LOOT_TOAST_QUANTITY, toastToggle)

    layout:AddSpacer(5)

    -- Filtering Section
    layout:AddSection("Filtering")
    layout:AddSubDropdown(L.LOOT_TOAST_MIN_QUALITY or "Minimum Quality", "LootToast_MinQuality",
        C.LOOT_QUALITY_OPTIONS, L.TIP_LOOT_TOAST_MIN_QUALITY, toastToggle)
    layout:AddSubCheckbox(L.LOOT_TOAST_ALWAYS_SHOW_UNCOLLECTED or "Always Show Uncollected Transmog",
        "LootToast_AlwaysShowUncollected", L.TIP_LOOT_TOAST_ALWAYS_SHOW_UNCOLLECTED, toastToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

-- VENDORS
local function SetupVendorsContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    -- Auto Sell
    layout:AddSection(L.MODULE_AUTO_SELL or "Auto Sell Junk")
    local sellToggle = layout:AddModule(L.MODULE_AUTO_SELL or "Auto Sell Junk", "AutoSellJunk", L.TIP_SELL_NOTIFY)
    layout:AddSubCheckbox(L.SHOW_NOTIFICATIONS or "Show Notifications", "AutoSellJunk_ShowNotify", L.TIP_SELL_NOTIFY,
        sellToggle)
    layout:AddSubCheckbox(L.SELL_KNOWN_TRANSMOG or "Sell Known Transmog", "AutoSellJunk_SellKnownTransmog",
        L.TIP_SELL_KNOWN_TRANSMOG, sellToggle)
    layout:AddSubCheckbox(L.KEEP_TRANSMOG or "Keep Uncollected Transmog", "AutoSellJunk_KeepTransmog",
        L.TIP_KEEP_TRANSMOG, sellToggle)
    layout:AddSubCheckbox(L.SELL_LOW_ILVL or "Sell Low iLvl Gear", "AutoSellJunk_SellLowILvl", L.TIP_SELL_LOW_ILVL,
        sellToggle)
    layout:AddSubSlider("Max iLvl", "AutoSellJunk_MaxILvl", 0, 700, 10, L.TIP_MAX_ILVL, sellToggle)

    layout:AddSpacer(10)

    -- Auto Repair
    layout:AddSection(L.MODULE_AUTO_REPAIR or "Auto Repair")
    local repairToggle = layout:AddModule(L.MODULE_AUTO_REPAIR or "Auto Repair", "AutoRepair", L.TIP_REPAIR_NOTIFY)
    layout:AddSubCheckbox(L.USE_GUILD_FUNDS or "Use Guild Funds", "AutoRepair_UseGuild", L.TIP_USE_GUILD_FUNDS,
        repairToggle)
    layout:AddSubCheckbox(L.SHOW_NOTIFICATIONS or "Show Notifications", "AutoRepair_ShowNotify", L.TIP_REPAIR_NOTIFY,
        repairToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

-- CONFIRMATIONS
local function SetupConfirmationsContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    layout:AddSection(L.MODULE_AUTO_CONFIRM or "Auto Confirm")
    local confirmToggle = layout:AddModule(L.MODULE_AUTO_CONFIRM or "Auto Confirm", "AutoConfirm",
        "Auto-confirm ready checks, summons, and more.")
    layout:AddSubCheckbox(L.CONFIRM_READY_CHECK or "Ready Check", "AutoConfirm_ReadyCheck", L.TIP_READY_CHECK,
        confirmToggle)
    layout:AddSubCheckbox(L.CONFIRM_SUMMON or "Summon", "AutoConfirm_Summon", L.TIP_SUMMON, confirmToggle)
    layout:AddSubCheckbox(L.CONFIRM_ROLE_CHECK or "Role Check", "AutoConfirm_RoleCheck", L.TIP_ROLE_CHECK, confirmToggle)
    layout:AddSubCheckbox(L.CONFIRM_RESURRECT or "Resurrect", "AutoConfirm_Resurrect", L.TIP_RESURRECT, confirmToggle)
    layout:AddSubCheckbox(L.CONFIRM_BINDING or "Bind Confirmation", "AutoConfirm_Binding", L.TIP_BINDING, confirmToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

-- TOOLTIPS
local function SetupTooltipsContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    layout:AddSection(L.MODULE_TOOLTIP_PLUS or "Tooltip+")
    local tooltipToggle = layout:AddModule("Enable Tooltip+", "TooltipPlus", "Enhanced tooltip features")

    layout:AddSpacer(5)

    -- Positioning
    layout:AddSection("Positioning")
    layout:AddSubDropdown(L.TOOLTIP_ANCHOR or "Anchor Position", "TooltipPlus_Anchor", C.TOOLTIP_ANCHOR_OPTIONS, nil,
        tooltipToggle)
    layout:AddSubDropdown(L.TOOLTIP_MOUSE_SIDE or "Mouse Side", "TooltipPlus_MouseSide", C.MOUSE_SIDE_OPTIONS, nil,
        tooltipToggle)

    layout:AddSpacer(5)

    -- Appearance
    layout:AddSection("Appearance")
    layout:AddSubCheckbox(L.TOOLTIP_CLASS_COLORS or "Class Color Border", "TooltipPlus_ClassColors",
        "Color border based on class/reaction.", tooltipToggle)
    layout:AddSubCheckbox(L.TOOLTIP_RARITY_BORDER or "Rarity Border", "TooltipPlus_RarityBorder",
        "Color item borders by quality.", tooltipToggle)
    layout:AddSubCheckbox(L.TOOLTIP_SHOW_TRANSMOG or "Show Transmog Status", "TooltipPlus_ShowTransmog",
        "Show collection status on items.", tooltipToggle)

    layout:AddSpacer(5)

    -- Transmog Overlay
    layout:AddSection("Transmog Overlay")
    layout:AddSubCheckbox(L.TOOLTIP_TRANSMOG_OVERLAY or "Show Overlay Icons", "TooltipPlus_TransmogOverlay",
        "Show icons on item buttons.", tooltipToggle)
    layout:AddSubDropdown(L.TOOLTIP_TRANSMOG_CORNER or "Icon Corner", "TooltipPlus_TransmogCorner", C.CORNER_OPTIONS, nil,
        tooltipToggle)

    layout:AddSpacer(5)

    -- Hide Elements
    layout:AddSection("Hide Elements")
    layout:AddSubCheckbox(L.TOOLTIP_HIDE_HEALTHBAR or "Hide Health Bar", "TooltipPlus_HideHealthbar",
        "Hide unit health bar.", tooltipToggle)
    layout:AddSubCheckbox(L.TOOLTIP_HIDE_GUILD or "Hide Guild", "TooltipPlus_HideGuild", "Hide guild name.",
        tooltipToggle)
    layout:AddSubCheckbox(L.TOOLTIP_HIDE_FACTION or "Hide Faction", "TooltipPlus_HideFaction", "Hide faction text.",
        tooltipToggle)
    layout:AddSubCheckbox(L.TOOLTIP_HIDE_PVP or "Hide PvP", "TooltipPlus_HidePvP", "Hide PvP status.", tooltipToggle)
    layout:AddSubCheckbox(L.TOOLTIP_HIDE_REALM or "Hide Realm", "TooltipPlus_HideRealm", "Hide cross-realm names.",
        tooltipToggle)

    layout:AddSpacer(5)

    -- Extra Info
    layout:AddSection("Extra Info")
    layout:AddSubCheckbox(L.TOOLTIP_SHOW_ITEM_ID or "Show Item ID", "TooltipPlus_ShowItemID", "Display item database ID.",
        tooltipToggle)
    layout:AddSubCheckbox(L.TOOLTIP_SHOW_SPELL_ID or "Show Spell ID", "TooltipPlus_ShowSpellID",
        "Display spell database ID.", tooltipToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

-- FRAMES (Combat Fade)
local function SetupFramesContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    layout:AddSection(L.MODULE_COMBAT_FADE or "Combat Fade")
    local fadeToggle = layout:AddModule(L.MODULE_COMBAT_FADE or "Combat Fade", "CombatFade", L.TIP_COMBAT_FADE)
    layout:AddSubCheckbox(L.COMBAT_FADE_ACTION_BARS or "Fade Action Bars", "CombatFade_ActionBars",
        L.TIP_COMBAT_FADE_ACTION_BARS, fadeToggle)
    layout:AddSubSlider("Action Bar Opacity", "CombatFade_ActionBars_Opacity", 0, 100, 5,
        L.TIP_COMBAT_FADE_ACTION_BARS_OPACITY, fadeToggle)
    layout:AddSubCheckbox(L.COMBAT_FADE_PLAYER_FRAME or "Fade Player Frame", "CombatFade_PlayerFrame",
        L.TIP_COMBAT_FADE_PLAYER_FRAME, fadeToggle)
    layout:AddSubSlider("Player Frame Opacity", "CombatFade_PlayerFrame_Opacity", 0, 100, 5,
        L.TIP_COMBAT_FADE_PLAYER_FRAME_OPACITY, fadeToggle)

    layout:AddSpacer(10)

    -- Speed Display
    layout:AddSection(L.MODULE_SPEED_DISPLAY or "Speed Display")
    local speedToggle = layout:AddModule(L.MODULE_SPEED_DISPLAY or "Speed Display", "SpeedDisplay", L.TIP_SPEED_DISPLAY)
    layout:AddSubCheckbox(L.SPEED_DECIMALS or "Show Decimals", "SpeedDisplay_Decimals", L.TIP_SPEED_DECIMALS, speedToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end


-- NAMEPLATES
local function SetupNameplatesContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    layout:AddSection(L.MODULE_QUEST_NAMEPLATES or "Quest Nameplates")
    local npToggle = layout:AddModule(L.MODULE_QUEST_NAMEPLATES or "Quest Nameplates", "QuestNameplates",
        L.TIP_QUEST_NAMEPLATES)
    layout:AddSubCheckbox(L.SHOW_KILL_ICON or "Show Kill Icon", "QuestNameplates_ShowKillIcon", nil, npToggle)
    layout:AddSubCheckbox(L.SHOW_LOOT_ICON or "Show Loot Icon", "QuestNameplates_ShowLootIcon", nil, npToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

-- CAMERA
local function SetupCameraContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    layout:AddSection(L.MODULE_ACTIONCAM or "Action Camera")
    local camToggle = layout:AddModule(L.MODULE_ACTIONCAM or "Action Camera", "ActionCam", L.TIP_ACTIONCAM)
    layout:AddSubDropdown(L.ACTIONCAM_MODE or "Camera Mode", "ActionCam_Mode", C.ACTIONCAM_MODE_OPTIONS, nil, camToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

-- SOCIAL (Auto Invite + Auto Release)
local function SetupSocialContent(parent)
    local container = CreateScrollableContent(parent)
    local content = container.content
    local layout = CreateContentLayout(content)

    -- Auto Invite
    layout:AddSection(L.MODULE_AUTO_INVITE or "Auto Accept Invite")
    local inviteToggle = layout:AddModule(L.MODULE_AUTO_INVITE or "Auto Accept Invite", "AutoInvite",
        "Accept invites from trusted sources.")
    layout:AddSubCheckbox(L.INVITE_FRIENDS or "Friends", "AutoInvite_Friends", L.TIP_INVITE_FRIENDS, inviteToggle)
    layout:AddSubCheckbox(L.INVITE_BNET or "Battle.net Friends", "AutoInvite_BNetFriends", L.TIP_INVITE_BNET,
        inviteToggle)
    layout:AddSubCheckbox(L.INVITE_GUILD or "Guild Members", "AutoInvite_Guild", L.TIP_INVITE_GUILD, inviteToggle)
    layout:AddSubCheckbox(L.INVITE_GUILD_INVITES or "Guild Invites", "AutoInvite_GuildInvites", L.TIP_GUILD_INVITES,
        inviteToggle)

    layout:AddSpacer(10)

    -- Auto Release
    layout:AddSection(L.MODULE_AUTO_RELEASE or "Auto Release")
    local releaseToggle = layout:AddModule(L.MODULE_AUTO_RELEASE or "Auto Release", "AutoRelease",
        "Release spirit automatically when you die.")
    layout:AddSubDropdown(L.RELEASE_MODE or "Release Mode", "AutoRelease_Mode", C.RELEASE_MODE_OPTIONS, nil,
        releaseToggle)
    layout:AddSubCheckbox(L.SHOW_NOTIFICATIONS or "Show Notifications", "AutoRelease_Notify", L.TIP_RELEASE_NOTIFY,
        releaseToggle)

    layout:AddDefaultsButton(container)
    content:SetHeight(layout:Finalize())
    container.layout = layout
    container:SetScript("OnShow", function() layout:RefreshAll() end)
    return container
end

----------------------------------------------
-- Content Setup Map
----------------------------------------------
local CONTENT_SETUP = {
    -- Gameplay
    questing = SetupQuestingContent,
    looting = SetupLootingContent,
    camera = SetupCameraContent,
    -- Automation
    vendors = SetupVendorsContent,
    confirmations = SetupConfirmationsContent,
    social = SetupSocialContent,
    -- Interface
    tooltips = SetupTooltipsContent,
    nameplates = SetupNameplatesContent,
    frames = SetupFramesContent,
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
        -- Refresh all visible content
        for _, panel in pairs(contentPanels) do
            if panel.layout and panel.layout.RefreshAll then
                panel.layout:RefreshAll()
            end
        end
    end
end

----------------------------------------------
-- Create Sidebar Category Header
----------------------------------------------
local function CreateCategoryHeader(parent, text, yOffset)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(LAYOUT.CATEGORY_HEIGHT)
    header:SetPoint("TOPLEFT", 8, yOffset)
    header:SetPoint("RIGHT", -8, 0)

    -- Category label (gold text like Blizzard's)
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 4, 0)
    label:SetText(text)
    label:SetTextColor(1, 0.82, 0) -- Gold color like WoW headers

    -- Horizontal divider line using native atlas
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetAtlas("Options_HorizontalDivider", false)
    line:SetHeight(1)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", 0, 0)

    return header, LAYOUT.CATEGORY_HEIGHT
end

----------------------------------------------
-- Create Sidebar Subcategory Button
-- Uses native Options_List_Active and Options_List_Hover atlases
----------------------------------------------
local function CreateSubcategoryButton(parent, text, key, yOffset, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(21) -- Match atlas height (Options_List_Active is 21px tall)
    btn:SetPoint("TOPLEFT", LAYOUT.SUBCATEGORY_INDENT, yOffset)
    btn:SetPoint("RIGHT", -4, 0)
    btn.key = key

    -- Hover highlight using native atlas (hidden by default)
    local hover = btn:CreateTexture(nil, "BACKGROUND")
    hover:SetAtlas("Options_List_Hover", false)
    hover:SetAllPoints()
    hover:Hide()
    btn.hoverTex = hover

    -- Selected/Active state using native atlas (hidden by default)
    local active = btn:CreateTexture(nil, "BACKGROUND")
    active:SetAtlas("Options_List_Active", false)
    active:SetAllPoints()
    active:Hide()
    btn.activeTex = active

    -- Label
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9)
    btn.label = label

    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        if selectedCategory ~= self.key then
            self.hoverTex:Show()
            self.label:SetTextColor(1, 1, 1)
        end
    end)

    btn:SetScript("OnLeave", function(self)
        if selectedCategory ~= self.key then
            self.hoverTex:Hide()
            self.label:SetTextColor(0.9, 0.9, 0.9)
        end
    end)

    btn:SetScript("OnClick", function(self)
        onClick(self.key)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    return btn, 21 + 2 -- Height + spacing
end

----------------------------------------------
-- Select Category
----------------------------------------------
local function SelectCategory(key)
    -- Deselect all buttons
    for _, btn in ipairs(sidebarButtons) do
        btn.hoverTex:Hide()
        btn.activeTex:Hide()
        btn.label:SetTextColor(0.9, 0.9, 0.9)
    end

    -- Hide all content panels
    for _, panel in pairs(contentPanels) do
        panel:Hide()
    end

    -- Find and select the button
    for _, btn in ipairs(sidebarButtons) do
        if btn.key == key then
            btn.activeTex:Show()
            btn.label:SetTextColor(1, 0.82, 0) -- Gold text
            break
        end
    end

    -- Show the content panel
    if contentPanels[key] then
        contentPanels[key]:Show()
    end

    selectedCategory = key
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

    frame.NineSlice.Text:SetText(L.SETTINGS_TITLE or "Refactor Settings")

    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(5, 0, 0, 0)

    -- Drag handle
    local dragHandle = CreateFrame("Frame", nil, frame)
    dragHandle:SetPoint("TOPLEFT", 4, 0)
    dragHandle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -28, -24)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnEnter", function() SetCursor("Interface/CURSOR/UI-Cursor-Move.crosshair") end)
    dragHandle:SetScript("OnLeave", function() SetCursor(nil) end)
    dragHandle:SetScript("OnDragStart", function()
        frame:SetMovable(true)
        frame:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    frame:EnableMouse(true)
    frame:SetMouseClickEnabled(true)
    frame:SetMouseMotionEnabled(true)
    frame:SetScript("OnMouseWheel", function() end)

    -- Unified inner frame (contains both sidebar and content - like Blizzard's Game Menu)
    local innerFrame = CreateFrame("Frame", nil, frame)
    innerFrame:SetPoint("TOPLEFT", 10, -35)
    innerFrame:SetPoint("BOTTOMRIGHT", -10, 45)
    innerFrame:SetClipsChildren(true)

    -- Shared background for entire inner frame (sidebar + content)
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

    -- Sidebar (left portion of inner frame)
    local sidebar = CreateFrame("Frame", nil, innerFrame)
    sidebar:SetWidth(LAYOUT.SIDEBAR_WIDTH)
    sidebar:SetPoint("TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)

    -- Subtle divider line between sidebar and content
    local sidebarDivider = innerFrame:CreateTexture(nil, "ARTWORK")
    sidebarDivider:SetWidth(1)
    sidebarDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, -5)
    sidebarDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 5)
    sidebarDivider:SetColorTexture(0.35, 0.35, 0.35, 0.5)

    frame.Sidebar = sidebar

    -- Content area (right portion of inner frame)
    local contentArea = CreateFrame("Frame", nil, innerFrame)
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 0)
    contentArea:SetClipsChildren(true)

    frame.ContentArea = contentArea

    -- Build sidebar categories
    local currentY = -10
    for _, category in ipairs(CATEGORIES) do
        -- Category header
        local header, headerHeight = CreateCategoryHeader(sidebar, category.name, currentY)
        currentY = currentY - headerHeight - 4

        -- Subcategories
        for _, sub in ipairs(category.subcategories) do
            local btn, btnHeight = CreateSubcategoryButton(sidebar, sub.name, sub.key, currentY, SelectCategory)
            table.insert(sidebarButtons, btn)
            currentY = currentY - btnHeight - 2

            -- Create content panel for this subcategory
            if CONTENT_SETUP[sub.key] then
                local panel = CONTENT_SETUP[sub.key](contentArea)
                panel:SetPoint("TOPLEFT", 5, -5)
                panel:SetPoint("BOTTOMRIGHT", -5, 5)
                panel:Hide()
                contentPanels[sub.key] = panel
            end
        end

        currentY = currentY - 8 -- Space between categories
    end

    -- Bottom buttons
    local resetAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetAllBtn:SetSize(110, 24)
    resetAllBtn:SetPoint("BOTTOMLEFT", 15, 12)
    resetAllBtn:SetText("Reset All")
    resetAllBtn:SetScript("OnClick", function()
        StaticPopupDialogs["REFACTOR_RESET_ALL"] = {
            text = "Reset ALL Refactor settings to their default values?\n\n|cffff8800This will affect every tab.|r",
            button1 = YES,
            button2 = NO,
            OnAccept = ResetToDefaults,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("REFACTOR_RESET_ALL")
    end)
    StyleButtonWithAtlas(resetAllBtn)

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

    frame.ResetAllButton, frame.CancelButton, frame.OkayButton = resetAllBtn, cancelBtn, okayBtn

    table.insert(UISpecialFrames, frame:GetName())

    -- Select first category by default
    if CATEGORIES[1] and CATEGORIES[1].subcategories[1] then
        SelectCategory(CATEGORIES[1].subcategories[1].key)
    end

    frame:SetScript("OnShow", SaveSessionState)
    frame:Hide()

    return frame
end

----------------------------------------------
-- Public Functions
----------------------------------------------
function SettingsPanel:Toggle()
    if not frame then CreateSettingsFrame() end
    if frame then frame:SetShown(not frame:IsShown()) end
end

function SettingsPanel:Show()
    if not frame then CreateSettingsFrame() end
    if frame then frame:Show() end
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
