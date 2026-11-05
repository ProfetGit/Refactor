local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme
local MAX_ROWS = 8

-- The page answers the question a player opens it with first, what this character follows,
-- before anything else: that used to be one grey line at the bottom, under the import box.
local CONTROL_WIDTH, ROW_HEIGHT, ROW_BUTTON, NAME_WIDTH = 380, 30, 84, 220
local INPUT_WIDTH, SAVE_WIDTH, SHARE_WIDTH, SHARE_HEIGHT, STATUS_HEIGHT = 260, 104, 380, 54, 14
local DROPDOWN_GAP = 6
-- The assignment dropdown's entry for following the account, which is no profile at all.
local NO_PROFILE = ""

local function panelFrame(parent)
    local layout = UI.layout
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", layout.x, layout.top)
    panel:SetPoint("BOTTOMRIGHT", layout.right, layout.bottom)
    return panel
end

local function profileNames()
    local names = {}
    for name in pairs(Settings.account and Settings.account.profiles or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- How many of the registered features a profile switches on, as the row's summary.
local function onCount(profile)
    local on = 0
    for _, module in ipairs(R.modules) do
        if profile[module.id] then on = on + 1 end
    end
    return on
end

-- Assigning a profile also points the Editing switch at it, since from now on that is the
-- layer this character's clicks should change; leaving one puts the switch back.
function UI:AssignProfile(name)
    Settings:AssignProfile(name)
    if name then
        if Settings:SetScope("profile") then self.mode = "profile" end
    elseif self.mode == "profile" then
        Settings:SetScope("account")
        self.mode = "account"
    end
    self.pendingDelete = nil
    self:Refresh()
end

function UI:BuildProfileRow(panel, index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row.hover = Theme:RowHighlight(row)
    row.name = Theme:Text(row, "", "body", "TEXT_BODY")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetWordWrap(false)
    row.summary = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.summary:SetPoint("LEFT", row.name, "RIGHT", 12, 0)
    row.summary:SetWordWrap(false)
    row.delete = Theme:Button(row, ROW_BUTTON, L.UI_PROFILE_DELETE, function()
        -- Two presses: the first arms the row and says so, the second deletes.
        if self.pendingDelete ~= row.profileName then
            self.pendingDelete = row.profileName
            self:LoadProfiles()
            return
        end
        self.pendingDelete = nil
        Settings:DeleteProfile(row.profileName)
        self.profileStatus:SetText(string.format(L.UI_PROFILE_DELETED, row.profileName))
        self:Refresh()
    end)
    row.delete:SetPoint("RIGHT", -8, 0)
    row.export = Theme:Button(row, ROW_BUTTON, L.UI_PROFILE_EXPORT, function()
        self.pendingDelete = nil
        self.profileString:SetText(Settings:ExportProfile(row.profileName) or "")
        self.profileString:SetFocus()
        self.profileString:HighlightText()
        self.profileStatus:SetText(L.UI_PROFILE_EXPORTED)
        self:LoadProfiles()
    end)
    row.export:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function() row.hover:To(1) end)
    row:SetScript("OnLeave", function() row.hover:To(0) end)
    row:Hide()
    panel:Place(row, ROW_HEIGHT, 0)
    row:SetPoint("RIGHT")
    self.profileRows[index] = row
end

function UI:BuildProfiles(parent)
    local panel = self.Widgets:Stack(panelFrame(parent), self.panelWidth)
    panel.helpKey, panel.countKey = "UI_PROFILES_HELP", "UI_PROFILES"
    self.profilePanel = panel

    self.profileAssign = Theme:Dropdown(panel, CONTROL_WIDTH, {},
        function(value) return (Settings:AssignedProfile() or NO_PROFILE) == value end,
        function(value) self:AssignProfile(value ~= NO_PROFILE and value or nil) end)
    panel:Place(self.profileAssign, Theme.dropdownRowHeight, DROPDOWN_GAP)
    self.profileAssign:SetLabel(L.UI_PROFILE_USES)
    self.profileAssigned = panel:Note(nil, L.UI_PROFILE_UNASSIGNED,
        string.format(L.UI_PROFILE_ASSIGNED, string.rep("W", 24)))

    panel:Group(L.UI_PROFILE_SAVED)
    self.profileEmpty = Theme:Text(panel, L.UI_PROFILE_NONE, "small", "TEXT_MUTED")
    self.profileEmpty:SetPoint("TOPLEFT", 8, panel.cursor - 8)
    self.profileRowsTop = panel.cursor
    self.profileRows = {}
    for index = 1, MAX_ROWS do self:BuildProfileRow(panel, index) end
    self.profileMore = Theme:Text(panel, "", "small", "TEXT_MUTED")

    -- Everything under the list follows the rows actually shown, so one profile does not
    -- leave the space of eight above the next group.
    local lower = self.Widgets:Stack(CreateFrame("Frame", nil, panel), self.panelWidth)
    lower:SetHeight(1)
    self.profileLower = lower
    lower:Skip(self.Widgets.GROUP_GAP)
    lower:Group(L.UI_PROFILE_NEW)
    self.profileName = self.Widgets:Input(lower, INPUT_WIDTH)
    lower:Place(self.profileName, self.Widgets.INPUT_HEIGHT, self.Widgets.NOTE_GAP)
    local create = Theme:Button(lower, SAVE_WIDTH, L.UI_PROFILE_CREATE, function()
        self:CreateProfileFromCharacter()
    end)
    create:SetPoint("LEFT", self.profileName, "RIGHT", 8, 0)
    self.profileName:SetScript("OnEnterPressed", function() self:CreateProfileFromCharacter() end)
    lower:Note(L.UI_PROFILE_NEW_HELP)

    lower:Group(L.UI_PROFILE_SHARE)
    self.profileString = self.Widgets:Input(lower, SHARE_WIDTH, SHARE_HEIGHT, true)
    lower:Place(self.profileString, SHARE_HEIGHT, self.Widgets.NOTE_GAP)
    local import = Theme:Button(lower, SAVE_WIDTH, L.UI_PROFILE_IMPORT, function()
        self.pendingDelete = nil
        local ok, result = Settings:ImportProfile(self.profileString:GetText())
        self.profileStatus:SetText(ok and string.format(L.UI_PROFILE_IMPORTED, result)
            or L["UI_PROFILE_ERR_" .. tostring(result)] or L.UI_PROFILE_INVALID)
        if ok then
            self.profileString:SetText("")
            self.profileString:ClearFocus()
            self:Refresh()
        end
    end)
    import:SetPoint("TOPLEFT", self.profileString, "TOPRIGHT", 8, 0)

    self.profileStatus = Theme:Text(lower, "", "small", "TEXT_TITLE")
    lower:Place(self.profileStatus, STATUS_HEIGHT)
    self.profileStatus:SetPoint("RIGHT")

    panel.Update = function() self:LoadProfiles() end
    self:RegisterPanel("Profiles", panel)
end

-- A new profile starts from what this character resolves to today, which is what the player
-- is looking at when they press the button.
function UI:CreateProfileFromCharacter()
    self.pendingDelete = nil
    local values = {}
    for _, module in ipairs(R.modules) do
        values[module.id] = Settings:Get(module.id)
    end
    local name = self.profileName:GetText()
    if name == "" then
        self.profileStatus:SetText(L.UI_PROFILE_NAME_MISSING)
        return
    end
    local ok, err = Settings:CreateProfile(name, values)
    self.profileStatus:SetText(ok and string.format(L.UI_PROFILE_CREATED, name)
        or L["UI_PROFILE_ERR_" .. tostring(err)] or L.UI_PROFILE_INVALID)
    if ok then
        self.profileName:SetText("")
        self.profileName:ClearFocus()
        self:Refresh()
    end
end

function UI:LoadProfiles()
    if not self.profileRows then
        return
    end
    local names = profileNames()
    local assigned = Settings:AssignedProfile()
    local entries = { { value = NO_PROFILE, text = L.UI_ACCOUNT } }
    for _, name in ipairs(names) do entries[#entries + 1] = { value = name, text = name } end
    self.profileAssign:SetEntries(entries)
    self.profileAssign:SetValueText(assigned or L.UI_ACCOUNT)
    self.profileAssigned:SetText(assigned and string.format(L.UI_PROFILE_ASSIGNED, assigned)
        or L.UI_PROFILE_UNASSIGNED)
    local total = #R.modules
    for index, row in ipairs(self.profileRows) do
        local name = names[index]
        row.profileName = name
        row:SetShown(name ~= nil)
        if name then
            row.name:SetText(name)
            Theme:Color(row.name, name == assigned and "TEXT_TITLE" or "TEXT_BODY", true)
            local summary = string.format(L.UI_PROFILE_SUMMARY, onCount(Settings.account.profiles[name]), total)
            row.summary:SetText(name == assigned and (summary .. L.UI_PROFILE_IN_USE) or summary)
            local arming = self.pendingDelete == name
            row.delete.label:SetText(arming and L.UI_PROFILE_CONFIRM or L.UI_PROFILE_DELETE)
        end
    end
    self.profileEmpty:SetShown(#names == 0)
    local shown = math.min(#names, MAX_ROWS)
    local bottom = self.profileRowsTop - math.max(1, shown) * ROW_HEIGHT
    self.profileMore:SetShown(#names > MAX_ROWS)
    if #names > MAX_ROWS then
        self.profileMore:SetText(string.format(L.UI_PROFILE_MORE, #names - MAX_ROWS))
        self.profileMore:ClearAllPoints()
        self.profileMore:SetPoint("TOPLEFT", 8, bottom - 4)
        bottom = bottom - STATUS_HEIGHT - 4
    end
    self.profileLower:ClearAllPoints()
    self.profileLower:SetPoint("TOPLEFT", 0, bottom)
    self.profileLower:SetPoint("RIGHT")
end
