local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme
local MAX_ROWS = 8

function UI:BuildConflicts(parent)
    local layout = self.layout
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", layout.x, layout.top)
    panel:SetPoint("BOTTOMRIGHT", layout.right, layout.bottom)
    panel.helpKey, panel.countKey = "UI_CONFLICTS_HELP", "UI_CONFLICTS_TITLE"
    self.conflictRows = {}
    self.conflictList = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(44)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * 48)
        row:SetPoint("RIGHT", -160, 0)
        row.title = Theme:Text(row, "", "body", "TEXT_BODY")
        row.title:SetPoint("TOPLEFT")
        row.title:SetPoint("RIGHT")
        row.detail = Theme:Text(row, "", "small", "TEXT_MUTED")
        row.detail:SetPoint("TOPLEFT", 0, -20)
        row.detail:SetPoint("RIGHT")
        row.resolve = Theme:Button(row, 148, L.UI_CONFLICT_DISABLE, function()
            if row.moduleID then
                Settings:SetAccount(row.moduleID, false)
                Settings:SetOverride(row.moduleID, nil)
                self:Refresh()
            end
        end)
        row.resolve:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, -6)
        row:Hide()
        self.conflictRows[index] = row
    end
    self.conflictEmpty = Theme:Text(panel, L.UI_CONFLICT_NONE, "body", "TEXT_MUTED")
    self.conflictEmpty:SetPoint("TOPLEFT", 0, -4)
    self.conflictEmpty:SetPoint("RIGHT")
    panel.Update = function() self:LoadConflicts() end
    self:RegisterPanel("Conflicts", panel)
end

function UI:LoadConflicts()
    if not self.conflictRows then
        return
    end
    local conflicts = R.Integrations:Conflicts(self.conflictList)
    for index, row in ipairs(self.conflictRows) do
        local conflict = conflicts[index]
        row:SetShown(conflict ~= nil)
        if conflict then
            local module = conflict.module
            row.moduleID = module.id
            row.title:SetText(string.format(L.UI_CONFLICT_ROW, L[conflict.labelKey] or conflict.addon,
                self:ModuleText(module, "name")))
            local deferred = module.state == "unavailable" and module.unavailableReason
            row.detail:SetText(deferred or (Settings:Get(module.id) and L.UI_CONFLICT_BOTH_ON
                or L.UI_CONFLICT_MINE_OFF))
            row.resolve:SetEnabled(Settings:Get(module.id) == true)
        end
    end
    self.conflictEmpty:SetShown(#conflicts == 0)
end
