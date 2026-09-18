local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = LibStub("LibRefactorTheme-1.0")
local unpack = unpack

-- One sidebar entry per category, in a fixed order, and only for categories that own a
-- module: a stacked group ("Quests & loot") hid which category a row belonged to and left
-- the list with no structure of its own. Panels are the tool pages. Automation is its own
-- category (PRD 6.3), so a module that decides for the player is never listed under the
-- category it would otherwise sit in.
local CATEGORY_ORDER = {
    "Quest", "Loot", "Vendor", "Items", "Interface", "Chat", "Social",
    "Nameplates", "Tooltips", "Toasts", "Automation",
}
local TOOL_ENTRIES = {
    { key = "Options", labelKey = "UI_OPTIONS", tools = true },
    { key = "Profiles", labelKey = "UI_Profiles", tools = true },
    { key = "Conflicts", labelKey = "UI_Conflicts", tools = true },
    { key = "Diagnostics", labelKey = "UI_Diagnostics", tools = true },
}
UI.categoryOrder = CATEGORY_ORDER
UI.sidebar = { { key = "All", labelKey = "UI_ALL" } }

-- Every category that owns a module, in display order. A category the order list has not
-- heard of still gets listed, after the known ones, so registering one cannot make its
-- modules unreachable.
function UI:CategoriesInOrder()
    local present, ordered, known = {}, {}, {}
    for _, module in ipairs(R.modules) do present[self:Category(module)] = true end
    for _, category in ipairs(CATEGORY_ORDER) do
        known[category] = true
        if present[category] then ordered[#ordered + 1] = category end
    end
    local extra = {}
    for category in pairs(present) do
        if not known[category] then extra[#extra + 1] = category end
    end
    table.sort(extra)
    for _, category in ipairs(extra) do ordered[#ordered + 1] = category end
    return ordered
end

-- Built from the modules that actually registered, so a category with nothing in it never
-- becomes a dead row and a new category needs no edit here.
function UI:BuildSidebar()
    local list = { { key = "All", labelKey = "UI_ALL" } }
    for _, category in ipairs(self:CategoriesInOrder()) do
        list[#list + 1] = {
            key = category,
            labelKey = "UI_" .. category,
            categories = { category },
            set = { [category] = true },
            tone = category == "Automation" and "TEXT_WARNING" or nil,
        }
    end
    for _, entry in ipairs(TOOL_ENTRIES) do list[#list + 1] = entry end
    self.sidebar = list
    return list
end

local PAD, SIDEBAR_WIDTH, SIDEBAR_ROW, SIDEBAR_TOP = 24, 148, 24, -64
local CONTENT_X = PAD + SIDEBAR_WIDTH + 22
local SEARCH_TOP, SEARCH_HEIGHT = -22, 26
local TAB_BASELINE, HELP_Y = -72, -80
-- The feature list has no heading of its own, so it runs the full height of the window,
-- stopping only where the nine-slice border starts. A panel still keeps its title band.
local LIST_TOP, LIST_BOTTOM = -14, 14
-- The close button's own height plus a gap, so the upper stepper clears it.
local LIST_BAR_TOP = 32
local SECTION_GAP = 24
-- Space above a heading, and between a heading and the first row under it.
local LIST_SECTION_GAP, HEADER_GAP = 18, 4
UI.layout = { x = CONTENT_X, top = -102, right = -36, bottom = 24 }
local ROW_HEIGHT = UI.Widgets.ROW_HEIGHT
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
    local override = Settings:GetOverride(module.id)
    return override ~= nil and override ~= Settings:GetInherited(module.id)
end

function UI:ResetModule(module)
    if self.mode == "account" then Settings:SetAccount(module.id, nil)
    else Settings:SetOverride(module.id, nil) end
    self:Refresh()
end

function UI:Cycle(module)
    self:SetModuleEnabled(module, not Settings:Get(module.id))
end

-- Dropped between two pixels, the window puts every rule inside it between two pixels too.
function UI:SnapPosition()
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, UIParent, relativePoint,
        Theme:Snap(self.frame, x), Theme:Snap(self.frame, y))
    if self.frame:IsShown() then self:Refresh() end
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
        self.frame:SetPoint(saved.point, UIParent, saved.relativePoint,
            Theme:Snap(self.frame, saved.x), Theme:Snap(self.frame, saved.y))
    end
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then self.frame:Hide()
    else self:OnPixelsChanged(); self:Refresh(); self.frame:Show() end
end

-- What the feature does, and nothing else. Overlaps with other addons have their own
-- panel, and the recovery advice was the same sentence on all twenty rows.
function UI:DetailText(module)
    local title = self:ModuleText(module, "name")
    local reason = self:StatusReason(module)
    local body = self:ModuleText(module, "description") .. "\n\n" .. self:ModuleText(module, "detail")
        .. (reason and "\n\n" .. reason or "")
    return title, body
end

-- The detail is a tooltip on the row itself, so it needs no click and no dialog to dismiss.
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
    self.panelTitle:SetShown(panel ~= nil)
    self.headerRule:SetShown(panel ~= nil)
    self.help:SetText(panel and L[panel.helpKey or "UI_OPTIONS_HELP"] or "")
    local entry
    for _, button in ipairs(self.categoryButtons) do
        local selected = self.category == button.category
        if selected then entry = button.entry end
        Theme:ListButtonState(button, selected, button.entry.tone)
    end
    if panel then
        self.panelTitle:SetText(L[panel.countKey or "UI_OPTIONS"])
        if panel.Update then panel:Update() end
        self.empty:Hide()
        self.scroll.slider:Hide(); self.scroll.up:Hide(); self.scroll.down:Hide()
        return
    end
    local filter = entry and entry.set or nil
    -- One block per category, headed by its name: the list carries the same structure as
    -- the sidebar, and a search result says which category each row came from.
    local count, offset = 0, 0
    for _, category in ipairs(self.categories) do
        local header, shown = self.sections[category], 0
        for _, row in ipairs(self.sectionRows[category]) do
            local module = row.module
            local visible = self:Matches(module, query, filter)
            row:SetShown(visible)
            if visible then
                if shown == 0 then
                    if count > 0 then offset = offset + LIST_SECTION_GAP end
                    header:ClearAllPoints()
                    header:SetPoint("TOPLEFT", 0, -offset)
                    header:SetPoint("RIGHT", self.scroll.child, "RIGHT")
                    -- Anchored first, then measured: the rule can only be put on a whole
                    -- pixel once its heading knows where it sits.
                    Theme:AlignHairline(header.line, header, header.lineY)
                    offset = offset + header.height + HEADER_GAP
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -offset)
                row:SetPoint("RIGHT", self.scroll.child, "RIGHT")
                offset = offset + ROW_HEIGHT
                count, shown = count + 1, shown + 1
                row.name:SetText(self:ModuleText(module, "name"))
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
        header:SetShown(shown > 0)
    end
    self.empty:SetShown(count == 0)
    self.scroll:UpdateExtent(offset)
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
    local sections = {
        self:BuildScopeSection(page.child),
        self:BuildSafetySection(page.child),
        self:BuildNameplateSection(page.child),
    }
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
        self:RefreshScope()
        self:LoadDisplay()
        self:LoadTooltips()
        self:RefreshNameplateOptions()
        page:UpdateExtent(options.contentHeight)
    end
    self:RegisterPanel("Options", options)
end

-- The scope switch lives here rather than above the feature list: it is set once and then
-- left alone, so it does not earn permanent space in the view it affects.
function UI:BuildScopeSection(parent)
    local section = self.Widgets:Section(parent, L.UI_SCOPE, L.UI_SCOPE_HELP)
    self.scopeButton = Theme:Button(section, 240, "", function()
        self.mode = self.mode == "account" and "character" or "account"
        self:RefreshScope()
        self:Refresh()
    end)
    self.scopeButton:SetPoint("TOPLEFT", 0, section.top)
    self.scopeHelp = Theme:Text(section, "", "small", "TEXT_MUTED")
    self.scopeHelp:SetPoint("TOPLEFT", 0, section.top - 34)
    self.scopeHelp:SetPoint("RIGHT")
    section:SetBodyHeight(58)
    return section
end

function UI:RefreshScope()
    if not self.scopeButton then return end
    local account = self.mode == "account"
    self.scopeButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_SCOPE,
        account and L.UI_ACCOUNT or L.UI_CHARACTER))
    self.scopeHelp:SetText(account and L.UI_ACCOUNT_HELP or L.UI_CHARACTER_HELP)
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

