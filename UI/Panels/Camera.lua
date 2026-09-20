local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme, Profiles = R.Theme, R.CameraProfiles

local CONTROL_WIDTH, BOX_STEP, DROPDOWN_STEP, NOTE_HEIGHT = 380, 32, 36, 30
local SLIDER_STEP = LibStub("LibRefactorTheme-1.0").sliderRowHeight + 6
local DEFAULT_SITUATION = "indoors"

local SITUATION_ENTRIES = {}
for index, situation in ipairs(Profiles.situations) do
    SITUATION_ENTRIES[index] = { value = situation, labelKey = "UI_CAMERA_SITUATION_" .. situation:upper() }
end

-- A distance slider's leftmost stop sits one below the smallest real distance and means
-- the profile leaves the camera alone; the profile stores that as its LEAVE value.
local LEAVE_STOP_OFFSET = 1

local function yardsText(value)
    return string.format(L.UI_CAMERA_YARDS, value)
end

local function distanceText(value, minimum)
    if value < minimum then
        return L.UI_CAMERA_LEAVE
    end
    return yardsText(value)
end

-- A shoulder offset is a side before it is a number, so the sign is spelled out.
local function shoulderText(value)
    if value > 0.05 then
        return string.format(L.UI_CAMERA_RIGHT, value)
    elseif value < -0.05 then
        return string.format(L.UI_CAMERA_LEFT, -value)
    end
    return L.UI_CAMERA_CENTRED
end

local function swayText(value)
    if value < 0.05 then
        return L.UI_CAMERA_OFF
    end
    return string.format(L.UI_CAMERA_PERCENT, math.floor(value * 100 + 0.5))
end

-- The base fields, then the two a situation carries. suffix marks the ones whose field
-- depends on which situation the dropdown is showing.
local BASE_DISTANCE = { key = "distance", labelKey = "UI_CAMERA_DISTANCE" }
local BASE_SHOULDER = { key = "shoulder", labelKey = "UI_CAMERA_SHOULDER", formatter = shoulderText }
local BASE_SWAY = { key = "headBob", labelKey = "UI_CAMERA_HEAD_BOB", formatter = swayText }
local BASE_PULL = { key = "targetPull", labelKey = "UI_CAMERA_TARGET_PULL", formatter = swayText }
local SITUATION_DISTANCE = { suffix = "Distance", labelKey = "UI_CAMERA_SITUATION_DISTANCE" }
local SITUATION_SHOULDER = { suffix = "Shoulder", labelKey = "UI_CAMERA_SITUATION_SHOULDER",
    formatter = shoulderText }
local BOXES = {
    { key = "pitch", labelKey = "UI_CAMERA_PITCH" },
    { key = "focusInteract", labelKey = "UI_CAMERA_FOCUS_INTERACT" },
}

local function fieldFor(spec, situation)
    return spec.key or (situation .. spec.suffix)
end

local function fieldRange(key)
    for _, field in ipairs(Profiles.fields) do
        if field.key == key then return field end
    end
    return nil
end

-- A slider's own value is a float from a track; the profile stores it back on its step so
-- 0.6 is 0.6 and not the tail a drag left on it. Dividing by the whole-number scale rather
-- than multiplying by the step is what lands on the same double the literal would.
local function onStep(value, step)
    local scale = math.floor(1 / step + 0.5)
    return math.floor(value * scale + 0.5) / scale
end

local function setSliderEnabled(slider, enabled)
    slider.slider:SetEnabled(enabled)
    slider.back:SetEnabled(enabled)
    slider.forward:SetEnabled(enabled)
    Theme:Color(slider.label, enabled and "TEXT_BODY" or "TEXT_MUTED", true)
end

