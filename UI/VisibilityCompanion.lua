local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme, Rules = R.Theme, R.Visibility

local WIDTH, PAD, GAP = 360, 18, 8
local NOTE_HEIGHT, LABEL_STEP, BOX_STEP = 44, 20, 26
local TAB_GAP, TAB_ROW = 4, 30
-- A system stands for at most the four chat elements, so four tabs are built and shown as needed.
local MAX_TABS = 4
local MODULE_ID = "interface.visibility"
-- The picker's value for "no behaviour". A behaviour id starts with a letter, so it can never be this.
local NONE = ""

local Companion = {}
Companion.__index = Companion

function Companion:Assigned()
    local behaviour = self.current and Rules:BehaviourFor(self.current, self.module.place)
    return behaviour and behaviour.id or NONE
end

-- Writes to the setup in use where the player stands, the one they are looking at.
function Companion:Assign(value)
    if self.current and self.module.place then
        Rules:Assign({ self.current }, self.module.place, value ~= NONE and value or nil)
    end
    self:Load()
end

-- Built once, at the module's first enable, and kept for the session (rule 11).
function Companion:Build()
    local frame = CreateFrame("Frame", nil, UIParent)
    self.frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetWidth(WIDTH)
    frame:Hide()
    R:OwnFrame(frame)
    Theme:Dialog(frame)
    self.title = Theme:Text(frame, "", "body", "TEXT_TITLE")
    self.title:SetPoint("TOPLEFT", PAD, -PAD)
    -- Flush on the corner, over the border, where EditModeSystemSettingsDialog anchors its
    -- own UIPanelCloseButton (EditModeDialogs.xml, 12.1.0), so the two dialogs side by side
    -- close the same way.
    local close = Theme:CloseButton(frame, function() self:Close() end)
    close:SetPoint("TOPRIGHT")
    local y = -PAD - 22

    self.tabs = {}
    for index = 1, MAX_TABS do
        local tab = Theme:Tab(frame, "", function(widget)
            self.current = widget.groupId
            self:Load()
        end)
        tab:SetPoint("BOTTOMLEFT", PAD, 0)
        tab:Hide()
        self.tabs[index] = tab
    end
    self.tabTop = y
    y = y - TAB_ROW

    self.status = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.status:SetPoint("TOPLEFT", PAD, y)
    self.status:SetPoint("RIGHT", -PAD, 0)
    self.status:SetHeight(LABEL_STEP)
    self.status:SetJustifyV("TOP")
    y = y - LABEL_STEP - GAP

    self.behaviour = Theme:Dropdown(frame, WIDTH - PAD * 2, {},
        function(value) return self:Assigned() == value end,
        function(value) self:Assign(value) end)
    self.behaviour:SetPoint("TOPLEFT", PAD, y)
    self.behaviour:SetLabel(L.UI_VIS_BEHAVIOUR)
    y = y - Theme.dropdownRowHeight - GAP

    self.setup = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.setup:SetPoint("TOPLEFT", PAD, y)
    self.setup:SetJustifyV("TOP")
    self.setup:SetWordWrap(true)
    local variants = {}
    for _, place in ipairs(Rules.places) do
        variants[#variants + 1] = string.format(L.UI_VIS_COMPANION_SETUP, L["VIS_PLACE_" .. place])
    end
    local setupHeight = UI.Widgets:TextHeight(self.setup, WIDTH - PAD * 2, unpack(variants))
    self.setup:SetHeight(setupHeight)
    y = y - setupHeight - GAP

    self.blobs = Theme:Checkbox(frame, WIDTH - PAD * 2, L.UI_VIS_BLOBS, function(widget)
        Settings:SetOption("uiVisibilityBlobs", widget:GetChecked() == true)
    end)
    self.blobs:SetPoint("TOPLEFT", PAD, y)
    y = y - BOX_STEP - GAP

    self.edit = Theme:Button(frame, WIDTH - PAD * 2, L.UI_VIS_EDIT_BEHAVIOURS, function()
        UI:OpenModule(MODULE_ID)
    end)
    self.edit:SetPoint("TOPLEFT", PAD, y)
    y = y - self.edit.height - GAP

    -- Measured against every group's note, so the longest one (the minimap's, four lines)
    -- is not cut off by a box sized for three.
    self.note = Theme:Text(frame, "", "small", "TEXT_MUTED")
    self.note:SetPoint("TOPLEFT", PAD, y)
    self.note:SetJustifyV("TOP")
    local notes = {}
    for _, group in ipairs(Rules.groups) do
        if group.noteKey then notes[#notes + 1] = L[group.noteKey] end
    end
    local noteHeight = math.max(NOTE_HEIGHT, UI.Widgets:TextHeight(self.note, WIDTH - PAD * 2, unpack(notes)))
    self.note:SetHeight(noteHeight)
    y = y - noteHeight
    frame:SetHeight(-y + PAD)
end

-- Anchored to Blizzard's dialog, so a drag of theirs carries ours; nothing of theirs is
-- touched. ids are the groups the selected system stands for, first one showing.
function Companion:Open(dialog, ids)
    self.ids = ids
    self.current = ids[1]
    local frame = self.frame
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", dialog, "TOPRIGHT", GAP, 0)
    frame:Show()
    self:Load()
end

function Companion:Close()
    self.ids, self.current = nil, nil
    self.frame:Hide()
end

-- None first, then every behaviour in the player's order.
function Companion:Entries()
    local entries = { { value = NONE, text = L.VIS_BEHAVIOUR_NONE } }
    for _, behaviour in ipairs(Rules:Behaviours()) do
        entries[#entries + 1] = { value = behaviour.id, text = Rules:Name(behaviour) }
    end
    return entries
end

function Companion:Load()
    local group = self.current and Rules:Group(self.current)
    if not group or not self.frame:IsShown() then
        return
    end
    self.title:SetText(L[group.labelKey])
    local x = PAD
    for index, tab in ipairs(self.tabs) do
        local id = self.ids[index]
        if id and #self.ids > 1 then
            local other = Rules:Group(id)
            tab.groupId = id
            tab.label:SetText(L[other.labelKey])
            tab:SetWidth(tab.label:GetStringWidth() + 24)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", x, self.tabTop)
            x = x + tab:GetWidth() + TAB_GAP
            Theme:TabState(tab, id == self.current)
            tab:Show()
        else
            tab:Hide()
        end
    end
    local runtime = self.module.groups and self.module.groups[group.id]
    if runtime and runtime.status == "owned" then
        self.status:SetText(string.format(L.UI_VIS_STATUS_OWNED, runtime.owner))
        Theme:Color(self.status, "TEXT_WARNING", true)
    elseif runtime and runtime.status == "missing" then
        self.status:SetText(string.format(L.UI_VIS_STATUS_MISSING, runtime.missing))
        Theme:Color(self.status, "TEXT_WARNING", true)
    else
        self.status:SetText(L.UI_VIS_STATUS_OK)
        Theme:Color(self.status, "TEXT_MUTED", true)
    end
    self.behaviour:SetEntries(self:Entries())
    local assigned = Rules:BehaviourFor(group.id, self.module.place)
    self.behaviour:SetValueText(assigned and Rules:Name(assigned) or L.VIS_BEHAVIOUR_NONE)
    local place = self.module.place or Rules.world
    self.setup:SetText(string.format(L.UI_VIS_COMPANION_SETUP, L["VIS_PLACE_" .. place]))
    self.blobs:SetShown(group.extras ~= nil)
    self.blobs:SetChecked(Settings:GetOption("uiVisibilityBlobs") == true)
    self.note:SetText(group.noteKey and L[group.noteKey] or "")
end

-- The module asks for this once, at its first enable, and opens and closes it from the
-- Edit Mode hooks it owns.
function UI:CreateVisibilityCompanion(module)
    local companion = setmetatable({ module = module }, Companion)
    companion:Build()
    self.visCompanion = companion
    return companion
end
