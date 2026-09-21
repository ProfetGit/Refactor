local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

local MODE_ENTRIES = {
    { value = "cursor", labelKey = "UI_TOOLTIP_MODE_CURSOR" },
    { value = "point", labelKey = "UI_TOOLTIP_MODE_POINT" },
}
local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local CURSOR_SIDES = { "RIGHT", "LEFT", "CENTER" }

-- The nine screen anchors are not translated: they are the same names the API takes, and
-- a player setting one is reading them as coordinates, not as prose.
local POINT_ENTRIES, CURSOR_ENTRIES = {}, {}
for index, point in ipairs(POINTS) do
    POINT_ENTRIES[index] = { value = point, text = point }
end
for index, side in ipairs(CURSOR_SIDES) do
    CURSOR_ENTRIES[index] = { value = side, labelKey = "UI_TOOLTIP_SIDE_" .. side }
end

-- The settings block behind the tooltip anchor row. Everything here applies on click,
-- except the typed offsets, which wait for Save.
function UI:BuildTooltipSettings(parent)
    local section = self.Widgets:SettingsBlock(parent, L.UI_TOOLTIP_HELP)
    local top = section.top
    section:Index(L.UI_TOOLTIP_OPTIONS, L.UI_TOOLTIP_MODE, L.UI_TOOLTIP_POINT, L.UI_TOOLTIP_OFFSET,
        L.UI_TOOLTIP_CURSOR_SIDE, L.UI_TOOLTIP_CURSOR_OFFSET)
    self.tooltipModeDropdown = self:OptionDropdown(section, "tooltipAnchor", MODE_ENTRIES,
        "UI_TOOLTIP_MODE", top)
    -- One dropdown for both placement lists. The menu is generated when it opens, so
    -- swapping the list is enough for it to offer whichever the current mode uses.
    self.tooltipPointDropdown = Theme:Dropdown(section, 380, CURSOR_ENTRIES,
        function(value) return self:TooltipPlacement() == value end,
        function(value)
            Settings:SetOption(self:TooltipPlacementKey(), value)
            self:LoadTooltips()
        end)
    self.tooltipPointDropdown:SetPoint("TOPLEFT", 0, top - 34)
    for index, entry in ipairs(CURSOR_ENTRIES) do
        CURSOR_ENTRIES[index] = { value = entry.value, text = L[entry.labelKey] }
        section:Index(L[entry.labelKey])
    end
    section:Index(L.UI_TOOLTIP_POINT, L.UI_TOOLTIP_CURSOR_SIDE)
    self.tooltipOffsetLabel = Theme:Text(section, L.UI_TOOLTIP_OFFSET, "small", "TEXT_MUTED")
    self.tooltipOffsetLabel:SetPoint("TOPLEFT", 0, top - 66)
    self.tooltipX = self.Widgets:Input(section, 90, 26)
    self.tooltipX:SetPoint("TOPLEFT", 0, top - 84)
    self.tooltipY = self.Widgets:Input(section, 90, 26)
    self.tooltipY:SetPoint("LEFT", self.tooltipX, "RIGHT", 8, 0)
    local saveOffsets = Theme:Button(section, 104, L.UI_SAVE_SHORT, function()
        local cursor = Settings:GetOption("tooltipAnchor") ~= "point"
        local keyX, keyY = cursor and "tooltipCursorX" or "tooltipX", cursor and "tooltipCursorY" or "tooltipY"
        local x, y = tonumber(self.tooltipX:GetText()), tonumber(self.tooltipY:GetText())
        if x and y and Settings:SetOption(keyX, x) and Settings:SetOption(keyY, y) then
            self.tooltipStatus:SetText(L.UI_SAVED)
        else
            self.tooltipStatus:SetText(L.UI_OFFSET_INVALID)
        end
        self.tooltipX:ClearFocus()
        self.tooltipY:ClearFocus()
    end)
    saveOffsets:SetPoint("LEFT", self.tooltipY, "RIGHT", 8, 0)
    self.tooltipStatus = Theme:Text(section, "", "small", "TEXT_TITLE")
    self.tooltipStatus:SetPoint("LEFT", saveOffsets, "RIGHT", 12, 0)
    self.tooltipStatus:SetPoint("RIGHT")
    self.tooltipNote = Theme:Text(section, "", "small", "TEXT_MUTED")
    self.tooltipNote:SetPoint("TOPLEFT", 0, top - 120)
    self.tooltipNote:SetPoint("RIGHT")
    self.tooltipNote:SetHeight(40)
    self.tooltipNote:SetJustifyV("TOP")
    section:SetBodyHeight(160)
    self:RegisterModuleSettings("tooltips.anchor", section)
end

function UI:BuildTooltipBorderSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_TOOLTIP_BORDER_HELP)
    self:OptionCheckbox(block, "tooltipClassBorder", "UI_TOOLTIP_CLASS_BORDER", block.top)
    block:SetBodyHeight(32)
    self:RegisterModuleSettings("tooltips.rarityBorder", block)
end

-- Which placement setting the one placement dropdown is standing in for.
function UI:TooltipPlacementKey()
    return Settings:GetOption("tooltipAnchor") == "point" and "tooltipPoint" or "tooltipCursorSide"
end

function UI:TooltipPlacement()
    return Settings:GetOption(self:TooltipPlacementKey())
end

function UI:LoadTooltips()
    if not self.tooltipModeDropdown then return end
    local cursor = Settings:GetOption("tooltipAnchor") ~= "point"
    self.tooltipPointDropdown:SetEntries(cursor and CURSOR_ENTRIES or POINT_ENTRIES)
    self.tooltipPointDropdown:SetLabel(cursor and L.UI_TOOLTIP_CURSOR_SIDE or L.UI_TOOLTIP_POINT)
    local placement, text = self:TooltipPlacement(), nil
    for _, entry in ipairs(cursor and CURSOR_ENTRIES or POINT_ENTRIES) do
        if entry.value == placement then text = entry.text end
    end
    self.tooltipPointDropdown:SetValueText(text or "")
    self.tooltipOffsetLabel:SetText(cursor and L.UI_TOOLTIP_CURSOR_OFFSET or L.UI_TOOLTIP_OFFSET)
    local keyX, keyY = cursor and "tooltipCursorX" or "tooltipX", cursor and "tooltipCursorY" or "tooltipY"
    if not self.tooltipX:HasFocus() then
        self.tooltipX:SetText(tostring(Settings:GetOption(keyX) or (cursor and 16 or 0)))
    end
    if not self.tooltipY:HasFocus() then
        self.tooltipY:SetText(tostring(Settings:GetOption(keyY) or 0))
    end
    local anchorModule = R.moduleByID and R.moduleByID["tooltips.anchor"]
    self.tooltipNote:SetText(anchorModule and anchorModule.state ~= "enabled" and L.UI_TOOLTIP_ANCHOR_OFF or "")
    self.tooltipStatus:SetText("")
end
