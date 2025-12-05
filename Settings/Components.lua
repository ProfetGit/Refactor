-- Refactor Addon - Settings UI Components
-- Reusable UI components inspired by Chattynator

local addonName, addon = ...
local L = addon.L

local Components = addon.SettingsUI

----------------------------------------------
-- Color Definitions
----------------------------------------------
local Colors = {
    Normal = { 0.84, 0.75, 0.64 },      -- Warm beige
    Highlight = { 1, 1, 1 },            -- White
    Disabled = { 0.5, 0.5, 0.5 },       -- Grey
    Accent = { 1, 0.82, 0 },            -- WoW Gold/Yellow
}

----------------------------------------------
-- Scrollable Container Component
----------------------------------------------
function Components.CreateScrollContainer(parent)
    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    -- Create content frame that will hold all the settings
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() - 10)
    content:SetHeight(1) -- Will be adjusted dynamically
    
    scrollFrame:SetScrollChild(content)
    
    -- Update content width when parent resizes
    scrollFrame:SetScript("OnSizeChanged", function(self, width, height)
        content:SetWidth(width - 10)
    end)
    
    -- Store reference and helper function
    scrollFrame.content = content
    
    function scrollFrame:UpdateContentHeight(height)
        content:SetHeight(math.max(height, scrollFrame:GetHeight()))
    end
    
    return scrollFrame, content
end

----------------------------------------------
-- Checkbox Component
----------------------------------------------
function Components.CreateCheckbox(parent, label, spacing, callback)
    spacing = spacing or 0
    
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(40)
    holder:SetPoint("LEFT", parent, "LEFT", 30, 0)
    holder:SetPoint("RIGHT", parent, "RIGHT", -15, 0)
    
    local checkBox = CreateFrame("CheckButton", nil, holder, "SettingsCheckboxTemplate")
    checkBox:SetPoint("LEFT", holder, "CENTER", -15 - spacing, 0)
    checkBox:SetText(label)
    checkBox:SetNormalFontObject(GameFontHighlight)
    checkBox:GetFontString():SetPoint("RIGHT", holder, "CENTER", -30 - spacing, 0)
    checkBox:GetFontString():SetJustifyH("RIGHT")
    
    function holder:SetValue(value)
        checkBox:SetChecked(value)
    end
    
    function holder:GetValue()
        return checkBox:GetChecked()
    end
    
    holder:SetScript("OnEnter", function()
        if checkBox.OnEnter then checkBox:OnEnter() end
    end)
    
    holder:SetScript("OnLeave", function()
        if checkBox.OnLeave then checkBox:OnLeave() end
    end)
    
    holder:SetScript("OnMouseUp", function()
        checkBox:Click()
    end)
    
    checkBox:SetScript("OnClick", function()
        if callback then
            callback(checkBox:GetChecked())
        end
    end)
    
    return holder
end

----------------------------------------------
-- Header Component
----------------------------------------------
function Components.CreateHeader(parent, text)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("LEFT", 30, 0)
    holder:SetPoint("RIGHT", -30, 0)
    holder:SetHeight(40)
    
    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    holder.text:SetText(text)
    holder.text:SetPoint("LEFT", 20, -1)
    holder.text:SetTextColor(Colors.Accent[1], Colors.Accent[2], Colors.Accent[3])
    
    -- Subtle divider line
    holder.line = holder:CreateTexture(nil, "ARTWORK")
    holder.line:SetHeight(1)
    holder.line:SetPoint("LEFT", holder.text, "LEFT", 0, -15)
    holder.line:SetPoint("RIGHT", holder, "RIGHT", -20, -15)
    holder.line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    
    return holder
end

----------------------------------------------
-- Tab Button Component
----------------------------------------------
function Components.CreateTab(parent, text)
    local tab = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
    tab:SetText(text)
    
    tab:SetScript("OnShow", function(self)
        PanelTemplates_TabResize(self, 15, nil, 10)
        PanelTemplates_DeselectTab(self)
    end)
    
    tab:GetScript("OnShow")(tab)
    
    return tab
end

