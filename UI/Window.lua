local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = LibStub("LibRefactorTheme-1.0")
local unpack = unpack

-- One sidebar entry per group of categories, not per category: a category stays on every
-- row as its breadcrumb (PRD 8.2), so the sidebar only has to be a short way in. Panels
-- are the tool pages. Every module category must appear in exactly one group; a spec
-- checks that so a new category cannot silently vanish from the sidebar.
local SIDEBAR = {
    { key = "All", labelKey = "UI_ALL" },
    { key = "Quests", labelKey = "UI_GROUP_QUESTS", categories = { "Quest", "Loot", "Toasts" } },
    { key = "Vendor", labelKey = "UI_GROUP_VENDOR", categories = { "Vendor", "Items" } },
    { key = "Interface", labelKey = "UI_GROUP_INTERFACE",
        categories = { "Interface", "Chat", "Social", "Nameplates" } },
    { key = "Tooltips", labelKey = "UI_Tooltips", categories = { "Tooltips" } },
    { key = "Automation", labelKey = "UI_Automation", categories = { "Automation" }, tone = "TEXT_WARNING" },
    { key = "Options", labelKey = "UI_OPTIONS", tools = true },
    { key = "Profiles", labelKey = "UI_Profiles", tools = true },
    { key = "Conflicts", labelKey = "UI_Conflicts", tools = true },
    { key = "Diagnostics", labelKey = "UI_Diagnostics", tools = true },
}
for _, entry in ipairs(SIDEBAR) do
    if entry.categories then
        entry.set = {}
        for _, category in ipairs(entry.categories) do entry.set[category] = true end
    end
end
UI.sidebar = SIDEBAR

local PAD, SIDEBAR_WIDTH, SIDEBAR_ROW, SIDEBAR_TOP = 24, 148, 24, -64
local CONTENT_X = PAD + SIDEBAR_WIDTH + 22
local SEARCH_TOP, SEARCH_HEIGHT = -22, 26
local TAB_BASELINE, HELP_Y = -72, -80
local SECTION_GAP = 24
UI.layout = { x = CONTENT_X, top = -102, right = -36, bottom = 48 }
local ROW_HEIGHT = 58
local modifiers = { "CTRL", "SHIFT", "ALT" }

local function accountValue(module)
    local value = Settings.account and Settings.account.modules[module.id]
    if value == nil then value = Settings.defaults[module.id] end
    return value == true
end

-- On or off, nothing else. A character override is written explicitly rather than cycling
-- through Inherit, so the checkbox always shows exactly what this character will do.
function UI:SetModuleEnabled(module, enabled)
    if not Settings.account then return end
    if enabled and module.risk == "automation" and not Settings:IsConfirmed(module.id) then
        self:Refresh()
        self:ConfirmAutomation(module, function() self:SetModuleEnabled(module, true) end)
        return
    end
    if self.mode == "account" then
        Settings:SetAccount(module.id, enabled)
    else
        Settings:SetOverride(module.id, enabled)
    end
    self:Refresh()
end

-- What "undo" means depends on the tab: a character override goes back to inheriting,
-- an account value goes back to the shipped default.
function UI:IsModified(module)
    if self.mode == "account" then
        local value = Settings.account and Settings.account.modules[module.id]
        return value ~= nil and value ~= Settings.defaults[module.id]
    end
    return Settings:GetOverride(module.id) ~= nil
end

function UI:ResetModule(module)
    if self.mode == "account" then Settings:SetAccount(module.id, nil)
    else Settings:SetOverride(module.id, nil) end
    self:Refresh()
end

function UI:Cycle(module)
    self:SetModuleEnabled(module, not Settings:Get(module.id))
end

function UI:SavePosition()
    if not Settings.character then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    Settings.character.window = { point = point, relativePoint = relativePoint, x = x, y = y }
end

function UI:RestorePosition()
    if self.restored or not Settings.character then return end
    self.restored = true
    local saved = Settings.character.window
    local validPoints = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    if validPoints[saved.point] and validPoints[saved.relativePoint]
        and type(saved.x) == "number" and type(saved.y) == "number" then
        self.frame:ClearAllPoints()
        self.frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then self.frame:Hide()
    else self:Refresh(); self.frame:Show() end
end

