local _, R = ...
local L = R.L
local Theme = R.Theme

-- Refactor's own panel, docked to the right of the profession window. Nothing here touches a Blizzard frame
-- beyond anchoring to it. Every row exists from module enable on and is only filled, shown or hidden; rows
-- that do not fit the window's height are counted into a "more" line instead of running off the panel.
local WIDTH, DOCK_GAP, PAD = 300, 3, 14
local TITLE_Y, SUMMARY_Y, BODY_Y = -16, -44, 68
local TOGGLE_WIDTH, TOGGLE_HEIGHT = 64, 20
local STEP_HEIGHT, ICON, ICON_CROP, ROW_PAD = 36, 28, 0.08, 4
-- WhiteIconFrame draws its edge inside its own rect, so it sits this far out to frame the whole icon.
local BORDER_OUTSET = 2
local REAGENT_HEIGHT, REAGENT_ICON = 20, 16
local LINE_HEIGHT, SECTION_GAP, STEP_BAR = 18, 10, 2
local STEP_POOL, CANDIDATE_POOL, REAGENT_POOL = 8, 3, 8
local READY_GAP, HAVE_WIDTH = 8, 70
local PANEL_LEVEL = 5
local UNLEARNED_ALPHA = 0.55
local SHOWN_RATE = 1.05
local INNER = WIDTH - PAD * 2

local function hideTip(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function line(text, token)
    return "|c" .. Theme:Hex(token) .. text .. "|r"
end

local function stepTip(row)
    local entry, ui = row.entry, row.ui
    if not entry then return end
    row.wash:To(1)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(entry.name, nil, nil, nil, true)
    local green = math.floor((entry.low + entry.high) / 2)
    GameTooltip:AddLine(line(string.format(L.PLANNER_TIP_COLOURS, entry.low, green, entry.high), "TEXT_BODY"))
    local sourceKey = entry.source == "table" and "PLANNER_TIP_TABLE" or entry.source == "seen" and
        "PLANNER_TIP_SEEN" or "PLANNER_TIP_ESTIMATE"
    GameTooltip:AddLine(line(L[sourceKey], "TEXT_MUTED"), nil, nil, nil, true)
    if not entry.learned then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(line(L.PLANNER_TIP_LEARN, "TEXT_WARNING"))
        local source = ui.handlers.sourceText(entry.id)
        if type(source) == "string" and source ~= "" then GameTooltip:AddLine(source, nil, nil, nil, true) end
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(line(L.PLANNER_TIP_CLICK, "TEXT_MUTED"), nil, nil, nil, true)
    end
    GameTooltip:Show()
end

local function newStepRow(ui)
    local row = CreateFrame("Button", nil, ui.panel)
    row.ui = ui
    row:SetSize(INNER, STEP_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row.wash = Theme:RowHighlight(row)
    row.accent = Theme:Fill(row, "PLAN_READY", "ARTWORK")
    row.accent:ClearAllPoints()
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")
    row.accent:SetWidth(2)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", ROW_PAD + 2, 0)
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    row.border = Theme:Texture(row, "itemBorder", "OVERLAY")
    row.border:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -BORDER_OUTSET, BORDER_OUTSET)
    row.border:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", BORDER_OUTSET, -BORDER_OUTSET)
    -- The count shares the second line, so the recipe's name has the row's whole width.
    row.ready = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.ready:SetJustifyH("RIGHT")
    row.ready:SetPoint("BOTTOMRIGHT", -ROW_PAD, (STEP_HEIGHT - ICON) / 2)
    local textWidth = INNER - ROW_PAD * 2 - 2 - ICON - 8
    row.name = Theme:Text(row, "", "body", "TEXT_BODY")
    row.name:SetWordWrap(false)
    row.name:SetWidth(textWidth)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.sub = Theme:Text(row, "", "small", "TEXT_MUTED")
    row.sub:SetWordWrap(false)
    row.sub:SetWidth(textWidth)
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row.track = Theme:Texture(row, "hudMeterTrack", "ARTWORK")
    row.track:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -4)
    row.track:SetSize(textWidth, STEP_BAR)
    Theme:Color(row.track, "HUD_TRACK")
    row.fill = Theme:Texture(row, "hudMeterFill", "OVERLAY")
    row.fill:SetPoint("TOPLEFT", row.track, "TOPLEFT")
    row.fill:SetHeight(STEP_BAR)
    Theme:Color(row.fill, "PLAN_READY")
    row.barWidth = textWidth
    row:SetScript("OnClick", function(widget)
        if widget.entry and widget.entry.learned then widget.ui.handlers.onStep(widget.entry.id) end
    end)
    row:SetScript("OnEnter", stepTip)
    row:SetScript("OnLeave", function(widget)
        widget.wash:To(0)
        hideTip(widget)
    end)
    row:Hide()
    return row
