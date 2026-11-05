local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")
local Widgets = {}
R.UI.Widgets = Widgets

local INPUT_HEIGHT, INFO_SIZE, CHECK_SIZE = 26, 18, 26
Widgets.INPUT_HEIGHT = INPUT_HEIGHT
-- Two lines of text, name and description, on the 4 px grid.
Widgets.ROW_HEIGHT = 44
local CHEVRON_SIZE = 14
-- The name's top sits this far above the checkbox's, so the two lines together centre on it.
local TEXT_GAP, NAME_Y, DESC_GAP = 10, 2, 3
-- A settings block is inset from its row's left edge and separated from the next row by a
-- rule, so an open block reads as belonging to the row above it rather than to the list.
local BLOCK_TOP_GAP, BLOCK_BOTTOM_GAP = 10, 16
Widgets.BLOCK_INDENT = 42

-- Exponential catch-up rather than a fixed tween: a new wheel tick moves the target at
-- once and the view is always chasing it, so input never waits for an animation to end.
-- TAU is the time to close 63% of the gap, which reads as immediate but not instant.
local SCROLL_TAU, SCROLL_SNAP = 0.055, 0.5

-- Scrolled to a fraction of a pixel, every hairline in the list lands between pixels and
-- some of them stop being drawn. The glide keeps its own exact offset and only what the
-- frame is told is rounded to whole pixels.
local function toPixels(frame, value)
    local pixel = frame.pixel
    if not pixel or pixel <= 0 then return value end
    return math.floor(value / pixel + 0.5) * pixel
end

local function scrollStep(frame, elapsed)
    local delta = frame.target - frame.offset
    if delta > -SCROLL_SNAP and delta < SCROLL_SNAP then
        frame.offset = frame.target
        frame:SetVerticalScroll(toPixels(frame, frame.offset))
        frame:SetScript("OnUpdate", nil)
        return
    end
    frame.offset = frame.offset + delta * (1 - math.exp(-elapsed / SCROLL_TAU))
    frame:SetVerticalScroll(toPixels(frame, frame.offset))
end

function Widgets:Input(parent, width, height, multiline)
    local input = CreateFrame("EditBox", nil, parent)
    height = height or INPUT_HEIGHT
    input:SetSize(width, height)
    input:SetAutoFocus(false)
    input:SetMultiLine(multiline == true)
    input:SetFontObject(Theme.fonts.body)
    input:SetTextInsets(10, 10, 6, 6)
    input:SetMaxLetters(multiline and 10000 or 160)
    Theme:Color(input, "TEXT_BODY", true)
    if multiline then
        -- The single-line border is a horizontal three-slice and stretches badly; a text
        -- area gets a flat surface with a rule under it instead.
        Theme:Fill(input, "SURFACE")
        local edge = Theme:Divider(input)
        edge:SetPoint("BOTTOMLEFT")
        edge:SetPoint("BOTTOMRIGHT")
    else
        Theme:InputBorder(input, height)
    end
    input:SetScript("OnEscapePressed", function(widget) widget:ClearFocus() end)
    if not multiline then
        input:SetScript("OnEnterPressed", function(widget) widget:ClearFocus() end)
    end
    return input
end

function Widgets:Search(parent, width, height, placeholder)
    local input = self:Input(parent, width, height)
    input:SetTextInsets(28, 10, 0, 0)
    input.icon = Theme:Texture(input, "searchIcon", "OVERLAY")
    input.icon:SetSize(12, 12)
    input.icon:SetPoint("LEFT", 10, 0)
    input.placeholder = Theme:Text(input, placeholder, "small", "TEXT_MUTED")
    input.placeholder:SetPoint("LEFT", 28, 0)
    return input
end

-- A titled block on a scrolling page. Builders place their widgets from section.top down
-- and finish with SetBodyHeight, so the page can stack sections without measuring them.
function Widgets:Section(parent, title, help)
    local section = CreateFrame("Frame", nil, parent)
    section.header = Theme:SectionHeader(section, title, help)
    section.header:SetPoint("TOPLEFT")
    section.header:SetPoint("RIGHT")
    section.top = -(section.header.height + 8)
    function section:SetBodyHeight(height)
        self.height = self.header.height + 8 + height
        self:SetHeight(self.height)
    end
    return section
