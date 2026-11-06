local _, R = ...
local UI, L = R.UI, R.L
local Theme, Rules, Conditions = R.Theme, R.Visibility, R.Conditions

local CONTROL_WIDTH, DROPDOWN_GAP, SLIDER_GAP, CHECKBOX_GAP, ROW_GAP = 380, 6, 6, 10, 2
-- The button beside the behaviour picker and beside its name, the name box, a small label
-- over a list, and the line that reports what the last press did.
local ACTION_WIDTH, NAME_HEIGHT, LABEL_HEIGHT, STATUS_HEIGHT = 104, 26, 16, 14
-- One line per condition: its name, then a Reveal and a Hide box in two columns, so each
-- condition is listed once and can only do one of the two.
local REVEAL_X, HIDE_X, COLUMN_BOX = 240, 320, 40
local MODULE_ID = "interface.visibility"
-- A picker's value for "no behaviour". A behaviour id starts with a letter, so it can never be this.
local NONE = ""
local unpack = unpack

local function onStep(value, step)
    local scale = math.floor(1 / step + 0.5)
    return math.floor(value * scale + 0.5) / scale
end

local function percentText(value)
    return string.format(L.UI_VIS_PERCENT, math.floor(value * 100 + 0.5))
end

local function secondsText(value)
    if value < 0.025 then
        return L.UI_VIS_INSTANT
    end
    return string.format(L.UI_VIS_SECONDS, value)
end

local function setSliderEnabled(slider, enabled)
    slider.slider:SetEnabled(enabled)
    slider.back:SetEnabled(enabled)
    slider.forward:SetEnabled(enabled)
    Theme:Color(slider.label, enabled and "TEXT_BODY" or "TEXT_MUTED", true)
end

local function setBoxEnabled(box, enabled)
    box:SetEnabled(enabled)
    Theme:Color(box.label, enabled and "TEXT_BODY" or "TEXT_MUTED", true)
end

local function errorText(err)
    return L["UI_VIS_ERR_" .. tostring(err)] or ""
end

-- What the note under the setup picker says: which setup this is, then which one is in use
-- where the player stands, when the feature is on and so knows.
local function setupNote(place, own, now)
    local text = place == Rules.world and L.UI_VIS_SETUP_WORLD or own and L.UI_VIS_SETUP_OWN
        or L.UI_VIS_SETUP_FOLLOWS
    if now then
        text = text .. " " .. string.format(L.UI_VIS_SETUP_NOW, L["VIS_PLACE_" .. now])
    end
    return text
end

local function usesText(entry)
    if not entry then
        return L.UI_VIS_NONE_YET
    end
    local uses = Rules:Uses(entry.id)
    if uses == 0 then
        return L.UI_VIS_USES_NONE
    elseif uses == 1 then
        return L.UI_VIS_USES_ONE
    end
    return string.format(L.UI_VIS_USES, uses)
end

function UI:VisSetupInUse()
    local module = R.moduleByID and R.moduleByID[MODULE_ID]
    return module and module.state == "enabled" and module.place or nil
end

function UI:VisAssigned(groupId)
    local behaviour = Rules:BehaviourFor(groupId, self.visPlace)
    return behaviour and behaviour.id or NONE
end

