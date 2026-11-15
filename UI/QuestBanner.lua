local _, R = ...
local L = R.L
local Theme = R.Theme

-- Refactor's own banner for quest progress, a finished quest and a hand-in, hung under Blizzard's
-- error text so a red "Not enough rage" never lands on top of it. Nothing of Blizzard's is drawn
-- on. The rows are made once at enable and recycled; the newest sits on top, as the error text
-- inserts its own.
local MAX_ROWS = 3
local ROW_GAP = 5
-- The smoke's dense core is the middle of its art and the wisps fill the rest, so it overhangs
-- the row on every side to keep the text over the core.
local PAD_X, SMUDGE_BLEED, SMUDGE_LIFT = 30, 36, 10
-- The objective line is the size of the line it replaces: Blizzard's ErrorFont is GameFontNormalLarge,
-- Friz Quadrata at 16 px (12.1.0 GameFontStyles.xml). Everything else is scaled from it.
local ICON, ICON_GAP, COUNT_GAP = 16, 6, 7
local TITLE_HEIGHT, LINE_HEIGHT = 16, 21
local BAR_GAP, BAR_HEIGHT, BAR_MIN, PAD_BOTTOM = 5, 6, 120, 7
-- The fill's glow is twice the groove's height and spills evenly above and below it.
local FILL_HEIGHT = 12
local HEADING_HEIGHT, SUB_HEIGHT, RULE_GAP, RULE_HEIGHT = 27, 17, 4, 4
local FADE_IN, FADE_OUT = 0.25, 0.9
local DROP, DROP_TIME = 6, 0.3
local GROW_TIME, FLASH_IN, FLASH_OUT = 0.45, 0.12, 0.5
-- A changed count rolls: the old number rises out and fades as the new one rises in from below.
local ROLL, ROLL_TIME = 6, 0.28
local RULE_OPEN = 0.5
local FALLBACK_Y, ERRORS_GAP = -184, 4
-- Blizzard's level-up toast (EventToastManagerFrame, 72 px at TOP -190) and the new-abilities strip
-- under it take the space below the error text for a few seconds. A hand-in that levels you lands
-- in that moment, so the banner steps down under both rather than over them.
local LEVEL_UP_CLEARANCE = 152
local ICON_KEYS = { kill = "questIconKill", item = "questIconItem", other = "questIconOther" }

local function shadowed(text)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    return text
end

-- The bar and the rule are revealed by tweening their width and crop through R.Fade, never by a
-- Scale animation. A Scale squashes the tapered art, and it takes hold a frame after Play, so the
-- bar showed its new length for one frame, snapped back and grew again. The tween eases out, so
-- the bar answers the update at once and settles, rather than seeming to wait before it moves.
local function writeFill(fill, value)
    fill.value = value
    if value <= 0 then
        fill:Hide()
        return
    end
    fill:SetTexCoord(0, value, 0, 1)
    fill:SetWidth(math.max(1, fill.span * value))
    fill:Show()
end

-- The rule opens from the middle: a centred crop of its art, widening to the whole of it.
local function writeRule(rule, value)
    local half = math.max(value, 0.01) / 2
    rule:SetTexCoord(0.5 - half, 0.5 + half, 0, 1)
    rule:SetWidth(math.max(1, rule.span * value))
end

-- The client snaps textures to whole pixels by default, so an edge moving less than a pixel a frame
-- advanced in uneven one-pixel steps. Theme:Divider turns the same two switches off.
local function unsnapped(texture)
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    return texture
end

-- The incoming number starts at zero alpha and keeps its final alpha, so neither jump of its two
-- Translation legs is ever drawn; the outgoing one leaves from where the number was.
local function roller(text, incoming)
    local group = text:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    if incoming then
        local below = group:CreateAnimation("Translation")
        below:SetOffset(0, -ROLL)
        below:SetDuration(0)
        below:SetOrder(1)
    end
    local move = group:CreateAnimation("Translation")
    move:SetOffset(0, ROLL)
    move:SetDuration(ROLL_TIME)
    move:SetOrder(2)
    move:SetSmoothing("OUT")
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(incoming and 0 or 1)
    alpha:SetToAlpha(incoming and 1 or 0)
    alpha:SetDuration(ROLL_TIME)
    alpha:SetOrder(2)
    alpha:SetSmoothing("OUT")
    return group
