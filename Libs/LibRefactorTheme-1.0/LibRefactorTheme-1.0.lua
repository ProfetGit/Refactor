local Theme = LibStub:NewLibrary("LibRefactorTheme-1.0", 9)
if not Theme then return end

local unpack = unpack
Theme.colors = {
    PANEL_BG = { 0.065, 0.051, 0.041, 0.98 },
    SURFACE = { 0.105, 0.086, 0.068, 0.98 },
    ROW_BG = { 0.145, 0.120, 0.094, 0.92 },
    BORDER_BRONZE = { 0.48, 0.34, 0.20, 1 },
    ACCENT_COPPER = { 0.78, 0.54, 0.30, 1 },
    TEXT_TITLE = { 0.91, 0.76, 0.49, 1 },
    TEXT_BODY = { 0.89, 0.84, 0.73, 1 },
    TEXT_MUTED = { 0.66, 0.62, 0.55, 1 },
    TEXT_HIGHLIGHT = { 1, 0.98, 0.94, 1 },
    TEXT_ACTIVE = { 0.90, 0.94, 0.80, 1 },
    TEXT_WARNING = { 1, 0.63, 0.35, 1 },
    HIGHLIGHT = { 0.91, 0.75, 0.48, 0.20 },
    RING_SHADOW = { 0, 0, 0, 0.45 },
    RING_SHADOW_SOFT = { 0, 0, 0, 0.16 },
    RING_TRACK = { 0.28, 0.24, 0.19, 0.85 },
    RING_FILL = { 0.85, 0.70, 0.42, 1 },
    RING_LAST = { 1, 0.86, 0.36, 1 },
    RING_DONE = { 0.43, 0.82, 0.40, 1 },
    QUEST_VALUE = { 1, 1, 1, 1 },
    QUEST_TOTAL = { 0.90, 0.90, 0.86, 1 },
    TEXT_LAST = { 1, 0.86, 0.36, 1 },
    PLATE_DIM = { 0, 0, 0, 0.55 },
}
-- Shared immutable gradient endpoints; allocated once, never during progress updates.
Theme.ringShadeBottom = CreateColor(0.55, 0.55, 0.55, 1)
Theme.ringShadeTop = CreateColor(1, 1, 1, 1)
Theme.fonts = { title = "GameFontNormalLarge", body = "GameFontNormal", small = "GameFontNormalSmall",
    editLabel = "GameFontHighlightLarge" }

-- The window border is one of Blizzard's NineSliceLayouts (12.1.0 NineSliceLayouts.lua),
-- applied by NineSliceUtil so every piece takes its size from the atlas. "Dialog" is the
-- DiamondMetal frame every Retail dialog wears; "GenericMetal" and "SimplePanelTemplate"
-- are the other window-sized kits.
Theme.panelLayout = "Dialog"

