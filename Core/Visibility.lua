--- @core visibility
--- Purpose: the shape of a UI visibility rule, the frame groups it applies to, the presets, and the resolver.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Visibility = {}
R.Visibility = Visibility

local MODES = { always = true, mouseover = true, hidden = true }
Visibility.modes = { "always", "mouseover", "hidden" }
local CONDITIONS = {}
for _, name in ipairs(R.Conditions.names) do
    CONDITIONS[name] = true
end
local FADE_MIN, FADE_MAX, FADE_STEP = 0, 2, 0.05
local DEFAULT_FADE_IN, DEFAULT_FADE_OUT = 0.15, 0.4
local MAX_GROUPS, RULE_FIELDS = 32, 7
-- How visible an element is when its rule says shown, and when it says hidden: a share of
-- the alpha the game gives the frame, so an Edit Mode opacity still counts. Shown never
-- goes below a tenth, or an element could be lost with no rule saying so.
local SHOWN_MIN, HIDDEN_MIN, ALPHA_MAX, ALPHA_STEP = 0.1, 0, 1, 0.05
local DEFAULT_SHOWN, DEFAULT_HIDDEN = 1, 0
Visibility.fadeRange = { minimum = FADE_MIN, maximum = FADE_MAX, step = FADE_STEP }
Visibility.shownRange = { minimum = SHOWN_MIN, maximum = ALPHA_MAX, step = ALPHA_STEP }
Visibility.hiddenRange = { minimum = HIDDEN_MIN, maximum = ALPHA_MAX, step = ALPHA_STEP }
Visibility.option = "uiVisibility"
-- Opt-in extras a group may carry, each behind its own boolean option.
Visibility.extraOptions = { uiVisibilityBlobs = true }