function UI:DetailText(module)
    local title = self:ModuleText(module, "name")
    local overlaps = L.UI_NO_CONFLICTS
    if module.conflicts and #module.conflicts > 0 then overlaps = table.concat(module.conflicts, ", ") end
    local reason = self:StatusReason(module)
    local body = self:ModuleText(module, "detail") .. "\n\n" .. L.UI_CONFLICTS .. "\n" .. overlaps
        .. "\n\n" .. L.UI_RECOVERY .. (reason and "\n\n" .. reason or "")
    return title, body
end

-- The detail is a tooltip on the row's "i", so it needs no click and no dialog to dismiss.
function UI:ShowDetails(module, owner)
    if not GameTooltip then return end
    local title, body = self:DetailText(module)
    local r, g, b = unpack(Theme.colors.TEXT_BODY)
    GameTooltip:SetOwner(owner or self.frame, "ANCHOR_LEFT")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(body, r, g, b, true)
    GameTooltip:Show()
end

function UI:HideDetails()
    if GameTooltip then GameTooltip:Hide() end
end

function UI:StatusReason(module)
    if module.state == "unavailable" then
        local reason = module.unavailableReason or (module.unavailableReasonKey and L[module.unavailableReasonKey])
        if not reason and module.missing then reason = table.concat(module.missing, ", ") end
        return string.format(L.UI_UNAVAILABLE, reason or L.UI_STATUS_REASON)
    elseif module.state == "failed" then
        return string.format(L.UI_FAILED, module.failure or L.UI_STATUS_REASON)
    end
end

-- A sidebar entry either lists modules or owns a panel. Searching always returns to the
-- list, because search is the one interaction that must never be shadowed by a panel.
function UI:RegisterPanel(category, frame)
    self.panels = self.panels or {}
    self.panels[category] = frame
    frame:Hide()
end

function UI:SelectCategory(key)
    self.category = key
    self.search:SetText("")
    self.search:ClearFocus()
    self.scroll.slider:SetValue(0)
    if key == "Options" then self:LoadOptions() end
    if key == "Profiles" then self:LoadProfiles() end
    self:Refresh()
end

function UI:Refresh()
    if not self.frame then return end
    self:RestorePosition()
    local query = self.search:GetText() or ""
    local panel = query == "" and self.panels and self.panels[self.category] or nil
    for _, frame in pairs(self.panels or {}) do
        frame:SetShown(frame == panel)
    end
    self.scroll:SetShown(panel == nil)
    self.modeCharacter:SetShown(panel == nil)
    self.modeAccount:SetShown(panel == nil)
    Theme:TabState(self.modeCharacter, self.mode == "character")
    Theme:TabState(self.modeAccount, self.mode == "account")
    self.panelTitle:SetShown(panel ~= nil)
    self.help:SetText(panel and L[panel.helpKey or "UI_OPTIONS_HELP"]
        or self.mode == "account" and L.UI_ACCOUNT_HELP or L.UI_CHARACTER_HELP)
    local entry
    for _, button in ipairs(self.categoryButtons) do
        local selected = self.category == button.category
        if selected then entry = button.entry end
        Theme:ListButtonState(button, selected, button.entry.tone)
    end
    if panel then
        self.panelTitle:SetText(L[panel.countKey or "UI_OPTIONS"])
        if panel.Update then panel:Update() end
        self.count:SetText(L[panel.countKey or "UI_OPTIONS"])
        self.empty:Hide()
        self.scroll.slider:Hide(); self.scroll.up:Hide(); self.scroll.down:Hide()
        return
    end
    local filter = entry and entry.set or nil
    local count = 0
    for _, row in ipairs(self.rows) do
        local module = row.module
        local visible = self:Matches(module, query, filter)
        row:SetShown(visible)
        if visible then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -count * ROW_HEIGHT)
            row:SetPoint("RIGHT", self.scroll.child, "RIGHT")
            count = count + 1
            row.name:SetText(self:ModuleText(module, "name"))
            row.description:SetText(self:ModuleText(module, "description"))
            local value = self.mode == "account" and accountValue(module) or Settings:Get(module.id)
            row.toggle:SetChecked(value == true)
            local reason = self:StatusReason(module)
            row.meta:SetText(reason and (module.state == "failed" and L.UI_FAILED_SHORT or L.UI_UNAVAILABLE_SHORT)
                or module.state == "unconfirmed" and L.UI_STATE_UNCONFIRMED or "")
            Theme:Color(row.meta, reason and "TEXT_WARNING" or "TEXT_MUTED", true)
            row.toggle:SetEnabled(Settings.account ~= nil and not module.unavailableReasonKey)
            row.undo:SetShown(self:IsModified(module))
        end
    end
    self.count:SetText(string.format(query ~= "" and L.UI_MATCHES or L.UI_COUNT, count))
    self.empty:SetShown(count == 0)
    self.scroll:UpdateExtent(count * ROW_HEIGHT)
