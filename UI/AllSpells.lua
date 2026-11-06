local _, R = ...
local L = R.L
local Theme = R.Theme

-- Refactor's own panel, docked to the right of the spellbook. Nothing here touches a Blizzard
-- frame beyond anchoring to it: the spellbook's buttons cast, and writing to them would taint.
-- The list is virtual: a fixed pool of rows is recycled by scroll offset, so the frame count
-- never depends on how many spells a class has.
local WIDTH, DOCK_GAP, PAD = 320, 3, 16
local TITLE_Y, SUMMARY_Y, NEXT_Y, RULE_Y = -16, -44, -60, -82
local SEARCH_Y, SEARCH_HEIGHT = -94, 26
local TAB_Y, LIST_Y = -154, -162
local SCROLL_GUTTER = 24
local POOL, WHEEL_ROWS = 24, 3
local SPELL_HEIGHT, HEADER_HEIGHT, ICON, ICON_CROP = 36, 30, 28, 0.08
local LABEL_WIDTH, ROW_PAD = 66, 6
local NOTE_HEIGHT, NOTE_ICON = 40, 16
local PANEL_LEVEL = 5
local FUTURE_ICON_ALPHA = 0.55
local FALLBACK_WIDTH, FALLBACK_HEIGHT = WIDTH - PAD * 2 - SCROLL_GUTTER, 520
local TABS = {
    { key = "all", text = "ALL_SPELLS_TAB_ALL" },
    { key = "toLearn", text = "ALL_SPELLS_TAB_LEARN" },
    { key = "learned", text = "ALL_SPELLS_TAB_LEARNED" },
}

local function hideTip(row)
    if GameTooltip:IsOwned(row) then
        GameTooltip:Hide()
    end
end

local function entryHeight(entry)
    return entry.header and HEADER_HEIGHT or SPELL_HEIGHT
end

local function showTip(row)
    if row.spellID then
        row.wash:To(1)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(row.spellID)
        GameTooltip:Show()
    end
end

local function newRow(ui)
    local row = CreateFrame("Frame", nil, ui.list)
    row:EnableMouse(true)
    row.wash = Theme:RowHighlight(row)
    row.accent = Theme:Fill(row, "RING_DONE", "ARTWORK")
    row.accent:ClearAllPoints()
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")
    row.accent:SetWidth(2)
    row.accent:SetAlpha(0.9)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", ROW_PAD, 0)
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    row.border = Theme:Texture(row, "itemBorder", "OVERLAY")
    row.border:SetAllPoints(row.icon)
    row.label = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.label:SetWidth(LABEL_WIDTH)
    row.label:SetJustifyH("RIGHT")
    row.label:SetPoint("RIGHT", -ROW_PAD, 0)
    row.name = Theme:Text(row, "", "body", "TEXT_BODY")
    row.name:SetWordWrap(false)
    row.sub = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.sub:SetWordWrap(false)
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row.title = Theme:Text(row, "", "body", "TEXT_TITLE")
    row.title:SetWordWrap(false)
    row.title:SetPoint("BOTTOMLEFT", ROW_PAD, 7)
    row.count = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.count:SetJustifyH("RIGHT")
    row.count:SetPoint("BOTTOMRIGHT", -ROW_PAD, 7)
    row.rule = Theme:Divider(row)
    row.rule:SetPoint("BOTTOMLEFT", 0, 2)
    row.rule:SetPoint("BOTTOMRIGHT", 0, 2)
    row:SetScript("OnEnter", showTip)
    row:SetScript("OnLeave", function(widget)
        widget.wash:To(0)
        hideTip(widget)
    end)
    row:Hide()
    return row
end