end

-- What a search has to match to reach a setting that is not on a row of its own. Without
-- it the only way to reach "repair limit" is to already know it lives under Auto repair.
local function indexBlock(block, ...)
    for index = 1, select("#", ...) do
        local text = select(index, ...)
        if type(text) == "string" and text ~= "" then
            block.searchText = block.searchText .. " " .. text:lower()
        end
    end
end

-- The height a paragraph needs at a given width: the tallest of the texts it may show, so a
-- note whose words change with a setting never outgrows the room kept for it. A box of fixed
-- height cut the third line off every long note, silently, in whatever language it was in.
function Widgets:TextHeight(label, width, ...)
    label:SetWidth(width)
    local current, tallest = label:GetText(), 0
    for index = 1, select("#", ...) do
        local text = select(index, ...)
        if type(text) == "string" and text ~= "" then
            label:SetText(text)
            tallest = math.max(tallest, label:GetStringHeight() or 0)
        end
    end
    label:SetText(current or "")
    return math.ceil(tallest)
end

-- Vertical rhythm inside a settings block, on the 4 px grid: what follows a control, a note,
-- and the space before a titled group.
Widgets.CONTROL_GAP, Widgets.NOTE_GAP, Widgets.GROUP_GAP, Widgets.GROUP_LABEL = 4, 10, 14, 22

local BlockMethods = {}

-- Everything below is placed from block.cursor down, so a builder says what comes next
-- and never adds up offsets by hand. The cursor starts where the help text ends.
function BlockMethods:Place(widget, height, gap, x)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", x or 0, self.cursor)
    self.cursor = self.cursor - height - (gap or Widgets.CONTROL_GAP)
    return widget
end

function BlockMethods:Skip(height) self.cursor = self.cursor - height end

-- A muted paragraph at the block's width, measured rather than boxed. variants are the
-- other texts it may be given later, so the room kept fits the longest of them.
function BlockMethods:Note(text, ...)
    local note = Theme:Text(self, text or "", "small", "TEXT_MUTED")
    note:SetJustifyV("TOP")
    note:SetWordWrap(true)
    local height = Widgets:TextHeight(note, self.width, text, ...)
    note:SetHeight(math.max(1, height))
    self:Place(note, height, Widgets.NOTE_GAP)
    if text then self:Index(text) end
    return note
end

-- A titled group of settings inside one block. A group that is not the first gets space above.
function BlockMethods:Group(text)
    if self.cursor < self.top then self:Skip(Widgets.GROUP_GAP) end
    local label = Theme:Text(self, text, "body", "TEXT_TITLE")
    self:Place(label, Widgets.GROUP_LABEL - Widgets.CONTROL_GAP)
    label:SetPoint("RIGHT")
    self:Index(text)
    return label
end

-- Closes the block at the cursor.
function BlockMethods:Finish()
    self:SetBodyHeight(self.top - self.cursor - Widgets.CONTROL_GAP)
end

-- A headerless block of settings for one feature, opened from that feature's row. It
-- carries the same surface as Section (top, SetBodyHeight, height) so a builder can be
-- moved between the two without rewriting where it puts its widgets. The feature's name
-- is already on the row above, so repeating it in a banner would only take space.
-- Gives any frame the block's top-down placement: a tool page stacks its parts the same way
-- a feature's settings do, with the same spacing.
function Widgets:Stack(frame, width, top)
    -- The window is a fixed size, so a block's width is known before it is laid out, and
    -- every paragraph in it can be measured once, here, instead of on every refresh.
    frame.width = width
    frame.top = top or 0
    frame.cursor = frame.top
    frame.searchText = ""
    frame.Index = indexBlock
    for name, method in pairs(BlockMethods) do frame[name] = method end
    return frame
end