function UI:OnPixelsChanged()
    Theme:RefreshHairlines()
    if self.scroll then self.scroll.pixel = Theme:PixelSize(self.scroll) end
    -- Every rule in the list is anchored from Refresh, so re-running it re-aligns them.
    if self.frame and self.frame:IsShown() then self:Refresh() end
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
    frame:SetScript("OnDragStop", function(widget)
        widget:StopMovingOrSizing()
        self:SnapPosition()
        self:SavePosition()
    end)
    frame:SetScript("OnHide", function()
        self:SavePosition()
        self:HideDetails()
        self.confirmFrame:Hide()
    end)
    Theme:Panel(frame)
    -- Only the main window gets it: a dialog is shorter than two bands and would come out
    -- shaded end to end.
    Theme:Vignette(frame, Theme.panelInset)
    local close = Theme:CloseButton(frame, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -14)
    -- The one control that sits inside the shade and must not be dimmed by it.
    close:SetFrameLevel(frame:GetFrameLevel() + Theme.vignetteLevel + 1)
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
    for _, entry in ipairs(self:BuildSidebar()) do
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

    self.headerRule = Theme:Divider(frame)
    self.headerRule:SetPoint("TOPLEFT", CONTENT_X, TAB_BASELINE)
    self.headerRule:SetPoint("TOPRIGHT", self.layout.right, TAB_BASELINE)
    self.panelTitle = Theme:Text(frame, "", "title", "TEXT_TITLE")
    self.panelTitle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", CONTENT_X, TAB_BASELINE + 6)
    self.help = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.help:SetPoint("TOPLEFT", CONTENT_X, HELP_Y)
    self.help:SetPoint("RIGHT", self.layout.right, 0)
    self.scroll = self.Widgets:Scroll(frame, LIST_BAR_TOP)
    self.scroll:SetPoint("TOPLEFT", CONTENT_X, LIST_TOP)
    self.scroll:SetPoint("BOTTOMRIGHT", -48, LIST_BOTTOM)
    -- Rows are created once, grouped by the category they will be listed under; Refresh
    -- only ever re-anchors them.
    self.rows, self.sectionRows, self.sections = {}, {}, {}
    self.categories = self:CategoriesInOrder()
    for _, category in ipairs(self.categories) do
        self.sectionRows[category] = {}
        local header = Theme:SectionHeader(self.scroll.child, L["UI_" .. category] or category)
        header:SetPoint("RIGHT", self.scroll.child, "RIGHT")
        header:Hide()
        self.sections[category] = header
    end
    for _, module in ipairs(R.modules) do
        local row = self.Widgets:ModuleRow(self.scroll.child, module)
        self.rows[#self.rows + 1] = row
        local group = self.sectionRows[self:Category(module)]
        group[#group + 1] = row
    end
    self.empty = Theme:Text(self.scroll.child, L.UI_EMPTY, "body", "TEXT_MUTED")
    self.empty:SetPoint("TOPLEFT", 12, -24)
    self.empty:SetPoint("RIGHT", -12, 0)
    self.panels = {}
    self:BuildOptions(frame)
    self:BuildProfiles(frame)
    self:BuildConflicts(frame)
    self:BuildDiagnostics(frame)
    self:BuildConfirm(frame)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.Refresh, self)
    R.Broker:Subscribe("REFACTOR_MODULE_CHANGED", self.Refresh, self)
    -- The two events that change how many pixels a UI unit is worth, and so how tall a
    -- hairline has to be to survive rounding.
    R.Broker:Subscribe("UI_SCALE_CHANGED", self.OnPixelsChanged, self)
    R.Broker:Subscribe("DISPLAY_SIZE_CHANGED", self.OnPixelsChanged, self)
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
