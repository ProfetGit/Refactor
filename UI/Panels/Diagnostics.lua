local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

local STATE_KEYS = {
    enabled = "UI_STATE_ENABLED", disabled = "UI_STATE_DISABLED",
    unavailable = "UI_STATE_UNAVAILABLE", failed = "UI_STATE_FAILED",
    unconfirmed = "UI_STATE_UNCONFIRMED",
}

local ROW_HEIGHT, LIST_HEIGHT = 22, 250

function UI:BuildDiagnostics(parent)
    local layout = self.layout
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", layout.x, layout.top)
    panel:SetPoint("BOTTOMRIGHT", layout.right, layout.bottom)
    panel.helpKey, panel.countKey = "UI_DIAGNOSTICS_HELP", "UI_DIAGNOSTICS"
    -- The module list outgrew the panel, so it scrolls; everything else sits below it.
    local list = self.Widgets:Scroll(panel)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("TOPRIGHT", -16, 0)
    list:SetHeight(LIST_HEIGHT)
    self.statusList = list
    self.statusRows = {}
    for index, module in ipairs(R.modules) do
        local row = CreateFrame("Frame", nil, list.child)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", list.child, "RIGHT", -8, 0)
        row.module = module
        row.name = Theme:Text(row, "", "small", "TEXT_BODY")
        row.name:SetPoint("LEFT")
        row.name:SetPoint("RIGHT", -180, 0)
        row.state = Theme:Text(row, "", "small", "TEXT_MUTED")
        row.state:SetPoint("RIGHT")
        row.state:SetWidth(176)
        row.state:SetJustifyH("RIGHT")
        self.statusRows[index] = row
    end

    local offset = -LIST_HEIGHT - 18
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
    self.diagArt:SetHeight(30)
    self.diagArt:SetJustifyV("TOP")

    panel.Update = function() self:LoadDiagnostics() end
    self:RegisterPanel("Diagnostics", panel)
end

function UI:LoadDiagnostics()
    if not self.statusRows then
        return
    end
    self.statusList:UpdateExtent(#self.statusRows * ROW_HEIGHT)
    for _, row in ipairs(self.statusRows) do
        local module = row.module
        row.name:SetText(self:ModuleText(module, "name"))
        local reason = self:StatusReason(module)
        row.state:SetText(reason or L[STATE_KEYS[module.state] or "UI_STATE_DISABLED"])
        Theme:Color(row.state, reason and "TEXT_WARNING"
            or module.state == "enabled" and "TEXT_ACTIVE" or "TEXT_MUTED", true)
    end
    self.errorCount:SetText(string.format(L.UI_DIAG_COUNT, #R.errors))
    local missing = {}
    for atlas in pairs(Theme.missingAtlases) do
        missing[#missing + 1] = atlas
    end
    table.sort(missing)
    self.diagArt:SetText(#missing > 0 and string.format(L.UI_DIAG_ART, table.concat(missing, ", ")) or "")
end
