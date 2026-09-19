local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")
local L = R.L
local unpack = unpack

-- Sized so the longest line the module can produce still stops well short of the soft edge
-- the backdrop fades out on. BLEED is how far that smudge reaches past the content.
local HUD_WIDTH, PAD = 200, 12
local BLEED_X, BLEED_Y = 30, 22
-- Every control lives inside the frame's own rect, grip included. A button hanging over the
-- edge would take the mouse away from the HUD, and reaching for it would cancel the hover
-- that made it appear.
local GRIP_Y, RATE_Y, SUB_Y, METER_Y, ICON_Y = -1, -18, -38, -56, -68
local METER_HEIGHT, ICON_SIZE, ICON_GAP = 4, 12, 9
local GRIP_SIZE, DOT_SIZE = 14, 4
local HUD_HEIGHT = 90
-- Muted taupe at half strength, full brightness under the pointer. The art is white.
local ICON_REST, ICON_HOVER = 0.5, 1
local HOVER_FADE = 0.15
-- The chevron art points up as shipped, so up is the expanded state and the collapsed one
-- is the same caret turned over. One half turn, eased out, landing on the angle.
local CHEVRON_FLIP, CHEVRON_SPIN = 180, 0.16
local RADIANS_PER_DEGREE = math.pi / 180

-- The panel slides out from behind the HUD rather than appearing: it starts PANEL_DROP high
-- and eases down. No overshoot anywhere. This is a ledger, not a toy, and a number that
-- bounces before it settles invites you to distrust it.
--
-- No alpha leg either. The money lines carry the client's own coin textures as inline |T|t
-- escapes, and those do not fade with the frame the way a plain glyph does, so a fading
-- panel shows its coins arriving separately from the numbers they belong to.
local PANEL_GAP, PANEL_DROP, PANEL_RISE = -2, 11, 7
local PANEL_SLIDE, PANEL_CLOSE = 0.13, 0.09
-- Long enough that a mis-click cannot wipe a session, short enough not to feel punitive.
local RESET_HOLD = 1
local TOP_ROWS, TOP_ROW_HEIGHT, TOP_ICON = 5, 18, 14
local STAT_ROW_HEIGHT, SEPARATOR_GAP = 17, 9
local STAT_KEYS = { "hudClock", "hudTrend", "hudCoins", "hudBag" }
-- The trend row, the one the player can switch off.
local RATES_ROW = 2
local DEFAULT_POSITION = { point = "TOPLEFT", relativePoint = "CENTER", x = -440, y = 180 }
local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}
local TEXTURE_KEYS = {
    "hudBackdrop", "hudMeterTrack", "hudMeterFill", "hudGrip",
    "hudClock", "hudTrend", "hudCoins", "hudBag",
    "hudReset", "hudPause", "hudSettings", "hudCollapse",
}
R.UI.farmHudTextureKeys = TEXTURE_KEYS
R.UI.farmHudTopRows = TOP_ROWS

local function tooltipLines(anchor, title, body)
    if not GameTooltip then return end
    local r, g, b = unpack(Theme.colors.TEXT_BODY)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(body, r, g, b, true)
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- One shared handler per script rather than a closure per button, so the icon row is built
-- once at enable and costs nothing to show again. A child frame takes the mouse off its
-- parent, so each one re-asserts the hover it is standing inside.
local function iconEnter(button)
    local host = button.host
    button.art:SetAlpha(ICON_HOVER)
    host.hovered = true
    host:UpdateHover()
    tooltipLines(button, button.tipTitle, button.tip)
end

local function iconLeave(button)
    local host = button.host
    host:CancelHold()
    button.art:SetAlpha(button.lit and ICON_HOVER or ICON_REST)
    hideTooltip()
    host:LeaveIfOutside()
end

-- The hold that confirms a reset. No Alpha or Scale animation can drive SetTexCoord, which
-- is the one case rule 13 leaves to OnUpdate, and it clears itself the moment the button is
-- released, left, hidden, or the hold completes.
local function holdUpdate(button, elapsed)
    local host = button.host
    button.held = button.held + elapsed
    if button.held >= RESET_HOLD then
        host:CancelHold()
        if host.onReset then host.onReset() end
        return
    end
    host:ShowHold(button.held / RESET_HOLD)
end

