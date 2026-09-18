local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

local ANCHOR_MODES = { "cursor", "point" }
local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local CURSOR_SIDES = { "RIGHT", "LEFT", "CENTER" }

local function cycle(list, current)
    for index, value in ipairs(list) do
        if value == current then return list[index % #list + 1] end
    end
    return list[1]
end

-- One section of the Options page. Everything here applies on click, except the typed
-- offsets, which wait for Save.
function UI:BuildTooltips(parent)
    local section = self.Widgets:Section(parent, L.UI_TOOLTIP_OPTIONS, L.UI_TOOLTIP_HELP)
    local top = section.top
    self.tooltipModeButton = Theme:Button(section, 300, "", function()
        Settings:SetOption("tooltipAnchor", cycle(ANCHOR_MODES, Settings:GetOption("tooltipAnchor")))
        self:LoadTooltips()
    end)
    self.tooltipModeButton:SetPoint("TOPLEFT", 0, top)
    -- One button for both placement lists: which one it cycles follows the mode above.
    self.tooltipPointButton = Theme:Button(section, 300, "", function()
        if Settings:GetOption("tooltipAnchor") == "cursor" then
            Settings:SetOption("tooltipCursorSide", cycle(CURSOR_SIDES, Settings:GetOption("tooltipCursorSide")))
        else
            Settings:SetOption("tooltipPoint", cycle(POINTS, Settings:GetOption("tooltipPoint")))
        end
        self:LoadTooltips()
    end)
    self.tooltipPointButton:SetPoint("TOPLEFT", 0, top - 30)
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
    return section
end

function UI:LoadTooltips()
    if not self.tooltipModeButton then return end
    local cursor = Settings:GetOption("tooltipAnchor") ~= "point"
    self.tooltipModeButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOOLTIP_MODE,
        cursor and L.UI_TOOLTIP_MODE_CURSOR or L.UI_TOOLTIP_MODE_POINT))
    if cursor then
        self.tooltipPointButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOOLTIP_CURSOR_SIDE,
            L["UI_TOOLTIP_SIDE_" .. (Settings:GetOption("tooltipCursorSide") or "RIGHT")]))
    else
        self.tooltipPointButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOOLTIP_POINT,
            Settings:GetOption("tooltipPoint") or "BOTTOMRIGHT"))
    end
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
