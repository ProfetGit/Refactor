local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

local ROW_WIDTH, ROW_GAP, CHILD_INDENT = 300, 4, 18
local DIALOG_WIDTH, DIALOG_PADDING, DIALOG_TOP, DIALOG_ROW_GAP, DIALOG_GAP = 268, 16, 38, 10, 12
-- The pool is sized for the largest feed the settings allow plus one expanded group, so a
-- burst of loot never has to create a frame while an event is being handled (rule 11).
local MAX_ROWS_LIMIT, MAX_GROUP_ROWS = 10, 6
local POOL_SIZE = MAX_ROWS_LIMIT + MAX_GROUP_ROWS
local DEFAULT_POSITION = { point = "TOPLEFT", relativePoint = "CENTER", x = 180, y = -40 }
local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}
R.UI.lootFeedMaxGroupRows = MAX_GROUP_ROWS

local function step()
    return Theme.lootRowHeight + ROW_GAP
end

local function percentText(value)
    return string.format(R.L.UI_TOAST_PERCENT, math.floor(value + 0.5))
end

local function rowsText(value)
    return string.format(R.L.UI_TOAST_ROWS, value)
end

local function secondsText(value)
    return string.format(R.L.UI_TOAST_SECONDS, value)
end

-- One shared handler rather than a closure per row, so expanding a group allocates nothing.
local function onChevron(chevron)
    local row = chevron:GetParent()
    if row.host and row.item then row.host:ToggleItem(row.item) end
end

