local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme, Rules, Conditions = R.Theme, R.Visibility, R.Conditions

local WIDTH, PAD, GAP = 420, 18, 8
local DROPDOWN_STEP, NOTE_HEIGHT, LABEL_STEP = 36, 44, 20
local BOX_WIDTH, BOX_STEP, BOX_COLUMNS = 190, 26, 2
local SLIDER_STEP = LibStub("LibRefactorTheme-1.0").sliderRowHeight + 6
local TAB_GAP, TAB_ROW = 4, 30
-- A system stands for at most the four chat elements, so four tabs are built and shown as needed.
local MAX_TABS = 4

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

local Companion = {}
Companion.__index = Companion

function Companion:Write(patch)
    if self.current then
        Rules:SetRule(self.current, patch)
    end
    self:Load()
end

function Companion:Set(block, labelKey, field, y)
    local label = Theme:Text(block, L[labelKey], "small", "TEXT_MUTED")
    label:SetPoint("TOPLEFT", PAD, y)
    local boxes = {}
    for index, name in ipairs(Conditions.names) do
        local box = Theme:Checkbox(block, BOX_WIDTH, L["VIS_COND_" .. name], function()
            local set = {}
            for _, other in ipairs(boxes) do
                if other:GetChecked() then
                    set[other.condition] = true
                end
            end
            self:Write({ [field] = set })
        end)
        local column, row = (index - 1) % BOX_COLUMNS, math.floor((index - 1) / BOX_COLUMNS)
        box:SetPoint("TOPLEFT", PAD + column * BOX_WIDTH, y - LABEL_STEP - row * BOX_STEP)
        box.condition = name
        boxes[index] = box
    end
    return boxes, LABEL_STEP + math.ceil(#Conditions.names / BOX_COLUMNS) * BOX_STEP
end

function Companion:Slider(block, labelKey, field, range, formatter, y)
    local slider = Theme:Slider(block, WIDTH - PAD * 2, range.minimum, range.maximum, range.step, function(value)
        self:Write({ [field] = onStep(value, range.step) })
    end)
    slider:SetPoint("TOPLEFT", PAD, y)
    slider:SetLabel(L[labelKey], formatter)
    return slider
end

-- Built once, at the module's first enable, and kept for the session (rule 11).
function Companion:Build()
    local frame = CreateFrame("Frame", nil, UIParent)
    self.frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetWidth(WIDTH)
    frame:Hide()
    R:OwnFrame(frame)
    Theme:Dialog(frame)
    self.title = Theme:Text(frame, "", "body", "TEXT_TITLE")
    self.title:SetPoint("TOPLEFT", PAD, -PAD)
    -- Flush on the corner, over the border, where EditModeSystemSettingsDialog anchors its
    -- own UIPanelCloseButton (EditModeDialogs.xml, 12.1.0), so the two dialogs side by side
    -- close the same way.
    local close = Theme:CloseButton(frame, function() self:Close() end)
    close:SetPoint("TOPRIGHT")
    local y = -PAD - 22

    self.tabs = {}
    for index = 1, MAX_TABS do
        local tab = Theme:Tab(frame, "", function(widget)
            self.current = widget.groupId
            self:Load()
        end)
        tab:SetPoint("BOTTOMLEFT", PAD, 0)
        tab:Hide()
        self.tabs[index] = tab
    end
    self.tabTop = y
    y = y - TAB_ROW

    self.status = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.status:SetPoint("TOPLEFT", PAD, y)
    self.status:SetPoint("RIGHT", -PAD, 0)
    self.status:SetHeight(LABEL_STEP)
    self.status:SetJustifyV("TOP")
    y = y - LABEL_STEP - GAP

    local modeEntries = {}
    for index, mode in ipairs(Rules.modes) do
        modeEntries[index] = { value = mode, text = L["VIS_MODE_" .. mode] }
    end
    self.mode = Theme:Dropdown(frame, WIDTH - PAD * 2, modeEntries,
        function(value) return self.current ~= nil and Rules:Rule(self.current).mode == value end,
        function(value) self:Write({ mode = value }) end)
    self.mode:SetPoint("TOPLEFT", PAD, y)
    self.mode:SetLabel(L.UI_VIS_MODE)
    y = y - DROPDOWN_STEP - 2

    local zoneEntries = {}
    for index, zone in ipairs(Rules.zones) do
        zoneEntries[index] = { value = zone, text = L["VIS_ZONE_" .. zone] }
    end
    self.zone = Theme:Dropdown(frame, WIDTH - PAD * 2, zoneEntries,
        function(value) return self.current ~= nil and Rules:Rule(self.current).zone == value end,
        function(value) self:Write({ zone = value }) end)
    self.zone:SetPoint("TOPLEFT", PAD, y)
    self.zone:SetLabel(L.UI_VIS_ZONE)
    y = y - DROPDOWN_STEP - GAP

    self.shownAlpha = self:Slider(frame, "UI_VIS_SHOWN_ALPHA", "shownAlpha", Rules.shownRange, percentText, y)
    self.hiddenAlpha = self:Slider(frame, "UI_VIS_HIDDEN_ALPHA", "hiddenAlpha", Rules.hiddenRange, percentText,
        y - SLIDER_STEP)
    y = y - SLIDER_STEP * 2 - GAP

    local height
    self.showBoxes, height = self:Set(frame, "UI_VIS_SHOW_WHEN", "showWhen", y)
    y = y - height - GAP
    self.hideBoxes, height = self:Set(frame, "UI_VIS_HIDE_WHEN", "hideWhen", y)
    y = y - height - GAP

    self.fadeIn = self:Slider(frame, "UI_VIS_FADE_IN", "fadeIn", Rules.fadeRange, secondsText, y)
    self.fadeOut = self:Slider(frame, "UI_VIS_FADE_OUT", "fadeOut", Rules.fadeRange, secondsText, y - SLIDER_STEP)
    y = y - SLIDER_STEP * 2 - GAP

    self.blobs = Theme:Checkbox(frame, WIDTH - PAD * 2, L.UI_VIS_BLOBS, function(widget)
        Settings:SetOption("uiVisibilityBlobs", widget:GetChecked() == true)
    end)
    self.blobs:SetPoint("TOPLEFT", PAD, y)
    y = y - BOX_STEP - GAP

    self.sameForAll = Theme:Button(frame, WIDTH - PAD * 2, "", function()
        if self.current then
            Rules:SetRules(Rules:Siblings(self.current, self.siblings), Rules:Rule(self.current))
        end
        self:Load()
    end)
    self.sameForAll:SetPoint("TOPLEFT", PAD, y)
    y = y - self.sameForAll.height - GAP

    self.note = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.note:SetPoint("TOPLEFT", PAD, y)
    self.note:SetPoint("RIGHT", -PAD, 0)
    self.note:SetHeight(NOTE_HEIGHT)
    self.note:SetJustifyV("TOP")
    y = y - NOTE_HEIGHT
    frame:SetHeight(-y + PAD)
    self.siblings = {}
end

-- Anchored to Blizzard's dialog, so a drag of theirs carries ours; nothing of theirs is
-- touched. ids are the groups the selected system stands for, first one showing.
function Companion:Open(dialog, ids)
    self.ids = ids
    self.current = ids[1]
    local frame = self.frame
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", dialog, "TOPRIGHT", GAP, 0)
    frame:Show()
    self:Load()
end

function Companion:Close()
    self.ids, self.current = nil, nil
    self.frame:Hide()
end

local function loadBoxes(boxes, set)
    for _, box in ipairs(boxes) do
        local supported = Conditions:Supported(box.condition)
        box:SetChecked(set[box.condition] == true)
        box:SetEnabled(supported)
        Theme:Color(box.label, supported and "TEXT_BODY" or "TEXT_MUTED", true)
    end
end

function Companion:Load()
    local group = self.current and Rules:Group(self.current)
    if not group or not self.frame:IsShown() then
        return
    end
    self.title:SetText(L[group.labelKey])
    local x = PAD
    for index, tab in ipairs(self.tabs) do
        local id = self.ids[index]
        if id and #self.ids > 1 then
            local other = Rules:Group(id)
            tab.groupId = id
            tab.label:SetText(L[other.labelKey])
            tab:SetWidth(tab.label:GetStringWidth() + 24)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", x, self.tabTop)
            x = x + tab:GetWidth() + TAB_GAP
            Theme:TabState(tab, id == self.current)
            tab:Show()
        else
            tab:Hide()
        end
    end
    local runtime = self.module.groups and self.module.groups[group.id]
    if runtime and runtime.status == "owned" then
        self.status:SetText(string.format(L.UI_VIS_STATUS_OWNED, runtime.owner))
        Theme:Color(self.status, "TEXT_WARNING", true)
    elseif runtime and runtime.status == "missing" then
        self.status:SetText(string.format(L.UI_VIS_STATUS_MISSING, runtime.missing))
        Theme:Color(self.status, "TEXT_WARNING", true)
    else
        self.status:SetText(L.UI_VIS_STATUS_OK)
        Theme:Color(self.status, "TEXT_MUTED", true)
    end
    local rule = Rules:Rule(group.id)
    self.mode:SetValueText(L["VIS_MODE_" .. rule.mode])
    self.zone:SetValueText(L["VIS_ZONE_" .. rule.zone])
    self.shownAlpha:SetValue(rule.shownAlpha)
    self.hiddenAlpha:SetValue(rule.hiddenAlpha)
    loadBoxes(self.showBoxes, rule.showWhen)
    loadBoxes(self.hideBoxes, rule.hideWhen)
    self.fadeIn:SetValue(rule.fadeIn)
    self.fadeOut:SetValue(rule.fadeOut)
    self.blobs:SetShown(group.extras ~= nil)
    self.blobs:SetChecked(Settings:GetOption("uiVisibilityBlobs") == true)
    local siblings = Rules:Siblings(group.id, self.siblings)
    self.sameForAll.label:SetText(string.format(L.UI_VIS_SAME_FOR_ALL, L["VIS_KIND_" .. group.kind]))
    self.sameForAll:SetShown(#siblings > 0)
    self.note:SetText(group.noteKey and L[group.noteKey] or "")
end

-- The module asks for this once, at its first enable, and opens and closes it from the
-- Edit Mode hooks it owns.
function UI:CreateVisibilityCompanion(module)
    local companion = setmetatable({ module = module }, Companion)
    companion:Build()
    self.visCompanion = companion
    return companion
end
