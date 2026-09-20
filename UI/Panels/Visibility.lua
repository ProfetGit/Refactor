local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme, Rules, Conditions = R.Theme, R.Visibility, R.Conditions

local CONTROL_WIDTH, DROPDOWN_STEP, NOTE_HEIGHT, LABEL_STEP = 380, 36, 30, 20
local BOX_WIDTH, BOX_STEP, BOX_COLUMNS = 190, 26, 2
local SLIDER_STEP = LibStub("LibRefactorTheme-1.0").sliderRowHeight + 6
local MODULE_ID = "interface.visibility"
-- The order the element list runs in; a kind with one member gets no header of its own.
local KINDS = { "chat", "bars", "unit", "hud", "art" }

local function onStep(value, step)
    local scale = math.floor(1 / step + 0.5)
    return math.floor(value * scale + 0.5) / scale
end

local function secondsText(value)
    if value < 0.025 then
        return L.UI_VIS_INSTANT
    end
    return string.format(L.UI_VIS_SECONDS, value)
end

local function percentText(value)
    return string.format(L.UI_VIS_PERCENT, math.floor(value * 100 + 0.5))
end

-- The elements the editor writes to: the ticked ones, in catalogue order. The first is
-- the one whose values the editor shows.
function UI:VisibilityTargets(into)
    local targets = into or {}
    for index = #targets, 1, -1 do
        targets[index] = nil
    end
    for _, group in ipairs(Rules.groups) do
        if self.visSelected[group.id] then
            targets[#targets + 1] = group.id
        end
    end
    return targets
end

-- One patch, every ticked element, one write. Making two bars alike is ticking both.
function UI:VisibilityWrite(patch)
    local targets = self:VisibilityTargets(self.visTargets)
    if #targets > 0 then
        Rules:SetRules(targets, patch)
    end
    self:LoadVisibility()
end

-- What the module has to say about an element: available, or why not. The third value is
-- whether the label reads as live; a module that is off is not a reason to grey a name.
function UI:VisibilityStatus(group)
    local module = R.moduleByID[MODULE_ID]
    local runtime = module and module.state == "enabled" and module.groups and module.groups[group.id]
    if not runtime then
        return L.UI_VIS_STATUS_OFF, "TEXT_MUTED", true
    elseif runtime.status == "owned" then
        return string.format(L.UI_VIS_STATUS_OWNED, runtime.owner), "TEXT_WARNING", false
    elseif runtime.status == "missing" then
        return string.format(L.UI_VIS_STATUS_MISSING, runtime.missing), "TEXT_WARNING", false
    end
    return L.UI_VIS_STATUS_OK, "TEXT_MUTED", true
end

-- The element list: a box per element under a box per kind that ticks the whole kind.
function UI:VisibilityElements(block, y)
    local top = y
    self.visElementBoxes, self.visKindBoxes = {}, {}
    for _, kind in ipairs(KINDS) do
        local members = {}
        for _, group in ipairs(Rules.groups) do
            if group.kind == kind then
                members[#members + 1] = group
            end
        end
        if #members > 1 then
            local text = string.format(L.UI_VIS_ALL_KIND, L["VIS_KIND_" .. kind])
            local header = Theme:Checkbox(block, CONTROL_WIDTH, text, function(widget)
                local checked = widget:GetChecked() == true
                for _, group in ipairs(members) do
                    self.visSelected[group.id] = checked
                end
                self:LoadVisibility()
            end)
            header:SetPoint("TOPLEFT", 0, y)
            header.members = members
            block:Index(text)
            self.visKindBoxes[#self.visKindBoxes + 1] = header
            y = y - BOX_STEP
        end
        for index, group in ipairs(members) do
            local box = Theme:Checkbox(block, BOX_WIDTH, L[group.labelKey], function(widget)
                self.visSelected[group.id] = widget:GetChecked() == true
                self:LoadVisibility()
            end)
            local column, row = (index - 1) % BOX_COLUMNS, math.floor((index - 1) / BOX_COLUMNS)
            box:SetPoint("TOPLEFT", column * BOX_WIDTH, y - row * BOX_STEP)
            box.group = group
            block:Index(L[group.labelKey])
            self.visElementBoxes[#self.visElementBoxes + 1] = box
        end
        y = y - math.ceil(#members / BOX_COLUMNS) * BOX_STEP - 4
    end
    return top - y
end

-- One condition set as a labelled grid of checkboxes. A click writes the whole set back,
-- so the saved rule never holds a condition the boxes do not show.
function UI:VisibilitySet(block, labelKey, field, y)
    local label = Theme:Text(block, L[labelKey], "small", "TEXT_MUTED")
    label:SetPoint("TOPLEFT", 0, y)
    block:Index(L[labelKey])
    local boxes = {}
    for index, name in ipairs(Conditions.names) do
        local box = Theme:Checkbox(block, BOX_WIDTH, L["VIS_COND_" .. name], function()
            local set = {}
            for _, other in ipairs(boxes) do
                if other:GetChecked() then
                    set[other.condition] = true
                end
            end
            self:VisibilityWrite({ [field] = set })
        end)
        local column, row = (index - 1) % BOX_COLUMNS, math.floor((index - 1) / BOX_COLUMNS)
        box:SetPoint("TOPLEFT", column * BOX_WIDTH, y - LABEL_STEP - row * BOX_STEP)
        box.condition = name
        block:Index(L["VIS_COND_" .. name])
        boxes[index] = box
    end
    local rows = math.ceil(#Conditions.names / BOX_COLUMNS)
    return boxes, LABEL_STEP + rows * BOX_STEP
end

function UI:VisibilitySlider(block, labelKey, field, range, formatter, y)
    local slider = Theme:Slider(block, CONTROL_WIDTH, range.minimum, range.maximum, range.step, function(value)
        self:VisibilityWrite({ [field] = onStep(value, range.step) })
    end)
    slider:SetPoint("TOPLEFT", 0, y)
    slider:SetLabel(L[labelKey], formatter)
    block:Index(L[labelKey])
    return slider
end

-- The settings block behind the UI visibility row: a preset for everyone, then the list
-- of elements to tick and one editor that writes to every ticked one.
function UI:BuildVisibilitySettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_VIS_HELP)
    local top = block.top
    self.visSelected, self.visTargets = { [Rules.groups[1].id] = true }, {}
    for _, preset in ipairs(Rules.presets) do
        block:Index(L[preset.nameKey])
    end
    for _, mode in ipairs(Rules.modes) do
        block:Index(L["VIS_MODE_" .. mode])
    end
    block:Index(L.UI_VIS_PRESET, L.UI_VIS_ELEMENTS, L.UI_VIS_MODE, L.VIS_PRESET_CUSTOM)

    local presetEntries = {}
    for index, preset in ipairs(Rules.presets) do
        presetEntries[index] = { value = preset.id, text = L[preset.nameKey] }
    end
    self.visPresetDropdown = Theme:Dropdown(block, CONTROL_WIDTH, presetEntries,
        function(value) return Rules:Settings().preset == value end,
        function(value)
            Rules:ApplyPreset(value)
            self:LoadVisibility()
        end)
    self.visPresetDropdown:SetPoint("TOPLEFT", 0, top)
    self.visPresetDropdown:SetLabel(L.UI_VIS_PRESET)
    self.visPresetDetail = Theme:Text(block, "", "small", "TEXT_MUTED")
    self.visPresetDetail:SetPoint("TOPLEFT", 0, top - DROPDOWN_STEP)
    self.visPresetDetail:SetPoint("RIGHT")
    self.visPresetDetail:SetHeight(NOTE_HEIGHT)
    self.visPresetDetail:SetJustifyV("TOP")
    local y = top - DROPDOWN_STEP - NOTE_HEIGHT - 6

    local elementsLabel = Theme:Text(block, L.UI_VIS_ELEMENTS, "small", "TEXT_MUTED")
    elementsLabel:SetPoint("TOPLEFT", 0, y)
    y = y - LABEL_STEP
    y = y - self:VisibilityElements(block, y)

    self.visEditing = Theme:Text(block, "", "body", "TEXT_TITLE")
    self.visEditing:SetPoint("TOPLEFT", 0, y)
    self.visEditing:SetPoint("RIGHT")
    self.visStatus = Theme:Text(block, "", "small", "TEXT_MUTED")
    self.visStatus:SetPoint("TOPLEFT", 0, y - LABEL_STEP)
    self.visStatus:SetPoint("RIGHT")
    self.visStatus:SetHeight(NOTE_HEIGHT)
    self.visStatus:SetJustifyV("TOP")
    y = y - LABEL_STEP - NOTE_HEIGHT - 4

    local modeEntries = {}
    for index, mode in ipairs(Rules.modes) do
        modeEntries[index] = { value = mode, text = L["VIS_MODE_" .. mode] }
    end
    self.visModeDropdown = Theme:Dropdown(block, CONTROL_WIDTH, modeEntries,
        function(value)
            local targets = self:VisibilityTargets(self.visTargets)
            return targets[1] ~= nil and Rules:Rule(targets[1]).mode == value
        end,
        function(value) self:VisibilityWrite({ mode = value }) end)
    self.visModeDropdown:SetPoint("TOPLEFT", 0, y)
    self.visModeDropdown:SetLabel(L.UI_VIS_MODE)
    y = y - DROPDOWN_STEP - 6

    self.visShownAlpha = self:VisibilitySlider(block, "UI_VIS_SHOWN_ALPHA", "shownAlpha", Rules.shownRange,
        percentText, y)
    self.visHiddenAlpha = self:VisibilitySlider(block, "UI_VIS_HIDDEN_ALPHA", "hiddenAlpha", Rules.hiddenRange,
        percentText, y - SLIDER_STEP)
    y = y - SLIDER_STEP * 2 - 4

    local height
    self.visShowBoxes, height = self:VisibilitySet(block, "UI_VIS_SHOW_WHEN", "showWhen", y)
    y = y - height - 8
    self.visHideBoxes, height = self:VisibilitySet(block, "UI_VIS_HIDE_WHEN", "hideWhen", y)
    y = y - height - 8

    self.visFadeIn = self:VisibilitySlider(block, "UI_VIS_FADE_IN", "fadeIn", Rules.fadeRange, secondsText, y)
    self.visFadeOut = self:VisibilitySlider(block, "UI_VIS_FADE_OUT", "fadeOut", Rules.fadeRange, secondsText,
        y - SLIDER_STEP)
    y = y - SLIDER_STEP * 2 - 4

    self.visBlobs = Theme:Checkbox(block, CONTROL_WIDTH, L.UI_VIS_BLOBS, function(widget)
        Settings:SetOption("uiVisibilityBlobs", widget:GetChecked() == true)
    end)
    self.visBlobs:SetPoint("TOPLEFT", 0, y)
    block:Index(L.UI_VIS_BLOBS)
    y = y - BOX_STEP - 4

    self.visNote = Theme:Text(block, "", "small", "TEXT_MUTED")
    self.visNote:SetPoint("TOPLEFT", 0, y)
    self.visNote:SetPoint("RIGHT")
    self.visNote:SetHeight(NOTE_HEIGHT)
    self.visNote:SetJustifyV("TOP")
    for _, group in ipairs(Rules.groups) do
        if group.noteKey then
            block:Index(L[group.noteKey])
        end
    end
    y = y - NOTE_HEIGHT
    block:SetBodyHeight(top - y + 20)
    self:RegisterModuleSettings(MODULE_ID, block)
end

local function loadBoxes(boxes, set)
    for _, box in ipairs(boxes) do
        local supported = Conditions:Supported(box.condition)
        box:SetChecked(set[box.condition] == true)
        box:SetEnabled(supported)
        Theme:Color(box.label, supported and "TEXT_BODY" or "TEXT_MUTED", true)
    end
end

function UI:LoadVisibility()
    if not self.visPresetDropdown then
        return
    end
    local settings = Rules:Settings()
    local preset = Rules:Preset(settings.preset)
    self.visPresetDropdown:SetValueText(preset and L[preset.nameKey] or L.VIS_PRESET_CUSTOM)
    self.visPresetDetail:SetText(preset and L[preset.detailKey] or L.VIS_PRESET_CUSTOM_DETAIL)

    local extras = false
    for _, box in ipairs(self.visElementBoxes) do
        box:SetChecked(self.visSelected[box.group.id] == true)
        local _, _, live = self:VisibilityStatus(box.group)
        Theme:Color(box.label, live and "TEXT_BODY" or "TEXT_MUTED", true)
        if box.group.extras and self.visSelected[box.group.id] then
            extras = true
        end
    end
    for _, header in ipairs(self.visKindBoxes) do
        local all = true
        for _, group in ipairs(header.members) do
            if not self.visSelected[group.id] then
                all = false
            end
        end
        header:SetChecked(all)
    end

    local targets = self:VisibilityTargets(self.visTargets)
    local anchor = targets[1] and Rules:Group(targets[1])
    if not anchor then
        self.visEditing:SetText(L.UI_VIS_EDITING_NONE)
        self.visStatus:SetText("")
    elseif #targets == 1 then
        self.visEditing:SetText(string.format(L.UI_VIS_EDITING_ONE, L[anchor.labelKey]))
    else
        self.visEditing:SetText(string.format(L.UI_VIS_EDITING_MANY, #targets, L[anchor.labelKey]))
    end
    if anchor then
        local text, token = self:VisibilityStatus(anchor)
        self.visStatus:SetText(text)
        Theme:Color(self.visStatus, token, true)
    end
    local rule = anchor and Rules:Rule(anchor.id) or Rules:DefaultRule()
    self.visModeDropdown:SetValueText(L["VIS_MODE_" .. rule.mode])
    self.visShownAlpha:SetValue(rule.shownAlpha)
    self.visHiddenAlpha:SetValue(rule.hiddenAlpha)
    loadBoxes(self.visShowBoxes, rule.showWhen)
    loadBoxes(self.visHideBoxes, rule.hideWhen)
    self.visFadeIn:SetValue(rule.fadeIn)
    self.visFadeOut:SetValue(rule.fadeOut)
    self.visBlobs:SetShown(extras)
    self.visBlobs:SetChecked(Settings:GetOption("uiVisibilityBlobs") == true)
    self.visNote:SetText(anchor and anchor.noteKey and L[anchor.noteKey] or "")
end
