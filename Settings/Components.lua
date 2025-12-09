-- Refactor Addon - Settings UI Components
-- Premium design with 2-column layout

local addonName, addon = ...
local L = addon.L

local Components = addon.SettingsUI

----------------------------------------------
-- Color Definitions
----------------------------------------------
local Colors = {
    Header = { 1, 0.82, 0 },              -- Gold accent (WoW yellow)
    HeaderDisabled = { 0.5, 0.45, 0.35 }, -- Muted gold
    Normal = { 0.9, 0.9, 0.9 },           -- Bright white-ish
    Highlight = { 1, 1, 1 },              -- Pure white
    Disabled = { 0.5, 0.5, 0.5 },         -- Grey
    SubOption = { 0.75, 0.75, 0.75 },     -- Slightly dimmed
    Divider = { 0.35, 0.35, 0.35, 0.6 },  -- Subtle line
}

----------------------------------------------
-- Layout Constants
----------------------------------------------
local LAYOUT = {
    COLUMN_WIDTH = 280,     -- Width of each column
    COLUMN_GAP = 20,        -- Gap between columns
    LEFT_MARGIN = 20,       -- Left edge margin
    RIGHT_MARGIN = 20,      -- Right edge margin
    SECTION_SPACING = 16,   -- Space before section header
    ROW_HEIGHT = 24,        -- Height of a single option row
    SUB_OPTION_HEIGHT = 26, -- Height of sub-options (increased for spacing)
    SUB_OPTION_INDENT = 22, -- Indentation for sub-options
    HEADER_HEIGHT = 28,     -- Section header height
    MODULE_HEIGHT = 28,     -- Module toggle row height
}

----------------------------------------------
-- Tab Button Component (Modern Tabs)
----------------------------------------------
local minitabs = {}

local function MiniTab_Deselect(self)
    local r = minitabs[self]
    if not r then return end
    r.Text:SetPoint("BOTTOM", 0, 6)
    r.Text:SetFontObject("GameFontNormalSmall")
    r.Left:SetAtlas("Options_Tab_Left", true)
    r.Middle:SetAtlas("Options_Tab_Middle", true)
    r.Right:SetAtlas("Options_Tab_Right", true)
    r.NormalBG:SetPoint("TOPRIGHT", -2, -15)
    r.HighlightBG:SetColorTexture(1, 1, 1, 1)
    r.SelectedBG:SetColorTexture(0, 0, 0, 0)
    self:SetNormalFontObject(GameFontNormalSmall)
end

local function MiniTab_Select(self)
    local r = minitabs[self]
    if not r then return end
    r.Text:SetPoint("BOTTOM", 0, 8)
    r.Text:SetFontObject("GameFontHighlightSmall")
    r.Left:SetAtlas("Options_Tab_Active_Left", true)
    r.Middle:SetAtlas("Options_Tab_Active_Middle", true)
    r.Right:SetAtlas("Options_Tab_Active_Right", true)
    r.NormalBG:SetPoint("TOPRIGHT", -2, -12)
    r.HighlightBG:SetColorTexture(0, 0, 0, 0)
    r.SelectedBG:SetColorTexture(1, 1, 1, 1)
    self:SetNormalFontObject(GameFontHighlightSmall)
end

function Components.CreateTab(parent, text)
    local b = CreateFrame("Button", nil, parent)
    local r = {}
    minitabs[b] = r
    r.f = b

    -- Text
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b:SetFontString(t)
    t:ClearAllPoints()
    t:SetPoint("BOTTOM", 0, 6)
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetPushedTextOffset(0, 0)
    t:SetText(text)
    r.Text = t

    -- Left edge texture
    t = b:CreateTexture(nil, "BACKGROUND")
    t:SetPoint("BOTTOMLEFT")
    r.Left = t

    -- Right edge texture
    t = b:CreateTexture(nil, "BACKGROUND")
    t:SetPoint("BOTTOMRIGHT")
    r.Right = t

    -- Middle texture
    t = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    t:SetPoint("TOPLEFT", r.Left, "TOPRIGHT", 0, 0)
    t:SetPoint("TOPRIGHT", r.Right, "TOPLEFT", 0, 0)
    r.Middle = t

    -- Normal background (dark gradient)
    t = b:CreateTexture(nil, "BACKGROUND", nil, -3)
    t:SetPoint("BOTTOMLEFT", 2, 0)
    t:SetPoint("TOPRIGHT", -2, -15)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetGradient("VERTICAL", CreateColor(0.1, 0.1, 0.1, 0.85), CreateColor(0.15, 0.15, 0.15, 0.85))
    r.NormalBG = t

    -- Highlight background
    t = b:CreateTexture(nil, "HIGHLIGHT")
    t:SetPoint("BOTTOMLEFT", 2, 0)
    t:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -2, 12)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.15), CreateColor(0, 0, 0, 0))
    r.HighlightBG = t

    -- Selected background
    t = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    t:SetPoint("BOTTOMLEFT", 2, 0)
    t:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -2, 16)
    t:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.15), CreateColor(0, 0, 0, 0))
    r.SelectedBG = t

    -- Size based on text width
    b:SetSize(r.Text:GetStringWidth() + 40, 37)

    -- Start deselected
    MiniTab_Deselect(b)

    -- Custom select/deselect methods
    b.Select = MiniTab_Select
    b.Deselect = MiniTab_Deselect

    return b