end

local function newReagentRow(ui)
    local row = CreateFrame("Frame", nil, ui.panel)
    row:SetSize(INNER, REAGENT_HEIGHT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(REAGENT_ICON, REAGENT_ICON)
    row.icon:SetPoint("LEFT", ROW_PAD + 2, 0)
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    row.have = Theme:Text(row, "", "small", "TEXT_BODY")
    row.have:SetWidth(HAVE_WIDTH)
    row.have:SetJustifyH("RIGHT")
    row.have:SetPoint("RIGHT", -ROW_PAD, 0)
    row.name = Theme:Text(row, "", "small", "TEXT_BODY")
    row.name:SetWordWrap(false)
    row.name:SetWidth(INNER - ROW_PAD * 2 - 2 - REAGENT_ICON - 6 - HAVE_WIDTH - 4)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row:Hide()
    return row
end

local function setIcon(texture, icon)
    if icon then
        texture:SetTexture(icon)
    else
        Theme:ApplyAsset(texture, "unknownItem")
    end
end

-- The second line, longest first: the first that fits beside the ready count is shown, so the line loses a
-- word or the rate rather than being cut mid-word. "About" marks a rate from estimated colours.
local RATE_KEYS = {
    table = { "PLANNER_RATE", "PLANNER_RATE_SHORT" },
    estimate = { "PLANNER_RATE_ESTIMATED", "PLANNER_RATE_SHORT_ESTIMATED" },
}

local function setSub(row, step, width)
    local span = step.to - step.from
    row.sub:SetWidth(width)
    if span > 0 and step.crafts / span > SHOWN_RATE then
        for _, key in ipairs(RATE_KEYS[step.recipe.source == "estimate" and "estimate" or "table"]) do
            row.sub:SetText(string.format(L[key], step.from, step.to, step.crafts / span))
            local used = row.sub:GetStringWidth()
            if type(used) ~= "number" or used <= width then return end
        end
    end
    row.sub:SetText(string.format(L.PLANNER_RANGE, step.from, step.to))
end

local function fillStep(row, step, skill, ready, current)
    local entry = step.recipe
    row.entry = entry
    row.wash:Snap(0)
    hideTip(row)
    setIcon(row.icon, entry.icon)
    row.icon:SetDesaturated(false)
    row.icon:SetAlpha(1)
    Theme:Color(row.border, current and "PLAN_READY" or "ACCENT_COPPER")
    row.border:SetAlpha(1)
    row.accent:SetShown(current)
    Theme:Color(row.name, "TEXT_BODY", true)
    row.name:SetText(string.format(L.PLANNER_STEP, line(string.format(L.PLANNER_COUNT, step.whole), "TEXT_TITLE"),
        entry.name))
    Theme:Color(row.ready, "PLAN_READY", true)
    row.ready:SetText(ready > 0 and string.format(L.PLANNER_READY, ready) or "")
    local readyWidth = ready > 0 and row.ready:GetStringWidth() or 0
    setSub(row, step, row.barWidth - (type(readyWidth) == "number" and readyWidth > 0 and readyWidth + READY_GAP or 0))
    local started = step.started or step.from
    local share = current and step.to > started and (skill - started) / (step.to - started) or 0
    row.track:SetShown(current)
    row.fill:SetShown(current and share > 0)
    row.fill:SetWidth(math.max(1, row.barWidth * math.min(1, share)))
    row:Show()
end

local function fillCandidate(row, entry)
    row.entry = entry
    row.wash:Snap(0)
    hideTip(row)
    setIcon(row.icon, entry.icon)
    row.icon:SetDesaturated(true)
    row.icon:SetAlpha(UNLEARNED_ALPHA)
    Theme:Color(row.border, "TEXT_MUTED")
    row.border:SetAlpha(UNLEARNED_ALPHA)
    row.accent:Hide()
    Theme:Color(row.name, "TEXT_MUTED", true)
    row.name:SetText(entry.name)
    row.sub:SetWidth(row.barWidth)
    row.sub:SetText(string.format(L.PLANNER_CANDIDATE, entry.low, entry.high))
    row.ready:SetText("")
    row.track:Hide()
    row.fill:Hide()
    row:Show()
end

local function fillReagent(row, reagent)
    setIcon(row.icon, reagent.icon)
    row.name:SetText(reagent.name)
    Theme:Color(row.have, reagent.have >= reagent.need and "PLAN_READY" or "TEXT_WARNING", true)
    row.have:SetText(string.format(L.PLANNER_HAVE, math.min(reagent.have, reagent.need), reagent.need))
    row:Show()
end

local GOALS = { { value = "crafts", key = "PLANNER_GOAL_CRAFTS" }, { value = "gold", key = "PLANNER_GOAL_GOLD" } }

function R.UI:PlannerCreate(handlers)
    local ui = { handlers = handlers, steps = {}, candidates = {}, reagents = {}, attached = false }
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(WIDTH)
    panel:EnableMouse(true)
    panel:Hide()
    R:OwnFrame(panel)
    Theme:Panel(panel)
    ui.panel = panel

    ui.title = Theme:Text(panel, L.PLANNER_TITLE, "title", "TEXT_TITLE")
    ui.title:SetPoint("TOPLEFT", PAD, TITLE_Y)
    ui.title:SetPoint("RIGHT", -PAD - TOGGLE_WIDTH - 6, 0)
    ui.title:SetWordWrap(false)
    ui.toggle = Theme:Button(panel, TOGGLE_WIDTH, L.PLANNER_LESS, function() handlers.onCollapse() end,
        TOGGLE_HEIGHT)
    ui.toggle:SetPoint("TOPRIGHT", -PAD, TITLE_Y + 3)

    -- What is left of the plan, the one number the profession window does not already show. No rank bar:
    -- the window has its own.
    ui.summary = Theme:Text(panel, "", "small", "TEXT_BODY")
    ui.summary:SetPoint("TOPLEFT", PAD, SUMMARY_Y)
    ui.summary:SetPoint("RIGHT", -PAD, 0)
    ui.summary:SetWordWrap(false)

    local entries = {}
    for index, goal in ipairs(GOALS) do entries[index] = { value = goal.value, text = L[goal.key] } end
    ui.goal = Theme:Dropdown(panel, INNER, entries,
        function(value) return R.Settings:GetOption("plannerGoal") == value end,
        function(value) handlers.onGoal(value) end)
    ui.goal:SetLabel(L.PLANNER_GOAL)
    ui.goalText = {}
    for _, goal in ipairs(GOALS) do ui.goalText[goal.value] = L[goal.key] end

    ui.costLabel = Theme:Text(panel, L.PLANNER_COST, "small", "TEXT_MUTED")
    ui.cost = Theme:Coins(panel)
    ui.note = Theme:Text(panel, "", "small", "TEXT_WARNING")
    ui.note:SetWidth(INNER)
    ui.rule = Theme:Divider(panel)
    ui.stepsHeader = Theme:Text(panel, L.PLANNER_STEPS, "body", "TEXT_TITLE")
    ui.moreSteps = Theme:Text(panel, "", "small", "TEXT_MUTED")
    ui.gap = Theme:Text(panel, "", "small", "TEXT_MUTED")
    ui.gap:SetWidth(INNER)
    ui.reagentsHeader = Theme:Text(panel, L.PLANNER_REAGENTS, "body", "TEXT_TITLE")
    ui.moreReagents = Theme:Text(panel, "", "small", "TEXT_MUTED")
    for index = 1, STEP_POOL do ui.steps[index] = newStepRow(ui) end
    for index = 1, CANDIDATE_POOL do ui.candidates[index] = newStepRow(ui) end
    for index = 1, REAGENT_POOL do ui.reagents[index] = newReagentRow(ui) end

    panel:SetScript("OnHide", function()
        for _, row in ipairs(ui.steps) do hideTip(row) end
        for _, row in ipairs(ui.candidates) do hideTip(row) end
    end)
    return ui
end

-- How far past the window's right edge something else already sits: Forever's own profession tabs, and the
-- shared ProfessionsFrameTabSideBar other addons put their tabs in, which AllTheThings moves to the right of its
-- own window while that is open. Found by structure, not by name: a shown frame of the window, or a frame of
-- one on its edge, that starts at the edge and reaches past it.
local EDGE_SLACK = 16

local function reach(region, edge, best)
    if not region:IsShown() then return best end
    local left, right = region:GetLeft(), region:GetRight()
    if type(left) == "number" and type(right) == "number" and left >= edge - EDGE_SLACK and right > best then
        return right
    end
    return best
end

local function dockOffset(window, panel)
    local edge = window:GetRight()
    if type(edge) ~= "number" then return 0 end
    local best = edge
    for _, child in ipairs({ window:GetChildren() }) do
        if child ~= panel and child:IsShown() then
            local left = child:GetLeft()
            if type(left) == "number" and left >= edge - EDGE_SLACK then
                best = reach(child, edge, best)
                for _, inner in ipairs({ child:GetChildren() }) do best = reach(inner, edge, best) end
            end
        end
    end
    return best - edge
end

-- Parented to the window so it leaves with it, and drawn just above it.
function R.UI:PlannerAttach(ui, window)
    ui.attached, ui.window = true, window
    ui.panel:SetParent(window)
    ui.panel:SetFrameStrata(window:GetFrameStrata())
    ui.panel:SetFrameLevel(window:GetFrameLevel() + PANEL_LEVEL)
end

function R.UI:PlannerDetach(ui)
    ui.attached, ui.window = false, nil
    ui.panel:Hide()
    ui.panel:SetParent(UIParent)
    ui.panel:ClearAllPoints()
end

function R.UI:PlannerHide(ui)
    ui.panel:Hide()
end

local function place(ui, region, y, height, x)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", ui.panel, "TOPLEFT", x or PAD, -y)
    region:Show()
    return y + height
end

-- A note that may wrap takes the room its text needs, never less than a line.
local function textHeight(region)
    local height = region:GetStringHeight()
    return math.max(LINE_HEIGHT, (type(height) == "number" and height or 0) + 6)
end

local function hideAll(rows, from)
    for index = from, #rows do
        rows[index].entry = nil
        hideTip(rows[index])
        rows[index]:Hide()
    end
end

local function hideBody(ui)
    for _, region in ipairs({ ui.goal, ui.costLabel, ui.note, ui.rule, ui.stepsHeader, ui.moreSteps,
        ui.gap, ui.reagentsHeader, ui.moreReagents }) do
        region:Hide()
    end
    ui.cost:Hide()
end

-- The line under the title, which collapsed and full share: the crafts left, or the skill when nothing is left
-- to plan.
local function renderHeader(ui, data, plan)
    if #plan.steps > 0 then
        ui.summary:SetText(string.format(L.PLANNER_TOTAL, math.floor(plan.crafts + 0.5), plan.reached))
    else
        ui.summary:SetText(string.format(L.PLANNER_PROGRESS, data.name, data.skill, data.cap))
    end
end

local function steps(ui, plan, data, y, limit, count)
    local shown = 0
    for index, step in ipairs(plan.steps) do
        if index > count or y + STEP_HEIGHT > limit then break end
        local current = index == 1
        local ready = index <= STEP_POOL and ui.handlers.ready(step.recipe.id) or 0
        fillStep(ui.steps[index], step, data.skill, ready, current)
        y = place(ui, ui.steps[index], y, STEP_HEIGHT)
        shown = index
    end
    hideAll(ui.steps, shown + 1)
    return y, shown
end

function R.UI:PlannerRender(ui, view, collapsed)
    local data, plan, panel, window = view.data, view.plan, ui.panel, ui.window
    renderHeader(ui, data, plan)
    ui.toggle.label:SetText(collapsed and L.PLANNER_MORE or L.PLANNER_LESS)
    ui.dockX = DOCK_GAP + dockOffset(window, panel)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", window, "TOPRIGHT", ui.dockX, 0)
    hideBody(ui)
    hideAll(ui.candidates, 1)
    hideAll(ui.reagents, 1)
    local atCap = data.skill >= data.cap
    if collapsed then
        local y = BODY_Y
        local shown
        y, shown = steps(ui, plan, data, y, math.huge, 1)
        if shown == 0 then
            ui.gap:SetText(atCap and string.format(L.PLANNER_AT_CAP, data.cap)
                or string.format(L.PLANNER_GAP_NONE, plan.reached))
            y = place(ui, ui.gap, y, textHeight(ui.gap))
        end
        panel:SetHeight(y + PAD)
        panel:Show()
        return
    end
    panel:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", ui.dockX, 0)
    local height = panel:GetHeight()
    local limit = (type(height) == "number" and height > 0 and height or 600) - PAD
    ui.goal:SetValueText(ui.goalText[plan.requested] or "")
    local y = place(ui, ui.goal, BODY_Y, Theme.dropdownRowHeight + 4)
    if #plan.steps > 0 and plan.goal == "gold" then
        place(ui, ui.costLabel, y, LINE_HEIGHT)
        ui.cost:Place(ui.costLabel, math.floor(plan.total + 0.5), nil, "LEFT", ui.costLabel, "RIGHT", 4, 0)
        y = y + LINE_HEIGHT
    end
    if plan.note then
        ui.note:SetText(plan.note == "noAuction" and L.PLANNER_NO_AUCTION or L.PLANNER_UNPRICED)
        y = place(ui, ui.note, y, textHeight(ui.note))
    end
    ui.rule:ClearAllPoints()
    ui.rule:SetPoint("TOPLEFT", PAD, -(y + 4))
    ui.rule:SetPoint("TOPRIGHT", -PAD, -(y + 4))
    ui.rule:Show()
    y = y + SECTION_GAP
    if #plan.steps > 0 then
        y = place(ui, ui.stepsHeader, y, LINE_HEIGHT + 4)
    end
    local reserve = #plan.reagents > 0 and LINE_HEIGHT * 2 + REAGENT_HEIGHT * 2 or 0
    local shown
    y, shown = steps(ui, plan, data, y, limit - reserve, STEP_POOL)
    if shown < #plan.steps then
        ui.moreSteps:SetText(string.format(L.PLANNER_MORE_STEPS, #plan.steps - shown))
        y = place(ui, ui.moreSteps, y, LINE_HEIGHT, PAD + ROW_PAD)
    end
    if atCap then
        ui.gap:SetText(string.format(L.PLANNER_AT_CAP, data.cap))
        y = place(ui, ui.gap, y + 4, textHeight(ui.gap))
    elseif plan.reached < data.cap then
        local candidates = plan.candidates
        ui.gap:SetText(string.format(#candidates > 0 and L.PLANNER_GAP or L.PLANNER_GAP_NONE, plan.reached))
        y = place(ui, ui.gap, y + 4, textHeight(ui.gap))
        for index, entry in ipairs(candidates) do
            if index > CANDIDATE_POOL or y + STEP_HEIGHT > limit - reserve then break end
            fillCandidate(ui.candidates[index], entry)
            y = place(ui, ui.candidates[index], y, STEP_HEIGHT)
        end
    end
    if #plan.reagents == 0 then
        panel:Show()
        return
    end
    y = place(ui, ui.reagentsHeader, y + SECTION_GAP, LINE_HEIGHT + 4)
    local placed = 0
    for index, reagent in ipairs(plan.reagents) do
        if index > REAGENT_POOL or y + REAGENT_HEIGHT > limit - LINE_HEIGHT then break end
        fillReagent(ui.reagents[index], reagent)
        y = place(ui, ui.reagents[index], y, REAGENT_HEIGHT)
        placed = index
    end
    if placed < #plan.reagents then
        ui.moreReagents:SetText(string.format(L.PLANNER_MORE_REAGENTS, #plan.reagents - placed))
        place(ui, ui.moreReagents, y, LINE_HEIGHT, PAD + ROW_PAD)
    end
    panel:Show()
end
