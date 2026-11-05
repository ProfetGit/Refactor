local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

local STATE_KEYS = {
    enabled = "UI_STATE_ENABLED", disabled = "UI_STATE_DISABLED",
    unavailable = "UI_STATE_UNAVAILABLE", failed = "UI_STATE_FAILED",
}

local ROW_HEIGHT, LIST_HEIGHT, SUMMARY_HEIGHT, CATEGORY_WIDTH, STATE_WIDTH = 22, 250, 24, 110, 120
-- The colour each state reads in, as a dot before its word: the list is scanned for anything
-- not green long before it is read.
local STATE_TOKENS = {
    enabled = "RING_DONE", disabled = "TEXT_MUTED", unavailable = "TEXT_WARNING", failed = "TEXT_ERROR",
}

local function stateDot(state)
    local color = Theme.colors[STATE_TOKENS[state] or "TEXT_MUTED"]
    return Theme:Dot(color[1], color[2], color[3])
end

-- The full reason, which the state column has no room for, on hover.
local function rowEnter(row)
    if not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(UI:ModuleText(row.module, "name"))
    local r, g, b = unpack(Theme.colors.TEXT_BODY)
    GameTooltip:AddLine(UI:StatusReason(row.module) or L[STATE_KEYS[row.module.state] or "UI_STATE_DISABLED"],
        r, g, b, true)
    GameTooltip:Show()
end

local function rowLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function UI:BuildDiagnostics(parent)
    local layout = self.layout
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", layout.x, layout.top)
    panel:SetPoint("BOTTOMRIGHT", layout.right, layout.bottom)
    panel.helpKey, panel.countKey = "UI_DIAGNOSTICS_HELP", "UI_DIAGNOSTICS"
    self.statusSummary = Theme:Text(panel, "", "body", "TEXT_TITLE")
    self.statusSummary:SetPoint("TOPLEFT", 0, 0)
    self.statusSummary:SetPoint("RIGHT")
    -- The module list outgrew the panel, so it scrolls; everything else sits below it.
    local list = self.Widgets:Scroll(panel)
    list:SetPoint("TOPLEFT", 0, -SUMMARY_HEIGHT)
    list:SetPoint("TOPRIGHT", -16, -SUMMARY_HEIGHT)
    list:SetHeight(LIST_HEIGHT)
    self.statusList = list
    self.statusRows = {}
    for index, module in ipairs(R.modules) do
        local row = CreateFrame("Frame", nil, list.child)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", list.child, "RIGHT", -8, 0)
        row.module = module
        row.hover = Theme:RowHighlight(row)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(widget) widget.hover:To(1) rowEnter(widget) end)
        row:SetScript("OnLeave", function(widget) widget.hover:To(0) rowLeave() end)
        row.state = Theme:Text(row, "", "small", "TEXT_MUTED")
        row.state:SetPoint("RIGHT", -6, 0)
        row.state:SetWidth(STATE_WIDTH)
        row.state:SetJustifyH("LEFT")
        row.state:SetWordWrap(false)
        row.category = Theme:Text(row, L["UI_" .. module.category] or module.category or "", "small", "TEXT_MUTED")
        row.category:SetPoint("RIGHT", row.state, "LEFT", -8, 0)
        row.category:SetWidth(CATEGORY_WIDTH)
        row.category:SetWordWrap(false)
        row.name = Theme:Text(row, "", "small", "TEXT_BODY")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetPoint("RIGHT", row.category, "LEFT", -8, 0)
        row.name:SetWordWrap(false)
        self.statusRows[index] = row
    end

    local offset = -SUMMARY_HEIGHT - LIST_HEIGHT - 18
    self.errorCount = Theme:Text(panel, "", "body", "TEXT_TITLE")
    self.errorCount:SetPoint("TOPLEFT", 0, offset)
    self.errorCount:SetPoint("RIGHT")
    local showErrors = Theme:Button(panel, 160, L.UI_DIAG_ERRORS, function()
        for _, line in ipairs(R.Commands:Dispatch("errors") or {}) do
            R:Print(line)
        end
    end)
    showErrors:SetPoint("TOPLEFT", 0, offset - 26)
    local clearErrors = Theme:Button(panel, 160, L.UI_DIAG_CLEAR, function()
        R.Commands:Clear()
        self:Refresh()
    end)
    clearErrors:SetPoint("LEFT", showErrors, "RIGHT", 8, 0)

    local exportLabel = Theme:Text(panel, L.UI_DIAG_EXPORT, "body", "TEXT_TITLE")
    exportLabel:SetPoint("TOPLEFT", 0, offset - 68)
    self.diagString = self.Widgets:Input(panel, 340, 54, true)
    self.diagString:SetPoint("TOPLEFT", 0, offset - 92)
    local copy = Theme:Button(panel, 160, L.UI_DIAG_COPY, function()
        -- Support tool, not a feature: one string that says exactly what is switched on.
        local values = {}
        for _, module in ipairs(R.modules) do
            values[module.id] = Settings:Get(module.id)
        end
        self.diagString:SetText(R.Codec:EncodeProfile(L.UI_DIAG_SNAPSHOT, values) or "")
        self.diagString:SetFocus()
    end)
    copy:SetPoint("LEFT", self.diagString, "RIGHT", 8, 0)

    self.diagArt = Theme:Text(panel, "", "small", "TEXT_WARNING")
    self.diagArt:SetPoint("TOPLEFT", 0, offset - 152)
    self.diagArt:SetPoint("RIGHT")
    self.diagArt:SetJustifyV("TOP")

    panel.Update = function() self:LoadDiagnostics() end
    self:RegisterPanel("Diagnostics", panel)
end

function UI:LoadDiagnostics()
    if not self.statusRows then
        return
    end
    self.statusList:UpdateExtent(#self.statusRows * ROW_HEIGHT)
    local counts = { enabled = 0, disabled = 0, unavailable = 0, failed = 0 }
    for _, row in ipairs(self.statusRows) do
        local module = row.module
        local state = STATE_KEYS[module.state] and module.state or "disabled"
        counts[state] = counts[state] + 1
        row.name:SetText(self:ModuleText(module, "name"))
        row.state:SetText(stateDot(state) .. " " .. L[STATE_KEYS[state]])
        Theme:Color(row.state, state == "enabled" and "TEXT_ACTIVE" or state == "disabled" and "TEXT_MUTED"
            or STATE_TOKENS[state], true)
    end
    self.statusSummary:SetText(string.format(L.UI_DIAG_SUMMARY, counts.enabled, counts.disabled,
        counts.unavailable, counts.failed))
    self.errorCount:SetText(string.format(L.UI_DIAG_COUNT, #R.errors))
    local missing = {}
    for atlas in pairs(Theme.missingAtlases) do
        missing[#missing + 1] = atlas
    end
    table.sort(missing)
    self.diagArt:SetText(#missing > 0 and string.format(L.UI_DIAG_ART, table.concat(missing, ", ")) or "")
end