-- A slider over one field of the behaviour being edited. A refused write puts the slider
-- back where the saved value is.
function UI:VisSlider(block, labelKey, field, range, formatter)
    local slider = Theme:Slider(block, CONTROL_WIDTH, range.minimum, range.maximum, range.step, function(value)
        local id = self.visBehaviour
        if not (id and Rules:UpdateBehaviour(id, { [field] = onStep(value, range.step) })) then
            self:LoadVisibility()
        end
    end)
    block:Place(slider, Theme.sliderRowHeight, SLIDER_GAP)
    slider:SetLabel(L[labelKey], formatter)
    slider.field, slider.range = field, range
    block:Index(L[labelKey])
    self.visSliders[#self.visSliders + 1] = slider
    return slider
end

function UI:VisCheckbox(block, labelKey, field)
    local box = Theme:Checkbox(block, CONTROL_WIDTH, L[labelKey], function(widget)
        local id = self.visBehaviour
        if not (id and Rules:UpdateBehaviour(id, { [field] = widget:GetChecked() == true })) then
            self:LoadVisibility()
        end
    end)
    block:Place(box, Theme.checkboxSize, CHECKBOX_GAP)
    box.field = field
    block:Index(L[labelKey])
    self.visBoxes[#self.visBoxes + 1] = box
    return box
end

function UI:VisCondition(condition, role)
    if self.visBehaviour then
        Rules:SetCondition(self.visBehaviour, condition, role)
    end
    self:LoadVisibility()
end

function UI:VisConditionRows(block)
    local header = CreateFrame("Frame", nil, block)
    header:SetSize(CONTROL_WIDTH, LABEL_HEIGHT)
    local when = Theme:Text(header, L.UI_VIS_CONDITIONS, "small", "TEXT_MUTED")
    when:SetPoint("LEFT")
    for _, column in ipairs({ { L.UI_VIS_REVEAL, REVEAL_X }, { L.UI_VIS_HIDE, HIDE_X } }) do
        local label = Theme:Text(header, column[1], "small", "TEXT_MUTED")
        label:SetPoint("CENTER", header, "LEFT", column[2] + Theme.checkboxSize / 2, 0)
    end
    block:Place(header, LABEL_HEIGHT, ROW_GAP)
    block:Index(L.UI_VIS_REVEAL, L.UI_VIS_HIDE)
    for _, condition in ipairs(Rules.conditions) do
        local row = CreateFrame("Frame", nil, block)
        row:SetSize(CONTROL_WIDTH, Theme.checkboxSize)
        row.label = Theme:Text(row, L["VIS_COND_" .. condition], "body", "TEXT_BODY")
        row.label:SetPoint("LEFT")
        row.reveal = Theme:Checkbox(row, COLUMN_BOX, "", function(widget)
            self:VisCondition(condition, widget:GetChecked() and "reveal" or nil)
        end)
        row.reveal:SetPoint("LEFT", REVEAL_X, 0)
        row.hide = Theme:Checkbox(row, COLUMN_BOX, "", function(widget)
            self:VisCondition(condition, widget:GetChecked() and "hide" or nil)
        end)
        row.hide:SetPoint("LEFT", HIDE_X, 0)
        row.condition = condition
        block:Place(row, Theme.checkboxSize, ROW_GAP)
        block:Index(L["VIS_COND_" .. condition])
        self.visConditions[#self.visConditions + 1] = row
    end
end

-- Names commit on Enter or when the box lets go. The same name again is no change, so the
-- focus loss that follows an Enter writes nothing.
function UI:VisRename()
    local entry = self.visBehaviour and Rules:Behaviour(self.visBehaviour)
    if not entry then
        return
    end
    local text = (self.visName:GetText() or ""):match("^%s*(.-)%s*$")
    if text == Rules:Name(entry) then
        return
    end
    local ok, err = Rules:RenameBehaviour(entry.id, text)
    self:LoadVisibility()
    if not ok then
        self.visStatus:SetText(errorText(err))
    end
end

function UI:VisSetupRows(block)
    for index, kind in ipairs(Rules.kinds) do
        if index > 1 then
            block:Skip(DROPDOWN_GAP)
        end
        local header = Theme:Text(block, L["VIS_KIND_" .. kind], "small", "TEXT_MUTED")
        block:Place(header, LABEL_HEIGHT, ROW_GAP)
        for _, group in ipairs(Rules.groups) do
            if group.kind == kind then
                local row = Theme:Dropdown(block, CONTROL_WIDTH, {},
                    function(value) return self:VisAssigned(group.id) == value end,
                    function(value)
                        Rules:Assign({ group.id }, self.visPlace, value ~= NONE and value or nil)
                        self:LoadVisibility()
                    end)
                block:Place(row, Theme.dropdownRowHeight, ROW_GAP)
                row:SetLabel(L[group.labelKey])
                row.groupId = group.id
                block:Index(L[group.labelKey])
                self.visRows[#self.visRows + 1] = row
            end
        end
    end
end

-- The settings block behind the UI visibility row. Setups first, because giving an element
-- a behaviour is what a player does most; then the behaviours themselves.
function UI:BuildVisibilitySettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_VIS_HELP)
    self.visPlace, self.visBehaviour = Rules.world, nil
    self.visRows, self.visSliders, self.visBoxes, self.visConditions = {}, {}, {}, {}
    for _, starter in ipairs(Rules.starters) do
        block:Index(Rules:Name(starter))
    end

    block:Group(L.UI_VIS_SETUPS)
    self.visSetupDropdown = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return self.visPlace == value end,
        function(value)
            self.visPlace = value
            self:LoadVisibility()
        end)
    block:Place(self.visSetupDropdown, Theme.dropdownRowHeight, DROPDOWN_GAP)
    self.visSetupDropdown:SetLabel(L.UI_VIS_SETUP)
    self.visOwnSetup = Theme:Checkbox(block, CONTROL_WIDTH, L.UI_VIS_OWN_SETUP, function(widget)
        Rules:SetOwnSetup(self.visPlace, widget:GetChecked() == true)
        self:LoadVisibility()
    end)
    block:Place(self.visOwnSetup, Theme.checkboxSize, CHECKBOX_GAP)
    local notes = {}
    for _, place in ipairs(Rules.places) do
        block:Index(L["VIS_PLACE_" .. place])
        notes[#notes + 1] = setupNote(place, false, "pvp")
        notes[#notes + 1] = setupNote(place, true, "pvp")
    end
    self.visSetupNote = block:Note(nil, unpack(notes))
    self:VisSetupRows(block)

    block:Group(L.UI_VIS_BEHAVIOURS)
    self.visBehaviourDropdown = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return self.visBehaviour == value end,
        function(value)
            self.visBehaviour = value
            self:LoadVisibility()
        end)
    block:Place(self.visBehaviourDropdown, Theme.dropdownRowHeight, DROPDOWN_GAP)
    self.visBehaviourDropdown:SetLabel(L.UI_VIS_BEHAVIOUR)
    self.visCopy = Theme:Button(block, ACTION_WIDTH, L.UI_VIS_COPY, function()
        local id, err = Rules:CopyBehaviour(self.visBehaviour)
        if id then
            self.visBehaviour = id
        end
        self:LoadVisibility()
        self.visStatus:SetText(id and L.UI_VIS_COPIED or errorText(err))
    end)
    self.visCopy:SetPoint("LEFT", self.visBehaviourDropdown, "RIGHT", 8, 0)
    self.visUses = block:Note(nil, L.UI_VIS_NONE_YET, L.UI_VIS_USES_NONE, L.UI_VIS_USES_ONE,
        string.format(L.UI_VIS_USES, #Rules.groups))

    local nameLabel = Theme:Text(block, L.UI_VIS_NAME, "small", "TEXT_MUTED")
    block:Place(nameLabel, LABEL_HEIGHT, ROW_GAP)
    self.visName = self.Widgets:Input(block, CONTROL_WIDTH, NAME_HEIGHT)
    block:Place(self.visName, NAME_HEIGHT, DROPDOWN_GAP)
    self.visName:SetScript("OnEnterPressed", function(widget)
        self:VisRename()
        widget:ClearFocus()
    end)
    self.visName:SetScript("OnEditFocusLost", function() self:VisRename() end)
    self.visDelete = Theme:Button(block, ACTION_WIDTH, L.UI_VIS_DELETE, function()
        if self.visBehaviour and Rules:DeleteBehaviour(self.visBehaviour) then
            self.visBehaviour = nil
            self:LoadVisibility()
            self.visStatus:SetText(L.UI_VIS_DELETED)
        end
    end)
    self.visDelete:SetPoint("LEFT", self.visName, "RIGHT", 8, 0)
    self.visStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    block:Place(self.visStatus, STATUS_HEIGHT, DROPDOWN_GAP)
    self.visStatus:SetPoint("RIGHT")

    self:VisSlider(block, "UI_VIS_RESTING", "resting", Rules.restingRange, percentText)
    self:VisSlider(block, "UI_VIS_REVEALED", "revealed", Rules.revealedRange, percentText)
    self:VisCheckbox(block, "UI_VIS_MOUSEOVER", "mouseover")
    self:VisCheckbox(block, "UI_VIS_TOGETHER", "together")
    self:VisConditionRows(block)
    block:Skip(DROPDOWN_GAP)
    block:Note(L.UI_VIS_ORDER)
    self:VisSlider(block, "UI_VIS_FADE_IN", "fadeIn", Rules.fadeRange, secondsText)
    self:VisSlider(block, "UI_VIS_FADE_OUT", "fadeOut", Rules.fadeRange, secondsText)
    block:Finish()
    self:RegisterModuleSettings(MODULE_ID, block)
end

function UI:LoadVisibilitySetups(entries)
    local places = {}
    for index, place in ipairs(Rules.places) do
        local name = L["VIS_PLACE_" .. place]
        places[index] = { value = place,
            text = Rules:HasOwnSetup(place) and name or string.format(L.UI_VIS_SETUP_USES_WORLD, name) }
    end
    self.visSetupDropdown:SetEntries(places)
    self.visSetupDropdown:SetValueText(L["VIS_PLACE_" .. self.visPlace])
    local world, own = self.visPlace == Rules.world, Rules:HasOwnSetup(self.visPlace)
    self.visOwnSetup:SetChecked(own)
    setBoxEnabled(self.visOwnSetup, not world)
    self.visSetupNote:SetText(setupNote(self.visPlace, own, self:VisSetupInUse()))
    -- A place following World's setup shows World's choices, greyed out, until it has its own.
    for _, row in ipairs(self.visRows) do
        row:SetEntries(entries)
        local assigned = Rules:BehaviourFor(row.groupId, self.visPlace)
        row:SetValueText(assigned and Rules:Name(assigned) or L.VIS_BEHAVIOUR_NONE)
        row.button:SetEnabled(own)
        Theme:Color(row.label, own and "TEXT_BODY" or "TEXT_MUTED", true)
    end
end

function UI:LoadVisibilityBehaviour(entry)
    self.visCopy.label:SetText(entry and L.UI_VIS_COPY or L.UI_VIS_NEW)
    self.visUses:SetText(usesText(entry))
    -- Never under the player's fingers: a refresh while they type would undo the typing.
    if not self.visName:HasFocus() then
        self.visName:SetText(entry and Rules:Name(entry) or "")
    end
    self.visName:SetEnabled(entry ~= nil)
    self.visDelete:SetEnabled(entry ~= nil)
    for _, slider in ipairs(self.visSliders) do
        slider:SetValue(entry and entry[slider.field] or slider.range.minimum)
        setSliderEnabled(slider, entry ~= nil)
    end
    for _, box in ipairs(self.visBoxes) do
        box:SetChecked(entry ~= nil and entry[box.field] == true)
        setBoxEnabled(box, entry ~= nil)
    end
    for _, row in ipairs(self.visConditions) do
        local role = entry and Rules:ConditionRole(entry, row.condition)
        local enabled = entry ~= nil and Conditions:Supported(row.condition)
        row.reveal:SetChecked(role == "reveal")
        row.hide:SetChecked(role == "hide")
        row.reveal:SetEnabled(enabled)
        row.hide:SetEnabled(enabled)
        Theme:Color(row.label, enabled and "TEXT_BODY" or "TEXT_MUTED", true)
    end
end

function UI:LoadVisibility()
    if not self.visSetupDropdown then
        return
    end
    local behaviours = Rules:Behaviours()
    if not (self.visBehaviour and Rules:Behaviour(self.visBehaviour)) then
        self.visBehaviour = behaviours[1] and behaviours[1].id or nil
    end
    local entries, names = { { value = NONE, text = L.VIS_BEHAVIOUR_NONE } }, {}
    for _, behaviour in ipairs(behaviours) do
        entries[#entries + 1] = { value = behaviour.id, text = Rules:Name(behaviour) }
        names[#names + 1] = { value = behaviour.id, text = Rules:Name(behaviour) }
    end
    self:LoadVisibilitySetups(entries)
    local entry = self.visBehaviour and Rules:Behaviour(self.visBehaviour)
    self.visBehaviourDropdown:SetEntries(names)
    self.visBehaviourDropdown:SetValueText(entry and Rules:Name(entry) or L.UI_VIS_NO_BEHAVIOUR)
    self:LoadVisibilityBehaviour(entry)
    self.visStatus:SetText("")
    if self.visCompanion then
        self.visCompanion:Load()
    end
end
