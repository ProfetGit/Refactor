local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme
local MAX_ROWS = 8
local ROW_HEIGHT, ROW_GAP, BUTTON_WIDTH, BUTTON_PAD = 44, 4, 148, 160

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
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))
        row:SetPoint("RIGHT", -BUTTON_PAD, 0)
        row.title = Theme:Text(row, "", "body", "TEXT_BODY")
        row.title:SetPoint("TOPLEFT", 0, -4)
        row.title:SetPoint("RIGHT")
        row.title:SetWordWrap(false)
        row.detail = Theme:Text(row, "", "small", "TEXT_MUTED")
        row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
        row.detail:SetPoint("RIGHT")
        row.detail:SetWordWrap(false)
        row.resolve = Theme:Button(row, BUTTON_WIDTH, L.UI_CONFLICT_DISABLE, function()
            if row.moduleID then
                Settings:SetAccount(row.moduleID, false)
                Settings:SetOverride(row.moduleID, nil)
                self:Refresh()
            end
        end)
        row.resolve:SetPoint("LEFT", row, "RIGHT", 8, 0)
        row:Hide()
        self.conflictRows[index] = row
    end
    self.conflictEmpty = Theme:Text(panel, L.UI_CONFLICT_NONE, "body", "TEXT_MUTED")
    self.conflictEmpty:SetPoint("TOPLEFT", 0, -4)
    self.conflictEmpty:SetPoint("RIGHT")
    -- What is looked for, so an empty page reads as checked rather than as not working.
    self.conflictChecked = Theme:Text(panel, "", "small", "TEXT_MUTED")
    self.conflictChecked:SetPoint("RIGHT")
    self.conflictChecked:SetJustifyV("TOP")
    panel.Update = function() self:LoadConflicts() end
    self:RegisterPanel("Conflicts", panel)
end

-- Every neighbour's name once, in the order they are listed.
local function checkedNames()
    local seen, names = {}, {}
    for _, neighbour in ipairs(R.Integrations.neighbours or {}) do
        local name = L[neighbour.labelKey] or neighbour.addon
        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return table.concat(names, ", ")
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
            local on = Settings:Get(module.id) == true
            row.detail:SetText(deferred or (on and L.UI_CONFLICT_BOTH_ON or L.UI_CONFLICT_MINE_OFF))
            Theme:Color(row.detail, on and not deferred and "TEXT_WARNING" or "TEXT_MUTED", true)
            row.resolve:SetShown(on and not deferred)
        end
    end
    self.conflictEmpty:SetShown(#conflicts == 0)
    local shown = math.min(#conflicts, MAX_ROWS)
    self.conflictChecked:ClearAllPoints()
    self.conflictChecked:SetPoint("TOPLEFT", 0, shown > 0 and -(shown * (ROW_HEIGHT + ROW_GAP) + 8) or -28)
    self.conflictChecked:SetPoint("RIGHT")
    self.conflictChecked:SetText(string.format(L.UI_CONFLICT_CHECKED, checkedNames()))
end