-- Verified in Blizzard's 12.1.0 UI source: ThreeSliceButtonMixin and MinimalScrollBar.
-- Never fall back to legacy panel art.
Theme.assets = {
    panelFill = { atlas = "ui-frame-dragonflight-backgroundtile", fallback = "PANEL_BG" },
    header = { atlas = "dragonriding-talents-line", fallback = "BORDER_BRONZE" },
    -- UIPanelButtonTemplate's own kit (ThreeSliceButtonMixin, atlasName "128-RedButton"). The
    -- caps are 114 and 292 px wide at 128 px tall, so they are scaled by height, never squashed.
    buttonLeft = { atlas = "128-RedButton-Left", fallback = "ROW_BG" },
    buttonCenter = { atlas = "_128-RedButton-Center", fallback = "ROW_BG" },
    buttonRight = { atlas = "128-RedButton-Right", fallback = "ROW_BG" },
    buttonLeftPressed = { atlas = "128-RedButton-Left-Pressed", fallback = "SURFACE" },
    buttonCenterPressed = { atlas = "_128-RedButton-Center-Pressed", fallback = "SURFACE" },
    buttonRightPressed = { atlas = "128-RedButton-Right-Pressed", fallback = "SURFACE" },
    buttonLeftDisabled = { atlas = "128-RedButton-Left-Disabled", fallback = "SURFACE" },
    buttonCenterDisabled = { atlas = "_128-RedButton-Center-Disabled", fallback = "SURFACE" },
    buttonRightDisabled = { atlas = "128-RedButton-Right-Disabled", fallback = "SURFACE" },
    buttonHighlight = { atlas = "128-RedButton-Highlight", fallback = "HIGHLIGHT" },
    -- UIPanelCloseButtonNoScripts, SettingsCategoryListButtonMixin, MinimalTabTemplate,
    -- InputBoxVisualTemplate, SearchBoxTemplate, SettingsList and MinimalCheckboxArtTemplate,
    -- all read from the 12.1.0 UI source.
    closeNormal = { atlas = "RedButton-Exit", fallback = "ACCENT_COPPER" },
    closePressed = { atlas = "RedButton-Exit-Pressed", fallback = "BORDER_BRONZE" },
    closeHighlight = { atlas = "RedButton-Highlight", fallback = "HIGHLIGHT" },
    listActive = { atlas = "Options_List_Active", fallback = "HIGHLIGHT" },
    listHover = { atlas = "Options_List_Hover", fallback = "HIGHLIGHT" },
    tabLeft = { atlas = "Options_Tab_Left", fallback = "SURFACE" },
    tabMiddle = { atlas = "Options_Tab_Middle", fallback = "SURFACE" },
    tabRight = { atlas = "Options_Tab_Right", fallback = "SURFACE" },
    tabActiveLeft = { atlas = "Options_Tab_Active_Left", fallback = "ROW_BG" },
    tabActiveMiddle = { atlas = "Options_Tab_Active_Middle", fallback = "ROW_BG" },
    tabActiveRight = { atlas = "Options_Tab_Active_Right", fallback = "ROW_BG" },
    inputLeft = { atlas = "common-search-border-left", fallback = "SURFACE" },
    inputMiddle = { atlas = "common-search-border-middle", fallback = "SURFACE" },
    inputRight = { atlas = "common-search-border-right", fallback = "SURFACE" },
    searchIcon = { atlas = "common-search-magnifyingglass", fallback = "TEXT_MUTED" },
    rowDivider = { atlas = "Options_HorizontalDivider", fallback = "BORDER_BRONZE" },
    -- Interface\Common\help-i, the "i" Blizzard's HelpPlate and Communities frames use.
    infoIcon = { file = 616343 },
    undoIcon = { atlas = "talents-button-undo", fallback = "ACCENT_COPPER" },
    -- PanelResizeButtonTemplate's grabber, the same one on every resizable Blizzard panel.
    resizeGrip = { file = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" },
    resizeGripPressed = { file = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down" },
    resizeGripHighlight = { file = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight" },
    -- MinimalScrollBar.xml stacks three pieces per bar: a cap at each end at its own atlas
    -- size and a middle stretched between them. One stretched middle on its own is what
    -- squares off the ends. Track caps come from the full-size kit and the thumb from the
    -- small kit, which is the pairing Blizzard's own template uses.
    scrollTrackTop = { atlas = "minimal-scrollbar-track-top", fallback = "SURFACE" },
    scrollTrackMiddle = { atlas = "!minimal-scrollbar-track-middle", fallback = "SURFACE" },
    scrollTrackBottom = { atlas = "minimal-scrollbar-track-bottom", fallback = "SURFACE" },
    scrollThumbTop = { atlas = "minimal-scrollbar-small-thumb-top", fallback = "ACCENT_COPPER" },
    scrollThumbMiddle = { atlas = "minimal-scrollbar-small-thumb-middle", fallback = "ACCENT_COPPER" },
    scrollThumbBottom = { atlas = "minimal-scrollbar-small-thumb-bottom", fallback = "ACCENT_COPPER" },
    scrollThumbTopOver = { atlas = "minimal-scrollbar-small-thumb-top-over", fallback = "HIGHLIGHT" },
    scrollThumbMiddleOver = { atlas = "minimal-scrollbar-small-thumb-middle-over", fallback = "HIGHLIGHT" },
    scrollThumbBottomOver = { atlas = "minimal-scrollbar-small-thumb-bottom-over", fallback = "HIGHLIGHT" },
    scrollThumbTopDown = { atlas = "minimal-scrollbar-small-thumb-top-down", fallback = "BORDER_BRONZE" },
    scrollThumbMiddleDown = { atlas = "minimal-scrollbar-small-thumb-middle-down", fallback = "BORDER_BRONZE" },
    scrollThumbBottomDown = { atlas = "minimal-scrollbar-small-thumb-bottom-down", fallback = "BORDER_BRONZE" },
    scrollUp = { atlas = "minimal-scrollbar-arrow-top", fallback = "ACCENT_COPPER" },
    scrollUpOver = { atlas = "minimal-scrollbar-arrow-top-over", fallback = "HIGHLIGHT" },
    scrollUpDown = { atlas = "minimal-scrollbar-arrow-top-down", fallback = "BORDER_BRONZE" },
    scrollDown = { atlas = "minimal-scrollbar-arrow-bottom", fallback = "ACCENT_COPPER" },
    scrollDownOver = { atlas = "minimal-scrollbar-arrow-bottom-over", fallback = "HIGHLIGHT" },
    scrollDownDown = { atlas = "minimal-scrollbar-arrow-bottom-down", fallback = "BORDER_BRONZE" },
    -- Objective atlases selected in TextureAtlasViewer on the installed client.
    questRing = { file = "Interface\\AddOns\\Refactor\\Media\\RefactorRing.tga" },
    questIconKill = { atlas = "Crosshair_Attack_48", fallback = "TEXT_MUTED" },
    questIconItem = { atlas = "Crosshair_buy_48", fallback = "TEXT_MUTED" },
    questIconOther = { atlas = "QuestNormal", fallback = "TEXT_MUTED" },
    questCheck = { atlas = "common-icon-checkmark", fallback = "RING_DONE" },
    checkboxBox = { atlas = "checkbox-minimal", fallback = "SURFACE" },
    checkboxTick = { atlas = "checkmark-minimal", fallback = "RING_DONE" },
    checkboxTickDisabled = { atlas = "checkmark-minimal-disabled", fallback = "TEXT_MUTED" },
    checkboxHighlight = { atlas = "checkbox-minimal", fallback = "HIGHLIGHT" },
    minimapBorder = { file = 136430 },
    minimapHighlight = { file = 136477 },
    addonIcon = { file = "Interface\\AddOns\\Refactor\\Media\\RefactorIcon.tga" },
    -- Verified in the installed client's atlas list and file index (Tools MCP, 12.1.0).
    toastBorder = { atlas = "loottoast-itemborder-white", fallback = "BORDER_BRONZE" },
    toastGold = { file = 237618 },
}

-- Blizzard's Edit Mode selection nine-slice. EditModeSystemSelectionLayout is a local in
-- EditModeSystemTemplates.lua, so the same table is repeated here and handed to Blizzard's
-- own NineSliceUtil with the same two texture kits. Verified atlases, 12.1.0.
Theme.editModeLayout = {
    TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
    TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
    BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
    BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
    TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
    BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
    LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
    RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
    Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
Theme.editModeKits = { highlight = "editmode-actionbar-highlight", selected = "editmode-actionbar-selected" }
Theme.missingAtlases = {}

function Theme:SetAsset(key, asset)
    assert(self.assets[key], "Unknown theme asset")
    assert(type(asset) == "table", "Theme assets must be tables")
    self.assets[key] = asset
end

function Theme:SetColor(key, color)
    assert(self.colors[key], "Unknown theme color")
    self.colors[key] = color
end

function Theme:Color(region, token, text)
    if text then region:SetTextColor(unpack(self.colors[token]))
    else region:SetVertexColor(unpack(self.colors[token])) end
end

-- "ff" plus six hex digits, for text markup that cannot take a colour object.
function Theme:Hex(token)
    local color = self.colors[token]
    return string.format("ff%02x%02x%02x", math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
end

function Theme:ApplyAsset(texture, key)
    local asset = self.assets[key]
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, 1)
    if asset.file then
        texture:SetTexture(asset.file)
        if asset.texcoords then texture:SetTexCoord(unpack(asset.texcoords)) end
    elseif asset.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(asset.atlas) then
        texture:SetAtlas(asset.atlas, false)
    else
        if asset.atlas then self.missingAtlases[asset.atlas] = true end
        texture:SetColorTexture(unpack(self.colors[asset.fallback or "SURFACE"]))
    end
    if asset.tint then self:Color(texture, asset.tint) end
end

function Theme:Texture(parent, key, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    self:ApplyAsset(texture, key)
    return texture
end

function Theme:Fill(parent, token, layer)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(unpack(self.colors[token]))
    return texture
end

local FLAT_BORDER_SIDES = {
    { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
}

-- One-pixel bronze rule on each side: the border for frames too small for corner art,
-- and the border everywhere when the client has no NineSliceUtil.
function Theme:FlatBorder(frame)
    for _, side in ipairs(FLAT_BORDER_SIDES) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(unpack(self.colors.BORDER_BRONZE))
        line:SetPoint(side[1])
        line:SetPoint(side[2])
        if side[3] then line:SetHeight(1) else line:SetWidth(1) end
    end
end

-- Window-sized frames wear a Blizzard nine-slice; NineSliceUtil sizes every piece from its
-- atlas, which is what hand-placed pieces got wrong. Compact frames (a toast, a one-line
-- readout) cannot host 64 px corners and take the flat border instead.
local NINE_SLICE_INSET, FLAT_INSET = 10, 1

function Theme:Panel(frame, compact)
    local nineSlice = not compact and NineSliceUtil and NineSliceUtil.GetLayout
        and NineSliceUtil.GetLayout(self.panelLayout)
    -- The nine-slice edges are drawn inside the frame rect, so both backgrounds stop short
    -- of it; filling to the edge makes the tile spill over the bevel at the corners.
    local inset = nineSlice and NINE_SLICE_INSET or FLAT_INSET
    local base = self:Fill(frame, "PANEL_BG")
    base:ClearAllPoints()
    base:SetPoint("TOPLEFT", inset, -inset)
    base:SetPoint("BOTTOMRIGHT", -inset, inset)
    local fill = self:Texture(frame, "panelFill", "BACKGROUND")
    fill:SetPoint("TOPLEFT", inset, -inset)
    fill:SetPoint("BOTTOMRIGHT", -inset, inset)
    fill:SetAlpha(0.38)
    if nineSlice then
        NineSliceUtil.ApplyLayoutByName(frame, self.panelLayout)
        return
    end
    self:FlatBorder(frame)
end

function Theme:Text(parent, text, style, token)
    local label = parent:CreateFontString(nil, "OVERLAY", self.fonts[style or "body"])
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    self:Color(label, token or "TEXT_BODY", true)
    return label
end

local BUTTON_HEIGHT, FALLBACK_CAP = 22, 8
local BUTTON_PARTS = { "Left", "Center", "Right" }

function Theme:AtlasInfo(key)
    local asset = self.assets[key]
    if asset and asset.atlas and C_Texture and C_Texture.GetAtlasInfo then
        return C_Texture.GetAtlasInfo(asset.atlas)
    end
end

-- Cap widths the way ThreeSliceButtonMixin:UpdateScale computes them: each cap keeps its
-- atlas aspect at the button height, and only when the two caps together overflow the
-- button is width taken off their inner edges. Returns left width, right width and the
-- fraction of each cap that survives, so the caller can trim the texture coordinates.
function Theme:SliceWidths(width, height, leftInfo, rightInfo)
    if not leftInfo or not rightInfo or not leftInfo.height or leftInfo.height <= 0 then
        return FALLBACK_CAP, FALLBACK_CAP, 1, 1
    end
    local scale = height / leftInfo.height
    local left, right = leftInfo.width * scale, rightInfo.width * scale
    local extra = left + right - width
    if extra <= 0 then return left, right, 1, 1 end
    local newLeft, newRight = left, right
    if left - extra > right then
        newLeft = left - extra
    elseif right - extra > left then
        newRight = right - extra
    else
        if left ~= right then
            extra = extra - math.abs(left - right)
            newLeft = math.min(left, right)
            newRight = newLeft
        end
        newLeft = newLeft - extra / 2
        newRight = newRight - extra / 2
    end
    return newLeft, newRight, newLeft / left, newRight / right
end

function Theme:ButtonState(button, state)
    local suffix = state or ""
    for _, part in ipairs(BUTTON_PARTS) do
        self:ApplyAsset(button.art[part], "button" .. part .. suffix)
    end
    local leftWidth, rightWidth, leftKept, rightKept = self:SliceWidths(button.width, button.height,
        self:AtlasInfo("buttonLeft" .. suffix), self:AtlasInfo("buttonRight" .. suffix))
    button.art.Left:SetWidth(leftWidth)
    button.art.Right:SetWidth(rightWidth)
    if leftKept < 1 then button.art.Left:SetTexCoord(0, leftKept, 0, 1) end
    if rightKept < 1 then button.art.Right:SetTexCoord(1 - rightKept, 1, 0, 1) end
    self:Color(button.label, suffix == "Disabled" and "TEXT_MUTED" or "TEXT_TITLE", true)
end

-- The red three-slice is for one thing only: a click that performs an action or writes a
-- value now (Save, Create, Import, Assign, Delete, Turn mine off, a value cycler). Never
-- for navigation (sidebar rows, tabs), never to display a state, never as an icon holder.
-- Close is CloseButton, resize is ResizeGrip, details are InfoIcon.
function Theme:Button(parent, width, text, callback, height)
    local button = CreateFrame("Button", nil, parent)
    button.width, button.height = width, height or BUTTON_HEIGHT
    button:SetSize(button.width, button.height)
    button.art = {}
    for _, part in ipairs(BUTTON_PARTS) do
        button.art[part] = self:Texture(button, "button" .. part, "BACKGROUND")
    end
    button.art.Left:SetPoint("TOPLEFT")
    button.art.Left:SetPoint("BOTTOMLEFT")
    button.art.Right:SetPoint("TOPRIGHT")
    button.art.Right:SetPoint("BOTTOMRIGHT")
    button.art.Center:SetPoint("TOPLEFT", button.art.Left, "TOPRIGHT")
    button.art.Center:SetPoint("BOTTOMRIGHT", button.art.Right, "BOTTOMLEFT")
    button.label = self:Text(button, text)
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetWidth(width - 16)
    button.label:SetJustifyH("CENTER")
    local highlight = self:Texture(button, "buttonHighlight", "HIGHLIGHT")
    highlight:SetAllPoints()
    button:SetHighlightTexture(highlight)
    button:SetScript("OnClick", callback)
    button:SetScript("OnMouseDown", function(widget)
        if widget:IsEnabled() then self:ButtonState(widget, "Pressed") end
    end)
    button:SetScript("OnMouseUp", function(widget)
        self:ButtonState(widget, widget:IsEnabled() and "" or "Disabled")
    end)
    button:SetScript("OnEnable", function(widget) self:ButtonState(widget) end)
    button:SetScript("OnDisable", function(widget) self:ButtonState(widget, "Disabled") end)
    self:ButtonState(button)
    return button
end

-- The X every Retail panel closes with. No text, no red bar.
function Theme:CloseButton(parent, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)
    button.art = self:Texture(button, "closeNormal", "ARTWORK")
    button.art:SetAllPoints()
    local highlight = self:Texture(button, "closeHighlight", "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    button:SetHighlightTexture(highlight)
    button:SetScript("OnMouseDown", function(widget) self:ApplyAsset(widget.art, "closePressed") end)
    button:SetScript("OnMouseUp", function(widget) self:ApplyAsset(widget.art, "closeNormal") end)
    button:SetScript("OnClick", callback)
    return button
end

-- A sidebar row in the Settings panel's own style: text, a hover wash, a gold bar when
-- selected. No button art, because choosing a page is navigation, not an action.
local MIN_FADE = 0.01

-- A fade that can be reversed mid-flight. An Alpha animation always starts from the value
-- it was given, so an interrupted fade would snap before easing back; reading the smooth
-- progress gives the alpha actually on screen, and the new leg starts there with its
-- duration cut to the distance left. Crossing a list quickly therefore never flickers.
function Theme:Fader(region, fadeIn, fadeOut)
    local fader = { region = region, fadeIn = fadeIn, fadeOut = fadeOut, resting = 0 }
    region:SetAlpha(0)
    fader.group = region:CreateAnimationGroup()
    fader.group:SetToFinalAlpha(true)
    fader.anim = fader.group:CreateAnimation("Alpha")
    fader.group:SetScript("OnFinished", function() fader.resting = fader.to end)

    function fader:Current()
        if self.anim:IsPlaying() then
            return self.from + (self.to - self.from) * self.anim:GetSmoothProgress()
        end
        return self.resting
    end

    function fader:To(target)
        local current = self:Current()
        self.group:Stop()
        self.region:SetAlpha(current)
        self.resting = current
        if current == target then return end
        local full = target > current and self.fadeIn or self.fadeOut
        self.from, self.to = current, target
        self.anim:SetFromAlpha(current)
        self.anim:SetToAlpha(target)
        self.anim:SetDuration(math.max(MIN_FADE, full * math.abs(target - current)))
        self.anim:SetSmoothing(target > current and "OUT" or "IN")
        self.group:Play()
    end

    function fader:Snap(alpha)
        self.group:Stop()
        self.resting = alpha
        self.region:SetAlpha(alpha)
    end

    return fader
end

local HOVER_IN, HOVER_OUT = 0.08, 0.13

function Theme:ListButton(parent, width, height, text, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.selection = self:Texture(button, "listActive", "BACKGROUND")
    button.selection:SetAllPoints()
    button.selection:Hide()
    button.hover = self:Texture(button, "listHover", "BACKGROUND")
    button.hover:SetAllPoints()
    button.hoverFade = self:Fader(button.hover, HOVER_IN, HOVER_OUT)
    button.label = self:Text(button, text, "body", "TEXT_BODY")
    button.label:SetPoint("LEFT", 12, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function(widget)
        if not widget.selected then widget.hoverFade:To(1) end
    end)
    button:SetScript("OnLeave", function(widget) widget.hoverFade:To(0) end)
    self:ListButtonState(button, false)
    return button
end

function Theme:ListButtonState(button, selected, tone)
    button.selected = selected == true
    button.selection:SetShown(button.selected)
    -- Selection wins outright: a fade under the active row would read as a stuck highlight.
    if button.selected then button.hoverFade:Snap(0) end
    self:Color(button.label, button.selected and "TEXT_HIGHLIGHT" or tone or "TEXT_BODY", true)
end

local TAB_HEIGHT, TAB_ACTIVE_HEIGHT, TAB_CAP, TAB_PAD = 23, 26, 7, 40
local TAB_PARTS = { "Left", "Middle", "Right" }

-- MinimalTabTemplate: the selected tab stands 3 px taller and reads in white.
function Theme:Tab(parent, text, callback)
    local tab = CreateFrame("Button", nil, parent)
    tab.art = {}
    for _, part in ipairs(TAB_PARTS) do
        tab.art[part] = self:Texture(tab, "tab" .. part, "BACKGROUND")
    end
    tab.art.Left:SetPoint("BOTTOMLEFT")
    tab.art.Right:SetPoint("BOTTOMRIGHT")
    tab.art.Middle:SetPoint("BOTTOMLEFT", tab.art.Left, "BOTTOMRIGHT")
    tab.art.Middle:SetPoint("BOTTOMRIGHT", tab.art.Right, "BOTTOMLEFT")
    tab.label = self:Text(tab, text, "small", "TEXT_TITLE")
    tab.label:SetJustifyH("CENTER")
    tab:SetSize(tab.label:GetStringWidth() + TAB_PAD, TAB_ACTIVE_HEIGHT)
    tab:SetScript("OnClick", callback)
    tab:SetScript("OnEnter", function(widget)
        if not widget.selected then self:Color(widget.label, "TEXT_HIGHLIGHT", true) end
    end)
    tab:SetScript("OnLeave", function(widget)
        if not widget.selected then self:Color(widget.label, "TEXT_TITLE", true) end
    end)
    self:TabState(tab, false)
    return tab
end

function Theme:TabState(tab, selected)
    tab.selected = selected == true
    local prefix = tab.selected and "tabActive" or "tab"
    local height = tab.selected and TAB_ACTIVE_HEIGHT or TAB_HEIGHT
    for _, part in ipairs(TAB_PARTS) do
        self:ApplyAsset(tab.art[part], prefix .. part)
        tab.art[part]:SetHeight(height)
    end
    tab.art.Left:SetWidth(TAB_CAP)
    tab.art.Right:SetWidth(TAB_CAP)
    tab.label:ClearAllPoints()
    tab.label:SetPoint("BOTTOM", 0, tab.selected and 7 or 5)
    self:Color(tab.label, tab.selected and "TEXT_HIGHLIGHT" or "TEXT_TITLE", true)
end

-- InputBoxVisualTemplate's border, sized from the box height (the art is 16 by 40).
function Theme:InputBorder(frame, height)
    local cap = math.floor(height * 0.4 + 0.5)
    local left = self:Texture(frame, "inputLeft", "BACKGROUND")
    left:SetSize(cap, height)
    left:SetPoint("LEFT")
    local right = self:Texture(frame, "inputRight", "BACKGROUND")
    right:SetSize(cap, height)
    right:SetPoint("RIGHT")
    local middle = self:Texture(frame, "inputMiddle", "BACKGROUND")
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end

-- The one-pixel rule Blizzard's SettingsList draws between rows.
function Theme:Divider(parent, layer)
    local line = self:Texture(parent, "rowDivider", layer or "ARTWORK")
    line:SetHeight(1)
    line:SetAlpha(0.6)
    return line
end

local HEADER_TITLE_HEIGHT, HEADER_HELP_HEIGHT = 26, 32

function Theme:SectionHeader(parent, title, help)
    local header = CreateFrame("Frame", nil, parent)
    header.title = self:Text(header, title, "body", "TEXT_TITLE")
    header.title:SetPoint("TOPLEFT")
    header.line = self:Divider(header)
    header.line:SetPoint("TOPLEFT", 0, -20)
    header.line:SetPoint("RIGHT")
    header.height = HEADER_TITLE_HEIGHT
    if help then
        header.help = self:Text(header, help, "small", "TEXT_MUTED")
        header.help:SetPoint("TOPLEFT", 0, -HEADER_TITLE_HEIGHT)
        header.help:SetPoint("RIGHT")
        header.help:SetHeight(HEADER_HELP_HEIGHT - 4)
        header.help:SetJustifyV("TOP")
        header.height = header.height + HEADER_HELP_HEIGHT
    end
    header:SetHeight(header.height)
    return header
end

-- Hover target, not a button: nothing happens on click, the detail lives in the tooltip.
function Theme:InfoIcon(parent, size)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(size, size)
    icon:EnableMouse(true)
    icon.art = self:Texture(icon, "infoIcon", "ARTWORK")
    icon.art:SetAllPoints()
    icon.art:SetAlpha(0.75)
    icon:SetScript("OnEnter", function(widget)
        widget.art:SetAlpha(1)
        if widget.onEnter then widget.onEnter(widget) end
    end)
    icon:SetScript("OnLeave", function(widget)
        widget.art:SetAlpha(0.75)
        if widget.onLeave then widget.onLeave(widget) end
    end)
    return icon
end

-- Icon-only button that puts a value back to its default. Shown only while there is
-- something to undo, so the row reads clean at rest.
function Theme:UndoButton(parent, size, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.art = self:Texture(button, "undoIcon", "ARTWORK")
    button.art:SetAllPoints()
    local highlight = self:Texture(button, "undoIcon", "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    button:SetHighlightTexture(highlight)
    button:SetScript("OnClick", callback)
    button:Hide()
    return button
end

-- MinimalScrollBar, 12.1.0: an 8 px bar, 8 px caps, a 17x11 stepper at each end and a
-- track inset by 19 so the steppers clear it. The thumb never goes below 23 px or it
-- cannot be grabbed.
local BAR_WIDTH, BAR_CAP, MIN_THUMB = 8, 8, 23
local STEPPER_WIDTH, STEPPER_HEIGHT, STEPPER_GAP = 17, 11, 8
Theme.scrollBar = { width = BAR_WIDTH, minThumb = MIN_THUMB,
    stepperGap = STEPPER_GAP, trackInset = STEPPER_HEIGHT + STEPPER_GAP }

local THUMB_STATES = { normal = "", over = "Over", down = "Down" }

local function threeSlice(parent, prefix, layer)
    local slice = { prefix = prefix }
    slice.top = Theme:Texture(parent, prefix .. "Top", layer)
    slice.top:SetSize(BAR_WIDTH, BAR_CAP)
    slice.top:SetPoint("TOPLEFT")
    slice.bottom = Theme:Texture(parent, prefix .. "Bottom", layer)
    slice.bottom:SetSize(BAR_WIDTH, BAR_CAP)
    slice.bottom:SetPoint("BOTTOMLEFT")
    -- Anchored cap to cap: the middle must not run under a rounded cap, or the square
    -- corners of the stretched piece show through the transparent part of the cap.
    slice.middle = Theme:Texture(parent, prefix .. "Middle", layer)
    slice.middle:SetPoint("TOPLEFT", slice.top, "BOTTOMLEFT")
    slice.middle:SetPoint("BOTTOMRIGHT", slice.bottom, "TOPRIGHT")
    return slice
end

function Theme:ScrollThumbState(thumb, state)
    local suffix = THUMB_STATES[state] or ""
    self:ApplyAsset(thumb.slice.top, "scrollThumbTop" .. suffix)
    self:ApplyAsset(thumb.slice.middle, "scrollThumbMiddle" .. suffix)
    self:ApplyAsset(thumb.slice.bottom, "scrollThumbBottom" .. suffix)
end

-- The Slider widget takes a single thumb texture, which cannot be a three-slice. The
-- texture it moves is kept empty and used purely as an anchor: the visible thumb is a
-- frame pinned to it, so the caps ride along with no per-frame work.
function Theme:ScrollBar(parent)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(BAR_WIDTH)
    threeSlice(slider, "scrollTrack", "BACKGROUND")
    local anchor = slider:CreateTexture(nil, "ARTWORK")
    anchor:SetSize(BAR_WIDTH, MIN_THUMB)
    slider:SetThumbTexture(anchor)
    local thumb = CreateFrame("Frame", nil, slider)
    thumb:SetAllPoints(anchor)
    thumb.anchor = anchor
    thumb.slice = threeSlice(thumb, "scrollThumb", "ARTWORK")
    slider.thumb = thumb
    return slider
end

function Theme:ScrollStepper(parent, key, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(STEPPER_WIDTH, STEPPER_HEIGHT)
    for method, suffix in pairs({ SetNormalTexture = "", SetPushedTexture = "Down",
        SetHighlightTexture = "Over" }) do
        local art = self:Texture(button, key .. suffix)
        art:SetAllPoints()
        button[method](button, art)
    end
    button:SetScript("OnClick", onClick)
    return button
end

function Theme:ResizeGrip(parent, onStart, onStop)
    local grip = CreateFrame("Button", nil, parent)
    grip:SetSize(16, 16)
    grip.art = self:Texture(grip, "resizeGrip", "ARTWORK")
    grip.art:SetAllPoints()
    local highlight = self:Texture(grip, "resizeGripHighlight", "HIGHLIGHT")
    highlight:SetAllPoints()
    grip:SetHighlightTexture(highlight)
    grip:SetScript("OnMouseDown", function(widget)
        self:ApplyAsset(widget.art, "resizeGripPressed")
        onStart()
    end)
    grip:SetScript("OnMouseUp", function(widget)
        self:ApplyAsset(widget.art, "resizeGrip")
        onStop()
    end)
    return grip
end

local INDICATOR_SIZE = 18
local ICON_KEYS = { kill = "questIconKill", item = "questIconItem", other = "questIconOther" }

-- Objective indicator: quest type icon (sword for kill, bag for loot) with progress numbers.
-- Progress is carried purely by numbers (e.g. 5/6) and the gold highlight on the last mob,
-- eliminating redundant circular/radial progress bars that clutter nameplates.
function Theme:QuestIndicator(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)

    frame.icon = self:Texture(frame, "questIconOther", "OVERLAY")
    frame.icon:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    frame.icon:SetPoint("CENTER")
    frame.check = self:Texture(frame, "questCheck", "OVERLAY")
    frame.check:SetSize(INDICATOR_SIZE + 2, INDICATOR_SIZE + 2)
    frame.check:SetPoint("CENTER")
    frame.check:Hide()
    -- Two strings, with value anchored in a stationary holder so only the number
    -- animates while "/6" stays completely still without bouncing or shifting.
    local valueHolder = CreateFrame("Frame", nil, frame)
    valueHolder:SetPoint("LEFT", frame, "RIGHT", 4, 0)
    valueHolder:SetSize(10, 16)
    frame.valueHolder = valueHolder

    frame.value = self:Text(valueHolder, "", "body", "QUEST_VALUE")
    frame.value:SetPoint("CENTER", valueHolder, "CENTER", 0, 0)
    frame.value:SetJustifyH("CENTER")
    frame.value:SetSmoothScaling(true)
    frame.total = self:Text(frame, "", "body", "QUEST_TOTAL")
    frame.total:SetPoint("LEFT", valueHolder, "RIGHT", -2, 0)
    frame.total:SetJustifyH("LEFT")
    local fontFile = frame.value:GetFont()
    frame.value:SetFont(fontFile, 16, "OUTLINE")
    frame.total:SetFont(fontFile, 14, "OUTLINE")
    frame.value:SetShadowOffset(1, -1)
    frame.total:SetShadowOffset(1, -1)
    frame.count = frame.value

    -- Calm, elegant: pure soft alpha fade-in on the updated number.
    -- No scaling or geometric transformation, avoiding FontString outline re-rasterization flicker.
    local pop = frame.value:CreateAnimationGroup()
    local fadeAnim = pop:CreateAnimation("Alpha")
    fadeAnim:SetFromAlpha(0.20)
    fadeAnim:SetToAlpha(1)
    fadeAnim:SetDuration(0.25)
    fadeAnim:SetSmoothing("OUT")
    frame.pop = pop

    local fade = frame:CreateAnimationGroup()
    local out = fade:CreateAnimation("Alpha")
    out:SetFromAlpha(1)
    out:SetToAlpha(0)
    out:SetDuration(0.15)
    out:SetStartDelay(0.6)
    fade:SetScript("OnFinished", function() frame:Hide() end)
    frame.fade = fade

    function frame:SetFraction(fraction)
        self.fraction = fraction
    end

    function frame:SetIconKind(kind)
        Theme:ApplyAsset(self.icon, ICON_KEYS[kind] or ICON_KEYS.other)
    end

    function frame:SetIconShown(shown)
        self.icon:SetShown(shown == true)
    end

    function frame:SetProgress(fulfilled, required, lastOne)
        self.fraction = (required and required > 0) and math.min(1, (fulfilled or 0) / required) or 0
        Theme:Color(self.value, lastOne and "TEXT_LAST" or "QUEST_VALUE", true)
    end

    function frame:SetComplete(complete)
        if complete then
            self.fraction = 1
        end
        self.icon:SetShown(not complete)
        self.check:SetShown(complete == true)
    end

    function frame:SetCountText(value, total)
        self.value:SetText(value or "")
        local width = self.value:GetStringWidth()
        if width and width > 0 then
            self.valueHolder:SetWidth(width)
        end
        self.total:SetText(total or "")
    end

    function frame:SetRingShown(shown)
        self.ringShown = shown == true
    end

    function frame:Pop(reduceAnimation)
        if reduceAnimation then
            return
        end
        self.pop:Stop()
        self.pop:Play()
    end

    function frame:FadeOut(reduceAnimation)
        self.fade:Stop()
        if reduceAnimation then
            self:Hide()
            return
        end
        self.fade:Play()
    end

    function frame:ResetIndicator()
        self.pop:Stop()
        self.fade:Stop()
        self:SetAlpha(1)
        self.value:SetAlpha(1)
        self:SetCountText(nil, nil)
        self.fraction = 0
        self.check:Hide()
        self.icon:Show()
        self:ClearAllPoints()
        self:SetParent(nil)
        self:Hide()
    end

    frame:Hide()
    return frame
end

-- Refactor's own overlay, never a change to Blizzard's plate textures or alpha.
function Theme:PlateDim(parent)
    local dim = CreateFrame("Frame", nil, parent)
    dim:SetFrameStrata("BACKGROUND")
    self:Fill(dim, "PLATE_DIM")
    dim:Hide()
    return dim
end

local CHECK_SIZE = 26

-- A real CheckButton wearing the Settings panel's minimal checkbox. An on/off setting
-- should look like every other on/off setting the player has ever seen.
function Theme:Checkbox(parent, width, text, callback)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(CHECK_SIZE, CHECK_SIZE)
    box:SetHitRectInsets(0, -(width or 200) + CHECK_SIZE, 0, 0)
    box.background = self:Texture(box, "checkboxBox", "BACKGROUND")
    box.background:SetAllPoints()
    box.tick = self:Texture(box, "checkboxTick", "ARTWORK")
    box.tick:SetAllPoints()
    box:SetCheckedTexture(box.tick)
    box.tickDisabled = self:Texture(box, "checkboxTickDisabled", "ARTWORK")
    box.tickDisabled:SetAllPoints()
    box:SetDisabledCheckedTexture(box.tickDisabled)
    local highlight = self:Texture(box, "checkboxHighlight", "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    box:SetHighlightTexture(highlight)
    box.label = self:Text(box, text, "body", "TEXT_BODY")
    box.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    box.label:SetWidth((width or 200) - 34)
    box:SetScript("OnClick", callback)
    return box
end

local TOAST_WIDTH, TOAST_HEIGHT, TOAST_ICON = 272, 52, 38
local TOAST_FADE, TOAST_HOLD = 0.15, 3

-- A loot toast: icon with a quality-tinted frame, name, count, and one muted line for the
-- price and its source. Fades only, 150 ms, no bounce (PRD 8.3). The hold is an animation
-- delay, so nothing runs in Lua while a toast is on screen.
function Theme:Toast(parent)
    local toast = CreateFrame("Frame", nil, parent)
    toast:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    toast:SetFrameStrata("HIGH")
    self:Panel(toast, true)
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(TOAST_ICON, TOAST_ICON)
    toast.icon:SetPoint("LEFT", 8, 0)
    toast.border = self:Texture(toast, "toastBorder", "OVERLAY")
    toast.border:SetPoint("TOPLEFT", toast.icon, "TOPLEFT", -4, 4)
    toast.border:SetPoint("BOTTOMRIGHT", toast.icon, "BOTTOMRIGHT", 4, -4)
    toast.name = self:Text(toast, "", "body", "TEXT_BODY")
    toast.name:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, -1)
    toast.name:SetPoint("RIGHT", -12, 0)
    toast.detail = self:Text(toast, "", "small", "TEXT_MUTED")
    toast.detail:SetPoint("BOTTOMLEFT", toast.icon, "BOTTOMRIGHT", 10, 1)
    toast.detail:SetPoint("RIGHT", -12, 0)
    local show = toast:CreateAnimationGroup()
    local fadeIn = show:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(TOAST_FADE)
    toast.show = show
    local hide = toast:CreateAnimationGroup()
    local fadeOut = hide:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(TOAST_HOLD)
    fadeOut:SetDuration(TOAST_FADE)
    hide:SetScript("OnFinished", function()
        toast:Hide()
        if toast.onHidden then toast.onHidden(toast) end
    end)
    toast.hide = hide

    function toast:SetIcon(fileID)
        self.icon:SetTexture(fileID)
    end
    function toast:SetQualityColor(r, g, b)
        self.border:SetVertexColor(r or 1, g or 1, b or 1, 1)
        self.name:SetTextColor(r or 1, g or 1, b or 1, 1)
    end
    function toast:SetLines(name, detail)
        self.name:SetText(name or "")
        self.detail:SetText(detail or "")
    end
    -- Called again for the same item while visible: the hold restarts, nothing flashes.
    function toast:Present()
        self.hide:Stop()
        if not self:IsShown() then
            self:SetAlpha(1)
            self:Show()
            self.show:Stop()
            self.show:Play()
        end
        self.hide:Play()
    end
    function toast:ResetToast()
        self.show:Stop()
        self.hide:Stop()
        self:SetAlpha(1)
        self:SetLines(nil, nil)
        self:SetQualityColor(1, 1, 1)
        self:ClearAllPoints()
        self:Hide()
    end
    toast:Hide()
    return toast
end

-- A stand-in for an Edit Mode system frame. Refactor cannot register a real system without
-- touching secure code, so this is our own frame wearing Blizzard's selection art: the same
-- nine-slice, the same two states, the same drag behaviour. Nothing Blizzard owns is touched.
function Theme:EditModeSelection(parent, labelText)
    local usable = NineSliceUtil and NineSliceUtil.ApplyLayout
    local selection = CreateFrame("Frame", nil, parent, usable and "NineSliceCodeTemplate" or nil)
    selection:SetAllPoints()
    selection:SetFrameStrata("HIGH")
    selection:SetFrameLevel(parent:GetFrameLevel() + 10)
    selection:EnableMouse(true)
    selection:RegisterForDrag("LeftButton")
    if not usable then
        self:Panel(selection)
    end
    selection.label = selection:CreateFontString(nil, "OVERLAY", self.fonts.editLabel)
    selection.label:SetPoint("CENTER")
    selection.label:SetText(labelText or "")

    -- Blizzard reapplies the layout only when the kit actually changes, and so does this.
    function selection:SetSelected(selected)
        local kit = selected and Theme.editModeKits.selected or Theme.editModeKits.highlight
        if usable and self.kit ~= kit then
            self.kit = kit
            NineSliceUtil.ApplyLayout(self, Theme.editModeLayout, kit)
        end
    end

    selection:SetSelected(false)
    selection:Hide()
    return selection
end

-- Refactor's own button, parented to the minimap but never altering it.
function Theme:MinimapButton(parent, size, inset)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(parent:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button.icon = self:Texture(button, "addonIcon", "ARTWORK")
    button.icon:SetPoint("TOPLEFT", inset, -inset)
    button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    -- Match the Retail border used by BugSack's LibDBIcon; the old path missed a hyphen.
    button.border = self:Texture(button, "minimapBorder", "OVERLAY")
    button.border:SetSize(50, 50)
    button.border:SetPoint("TOPLEFT", 0, 0)
    -- Use the same full-button highlight and default blending as BugSack's LibDBIcon.
    button:SetHighlightTexture(self.assets.minimapHighlight.file)
    return button
end