end

----------------------------------------------
-- Section Header Component
----------------------------------------------
function Components.CreateSectionHeader(parent, text)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(LAYOUT.HEADER_HEIGHT)

    -- Header text with gold accent
    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    holder.text:SetText(text)
    holder.text:SetPoint("LEFT", 0, 0)
    holder.text:SetTextColor(Colors.Header[1], Colors.Header[2], Colors.Header[3])

    -- Subtle divider line extending from text to right edge
    holder.line = holder:CreateTexture(nil, "ARTWORK")
    holder.line:SetHeight(1)
    holder.line:SetPoint("LEFT", holder.text, "RIGHT", 12, 0)
    holder.line:SetPoint("RIGHT", 0, 0)
    holder.line:SetColorTexture(Colors.Divider[1], Colors.Divider[2], Colors.Divider[3], Colors.Divider[4])

    return holder
end

----------------------------------------------
-- Module Toggle (Inline checkbox with module name)
-- This is the main enable/disable toggle for a feature
----------------------------------------------
function Components.CreateModuleToggle(parent, label, moduleKey, tooltip)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(LAYOUT.MODULE_HEIGHT)

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, holder, "SettingsCheckboxTemplate")
    cb:SetPoint("LEFT", 0, 0)
    cb:SetText(label)
    cb:SetNormalFontObject(GameFontHighlight)

    -- Position text to right of checkbox
    local fs = cb:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetTextColor(Colors.Normal[1], Colors.Normal[2], Colors.Normal[3])

    -- State management
    holder.checkbox = cb
    holder.moduleKey = moduleKey
    holder.subOptions = {}
    holder.enabled = true

    -- Initialize state
    if moduleKey then
        cb:SetChecked(addon.GetDBBool(moduleKey))
    end

    -- Click handler
    cb:SetScript("OnClick", function()
        local checked = cb:GetChecked()
        if moduleKey then
            addon.SetDBValue(moduleKey, checked, true)
        end
        holder:UpdateSubOptionsState(checked)
    end)

    -- Tooltip
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Enable/disable sub-options based on parent state
    function holder:UpdateSubOptionsState(enabled)
        for _, opt in ipairs(self.subOptions) do
            if opt.SetEnabled then
                opt:SetEnabled(enabled)
            elseif opt.checkbox then
                opt.checkbox:SetEnabled(enabled)
            end
        end
    end

    function holder:SetValue(value)
        cb:SetChecked(value)
        self:UpdateSubOptionsState(value)
    end

    function holder:GetValue()
        return cb:GetChecked()
    end

    function holder:Refresh()
        if moduleKey then
            local value = addon.GetDBBool(moduleKey)
            cb:SetChecked(value)
            self:UpdateSubOptionsState(value)
        end
    end

    -- Register a sub-option to be controlled by this toggle
    function holder:RegisterSubOption(subOpt)
        table.insert(self.subOptions, subOpt)
    end

    return holder
end

----------------------------------------------
-- Sub-Option Checkbox (Indented, smaller)
----------------------------------------------
function Components.CreateSubCheckbox(parent, label, optionKey, tooltip, parentToggle)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(LAYOUT.SUB_OPTION_HEIGHT)

    -- Tree line indicator (visual hierarchy)
    local treeLine = holder:CreateTexture(nil, "ARTWORK")
    treeLine:SetSize(8, 8)
    treeLine:SetPoint("LEFT", 4, 0)
    treeLine:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    treeLine:SetTexture("Interface\\Common\\Indicator-Gray") -- Small dot
    holder.treeLine = treeLine

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, holder, "SettingsCheckboxTemplate")
    cb:SetPoint("LEFT", LAYOUT.SUB_OPTION_INDENT, 0)
    cb:SetText(label)
    cb:SetNormalFontObject(GameFontHighlightSmall)

    local fs = cb:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetTextColor(Colors.SubOption[1], Colors.SubOption[2], Colors.SubOption[3])

    holder.checkbox = cb
    holder.optionKey = optionKey

    -- Initialize
    if optionKey then
        cb:SetChecked(addon.GetDBBool(optionKey))
    end

    -- Click handler
    cb:SetScript("OnClick", function()
        if optionKey then
            addon.SetDBValue(optionKey, cb:GetChecked(), true)
        end
    end)

    -- Tooltip
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    function holder:SetEnabled(enabled)
        cb:SetEnabled(enabled)
        if enabled then
            fs:SetTextColor(Colors.SubOption[1], Colors.SubOption[2], Colors.SubOption[3])
            treeLine:SetAlpha(0.5)
        else
            fs:SetTextColor(Colors.Disabled[1], Colors.Disabled[2], Colors.Disabled[3])
            treeLine:SetAlpha(0.2)
        end
    end

    function holder:SetValue(value)
        cb:SetChecked(value)
    end

    function holder:GetValue()
        return cb:GetChecked()
    end

    function holder:Refresh()
        if optionKey then
            cb:SetChecked(addon.GetDBBool(optionKey))
        end
    end

    -- Register with parent toggle if provided
    if parentToggle and parentToggle.RegisterSubOption then
        parentToggle:RegisterSubOption(holder)
    end

    return holder