function Widgets:SettingsBlock(parent, help, width)
    local block = CreateFrame("Frame", nil, parent)
    -- Opening and closing animates the block's height, so its contents have to be cut off
    -- at whatever is revealed rather than spilling over the rows below it.
    block:SetClipsChildren(true)
    self:Stack(block, width or R.UI.blockWidth, -BLOCK_TOP_GAP)
    if help then
        block.help = block:Note(help)
        block.top = block.cursor
    end
    block.line = Theme:Divider(block)
    function block:SetBodyHeight(height)
        self.height = -self.top + height + BLOCK_BOTTOM_GAP
        self:SetHeight(self.height)
        self.line:SetPoint("BOTTOMLEFT", 0, BLOCK_BOTTOM_GAP * 0.5)
        self.line:SetPoint("BOTTOMRIGHT", 0, BLOCK_BOTTOM_GAP * 0.5)
    end
    return block
end

-- barTop shortens the bar from the top without shortening the list: the feature list runs
-- to the window border and the close button sits over where the upper stepper would be.
function Widgets:Scroll(parent, barTop)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 1)
    scroll:SetScrollChild(child)
    local bar = Theme.scrollBar
    local slider = Theme:ScrollBar(parent)
    slider:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -(bar.trackInset + (barTop or 0)))
    slider:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, bar.trackInset)
    slider:SetMinMaxValues(0, 0)
    -- Continuous like every native bar: a 16 px step made a drag stutter against the glide.
    slider:SetValueStep(1)
    slider:SetScript("OnEnter", function(widget) Theme:ScrollThumbState(widget.thumb, "over") end)
    slider:SetScript("OnLeave", function(widget) Theme:ScrollThumbState(widget.thumb, "normal") end)
    -- Dragging the thumb is direct manipulation and must track the hand exactly; a wheel
    -- tick, an arrow or a filter reset is a jump and gets the glide.
    slider:SetScript("OnValueChanged", function(widget, value)
        scroll:ScrollTo(value, widget.dragging)
        -- The sidebar tracks the view, so every move of the bar reports where it went.
        if scroll.onScroll then scroll.onScroll(value) end
    end)
    slider:SetScript("OnMouseDown", function(widget)
        widget.dragging = true
        Theme:ScrollThumbState(widget.thumb, "down")
    end)
    slider:SetScript("OnMouseUp", function(widget)
        widget.dragging = false
        Theme:ScrollThumbState(widget.thumb, widget:IsMouseOver() and "over" or "normal")
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local _, maxValue = slider:GetMinMaxValues()
        -- Releasing the thumb off the slider can leave the drag flag set; every indirect
        -- move clears it so a stuck flag cannot silently turn the glide off for good.
        slider.dragging = false
        slider:SetValue(math.max(0, math.min(maxValue, slider:GetValue() - delta * 48)))
    end)
    -- The steppers sit outside the track, centred on it, exactly as MinimalScrollBar
    -- anchors Back to the top of the bar and Forward to the bottom.
    local function arrow(asset, point, opposite, gap, direction)
        local button = Theme:ScrollStepper(parent, asset, function()
            local _, maxValue = slider:GetMinMaxValues()
            slider.dragging = false
            slider:SetValue(math.max(0, math.min(maxValue, slider:GetValue() + direction * 80)))
        end)
        button:SetPoint(opposite, slider, point, 0, gap)
        return button
    end
    scroll.up = arrow("scrollUp", "TOP", "BOTTOM", bar.stepperGap, -1)
    scroll.down = arrow("scrollDown", "BOTTOM", "TOP", -bar.stepperGap, 1)
    scroll.child, scroll.slider = child, slider
    scroll.offset, scroll.target = 0, 0
    function scroll:ScrollTo(value, instant)
        self.target = value
        self.pixel = Theme:PixelSize(self)
        if instant then
            self.offset = value
            self:SetVerticalScroll(toPixels(self, value))
            self:SetScript("OnUpdate", nil)
        else
            self:SetScript("OnUpdate", scrollStep)
        end
    end
    function scroll:UpdateExtent(height)
        self.child:SetSize(math.max(1, self:GetWidth()), math.max(1, height))
        local visible = self:GetHeight()
        local maximum = math.max(0, height - visible)
        self.slider:SetMinMaxValues(0, maximum)
        -- Native bars show how much of the list is on screen in the length of the thumb.
        local track = self.slider:GetHeight()
        local extent = math.min(track, math.max(bar.minThumb, track * visible / math.max(1, height)))
        self.slider.thumb.anchor:SetHeight(extent)
        local clamped = math.min(maximum, self.slider:GetValue())
        self.slider:SetValue(clamped)
        -- A list that just got shorter is not a scroll the player asked for.
        self:ScrollTo(clamped, true)
        self.slider:SetShown(maximum > 0)
        self.up:SetShown(maximum > 0)
        self.down:SetShown(maximum > 0)
    end
    slider:SetValue(0)
    return scroll
