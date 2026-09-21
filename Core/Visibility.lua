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
local MAX_GROUPS, RULE_FIELDS = 32, 8
-- How visible an element is when its rule says shown, and when it says hidden: a share of
-- the alpha the game gives the frame, so an Edit Mode opacity still counts. Shown never
-- goes below a tenth, or an element could be lost with no rule saying so.
local SHOWN_MIN, HIDDEN_MIN, ALPHA_MAX, ALPHA_STEP = 0.1, 0, 1, 0.05
local DEFAULT_SHOWN, DEFAULT_HIDDEN = 1, 0
Visibility.fadeRange = { minimum = FADE_MIN, maximum = FADE_MAX, step = FADE_STEP }
Visibility.shownRange = { minimum = SHOWN_MIN, maximum = ALPHA_MAX, step = ALPHA_STEP }
Visibility.hiddenRange = { minimum = HIDDEN_MIN, maximum = ALPHA_MAX, step = ALPHA_STEP }
Visibility.option = "uiVisibility"
-- A zone is hovered while any element in it is, so the bars, the bags and the micro menu
-- along the bottom come and go as one. The names are where things usually sit; an
-- element can be put in any of them.
Visibility.zones = { "none", "bottom", "top", "left", "right" }
Visibility.noZone = "none"
local ZONES = {}
for _, zone in ipairs(Visibility.zones) do
    ZONES[zone] = true
end
-- Opt-in extras a group may carry, each behind its own boolean option.
Visibility.extraOptions = { uiVisibilityBlobs = true }

