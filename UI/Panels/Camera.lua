local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme, Profiles = R.Theme, R.CameraProfiles

local CONTROL_WIDTH, SLIDER_GAP, DROPDOWN_GAP = 380, 6, 6
-- A checkbox now sits between sliders, whose labels need the same air above them a slider leaves.
local CHECKBOX_GAP = 10
-- The button beside the profile dropdown, the share string box, its two buttons and the
-- line that reports what the last press did.
local ACTION_WIDTH, STRING_WIDTH, STRING_HEIGHT, SAVE_WIDTH, STATUS_HEIGHT = 104, 380, 54, 104, 14
local DEFAULT_SITUATION = "indoors"
local unpack = unpack

local SITUATION_ENTRIES = {}
for index, situation in ipairs(Profiles.situations) do
    SITUATION_ENTRIES[index] = { value = situation, labelKey = "UI_CAMERA_SITUATION_" .. situation:upper() }
end

-- A distance slider's leftmost stop sits one below the smallest real distance and means
-- the profile leaves the camera alone; the profile stores that as its LEAVE value.
local LEAVE_STOP_OFFSET = 1

-- Stored as the factor the CVar takes; the slider works in hundredths so a step never
-- lands on a value that cannot be written back exactly.
local function zoomText(value)
    return string.format(L.UI_CAMERA_ZOOM_FACTOR, value / 100)
end

local MAX_ZOOM = { key = "cameraMaxZoom", minimum = 100, maximum = 260, step = 10,
    labelKey = "UI_CAMERA_MAX_ZOOM", formatter = zoomText,
    show = function(stored) return math.floor((stored or 2.6) * 100 + 0.5) end,
    store = function(value) return value / 100 end }

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
local BASE_TILT = { key = "tilt", labelKey = "UI_CAMERA_TILT", formatter = swayText }
local SITUATION_DISTANCE = { suffix = "Distance", labelKey = "UI_CAMERA_SITUATION_DISTANCE" }
local SITUATION_SHOULDER = { suffix = "Shoulder", labelKey = "UI_CAMERA_SITUATION_SHOULDER",
    formatter = shoulderText }
local SWAY_MOVING_BOX = { key = "swayWhileMoving", labelKey = "UI_CAMERA_SWAY_MOVING" }
local FOCUS_BOX = { key = "focusInteract", labelKey = "UI_CAMERA_FOCUS_INTERACT" }

-- The situation distance reads as the way it moves the camera: indoors only ever brings it
-- in, a mount only ever backs it off. The leftmost stop is still "leave it".
local function directionalDistanceText(value)
    if value < Profiles.distanceMinimum then
        return L.UI_CAMERA_LEAVE
    end
    local direction = Profiles.directions[UI.cameraSituation]
    return string.format(direction == "in" and L.UI_CAMERA_COMES_IN or L.UI_CAMERA_BACKS_OFF, value)
end
SITUATION_DISTANCE.formatter = directionalDistanceText

local function entryText(situation, values)
    local distance = values[situation .. "Distance"]
    if distance == Profiles.LEAVE then
        distance = L.UI_CAMERA_LEAVE
    else
        distance = string.format(Profiles.directions[situation] == "in" and L.UI_CAMERA_AT_MOST
            or L.UI_CAMERA_AT_LEAST, distance)
    end
    return string.format(L.UI_CAMERA_ENTRY, L["UI_CAMERA_SITUATION_" .. situation:upper()], distance,
        shoulderText(values[situation .. "Shoulder"]))
end

