local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")
local Widgets = {}
R.UI.Widgets = Widgets

local INPUT_HEIGHT, INFO_SIZE, CHECK_SIZE = 26, 18, 26
Widgets.ROW_HEIGHT = 34

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

function Widgets:Scroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 1)
    scroll:SetScrollChild(child)
    local bar = Theme.scrollBar
    local slider = Theme:ScrollBar(parent)
    slider:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -bar.trackInset)
    slider:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, bar.trackInset)
    slider:SetMinMaxValues(0, 0)
    -- Continuous like every native bar: a 16 px step made a drag stutter against the glide.
    slider:SetValueStep(1)
    slider:SetScript("OnEnter", function(widget) Theme:ScrollThumbState(widget.thumb, "over") end)
    slider:SetScript("OnLeave", function(widget) Theme:ScrollThumbState(widget.thumb, "normal") end)
    -- Dragging the thumb is direct manipulation and must track the hand exactly; a wheel
    -- tick, an arrow or a filter reset is a jump and gets the glide.
    slider:SetScript("OnValueChanged", function(widget, value) scroll:ScrollTo(value, widget.dragging) end)
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

-- One feature on one line: toggle, name, the slot that reports a warning state, and undo.
-- The whole row is the click target, so the checkbox takes no mouse of its own and the
-- pointer never falls into a gap. Hovering the row is what shows the detail, so there is
-- neither a description line nor an info icon to hunt for.
function Widgets:ModuleRow(parent, module)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Widgets.ROW_HEIGHT)
    row.module = module
    row.hover = Theme:RowHighlight(row)
    row.toggle = Theme:Checkbox(row, CHECK_SIZE, "", function(widget)
        R.UI:SetModuleEnabled(module, widget:GetChecked() == true)
    end)
    row.toggle:EnableMouse(false)
    row.toggle:SetPoint("LEFT", 6, 0)
    row.undo = Theme:UndoButton(row, INFO_SIZE + 2, function() R.UI:ResetModule(module) end)
    row.undo:SetPoint("RIGHT", -10, 0)
    -- Undo sits inside the row, so entering it must not read as leaving the row.
    row.undo:SetScript("OnEnter", function() row.hover:To(1) end)
    row.undo:SetScript("OnLeave", function()
        if not row:IsMouseOver() then row.hover:To(0) end
    end)
    row.meta = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.meta:SetPoint("RIGHT", row.undo, "LEFT", -10, 0)
    row.meta:SetWidth(180)
    row.meta:SetJustifyH("RIGHT")
    row.name = Theme:Text(row, "", "body", "TEXT_BODY")
    row.name:SetPoint("LEFT", row.toggle, "RIGHT", 8, 0)
    row:SetScript("OnEnter", function(widget)
        widget.hover:To(1)
        R.UI:ShowDetails(module, widget)
    end)
    row:SetScript("OnLeave", function(widget)
        widget.hover:To(0)
        R.UI:HideDetails()
    end)
    row:SetScript("OnClick", function(widget)
        if not widget.toggle:IsEnabled() then return end
        R.UI:SetModuleEnabled(module, not widget.toggle:GetChecked())
    end)
    return row
end
