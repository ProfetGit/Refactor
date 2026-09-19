local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = LibStub("LibRefactorTheme-1.0")
local unpack = unpack

-- One sidebar entry per category, in a fixed order, and only for categories that own a
-- module: a stacked group ("Quests & loot") hid which category a row belonged to and left
-- the list with no structure of its own. Panels are the tool pages.
--
-- The category entries are a table of contents, not a filter: every feature is in the list
-- at all times and a category row jumps to its section. An "All features" entry on top of
-- per-category filtering made the same list reachable two ways and hid the rest of it.
local CATEGORY_ORDER = {
    "Quest", "Loot", "Vendor", "Items", "Interface", "Chat", "Social",
    "Nameplates", "Tooltips", "Toasts",
}
-- Settings that belong to one feature live on that feature's row. General holds only the
-- ones that belong to none of them, so it is a list section like any other rather than a
-- page, and it comes last: it is set once, and putting it first made every visit to the
-- list scroll past it.
local GENERAL_KEY = "General"
local TOOL_ENTRIES = {
    { key = "Profiles", labelKey = "UI_Profiles", tools = true },
    { key = "Conflicts", labelKey = "UI_Conflicts", tools = true },
    { key = "Diagnostics", labelKey = "UI_Diagnostics", tools = true },
}
UI.categoryOrder = CATEGORY_ORDER
UI.sidebar = {}

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
    local list = {}
    for _, category in ipairs(self:CategoriesInOrder()) do
        list[#list + 1] = {
            key = category,
            labelKey = "UI_" .. category,
            categories = { category },
            set = { [category] = true },
        }
    end
    list[#list + 1] = { key = GENERAL_KEY, labelKey = "UI_General" }
    for _, entry in ipairs(TOOL_ENTRIES) do list[#list + 1] = entry end
    self.sidebar = list
    return list
end

-- The sections the scrolling list lays out, in order: one per category, then General.
function UI:ListSections()
    local sections = self:CategoriesInOrder()
    sections[#sections + 1] = GENERAL_KEY
    return sections
end

local PAD, SIDEBAR_WIDTH, SIDEBAR_ROW, SIDEBAR_TOP = 24, 148, 24, -64
local CONTENT_X = PAD + SIDEBAR_WIDTH + 22
local SEARCH_TOP, SEARCH_HEIGHT = -22, 26
local TAB_BASELINE, HELP_Y = -72, -80
-- The feature list has no heading of its own, so it runs the full height of the window,
-- stopping only where the nine-slice border starts. A panel still keeps its title band.
-- The scroll frame has to end there rather than short of it: a row is cut off at that
-- edge, and the cut has to happen under the vignette, where it reads as the row passing
-- behind the border instead of ending in mid air.
local LIST_TOP, LIST_BOTTOM = -14, 14
-- The close button's own height plus a gap, so the upper stepper clears it.
local LIST_BAR_TOP = 32
-- Breathing room above the first heading, carried by the list's own content rather than by
-- the frame that clips it. A category jump keeps the same gap above the heading it lands
-- on, so no heading ever sits against the border.
local LIST_LEAD = PAD
-- Space above a heading, and between a heading and the first row under it.
local LIST_SECTION_GAP, HEADER_GAP = 18, 4
-- How far past a section's heading the view can sit before the sidebar stops calling it the
-- section you are in: the lead-in a jump leaves above the heading, plus a hairline of slack
-- so a jump that lands a pixel short still reads as having arrived.
local SPY_SLOP = LIST_LEAD + 4
UI.layout = { x = CONTENT_X, top = -102, right = -36, bottom = 24 }
local ROW_HEIGHT = UI.Widgets.ROW_HEIGHT
local BLOCK_INDENT = UI.Widgets.BLOCK_INDENT
-- Space between two titled groups inside the General block, and the height of one title.
local GROUP_GAP, GROUP_LABEL = 22, 22
-- Above this a repair bill is not a typo, it is a different currency.
local MAX_REPAIR_CAP = 10000000
-- The same 150 ms every other move in the window takes (PRD 8.3).
local EXPAND_TIME = 0.15
local MODIFIER_ENTRIES = {
    { value = "CTRL", labelKey = "UI_CTRL" },
    { value = "SHIFT", labelKey = "UI_SHIFT" },
    { value = "ALT", labelKey = "UI_ALT" },
}
local SCOPE_ENTRIES = {
    { value = "character", labelKey = "UI_CHARACTER" },
    { value = "account", labelKey = "UI_ACCOUNT" },
}
local SIDE_ENTRIES = {
    { value = "LEFT", labelKey = "UI_LEFT" },
    { value = "RIGHT", labelKey = "UI_RIGHT" },
}
-- The width every dropdown and slider in a settings block shares.
local CONTROL_WIDTH = 380

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

-- The value the row's checkbox shows: the account default in account mode, the resolved
-- per-character value otherwise. Cycle and Refresh read it from here so a click always
-- flips the setting itself, never a checkbox tick that drifted out of sync with it.
function UI:DisplayedValue(module)
    if self.mode == "account" then
        return accountValue(module)
    end
    return Settings:Get(module.id) == true
end

function UI:Cycle(module)
    self:SetModuleEnabled(module, not self:DisplayedValue(module))
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
    -- Shown first, then laid out: the tail below the last section is measured from the
    -- list's own height, and a frame that has never been on screen has none.
    if self.frame:IsShown() then self.frame:Hide()
    else self.frame:Show(); self:OnPixelsChanged() end
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

-- Every frame the list places, in the order it placed them. An opening block has to move
-- everything below it, and re-running the whole layout for that on each frame would mean
-- re-reading every setting sixty times a second; this way a step is a loop of SetPoint.
function UI:Place(frame, x, y, rightPad)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", x, -y)
    frame:SetPoint("RIGHT", self.scroll.child, "RIGHT", rightPad or 0, 0)
    local index = self.placedCount + 1
    self.placedCount = index
    local entry = self.placed[index]
    if not entry then
        entry = {}
        self.placed[index] = entry
    end
    entry.frame, entry.x, entry.y, entry.rightPad = frame, x, y, rightPad or 0
    return index
end

-- How much of the block is showing. The rows below it sit by the same amount higher, and
-- the scroll extent shrinks with them, so the list never reports more height than it draws.
function UI:ApplyExpand(block, revealed)
    local full = block.height
    if not full or full <= 0 then return end
    if revealed < 0 then revealed = 0 elseif revealed > full then revealed = full end
    block:SetHeight(math.max(1, revealed))
    block:SetAlpha(revealed / full)
    local shift = full - revealed
    for index = (block.planIndex or self.placedCount) + 1, self.placedCount do
        local entry = self.placed[index]
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint("TOPLEFT", entry.x, -(entry.y - shift))
        entry.frame:SetPoint("RIGHT", self.scroll.child, "RIGHT", entry.rightPad, 0)
    end
    self.scroll:UpdateExtent(math.max(1, (self.planExtent or 0) - shift))
end

-- A block's height and its siblings' offsets are not things an AnimationGroup can drive,
-- which is the one case the rule leaves to OnUpdate. It runs only while a block is moving
-- and takes itself off on the last frame, so an idle window has none.
local function expandStep(block, elapsed)
    block.animElapsed = block.animElapsed + elapsed
    local progress = block.animElapsed / EXPAND_TIME
    if progress > 1 then progress = 1 end
    -- Eased out, so the list settles rather than stopping dead. No overshoot: the rows
    -- below would have to come back up, and nothing else in this window bounces.
    local eased = 1 - (1 - progress) * (1 - progress)
    UI:ApplyExpand(block, block.animFrom + (block.animTo - block.animFrom) * eased)
    if progress >= 1 then
        block:SetScript("OnUpdate", nil)
        UI:FinishExpand(block)
    end
end

-- Leaves the block at its full height whatever it was doing, so an interrupted animation
-- cannot strand a handler on a frame that is about to be hidden.
function UI:CancelExpand()
    local block = self.animBlock
    if not block then return end
    self.animBlock = nil
    block:SetScript("OnUpdate", nil)
    block:SetHeight(block.height)
    block:SetAlpha(1)
end

function UI:StartExpand(block, from, to)
    self:CancelExpand()
    self.animBlock = block
    block.animFrom, block.animTo, block.animElapsed = from, to, 0
    self:ApplyExpand(block, from)
    block:SetScript("OnUpdate", expandStep)
end

function UI:FinishExpand(block)
    self.animBlock = nil
    if not self.collapsing then
        self:ApplyExpand(block, block.height)
        return
    end
    self.collapsing = nil
    self:Refresh()
    block:SetAlpha(1)
    block:SetHeight(block.height)
end

-- A feature's settings open under its own row, one at a time: the blocks are tall enough
-- that two of them open at once leaves the list impossible to scan. A collapse keeps the
-- block laid out until its animation ends, or there would be nothing left to animate.
function UI:ToggleExpanded(id)
    local block = self.moduleSettings[id]
    if not block then return end
    local closing = self.expanded == id
    -- Stops whatever was moving; the two lines below are then the only state there is.
    self:CancelExpand()
    -- Spelled out rather than "closing and nil or id", which is always id: the middle
    -- term of that idiom cannot be nil.
    if closing then
        self.expanded, self.collapsing = nil, id
    else
        self.expanded, self.collapsing = id, nil
    end
    self:Refresh()
    -- A filtered list opens whatever the query reached, so there is no single block to
    -- animate and the layout has already been settled by the search.
    if not block:IsShown() or not block.planIndex or (self.search:GetText() or "") ~= "" then
        if self.collapsing then
            self.collapsing = nil
            self:Refresh()
        end
        return
    end
    if closing then
        self:StartExpand(block, block.height, 0)
    else
        self:StartExpand(block, 0, block.height)
    end
end

function UI:RegisterModuleSettings(id, block)
    self.moduleSettings[id] = block
    block:Hide()
end

function UI:SelectCategory(key)
    self.category = key
    self.search:SetText("")
    self.search:ClearFocus()
    self:ClearSaveStatus()
    if key == "Profiles" then self:LoadProfiles() end
    if self.panels and self.panels[key] then
        self.scroll.slider:SetValue(0)
    else
        -- Where a section sits is only known once Refresh has laid the list out, so the
        -- jump is what Refresh does last rather than something guessed from here.
        self.pendingScroll = key
    end
    self:Refresh()
end

function UI:HighlightSidebar()
    for _, button in ipairs(self.categoryButtons) do
        Theme:ListButtonState(button, self.category == button.category, button.entry.tone)
    end
end

-- The sidebar is a table of contents, so the row that reads as selected has to be the
-- section at the top of the view, not the last row clicked. A tool page owns the whole
-- view and keeps its own selection.
function UI:SpySection(value)
    if not self.sectionOffset then return end
    if self.panels and self.panels[self.category] then return end
    local current
    for _, category in ipairs(self.categories) do
        local top = self.sectionOffset[category]
        if top and top <= value + SPY_SLOP then current = category end
    end
    if current and current ~= self.category then
        self.category = current
        self:HighlightSidebar()
    end
end

-- Open the window straight at one page. A module that offers a settings shortcut has to be
-- able to say which page without knowing whether the window is already up.
function UI:OpenPanel(key)
    if not self.frame then return end
    self.frame:Show()
    self:OnPixelsChanged()
    self:SelectCategory(key)
end

-- Open the window on one feature's own settings. A module offering a shortcut to its
-- options cannot know whether the window is already up, or which section it is filed under.
function UI:OpenModule(id)
    if not self.frame then return end
    local module = R.moduleByID and R.moduleByID[id]
    if not module then return end
    self.frame:Show()
    self:OnPixelsChanged()
    self.expanded = id
    self:SelectCategory(self:Category(module))
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
    self:HighlightSidebar()
    if panel then
        self.panelTitle:SetText(L[panel.countKey or "UI_OPTIONS"])
        if panel.Update then panel:Update() end
        self.empty:Hide()
        self.scroll.slider:Hide(); self.scroll.up:Hide(); self.scroll.down:Hide()
        return
    end
    -- Every checkbox tracks its setting, visible or not: Refresh used to sync only the rows
    -- it was laying out, so a value changed while its row was off-page left the tick stale
    -- and the next click read the stale tick instead of the setting.
    for _, row in ipairs(self.rows) do
        row.toggle:SetChecked(self:DisplayedValue(row.module))
        row.toggle:SetEnabled(Settings.account ~= nil and not row.module.unavailableReasonKey)
    end
    -- The settings blocks are part of the list now, so their own controls are re-read here
    -- rather than by a panel that is about to be shown.
    self:LoadGeneral()
    self:LoadDisplay()
    self:LoadTooltips()
    self:RefreshNameplateOptions()
    -- One block per category, headed by its name: the list carries the same structure as
    -- the sidebar, and a search result says which category each row came from.
    local count, offset, lastTop = 0, LIST_LEAD, LIST_LEAD
    self.placedCount = 0
    local offsets = self.sectionOffset
    for _, category in ipairs(self.categories) do offsets[category] = nil end
    for _, category in ipairs(self.categories) do
        local header, rows = self.sections[category], self.sectionRows[category]
        local block = self.sectionBlocks[category]
        -- What survives the query is settled for the whole section first: the heading is
        -- placed before the rows under it, and only then knows whether it has any.
        local blockVisible = block ~= nil and self:MatchesBlock(block, query)
        local shown = blockVisible and 1 or 0
        for _, row in ipairs(rows) do
            local settings = self.moduleSettings[row.module.id]
            -- A search reaches a setting that has no row of its own and opens the block
            -- holding it: "repair limit" should not need you to know it is under Auto repair.
            local hit = settings ~= nil and query ~= "" and self:MatchesText(settings.searchText, query)
            row.visible = hit or self:Matches(row.module, query, nil)
            row.openSettings = settings ~= nil and row.visible
                and (hit or (query == "" and (self.expanded == row.module.id
                    or self.collapsing == row.module.id)))
            if row.visible then shown = shown + 1 end
        end
        -- Shown or hidden exactly once per pass, and never hidden and shown again in the
        -- same one: dragging a slider saves its setting on every step, and a Hide/Show of
        -- the block it sits in would drop the drag on the first of them.
        for _, row in ipairs(rows) do
            local settings = self.moduleSettings[row.module.id]
            if settings then settings:SetShown(row.openSettings == true) end
        end
        if shown > 0 then
            if count > 0 then offset = offset + LIST_SECTION_GAP end
            offsets[category], lastTop = offset, offset
            self:Place(header, 0, offset)
            -- Anchored first, then measured: the rule can only be put on a whole pixel
            -- once its heading knows where it sits.
            Theme:AlignHairline(header.line, header, header.lineY)
            offset = offset + header.height + HEADER_GAP
            count = count + shown
        end
        if block then
            block:SetShown(blockVisible)
            if blockVisible then
                self:Place(block, 0, offset, -8)
                offset = offset + block.height
            end
        end
        for _, row in ipairs(rows) do
            row:SetShown(row.visible)
            if row.visible then
                self:Place(row, 0, offset)
                offset = offset + ROW_HEIGHT
                self:RefreshRow(row)
                local settings = self.moduleSettings[row.module.id]
                row.chevron:SetShown(settings ~= nil)
                if settings then
                    Theme:ApplyAsset(row.chevron.art, row.openSettings and "scrollUp" or "scrollDown")
                    Theme:Color(row.chevron.art, "ACCENT_COPPER")
                end
                if row.openSettings then
                    settings.planIndex = self:Place(settings, BLOCK_INDENT, offset, -8)
                    offset = offset + settings.height
                end
            end
        end
        header:SetShown(shown > 0)
    end
    self.empty:SetShown(count == 0)
    -- Without this the last sections share one scroll position: the list is barely taller
    -- than the view, so a jump to anything past the halfway point stops at the end of the
    -- track and the sidebar highlight would be naming a section that is not at the top.
    local tail = count > 0
        and math.max(0, self.scroll:GetHeight() - LIST_LEAD - (offset - lastTop)) or 0
    self.planExtent = offset + tail
    self.scroll:UpdateExtent(self.planExtent)
    local target = self.pendingScroll
    self.pendingScroll = nil
    if target and offsets[target] then
        local _, maximum = self.scroll.slider:GetMinMaxValues()
        self.scroll.slider:SetValue(math.max(0, math.min(offsets[target] - LIST_LEAD, maximum)))
    end
end

function UI:RefreshRow(row)
    local module = row.module
    row.name:SetText(self:ModuleText(module, "name"))
    local reason = self:StatusReason(module)
    row.meta:SetText(reason and (module.state == "failed" and L.UI_FAILED_SHORT or L.UI_UNAVAILABLE_SHORT)
        or module.state == "unconfirmed" and L.UI_STATE_UNCONFIRMED or "")
    Theme:Color(row.meta, reason and "TEXT_WARNING" or "TEXT_MUTED", true)
    row.undo:SetShown(self:IsModified(module))
end

-- General is a section of the list, so it is there whenever the list is unfiltered. A
-- feature's own block only opens when the query reaches inside it.
function UI:MatchesBlock(block, query)
    if query == "" then return true end
    return self:MatchesText(block.searchText, query)
end

-- Cleared when the view changes, not on every Refresh: a save fires the settings event,
-- which refreshes the list, and clearing there would wipe the confirmation as it appeared.
function UI:ClearSaveStatus()
    if self.sellStatus then self.sellStatus:SetText("") end
    if self.repairStatus then self.repairStatus:SetText("") end
    if self.farmStatus then self.farmStatus:SetText("") end
    if self.displayStatus then self.displayStatus:SetText("") end
    if self.tooltipStatus then self.tooltipStatus:SetText("") end
end

-- The list re-reads these on every Refresh, so a field that still holds the cursor is left
-- alone: overwriting it would undo what is being typed into it.
function UI:LoadGeneral()
    if not self.modifierDropdown then return end
    local ids = {}
    for id in pairs(Settings:GetOption("neverSellIDs")) do ids[#ids + 1] = id end
    table.sort(ids)
    for index, id in ipairs(ids) do ids[index] = tostring(id) end
    if not self.neverSell:HasFocus() then self.neverSell:SetText(table.concat(ids, ", ")) end
    if not self.repairCap:HasFocus() then
        self.repairCap:SetText(tostring(Settings:GetOption("repairCapGold")))
    end
    self:RefreshScope()
    self:RefreshMinimapButton()
end

function UI:SaveNeverSell()
    local neverSell = self:ParseNeverSell(self.neverSell:GetText())
    if not neverSell or not Settings:SetOption("neverSellIDs", neverSell) then
        self.sellStatus:SetText(L.UI_NEVER_SELL_INVALID)
        return
    end
    self.neverSell:ClearFocus()
    self.sellStatus:SetText(L.UI_SAVED)
end

function UI:SaveRepairCap()
    local cap = tonumber(self.repairCap:GetText())
    if not cap or cap < 0 or cap > MAX_REPAIR_CAP or not Settings:SetOption("repairCapGold", cap) then
        self.repairStatus:SetText(L.UI_REPAIR_INVALID)
        return
    end
    self.repairCap:ClearFocus()
    self.repairStatus:SetText(L.UI_SAVED)
end

-- A titled group inside the General block. These are settings, not features, so they get a
-- label rather than a row and a chevron of their own.
function UI:GeneralGroup(block, labelKey, top)
    local label = Theme:Text(block, L[labelKey], "body", "TEXT_TITLE")
    label:SetPoint("TOPLEFT", 0, top)
    label:SetPoint("RIGHT")
    block:Index(L[labelKey])
    return GROUP_LABEL
end

-- The scope switch is a mode for the whole list rather than a setting of any one feature,
-- so it sits with the other options that belong to none of them.
function UI:BuildScopeControls(block, top)
    local used = self:GeneralGroup(block, "UI_SCOPE", top)
    local list = {}
    for index, entry in ipairs(SCOPE_ENTRIES) do
        list[index] = { value = entry.value, text = L[entry.labelKey] }
        block:Index(L[entry.labelKey])
    end
    -- Not an option in the store: which layer the feature checkboxes write to is a state of
    -- the window, so this one reads and writes self.mode rather than Settings.
    self.scopeDropdown = Theme:Dropdown(block, CONTROL_WIDTH, list,
        function(value) return self.mode == value end,
        function(value)
            self.mode = value
            self:Refresh()
        end)
    self.scopeDropdown:SetPoint("TOPLEFT", 0, top - used)
    self.scopeDropdown:SetLabel(L.UI_SCOPE)
    self.scopeEntries = list
    self.scopeHelp = Theme:Text(block, "", "small", "TEXT_MUTED")
    self.scopeHelp:SetPoint("TOPLEFT", 0, top - used - 34)
    self.scopeHelp:SetPoint("RIGHT")
    self.scopeHelp:SetHeight(28)
    self.scopeHelp:SetJustifyV("TOP")
    block:Index(L.UI_SCOPE_HELP, L.UI_ACCOUNT, L.UI_CHARACTER)
    return used + 62
end

function UI:RefreshScope()
    if not self.scopeDropdown then return end
    local account = self.mode == "account"
    self.scopeDropdown:SetValueText(account and L.UI_ACCOUNT or L.UI_CHARACTER)
    self.scopeHelp:SetText(account and L.UI_ACCOUNT_HELP or L.UI_CHARACTER_HELP)
end

-- The pause modifier guards every automatic action in the addon, so it belongs to no one
-- module. It applies on click like the other cyclers rather than waiting for a Save.
function UI:BuildPauseControls(block, top)
    local used = self:GeneralGroup(block, "UI_KILL_SWITCH", top)
    self.modifierDropdown = self:OptionDropdown(block, "killSwitch", MODIFIER_ENTRIES,
        "UI_KILL_SWITCH", top - used)
    local help = Theme:Text(block, L.UI_KILL_SWITCH_HELP, "small", "TEXT_MUTED")
    help:SetPoint("TOPLEFT", 0, top - used - 34)
    help:SetPoint("RIGHT")
    help:SetHeight(28)
    help:SetJustifyV("TOP")
    block:Index(L.UI_KILL_SWITCH_HELP)
    return used + 62
end

-- Refactor's own entry point, not a feature of the addon's, and never a nameplate setting:
-- it sat under the nameplate heading, where nothing about it belonged.
function UI:BuildMinimapControls(block, top)
    local box = Theme:Checkbox(block, 300, L.UI_MINIMAP_BUTTON, function(widget)
        Settings:SetOption("minimapButton", widget:GetChecked() == true)
        self:RefreshMinimapButton()
    end)
    box:SetPoint("TOPLEFT", 0, top)
    box.optionKey = "minimapButton"
    block:Index(L.UI_MINIMAP_BUTTON)
    self.displayToggles[#self.displayToggles + 1] = box
    self.minimapToggle = box
    return 26
end

function UI:BuildGeneral(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_GENERAL_HELP)
    local top = block.top
    top = top - self:BuildScopeControls(block, top) - GROUP_GAP
    top = top - self:BuildPauseControls(block, top) - GROUP_GAP
    top = top - self:BuildMinimapControls(block, top) - GROUP_GAP
    top = top - self:GeneralGroup(block, "UI_PRICE_OPTIONS", top)
    top = top - self:BuildPriceControls(block, top)
    block:SetBodyHeight(block.top - top)
    self.general = block
    self.sectionBlocks[GENERAL_KEY] = block
end

function UI:BuildSellSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_NEVER_SELL_HELP)
    local top = block.top
    local label = Theme:Text(block, L.UI_NEVER_SELL, "body", "TEXT_TITLE")
    label:SetPoint("TOPLEFT", 0, top)
    label:SetPoint("RIGHT")
    block:Index(L.UI_NEVER_SELL)
    self.neverSell = self.Widgets:Input(block, 400, 56, true)
    self.neverSell:SetPoint("TOPLEFT", 0, top - 24)
    self.neverSell:SetPoint("RIGHT")
    local save = Theme:Button(block, 152, L.UI_SAVE_SHORT, function() self:SaveNeverSell() end)
    save:SetPoint("TOPLEFT", 0, top - 88)
    self.sellStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    self.sellStatus:SetPoint("LEFT", save, "RIGHT", 12, 0)
    self.sellStatus:SetPoint("RIGHT")
    block:SetBodyHeight(114)
    self:RegisterModuleSettings("vendor.autoSell", block)
end

function UI:BuildRepairSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_REPAIR_CAP_HELP)
    local top = block.top
    local label = Theme:Text(block, L.UI_REPAIR_CAP, "body", "TEXT_TITLE")
    label:SetPoint("TOPLEFT", 0, top)
    label:SetPoint("RIGHT")
    block:Index(L.UI_REPAIR_CAP)
    self.repairCap = self.Widgets:Input(block, 116, 26)
    self.repairCap:SetPoint("TOPLEFT", 0, top - 24)
    local save = Theme:Button(block, 152, L.UI_SAVE_SHORT, function() self:SaveRepairCap() end)
    save:SetPoint("LEFT", self.repairCap, "RIGHT", 8, 0)
    self.repairStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    self.repairStatus:SetPoint("LEFT", save, "RIGHT", 12, 0)
    self.repairStatus:SetPoint("RIGHT")
    block:SetBodyHeight(56)
    self:RegisterModuleSettings("vendor.autoRepair", block)
end

local nameplateToggles = {
    { key = "nameplateShowRing", label = "UI_NAMEPLATE_RING" },
    { key = "nameplateShowIcon", label = "UI_NAMEPLATE_ICON" },
    { key = "nameplateDimCompleted", label = "UI_NAMEPLATE_DIM" },
    { key = "nameplateReduceAnimation", label = "UI_NAMEPLATE_REDUCE" },
}

-- Booleans apply on click. Only the typed fields wait for Save.
function UI:BuildNameplateSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_NAMEPLATE_HELP)
    local top = block.top
    self.nameplateButtons = {}
    self.nameplateSideDropdown = self:OptionDropdown(block, "nameplateSide", SIDE_ENTRIES,
        "UI_NAMEPLATE_SIDE", top)
    for index, toggle in ipairs(nameplateToggles) do
        local box = Theme:Checkbox(block, 300, L[toggle.label], function(widget)
            Settings:SetOption(toggle.key, widget:GetChecked() == true)
            self:RefreshNameplateOptions()
        end)
        box:SetPoint("TOPLEFT", 0, top - 6 - index * 32)
        box.optionKey = toggle.key
        block:Index(L[toggle.label])
        self.nameplateButtons[index] = box
    end
    block:SetBodyHeight(6 + #nameplateToggles * 32 + 26)
    self:RegisterModuleSettings("nameplates.questProgress", block)
end

function UI:RefreshNameplateOptions()
    if not self.nameplateButtons then return end
    for _, box in ipairs(self.nameplateButtons) do
        box:SetChecked(Settings:GetOption(box.optionKey) == true)
    end
end

function UI:OnPixelsChanged()
    Theme:RefreshHairlines()
    if self.scroll then self.scroll.pixel = Theme:PixelSize(self.scroll) end
    -- Every rule in the list is anchored from Refresh, so re-running it re-aligns them.
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function UI:Initialize()
    if self.frame then return end
    self.mode = "character"
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
        -- Closed mid-animation, the block keeps its handler and comes back part-drawn.
        self:CancelExpand()
        self.collapsing = nil
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
    self.scroll.onScroll = function(value) self:SpySection(value) end
    self.rows, self.sectionRows, self.sections, self.sectionOffset = {}, {}, {}, {}
    self.moduleSettings, self.sectionBlocks, self.displayToggles = {}, {}, {}
    self.optionSliders, self.optionDropdowns = {}, {}
    self.placed, self.placedCount = {}, 0
    self.categories = self:ListSections()
    -- The list opens at its head, and the sidebar names the section that is there.
    self.category = self.categories[1] or TOOL_ENTRIES[1].key
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
    -- Every block is built once, here, and only ever re-anchored afterwards: a chevron
    -- click is an event handler, and no frame is created inside one.
    self:BuildGeneral(self.scroll.child)
    self:BuildSellSettings(self.scroll.child)
    self:BuildRepairSettings(self.scroll.child)
    self:BuildVendorListSettings(self.scroll.child)
    self:BuildNameplateSettings(self.scroll.child)
    self:BuildToastSettings(self.scroll.child)
    self:BuildFarmSettings(self.scroll.child)
    self:BuildQuestSettings(self.scroll.child)
    self:BuildGossipSettings(self.scroll.child)
    self:BuildResurrectSettings(self.scroll.child)
    self:BuildTooltipSettings(self.scroll.child)
    self.panels = {}
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
