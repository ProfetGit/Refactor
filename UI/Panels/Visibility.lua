local _, R = ...
local UI, L = R.UI, R.L
local Theme, Rules, Conditions = R.Theme, R.Visibility, R.Conditions

local CONTROL_WIDTH, DROPDOWN_GAP, SLIDER_GAP, CHECKBOX_GAP, ROW_GAP = 380, 6, 6, 10, 2
-- The button beside the behaviour picker and beside its name, the name box, a small label
-- over a list, and the line that reports what the last press did.
local ACTION_WIDTH, NAME_HEIGHT, LABEL_HEIGHT, STATUS_HEIGHT = 104, 26, 16, 14
-- A kind's elements sit one chevron in under it, their pickers ending where the kind's does.
local CHEVRON, CHEVRON_GAP, ELEMENT_INDENT = 12, 6, 18
-- Past this many names the editor counts the rest: a sentence that lists twenty elements is
-- read as a wall, and the kinds above already show them all.
local MAX_NAMES = 4
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

local function setDropdownEnabled(row, enabled)
    row.button:SetEnabled(enabled)
    Theme:Color(row.label, enabled and "TEXT_BODY" or "TEXT_MUTED", true)
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

-- A list read as a sentence: "a", "a and b", "a, b and c", and past MAX_NAMES "a, b, c, d and
-- 3 more".
local function sentence(names)
    if #names == 1 then
        return names[1]
    elseif #names <= MAX_NAMES then
        return string.format(L.UI_VIS_LIST_AND, table.concat(names, L.UI_LIST_SEPARATOR, 1, #names - 1),
            names[#names])
    end
    return string.format(L.UI_VIS_LIST_MORE, table.concat(names, L.UI_LIST_SEPARATOR, 1, MAX_NAMES),
        #names - MAX_NAMES)
end

-- The behaviour a picker opens on when none is chosen yet: the one most elements have, which
-- is the one a player who opens this panel has come to tune.
local function mostUsed(behaviours)
    local best, count = nil, -1
    for _, entry in ipairs(behaviours) do
        local uses = Rules:Uses(entry.id)
        if uses > count then
            best, count = entry.id, uses
        end
    end
    return best
end

function UI:VisSetupInUse()
    local module = R.moduleByID and R.moduleByID[MODULE_ID]
    return module and module.state == "enabled" and module.place or nil
end

function UI:VisAssigned(groupId)
    local behaviour = Rules:BehaviourFor(groupId, self.visPlace)
    return behaviour and behaviour.id or NONE
end

-- The behaviour every element of a kind has in the setup shown, NONE when none of them has
-- one, nil when they differ.
function UI:VisKindValue(kind)
    local common
    for index, groupId in ipairs(self.visKindGroups[kind]) do
        local value = self:VisAssigned(groupId)
        if index == 1 then
            common = value
        elseif value ~= common then
            return nil
        end
    end
    return common
end

function UI:VisBehaviourText(value)
    if value == nil then
        return L.UI_VIS_MIXED
    end
    local entry = value ~= NONE and Rules:Behaviour(value)
    return entry and Rules:Name(entry) or L.VIS_BEHAVIOUR_NONE
end

-- Giving elements a behaviour also opens it in the editor: the next thing a player does after
-- choosing a look is usually to tune it.
function UI:VisChoose(groupIds, value)
    Rules:Assign(groupIds, self.visPlace, value ~= NONE and value or nil)
    if value ~= NONE then
        self.visBehaviour, self.visPicked = value, true
    end
    self:LoadVisibility()
end

-- Who a change to this behaviour reaches, by name. A kind every element of which has it is
-- named once, as a kind.
function UI:VisUsedBy(entry)
    if not entry then
        return L.UI_VIS_NONE_YET
    end
    local used = Rules:UsedBy(entry.id)
    if #used == 0 then
        return L.UI_VIS_USES_NONE
    end
    local has = {}
    for _, groupId in ipairs(used) do
        has[groupId] = true
    end
    local names, named = {}, {}
    for _, groupId in ipairs(used) do
        local group = Rules:Group(groupId)
        if not named[group.kind] then
            local whole = true
            for _, id in ipairs(self.visKindGroups[group.kind]) do
                if not has[id] then
                    whole = false
                    break
                end
            end
            if whole then
                named[group.kind] = true
                names[#names + 1] = L["VIS_KIND_ALL_" .. group.kind]
            else
                names[#names + 1] = L[group.labelKey]
            end
        end
    end
    return string.format(#used == 1 and L.UI_VIS_USED_BY_ONE or L.UI_VIS_USED_BY, sentence(names))
end

-- Every widget below the help text, in order, so the block can be laid out again when a kind
-- opens or closes. shown, when given, says whether the widget takes its place on this pass;
-- stretch reaches the widget across to the block's right edge.
function UI:VisItem(widget, height, gap, options)
    options = options or {}
    local items = self.visItems
    items[#items + 1] = { widget = widget, height = height, gap = gap, x = options.x, shown = options.shown,
        stretch = options.stretch }
    return widget
end

function UI:VisSkip(height)
    self.visItems[#self.visItems + 1] = { skip = height }
end

function UI:VisGroup(text)
    local block = self.visBlock
    if #self.visItems > 0 then
        self:VisSkip(self.Widgets.GROUP_GAP)
    end
    local label = Theme:Text(block, text, "body", "TEXT_TITLE")
    block:Index(text)
    return self:VisItem(label, self.Widgets.GROUP_LABEL - self.Widgets.CONTROL_GAP, nil, { stretch = true })
end

-- A muted paragraph measured against the longest text it may show, the way Note keeps room.
function UI:VisNote(text, ...)
    local block = self.visBlock
    local note = Theme:Text(block, text or "", "small", "TEXT_MUTED")
    note:SetJustifyV("TOP")
    note:SetWordWrap(true)
    local height = self.Widgets:TextHeight(note, block.width, text, ...)
    note:SetHeight(math.max(1, height))
    if text then
        block:Index(text)
    end
    return self:VisItem(note, height, self.Widgets.NOTE_GAP)
end

function UI:VisKindOpen(kind)
    return self.visOpen[kind] == true or self.visQueryOpen[kind] == true
end

function UI:VisLayout()
    local block = self.visBlock
    block.cursor = block.top
    for _, item in ipairs(self.visItems) do
        if item.skip then
            block:Skip(item.skip)
        else
            local shown = item.shown == nil or item.shown()
            item.widget:SetShown(shown)
            if shown then
                block:Place(item.widget, item.height, item.gap, item.x)
                if item.stretch then
                    item.widget:SetPoint("RIGHT")
                end
            end
        end
    end
    for _, row in ipairs(self.visKinds) do
        Theme:ApplyAsset(row.toggle.art, self:VisKindOpen(row.kind) and "scrollUp" or "scrollDown")
        Theme:Color(row.toggle.art, "ACCENT_COPPER")
    end
    block:Finish()
end

function UI:VisToggleKind(kind)
    local open = not self:VisKindOpen(kind)
    self.visOpen[kind] = open
    if not open then
        self.visQueryOpen[kind] = nil
    end
    self:VisLayout()
    self:Refresh()
end

-- The window asks on every pass while the block is open, before it reads the block's height.
-- A search for one element opens the kind holding it; clearing the search closes what only it
-- opened. Nothing moves when the answer is the same, so a slider drag is never interrupted.
function UI:VisApplyQuery(query)
    local wanted, changed = {}, false
    if query ~= "" then
        for _, kind in ipairs(Rules.kinds) do
            local hit = self:MatchesText(L["VIS_KIND_" .. kind], query)
            for _, groupId in ipairs(self.visKindGroups[kind]) do
                hit = hit or self:MatchesText(L[Rules:Group(groupId).labelKey], query)
            end
            wanted[kind] = hit or nil
        end
    end
    for _, kind in ipairs(Rules.kinds) do
        if wanted[kind] ~= self.visQueryOpen[kind] then
            changed = true
        end
    end
    self.visQueryOpen = wanted
    if changed then
        self:VisLayout()
    end
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
    self:VisItem(slider, Theme.sliderRowHeight, SLIDER_GAP)
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
    self:VisItem(box, Theme.checkboxSize, CHECKBOX_GAP)
    box.field = field
    block:Index(L[labelKey])
    self.visBoxes[#self.visBoxes + 1] = box
    return box
end

function UI:VisRole(condition)
    local entry = self.visBehaviour and Rules:Behaviour(self.visBehaviour)
    return entry and Rules:ConditionRole(entry, condition) or NONE
end

function UI:VisCondition(condition, role)
    if self.visBehaviour then
        Rules:SetCondition(self.visBehaviour, condition, role)
    end
    self:LoadVisibility()
end

-- One choice per condition: it does nothing, shows the element, or hides it, and can never
-- do two of those at once.
function UI:VisConditionRows(block)
    local header = Theme:Text(block, L.UI_VIS_CONDITIONS, "small", "TEXT_MUTED")
    self:VisItem(header, LABEL_HEIGHT, ROW_GAP)
    block:Index(L.UI_VIS_CONDITIONS)
    self.visRoleEntries = {
        { value = NONE, text = L.UI_VIS_COND_NONE },
        { value = "reveal", text = L.UI_VIS_COND_SHOW },
        { value = "hide", text = L.UI_VIS_COND_HIDE },
    }
    self.visRoleText = { [NONE] = L.UI_VIS_COND_NONE, reveal = L.UI_VIS_COND_SHOW, hide = L.UI_VIS_COND_HIDE }
    block:Index(L.UI_VIS_COND_NONE, L.UI_VIS_COND_SHOW, L.UI_VIS_COND_HIDE)
    for _, condition in ipairs(Rules.conditions) do
        local row = Theme:Dropdown(block, CONTROL_WIDTH, self.visRoleEntries,
            function(value) return self:VisRole(condition) == value end,
            function(value) self:VisCondition(condition, value ~= NONE and value or nil) end)
        row:SetLabel(L["VIS_COND_" .. condition])
        row.condition = condition
        self:VisItem(row, Theme.dropdownRowHeight, ROW_GAP)
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

-- A kind is one row that sets all of its elements at once, with a chevron that lists them.
function UI:VisKindRow(block, kind)
    local row = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return self:VisKindValue(kind) == value end,
        function(value) self:VisChoose(self.visKindGroups[kind], value) end)
    row:SetLabel(L["VIS_KIND_" .. kind])
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", CHEVRON + CHEVRON_GAP, 0)
    -- The chevron and the name both open the kind, the way a feature's row opens its block.
    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetPoint("TOPLEFT")
    row.toggle:SetPoint("BOTTOMRIGHT", row.button, "BOTTOMLEFT", -8, 0)
    row.toggle.art = Theme:Texture(row.toggle, "scrollDown", "OVERLAY")
    row.toggle.art:SetSize(CHEVRON, CHEVRON)
    row.toggle.art:SetPoint("LEFT")
    row.toggle:SetScript("OnClick", function() self:VisToggleKind(kind) end)
    row.kind = kind
    self:VisItem(row, Theme.dropdownRowHeight, ROW_GAP)
    block:Index(L["VIS_KIND_" .. kind])
    self.visKinds[#self.visKinds + 1] = row
    for _, groupId in ipairs(self.visKindGroups[kind]) do
        local group = Rules:Group(groupId)
        local element = Theme:Dropdown(block, CONTROL_WIDTH - ELEMENT_INDENT, {},
            function(value) return self:VisAssigned(group.id) == value end,
            function(value) self:VisChoose({ group.id }, value) end)
        element:SetLabel(L[group.labelKey])
        element.groupId = group.id
        self:VisItem(element, Theme.dropdownRowHeight, ROW_GAP,
            { x = ELEMENT_INDENT, shown = function() return self:VisKindOpen(kind) end })
        block:Index(L[group.labelKey])
        self.visRows[#self.visRows + 1] = element
    end
end

-- The settings block behind the UI visibility row. Elements first, because giving them a
-- behaviour is what a player does first; then the editor for the behaviour last chosen.
function UI:BuildVisibilitySettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_VIS_HELP)
    self.visBlock, self.visItems = block, {}
    self.visPlace, self.visBehaviour = Rules.world, nil
    self.visRows, self.visKinds, self.visSliders, self.visBoxes, self.visConditions = {}, {}, {}, {}, {}
    self.visOpen, self.visQueryOpen, self.visKindGroups = {}, {}, {}
    for _, kind in ipairs(Rules.kinds) do
        self.visKindGroups[kind] = {}
    end
    for _, group in ipairs(Rules.groups) do
        local list = self.visKindGroups[group.kind]
        list[#list + 1] = group.id
    end
    for _, starter in ipairs(Rules.starters) do
        block:Index(Rules:Name(starter))
    end

    self:VisGroup(L.UI_VIS_SETUPS)
    self.visSetupDropdown = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return self.visPlace == value end,
        function(value)
            self.visPlace = value
            self:LoadVisibility()
            self:VisLayout()
            self:Refresh()
        end)
    self:VisItem(self.visSetupDropdown, Theme.dropdownRowHeight, DROPDOWN_GAP)
    self.visSetupDropdown:SetLabel(L.UI_VIS_SETUP)
    -- Everywhere is always a setup of its own, so the tick is only there for the other places.
    self.visOwnSetup = Theme:Checkbox(block, CONTROL_WIDTH, L.UI_VIS_OWN_SETUP, function(widget)
        Rules:SetOwnSetup(self.visPlace, widget:GetChecked() == true)
        self:LoadVisibility()
    end)
    self:VisItem(self.visOwnSetup, Theme.checkboxSize, CHECKBOX_GAP,
        { shown = function() return self.visPlace ~= Rules.world end })
    local notes = {}
    for _, place in ipairs(Rules.places) do
        block:Index(L["VIS_PLACE_" .. place])
        notes[#notes + 1] = setupNote(place, false, "pvp")
        notes[#notes + 1] = setupNote(place, true, "pvp")
    end
    self.visSetupNote = self:VisNote(nil, unpack(notes))
    for _, kind in ipairs(Rules.kinds) do
        self:VisKindRow(block, kind)
    end

    self:VisGroup(L.UI_VIS_BEHAVIOURS)
    self.visBehaviourDropdown = Theme:Dropdown(block, CONTROL_WIDTH, {},
        function(value) return self.visBehaviour == value end,
        function(value)
            self.visBehaviour, self.visPicked = value, true
            self:LoadVisibility()
        end)
    self:VisItem(self.visBehaviourDropdown, Theme.dropdownRowHeight, DROPDOWN_GAP)
    self.visBehaviourDropdown:SetLabel(L.UI_VIS_BEHAVIOUR)
    self.visCopy = Theme:Button(block, ACTION_WIDTH, L.UI_VIS_COPY, function()
        local id, err = Rules:CopyBehaviour(self.visBehaviour)
        if id then
            self.visBehaviour, self.visPicked = id, true
        end
        self:LoadVisibility()
        self.visStatus:SetText(id and L.UI_VIS_COPIED or errorText(err))
    end)
    self.visCopy:SetPoint("LEFT", self.visBehaviourDropdown, "RIGHT", 8, 0)
    -- Room for the longest sentence it can say: the four longest names and a count.
    local longest = {}
    for _, group in ipairs(Rules.groups) do
        longest[#longest + 1] = L[group.labelKey]
    end
    table.sort(longest, function(a, b) return #a > #b end)
    local widest = string.format(L.UI_VIS_USED_BY, string.format(L.UI_VIS_LIST_MORE,
        table.concat(longest, L.UI_LIST_SEPARATOR, 1, MAX_NAMES), #Rules.groups))
    self.visUses = self:VisNote(nil, L.UI_VIS_NONE_YET, L.UI_VIS_USES_NONE, widest)

    local nameLabel = Theme:Text(block, L.UI_VIS_NAME, "small", "TEXT_MUTED")
    self:VisItem(nameLabel, LABEL_HEIGHT, ROW_GAP)
    self.visName = self.Widgets:Input(block, CONTROL_WIDTH, NAME_HEIGHT)
    self:VisItem(self.visName, NAME_HEIGHT, DROPDOWN_GAP)
    self.visName:SetScript("OnEnterPressed", function(widget)
        self:VisRename()
        widget:ClearFocus()
    end)
    self.visName:SetScript("OnEditFocusLost", function() self:VisRename() end)
    self.visDelete = Theme:Button(block, ACTION_WIDTH, L.UI_VIS_DELETE, function()
        if self.visBehaviour and Rules:DeleteBehaviour(self.visBehaviour) then
            self.visBehaviour, self.visPicked = nil, false
            self:LoadVisibility()
            self.visStatus:SetText(L.UI_VIS_DELETED)
        end
    end)
    self.visDelete:SetPoint("LEFT", self.visName, "RIGHT", 8, 0)
    self.visStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    self:VisItem(self.visStatus, STATUS_HEIGHT, DROPDOWN_GAP, { stretch = true })

    self:VisSlider(block, "UI_VIS_RESTING", "resting", Rules.restingRange, percentText)
    self:VisSlider(block, "UI_VIS_REVEALED", "revealed", Rules.revealedRange, percentText)
    self:VisCheckbox(block, "UI_VIS_MOUSEOVER", "mouseover")
    self:VisCheckbox(block, "UI_VIS_TOGETHER", "together")
    self:VisConditionRows(block)
    self:VisSkip(DROPDOWN_GAP)
    self:VisNote(L.UI_VIS_ORDER)
    self:VisSlider(block, "UI_VIS_FADE_IN", "fadeIn", Rules.fadeRange, secondsText)
    self:VisSlider(block, "UI_VIS_FADE_OUT", "fadeOut", Rules.fadeRange, secondsText)
    function block.OnQuery(_, query) self:VisApplyQuery(query) end
    self:VisLayout()
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
    local own = Rules:HasOwnSetup(self.visPlace)
    self.visOwnSetup:SetChecked(own)
    self.visSetupNote:SetText(setupNote(self.visPlace, own, self:VisSetupInUse()))
    -- A place following Everywhere's setup shows its choices, greyed out, until it has its own.
    for _, row in ipairs(self.visKinds) do
        row:SetEntries(entries)
        row:SetValueText(self:VisBehaviourText(self:VisKindValue(row.kind)))
        setDropdownEnabled(row, own)
    end
    for _, row in ipairs(self.visRows) do
        row:SetEntries(entries)
        row:SetValueText(self:VisBehaviourText(self:VisAssigned(row.groupId)))
        setDropdownEnabled(row, own)
    end
end

function UI:LoadVisibilityBehaviour(entry)
    self.visCopy.label:SetText(entry and L.UI_VIS_COPY or L.UI_VIS_NEW)
    self.visUses:SetText(self:VisUsedBy(entry))
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
        local role = entry and Rules:ConditionRole(entry, row.condition) or NONE
        row:SetValueText(self.visRoleText[role])
        setDropdownEnabled(row, entry ~= nil and Conditions:Supported(row.condition))
    end
end

function UI:LoadVisibility()
    if not self.visSetupDropdown then
        return
    end
    local behaviours = Rules:Behaviours()
    -- Until the player picks one, the editor keeps to the behaviour most elements have.
    if not (self.visPicked and self.visBehaviour and Rules:Behaviour(self.visBehaviour)) then
        self.visBehaviour, self.visPicked = mostUsed(behaviours), false
    end
    local entries, names = { { value = NONE, text = L.VIS_BEHAVIOUR_NONE } }, {}
    for _, behaviour in ipairs(behaviours) do
        local name = Rules:Name(behaviour)
        entries[#entries + 1] = { value = behaviour.id, text = name }
        -- An unused behaviour says so in the editor's list, so leftovers stand out to delete.
        names[#names + 1] = { value = behaviour.id,
            text = Rules:Uses(behaviour.id) == 0 and string.format(L.UI_VIS_NOT_USED, name) or name }
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