-- What the module last reported, copied because it reuses its table. Nothing is known
-- until the first event, which reads the same as off.
local function nowText(status)
    if not status.active then
        return L.UI_CAMERA_NOW_OFF
    elseif status.preset then
        return L.UI_CAMERA_NOW_PRESET
    elseif not status.situation then
        return L.UI_CAMERA_NOW_NOWHERE
    end
    local parts = { L["UI_CAMERA_NOW_" .. status.situation:upper()] }
    if status.target then
        local text = string.format(status.direction == "in" and L.UI_CAMERA_COMING_IN
            or L.UI_CAMERA_BACKING_OFF, status.target)
        parts[#parts + 1] = status.learned and string.format(L.UI_CAMERA_FROM_WHEEL, text) or text
    else
        parts[#parts + 1] = L.UI_CAMERA_YOUR_DISTANCE
    end
    if status.shoulder then
        parts[#parts + 1] = shoulderText(status.shoulder)
    end
    return string.format(L.UI_CAMERA_NOW, table.concat(parts, ", "))
end

-- Reduce Unexpected Camera Movement cancels the shoulder offset, which reads as the profile
-- doing nothing, so the status says so while it is on.
local function warningSuffix(status)
    if not (status.active and status.reduceMovement) then
        return ""
    end
    return "\n|c" .. Theme:Hex("TEXT_WARNING") .. L.UI_CAMERA_REDUCE_WARNING .. "|r"
end

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
function UI:CameraSlider(block, spec)
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
    block:Place(slider, Theme.sliderRowHeight, SLIDER_GAP)
    slider:SetLabel(L[spec.labelKey], spec.formatter
        or function(value) return distanceText(value, range.minimum) end)
    slider.spec, slider.range = spec, range
    block:Index(L[spec.labelKey])
    self.cameraSliders[#self.cameraSliders + 1] = slider
    return slider
end

function UI:CameraCheckbox(block, spec)
    local box = Theme:Checkbox(block, CONTROL_WIDTH, L[spec.labelKey], function(widget)
        if not Profiles:SetField(spec.key, widget:GetChecked() == true) then
            self:LoadCamera()
        end
    end)
    block:Place(box, Theme.checkboxSize, CHECKBOX_GAP)
    box.fieldKey = spec.key
    block:Index(L[spec.labelKey])
    self.cameraBoxes[#self.cameraBoxes + 1] = box
    return box
end

local function statusText(ok, okText, err)
    if ok then return okText end
    return L["UI_CAMERA_ERR_" .. tostring(err)] or L.UI_CAMERA_ERR_invalid_profile
end

-- A built-in profile is edited by copying it: one click makes "My Immersive", selects it
-- and unlocks the sliders. Typing a name before being allowed to move a slider was the
-- step every player had to discover first.
function UI:CustomizeCamera()
    local active = Profiles:Active()
    if not active or not active.builtIn then return end
    local base = L[active.nameKey] or active.name or ""
    local custom = Settings:GetOption("cameraProfiles") or {}
    local name, index = string.format(L.UI_CAMERA_COPY_NAME, base), 2
    while custom[name] do
        name = string.format(L.UI_CAMERA_COPY_NAME_N, base, index)
        index = index + 1
    end
    local ok, result = Profiles:SaveCopy(name, active.values)
    self:LoadCamera()
    self.cameraStatus:SetText(statusText(ok, ok and string.format(L.UI_CAMERA_SAVED, result), result))
end

-- The settings block behind the ActionCam row: a profile to pick, its numbers, and the
-- copy, delete, export and import that make a profile the player's own.
function UI:BuildCameraSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_CAMERA_HELP)
    self.cameraSliders, self.cameraBoxes, self.cameraSituation = {}, {}, DEFAULT_SITUATION
    self.cameraNowStatus = { active = false }
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
    block:Place(self.cameraProfileDropdown, Theme.dropdownRowHeight, DROPDOWN_GAP)
    self.cameraProfileDropdown:SetLabel(L.UI_CAMERA_PROFILE)
    -- One slot beside the profile: Customize for a built-in, Delete for one of your own.
    self.cameraCustomize = Theme:Button(block, ACTION_WIDTH, L.UI_CAMERA_CUSTOMIZE, function()
        self:CustomizeCamera()
    end)
    self.cameraCustomize:SetPoint("LEFT", self.cameraProfileDropdown, "RIGHT", 8, 0)
    self.cameraDelete = Theme:Button(block, ACTION_WIDTH, L.UI_CAMERA_DELETE, function()
        local active = Profiles:Active()
        if active and not active.builtIn and Profiles:Delete(active.name) then
            self:LoadCamera()
            self.cameraStatus:SetText(L.UI_CAMERA_DELETED)
        end
    end)
    self.cameraDelete:SetPoint("LEFT", self.cameraProfileDropdown, "RIGHT", 8, 0)
    local details = { L.CAMERA_PROFILE_CUSTOM_DETAIL }
    for _, profile in ipairs(Profiles.builtIn) do
        details[#details + 1] = L[profile.detailKey] .. " " .. L.UI_CAMERA_BUILT_IN
    end
    self.cameraDetail = block:Note(nil, unpack(details))

    -- One note for the status and, under it, the Accessibility warning in the warning colour:
    -- blocks are laid out once, so it is sized for the longest status plus the warning, and a
    -- second note would hold a gap of its own whenever the warning is not showing.
    local longest = { active = true, situation = "battleground", target = 30, direction = "out",
        learned = true, shoulder = -2, reduceMovement = true }
    self.cameraNow = block:Note(nil, nowText(longest) .. warningSuffix(longest))
    Theme:Color(self.cameraNow, "TEXT_BODY", true)
    self:ShowCameraNow()
    R.Broker:Subscribe("REFACTOR_CAMERA_SITUATION", self.OnCameraSituation, self)

    block:Group(L.UI_CAMERA_EVERYWHERE)
    self:CameraSlider(block, BASE_DISTANCE)
    self:CameraSlider(block, BASE_SHOULDER)
    self:CameraSlider(block, BASE_SWAY)
    self:CameraCheckbox(block, SWAY_MOVING_BOX)
    self:CameraSlider(block, BASE_TILT)
    self:CameraSlider(block, BASE_PULL)
    self:CameraCheckbox(block, FOCUS_BOX)

    block:Group(L.UI_CAMERA_SITUATIONS)
    self.cameraSituationDropdown = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return self.cameraSituation == value end,
        function(value)
            self.cameraSituation = value
            self:LoadCamera()
        end)
    block:Place(self.cameraSituationDropdown, Theme.dropdownRowHeight, DROPDOWN_GAP)
    self.cameraSituationDropdown:SetLabel(L.UI_CAMERA_SITUATION)
    block:Note(L.UI_CAMERA_SITUATION_HELP)
    self:OptionCheckbox(block, "cameraLearnZoom", "UI_CAMERA_LEARN")
    block:Note(L.UI_CAMERA_LEARN_NOTE)
    local situations = {}
    for index, entry in ipairs(SITUATION_ENTRIES) do
        situations[index] = { value = entry.value, text = L[entry.labelKey] }
        block:Index(L[entry.labelKey])
    end
    self.cameraSituationDropdown:SetEntries(situations)
    self.cameraSituationEntries = situations
    self:CameraSlider(block, SITUATION_DISTANCE)
    self:CameraSlider(block, SITUATION_SHOULDER)

    block:Group(L.UI_CAMERA_SHARE)
    self.cameraString = self.Widgets:Input(block, STRING_WIDTH, STRING_HEIGHT, true)
    block:Place(self.cameraString, STRING_HEIGHT, self.Widgets.NOTE_GAP)
    local export = Theme:Button(block, SAVE_WIDTH, L.UI_CAMERA_EXPORT, function()
        local encoded, err = Profiles:Export(Settings:GetOption("cameraProfile"))
        self.cameraString:SetText(encoded or "")
        if encoded then self.cameraString:SetFocus() end
        self.cameraStatus:SetText(statusText(encoded ~= nil, L.UI_CAMERA_EXPORTED, err))
    end)
    export:SetPoint("TOPLEFT", self.cameraString, "TOPRIGHT", 8, 0)
    self.cameraExport = export
    local import = Theme:Button(block, SAVE_WIDTH, L.UI_CAMERA_IMPORT, function()
        local ok, result = Profiles:Import(self.cameraString:GetText())
        self:LoadCamera()
        self.cameraStatus:SetText(statusText(ok, ok and string.format(L.UI_CAMERA_IMPORTED, result), result))
        if ok then self.cameraString:SetText("") end
        self.cameraString:ClearFocus()
    end)
    import:SetPoint("TOPLEFT", export, "BOTTOMLEFT", 0, -6)
    self.cameraImport = import
    self.cameraStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    block:Place(self.cameraStatus, STATUS_HEIGHT)
    self.cameraStatus:SetPoint("RIGHT")
    block:Finish()
    self:RegisterModuleSettings("interface.actionCam", block)
end

function UI:ShowCameraNow()
    local status = self.cameraNowStatus
    self.cameraNow:SetText(nowText(status) .. warningSuffix(status))
end

function UI:OnCameraSituation(_, status)
    local mine = self.cameraNowStatus
    for key in pairs(mine) do
        mine[key] = nil
    end
    if status then
        mine.active, mine.preset, mine.situation = status.active == true, status.preset, status.situation
        mine.target, mine.direction, mine.learned = status.target, status.direction, status.learned
        mine.shoulder, mine.reduceMovement = status.shoulder, status.reduceMovement
    else
        mine.active = false
    end
    self:ShowCameraNow()
end

-- Called when the block is opened and only then: a drag in progress must never find the
-- situation it writes to changed under it by the player walking indoors.
function UI:FollowCameraSituation()
    local situation = self.cameraNowStatus and self.cameraNowStatus.situation
    if situation and self.cameraSituationDropdown then
        self.cameraSituation = situation
        self:LoadCamera()
    end
end

-- The maximum camera distance feature is one number, so its whole panel is one slider.
function UI:BuildCameraDistanceSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_CAMERA_DISTANCE_HELP)
    self.cameraZoomSlider = self:OptionSlider(block, MAX_ZOOM)
    block:Finish()
    self:RegisterModuleSettings("interface.cameraDistance", block)
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
    local situations = {}
    for index, entry in ipairs(SITUATION_ENTRIES) do
        situations[index] = { value = entry.value, text = entryText(entry.value, active.values) }
        if entry.value == self.cameraSituation then
            self.cameraSituationDropdown:SetValueText(L[entry.labelKey])
        end
    end
    self.cameraSituationDropdown:SetEntries(situations)
    self.cameraSituationEntries = situations
    self.cameraCustomize:SetShown(not editable)
    self.cameraDelete:SetShown(editable)
    self.cameraStatus:SetText("")
end
