local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme
local MAX_ROWS = 8

local function panelFrame(parent)
    local layout = UI.layout
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", layout.x, layout.top)
    panel:SetPoint("BOTTOMRIGHT", layout.right, layout.bottom)
    return panel
end

function UI:BuildProfiles(parent)
    local panel = panelFrame(parent)
    panel.helpKey, panel.countKey = "UI_PROFILES_HELP", "UI_PROFILES"
    self.profilePanel = panel
    self.profileRows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * 28)
        row:SetPoint("RIGHT", -300, 0)
        row.name = Theme:Text(row, "", "body", "TEXT_BODY")
        row.name:SetPoint("LEFT")
        row.assign = Theme:Button(row, 92, L.UI_PROFILE_ASSIGN, function()
            Settings:AssignProfile(row.profileName)
            self:LoadProfiles()
        end)
        row.assign:SetPoint("LEFT", row, "RIGHT", 8, 0)
        row.export = Theme:Button(row, 92, L.UI_PROFILE_EXPORT, function()
            self.profileString:SetText(Settings:ExportProfile(row.profileName) or "")
            self.profileString:SetFocus()
            self.profileStatus:SetText(L.UI_PROFILE_EXPORTED)
        end)
        row.export:SetPoint("LEFT", row.assign, "RIGHT", 6, 0)
        row.delete = Theme:Button(row, 92, L.UI_PROFILE_DELETE, function()
            Settings:DeleteProfile(row.profileName)
            self:LoadProfiles()
        end)
        row.delete:SetPoint("LEFT", row.export, "RIGHT", 6, 0)
        row:Hide()
        self.profileRows[index] = row
    end

    self.profileEmpty = Theme:Text(panel, L.UI_PROFILE_NONE, "small", "TEXT_MUTED")
    self.profileEmpty:SetPoint("TOPLEFT", 0, -4)
    self.profileEmpty:SetPoint("RIGHT")

    local createLabel = Theme:Text(panel, L.UI_PROFILE_NEW, "body", "TEXT_TITLE")
    createLabel:SetPoint("TOPLEFT", 0, -(MAX_ROWS * 28) - 16)
    self.profileName = self.Widgets:Input(panel, 260, 30)
    self.profileName:SetPoint("TOPLEFT", 0, -(MAX_ROWS * 28) - 40)
    local create = Theme:Button(panel, 140, L.UI_PROFILE_CREATE, function()
        -- A new profile starts from what this character resolves to today, which is what
        -- the player is looking at when they press the button.
        local values = {}
        for _, module in ipairs(R.modules) do
            values[module.id] = Settings:Get(module.id)
        end
        local ok, err = Settings:CreateProfile(self.profileName:GetText(), values)
        self.profileStatus:SetText(ok and L.UI_PROFILE_CREATED or L["UI_PROFILE_ERR_" .. tostring(err)]
            or L.UI_PROFILE_INVALID)
        if ok then
            self.profileName:SetText("")
            self:LoadProfiles()
        end
    end)
    create:SetPoint("LEFT", self.profileName, "RIGHT", 8, 0)

    local shareLabel = Theme:Text(panel, L.UI_PROFILE_SHARE, "body", "TEXT_TITLE")
    shareLabel:SetPoint("TOPLEFT", 0, -(MAX_ROWS * 28) - 84)
    self.profileString = self.Widgets:Input(panel, 260, 54, true)
    self.profileString:SetPoint("TOPLEFT", 0, -(MAX_ROWS * 28) - 108)
    local import = Theme:Button(panel, 140, L.UI_PROFILE_IMPORT, function()
        local ok, result = Settings:ImportProfile(self.profileString:GetText())
        self.profileStatus:SetText(ok and string.format(L.UI_PROFILE_IMPORTED, result)
            or L["UI_PROFILE_ERR_" .. tostring(result)] or L.UI_PROFILE_INVALID)
        if ok then
            self.profileString:SetText("")
            self:LoadProfiles()
        end
    end)
    import:SetPoint("LEFT", self.profileString, "RIGHT", 8, 0)

    self.profileStatus = Theme:Text(panel, "", "small", "TEXT_TITLE")
    self.profileStatus:SetPoint("TOPLEFT", 0, -(MAX_ROWS * 28) - 170)
    self.profileStatus:SetPoint("RIGHT")

    self.profileAssigned = Theme:Text(panel, "", "small", "TEXT_MUTED")
    self.profileAssigned:SetPoint("TOPLEFT", 0, -(MAX_ROWS * 28) - 190)
    self.profileAssigned:SetPoint("RIGHT")

    panel.Update = function() self:LoadProfiles() end
    self:RegisterPanel("Profiles", panel)
end

function UI:LoadProfiles()
    if not self.profileRows then
        return
    end
    local account = Settings.account
    local names = {}
    for name in pairs(account and account.profiles or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    local assigned = account and Settings.guid and account.assignments[Settings.guid]
    for index, row in ipairs(self.profileRows) do
        local name = names[index]
        row.profileName = name
        row:SetShown(name ~= nil)
        if name then
            row.name:SetText(name)
            Theme:Color(row.name, name == assigned and "TEXT_TITLE" or "TEXT_BODY", true)
            row.assign:SetEnabled(name ~= assigned)
        end
    end
    self.profileEmpty:SetShown(#names == 0)
    self.profileAssigned:SetText(assigned and string.format(L.UI_PROFILE_ASSIGNED, assigned)
        or L.UI_PROFILE_UNASSIGNED)
end