end

-- One feature: toggle, then its name over a one-line description (PRD 8.2: no setting is a
-- bare label, and a list of names alone had to be hovered row by row to be read), then the
-- slot that reports a warning state, the chevron and undo. The checkbox turns the feature on
-- and off; the rest of the row opens the feature's own settings, because a row that both
-- toggled and expanded had no way to say which a click meant. Hovering shows the long detail.
function Widgets:ModuleRow(parent, module)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Widgets.ROW_HEIGHT)
    row.module = module
    row.hover = Theme:RowHighlight(row)
    -- Every child of the row that takes a mouse of its own would otherwise read as leaving
    -- it: the pointer crossing into the checkbox must not drop the highlight or the detail.
    local function enterRow()
        row.hover:To(1)
        R.UI:ShowDetails(module, row)
    end
    local function leaveRow()
        if row:IsMouseOver() then return end
        row.hover:To(0)
        R.UI:HideDetails()
    end
    row.toggle = Theme:Checkbox(row, CHECK_SIZE, "", function(widget)
        R.UI:SetModuleEnabled(module, widget:GetChecked() == true)
    end)
    row.toggle:SetPoint("LEFT", 6, 0)
    row.toggle:SetScript("OnEnter", enterRow)
    row.toggle:SetScript("OnLeave", leaveRow)
    row.undo = Theme:UndoButton(row, INFO_SIZE + 2, function() R.UI:ResetModule(module) end)
    row.undo:SetPoint("RIGHT", -10, 0)
    -- Undo says what it goes back to, which depends on the layer being edited; the row's
    -- detail is one move away.
    row.undo:SetScript("OnEnter", function()
        row.hover:To(1)
        R.UI:ShowUndoTip(module, row.undo)
    end)
    row.undo:SetScript("OnLeave", leaveRow)
    -- The scrollbar's own arrow, as the loot feed already uses it for the same job. It
    -- keeps its slot whether or not this feature has settings, so the meta column lines up
    -- down the whole list instead of stepping in and out by a chevron's width.
    row.chevron = CreateFrame("Button", nil, row)
    row.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
    row.chevron:SetPoint("RIGHT", row.undo, "LEFT", -8, 0)
    row.chevron.art = Theme:Texture(row.chevron, "scrollDown", "OVERLAY")
    row.chevron.art:SetAllPoints()
    row.chevron:Hide()
    row.chevron:SetScript("OnEnter", enterRow)
    row.chevron:SetScript("OnLeave", leaveRow)
    row.chevron:SetScript("OnClick", function() R.UI:ToggleExpanded(module.id) end)
    -- Sized to its own text, so a row without a warning gives the description the room.
    row.meta = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.meta:SetPoint("RIGHT", row.chevron, "LEFT", -10, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetWordWrap(false)
    row.name = Theme:Text(row, "", "body", "TEXT_BODY")
    row.name:SetPoint("TOPLEFT", row.toggle, "TOPRIGHT", TEXT_GAP, NAME_Y)
    row.name:SetWordWrap(false)
    row.desc = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -DESC_GAP)
    row.desc:SetWordWrap(false)
    function row:FitText()
        local limit = self.meta:GetText() ~= "" and self.meta or self.chevron
        self.name:SetPoint("RIGHT", limit, "LEFT", -TEXT_GAP, 0)
        self.desc:SetPoint("RIGHT", limit, "LEFT", -TEXT_GAP, 0)
    end
    row:SetScript("OnEnter", enterRow)
    row:SetScript("OnLeave", leaveRow)
    row:SetScript("OnClick", function() R.UI:ToggleExpanded(module.id) end)
    return row
end