end

----------------------------------------------
-- Sub-Option Slider (Indented, compact)
----------------------------------------------
function Components.CreateSubSlider(parent, label, optionKey, minVal, maxVal, step, tooltip, parentToggle)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(LAYOUT.SUB_OPTION_HEIGHT + 4)

    -- Tree line indicator
    local treeLine = holder:CreateTexture(nil, "ARTWORK")
    treeLine:SetSize(8, 8)
    treeLine:SetPoint("LEFT", 4, 0)
    treeLine:SetTexture("Interface\\Common\\Indicator-Gray")
    treeLine:SetAlpha(0.5)
    holder.treeLine = treeLine

    -- Label
    local lbl = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", LAYOUT.SUB_OPTION_INDENT, 0)
    lbl:SetText(label)
    lbl:SetTextColor(Colors.SubOption[1], Colors.SubOption[2], Colors.SubOption[3])
    holder.label = lbl

    -- Slider (compact Dragonflight style)
    local slider = CreateFrame("Slider", nil, holder, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    slider:SetWidth(120)
    slider:SetHeight(18)

    local steps = (maxVal - minVal) / (step or 1)
    slider:Init(maxVal, minVal, maxVal, steps, {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
            MinimalSliderWithSteppersMixin.Label.Right,
            function(value)
                return WHITE_FONT_COLOR:WrapTextInColorCode(tostring(math.floor(value)))
            end
        )
    })

    -- Set initial value
    local currentValue = addon.GetDBValue(optionKey) or minVal
    slider:SetValue(currentValue)

    -- Handle value changes
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        value = math.floor(value + 0.5)
        addon.SetDBValue(optionKey, value, true)
    end)

    holder.slider = slider
    holder.optionKey = optionKey

    -- Mouse wheel support
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        if slider.Slider:IsEnabled() then
            local newValue = slider.Slider:GetValue() + (delta * (step or 1))
            newValue = math.max(minVal, math.min(maxVal, newValue))
            slider:SetValue(newValue)
        end
    end)

    -- Tooltip
    if tooltip then
        holder:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        holder:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    function holder:SetEnabled(enabled)
        slider:SetEnabled(enabled)
        if enabled then
            lbl:SetTextColor(Colors.SubOption[1], Colors.SubOption[2], Colors.SubOption[3])
            treeLine:SetAlpha(0.5)
        else
            lbl:SetTextColor(Colors.Disabled[1], Colors.Disabled[2], Colors.Disabled[3])
            treeLine:SetAlpha(0.2)
        end
    end

    function holder:SetValue(value)
        slider:SetValue(value)
    end

    function holder:GetValue()
        return slider.Slider:GetValue()
    end

    function holder:Refresh()
        if optionKey then
            local value = addon.GetDBValue(optionKey) or minVal
            slider:SetValue(value)
        end
    end

    -- Register with parent
    if parentToggle and parentToggle.RegisterSubOption then
        parentToggle:RegisterSubOption(holder)
    end

    return holder
end