----------------------------------------------
-- Dropdown Component
----------------------------------------------
function Components.CreateDropdown(parent, labelText, options, isSelectedCallback, onSelectionCallback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("LEFT", 30, 0)
    frame:SetPoint("RIGHT", -30, 0)
    frame:SetHeight(40)
    
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 20, 0)
    label:SetPoint("RIGHT", frame, "CENTER", -50, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(labelText)
    
    local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(200)
    dropdown:SetPoint("LEFT", frame, "CENTER", -32, 0)
    
    -- Build menu
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
-- Slider Component
----------------------------------------------
function Components.CreateSlider(parent, label, min, max, valuePattern, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(40)
    holder:SetPoint("LEFT", parent, "LEFT", 30, 0)
    holder:SetPoint("RIGHT", parent, "RIGHT", -30, 0)
    
    holder.Label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    holder.Label:SetJustifyH("RIGHT")
    holder.Label:SetPoint("LEFT", 20, 0)
    holder.Label:SetPoint("RIGHT", holder, "CENTER", -50, 0)
    holder.Label:SetText(label)
    
    holder.Slider = CreateFrame("Slider", nil, holder, "MinimalSliderWithSteppersTemplate")
    holder.Slider:SetPoint("LEFT", holder, "CENTER", -32, 0)
    holder.Slider:SetPoint("RIGHT", -45, 0)
    holder.Slider:SetHeight(20)
    
    holder.Slider:Init(max, min, max, max - min, {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
            MinimalSliderWithSteppersMixin.Label.Right, 
            function(value)
                return WHITE_FONT_COLOR:WrapTextInColorCode(valuePattern:format(value))
            end
        )
    })
    
    holder.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if callback then
            callback(value)
        end
    end)
    
    function holder:GetValue()
        return holder.Slider.Slider:GetValue()
    end
    
    function holder:SetValue(value)
        return holder.Slider:SetValue(value)
    end
    
    holder:SetScript("OnMouseWheel", function(_, delta)
        if holder.Slider.Slider:IsEnabled() then
            holder.Slider:SetValue(holder.Slider.Slider:GetValue() + delta)
        end
    end)
    
    return holder
end

----------------------------------------------
-- Module Toggle (Master Switch)
----------------------------------------------
function Components.CreateModuleToggle(parent, moduleInfo)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(50)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)
    
    -- Background highlight
    holder.bg = holder:CreateTexture(nil, "BACKGROUND")
    holder.bg:SetAllPoints()
    holder.bg:SetColorTexture(1, 1, 1, 0.03)
    holder.bg:Hide()
    
    -- Module name
    holder.Title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    holder.Title:SetPoint("LEFT", 15, 8)
    holder.Title:SetText(moduleInfo.name)
    holder.Title:SetTextColor(Colors.Normal[1], Colors.Normal[2], Colors.Normal[3])
    
    -- Module description
    holder.Desc = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.Desc:SetPoint("TOPLEFT", holder.Title, "BOTTOMLEFT", 0, -2)
    holder.Desc:SetPoint("RIGHT", -100, 0)
    holder.Desc:SetJustifyH("LEFT")
    holder.Desc:SetText(moduleInfo.description or "")
    holder.Desc:SetTextColor(Colors.Disabled[1], Colors.Disabled[2], Colors.Disabled[3])
    
    -- Enable checkbox
    holder.Toggle = CreateFrame("CheckButton", nil, holder, "SettingsCheckboxTemplate")
    holder.Toggle:SetPoint("RIGHT", -15, 0)
    holder.Toggle:SetChecked(addon.GetDBBool(moduleInfo.key))
    
    holder.Toggle:SetScript("OnClick", function()
        local enabled = holder.Toggle:GetChecked()
        addon.SetDBValue(moduleInfo.key, enabled, true)
        holder:UpdateState()
    end)
    
    function holder:UpdateState()
        local enabled = addon.GetDBBool(moduleInfo.key)
        holder.Toggle:SetChecked(enabled)
        if enabled then
            holder.Title:SetTextColor(Colors.Highlight[1], Colors.Highlight[2], Colors.Highlight[3])
        else
            holder.Title:SetTextColor(Colors.Disabled[1], Colors.Disabled[2], Colors.Disabled[3])
        end
    end
    
    holder:SetScript("OnEnter", function()
        holder.bg:Show()
        holder.Title:SetTextColor(Colors.Highlight[1], Colors.Highlight[2], Colors.Highlight[3])
    end)
    
    holder:SetScript("OnLeave", function()
        holder.bg:Hide()
        holder:UpdateState()
    end)
    
    holder:SetScript("OnMouseUp", function()
        holder.Toggle:Click()
    end)
    
    holder.moduleKey = moduleInfo.key
    holder:UpdateState()
    
    return holder