end

function UI:LoadOptions()
    local ids = {}
    for id in pairs(Settings:GetOption("neverSellIDs")) do ids[#ids + 1] = id end
    table.sort(ids)
    for index, id in ipairs(ids) do ids[index] = tostring(id) end
    self.neverSell:SetText(table.concat(ids, ", "))
    self.repairCap:SetText(tostring(Settings:GetOption("repairCapGold")))
    self.modifier = Settings:GetOption("killSwitch")
    self.modifierButton.label:SetText(L["UI_" .. self.modifier])
    self.optionStatus:SetText("")
    self:RefreshNameplateOptions()
end

function UI:SaveOptions()
    local neverSell = self:ParseNeverSell(self.neverSell:GetText())
    if not neverSell then self.optionStatus:SetText(L.UI_NEVER_SELL_INVALID); return end
    local cap = tonumber(self.repairCap:GetText())
    if not cap or cap < 0 or cap > 10000000 then self.optionStatus:SetText(L.UI_REPAIR_INVALID); return end
    if not Settings:SetOption("neverSellIDs", neverSell) then
        self.optionStatus:SetText(L.UI_NEVER_SELL_INVALID)
        return
    end
    Settings:SetOption("repairCapGold", cap)
    Settings:SetOption("killSwitch", self.modifier)
    self.neverSell:ClearFocus()
    self.repairCap:ClearFocus()
    self.optionStatus:SetText(L.UI_SAVED)
end

-- One scrolling page for every account-wide option, in sections, instead of three sidebar
-- entries. Each builder returns sections with a known height so they stack without measuring.
function UI:BuildOptions(parent)
    local layout = self.layout
    local options = CreateFrame("Frame", nil, parent)
    options:SetPoint("TOPLEFT", layout.x, layout.top)
    options:SetPoint("BOTTOMRIGHT", layout.right, layout.bottom)
    self.options = options
    local page = self.Widgets:Scroll(options)
    page:SetPoint("TOPLEFT")
    page:SetPoint("BOTTOMRIGHT", -20, 0)
    options.page = page
    local sections = { self:BuildSafetySection(page.child), self:BuildNameplateSection(page.child) }
    for _, section in ipairs(self:BuildDisplay(page.child)) do sections[#sections + 1] = section end
    sections[#sections + 1] = self:BuildTooltips(page.child)
    local offset = 0
    for _, section in ipairs(sections) do
        section:SetPoint("TOPLEFT", 0, -offset)
        section:SetPoint("RIGHT", page.child, "RIGHT", -8, 0)
        offset = offset + section.height + SECTION_GAP
    end
    options.contentHeight = offset - SECTION_GAP
    options.helpKey, options.countKey = "UI_OPTIONS_HELP", "UI_OPTIONS"
    options.Update = function()
        self:LoadDisplay()
        self:LoadTooltips()
        self:RefreshNameplateOptions()
        page:UpdateExtent(options.contentHeight)
    end
    self:RegisterPanel("Options", options)
end

function UI:BuildSafetySection(parent)
    local section = self.Widgets:Section(parent, L.UI_OPTIONS_SAFETY)
    local top = section.top
    local function label(text, y, style)
        local region = Theme:Text(section, text, style or "body", style and "TEXT_MUTED" or "TEXT_TITLE")
        region:SetPoint("TOPLEFT", 0, top + y)
        region:SetPoint("RIGHT")
        return region
    end
    label(L.UI_NEVER_SELL, 0)
    local help = label(L.UI_NEVER_SELL_HELP, -22, "small")
    help:SetHeight(28); help:SetJustifyV("TOP")
    self.neverSell = self.Widgets:Input(section, 400, 56, true)
    self.neverSell:SetPoint("TOPLEFT", 0, top - 52)
    self.neverSell:SetPoint("RIGHT")
    label(L.UI_REPAIR_CAP, -124)
    self.repairCap = self.Widgets:Input(section, 116, 26)
    self.repairCap:SetPoint("TOPLEFT", 0, top - 146)
    help = label(L.UI_REPAIR_CAP_HELP, -178, "small")
    help:SetHeight(28); help:SetJustifyV("TOP")
    label(L.UI_KILL_SWITCH, -216)
    self.modifierButton = Theme:Button(section, 116, L.UI_CTRL, function()
        for index, modifier in ipairs(modifiers) do
            if self.modifier == modifier then self.modifier = modifiers[index % #modifiers + 1]; break end
        end
        self.modifierButton.label:SetText(L["UI_" .. self.modifier])
    end)
    self.modifierButton:SetPoint("TOPLEFT", 0, top - 238)
    help = label(L.UI_KILL_SWITCH_HELP, -268, "small")
    help:SetHeight(28); help:SetJustifyV("TOP")
    self.saveOptions = Theme:Button(section, 152, L.UI_SAVE, function() self:SaveOptions() end)
    self.saveOptions:SetPoint("TOPLEFT", 0, top - 306)
    self.optionStatus = Theme:Text(section, "", "small", "TEXT_TITLE")
    self.optionStatus:SetPoint("LEFT", self.saveOptions, "RIGHT", 12, 0)
    self.optionStatus:SetPoint("RIGHT")
    section:SetBodyHeight(332)
    return section
end

local nameplateToggles = {
    { key = "nameplateShowRing", label = "UI_NAMEPLATE_RING" },
    { key = "nameplateShowIcon", label = "UI_NAMEPLATE_ICON" },
    { key = "nameplateDimCompleted", label = "UI_NAMEPLATE_DIM" },
    { key = "nameplateReduceAnimation", label = "UI_NAMEPLATE_REDUCE" },
    { key = "minimapButton", label = "UI_MINIMAP_BUTTON" },
}

-- Booleans apply on click. Only the typed fields wait for Save.
function UI:BuildNameplateSection(parent)
    local section = self.Widgets:Section(parent, L.UI_NAMEPLATE_OPTIONS, L.UI_NAMEPLATE_HELP)
    local top = section.top
    self.nameplateButtons = {}
    local side = Theme:Button(section, 240, "", function()
        local next = Settings:GetOption("nameplateSide") == "RIGHT" and "LEFT" or "RIGHT"
        Settings:SetOption("nameplateSide", next)
        self:RefreshNameplateOptions()
    end)
    side:SetPoint("TOPLEFT", 0, top)
    self.nameplateSideButton = side
    for index, toggle in ipairs(nameplateToggles) do
        local box = Theme:Checkbox(section, 300, L[toggle.label], function(widget)
            Settings:SetOption(toggle.key, widget:GetChecked() == true)
            self:RefreshNameplateOptions()
        end)
        box:SetPoint("TOPLEFT", 0, top - 6 - index * 32)
        box.optionKey = toggle.key
        self.nameplateButtons[index] = box
    end
    section:SetBodyHeight(6 + #nameplateToggles * 32 + 26)
    return section
end

function UI:RefreshNameplateOptions()
    if not self.nameplateButtons then return end
    local side = Settings:GetOption("nameplateSide") == "LEFT" and L.UI_LEFT or L.UI_RIGHT
    self.nameplateSideButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_NAMEPLATE_SIDE, side))
    for _, box in ipairs(self.nameplateButtons) do
        box:SetChecked(Settings:GetOption(box.optionKey) == true)
    end
    self:RefreshMinimapButton()
end

function UI:Initialize()
    if self.frame then return end
    self.mode, self.category = "character", "All"
    local frame = CreateFrame("Frame", nil, UIParent)
    self.frame = frame
    frame:SetSize(920, 660)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    R:OwnFrame(frame)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(widget) widget:StartMoving() end)
    frame:SetScript("OnDragStop", function(widget) widget:StopMovingOrSizing(); self:SavePosition() end)
    frame:SetScript("OnHide", function()
        self:SavePosition()
        self:HideDetails()
        self.confirmFrame:Hide()
    end)
    Theme:Panel(frame)
    local close = Theme:CloseButton(frame, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -14)
    -- Search sits at the head of the sidebar column, above the categories it filters.
    self.search = self.Widgets:Search(frame, SIDEBAR_WIDTH, SEARCH_HEIGHT, L.UI_SEARCH)
    self.search:SetPoint("TOPLEFT", PAD, SEARCH_TOP)
    self.search:SetScript("OnTextChanged", function(widget)
        widget.placeholder:SetShown(widget:GetText() == "")
        self.scroll.slider:SetValue(0)
        self:Refresh()
    end)
    self.categoryButtons = {}
    local y = SIDEBAR_TOP
    for _, entry in ipairs(SIDEBAR) do
        if entry.tools and not self.toolsHeader then
            local rule = Theme:Divider(frame)
            rule:SetPoint("TOPLEFT", PAD + 4, y - 6)
            rule:SetPoint("TOPRIGHT", frame, "TOPLEFT", PAD + SIDEBAR_WIDTH - 4, y - 6)
            self.toolsHeader = Theme:Text(frame, L.UI_TOOLS, "small", "TEXT_MUTED")
            self.toolsHeader:SetPoint("TOPLEFT", PAD + 12, y - 16)
            y = y - 34
        end
        local button = Theme:ListButton(frame, SIDEBAR_WIDTH, SIDEBAR_ROW - 2, L[entry.labelKey], function()
            self:SelectCategory(entry.key)
        end)
        button:SetPoint("TOPLEFT", PAD, y)
        button.category, button.entry = entry.key, entry
        self.categoryButtons[#self.categoryButtons + 1] = button
        y = y - SIDEBAR_ROW
    end

    self.modeCharacter = Theme:Tab(frame, L.UI_CHARACTER, function()
        self.mode = "character"; self:Refresh()
    end)
    self.modeCharacter:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", CONTENT_X + 4, TAB_BASELINE)
    self.modeAccount = Theme:Tab(frame, L.UI_ACCOUNT, function()
        self.mode = "account"; self:Refresh()
    end)
    self.modeAccount:SetPoint("BOTTOMLEFT", self.modeCharacter, "BOTTOMRIGHT", 4, 0)
    local strip = Theme:Divider(frame)
    strip:SetPoint("TOPLEFT", CONTENT_X, TAB_BASELINE)
    strip:SetPoint("TOPRIGHT", self.layout.right, TAB_BASELINE)
    self.panelTitle = Theme:Text(frame, "", "title", "TEXT_TITLE")
    self.panelTitle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", CONTENT_X, TAB_BASELINE + 6)
    self.help = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.help:SetPoint("TOPLEFT", CONTENT_X, HELP_Y)
    self.help:SetPoint("RIGHT", self.layout.right, 0)
    self.scroll = self.Widgets:Scroll(frame)
    self.scroll:SetPoint("TOPLEFT", CONTENT_X, self.layout.top)
    self.scroll:SetPoint("BOTTOMRIGHT", -48, self.layout.bottom)
    self.rows = {}
    for _, module in ipairs(R.modules) do
        self.rows[#self.rows + 1] = self.Widgets:ModuleRow(self.scroll.child, module)
    end
    self.count = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.count:SetPoint("BOTTOMLEFT", CONTENT_X, 24)
    self.empty = Theme:Text(self.scroll.child, L.UI_EMPTY, "body", "TEXT_MUTED")
    self.empty:SetPoint("TOPLEFT", 12, -24)
    self.empty:SetPoint("RIGHT", -12, 0)
    local edition = Theme:Text(frame, L.UI_RETAIL, "small", "TEXT_MUTED")
    edition:SetPoint("LEFT", self.count, "RIGHT", 16, 0)
    self.panels = {}
    self:BuildOptions(frame)
    self:BuildProfiles(frame)
    self:BuildConflicts(frame)
    self:BuildDiagnostics(frame)
    self:BuildConfirm(frame)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.Refresh, self)
    R.Broker:Subscribe("REFACTOR_MODULE_CHANGED", self.Refresh, self)
    frame:Hide()
    self:CreateMinimapButton()
    self:RegisterSettings()
end

function UI:RegisterSettings()
    if not Settings then return end
    local api = _G.Settings
    if not api or not api.RegisterCanvasLayoutCategory or not api.RegisterAddOnCategory then return end
    local panel = CreateFrame("Frame")
    local title = Theme:Text(panel, L.UI_TITLE, "title", "TEXT_TITLE")
    title:SetPoint("TOPLEFT", 24, -24)
    local description = Theme:Text(panel, L.UI_SETTINGS_DESCRIPTION, "body", "TEXT_BODY")
    description:SetPoint("TOPLEFT", 24, -68)
    description:SetWidth(560)
    description:SetJustifyV("TOP")
    local button = Theme:Button(panel, 180, L.UI_OPEN, function()
        if not self.frame:IsShown() then self:Toggle() end
    end)
    button:SetPoint("TOPLEFT", 24, -152)
    self.settingsCategory = api.RegisterCanvasLayoutCategory(panel, L.UI_TITLE)
    api.RegisterAddOnCategory(self.settingsCategory)
    self.settingsPanel = panel
end