end

-- A Translation ends where it started, so the drop is two legs: a jump up that takes no time,
-- then the fall back to where the row really is. The row is at zero alpha for the first frame.
local function dropper(row)
    local group = row:CreateAnimationGroup()
    local up = group:CreateAnimation("Translation")
    up:SetOffset(0, DROP)
    up:SetDuration(0)
    up:SetOrder(1)
    local down = group:CreateAnimation("Translation")
    down:SetOffset(0, -DROP)
    down:SetDuration(DROP_TIME)
    down:SetOrder(2)
    down:SetSmoothing("OUT")
    return group
end

local function newRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(BAR_MIN + PAD_X * 2, TITLE_HEIGHT + LINE_HEIGHT)
    row:Hide()
    row.smudge = Theme:Texture(row, "questBannerBackdrop", "BACKGROUND")
    Theme:Color(row.smudge, "QUEST_BANNER_BG")
    Theme:VerifyFile(row.smudge, "questBannerBackdrop")
    row.smudge:SetPoint("TOPLEFT", row, "TOPLEFT", -SMUDGE_BLEED, SMUDGE_LIFT)
    row.smudge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", SMUDGE_BLEED, -SMUDGE_LIFT)
    row.rule = unsnapped(Theme:Texture(row, "questBannerRule", "BORDER"))
    row.rule:SetHeight(RULE_HEIGHT)
    row.rule:SetPoint("TOP", row, "TOP", 0, -(HEADING_HEIGHT + SUB_HEIGHT + RULE_GAP))
    Theme:Color(row.rule, "ACCENT_COPPER")
    Theme:VerifyFile(row.rule, "questBannerRule")
    row.rule.span = BAR_MIN
    row.title = shadowed(Theme:Text(row, "", "body", "TEXT_TITLE"))
    row.title:SetJustifyH("CENTER")
    row.title:SetWordWrap(false)
    row.heading = shadowed(Theme:Text(row, "", "huge", "TEXT_TITLE"))
    row.heading:SetJustifyH("CENTER")
    row.heading:SetWordWrap(false)
    row.sub = shadowed(Theme:Text(row, "", "body", "RING_DONE"))
    row.sub:SetWordWrap(false)
    row.icon = Theme:Texture(row, "questIconOther", "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.label = shadowed(Theme:Text(row, "", "title", "TEXT_BODY"))
    row.label:SetWordWrap(false)
    row.value = shadowed(Theme:Text(row, "", "title", "QUEST_VALUE"))
    row.valueOld = shadowed(Theme:Text(row, "", "title", "QUEST_VALUE"))
    row.valueOld:SetAlpha(0)
    row.total = shadowed(Theme:Text(row, "", "title", "TEXT_MUTED"))
    row.track = unsnapped(Theme:Texture(row, "questBarTrack", "ARTWORK"))
    row.track:SetHeight(BAR_HEIGHT)
    Theme:Color(row.track, "QUEST_BAR_TRACK")
    Theme:VerifyFile(row.track, "questBarTrack")
    row.fill = unsnapped(Theme:Texture(row, "questBarFill", "OVERLAY"))
    row.fill:SetHeight(FILL_HEIGHT)
    row.fill:SetPoint("LEFT", row.track, "LEFT")
    Theme:VerifyFile(row.fill, "questBarFill")
    row.fill.span, row.fill.value = BAR_MIN, 0
    row.flash = unsnapped(Theme:Texture(row, "questBarFill", "OVERLAY"))
    row.flash:SetHeight(FILL_HEIGHT)
    row.flash:SetPoint("LEFT", row.track, "LEFT")
    row.flash:SetPoint("RIGHT", row.track, "RIGHT")
    row.flash:SetBlendMode("ADD")
    Theme:Color(row.flash, "TEXT_HIGHLIGHT")
    row.flash:SetAlpha(0)

    row.fader = Theme:Fader(row, FADE_IN, FADE_OUT)
    row.drop = dropper(row)
    -- Only the number moves, and only by Translation and Alpha: scaling a FontString
    -- re-rasterises its outline and flickers.
    row.rollIn = roller(row.value, true)
    row.rollOut = roller(row.valueOld, false)
    -- The finish flash lands as the fill arrives, not while it is still on its way.
    row.shine = row.flash:CreateAnimationGroup()
    local rise = row.shine:CreateAnimation("Alpha")
    rise:SetFromAlpha(0)
    rise:SetToAlpha(0.8)
    rise:SetDuration(FLASH_IN)
    rise:SetStartDelay(GROW_TIME * 0.7)
    rise:SetOrder(1)
    local fall = row.shine:CreateAnimation("Alpha")
    fall:SetFromAlpha(0.8)
    fall:SetToAlpha(0)
    fall:SetDuration(FLASH_OUT)
    fall:SetOrder(2)
    fall:SetSmoothing("IN")
    return row
end

-- Made once at module enable; hidden until the client reports progress.
function R.UI:QuestBannerCreate()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetSize(BAR_MIN + PAD_X * 2, 1)
    frame:Hide()
    R:OwnFrame(frame)
    local ui = { frame = frame, rows = {}, free = {}, active = {}, byKey = {} }
    for index = 1, MAX_ROWS do
        ui.rows[index] = newRow(frame)
        ui.free[index] = ui.rows[index]
    end
    return ui
end

R.UI.QUEST_BANNER_ROWS = MAX_ROWS

-- Under the error text when the client has it, else where that text sits by default.
local function anchor(ui)
    local frame, errors = ui.frame, ui.errors
    local drop = ui.wantLowered and LEVEL_UP_CLEARANCE or 0
    frame:ClearAllPoints()
    if type(errors) == "table" and type(errors.GetBottom) == "function" then
        frame:SetPoint("TOP", errors, "BOTTOM", 0, -(ERRORS_GAP + drop))
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, FALLBACK_Y - drop)
    end
    ui.lowered = ui.wantLowered
