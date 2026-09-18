local _, R = ...
local UI, L = R.UI, R.L
local Theme = R.Theme

local CHOICES = { "minimal", "standard", "full" }
local LABEL_KEYS = { minimal = "UI_PRESET_MINIMAL", standard = "UI_PRESET_STANDARD", full = "UI_PRESET_FULL" }
local DETAIL_KEYS = {
    minimal = "UI_PRESET_MINIMAL_DETAIL",
    standard = "UI_PRESET_STANDARD_DETAIL",
    full = "UI_PRESET_FULL_DETAIL",
}

-- One screen, not a wizard (PRD 6.1). The choice writes account defaults, so it is asked
-- once per account and every later character inherits it without a click.
function UI:BuildFirstRun()
    if self.firstRunFrame then
        return self.firstRunFrame
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(560, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    Theme:Panel(frame)
    local title = Theme:Text(frame, L.UI_TITLE, "title", "TEXT_TITLE")
    title:SetPoint("TOPLEFT", 28, -28)
    local intro = Theme:Text(frame, L.UI_FIRST_RUN_INTRO, "body", "TEXT_BODY")
    intro:SetPoint("TOPLEFT", 28, -62)
    intro:SetPoint("RIGHT", -28, 0)
    intro:SetHeight(40)
    intro:SetJustifyV("TOP")

    local function choose(preset)
        R.Presets:Apply(preset)
        R.Registry:ReconcileAll()
        frame:Hide()
        if preset == nil then
            self:Toggle()
        end
    end

    frame.rows = {}
    for index, preset in ipairs(CHOICES) do
        local button = Theme:Button(frame, 200, "", function() choose(preset) end)
        button:SetPoint("TOPLEFT", 28, -118 - (index - 1) * 74)
        local detail = Theme:Text(frame, L[DETAIL_KEYS[preset]], "small", "TEXT_MUTED")
        detail:SetPoint("TOPLEFT", 240, -118 - (index - 1) * 74)
        detail:SetPoint("RIGHT", -28, 0)
        detail:SetHeight(54)
        detail:SetJustifyV("TOP")
        frame.rows[index] = { preset = preset, button = button }
    end
    local browse = Theme:Button(frame, 200, L.UI_PRESET_BROWSE, function() choose(nil) end)
    browse:SetPoint("BOTTOMLEFT", 28, 28)
    local note = Theme:Text(frame, L.UI_FIRST_RUN_NOTE, "small", "TEXT_MUTED")
    note:SetPoint("LEFT", browse, "RIGHT", 16, 0)
    note:SetPoint("RIGHT", -28, 0)
    frame:Hide()
    self.firstRunFrame = frame
    return frame
end

function UI:ShowFirstRun()
    if not R.Settings:IsFirstRun() then
        return false
    end
    local frame = self:BuildFirstRun()
    for _, row in ipairs(frame.rows) do
        row.button.label:SetText(string.format(L.UI_PRESET_COUNT, L[LABEL_KEYS[row.preset]],
            R.Presets:Count(row.preset)))
    end
    frame:Show()
    return true
end
