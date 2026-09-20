local _, R = ...
local UI, L = R.UI, R.L
local Theme, Rules = R.Theme, R.Visibility

local CONTROL_WIDTH, DROPDOWN_STEP, NOTE_HEIGHT = 380, 36, 30
local MODULE_ID = "interface.visibility"

-- The settings block behind the UI visibility row: the preset, and where the rest lives.
-- Per-element tuning happens in Edit Mode, beside Blizzard's own dialog for that element.
function UI:BuildVisibilitySettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_VIS_HELP)
    local top = block.top
    for _, preset in ipairs(Rules.presets) do
        block:Index(L[preset.nameKey])
    end
    block:Index(L.UI_VIS_PRESET, L.VIS_PRESET_CUSTOM)
    local entries = {}
    for index, preset in ipairs(Rules.presets) do
        entries[index] = { value = preset.id, text = L[preset.nameKey] }
    end
    self.visPresetDropdown = Theme:Dropdown(block, CONTROL_WIDTH, entries,
        function(value) return Rules:Settings().preset == value end,
        function(value)
            Rules:ApplyPreset(value)
            self:LoadVisibility()
        end)
    self.visPresetDropdown:SetPoint("TOPLEFT", 0, top)
    self.visPresetDropdown:SetLabel(L.UI_VIS_PRESET)
    self.visPresetDetail = Theme:Text(block, "", "small", "TEXT_MUTED")
    self.visPresetDetail:SetPoint("TOPLEFT", 0, top - DROPDOWN_STEP)
    self.visPresetDetail:SetPoint("RIGHT")
    self.visPresetDetail:SetHeight(NOTE_HEIGHT)
    self.visPresetDetail:SetJustifyV("TOP")
    block:SetBodyHeight(-(top - DROPDOWN_STEP - NOTE_HEIGHT) + 8)
    self:RegisterModuleSettings(MODULE_ID, block)
end

function UI:LoadVisibility()
    if not self.visPresetDropdown then
        return
    end
    local preset = Rules:Preset(Rules:Settings().preset)
    self.visPresetDropdown:SetValueText(preset and L[preset.nameKey] or L.VIS_PRESET_CUSTOM)
    self.visPresetDetail:SetText(preset and L[preset.detailKey] or L.VIS_PRESET_CUSTOM_DETAIL)
    if self.visCompanion then
        self.visCompanion:Load()
    end
end