end

function R.UI:QuestBannerAnchor(ui, errors)
    ui.errors, ui.wantLowered = errors, false
    anchor(ui)
end

-- Stepping down happens at once, rows and all; stepping back up waits until the banner is empty,
-- so nothing on screen jumps while it is being read.
function R.UI:QuestBannerLower(ui, lowered)
    ui.wantLowered = lowered == true
    if ui.wantLowered or #ui.active == 0 then
        anchor(ui)
    end
end

local function showOnly(row, kind)
    local progress = kind == "progress"
    local banner = kind == "ready" or kind == "turnin"
    row.title:SetShown(progress)
    row.label:SetShown(progress)
    if not progress then
        row.value:Hide()
        row.valueOld:Hide()
        row.total:Hide()
        row.track:Hide()
        row.fill:Hide()
        row.flash:Hide()
    end
    row.icon:Show()
    row.heading:SetShown(banner)
    row.sub:SetShown(banner)
    row.rule:SetShown(banner)
end

local function setIcon(row, entry, done)
    Theme:ApplyAsset(row.icon, done and "questCheck" or ICON_KEYS[entry.icon] or ICON_KEYS.other)
    row.icon:SetSize(ICON, ICON)
end

-- The quest's name over the objective, the objective with its count, and a thin bar under it.
local function layoutProgress(row, entry)
    local counted = type(entry.have) == "number" and type(entry.need) == "number" and entry.need > 0
    local done = entry.done or counted and entry.have >= entry.need
    local hasTitle = type(entry.title) == "string" and entry.title ~= ""
    row.title:SetText(hasTitle and entry.title or "")
    row.label:SetText(entry.label or "")
    setIcon(row, entry, done)
    row.value:SetShown(counted)
    row.valueOld:SetShown(counted)
    row.total:SetShown(counted)
    row.track:SetShown(counted)
    row.flash:SetShown(counted)
    local valueWidth = 0
    if counted then
        row.value:SetText(tostring(entry.have))
        row.total:SetText(string.format(L.QUEST_BANNER_TOTAL, entry.need))
        Theme:Color(row.value, done and "RING_DONE" or "QUEST_VALUE", true)
        Theme:Color(row.total, done and "RING_DONE" or "TEXT_MUTED", true)
        valueWidth = COUNT_GAP + row.value:GetStringWidth() + row.total:GetStringWidth()
    else
        R.Fade:Cancel(row.fill)
        row.fill.value = 0
        row.fill:Hide()
    end
    local lineWidth = ICON + ICON_GAP + row.label:GetStringWidth() + valueWidth
    local width = math.max(lineWidth, BAR_MIN)
    local top = hasTitle and TITLE_HEIGHT or 0
    row.title:ClearAllPoints()
    row.title:SetPoint("TOP", row, "TOP", 0, 0)
    row.title:SetWidth(width + PAD_X)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "TOP", -lineWidth / 2, -(top + LINE_HEIGHT / 2))
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.icon, "RIGHT", ICON_GAP, 0)
    row.value:ClearAllPoints()
    row.value:SetPoint("LEFT", row.label, "RIGHT", COUNT_GAP, 0)
    row.valueOld:ClearAllPoints()
    row.valueOld:SetPoint("LEFT", row.label, "RIGHT", COUNT_GAP, 0)
    row.total:ClearAllPoints()
    row.total:SetPoint("LEFT", row.value, "RIGHT", 0, 0)
    local height = top + LINE_HEIGHT + PAD_BOTTOM
    if counted then
        row.track:ClearAllPoints()
        row.track:SetPoint("TOP", row, "TOP", 0, -(top + LINE_HEIGHT + BAR_GAP))
        row.track:SetWidth(width)
        row.fill.span = width
        Theme:Color(row.fill, done and "RING_DONE" or "RING_FILL")
        height = height + BAR_GAP + BAR_HEIGHT
    end
    row:SetSize(width + PAD_X * 2, height)
    return counted, done