-- A slider over one field of the active profile. Not one of the account option sliders:
-- what it writes is a number inside a profile, so there is no default for it to undo to.
function UI:CameraSlider(block, spec, y)
    local range = fieldRange(fieldFor(spec, DEFAULT_SITUATION))
    local distance = range.kind == "distance"
    local low = distance and range.minimum - LEAVE_STOP_OFFSET or range.minimum
    local slider = Theme:Slider(block, CONTROL_WIDTH, low, range.maximum, range.step,
        function(value)
            value = onStep(value, range.step)
            if distance and value < range.minimum then value = Profiles.LEAVE end
            if not Profiles:SetField(fieldFor(spec, self.cameraSituation), value) then
                self:LoadCamera()
            end
        end)
    slider:SetPoint("TOPLEFT", 0, y)
    slider:SetLabel(L[spec.labelKey], spec.formatter
        or function(value) return distanceText(value, range.minimum) end)
    slider.spec, slider.range = spec, range
    block:Index(L[spec.labelKey])
    self.cameraSliders[#self.cameraSliders + 1] = slider
    return slider
end

function UI:CameraCheckbox(block, spec, y)
    local box = Theme:Checkbox(block, 300, L[spec.labelKey], function(widget)
        if not Profiles:SetField(spec.key, widget:GetChecked() == true) then
            self:LoadCamera()
        end
    end)
    box:SetPoint("TOPLEFT", 0, y)
    box.fieldKey = spec.key
    block:Index(L[spec.labelKey])
    self.cameraBoxes[#self.cameraBoxes + 1] = box
    return box
end

local function statusText(ok, okText, err)
    if ok then return okText end
    return L["UI_CAMERA_ERR_" .. tostring(err)] or L.UI_CAMERA_ERR_invalid_profile
end

-- The settings block behind the ActionCam row: a profile to pick, its numbers, and the
-- copy, delete, export and import that make a profile the player's own.
function UI:BuildCameraSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_CAMERA_HELP)
    local top = block.top
    self.cameraSliders, self.cameraBoxes, self.cameraSituation = {}, {}, DEFAULT_SITUATION
    for _, profile in ipairs(Profiles.builtIn) do
        block:Index(L[profile.nameKey])
    end
    block:Index(L.UI_CAMERA_PROFILE, L.UI_CAMERA_SITUATION, L.UI_CAMERA_SHARE)

    self.cameraProfileDropdown = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return Settings:GetOption("cameraProfile") == value end,
        function(value)
            Profiles:Select(value)
            self:LoadCamera()
        end)
    self.cameraProfileDropdown:SetPoint("TOPLEFT", 0, top)
    self.cameraProfileDropdown:SetLabel(L.UI_CAMERA_PROFILE)
    self.cameraDetail = Theme:Text(block, "", "small", "TEXT_MUTED")
    self.cameraDetail:SetPoint("TOPLEFT", 0, top - DROPDOWN_STEP)
    self.cameraDetail:SetPoint("RIGHT")
    self.cameraDetail:SetHeight(NOTE_HEIGHT)
    self.cameraDetail:SetJustifyV("TOP")

    local y = top - DROPDOWN_STEP - NOTE_HEIGHT - 6
    self:CameraSlider(block, BASE_DISTANCE, y)
    self:CameraSlider(block, BASE_SHOULDER, y - SLIDER_STEP)
    self:CameraSlider(block, BASE_SWAY, y - SLIDER_STEP * 2)
    self:CameraSlider(block, BASE_PULL, y - SLIDER_STEP * 3)
    y = y - SLIDER_STEP * 4
    for index, spec in ipairs(BOXES) do
        self:CameraCheckbox(block, spec, y - (index - 1) * BOX_STEP)
    end
    y = y - #BOXES * BOX_STEP - 4

    self.cameraSituationDropdown = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return self.cameraSituation == value end,
        function(value)
            self.cameraSituation = value
            self:LoadCamera()
        end)
    self.cameraSituationDropdown:SetPoint("TOPLEFT", 0, y)
    self.cameraSituationDropdown:SetLabel(L.UI_CAMERA_SITUATION)
    local situationHelp = Theme:Text(block, L.UI_CAMERA_SITUATION_HELP, "small", "TEXT_MUTED")
    situationHelp:SetPoint("TOPLEFT", 0, y - DROPDOWN_STEP)
    situationHelp:SetPoint("RIGHT")
    block:Index(L.UI_CAMERA_SITUATION_HELP)
    local situations = {}
    for index, entry in ipairs(SITUATION_ENTRIES) do
        situations[index] = { value = entry.value, text = L[entry.labelKey] }
        block:Index(L[entry.labelKey])
    end
    self.cameraSituationDropdown:SetEntries(situations)
    self.cameraSituationEntries = situations
    y = y - DROPDOWN_STEP - 18
    self:CameraSlider(block, SITUATION_DISTANCE, y)
    self:CameraSlider(block, SITUATION_SHOULDER, y - SLIDER_STEP)
    y = y - SLIDER_STEP * 2 - 4

    local copyLabel = Theme:Text(block, L.UI_CAMERA_COPY_HELP, "small", "TEXT_MUTED")
    copyLabel:SetPoint("TOPLEFT", 0, y)
    copyLabel:SetPoint("RIGHT")
    block:Index(L.UI_CAMERA_COPY_HELP)
    self.cameraName = self.Widgets:Input(block, 200, 26)
    self.cameraName:SetPoint("TOPLEFT", 0, y - 16)
    local saveCopy = Theme:Button(block, 104, L.UI_CAMERA_SAVE_COPY, function()
        local name = self.cameraName:GetText()
        if name == "" then
            self.cameraStatus:SetText(L.UI_CAMERA_NAME_MISSING)
            return
        end
        local active = Profiles:Active()
        local ok, result = Profiles:SaveCopy(name, active and active.values or {})
        self:LoadCamera()
        self.cameraStatus:SetText(statusText(ok, ok and string.format(L.UI_CAMERA_SAVED, result), result))
        if ok then self.cameraName:SetText("") end
        self.cameraName:ClearFocus()
    end)
    saveCopy:SetPoint("LEFT", self.cameraName, "RIGHT", 8, 0)
    self.cameraSaveCopy = saveCopy
    self.cameraDelete = Theme:Button(block, 92, L.UI_CAMERA_DELETE, function()
        local active = Profiles:Active()
        if active and not active.builtIn and Profiles:Delete(active.name) then
            self:LoadCamera()
            self.cameraStatus:SetText(L.UI_CAMERA_DELETED)
        end
    end)
    self.cameraDelete:SetPoint("LEFT", saveCopy, "RIGHT", 6, 0)
    y = y - 16 - 26 - 12

    local shareLabel = Theme:Text(block, L.UI_CAMERA_SHARE, "small", "TEXT_MUTED")
    shareLabel:SetPoint("TOPLEFT", 0, y)
    shareLabel:SetPoint("RIGHT")
    self.cameraString = self.Widgets:Input(block, 200, 54, true)
    self.cameraString:SetPoint("TOPLEFT", 0, y - 16)
    local export = Theme:Button(block, 104, L.UI_CAMERA_EXPORT, function()
        local encoded, err = Profiles:Export(Settings:GetOption("cameraProfile"))
        self.cameraString:SetText(encoded or "")
        if encoded then self.cameraString:SetFocus() end
        self.cameraStatus:SetText(statusText(encoded ~= nil, L.UI_CAMERA_EXPORTED, err))
    end)
    export:SetPoint("TOPLEFT", self.cameraString, "TOPRIGHT", 8, 0)
    self.cameraExport = export
    local import = Theme:Button(block, 104, L.UI_CAMERA_IMPORT, function()
        local ok, result = Profiles:Import(self.cameraString:GetText())
        self:LoadCamera()
        self.cameraStatus:SetText(statusText(ok, ok and string.format(L.UI_CAMERA_IMPORTED, result), result))
        if ok then self.cameraString:SetText("") end
        self.cameraString:ClearFocus()
    end)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    self.cameraImport = import
    y = y - 16 - 54 - 10

    self.cameraStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    self.cameraStatus:SetPoint("TOPLEFT", 0, y)
    self.cameraStatus:SetPoint("RIGHT")
    block:SetBodyHeight(top - y + 20)
    self:RegisterModuleSettings("interface.actionCam", block)
