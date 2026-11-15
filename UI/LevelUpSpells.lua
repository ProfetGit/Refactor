local _, R = ...
local L = R.L
local Theme = R.Theme

-- Refactor's own strip, hung under Blizzard's level-up banner. It only anchors to that banner:
-- nothing of Blizzard's is restyled, hidden or written to. The cells are made once and recycled.
local MAX_CELLS = 5
local CELL_WIDTH, CELL_HEIGHT, CELL_GAP = 168, 34, 6
local ICON, ICON_CROP, TEXT_GAP = 30, 0.08, 8
local HEADER_HEIGHT, PAD_X, PAD_TOP, PAD_BOTTOM = 18, 26, 8, 12
local SMUDGE_BLEED = 40
local RULE_HEIGHT = 6
local FADE_IN, FADE_OUT = 0.55, 0.8
local REVEAL, REVEAL_STAGGER = 0.4, 0.12
local FALLBACK_Y = -262

local function shadowed(text)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    return text
end

local function halves(frame, key, layer, token, bleed, height)
    local pair = {}
    for side = 1, 2 do
        local texture = Theme:Texture(frame, key, layer)
        Theme:Color(texture, token)
        local left = side == 1
        if height > 0 then
            texture:SetHeight(height)
            texture:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", frame, left and "BOTTOMLEFT" or "BOTTOMRIGHT")
            texture:SetPoint(left and "BOTTOMRIGHT" or "BOTTOMLEFT", frame, "BOTTOM")
        else
            texture:SetPoint(left and "TOPLEFT" or "TOPRIGHT", frame, left and "TOPLEFT" or "TOPRIGHT",
                left and -bleed or bleed, 0)
            texture:SetPoint(left and "BOTTOMRIGHT" or "BOTTOMLEFT", frame, "BOTTOM")
        end
        if left then
            texture:SetTexCoord(1, 0, 0, 1)
        end
        pair[side] = texture
    end
    return pair
end

local function newCell(parent, index)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(CELL_WIDTH, CELL_HEIGHT)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ICON, ICON)
    cell.icon:SetPoint("LEFT")
    cell.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    cell.frame = Theme:Texture(cell, "lootIconFrame", "OVERLAY")
    cell.frame:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -1, 1)
    cell.frame:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 1, -1)
    cell.name = shadowed(Theme:Text(cell, "", "body", "TEXT_HIGHLIGHT"))
    cell.name:SetWordWrap(false)
    cell.name:SetWidth(CELL_WIDTH - ICON - TEXT_GAP)
    cell.name:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", TEXT_GAP, 0)
    cell.detail = shadowed(Theme:Text(cell, "", "small", "TEXT_MUTED"))
    cell.detail:SetWordWrap(false)
    cell.detail:SetWidth(CELL_WIDTH - ICON - TEXT_GAP)
    cell.detail:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMRIGHT", TEXT_GAP, 0)
    cell.reveal = cell:CreateAnimationGroup()
    cell.reveal:SetToFinalAlpha(true)
    local alpha = cell.reveal:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(REVEAL)
    alpha:SetStartDelay((index - 1) * REVEAL_STAGGER)
    alpha:SetSmoothing("OUT")
    cell:Hide()
    return cell
end

-- Made once at module enable; hidden until a level up has something to say.
function R.UI:LevelUpSpellsCreate()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetSize(CELL_WIDTH + PAD_X * 2, PAD_TOP + HEADER_HEIGHT + CELL_HEIGHT + PAD_BOTTOM)
    frame:Hide()
    R:OwnFrame(frame)
    local ui = { frame = frame, cells = {}, used = 0 }
    -- The loot feed art is bright at its left edge and fades to the right, so a centred strip is
    -- two halves: one mirrored, both bright at the middle.
    ui.smudge = halves(frame, "lootRow", "BACKGROUND", "LOOT_ROW", SMUDGE_BLEED, 0)
    ui.rule = halves(frame, "lootUnderline", "BORDER", "ACCENT_COPPER", 0, RULE_HEIGHT)
    ui.header = shadowed(Theme:Text(frame, L.LEVELUP_SPELLS_HEADER, "body", "TEXT_TITLE"))
    ui.header:SetJustifyH("CENTER")
    ui.header:SetPoint("TOP", 0, -PAD_TOP)
    ui.more = shadowed(Theme:Text(frame, "", "small", "TEXT_MUTED"))
    ui.more:SetJustifyH("CENTER")
    ui.more:SetPoint("BOTTOM", 0, 4)
    for index = 1, MAX_CELLS do
        ui.cells[index] = newCell(frame, index)
    end
    ui.fader = Theme:Fader(frame, FADE_IN, FADE_OUT)
    return ui
end

R.UI.LEVELUP_SPELLS_MAX = MAX_CELLS

-- Hung under the banner when the client has it, else where the banner sits by default.
function R.UI:LevelUpSpellsAnchor(ui, banner)
    local frame = ui.frame
    frame:ClearAllPoints()
    if type(banner) == "table" and type(banner.GetBottom) == "function" then
        frame:SetPoint("TOP", banner, "BOTTOM", 0, -2)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, FALLBACK_Y)
    end
end

-- entries: { name, icon, detail, ready }; more: how many did not fit.
function R.UI:LevelUpSpellsSet(ui, entries, more)
    local count = math.min(#entries, MAX_CELLS)
    ui.used = count
    local width = count * CELL_WIDTH + (count - 1) * CELL_GAP
    local left = -width / 2
    for index, cell in ipairs(ui.cells) do
        local entry = entries[index]
        cell.reveal:Stop()
        if index <= count and entry then
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", ui.frame, "TOP", left + (index - 1) * (CELL_WIDTH + CELL_GAP),
                -(PAD_TOP + HEADER_HEIGHT))
            if entry.icon then
                cell.icon:SetTexture(entry.icon)
            else
                Theme:ApplyAsset(cell.icon, "unknownItem")
            end
            cell.name:SetText(entry.name)
            cell.detail:SetText(entry.detail)
            Theme:Color(cell.detail, entry.ready and "RING_DONE" or "TEXT_MUTED", true)
            cell:SetAlpha(0)
            cell:Show()
        else
            cell:Hide()
        end
    end
    ui.more:SetText(more > 0 and string.format(L.LEVELUP_SPELLS_MORE, more) or "")
    local extra = more > 0 and 12 or 0
    ui.frame:SetSize(math.max(width, CELL_WIDTH) + PAD_X * 2,
        PAD_TOP + HEADER_HEIGHT + CELL_HEIGHT + PAD_BOTTOM + extra)
end

function R.UI:LevelUpSpellsShow(ui)
    ui.frame:Show()
    ui.fader:To(1)
    for index = 1, ui.used do
        ui.cells[index].reveal:Play()
    end
end

function R.UI:LevelUpSpellsFade(ui)
    ui.fader:To(0)
end

function R.UI:LevelUpSpellsHide(ui)
    ui.fader:Snap(0)
    for _, cell in ipairs(ui.cells) do
        cell.reveal:Stop()
        cell:Hide()
    end
    ui.frame:Hide()
end