end

-- A finished quest or a hand-in: the quest's name in the banner font, one line under it, and the
-- rule under that with room to breathe before the next row.
local function layoutBanner(row, entry)
    row.heading:SetText(entry.title or "")
    row.sub:SetText(entry.label or "")
    Theme:Color(row.sub, entry.kind == "ready" and "RING_DONE" or "TEXT_BODY", true)
    setIcon(row, entry, true)
    local subWidth = ICON + ICON_GAP + row.sub:GetStringWidth()
    local width = math.max(row.heading:GetStringWidth(), subWidth, BAR_MIN)
    row.heading:ClearAllPoints()
    row.heading:SetPoint("TOP", row, "TOP", 0, 0)
    row.heading:SetWidth(width + PAD_X)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "TOP", -subWidth / 2, -(HEADING_HEIGHT + SUB_HEIGHT / 2))
    row.sub:ClearAllPoints()
    row.sub:SetPoint("LEFT", row.icon, "RIGHT", ICON_GAP, 0)
    row.rule.span = width + PAD_X
    row:SetSize(width + PAD_X * 2, HEADING_HEIGHT + SUB_HEIGHT + RULE_GAP + RULE_HEIGHT + PAD_BOTTOM)
end

local function stopAll(row)
    row.drop:Stop()
    row.rollIn:Stop()
    row.rollOut:Stop()
    row.value:SetAlpha(1)
    row.valueOld:SetAlpha(0)
    row.shine:Stop()
    row.flash:SetAlpha(0)
    R.Fade:Cancel(row.fill)
    R.Fade:Cancel(row.rule)
end