end
----------------------------------------------
-- Module Section (with Sub-options)
-- Collapsible design for better UX
----------------------------------------------
function Components.CreateModuleSection(parent, title, description, moduleKey, hasOptions)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("LEFT", 30, 0)
    section:SetPoint("RIGHT", -15, 0)
    
    -- State tracking
    section.isExpanded = true
    section.collapsedHeight = 30
    section.innerHeight = 55
    section:SetHeight(section.innerHeight)
    
    -- Expand/Collapse arrow indicator
    section.Arrow = section:CreateTexture(nil, "OVERLAY")
    section.Arrow:SetSize(12, 12)
    section.Arrow:SetPoint("TOPLEFT", 5, -8)
    section.Arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    section.Arrow:SetTexCoord(0, 0.5, 0, 0.5) -- Down arrow for expanded
    
    -- Module name (accent color like headers)
    section.Title = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    section.Title:SetPoint("TOPLEFT", 22, -5)
    section.Title:SetText(title)
    section.Title:SetTextColor(Colors.Accent[1], Colors.Accent[2], Colors.Accent[3])
    
    -- Clickable overlay for title area (to toggle collapse)
    section.TitleButton = CreateFrame("Button", nil, section)
    section.TitleButton:SetPoint("TOPLEFT", 0, 0)
    section.TitleButton:SetPoint("BOTTOMRIGHT", section, "TOPRIGHT", -60, -28)
    section.TitleButton:SetScript("OnEnter", function()
        section.Title:SetTextColor(1, 1, 1) -- Highlight on hover
    end)
    section.TitleButton:SetScript("OnLeave", function()
        section:UpdateState()
    end)
    
    -- Cogwheel indicator if has options
    if hasOptions then
        section.OptionsIcon = section:CreateTexture(nil, "OVERLAY")
        section.OptionsIcon:SetSize(14, 14)
        section.OptionsIcon:SetPoint("LEFT", section.Title, "RIGHT", 6, 0)
        section.OptionsIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
        section.OptionsIcon:SetVertexColor(0.5, 0.5, 0.5)
    end
    
    -- Divider line under title
    section.divider = section:CreateTexture(nil, "ARTWORK")
    section.divider:SetHeight(1)
    section.divider:SetPoint("LEFT", 20, 0)
    section.divider:SetPoint("RIGHT", -20, 0)
    section.divider:SetPoint("TOP", 0, -28)
    section.divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    
    -- Description (part of collapsible content)
    section.ContentFrame = CreateFrame("Frame", nil, section)
    section.ContentFrame:SetPoint("TOPLEFT", 0, -30)
    section.ContentFrame:SetPoint("RIGHT", 0, 0)
    
    if description then
        section.Desc = section.ContentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        section.Desc:SetPoint("TOPLEFT", 22, -2)
        section.Desc:SetPoint("RIGHT", -100, 0)
        section.Desc:SetJustifyH("LEFT")
        section.Desc:SetText(description)
        section.Desc:SetTextColor(Colors.Disabled[1], Colors.Disabled[2], Colors.Disabled[3])
    end
    
    -- Enable toggle (positioned at right, same line as title)
    section.Toggle = CreateFrame("CheckButton", nil, section, "SettingsCheckboxTemplate")
    section.Toggle:SetPoint("RIGHT", -15, 0)
    section.Toggle:SetPoint("TOP", section.Title, "TOP", 0, 3)
    
    if moduleKey then
        section.Toggle:SetChecked(addon.GetDBBool(moduleKey))
        section.Toggle:SetScript("OnClick", function()
            addon.SetDBValue(moduleKey, section.Toggle:GetChecked(), true)
            section:UpdateState()
        end)
    end
    
    -- Sub-options container (inside ContentFrame)
    section.OptionsFrame = CreateFrame("Frame", nil, section.ContentFrame)
    section.OptionsFrame:SetPoint("TOPLEFT", 20, -20)
    section.OptionsFrame:SetPoint("RIGHT", -20, 0)
    section.OptionsFrame:SetHeight(1)
    section.subOptions = {}
    section.nextY = 0
    
    -- Toggle collapse function
    function section:SetExpanded(expanded)
        self.isExpanded = expanded
        
        if expanded then
            -- Show content
            self.ContentFrame:Show()
            self:SetHeight(self.innerHeight)
            -- Down arrow (expanded)
            self.Arrow:SetTexture("Interface\\Buttons\\SquareButtonTextures")
            self.Arrow:SetTexCoord(0.45312500, 0.64062500, 0.20312500, 0.01562500)
        else
            -- Hide content
            self.ContentFrame:Hide()
            self:SetHeight(self.collapsedHeight)
            -- Right arrow (collapsed)
            self.Arrow:SetTexture("Interface\\Buttons\\SquareButtonTextures")
            self.Arrow:SetTexCoord(0.42187500, 0.23437500, 0.01562500, 0.20312500)
        end
        
        -- Notify parent to recalculate layout
        if self.OnExpandChanged then
            self:OnExpandChanged(expanded)
        end
    end
    
    function section:ToggleExpand()
        self:SetExpanded(not self.isExpanded)
    end
    
    -- Click title to toggle
    section.TitleButton:SetScript("OnClick", function()
        section:ToggleExpand()
    end)

    function section:AddCheckbox(label, optionKey, tooltip, callback)
        local cb = CreateFrame("CheckButton", nil, self.OptionsFrame, "SettingsCheckboxTemplate")
        cb:SetPoint("TOPLEFT", 0, -self.nextY)
        cb:SetText(label)
        cb:SetNormalFontObject(GameFontHighlight)
        cb:GetFontString():ClearAllPoints()
        cb:GetFontString():SetPoint("LEFT", cb, "RIGHT", 5, 0)
        
        if optionKey then
            cb:SetChecked(addon.GetDBBool(optionKey))
            cb:SetScript("OnClick", function()
                addon.SetDBValue(optionKey, cb:GetChecked(), true)
                if callback then callback(cb:GetChecked()) end
            end)
            cb.optionKey = optionKey
        end
        
        -- Add tooltip on hover
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
        
        self.nextY = self.nextY + 26
        self.innerHeight = 55 + self.nextY
        self:SetHeight(self.innerHeight)
        table.insert(self.subOptions, cb)
        return cb
    end
    
    function section:AddDropdown(label, optionKey, options, callback)
        local frame = CreateFrame("Frame", nil, self.OptionsFrame)
        frame:SetPoint("TOPLEFT", 0, -self.nextY)
        frame:SetPoint("RIGHT", 0, 0)
        frame:SetHeight(30)
        
        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(label)
        
        local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        dropdown:SetWidth(150)
        dropdown:SetPoint("LEFT", lbl, "RIGHT", 15, 0)
        
        local entries = {}
        for _, opt in ipairs(options) do
            table.insert(entries, { opt.label, opt.value })
        end
        
        MenuUtil.CreateRadioMenu(dropdown, 
            function(value) return addon.GetDBValue(optionKey) == value end,
            function(value) 
                addon.SetDBValue(optionKey, value, true)
                if callback then callback(value) end
            end,
            unpack(entries)
        )
        
        frame.optionKey = optionKey
        frame.dropdown = dropdown
        
        self.nextY = self.nextY + 35
        self.innerHeight = 55 + self.nextY
        self:SetHeight(self.innerHeight)
        table.insert(self.subOptions, frame)
        return frame
    end
    
    function section:AddSlider(label, optionKey, minVal, maxVal, step, callback)
        local frame = CreateFrame("Frame", nil, self.OptionsFrame)
        frame:SetPoint("TOPLEFT", 0, -self.nextY)
        frame:SetPoint("RIGHT", -10, 0)
        frame:SetHeight(32)
        
        -- Label on the left
        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(label)
        
        -- Modern slider (Dragonflight style with +/- steppers)
        local slider = CreateFrame("Slider", nil, frame, "MinimalSliderWithSteppersTemplate")
        slider:SetPoint("LEFT", lbl, "RIGHT", 15, 0)
        slider:SetPoint("RIGHT", 0, 0)
        slider:SetHeight(20)
        
        -- Initialize the slider properly (this is key!)
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
            if callback then callback(value) end
        end)
        
        -- Mouse wheel support
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(_, delta)
            if slider.Slider:IsEnabled() then
                local newValue = slider.Slider:GetValue() + (delta * (step or 1))
                newValue = math.max(minVal, math.min(maxVal, newValue))
                slider:SetValue(newValue)
            end
        end)
        
        frame.optionKey = optionKey
        frame.slider = slider
        frame.label = lbl
        
        -- For refreshing
        function frame:SetValue(value)
            slider:SetValue(value)
        end
        function frame:GetValue()
            return slider.Slider:GetValue()
        end
        
        self.nextY = self.nextY + 36
        self.innerHeight = 55 + self.nextY
        self:SetHeight(self.innerHeight)
        table.insert(self.subOptions, frame)
        return frame
    end
    
    function section:AddSliderWithTooltip(label, optionKey, minVal, maxVal, step, tooltip, callback)
        local frame = self:AddSlider(label, optionKey, minVal, maxVal, step, callback)
        
        -- Add tooltip on hover to the label
        if tooltip and frame.label then
            frame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 0.82, 0)
                GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            frame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        
        return frame
    end
    
    function section:AddSpacer(height)
        self.nextY = self.nextY + (height or 10)
        self.innerHeight = 55 + self.nextY
        self:SetHeight(self.innerHeight)
    end
    
    function section:UpdateState()
        if not moduleKey then return end
        local enabled = addon.GetDBBool(moduleKey)
        self.Toggle:SetChecked(enabled)
        
        -- Title color based on enabled state
        if enabled then
            self.Title:SetTextColor(Colors.Accent[1], Colors.Accent[2], Colors.Accent[3])
        else
            self.Title:SetTextColor(Colors.Disabled[1], Colors.Disabled[2], Colors.Disabled[3])
        end
    end
    
    function section:RefreshOptions()
        for _, opt in ipairs(self.subOptions) do
            if opt.SetChecked and opt.optionKey then
                opt:SetChecked(addon.GetDBBool(opt.optionKey))
            end
        end
        self:UpdateState()
    end
    
    section.moduleKey = moduleKey
    section:UpdateState()
    section:SetExpanded(true) -- Start expanded
    
    return section
end