function R.UI:CreateFarmHud(owner)
    if owner.refactorFarmHud then return owner.refactorFarmHud end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(HUD_WIDTH, HUD_HEIGHT)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host:EnableMouse(true)
    host:RegisterForDrag("LeftButton")
    host.owner = owner
    R:OwnFrame(host)

    host.backdrop = Theme:Texture(host, "hudBackdrop", "BACKGROUND")
    host.backdrop:SetPoint("TOPLEFT", -BLEED_X, BLEED_Y)
    host.backdrop:SetPoint("BOTTOMRIGHT", BLEED_X, -BLEED_Y)
    Theme:VerifyFile(host.backdrop, "hudBackdrop")

    local function line(style, token, y)
        local label = Theme:Shadow(Theme:Text(host, "", style, token))
        label:SetPoint("TOPLEFT", PAD, y)
        label:SetPoint("RIGHT", -PAD, 0)
        return label
    end
    -- The one number the HUD exists for, and the one that is never hidden.
    host.rate = line("title", "TEXT_TITLE", RATE_Y)
    host.sub = line("small", "TEXT_MUTED", SUB_Y)

    host.pauseDot = host:CreateTexture(nil, "OVERLAY")
    host.pauseDot:SetSize(DOT_SIZE, DOT_SIZE)
    host.pauseDot:SetPoint("TOPRIGHT", -PAD, RATE_Y - 8)
    host.pauseDot:SetColorTexture(unpack(Theme.colors.TEXT_MUTED))
    host.pauseDot:Hide()

    host.track = Theme:Texture(host, "hudMeterTrack", "ARTWORK")
    host.track:SetPoint("TOPLEFT", PAD, METER_Y)
    host.track:SetPoint("RIGHT", -PAD, 0)
    host.track:SetHeight(METER_HEIGHT)
    Theme:Color(host.track, "HUD_TRACK")
    Theme:VerifyFile(host.track, "hudMeterTrack")
    host.fill = Theme:Texture(host, "hudMeterFill", "OVERLAY")
    host.fill:SetPoint("TOPLEFT", host.track, "TOPLEFT")
    host.fill:SetHeight(METER_HEIGHT)
    Theme:VerifyFile(host.fill, "hudMeterFill")

    host.grip = CreateFrame("Button", nil, host)
    host.grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    host.grip:SetPoint("TOP", 0, GRIP_Y)
    host.grip:RegisterForDrag("LeftButton")
    host.grip.art = Theme:Texture(host.grip, "hudGrip", "OVERLAY")
    host.grip.art:SetAllPoints()
    Theme:Color(host.grip.art, "TEXT_MUTED")
    Theme:VerifyFile(host.grip.art, "hudGrip")
    host.gripFade = Theme:Fader(host.grip, HOVER_FADE, HOVER_FADE)
    host.grip.host = host
    host.grip.tipTitle, host.grip.tip = L.FARM_TIP_GRIP_TITLE, L.FARM_TIP_GRIP
    host.grip:SetScript("OnEnter", function(widget)
        widget.host.hovered = true
        widget.host:UpdateHover()
        tooltipLines(widget, widget.tipTitle, widget.tip)
    end)
    host.grip:SetScript("OnLeave", function(widget)
        hideTooltip()
        widget.host:LeaveIfOutside()
    end)

    -- Every control exists before the first event and is only shown or hidden (rule 11).
    host.icons = {}
    local function icon(key, titleKey, tipKey, onClick)
        local button = CreateFrame("Button", nil, host)
        button:SetSize(ICON_SIZE, ICON_SIZE)
        button.x = PAD + #host.icons * (ICON_SIZE + ICON_GAP)
        button:SetPoint("TOPLEFT", button.x, ICON_Y)
        button.art = Theme:Texture(button, key, "OVERLAY")
        button.art:SetAllPoints()
        Theme:Color(button.art, "TEXT_MUTED")
        button.art:SetAlpha(ICON_REST)
        Theme:VerifyFile(button.art, key)
        button.host, button.assetKey = host, key
        button.tipTitle, button.tip = L[titleKey], L[tipKey]
        button:SetScript("OnEnter", iconEnter)
        button:SetScript("OnLeave", iconLeave)
        if onClick then
            button:RegisterForClicks("LeftButtonUp")
            button:SetScript("OnClick", onClick)
        end
        button.fade = Theme:Fader(button, HOVER_FADE, HOVER_FADE)
        host.icons[#host.icons + 1] = button
        return button
    end

    host.reset = icon("hudReset", "FARM_TIP_RESET_TITLE", "FARM_TIP_RESET")
    -- The only frame in this feature that ever carries an OnUpdate, so the bench has to be
    -- able to see it: zero idle handlers is a release gate, not a code review opinion.
    R:OwnFrame(host.reset)
    -- Press starts the hold, release ends it. No popup and no Blizzard dialog: the meter
    -- filling under the pointer is the confirmation.
    host.reset:SetScript("OnMouseDown", function(button)
        button.held = 0
        button.host:ShowHold(0)
        button:SetScript("OnUpdate", holdUpdate)
    end)
    host.reset:SetScript("OnMouseUp", function(button) button.host:CancelHold() end)

    host.pause = icon("hudPause", "FARM_TIP_PAUSE_TITLE", "FARM_TIP_PAUSE", function(button)
        if button.host.onTogglePause then button.host.onTogglePause() end
    end)
    host.settings = icon("hudSettings", "FARM_TIP_SETTINGS_TITLE", "FARM_TIP_SETTINGS", function(button)
        if button.host.onOpenSettings then button.host.onOpenSettings() end
    end)
    -- Two states and one button. The panel is open or it is not; there is no third,
    -- rate-only state hiding behind a second press, and nothing expands on hover alone.
    host.collapse = icon("hudCollapse", "FARM_TIP_EXPAND_TITLE", "FARM_TIP_EXPAND", function(button)
        R.Settings:SetOption("farmExpand", not button.host:Expanded())
    end)
    -- A Rotation animation ends where it started, so the texture is only pointed at its
    -- destination once the turn finishes and the angle it travelled is released.
    host.spin = host.collapse:CreateAnimationGroup()
    host.spinAnim = host.spin:CreateAnimation("Rotation")
    host.spinAnim:SetDuration(CHEVRON_SPIN)
    host.spinAnim:SetSmoothing("OUT")
    host.spin:SetScript("OnFinished", function()
        host.collapse.art:SetRotation(host.chevronTarget or 0)
    end)

    -- Display only. It takes no mouse, so hovering the HUD stays the whole interaction and
    -- the panel appearing under the pointer can never steal the hover that produced it.
    local expand = CreateFrame("Frame", nil, host)
    expand:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, PANEL_GAP)
    expand:SetWidth(HUD_WIDTH)
    expand:EnableMouse(false)
    -- The HUD's backdrop bleeds well past its bottom edge and the panel slides up through
    -- that bleed on the way in, so the panel is put above it rather than left to the
    -- default child ordering.
    expand:SetFrameLevel(host:GetFrameLevel() + 5)
    host.expand = expand
    expand.backdrop = Theme:Texture(expand, "hudBackdrop", "BACKGROUND")
    expand.backdrop:SetPoint("TOPLEFT", -BLEED_X, BLEED_Y)
    expand.backdrop:SetPoint("BOTTOMRIGHT", BLEED_X, -BLEED_Y)

    -- Rules, not textures: a one pixel line of flat colour is what separates the blocks.
    local function separator()
        local rule = expand:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetColorTexture(unpack(Theme.colors.LOOT_UNDERLINE))
        return rule
    end

    -- Built here and anchored nowhere: a row the player switched off leaves no gap, so the
    -- vertical layout is decided every refresh by LayoutPanel rather than baked in now.
    expand.stats = {}
    for index, key in ipairs(STAT_KEYS) do
        local row = {}
        row.icon = Theme:Texture(expand, key, "OVERLAY")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        Theme:Color(row.icon, "TEXT_MUTED")
        Theme:VerifyFile(row.icon, key)
        row.text = Theme:Shadow(Theme:Text(expand, "", "small", "TEXT_BODY"))
        row.visible = true
        expand.stats[index] = row
    end

    expand.bestRule = separator()
    expand.best = Theme:Shadow(Theme:Text(expand, "", "small", "TEXT_TITLE"))
    expand.topRule = separator()

    expand.rows = {}
    for index = 1, TOP_ROWS do
        local row = CreateFrame("Frame", nil, expand)
        row:SetHeight(TOP_ROW_HEIGHT)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(TOP_ICON, TOP_ICON)
        row.icon:SetPoint("LEFT")
        row.value = Theme:Shadow(Theme:Text(row, "", "small", "TEXT_MUTED"))
        row.value:SetPoint("RIGHT")
        row.value:SetJustifyH("RIGHT")
        row.name = Theme:Shadow(Theme:Text(row, "", "small", "TEXT_BODY"))
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row:Hide()
        expand.rows[index] = row
    end
    expand:Hide()

    -- Opening: slide down out from behind the HUD, easing to a stop. A Translation ends
    -- where it started, so the panel is pointed at its resting anchor only once the group
    -- finishes and the PANEL_DROP it travelled is released.
    local openGroup = expand:CreateAnimationGroup()
    local openSlide = openGroup:CreateAnimation("Translation")
    openSlide:SetOffset(0, -PANEL_DROP)
    openSlide:SetDuration(PANEL_SLIDE)
    openSlide:SetSmoothing("OUT")
    host.panelOpenGroup, host.panelOpenSlide = openGroup, openSlide

    -- Closing is the same move, shorter and upward: leaving costs less than arriving.
    local closeGroup = expand:CreateAnimationGroup()
    local closeRise = closeGroup:CreateAnimation("Translation")
    closeRise:SetOffset(0, PANEL_RISE)
    closeRise:SetDuration(PANEL_CLOSE)
    closeRise:SetSmoothing("IN")
    host.panelCloseGroup, host.panelCloseRise = closeGroup, closeRise

    -- Blizzard's own context menu, and unnamed on purpose: "MENU" display mode and cursor
    -- anchoring both reach the frame's parentKey children, never its global name, so the
    -- addon still writes exactly one global (rule 3).
    host.menu = CreateFrame("Frame", nil, UIParent, "UIDropDownMenuTemplate")

    function host:Opacity()
        local opacity = R.Settings:GetOption("farmOpacity")
        return type(opacity) == "number" and opacity or 1
    end

    function host:Locked()
        return R.Settings:GetOption("farmLocked") == true
    end

    function host:TintBackdrop(texture)
        local colour = Theme.colors.HUD_BG
        texture:SetVertexColor(colour[1], colour[2], colour[3], self:Opacity())
    end

    function host:SetMeter(progress, token)
        local width = self.track:GetWidth()
        if not progress or progress <= 0 or not width or width <= 0 then
            self.fill:Hide()
            return
        end
        progress = math.min(1, progress)
        -- Cropped, not stretched: the drawn width and the texture coordinate move together,
        -- so every pixel of the bar keeps its own pixel of the art.
        self.fill:SetTexCoord(0, progress, 0, 1)
        self.fill:SetWidth(math.max(1, width * progress))
        Theme:Color(self.fill, token or "ACCENT_COPPER")
        self.fill:Show()
    end

    -- The goal meter is borrowed for the hold, then handed straight back.
    function host:ShowHold(progress)
        self.holding = true
        self.track:Show()
        self:SetMeter(progress, "TEXT_WARNING")
        self.reset.art:SetAlpha(ICON_HOVER)
        Theme:Color(self.reset.art, "ACCENT_COPPER")
    end

    function host:CancelHold()
        if not self.holding then return end
        self.holding = nil
        self.reset.held = 0
        self.reset:SetScript("OnUpdate", nil)
        Theme:Color(self.reset.art, "TEXT_MUTED")
        self.reset.art:SetAlpha(ICON_REST)
        self:RestoreMeter()
    end

    function host:RestoreMeter()
        local wanted = R.Settings:GetOption("farmShowMeter") ~= false and self.progress or nil
        local shown = wanted ~= nil
        self.track:SetShown(shown)
        if not shown then
            self.fill:Hide()
            return
        end
        self:SetMeter(wanted)
    end

    -- Every vertical position in the panel, decided in one pass. A hidden stat row or a
    -- session with two items shortens the panel instead of leaving a hole in it.
    function host:LayoutPanel()
        local panel, offset = self.expand, -PAD
        for _, row in ipairs(panel.stats) do
            if row.visible then
                row.icon:ClearAllPoints()
                row.icon:SetPoint("TOPLEFT", PAD, offset - 1)
                row.text:ClearAllPoints()
                row.text:SetPoint("TOPLEFT", PAD + ICON_SIZE + 6, offset)
                row.text:SetPoint("RIGHT", -PAD, 0)
                offset = offset - STAT_ROW_HEIGHT
            end
        end
        local function rule(texture)
            offset = offset - SEPARATOR_GAP
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", PAD, offset)
            texture:SetPoint("TOPRIGHT", -PAD, offset)
            offset = offset - SEPARATOR_GAP
        end
        rule(panel.bestRule)
        panel.best:ClearAllPoints()
        panel.best:SetPoint("TOPLEFT", PAD, offset)
        panel.best:SetPoint("RIGHT", -PAD, 0)
        offset = offset - STAT_ROW_HEIGHT
        rule(panel.topRule)
        for _, row in ipairs(panel.rows) do
            if row:IsShown() then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", PAD, offset)
                row:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
                offset = offset - TOP_ROW_HEIGHT
            end
        end
        -- Kept as well as set, the way the options page keeps its own: a frame's height is
        -- not readable back in a headless test, and this is the number under test.
        panel.contentHeight = -offset + PAD
        panel:SetHeight(panel.contentHeight)
    end

    function host:SetStats(stats)
        self.rate:SetText(stats.rate or "")
        self.sub:SetText(stats.sub or "")
        self.tipTitle, self.tip = stats.tipTitle, stats.tip
        self.progress = stats.progress
        self.pauseDot:SetShown(stats.paused == true)
        self.pause.lit = stats.paused == true
        self.pause.art:SetAlpha(stats.paused and ICON_HOVER or ICON_REST)
        if not self.holding then self:RestoreMeter() end
        -- Rates are off unless asked for: how fast the drops come is not what a farmer is
        -- watching the HUD for, and it is the one row that reads as noise on a quiet pull.
        local showRates = R.Settings:GetOption("farmShowRates") == true
        for index, row in ipairs(self.expand.stats) do
            row.visible = index ~= RATES_ROW or showRates
            row.icon:SetShown(row.visible)
            row.text:SetShown(row.visible)
            row.text:SetText(stats.lines and stats.lines[index] or "")
        end
        self.expand.best:SetText(stats.best or "")
        local top = stats.top or {}
        for index, row in ipairs(self.expand.rows) do
            local entry = top[index]
            row:SetShown(entry ~= nil)
            if entry then
                row.icon:SetTexture(entry.icon)
                row.name:SetText(entry.name or "")
                row.value:SetText(entry.value or "")
                row.name:SetTextColor(entry.r or 1, entry.g or 1, entry.b or 1)
            end
        end
        self:LayoutPanel()
    end

    function host:Expanded()
        return R.Settings:GetOption("farmExpand") == true
    end

    -- Where the panel sits when nothing is moving it. Every group ends here, so a press
    -- part way through the last one cannot leave the panel parked off its anchor.
    function host:ParkPanel()
        self.expand:ClearAllPoints()
        self.expand:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, PANEL_GAP)
        self.expand:SetAlpha(1)
    end

    function host:SpinChevron(expanded, animate)
        local target = expanded and 0 or CHEVRON_FLIP * RADIANS_PER_DEGREE
        if self.chevronTarget == target then
            return
        end
        local from = self.chevronTarget or target
        self.chevronTarget = target
        self.spin:Stop()
        if not animate then
            self.collapse.art:SetRotation(target)
            return
        end
        -- The turn starts from where the caret actually is, so a press part way through the
        -- last one carries on from that angle rather than snapping back to begin again.
        self.collapse.art:SetRotation(from)
        self.spinAnim:SetDegrees((target - from) / RADIANS_PER_DEGREE)
        self.spin:Play()
    end

    function host:SettleAnimations()
        self.spin:Stop()
        self.collapse.art:SetRotation(self.chevronTarget or 0)
        self.panelOpenGroup:Stop()
        self.panelCloseGroup:Stop()
        self:ParkPanel()
        self.expand:SetShown(self.panelOpen == true)
    end

    -- The caret has to say which way the next press goes, so it is turned to match the
    -- state and its tooltip is rewritten with it.
    function host:ApplyExpanded(animate)
        local expanded = self:Expanded()
        self.collapse.tipTitle = expanded and L.FARM_TIP_COLLAPSE_TITLE or L.FARM_TIP_EXPAND_TITLE
        self.collapse.tip = expanded and L.FARM_TIP_COLLAPSE or L.FARM_TIP_EXPAND
        self:SpinChevron(expanded, animate)
        if self.panelOpen == expanded then
            return
        end
        self.panelOpen = expanded
        self.panelOpenGroup:Stop()
        self.panelCloseGroup:Stop()
        self:ParkPanel()
        if not animate then
            self.expand:SetShown(expanded)
            return
        end
        if expanded then
            self.expand:ClearAllPoints()
            self.expand:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, PANEL_GAP + PANEL_DROP)
            self.expand:Show()
            self.panelOpenGroup:Play()
        else
            self.panelCloseGroup:Play()
        end
    end

    -- The pointer moving from the HUD onto one of its own buttons is not leaving the HUD.
    function host:LeaveIfOutside()
        if self:IsMouseOver() then return end
        self.hovered = false
        self:UpdateHover()
    end

    -- Hover only ever governs the controls: the grip and the icon row. What the HUD shows
    -- is the player's choice and does not move when the pointer does.
    function host:UpdateHover()
        local hovered = self.hovered == true
        self.gripFade:To(hovered and not self:Locked() and 1 or 0)
        for _, button in ipairs(self.icons) do
            button.fade:To(hovered and 1 or 0)
        end
    end

    function host:ApplySettings()
        self:TintBackdrop(self.backdrop)
        self:TintBackdrop(self.expand.backdrop)
        self:RestoreMeter()
        self:ApplyExpanded(true)
        self:UpdateHover()
        self:SetShown(self.owner.state == "enabled" and R.Settings:GetOption("farmShowHud") ~= false)
    end

    function host:SavePosition()
        local character = R.Settings.character
        if not character then return end
        local point, _, relativePoint, x, y = self:GetPoint(1)
        character.farmHud = { point = point, relativePoint = relativePoint, x = x, y = y }
    end

    function host:RestorePosition()
        local saved = R.Settings.character and R.Settings.character.farmHud or nil
        if type(saved) ~= "table" or not VALID_POINTS[saved.point] or not VALID_POINTS[saved.relativePoint]
            or type(saved.x) ~= "number" or type(saved.y) ~= "number" then
            saved = DEFAULT_POSITION
        end
        self:ClearAllPoints()
        self:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end

    -- Rebuilt on every open so a checked item is never stale, which is what UIDropDownMenu
    -- expects an initializer to do.
    function host:InitializeMenu()
        local title = UIDropDownMenu_CreateInfo()
        title.text, title.isTitle, title.notCheckable = L.FARM_MENU_TITLE, true, true
        UIDropDownMenu_AddButton(title)
        local function entry(text, handler, checked)
            local button = UIDropDownMenu_CreateInfo()
            button.text, button.func = text, handler
            button.notCheckable = checked == nil
            button.checked = checked
            button.keepShownOnClick = false
            UIDropDownMenu_AddButton(button)
        end
        entry(L.FARM_MENU_RESET, function() if host.onReset then host.onReset() end end)
        entry(L.FARM_MENU_GOAL, function() if host.onSetGoal then host.onSetGoal() end end)
        entry(L.FARM_MENU_LOCK, function() R.Settings:SetOption("farmLocked", not host:Locked()) end,
            host:Locked())
        entry(L.FARM_MENU_HIDE, function() if host.onHide then host.onHide() end end)
        entry(L.FARM_MENU_SUMMARY, function() if host.onOpenSummary then host.onOpenSummary() end end)
    end

    function host:ToggleMenu()
        UIDropDownMenu_Initialize(self.menu, function() self:InitializeMenu() end, "MENU")
        ToggleDropDownMenu(1, nil, self.menu, "cursor", 0, 0)
    end

    host:SetScript("OnEnter", function(widget)
        widget.hovered = true
        widget:UpdateHover()
        tooltipLines(widget, widget.tipTitle or L.FARM_TIP_RATE_TITLE, widget.tip or L.FARM_TIP_RATE)
    end)
    host:SetScript("OnLeave", function(widget)
        hideTooltip()
        widget:LeaveIfOutside()
    end)
    host:SetScript("OnMouseUp", function(widget, button)
        if button == "RightButton" then widget:ToggleMenu() end
    end)
    -- Animations do not advance on a hidden frame, so a HUD hidden mid-move would come back
    -- with the panel parked off its anchor and the caret stopped part way round. Land both.
    host:SetScript("OnHide", function(widget)
        widget.hovered = false
        widget:CancelHold()
        widget:UpdateHover()
        widget:SettleAnimations()
    end)

    local function startDrag()
        if not host:Locked() then host:StartMoving() end
    end
    local function stopDrag()
        host:StopMovingOrSizing()
        host:SavePosition()
    end
    host:SetScript("OnDragStart", startDrag)
    host:SetScript("OnDragStop", stopDrag)
    host.grip:SetScript("OnDragStart", startDrag)
    host.grip:SetScript("OnDragStop", stopDrag)

    openGroup:SetScript("OnFinished", function() host:ParkPanel() end)
    closeGroup:SetScript("OnFinished", function()
        host.expand:Hide()
        host:ParkPanel()
    end)

    host:LayoutPanel()
    host:RestorePosition()
    host:ApplyExpanded(false)
    host:Hide()
    owner.refactorFarmHud = host
    return host
end