----------------------------------------------
-- Sub-Option Dropdown (Indented, compact)
----------------------------------------------
function Components.CreateSubDropdown(parent, label, optionKey, options, tooltip, parentToggle)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(LAYOUT.SUB_OPTION_HEIGHT + 6)

    -- Tree line indicator
    local treeLine = holder:CreateTexture(nil, "ARTWORK")
    treeLine:SetSize(8, 8)
    treeLine:SetPoint("LEFT", 4, 0)
    treeLine:SetTexture("Interface\\Common\\Indicator-Gray")
    treeLine:SetAlpha(0.5)
    holder.treeLine = treeLine

    -- Label
    local lbl = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", LAYOUT.SUB_OPTION_INDENT, 0)
    lbl:SetText(label)
    lbl:SetTextColor(Colors.SubOption[1], Colors.SubOption[2], Colors.SubOption[3])
    holder.label = lbl

    -- Dropdown
    local dropdown = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(130)
    dropdown:SetPoint("LEFT", lbl, "RIGHT", 10, 0)

    local entries = {}
    for _, opt in ipairs(options) do
        table.insert(entries, { opt.label, opt.value })
    end

    MenuUtil.CreateRadioMenu(dropdown,
        function(value) return addon.GetDBValue(optionKey) == value end,
        function(value) addon.SetDBValue(optionKey, value, true) end,
        unpack(entries)
    )

    holder.dropdown = dropdown
    holder.optionKey = optionKey

    -- Tooltip
    if tooltip then
        holder:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        holder:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    function holder:SetEnabled(enabled)
        dropdown:SetEnabled(enabled)
        if enabled then
            lbl:SetTextColor(Colors.SubOption[1], Colors.SubOption[2], Colors.SubOption[3])
            treeLine:SetAlpha(0.5)
        else
            lbl:SetTextColor(Colors.Disabled[1], Colors.Disabled[2], Colors.Disabled[3])
            treeLine:SetAlpha(0.2)
        end
    end

    function holder:Refresh()
        dropdown:GenerateMenu()
    end

    -- Register with parent
    if parentToggle and parentToggle.RegisterSubOption then
        parentToggle:RegisterSubOption(holder)
    end

    return holder
end

----------------------------------------------
-- Standalone Checkbox (for simple toggles)
----------------------------------------------
function Components.CreateCheckbox(parent, label, spacing, callback)
    spacing = spacing or 0

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(LAYOUT.ROW_HEIGHT)

    local cb = CreateFrame("CheckButton", nil, holder, "SettingsCheckboxTemplate")
    cb:SetPoint("LEFT", 0, 0)
    cb:SetText(label)
    cb:SetNormalFontObject(GameFontHighlight)

    local fs = cb:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)

    function holder:SetValue(value)
        cb:SetChecked(value)
    end

    function holder:GetValue()
        return cb:GetChecked()
    end

    cb:SetScript("OnClick", function()
        if callback then
            callback(cb:GetChecked())
        end
    end)

    holder.checkbox = cb

    return holder
end

----------------------------------------------
-- Standalone Dropdown
----------------------------------------------
function Components.CreateDropdown(parent, labelText, options, isSelectedCallback, onSelectionCallback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(LAYOUT.ROW_HEIGHT + 8)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText)

    local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(180)
    dropdown:SetPoint("LEFT", label, "RIGHT", 15, 0)

    local entries = {}
    for _, opt in ipairs(options) do
        table.insert(entries, { opt.label, opt.value })
    end

    MenuUtil.CreateRadioMenu(dropdown, isSelectedCallback, onSelectionCallback, unpack(entries))

    frame.Label = label
    frame.Dropdown = dropdown

    function frame:SetValue()
        dropdown:GenerateMenu()
    end

    return frame
end

----------------------------------------------
-- Header Component (for page titles)
----------------------------------------------
function Components.CreateHeader(parent, text)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(32)

    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    holder.text:SetText(text)
    holder.text:SetPoint("LEFT", 0, 0)
    holder.text:SetTextColor(Colors.Header[1], Colors.Header[2], Colors.Header[3])

    return holder
end

----------------------------------------------
-- Info Box (for addon header)
----------------------------------------------
function Components.CreateInfoBox(parent, name, version, description)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(60)

    -- Subtle dark background
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)

    -- Subtle border
    local border = holder:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", 0, 0)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    local innerBg = holder:CreateTexture(nil, "ARTWORK", nil, -1)
    innerBg:SetPoint("TOPLEFT", 1, -1)
    innerBg:SetPoint("BOTTOMRIGHT", -1, 1)
    innerBg:SetColorTexture(0.08, 0.08, 0.08, 0.8)

    local logo = holder:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    logo:SetSize(44, 44)
    logo:SetPoint("LEFT", 10, 0)

    local nameText = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    nameText:SetText(name)
    nameText:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -3)
    nameText:SetTextColor(Colors.Header[1], Colors.Header[2], Colors.Header[3])

    local versionText = holder:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    versionText:SetText("v" .. version)
    versionText:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
    versionText:SetTextColor(0.6, 0.6, 0.6)

    local descText = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    descText:SetText(description)
    descText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
    descText:SetTextColor(0.75, 0.75, 0.75)

    holder.logo = logo
    holder.name = nameText
    holder.version = versionText
    holder.description = descText

    return holder
end