local function fillSpell(ui, row, entry)
    row.spellID = entry.spellID
    if entry.icon then
        row.icon:SetTexture(entry.icon)
    else
        Theme:ApplyAsset(row.icon, "unknownItem")
    end
    local future = not entry.known and not entry.trainable
    row.icon:SetDesaturated(not entry.known)
    row.icon:SetAlpha(future and FUTURE_ICON_ALPHA or 1)
    Theme:Color(row.border, entry.known and "ACCENT_COPPER" or entry.trainable and "RING_DONE" or "TEXT_MUTED")
    row.border:SetAlpha(future and FUTURE_ICON_ALPHA or 1)
    row.accent:SetShown(entry.trainable == true)
    Theme:Color(row.name, future and "TEXT_MUTED" or "TEXT_BODY", true)
    row.name:SetText(entry.name)
    row.name:SetWidth(ui.nameWidth)
    row.name:ClearAllPoints()
    local sub = entry.sub or ""
    if sub ~= "" then
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.sub:SetText(sub)
        row.sub:SetWidth(ui.nameWidth)
    else
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    end
    row.sub:SetShown(sub ~= "")
    if entry.trainable then
        Theme:Color(row.label, "RING_DONE", true)
        row.label:SetText(L.ALL_SPELLS_TRAINABLE)
    else
        Theme:Color(row.label, "TEXT_MUTED", true)
        row.label:SetText(entry.level >= 1 and string.format(L.ALL_SPELLS_LEVEL, entry.level) or "")
    end
end

local function fillRow(ui, row, entry)
    row.spellID = nil
    row.wash:Snap(0)
    hideTip(row)
    if not entry then
        row:Hide()
        return
    end
    local isHeader = entry.header ~= nil
    row.title:SetShown(isHeader)
    row.count:SetShown(isHeader)
    row.rule:SetShown(isHeader)
    row.icon:SetShown(not isHeader)
    row.border:SetShown(not isHeader)
    row.name:SetShown(not isHeader)
    row.label:SetShown(not isHeader)
    row.accent:SetShown(false)
    row.sub:SetShown(false)
    if isHeader then
        row.title:SetText(entry.header)
        row.title:SetWidth(ui.rowWidth - LABEL_WIDTH - ROW_PAD * 2)
        row.count:SetText(string.format(L.ALL_SPELLS_COUNT, entry.learned or 0, entry.total or 0))
    else
        fillSpell(ui, row, entry)
    end
    row:Show()
    if not isHeader and row:IsMouseOver() then
        showTip(row)
    end
end