local function layout(ui)
    if #ui.active == 0 and ui.lowered ~= ui.wantLowered then
        anchor(ui)
    end
    local y = 0
    for _, row in ipairs(ui.active) do
        row:ClearAllPoints()
        row:SetPoint("TOP", ui.frame, "TOP", 0, -y)
        y = y + row:GetHeight() + ROW_GAP
    end
    ui.frame:SetShown(#ui.active > 0)
end

local function release(ui, row)
    for index, active in ipairs(ui.active) do
        if active == row then
            table.remove(ui.active, index)
            break
        end
    end
    if row.key then
        ui.byKey[row.key] = nil
    end
    row.key, row.entry, row.questID = nil, nil, nil
    stopAll(row)
    row.fader:Snap(0)
    row:Hide()
    ui.free[#ui.free + 1] = row
end

-- A row the entry may take over: the same key, or a progress row of the quest it finishes.
local function claim(ui, entry)
    local row = ui.byKey[entry.key]
    if row then
        return row, false
    end
    if entry.questID and entry.kind ~= "progress" then
        for index = #ui.active, 1, -1 do
            local active = ui.active[index]
            if active.questID == entry.questID and active.entry.kind == "progress" then
                if row then
                    release(ui, row)
                end
                row = active
            end
        end
        if row then
            ui.byKey[row.key] = nil
            return row, true
        end
    end
    row = table.remove(ui.free)
    if not row then
        row = ui.active[#ui.active]
        release(ui, row)
        table.remove(ui.free)
    end
    table.insert(ui.active, 1, row)
    return row, true
end

-- entry: { key, kind = "progress" | "ready" | "turnin", questID, title, label, icon, have, need, done }.
function R.UI:QuestBannerPut(ui, entry)
    if #ui.active == 0 and ui.lowered ~= ui.wantLowered then
        anchor(ui)
    end
    local row, fresh = claim(ui, entry)
    local previous = row.entry
    local same = not fresh and previous and previous.kind == entry.kind
    row.key, row.entry, row.questID = entry.key, entry, entry.questID
    ui.byKey[entry.key] = row
    if not same then
        stopAll(row)
        row.fill.value = 0
    end
    showOnly(row, entry.kind)
    if entry.kind == "progress" then
        local counted, done = layoutProgress(row, entry)
        if counted then
            -- A new row has no earlier count on screen, so it grows from the step before this one.
            local from = same and row.fill.value or math.max(0, entry.have - 1) / entry.need
            R.Fade:Value(row.fill, math.min(1, entry.have / entry.need), GROW_TIME, writeFill, from, "out")
            if same and previous.have ~= entry.have then
                row.rollIn:Stop()
                row.rollOut:Stop()
                row.valueOld:SetText(tostring(previous.have))
                Theme:Color(row.valueOld, previous.done and "RING_DONE" or "QUEST_VALUE", true)
                row.valueOld:SetAlpha(1)
                row.value:SetAlpha(0)
                row.rollOut:Play()
                row.rollIn:Play()
            end
            if done and not (same and previous.done) then
                row.shine:Stop()
                row.shine:Play()
            end
        end
        entry.done = done
    else
        layoutBanner(row, entry)
        R.Fade:Value(row.rule, 1, RULE_OPEN, writeRule, same and 1 or 0, "out")
    end
    if not same then
        row:SetAlpha(0)
        row.fader:Snap(0)
        row.drop:Play()
    end
    row:Show()
    row.fader:To(1)
    layout(ui)
    return row
end

function R.UI:QuestBannerLeave(ui, key)
    local row = ui.byKey[key]
    if row then
        row.fader:To(0)
    end
end

function R.UI:QuestBannerDrop(ui, key)
    local row = ui.byKey[key]
    if row then
        release(ui, row)
        layout(ui)
    end
end

function R.UI:QuestBannerHide(ui)
    for index = #ui.active, 1, -1 do
        release(ui, ui.active[index])
    end
    ui.frame:Hide()
    if ui.lowered ~= ui.wantLowered then
        anchor(ui)
    end
end