end

function UI:LoadCamera()
    if not self.cameraProfileDropdown then return end
    local active = Profiles:Active()
    if not active then return end
    local entries = {}
    for _, profile in ipairs(Profiles.builtIn) do
        entries[#entries + 1] = { value = profile.id, text = L[profile.nameKey] }
    end
    local names = {}
    for name in pairs(Settings:GetOption("cameraProfiles") or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        entries[#entries + 1] = { value = Profiles.customPrefix .. name, text = name }
    end
    self.cameraProfileDropdown:SetEntries(entries)
    self.cameraProfileDropdown:SetValueText(active.name or L[active.nameKey])
    self.cameraDetail:SetText(active.builtIn and (L[active.detailKey] .. " " .. L.UI_CAMERA_BUILT_IN)
        or L.CAMERA_PROFILE_CUSTOM_DETAIL)
    local editable = not active.builtIn
    for _, slider in ipairs(self.cameraSliders) do
        local value, range = active.values[fieldFor(slider.spec, self.cameraSituation)], slider.range
        if range.kind == "distance" and value == Profiles.LEAVE then
            value = range.minimum - LEAVE_STOP_OFFSET
        end
        slider:SetValue(value)
        setSliderEnabled(slider, editable)
    end
    for _, box in ipairs(self.cameraBoxes) do
        box:SetChecked(active.values[box.fieldKey] == true)
        box:SetEnabled(editable)
        Theme:Color(box.label, editable and "TEXT_BODY" or "TEXT_MUTED", true)
    end
    for _, entry in ipairs(self.cameraSituationEntries) do
        if entry.value == self.cameraSituation then
            self.cameraSituationDropdown:SetValueText(entry.text)
        end
    end
    self.cameraDelete:SetEnabled(editable)
    self.cameraStatus:SetText("")
end
