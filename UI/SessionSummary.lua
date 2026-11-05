local _, R = ...
local L = R.L
local Theme = R.Theme

-- Refactor's own window, the same Dialog border and title the main window wears: these are
-- Refactor's frames, so a report opened from the HUD reads as part of the addon it came
-- from, with the same close button in the same corner.
local WIDTH, HEIGHT, PAD, TOP = 460, 470, 22, 58
local TITLE_Y, RULE_Y = -20, -44
local HEADER_LINE, ROW_HEIGHT = 15, 17
local LIST_BOTTOM = 52
local WHEEL_STEP = ROW_HEIGHT * 3
-- Past this the list stops growing and says so. The Copy block always holds everything.
local MAX_ROWS = 100
local COPY_WIDTH, COPY_HEIGHT = 520, 420
local BUTTON_WIDTH = 110

local function scrollBy(scroll, delta)
    local range = scroll:GetVerticalScrollRange() or 0
    local value = scroll:GetVerticalScroll() - delta * WHEEL_STEP
    scroll:SetVerticalScroll(math.max(0, math.min(range, value)))
end

-- A movable Refactor window with a title and the corner close button.
local function window(width, height)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    -- Two windows at one frame level draw their layers interleaved, so the copy box opened
    -- over the summary showed the summary's text through its own ground. Toplevel raises a
    -- window above its neighbours when clicked, and it is raised again whenever it opens.
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    R:OwnFrame(frame)
    Theme:Panel(frame)
    frame.title = Theme:Text(frame, "", "title", "TEXT_TITLE")
    frame.title:SetPoint("TOPLEFT", PAD, TITLE_Y)
    frame.title:SetPoint("RIGHT", -PAD * 2, 0)
    frame.title:SetWordWrap(false)
    frame.rule = Theme:Divider(frame)
    frame.rule:SetPoint("TOPLEFT", PAD, RULE_Y)
    frame.rule:SetPoint("TOPRIGHT", -PAD, RULE_Y)
    local close = Theme:CloseButton(frame, function() frame:Hide() end)
    close:SetPoint("CENTER", frame, "TOPRIGHT", -10, -10)
    frame.close = close
    return frame
end

-- A plain text block, selected and ready for Ctrl C. The client cannot put anything on the
-- system clipboard for us, so the honest answer is to hand the player the text itself.
-- Shared: the farm summary and the chat copy button both end here, with their own title.
function R.UI:ShowSessionText(text, title)
    if not self.sessionTextFrame then
        local frame = window(COPY_WIDTH, COPY_HEIGHT)
        -- The text is the whole window, so it sits on the panel's inset surface like an
        -- input, rather than straight on the tiled ground.
        frame.well = Theme:Fill(frame, "SURFACE", "BORDER")
        frame.well:ClearAllPoints()
        frame.well:SetPoint("TOPLEFT", PAD - 6, -TOP + 6)
        frame.well:SetPoint("BOTTOMRIGHT", -PAD + 6, PAD - 6)

        local scroll = CreateFrame("ScrollFrame", nil, frame)
        scroll:SetPoint("TOPLEFT", PAD, -TOP)
        scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", scrollBy)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(Theme.fonts.small)
        Theme:Color(box, "TEXT_BODY", true)
        box:SetWidth(COPY_WIDTH - PAD * 2 - 8)
        box:SetScript("OnEscapePressed", function() frame:Hide() end)
        scroll:SetScrollChild(box)
        frame.box = box
        self.sessionTextFrame = frame
    end
    local frame = self.sessionTextFrame
    frame.title:SetText(title or L.FARM_COPY_TITLE)
    frame.box:SetText(text or "")
    frame:Show()
    frame:Raise()
    frame.box:SetFocus()
    frame.box:HighlightText()
end

-- `build` returns the report: header lines, item rows already sorted, and the plain text
-- block. Everything numeric is formatted by the module that owns the session, so this file
-- never touches a price or a clock.
function R.UI:ShowSessionSummary(build)
    if not self.sessionSummary then
        local frame = window(WIDTH, HEIGHT)
        frame.title:SetText(L.FARM_SUMMARY_TITLE)

        frame.header = Theme:Text(frame, "", "small", "TEXT_BODY")
        frame.header:SetPoint("TOPLEFT", PAD, -TOP)
        frame.header:SetPoint("RIGHT", -PAD, 0)
        frame.header:SetJustifyV("TOP")
        frame.header:SetSpacing(2)

        frame.listTitle = Theme:Text(frame, L.FARM_SUMMARY_ITEMS, "body", "TEXT_TITLE")
        frame.listTitle:SetPoint("TOPLEFT", PAD, 0)

        local scroll = CreateFrame("ScrollFrame", nil, frame)
        scroll:SetPoint("TOPLEFT", frame.listTitle, "BOTTOMLEFT", 0, -6)
        scroll:SetPoint("BOTTOMRIGHT", -PAD, LIST_BOTTOM)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", scrollBy)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(WIDTH - PAD * 2, 1)
        scroll:SetScrollChild(child)
        frame.scroll, frame.child, frame.rows = scroll, child, {}

        frame.empty = Theme:Text(frame, L.FARM_SUMMARY_EMPTY, "small", "TEXT_MUTED")
        frame.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -4)

        frame.copy = Theme:Button(frame, BUTTON_WIDTH, L.FARM_SUMMARY_COPY, function()
            R.UI:ShowSessionText(frame.report and frame.report.text)
        end)
        frame.copy:SetPoint("BOTTOMLEFT", PAD, PAD - 4)

        frame.refresh = Theme:Button(frame, BUTTON_WIDTH, L.FARM_SUMMARY_REFRESH, function()
            R.UI:RefreshSessionSummary()
        end)
        frame.refresh:SetPoint("LEFT", frame.copy, "RIGHT", 8, 0)

        frame.footer = Theme:Text(frame, "", "small", "TEXT_MUTED")
        frame.footer:SetPoint("BOTTOMRIGHT", -PAD, PAD + 2)
        frame.footer:SetJustifyH("RIGHT")
        self.sessionSummary = frame
    end
    self.sessionSummary.build = build or self.sessionSummary.build
    self:RefreshSessionSummary()
    self.sessionSummary:Show()
    self.sessionSummary:Raise()
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
    row.count = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.count:SetPoint("LEFT")
    row.count:SetWidth(34)
    row.count:SetJustifyH("RIGHT")
    row.value = Theme:Text(row, "", "small", "TEXT_BODY")
    row.value:SetPoint("RIGHT")
    row.value:SetJustifyH("RIGHT")
    row.name = Theme:Text(row, "", "small", "TEXT_BODY")
    row.name:SetPoint("LEFT", row.count, "RIGHT", 10, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -10, 0)
    row.name:SetWordWrap(false)
    frame.rows[index] = row
    return row
end

function R.UI:RefreshSessionSummary()
    local frame = self.sessionSummary
    if not frame or not frame.build then return end
    local report = frame.build()
    frame.report = report
    frame.header:SetText(table.concat(report.lines or {}, "\n"))
    -- Measured, not counted: a long line (a price source that changed mid session) wraps,
    -- and a height of one line per entry cut its second half off.
    frame.header:SetHeight(math.max(HEADER_LINE, math.ceil(frame.header:GetStringHeight() or 0)))
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