-- The feed is one anchored stack, not a cloud of floating toasts: rows enter at the bottom,
-- the oldest fades first, and the rest slide up into the gap it leaves.
function R.UI:CreateLootFeed(owner)
    if owner.refactorLootFeed then return owner.refactorLootFeed end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host.owner = owner
    host.items, host.byKey = {}, {}
    host.pool = R.Pools:Create(function()
        local row = Theme:LootRow(host, ROW_WIDTH)
        row.host = host
        row.onHidden = function(widget) host:Expire(widget) end
        row.onDismiss = function(widget) host:Dismiss(widget) end
        return row
    end, function(row) row:ResetRow() end)
    for _ = 1, POOL_SIZE do host.pool:Acquire() end
    host.pool:ReleaseAll()

    function host:Opacity()
        local opacity = R.Settings:GetOption("toastOpacity")
        return type(opacity) == "number" and opacity or 1
    end

    function host:Lifetime()
        local lifetime = R.Settings:GetOption("toastLifetime")
        return type(lifetime) == "number" and lifetime or 5
    end

    function host:MaxRows()
        local rows = R.Settings:GetOption("toastMaxRows")
        return math.min(MAX_ROWS_LIMIT, type(rows) == "number" and rows or 5)
    end

    -- Returns nil when every frame is busy, which drops the row instead of queueing it.
    function host:Take()
        if #self.pool.free == 0 then return nil end
        return self.pool:Acquire()
    end

    function host:Fill(row, entry, expandable, expanded)
        -- The link is what lets a hovered row show the item's own tooltip.
        row.link = entry.link
        row:SetRowOpacity(self:Opacity())
        row:SetIcon(entry.icon, entry.r, entry.g, entry.b, entry.framed)
        row:SetLines(entry.name, entry.detail, entry.r, entry.g, entry.b)
        row:SetExpander(expandable, expanded, onChevron)
    end

    function host:Layout(animate)
        local y, last = 0, nil
        for _, item in ipairs(self.items) do
            item.row:PlaceAt(self, 0, y, animate)
            item.row:SetUnderlineShown(true)
            last, y = item.row, y - step()
            if item.expanded then
                for _, row in ipairs(item.children) do
                    row:PlaceAt(self, CHILD_INDENT, y, animate)
                    row:SetUnderlineShown(true)
                    last, y = row, y - step()
                end
            end
        end
        -- The separator sits between rows, so the bottom row never wears one.
        if last then last:SetUnderlineShown(false) end
        self:SetSize(ROW_WIDTH, math.max(step(), self:MaxRows() * step()))
    end

    function host:Collapse(item)
        for index = #item.children, 1, -1 do
            self.pool:Release(item.children[index])
            item.children[index] = nil
        end
        item.expanded = false
    end

    function host:Drop(item)
        for index, current in ipairs(self.items) do
            if current == item then table.remove(self.items, index) break end
        end
        if item.row.key then self.byKey[item.row.key] = nil end
        self:Collapse(item)
        item.row.item = nil
        self.pool:Release(item.row)
    end

    -- The row's own fade finished. Everything below it slides up into the gap.
    function host:Expire(row)
        if row.item then
            self:Drop(row.item)
            self:Layout(true)
        end
    end

    -- Right clicking any row of a group dismisses the whole group: the count on the parent
    -- would otherwise disagree with what is left under it.
    function host:Dismiss(row)
        local item = row.item
        if not item then
            for _, candidate in ipairs(self.items) do
                for _, child in ipairs(candidate.children) do
                    if child == row then
                        item = candidate
                        break
                    end
                end
                if item then break end
            end
        end
        if not item then return end
        self:Drop(item)
        self:Layout(true)
    end

    function host:Trim()
        local maximum = self:MaxRows()
        while #self.items > maximum do
            self:Drop(self.items[1])
        end
    end

    -- An expanded group has no countdown: it waits for the player to collapse it again.
    function host:ToggleItem(item)
        if item.expanded then
            self:Collapse(item)
            item.row:SetExpander(true, false, onChevron)
            item.row:Present(self:Lifetime())
        else
            local children = item.entry.children or {}
            for index = 1, math.min(#children, MAX_GROUP_ROWS) do
                local row = self:Take()
                if not row then break end
                row.item, row.key = nil, nil
                self:Fill(row, children[index], false, false)
                -- A child row lives as long as the group is open, so it never counts down.
                row:HoldTimer()
                item.children[#item.children + 1] = row
            end
            item.expanded = true
            item.row:HoldTimer()
            item.row:SetExpander(true, true, onChevron)
        end
        self:Layout(true)
    end

    -- A key that is already on screen bumps that row rather than adding another, which is
    -- what makes a second drop of the same item read as "x2".
    function host:Push(entry)
        local expandable = entry.children ~= nil and #entry.children > 0
        local item = entry.key and self.byKey[entry.key]
        if item then
            item.entry = entry
            self:Fill(item.row, entry, expandable, item.expanded)
            if not item.expanded then item.row:Present(self:Lifetime()) end
            return item
        end
        local row = self:Take()
        if not row then return nil end
        item = { row = row, entry = entry, expanded = false, children = {} }
        row.item, row.key = item, entry.key
        if entry.key then self.byKey[entry.key] = item end
        self.items[#self.items + 1] = item
        self:Fill(row, entry, expandable, false)
        self:Trim()
        self:Layout(false)
        row:Present(self:Lifetime())
        return item
    end

    function host:Clear()
        for index = #self.items, 1, -1 do
            self:Drop(self.items[index])
        end
        self:Layout(false)
    end

    function host:Scale()
        local scale = R.Settings:GetOption("toastScale")
        return type(scale) == "number" and scale or 1
    end

    -- Opacity, size and row count are live settings: what is already on screen follows them.
    function host:ApplySettings()
        self:SetScale(self:Scale())
        for _, item in ipairs(self.items) do
            item.row:SetRowOpacity(self:Opacity())
            for _, row in ipairs(item.children) do row:SetRowOpacity(self:Opacity()) end
        end
        self:Trim()
        self:Layout(false)
        if self.dialog and self.dialog:IsShown() then
            self.dialog:Refresh()
        end
    end

    function host:SavePosition()
        local character = R.Settings.character
        if not character then return end
        local point, _, relativePoint, x, y = self:GetPoint(1)
        character.toast = { point = point, relativePoint = relativePoint, x = x, y = y }
    end

    function host:RestorePosition()
        local saved = R.Settings.character and R.Settings.character.toast or nil
        if type(saved) ~= "table" or not VALID_POINTS[saved.point] or not VALID_POINTS[saved.relativePoint]
            or type(saved.x) ~= "number" or type(saved.y) ~= "number" then
            saved = DEFAULT_POSITION
        end
        self:ClearAllPoints()
        self:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end

    host:RestorePosition()
    host:Layout(false)

    -- Blizzard's own Edit Mode dialog for a system: a Dialog-bordered panel with the system
    -- name, a close button, and one minimal slider per numeric setting. Built once here,
    -- never inside an event handler (rule 11).
    local inner = DIALOG_WIDTH - DIALOG_PADDING * 2
    local dialog = CreateFrame("Frame", nil, UIParent)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetSize(DIALOG_WIDTH, DIALOG_TOP + 3 * (Theme.sliderRowHeight + DIALOG_ROW_GAP)
        - DIALOG_ROW_GAP + DIALOG_PADDING)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    Theme:Panel(dialog)
    dialog.title = Theme:Text(dialog, R.L.UI_TOAST_SYSTEM_LABEL, "body", "TEXT_TITLE")
    dialog.title:SetPoint("TOPLEFT", DIALOG_PADDING, -14)
    dialog.title:SetPoint("TOPRIGHT", -DIALOG_PADDING, -14)
    dialog.title:SetJustifyH("CENTER")
    dialog.close = Theme:CloseButton(dialog, function() dialog:Hide() end)
    -- Flush on the corner, where Blizzard's Edit Mode dialogs anchor theirs.
    dialog.close:SetPoint("TOPRIGHT")
    dialog:Hide()
    host.dialog = dialog

    dialog.settings = {}
    local function setting(index, key, minimum, maximum, stepSize, labelKey, formatter, write, read)
        local slider = Theme:Slider(dialog, inner, minimum, maximum, stepSize, write)
        slider:SetPoint("TOPLEFT", DIALOG_PADDING, -(DIALOG_TOP + (index - 1)
            * (Theme.sliderRowHeight + DIALOG_ROW_GAP)))
        slider:SetLabel(R.L[labelKey], formatter)
        slider.optionKey, slider.read = key, read
        slider.onUndo = function()
            R.Settings:SetOption(key, R.Settings.optionDefaults[key])
            dialog:Refresh()
        end
        dialog.settings[index] = slider
        return slider
    end

    -- Scale is stored as a factor and shown as a percentage, the way Blizzard shows one.
    dialog.scale = setting(1, "toastScale", 70, 150, 5, "UI_TOAST_SCALE", percentText,
        function(value) R.Settings:SetOption("toastScale", value / 100) end,
        function() return math.floor(host:Scale() * 100 + 0.5) end)
    dialog.rows = setting(2, "toastMaxRows", 1, MAX_ROWS_LIMIT, 1, "UI_TOAST_MAX_ROWS", rowsText,
        function(value) R.Settings:SetOption("toastMaxRows", value) end,
        function() return host:MaxRows() end)
    dialog.lifetime = setting(3, "toastLifetime", 1, 20, 1, "UI_TOAST_LIFETIME", secondsText,
        function(value) R.Settings:SetOption("toastLifetime", value) end,
        function() return host:Lifetime() end)

    function dialog:Refresh()
        for _, slider in ipairs(self.settings) do
            slider:SetValue(slider.read())
            local key = slider.optionKey
            slider.undo:SetShown(R.Settings:GetOption(key) ~= R.Settings.optionDefaults[key])
        end
    end

    -- Screen space, never the feed: a dialog anchored to the feed would walk away under the
    -- cursor while the size slider it belongs to is being dragged.
    function dialog:Detach()
        local left, top = self:GetLeft(), self:GetTop()
        if not left or not top then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end

    function dialog:SavePosition()
        local character = R.Settings.character
        local left, top = self:GetLeft(), self:GetTop()
        if character and left and top then
            character.lootDialog = { x = left, y = top }
        end
    end

    function dialog:RestorePosition()
        local saved = R.Settings.character and R.Settings.character.lootDialog or nil
        self:ClearAllPoints()
        if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
            return
        end
        -- First open: beside the feed, then pinned to where that put it.
        self:SetPoint("TOPLEFT", host, "TOPRIGHT", DIALOG_GAP, 0)
        self:Show()
        self:Detach()
    end

    dialog:SetScript("OnDragStop", function(widget)
        widget:StopMovingOrSizing()
        widget:Detach()
        widget:SavePosition()
    end)

    function host:ToggleDialog()
        if self.dialog:IsShown() then
            self.dialog:Hide()
            return
        end
        self.dialog:RestorePosition()
        self.dialog:Refresh()
        self.dialog:Show()
    end

    -- Created once here, never inside an event handler (rule 11).
    local selection = Theme:EditModeSelection(host, R.L.UI_TOAST_SYSTEM_LABEL)
    host.selection = selection
    selection:SetScript("OnEnter", function(widget) widget:SetSelected(true) end)
    selection:SetScript("OnLeave", function(widget) widget:SetSelected(widget.dragging == true) end)
    selection:SetScript("OnDragStart", function(widget)
        widget.dragging = true
        widget:SetSelected(true)
        host:StartMoving()
    end)
    selection:SetScript("OnDragStop", function(widget)
        widget.dragging = nil
        -- The click that ends a drag must not also count as the click that opens settings.
        widget.dragged = true
        host:StopMovingOrSizing()
        host:SavePosition()
        widget:SetSelected(false)
    end)
    selection:SetScript("OnMouseUp", function(widget)
        if widget.dragged then
            widget.dragged = nil
            return
        end
        host:ToggleDialog()
    end)

    -- Blizzard fires these for everyone the moment Edit Mode opens and closes. Refactor is
    -- not a registered system, so this is the whole integration.
    function host:SetEditing(editing)
        local usable = editing and self.owner.state == "enabled"
        self.selection:SetShown(usable)
        if not usable then
            self.dialog:Hide()
        end
    end

    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() host:SetEditing(true) end, host)
        EventRegistry:RegisterCallback("EditMode.Exit", function() host:SetEditing(false) end, host)
    end

    owner.refactorLootFeed = host
    return host
end