-- Every frame name is a string resolved at enable, never a global read here: a frame the
-- client lacks costs its group, not the module. frames must all exist for the group to be
-- available; optional ones join when present. hover says where a mouseover comes from:
-- frames hooks OnEnter on each frame that is not secure, children on each frame's children
-- too (a number is how many levels down), tooltip takes the hover from GameTooltip naming
-- one of the group's frames as its owner (the only signal a secure button gives), chat
-- rides Blizzard's own chat fade call, and editBox keeps a chat window shown while its
-- edit box has focus. Leaving is never an event: a watch checks the mouse while anything
-- is hovered. reapply names what to
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
        hover = { tooltip = true, frames = true, children = true }, reapply = {}, noteKey = "VIS_NOTE_NESTED" },
    { id = "bars.main", kind = "bars", labelKey = "VIS_GROUP_BAR_1", frames = { "MainActionBar" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.bottomLeft", kind = "bars", labelKey = "VIS_GROUP_BAR_2", frames = { "MultiBarBottomLeft" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.bottomRight", kind = "bars", labelKey = "VIS_GROUP_BAR_3", frames = { "MultiBarBottomRight" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.right", kind = "bars", labelKey = "VIS_GROUP_BAR_4", frames = { "MultiBarRight" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.left", kind = "bars", labelKey = "VIS_GROUP_BAR_5", frames = { "MultiBarLeft" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.five", kind = "bars", labelKey = "VIS_GROUP_BAR_6", frames = { "MultiBar5" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.six", kind = "bars", labelKey = "VIS_GROUP_BAR_7", frames = { "MultiBar6" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.seven", kind = "bars", labelKey = "VIS_GROUP_BAR_8", frames = { "MultiBar7" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.pet", kind = "bars", labelKey = "VIS_GROUP_PET_BAR", frames = { "PetActionBar" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    { id = "bars.stance", kind = "bars", labelKey = "VIS_GROUP_STANCE_BAR", frames = { "StanceBar" },
        optional = {}, hover = { tooltip = true, frames = true }, reapply = {} },
    -- Unit frames are secure buttons, so no script of theirs is hooked: hover rides their tooltip.
    -- Edit Mode has an opacity setting for them and writes it through this method; what it
    -- writes is the frame's new resting alpha, so the hook takes it as the baseline.
    { id = "unit.player", kind = "unit", labelKey = "VIS_GROUP_PLAYER", frames = { "PlayerFrame" },
        optional = {}, hover = { tooltip = true },
        reapply = { { frame = "PlayerFrame", method = "UpdateSystemSettingOpacity", baseline = true } },
        noteKey = "VIS_NOTE_PLAYER" },
    { id = "unit.target", kind = "unit", labelKey = "VIS_GROUP_TARGET", frames = { "TargetFrame" },
        optional = {}, hover = { tooltip = true },
        reapply = { { frame = "TargetFrame", method = "UpdateSystemSettingOpacity", baseline = true } } },
    { id = "unit.party", kind = "unit", labelKey = "VIS_GROUP_PARTY", frames = { "PartyFrame" },
        optional = {}, hover = { tooltip = true },
        reapply = { { frame = "PartyFrame", method = "UpdateSystemSettingOpacity", baseline = true } } },
    -- The manager is the tab at the screen edge; a plain frame, so its own scripts are hooked.
    { id = "unit.raid", kind = "unit", labelKey = "VIS_GROUP_RAID", frames = { "CompactRaidFrameContainer" },
        optional = { "CompactRaidFrameManager" }, hover = { tooltip = true, frames = true },
        reapply = { { frame = "CompactRaidFrameContainer", method = "UpdateSystemSettingOpacity", baseline = true } },
        noteKey = "VIS_NOTE_RAID" },
    { id = "hud.status", kind = "hud", labelKey = "VIS_GROUP_STATUS", frames = { "StatusTrackingBarManager" },
        optional = {}, hover = { tooltip = true, frames = true, children = 2 }, reapply = {} },
    { id = "hud.microMenu", kind = "hud", labelKey = "VIS_GROUP_MICRO_MENU", frames = { "MicroMenuContainer" },
        optional = {}, hover = { tooltip = true, frames = true, children = 2 }, reapply = {} },
    { id = "hud.bags", kind = "hud", labelKey = "VIS_GROUP_BAGS", frames = { "BagsBar" },
        optional = {}, hover = { tooltip = true, frames = true, children = true }, reapply = {} },
    -- Quest blocks are pooled and made as quests arrive, so only the ones present at enable
    -- carry a hover hook; the tracker frame itself takes no mouse.
    { id = "hud.objectives", kind = "hud", labelKey = "VIS_GROUP_OBJECTIVES", frames = { "ObjectiveTrackerFrame" },
        optional = {}, hover = { tooltip = true, frames = true, children = 3 }, reapply = {},
        noteKey = "VIS_NOTE_OBJECTIVES" },
    -- The client draws the quest, task and dig-site areas inside the Minimap widget, past
    -- any frame alpha, and offers setters for their alpha but no getters and no default in
    -- its own UI code. So fading them is opt-in, and what they come back to when shown is
    -- Refactor's own: the ring on, the fills off, the look Blizzard ships as far as the eye
    -- can tell. The player arrow has no alpha of any kind on this client and stays.
    { id = "hud.minimap", kind = "hud", labelKey = "VIS_GROUP_MINIMAP", frames = { "MinimapCluster" },
        optional = {}, hover = { tooltip = true, frames = true, children = 3 }, reapply = {},
        noteKey = "VIS_NOTE_MINIMAP",
        extras = { { frame = "Minimap", option = "uiVisibilityBlobs", alphas = {
            SetQuestBlobRingAlpha = 1, SetQuestBlobInsideAlpha = 0, SetQuestBlobOutsideAlpha = 0,
            SetTaskBlobRingAlpha = 1, SetTaskBlobInsideAlpha = 0, SetTaskBlobOutsideAlpha = 0,
            SetArchBlobRingAlpha = 1, SetArchBlobInsideAlpha = 0, SetArchBlobOutsideAlpha = 0,
        } } } },
    { id = "hud.minimapButtons", kind = "hud", labelKey = "VIS_GROUP_MINIMAP_BUTTONS",
        frames = { "GameTimeFrame", "TimeManagerClockButton", "MinimapCluster.Tracking" },
        optional = { "AddonCompartmentFrame", "MinimapCluster.IndicatorFrame", "Minimap.ZoomIn", "Minimap.ZoomOut",
            "ExpansionLandingPageMinimapButton" },
        hover = { tooltip = true, frames = true, children = true }, reapply = {},
        noteKey = "VIS_NOTE_MINIMAP_BUTTONS" },
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

-- Where each element usually sits, which is the zone a preset puts it in.
local ZONE_DEFAULTS = {
    ["chat.frames"] = "left", ["chat.tabs"] = "left", ["chat.buttons"] = "left", ["chat.inputArt"] = "left",
    ["unit.player"] = "top", ["unit.target"] = "top", ["unit.party"] = "top", ["unit.raid"] = "top",
    ["hud.status"] = "bottom", ["hud.microMenu"] = "bottom", ["hud.bags"] = "bottom",
    ["hud.objectives"] = "right", ["hud.minimap"] = "right", ["hud.minimapButtons"] = "right",
}
for _, group in ipairs(Visibility.groups) do
    if group.kind == "bars" then
        ZONE_DEFAULTS[group.id] = "bottom"
    end
end
Visibility.zoneDefaults = ZONE_DEFAULTS

-- Which Edit Mode system frame each group is tuned from: selecting that system in Edit
-- Mode opens the group's settings beside Blizzard's own dialog. An element with no system
-- of its own hangs off the one it sits inside, so every group is reachable.
local CHAT, MINIMAP = { "ChatFrame1" }, { "MinimapCluster" }
local STATUS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
Visibility.systems = {
    ["chat.frames"] = CHAT, ["chat.tabs"] = CHAT, ["chat.buttons"] = CHAT, ["chat.inputArt"] = CHAT,
    ["bars.main"] = { "MainActionBar" }, ["bars.bottomLeft"] = { "MultiBarBottomLeft" },
    ["bars.bottomRight"] = { "MultiBarBottomRight" }, ["bars.right"] = { "MultiBarRight" },
    ["bars.left"] = { "MultiBarLeft" }, ["bars.five"] = { "MultiBar5" }, ["bars.six"] = { "MultiBar6" },
    ["bars.seven"] = { "MultiBar7" }, ["bars.pet"] = { "PetActionBar" }, ["bars.stance"] = { "StanceBar" },
    ["unit.player"] = { "PlayerFrame" }, ["unit.target"] = { "TargetFrame" },
    ["unit.party"] = { "PartyFrame" }, ["unit.raid"] = { "CompactRaidFrameContainer" },
    ["hud.status"] = STATUS, ["hud.microMenu"] = { "MicroMenuContainer" }, ["hud.bags"] = { "BagsBar" },
    ["hud.objectives"] = { "ObjectiveTrackerFrame" }, ["hud.minimap"] = MINIMAP, ["hud.minimapButtons"] = MINIMAP,
}

-- The groups a selected Edit Mode system frame stands for, in catalogue order.
function Visibility:GroupsForSystem(systemFrame, into)
    local ids = into or {}
    for index = #ids, 1, -1 do
        ids[index] = nil
    end
    if type(systemFrame) ~= "table" then
        return ids
    end
    for _, group in ipairs(self.groups) do
        for _, name in ipairs(self.systems[group.id] or {}) do
            if R.Capabilities:Resolve(name) == systemFrame then
                ids[#ids + 1] = group.id
                break
            end
        end
    end
    return ids
end

-- Ids of the other groups of the same kind, the ones "same for all" reaches.
function Visibility:Siblings(id, into)
    local group, siblings = GROUP_BY_ID[id], into or {}
    for index = #siblings, 1, -1 do
        siblings[index] = nil
    end
    for _, other in ipairs(self.groups) do
        if group and other.kind == group.kind and other.id ~= id then
            siblings[#siblings + 1] = other.id
        end
    end
    return siblings
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
        zone = stored.zone or Visibility.noZone,
    }
end

function Visibility:Group(id)
    return GROUP_BY_ID[id]
end

-- Frames Refactor makes itself can join a group. Nothing Refactor creates carries a global
-- name, because only Namespace writes globals, so the catalogue above cannot name one: the
-- module that owns the frame hands it over here and the visibility module reads it back.
-- That keeps the two modules from ever naming each other.
local CONTRIBUTED = {}
local NO_FRAMES = {}

function Visibility:Contribute(groupId, frame)
    if not GROUP_BY_ID[groupId] or type(frame) ~= "table" then
        return false
    end
    local frames = CONTRIBUTED[groupId]
    if not frames then
        frames = {}
        CONTRIBUTED[groupId] = frames
    end
    for _, existing in ipairs(frames) do
        if existing == frame then
            return true
        end
    end
    frames[#frames + 1] = frame
    R.Broker:Emit("REFACTOR_VISIBILITY_FRAMES", groupId)
    return true
end

function Visibility:Withdraw(groupId, frame)
    local frames = CONTRIBUTED[groupId]
    if not frames then
        return false
    end
    for index = #frames, 1, -1 do
        if frames[index] == frame then
            table.remove(frames, index)
            R.Broker:Emit("REFACTOR_VISIBILITY_FRAMES", groupId)
            return true
        end
    end
    return false
end

function Visibility:Contributions(groupId)
    return CONTRIBUTED[groupId] or NO_FRAMES
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
        and ZONES[rule.zone] == true
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
        rule.zone = ZONE_DEFAULTS[group.id] or self.noZone
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
    if patch.mode ~= nil or patch.showWhen ~= nil or patch.hideWhen ~= nil or patch.zone ~= nil then
        settings.preset = self.customPreset
    end
    return R.Settings:SetOption(self.option, settings)
end

function Visibility:SetRule(groupId, patch)
    return self:SetRules({ groupId }, patch)
end