-- How many entries fit when the list is scrolled to its end, which is also how far it can scroll.
local function measure(ui)
    local rows, used, fit = ui.entries, 0, 0
    for index = #rows, 1, -1 do
        local height = entryHeight(rows[index])
        if used + height > ui.viewport then
            break
        end
        used = used + height
        fit = fit + 1
    end
    fit = math.min(fit, POOL)
    ui.fit = fit
    ui.maxOffset = math.max(0, #rows - fit)
end

local function sizeBar(ui)
    local slider, bar = ui.slider, Theme.scrollBar
    local scrolls = ui.maxOffset > 0
    slider:SetMinMaxValues(0, ui.maxOffset)
    local track = slider:GetHeight()
    if scrolls and type(track) == "number" and track > 0 then
        slider.thumb.anchor:SetHeight(math.min(track, math.max(bar.minThumb, track * ui.fit / #ui.entries)))
    end
    slider:SetShown(scrolls)
    ui.up:SetShown(scrolls)
    ui.down:SetShown(scrolls)
end

function R.UI:AllSpellsRender(ui)
    local rows = ui.entries
    ui.offset = math.max(0, math.min(ui.offset, ui.maxOffset))
    local y, full = ui.noteHeight, false
    for slot = 1, POOL do
        local row = ui.pool[slot]
        local entry = rows[ui.offset + slot]
        local height = entry and entryHeight(entry)
        if not entry or full or y + height - ui.noteHeight > ui.viewport then
            full = true
            fillRow(ui, row, nil)
        else
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 0, -y)
            row:SetSize(ui.rowWidth, height)
            fillRow(ui, row, entry)
            y = y + height
        end
    end
    if ui.slider:GetValue() ~= ui.offset then
        ui.slider:SetValue(ui.offset)
    end
    ui.empty:SetShown(#rows == 0)
end

local function setOffset(ui, offset)
    offset = math.max(0, math.min(ui.maxOffset, offset))
    if offset ~= ui.offset then
        ui.offset = offset
        R.UI:AllSpellsRender(ui)
    end
end

-- The list's room, and so how many rows fit, is known only once the client has laid the panel
-- out. Runs when the panel shows and whenever the list is resized or refilled.
function R.UI:AllSpellsLayout(ui)
    local width, height = ui.list:GetWidth(), ui.list:GetHeight()
    if type(width) ~= "number" or width < 1 then width = FALLBACK_WIDTH end
    if type(height) ~= "number" or height < 1 then height = FALLBACK_HEIGHT end
    ui.rowWidth = width
    ui.nameWidth = math.max(40, width - ROW_PAD * 2 - ICON - 8 - LABEL_WIDTH - 8)
    ui.viewport = math.max(1, height - ui.noteHeight)
    measure(ui)
    sizeBar(ui)
    self:AllSpellsRender(ui)
end

-- Made once at module enable and kept: the panel and the pool of rows, all
-- parented to UIParent and hidden until the module finds the spellbook and attaches them.
function R.UI:AllSpellsCreate(handlers)
    local ui = { handlers = handlers, pool = {}, entries = {}, offset = 0, maxOffset = 0, fit = 0,
        noteHeight = 0, rowWidth = FALLBACK_WIDTH, nameWidth = 160, viewport = FALLBACK_HEIGHT,
        attached = false, tabs = {} }
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(WIDTH)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:Hide()
    R:OwnFrame(panel)
    Theme:Panel(panel)
    ui.panel = panel

    ui.title = Theme:Text(panel, L.ALL_SPELLS_TITLE, "title", "TEXT_TITLE")
    ui.title:SetPoint("TOPLEFT", PAD, TITLE_Y)
    ui.title:SetPoint("RIGHT", -PAD, 0)
    ui.title:SetWordWrap(false)
    ui.summary = Theme:Text(panel, "", "small", "TEXT_BODY")
    ui.summary:SetPoint("TOPLEFT", PAD, SUMMARY_Y)
    ui.summary:SetPoint("RIGHT", -PAD, 0)
    ui.summary:SetWordWrap(false)
    ui.upcoming = Theme:Text(panel, "", "small", "TEXT_MUTED")
    ui.upcoming:SetPoint("TOPLEFT", PAD, NEXT_Y)
    ui.upcoming:SetPoint("RIGHT", -PAD, 0)
    ui.upcoming:SetWordWrap(false)
    ui.rule = Theme:Divider(panel)
    ui.rule:SetPoint("TOPLEFT", PAD, RULE_Y)
    ui.rule:SetPoint("TOPRIGHT", -PAD, RULE_Y)

    ui.search = R.UI.Widgets:Search(panel, WIDTH - PAD * 2, SEARCH_HEIGHT, L.ALL_SPELLS_SEARCH)
    ui.search:SetPoint("TOPLEFT", PAD, SEARCH_Y)
    ui.search:SetPoint("TOPRIGHT", -PAD, SEARCH_Y)
    ui.search:SetScript("OnTextChanged", function(widget)
        widget.placeholder:SetShown(widget:GetText() == "")
        handlers.onSearch()
    end)

    local previous
    for index, entry in ipairs(TABS) do
        local tab = Theme:Tab(panel, L[entry.text], function() handlers.onTab(entry.key) end)
        if previous then
            tab:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 0, 0)
        else
            tab:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", PAD, TAB_Y)
        end
        tab.key = entry.key
        ui.tabs[index], previous = tab, tab
    end
    ui.tabRule = Theme:Divider(panel)
    ui.tabRule:SetPoint("TOPLEFT", PAD, TAB_Y)
    ui.tabRule:SetPoint("TOPRIGHT", -PAD, TAB_Y)

    ui.list = CreateFrame("Frame", nil, panel)
    ui.list:SetPoint("TOPLEFT", PAD, LIST_Y)
    ui.list:SetPoint("BOTTOMRIGHT", -PAD - SCROLL_GUTTER, PAD)
    ui.list:EnableMouseWheel(true)
    ui.list:SetScript("OnSizeChanged", function() R.UI:AllSpellsLayout(ui) end)

    ui.note = CreateFrame("Frame", nil, ui.list)
    ui.note:SetPoint("TOPLEFT")
    ui.note:SetPoint("TOPRIGHT")
    ui.note:SetHeight(NOTE_HEIGHT)
    ui.note.icon = Theme:InfoIcon(ui.note, NOTE_ICON)
    ui.note.icon:SetPoint("TOPLEFT", ROW_PAD, -2)
    ui.note.text = Theme:Text(ui.note, L.ALL_SPELLS_NO_DATA, "small", "TEXT_MUTED")
    ui.note.text:SetPoint("TOPLEFT", ROW_PAD + NOTE_ICON + 8, 0)
    ui.note.text:SetPoint("RIGHT", -ROW_PAD, 0)
    ui.note.text:SetJustifyV("TOP")
    ui.note:Hide()

    ui.empty = Theme:Text(ui.list, L.ALL_SPELLS_NONE, "body", "TEXT_MUTED")
    ui.empty:SetPoint("CENTER", ui.list, "CENTER", 0, 0)
    ui.empty:SetJustifyH("CENTER")
    ui.empty:Hide()

    for index = 1, POOL do
        ui.pool[index] = newRow(ui)
    end

    local bar = Theme.scrollBar
    ui.slider = Theme:ScrollBar(panel)
    ui.slider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD - 4, LIST_Y - bar.trackInset)
    ui.slider:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD - 4, PAD + bar.trackInset)
    ui.slider:SetMinMaxValues(0, 0)
    ui.slider:SetValueStep(1)
    ui.slider:SetScript("OnEnter", function(widget) Theme:ScrollThumbState(widget.thumb, "over") end)
    ui.slider:SetScript("OnLeave", function(widget) Theme:ScrollThumbState(widget.thumb, "normal") end)
    ui.slider:SetScript("OnValueChanged", function(_, value) setOffset(ui, math.floor(value + 0.5)) end)
    ui.slider:SetScript("OnMouseDown", function(widget) Theme:ScrollThumbState(widget.thumb, "down") end)
    ui.slider:SetScript("OnMouseUp", function(widget)
        Theme:ScrollThumbState(widget.thumb, widget:IsMouseOver() and "over" or "normal")
    end)
    ui.up = Theme:ScrollStepper(panel, "scrollUp", function() setOffset(ui, ui.offset - 1) end)
    ui.up:SetPoint("BOTTOM", ui.slider, "TOP", 0, bar.stepperGap)
    ui.down = Theme:ScrollStepper(panel, "scrollDown", function() setOffset(ui, ui.offset + 1) end)
    ui.down:SetPoint("TOP", ui.slider, "BOTTOM", 0, -bar.stepperGap)
    ui.slider:Hide()
    ui.up:Hide()
    ui.down:Hide()

    local function wheel(_, delta) setOffset(ui, ui.offset - delta * WHEEL_ROWS) end
    panel:SetScript("OnMouseWheel", wheel)
    ui.list:SetScript("OnMouseWheel", wheel)
    panel:SetScript("OnShow", function()
        R.UI:AllSpellsLayout(ui)
        handlers.onShow()
    end)
    panel:SetScript("OnHide", function()
        for _, row in ipairs(ui.pool) do
            hideTip(row)
        end
        handlers.onHide()
    end)
    return ui
end

function R.UI:AllSpellsSetTab(ui, key)
    for _, tab in ipairs(ui.tabs) do
        Theme:TabState(tab, tab.key == key)
    end
end

-- The two header lines, and the note that stands in for spells only the trainer can name.
function R.UI:AllSpellsSetSummary(ui, learned, total, upcoming, showNote)
    ui.summary:SetText(string.format(L.ALL_SPELLS_LEARNED, learned, total))
    ui.upcoming:SetText(upcoming and string.format(L.ALL_SPELLS_UPCOMING, upcoming.name, upcoming.level) or "")
    ui.noteHeight = showNote and NOTE_HEIGHT or 0
    ui.note:SetShown(showNote == true)
end

-- reset sends the list back to its top: a new search or tab is a new list, a refresh is not.
function R.UI:AllSpellsSetRows(ui, entries, reset)
    ui.entries = entries
    if reset then
        ui.offset = 0
    end
    self:AllSpellsLayout(ui)
end

-- Docks the panel to the window's right edge and parents it to the book, so it leaves with it.
function R.UI:AllSpellsAttach(ui, window, book)
    local panel = ui.panel
    local host = book or window
    ui.attached = true
    panel:SetParent(host)
    panel:SetFrameStrata(window:GetFrameStrata())
    panel:SetFrameLevel(host:GetFrameLevel() + PANEL_LEVEL)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", window, "TOPRIGHT", DOCK_GAP, 0)
    panel:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", DOCK_GAP, 0)
    panel:Show()
end

function R.UI:AllSpellsDetach(ui)
    ui.attached = false
    ui.panel:Hide()
    ui.panel:SetParent(UIParent)
    ui.panel:ClearAllPoints()
end
