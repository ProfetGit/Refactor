local _, R = ...
local L = R.L

-- Blizzard's own window kit, deliberately: the HUD is Refactor's, but a report you read,
-- scroll and copy from should look like every other panel in the game.
local WIDTH, HEIGHT, PAD, TOP = 460, 470, 16, 34
local HEADER_LINE, ROW_HEIGHT, BUTTON_HEIGHT = 15, 17, 22
local LIST_BOTTOM = 40
local WHEEL_STEP = ROW_HEIGHT * 3
-- Past this the list stops growing and says so. The Copy block always holds everything.
local MAX_ROWS = 100
local COPY_WIDTH, COPY_HEIGHT = 520, 420

local function scrollBy(scroll, delta)
    local range = scroll:GetVerticalScrollRange() or 0
    local value = scroll:GetVerticalScroll() - delta * WHEEL_STEP
    scroll:SetVerticalScroll(math.max(0, math.min(range, value)))
end

-- A plain text block, selected and ready for Ctrl C. The client cannot put anything on the
-- system clipboard for us, so the honest answer is to hand the player the text itself.
-- Shared: the farm summary and the chat copy button both end here, with their own title.
function R.UI:ShowSessionText(text, title)
    if not self.sessionTextFrame then
        local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(COPY_WIDTH, COPY_HEIGHT)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        R:OwnFrame(frame)

        local scroll = CreateFrame("ScrollFrame", nil, frame)
        scroll:SetPoint("TOPLEFT", PAD, -TOP)
        scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", scrollBy)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(R.Theme.fonts.small)
        box:SetWidth(COPY_WIDTH - PAD * 2 - 8)
        box:SetScript("OnEscapePressed", function() frame:Hide() end)
        scroll:SetScrollChild(box)
        frame.box = box
        self.sessionTextFrame = frame
    end
    local frame = self.sessionTextFrame
    frame.TitleText:SetText(title or L.FARM_COPY_TITLE)
    frame.box:SetText(text or "")
    frame:Show()
    frame.box:SetFocus()
    frame.box:HighlightText()
end

-- `build` returns the report: header lines, item rows already sorted, and the plain text
-- block. Everything numeric is formatted by the module that owns the session, so this file
-- never touches a price or a clock.
function R.UI:ShowSessionSummary(build)
    if not self.sessionSummary then
        local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(WIDTH, HEIGHT)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame.TitleText:SetText(L.FARM_SUMMARY_TITLE)
        R:OwnFrame(frame)

        frame.header = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        frame.header:SetPoint("TOPLEFT", PAD, -TOP)
        frame.header:SetPoint("RIGHT", -PAD, 0)
        frame.header:SetJustifyH("LEFT")
        frame.header:SetJustifyV("TOP")
        frame.header:SetSpacing(2)

        frame.listTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        frame.listTitle:SetPoint("TOPLEFT", PAD, 0)
        frame.listTitle:SetText(L.FARM_SUMMARY_ITEMS)

        local scroll = CreateFrame("ScrollFrame", nil, frame)
        scroll:SetPoint("TOPLEFT", frame.listTitle, "BOTTOMLEFT", 0, -6)
        scroll:SetPoint("BOTTOMRIGHT", -PAD, LIST_BOTTOM)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", scrollBy)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(WIDTH - PAD * 2, 1)
        scroll:SetScrollChild(child)
        frame.scroll, frame.child, frame.rows = scroll, child, {}

        frame.empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        frame.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -4)
        frame.empty:SetText(L.FARM_SUMMARY_EMPTY)

        frame.copy = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.copy:SetSize(110, BUTTON_HEIGHT)
        frame.copy:SetPoint("BOTTOMLEFT", PAD, 12)
        frame.copy:SetText(L.FARM_SUMMARY_COPY)
        frame.copy:SetScript("OnClick", function() R.UI:ShowSessionText(frame.report and frame.report.text) end)

        frame.refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.refresh:SetSize(110, BUTTON_HEIGHT)
        frame.refresh:SetPoint("LEFT", frame.copy, "RIGHT", 8, 0)
        frame.refresh:SetText(L.FARM_SUMMARY_REFRESH)
        frame.refresh:SetScript("OnClick", function() R.UI:RefreshSessionSummary() end)

        frame.footer = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        frame.footer:SetPoint("BOTTOMRIGHT", -PAD, 18)
        frame.footer:SetJustifyH("RIGHT")
        self.sessionSummary = frame
    end
    self.sessionSummary.build = build or self.sessionSummary.build
    self:RefreshSessionSummary()
    self.sessionSummary:Show()
end

-- Rows are created here rather than at module enable because this window is opened by a
-- click and never by a game event, which is the boundary rule 11 draws.
function R.UI:SessionSummaryRow(index)
    local frame = self.sessionSummary
    local row = frame.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, frame.child)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame.child, "RIGHT")
    row:SetHeight(ROW_HEIGHT)
    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.count:SetPoint("LEFT")
    row.count:SetWidth(34)
    row.count:SetJustifyH("RIGHT")
    row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT")
    row.value:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.count, "RIGHT", 10, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -10, 0)
    row.name:SetJustifyH("LEFT")
    frame.rows[index] = row
    return row
end

function R.UI:RefreshSessionSummary()
    local frame = self.sessionSummary
    if not frame or not frame.build then return end
    local report = frame.build()
    frame.report = report
    frame.header:SetText(table.concat(report.lines or {}, "\n"))
    frame.header:SetHeight(math.max(HEADER_LINE, #(report.lines or {}) * HEADER_LINE))
    frame.listTitle:ClearAllPoints()
    frame.listTitle:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -10)
    local rows = report.rows or {}
    local shown = math.min(#rows, MAX_ROWS)
    for index = 1, shown do
        local row, entry = self:SessionSummaryRow(index), rows[index]
        row.count:SetText(entry.count)
        row.name:SetText(entry.name)
        row.name:SetTextColor(entry.r or 1, entry.g or 1, entry.b or 1)
        row.value:SetText(entry.value)
        row:Show()
    end
    for index = shown + 1, #frame.rows do
        frame.rows[index]:Hide()
    end
    frame.child:SetHeight(math.max(1, shown * ROW_HEIGHT))
    frame.scroll:SetVerticalScroll(0)
    frame.empty:SetShown(shown == 0)
    frame.footer:SetText(#rows > shown and string.format(L.FARM_SUMMARY_TRUNCATED, shown, #rows) or "")
end
