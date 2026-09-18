local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")
local Widgets = {}
R.UI.Widgets = Widgets

local INPUT_HEIGHT, INFO_SIZE, CHECK_SIZE = 26, 18, 26
Widgets.ROW_HEIGHT = 58

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
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(10)
    slider:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -16)
    slider:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 16)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(16)
    local track = Theme:Texture(slider, "scrollTrack", "BACKGROUND")
    track:SetAllPoints()
    local thumb = Theme:Texture(slider, "scrollThumb")
    thumb:SetSize(10, 30)
    slider:SetThumbTexture(thumb)
    slider:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local _, maxValue = slider:GetMinMaxValues()
        slider:SetValue(math.max(0, math.min(maxValue, slider:GetValue() - delta * 48)))
    end)
    local function arrow(asset, point, offset, direction)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(18, 14)
        button:SetPoint(point, slider, point, 0, offset)
        local art = Theme:Texture(button, asset)
        art:SetAllPoints()
        button:SetNormalTexture(art)
        button:SetScript("OnClick", function()
            local _, maxValue = slider:GetMinMaxValues()
            slider:SetValue(math.max(0, math.min(maxValue, slider:GetValue() + direction * 80)))
        end)
        return button
    end
    scroll.up = arrow("scrollUp", "TOP", 16, -1)
    scroll.down = arrow("scrollDown", "BOTTOM", -16, 1)
    scroll.child, scroll.slider = child, slider
    function scroll:UpdateExtent(height)
        self.child:SetSize(math.max(1, self:GetWidth()), math.max(1, height))
        local maximum = math.max(0, height - self:GetHeight())
        self.slider:SetMinMaxValues(0, maximum)
        self.slider:SetValue(math.min(maximum, self.slider:GetValue()))
        self.slider:SetShown(maximum > 0)
        self.up:SetShown(maximum > 0)
        self.down:SetShown(maximum > 0)
    end
    slider:SetValue(0)
    return scroll
end

-- One feature: toggle, name, breadcrumb, one-line description, a rule underneath. No box
-- around it. The breadcrumb slot doubles as the place a warning state is reported.
function Widgets:ModuleRow(parent, module)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Widgets.ROW_HEIGHT)
    row.module = module
    row.toggle = Theme:Checkbox(row, CHECK_SIZE, "", function(widget)
        R.UI:SetModuleEnabled(module, widget:GetChecked() == true)
    end)
    row.toggle:SetPoint("TOPLEFT", 6, -8)
    row.undo = Theme:UndoButton(row, INFO_SIZE + 2, function() R.UI:ResetModule(module) end)
    row.undo:SetPoint("TOPRIGHT", -10, -11)
    row.meta = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.meta:SetPoint("RIGHT", row.undo, "LEFT", -10, 0)
    row.meta:SetWidth(180)
    row.meta:SetJustifyH("RIGHT")
    row.name = Theme:Text(row, "", "body", "TEXT_BODY")
    row.name:SetPoint("LEFT", row.toggle, "RIGHT", 8, 0)
    row.info = Theme:InfoIcon(row, INFO_SIZE)
    row.info:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.info.onEnter = function(icon) R.UI:ShowDetails(module, icon) end
    row.info.onLeave = function() R.UI:HideDetails() end
    row.description = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.description:SetPoint("TOPLEFT", 40, -36)
    row.description:SetPoint("RIGHT", -40, 0)
    row.description:SetHeight(16)
    row.description:SetJustifyV("TOP")
    row.divider = Theme:Divider(row)
    row.divider:SetPoint("BOTTOMLEFT")
    row.divider:SetPoint("BOTTOMRIGHT")
    return row
end