-- Every frame name is a string resolved at enable, never a global read here: a frame the
-- client lacks costs its group, not the module. frames must all exist for the group to be
-- available; optional ones join when present. hover says where a mouseover comes from:
-- frames hooks OnEnter and OnLeave on each frame, children on each frame's children too (a
-- number is how many levels down),
-- chat rides Blizzard's own chat fade calls (chat frames take no mouse of their own), and
-- editBox keeps a chat window shown while its edit box has focus. reapply names what to
-- hook when Blizzard writes an alpha of its own: a global function name, or a frame and
-- method. kind picks a preset's rule. Alpha multiplies down the frame tree, so a group
-- whose frames sit inside another group's frames can never be more visible than its parent;
-- noteKey says so on the panel.
Visibility.groups = {
    { id = "chat.frames", kind = "chat", labelKey = "VIS_GROUP_CHAT_FRAMES",
        frames = { "ChatFrame1" },
        optional = { "ChatFrame2", "ChatFrame3", "ChatFrame4", "ChatFrame5", "ChatFrame6", "ChatFrame7",
            "ChatFrame8", "ChatFrame9", "ChatFrame10" },
        hover = { chat = true, editBox = true }, reapply = {} },
    -- Docked tabs live under the dock; Blizzard animates each tab's own alpha, so the dock is
    -- the one place a fade of ours does not fight one of theirs.
    { id = "chat.tabs", kind = "chat", labelKey = "VIS_GROUP_CHAT_TABS",
        frames = { "GeneralDockManager" }, optional = {},
        hover = { chat = true, frames = true, children = true }, reapply = {}, noteKey = "VIS_NOTE_TABS" },
    { id = "chat.buttons", kind = "chat", labelKey = "VIS_GROUP_CHAT_BUTTONS",
        frames = { "ChatFrame1ButtonFrame" },
        optional = { "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton",
            "TextToSpeechButtonFrame" },
        hover = { frames = true, children = true }, reapply = {}, noteKey = "VIS_NOTE_NESTED" },
    { id = "bars.main", kind = "bars", labelKey = "VIS_GROUP_BAR_1", frames = { "MainActionBar" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.bottomLeft", kind = "bars", labelKey = "VIS_GROUP_BAR_2", frames = { "MultiBarBottomLeft" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.bottomRight", kind = "bars", labelKey = "VIS_GROUP_BAR_3", frames = { "MultiBarBottomRight" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.right", kind = "bars", labelKey = "VIS_GROUP_BAR_4", frames = { "MultiBarRight" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.left", kind = "bars", labelKey = "VIS_GROUP_BAR_5", frames = { "MultiBarLeft" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.five", kind = "bars", labelKey = "VIS_GROUP_BAR_6", frames = { "MultiBar5" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.six", kind = "bars", labelKey = "VIS_GROUP_BAR_7", frames = { "MultiBar6" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.seven", kind = "bars", labelKey = "VIS_GROUP_BAR_8", frames = { "MultiBar7" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.pet", kind = "bars", labelKey = "VIS_GROUP_PET_BAR", frames = { "PetActionBar" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    { id = "bars.stance", kind = "bars", labelKey = "VIS_GROUP_STANCE_BAR", frames = { "StanceBar" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    -- Edit Mode has an opacity setting for the unit frames and writes it through this method;
    -- what it writes is the frame's new resting alpha, so the hook takes it as the baseline.
    { id = "unit.player", kind = "unit", labelKey = "VIS_GROUP_PLAYER", frames = { "PlayerFrame" },
        optional = {}, hover = { frames = true, children = 2 },
        reapply = { { frame = "PlayerFrame", method = "UpdateSystemSettingOpacity", baseline = true } },
        noteKey = "VIS_NOTE_PLAYER" },
    { id = "unit.target", kind = "unit", labelKey = "VIS_GROUP_TARGET", frames = { "TargetFrame" },
        optional = {}, hover = { frames = true, children = 2 },
        reapply = { { frame = "TargetFrame", method = "UpdateSystemSettingOpacity", baseline = true } } },
    { id = "hud.status", kind = "hud", labelKey = "VIS_GROUP_STATUS", frames = { "StatusTrackingBarManager" },
        optional = {}, hover = { frames = true, children = 2 }, reapply = {} },
    { id = "hud.microMenu", kind = "hud", labelKey = "VIS_GROUP_MICRO_MENU", frames = { "MicroMenuContainer" },
        optional = {}, hover = { frames = true, children = 2 }, reapply = {} },
    { id = "hud.bags", kind = "hud", labelKey = "VIS_GROUP_BAGS", frames = { "BagsBar" },
        optional = {}, hover = { frames = true, children = true }, reapply = {} },
    -- Quest blocks are pooled and made as quests arrive, so only the ones present at enable
    -- carry a hover hook; the tracker frame itself takes no mouse.
    { id = "hud.objectives", kind = "hud", labelKey = "VIS_GROUP_OBJECTIVES", frames = { "ObjectiveTrackerFrame" },
        optional = {}, hover = { frames = true, children = 3 }, reapply = {}, noteKey = "VIS_NOTE_OBJECTIVES" },
    -- The client draws the quest, task and dig-site areas inside the Minimap widget, past
    -- any frame alpha, and offers setters for their alpha but no getters and no default in
    -- its own UI code. So fading them is opt-in, and what they come back to when shown is
    -- Refactor's own: the ring on, the fills off, the look Blizzard ships as far as the eye
    -- can tell. The player arrow has no alpha of any kind on this client and stays.
    { id = "hud.minimap", kind = "hud", labelKey = "VIS_GROUP_MINIMAP", frames = { "MinimapCluster" },
        optional = {}, hover = { frames = true, children = 3 }, reapply = {}, noteKey = "VIS_NOTE_MINIMAP",
        extras = { { frame = "Minimap", option = "uiVisibilityBlobs", alphas = {
            SetQuestBlobRingAlpha = 1, SetQuestBlobInsideAlpha = 0, SetQuestBlobOutsideAlpha = 0,
            SetTaskBlobRingAlpha = 1, SetTaskBlobInsideAlpha = 0, SetTaskBlobOutsideAlpha = 0,
            SetArchBlobRingAlpha = 1, SetArchBlobInsideAlpha = 0, SetArchBlobOutsideAlpha = 0,
        } } } },
    { id = "hud.minimapButtons", kind = "hud", labelKey = "VIS_GROUP_MINIMAP_BUTTONS",
        frames = { "GameTimeFrame", "TimeManagerClockButton", "MinimapCluster.Tracking" },
        optional = { "AddonCompartmentFrame", "MinimapCluster.IndicatorFrame", "Minimap.ZoomIn", "Minimap.ZoomOut",
            "ExpansionLandingPageMinimapButton" },
        hover = { frames = true, children = true }, reapply = {}, noteKey = "VIS_NOTE_MINIMAP_BUTTONS" },
}
-- The chat edit box's background and border are textures, which take no mouse, so this group
-- has no hover source and mouseover on it acts as hidden. The typed text is not touched.
local INPUT_ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local function inputArt(index)
    local names = {}
    for _, suffix in ipairs(INPUT_ART) do
        names[#names + 1] = "ChatFrame" .. index .. "EditBox" .. suffix
    end
    return names
end
local inputArtOptional = {}
for index = 2, 10 do
    for _, name in ipairs(inputArt(index)) do
        inputArtOptional[#inputArtOptional + 1] = name
    end
end
table.insert(Visibility.groups, 4, { id = "chat.inputArt", kind = "art", labelKey = "VIS_GROUP_CHAT_INPUT_ART",
    frames = inputArt(1), optional = inputArtOptional, hover = {}, reapply = {}, noteKey = "VIS_NOTE_INPUT_ART" })
local GROUP_BY_ID = {}
for _, group in ipairs(Visibility.groups) do
    GROUP_BY_ID[group.id] = group
end

local function spec(mode, showWhen, hideWhen)
    return { mode = mode, showWhen = showWhen or {}, hideWhen = hideWhen or {} }
end

-- A preset writes a rule for every group: the rule for its kind, else the default. Fade
-- times are the player's and survive a preset.
Visibility.presets = {
    { id = "immersion", nameKey = "VIS_PRESET_IMMERSION", detailKey = "VIS_PRESET_IMMERSION_DETAIL",
        rules = { default = spec("mouseover"), art = spec("hidden") } },
    { id = "combatOnly", nameKey = "VIS_PRESET_COMBAT", detailKey = "VIS_PRESET_COMBAT_DETAIL",
        rules = { default = spec("mouseover"), bars = spec("hidden", { combat = true }),
            unit = spec("hidden", { combat = true }), art = spec("hidden") } },
    { id = "mounted", nameKey = "VIS_PRESET_MOUNTED", detailKey = "VIS_PRESET_MOUNTED_DETAIL",
        rules = { default = spec("always", nil, { mounted = true }) } },
    { id = "off", nameKey = "VIS_PRESET_OFF", detailKey = "VIS_PRESET_OFF_DETAIL",
        rules = { default = spec("always") } },
}
Visibility.customPreset = "custom"
Visibility.defaultPreset = "off"
local PRESET_BY_ID = {}
for _, preset in ipairs(Visibility.presets) do
    PRESET_BY_ID[preset.id] = preset
end

local function copySet(set)
    local result = {}
    for name in pairs(set or {}) do
        result[name] = true
    end
    return result
end

local function complete(stored)
    stored = type(stored) == "table" and stored or {}
    return {
        mode = stored.mode or "always",
        showWhen = copySet(stored.showWhen), hideWhen = copySet(stored.hideWhen),
        fadeIn = stored.fadeIn or DEFAULT_FADE_IN, fadeOut = stored.fadeOut or DEFAULT_FADE_OUT,
        shownAlpha = stored.shownAlpha or DEFAULT_SHOWN, hiddenAlpha = stored.hiddenAlpha or DEFAULT_HIDDEN,
    }
end

function Visibility:Group(id)
    return GROUP_BY_ID[id]
end

function Visibility:Preset(id)
    return PRESET_BY_ID[id]
end

function Visibility:DefaultRule()
    return complete(nil)
end

local function validSet(set)
    if type(set) ~= "table" then
        return false
    end
    for name, value in pairs(set) do
        if not CONDITIONS[name] or value ~= true then
            return false
        end
    end
    return true
end

local function validNumber(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum and value <= maximum
end

function Visibility:ValidRule(rule)
    if type(rule) ~= "table" then
        return false
    end
    local count = 0
    for _ in pairs(rule) do
        count = count + 1
    end
    return count == RULE_FIELDS and MODES[rule.mode] == true and validSet(rule.showWhen) and validSet(rule.hideWhen)
        and validNumber(rule.fadeIn, FADE_MIN, FADE_MAX) and validNumber(rule.fadeOut, FADE_MIN, FADE_MAX)
        and validNumber(rule.shownAlpha, SHOWN_MIN, ALPHA_MAX) and validNumber(rule.hiddenAlpha, HIDDEN_MIN, ALPHA_MAX)
end

-- The whole saved option. Unknown group ids are kept: a group this build lacks may come back.
function Visibility:ValidSettings(value)
    if type(value) ~= "table" or type(value.groups) ~= "table" then
        return false
    end
    if value.preset ~= self.customPreset and not PRESET_BY_ID[value.preset] then
        return false
    end
    local count = 0
    for id, rule in pairs(value.groups) do
        count = count + 1
        if count > MAX_GROUPS or not R.Codec:ValidID(id) or not self:ValidRule(rule) then
            return false
        end
    end
    return true
end

-- The pure decision, as the share of the frame's own alpha to show. hover only means
-- anything to a mouseover rule; a show condition beats a hide condition, so "hide when
-- mounted, but show in combat" reads the way it sounds.
function Visibility:Resolve(rule, state, hovered)
    local shown, hidden = rule.shownAlpha, rule.hiddenAlpha
    if hovered and rule.mode == "mouseover" then
        return shown
    end
    for name in pairs(rule.showWhen) do
        if state[name] then
            return shown
        end
    end
    for name in pairs(rule.hideWhen) do
        if state[name] then
            return hidden
        end
    end
    return rule.mode == "always" and shown or hidden
end

-- A fresh copy of the saved option with every rule completed, so a caller can edit and hand
-- it back without touching the account table.
function Visibility:Settings()
    local stored = R.Settings:GetOption(self.option)
    local groups, storedGroups = {}, type(stored) == "table" and stored.groups or nil
    if type(storedGroups) == "table" then
        for id, rule in pairs(storedGroups) do
            groups[id] = complete(rule)
        end
    end
    return { preset = type(stored) == "table" and stored.preset or self.defaultPreset, groups = groups }
end

function Visibility:Rule(groupId)
    local stored = R.Settings:GetOption(self.option)
    return complete(type(stored) == "table" and type(stored.groups) == "table" and stored.groups[groupId] or nil)
end

function Visibility:ApplyPreset(id)
    local preset = PRESET_BY_ID[id]
    if not preset then
        return false
    end
    local settings = self:Settings()
    for _, group in ipairs(self.groups) do
        local wanted = preset.rules[group.kind] or preset.rules.default
        local rule = complete(settings.groups[group.id])
        rule.mode, rule.showWhen, rule.hideWhen = wanted.mode, copySet(wanted.showWhen), copySet(wanted.hideWhen)
        settings.groups[group.id] = rule
    end
    settings.preset = id
    return R.Settings:SetOption(self.option, settings)
end

-- The same patch onto several groups in one write, so listeners see it once. A hand edit
-- to the rule makes the selection "custom": a preset is a starting point, not a mode the
-- player is held to. Fade times and opacities are tuning and keep the preset's name.
function Visibility:SetRules(groupIds, patch)
    if type(groupIds) ~= "table" or type(patch) ~= "table" then
        return false
    end
    local settings, count = self:Settings(), 0
    for _, id in ipairs(groupIds) do
        if not GROUP_BY_ID[id] then
            return false
        end
        local rule = complete(settings.groups[id])
        for key, value in pairs(patch) do
            rule[key] = type(value) == "table" and copySet(value) or value
        end
        if not self:ValidRule(rule) then
            return false
        end
        settings.groups[id] = rule
        count = count + 1
    end
    if count == 0 then
        return false
    end
    if patch.mode ~= nil or patch.showWhen ~= nil or patch.hideWhen ~= nil then
        settings.preset = self.customPreset
    end
    return R.Settings:SetOption(self.option, settings)
end

function Visibility:SetRule(groupId, patch)
    return self:SetRules({ groupId }, patch)
end
