--- @core visibility
--- Purpose: the frame groups UI visibility fades, the behaviours and setups that say how, and the resolver.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Visibility = {}
R.Visibility = Visibility

-- What a behaviour can reveal or hide on, in the order the editor lists them. The instance
-- kinds Conditions also tracks pick a setup instead, so they are not offered here.
Visibility.conditions = { "combat", "casting", "hasTarget", "mounted", "resting", "inGroup", "inInstance",
    "stealthed", "dead" }
local CONDITIONS = {}
for _, name in ipairs(Visibility.conditions) do
    CONDITIONS[name] = true
end
local FADE_MIN, FADE_MAX, FADE_STEP = 0, 2, 0.05
local DEFAULT_FADE_IN, DEFAULT_FADE_OUT = 0.15, 0.4
-- Opacities are a share of the alpha the game gives the frame, so an Edit Mode opacity
-- still counts. Revealed never goes below a tenth, or an element could be lost with no rule
-- saying so; resting may be zero, which is the whole point of most behaviours.
local RESTING_MIN, REVEALED_MIN, ALPHA_MAX, ALPHA_STEP = 0, 0.1, 1, 0.05
local MAX_BEHAVIOURS, MAX_ASSIGNED, MAX_NAME = 30, 64, 32
Visibility.fadeRange = { minimum = FADE_MIN, maximum = FADE_MAX, step = FADE_STEP }
Visibility.restingRange = { minimum = RESTING_MIN, maximum = ALPHA_MAX, step = ALPHA_STEP }
Visibility.revealedRange = { minimum = REVEALED_MIN, maximum = ALPHA_MAX, step = ALPHA_STEP }
-- How an element with no behaviour comes back to the game's own alpha.
Visibility.defaultFades = { fadeIn = DEFAULT_FADE_IN, fadeOut = DEFAULT_FADE_OUT }
Visibility.option = "uiVisibility"
-- Where a setup applies. World is everywhere else and always exists; the rest are optional,
-- and a place without its own uses World's.
Visibility.places = { "world", "city", "dungeon", "raid", "pvp" }
Visibility.world = "world"
local PLACES = {}
for _, place in ipairs(Visibility.places) do
    PLACES[place] = true
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
-- method. kind is the heading the setup list files it under. Alpha multiplies down the frame tree, so a group
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
table.insert(Visibility.groups, 4, { id = "chat.inputArt", kind = "chat", labelKey = "VIS_GROUP_CHAT_INPUT_ART",
    frames = inputArt(1), optional = inputArtOptional, hover = {}, reapply = {}, noteKey = "VIS_NOTE_INPUT_ART" })
local GROUP_BY_ID = {}
for _, group in ipairs(Visibility.groups) do
    GROUP_BY_ID[group.id] = group
end

-- The headings of the setup list, in order.
Visibility.kinds = { "chat", "bars", "unit", "hud" }

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

local function copySet(set)
    local result = {}
    for name in pairs(set or {}) do
        result[name] = true
    end
    return result
end

local function behaviour(id, resting, mouseover, reveal, hide, together)
    return { id = id, resting = resting, revealed = 1, mouseover = mouseover, reveal = reveal, hide = hide,
        together = together, fadeIn = DEFAULT_FADE_IN, fadeOut = DEFAULT_FADE_OUT }
end

-- The starters stand in for the presets the first version had. They are ordinary behaviours
-- once saved: the player can edit, copy or delete them. With no name of their own they are
-- named by their locale key, so the names follow the client's language.
Visibility.starters = {
    behaviour("fadeAway", 0, true, {}, {}, true),
    behaviour("combatHud", 0.2, true, { combat = true, hasTarget = true }, {}, false),
    behaviour("cleanMounted", 1, true, {}, { mounted = true }, false),
}

local function copyBehaviour(source)
    return { id = source.id, name = source.name, resting = source.resting, revealed = source.revealed,
        mouseover = source.mouseover, reveal = copySet(source.reveal), hide = copySet(source.hide),
        together = source.together, fadeIn = source.fadeIn, fadeOut = source.fadeOut }
end

local function starterCopies()
    local list = {}
    for index, starter in ipairs(Visibility.starters) do
        list[index] = copyBehaviour(starter)
    end
    return list
end

-- A fresh install assigns nothing, so turning the feature on changes nothing on screen
-- until the player gives an element a behaviour.
function Visibility:Default()
    return { behaviours = starterCopies(), setups = { world = {} } }
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

-- How a behaviour is named on screen: the player's own name, else the starter's locale key.
function Visibility:Name(entry)
    if type(entry) ~= "table" then
        return ""
    end
    return entry.name or (R.L and R.L["VIS_BEHAVIOUR_" .. entry.id]) or entry.id
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

local function validName(name)
    return type(name) == "string" and #name > 0 and #name <= MAX_NAME and not name:find("[%c]")
        and not name:find("^%s") and not name:find("%s$")
end

local function validBehaviourId(id)
    return type(id) == "string" and #id <= 24 and id:match("^%a%w*$") ~= nil
end

local BEHAVIOUR_FIELDS = { id = true, name = true, resting = true, revealed = true, mouseover = true,
    reveal = true, hide = true, together = true, fadeIn = true, fadeOut = true }

function Visibility:ValidBehaviour(entry)
    if type(entry) ~= "table" then
        return false
    end
    for key in pairs(entry) do
        if not BEHAVIOUR_FIELDS[key] then
            return false
        end
    end
    if not validBehaviourId(entry.id) or (entry.name ~= nil and not validName(entry.name)) then
        return false
    end
    if not validNumber(entry.resting, RESTING_MIN, ALPHA_MAX)
        or not validNumber(entry.revealed, REVEALED_MIN, ALPHA_MAX)
        or not validNumber(entry.fadeIn, FADE_MIN, FADE_MAX) or not validNumber(entry.fadeOut, FADE_MIN, FADE_MAX) then
        return false
    end
    if type(entry.mouseover) ~= "boolean" or type(entry.together) ~= "boolean" then
        return false
    end
    if not validSet(entry.reveal) or not validSet(entry.hide) then
        return false
    end
    -- A condition does one thing: it reveals or it hides.
    for name in pairs(entry.reveal) do
        if entry.hide[name] then
            return false
        end
    end
    return true
end

-- Element ids to behaviour ids, every one of which must exist. Unknown element ids are
-- kept: a group this build lacks may come back.
local function validSetup(setup, ids)
    if type(setup) ~= "table" then
        return false
    end
    local count = 0
    for groupId, behaviourId in pairs(setup) do
        count = count + 1
        if count > MAX_ASSIGNED or not R.Codec:ValidID(groupId) or not ids[behaviourId] then
            return false
        end
    end
    return true
end

function Visibility:ValidSettings(value)
    if type(value) ~= "table" or type(value.behaviours) ~= "table" or type(value.setups) ~= "table" then
        return false
    end
    for key in pairs(value) do
        if key ~= "behaviours" and key ~= "setups" then
            return false
        end
    end
    local ids, count = {}, 0
    for _ in pairs(value.behaviours) do
        count = count + 1
    end
    if count > MAX_BEHAVIOURS then
        return false
    end
    for index = 1, count do
        local entry = value.behaviours[index]
        if not self:ValidBehaviour(entry) or ids[entry.id] then
            return false
        end
        ids[entry.id] = true
    end
    if type(value.setups.world) ~= "table" then
        return false
    end
    for place, setup in pairs(value.setups) do
        if not PLACES[place] or not validSetup(setup, ids) then
            return false
        end
    end
    return true
end

local function sortedNames(set)
    local names = {}
    for name in pairs(set) do
        names[#names + 1] = name
    end
    table.sort(names)
    return table.concat(names, ",")
end

-- The first version's rule for one element as a behaviour, or nil when the rule left the
-- element as the game has it. Its show conditions beat its hide conditions, so a condition
-- in both stays a reveal; a hide used to take the element to its hidden opacity and now
-- takes it to 0.
local function fromRule(rule)
    if type(rule) ~= "table" then
        return nil
    end
    local mode = rule.mode or "always"
    local shown = validNumber(rule.shownAlpha, REVEALED_MIN, ALPHA_MAX) and rule.shownAlpha or 1
    local hidden = validNumber(rule.hiddenAlpha, RESTING_MIN, ALPHA_MAX) and rule.hiddenAlpha or 0
    local showWhen = validSet(rule.showWhen) and rule.showWhen or {}
    local hideWhen = validSet(rule.hideWhen) and rule.hideWhen or {}
    if mode ~= "always" and mode ~= "mouseover" and mode ~= "hidden" then
        return nil
    end
    if mode == "always" and next(hideWhen) == nil and shown == 1 then
        return nil
    end
    local entry = behaviour(nil, hidden, mode == "mouseover", copySet(showWhen), copySet(hideWhen),
        type(rule.zone) == "string" and rule.zone ~= "none")
    entry.revealed = shown
    if mode == "always" then
        entry.resting, entry.reveal = shown, {}
    end
    for name in pairs(entry.reveal) do
        entry.hide[name] = nil
    end
    entry.fadeIn = validNumber(rule.fadeIn, FADE_MIN, FADE_MAX) and rule.fadeIn or DEFAULT_FADE_IN
    entry.fadeOut = validNumber(rule.fadeOut, FADE_MIN, FADE_MAX) and rule.fadeOut or DEFAULT_FADE_OUT
    return entry
end

-- Elements whose rules match share one behaviour. The zone is part of the match, so the
-- elements of one zone keep coming back together and two zones never merge into one.
local function ruleKey(entry, zone)
    return string.format("%s|%s|%s|%s|%s|%s|%s|%s", tostring(entry.resting), tostring(entry.revealed),
        tostring(entry.mouseover), sortedNames(entry.reveal), sortedNames(entry.hide), tostring(zone),
        tostring(entry.fadeIn), tostring(entry.fadeOut))
end

local function upgrade(old)
    local result = { behaviours = starterCopies(), setups = { world = {} } }
    local order, unknown = {}, {}
    for _, group in ipairs(Visibility.groups) do
        if old.groups[group.id] ~= nil then
            order[#order + 1] = group.id
        end
    end
    for id in pairs(old.groups) do
        if type(id) == "string" and not GROUP_BY_ID[id] then
            unknown[#unknown + 1] = id
        end
    end
    table.sort(unknown)
    for _, id in ipairs(unknown) do
        order[#order + 1] = id
    end
    local byKey, imported = {}, 0
    local nameFormat = R.L and R.L.VIS_IMPORTED_NAME
    for _, groupId in ipairs(order) do
        local rule = old.groups[groupId]
        local entry = R.Codec:ValidID(groupId) and fromRule(rule)
        if entry then
            local key = ruleKey(entry, rule.zone)
            if not byKey[key] and #result.behaviours < MAX_BEHAVIOURS then
                imported = imported + 1
                entry.id = string.format("imported%d", imported)
                entry.name = nameFormat and string.format(nameFormat, imported) or nil
                result.behaviours[#result.behaviours + 1] = entry
                byKey[key] = entry.id
            end
            result.setups.world[groupId] = byKey[key]
        end
    end
    return result
end

-- Run at login before the saved option is checked. The first version's rules are converted,
-- and a bad behaviour or assignment is dropped on its own rather than costing the player
-- every other one, which the all-or-nothing check after it would.
function Visibility:Clean(value)
    if type(value) ~= "table" then
        return nil
    end
    if value.behaviours == nil and type(value.groups) == "table" then
        return upgrade(value)
    end
    local clean, ids = { behaviours = {}, setups = {} }, {}
    for _, entry in ipairs(type(value.behaviours) == "table" and value.behaviours or {}) do
        if #clean.behaviours < MAX_BEHAVIOURS and self:ValidBehaviour(entry) and not ids[entry.id] then
            ids[entry.id] = true
            clean.behaviours[#clean.behaviours + 1] = copyBehaviour(entry)
        end
    end
    local setups = type(value.setups) == "table" and value.setups or {}
    for _, place in ipairs(self.places) do
        local setup = setups[place]
        if type(setup) == "table" then
            local kept, count = {}, 0
            for groupId, behaviourId in pairs(setup) do
                if count < MAX_ASSIGNED and R.Codec:ValidID(groupId) and ids[behaviourId] then
                    kept[groupId], count = behaviourId, count + 1
                end
            end
            clean.setups[place] = kept
        end
    end
    clean.setups.world = clean.setups.world or {}
    return clean
end

-- Before Settings has the account, GetOption answers with an empty table.
local NOTHING = { behaviours = {}, setups = { world = {} } }

local function live()
    local value = R.Settings:GetOption(Visibility.option)
    if type(value) ~= "table" or type(value.behaviours) ~= "table" or type(value.setups) ~= "table" then
        return NOTHING
    end
    return value
end

-- A fresh copy of the saved option, so a caller can edit it and hand it back without touching
-- the account table.
function Visibility:Settings()
    local value = live()
    local result = { behaviours = {}, setups = {} }
    for index, entry in ipairs(value.behaviours) do
        result.behaviours[index] = copyBehaviour(entry)
    end
    for place, setup in pairs(value.setups) do
        local map = {}
        for groupId, behaviourId in pairs(setup) do
            map[groupId] = behaviourId
        end
        result.setups[place] = map
    end
    result.setups.world = result.setups.world or {}
    return result
end

local function find(list, id)
    for index, entry in ipairs(list) do
        if entry.id == id then
            return entry, index
        end
    end
    return nil
end

-- The saved behaviours, in order. The live list: read it, never keep or edit it.
function Visibility:Behaviours()
    return live().behaviours
end

function Visibility:Behaviour(id)
    return (find(live().behaviours, id))
end

-- How many elements have this behaviour in any setup.
function Visibility:Uses(id)
    local seen, count = {}, 0
    for _, setup in pairs(live().setups) do
        for groupId, behaviourId in pairs(setup) do
            if behaviourId == id and not seen[groupId] then
                seen[groupId], count = true, count + 1
            end
        end
    end
    return count
end

-- The kind of place the player is in. An instance first, because it says more about what
-- the player needs to see than anything inside it, then a rest area, then World.
function Visibility:PlaceOf(state)
    if state.dungeon then
        return "dungeon"
    elseif state.raid then
        return "raid"
    elseif state.pvp then
        return "pvp"
    elseif state.resting then
        return "city"
    end
    return self.world
end

function Visibility:HasOwnSetup(place)
    return place == self.world or type(live().setups[place]) == "table"
end

-- The place whose setup is in use: where the player is when it has a setup of its own, else World.
function Visibility:SetupPlace(state)
    local place = self:PlaceOf(state)
    return self:HasOwnSetup(place) and place or self.world
end

-- An element's behaviour in a place's setup, a place without its own following World's. nil
-- leaves the element as the game has it. The live table: read it, never keep or edit it.
function Visibility:BehaviourFor(groupId, place)
    local value = live()
    local setup = value.setups[place] or value.setups.world
    local id = setup and setup[groupId]
    return id and (find(value.behaviours, id)) or nil
end

-- The pure decision, as the share of the frame's own alpha to show. Mouseover beats
-- everything, so an element can always be reached; a hide beats a reveal, so "hide when
-- mounted" holds whatever else is true.
function Visibility:Resolve(entry, state, hovered)
    if hovered and entry.mouseover then
        return entry.revealed
    end
    for name in pairs(entry.hide) do
        if state[name] then
            return 0
        end
    end
    for name in pairs(entry.reveal) do
        if state[name] then
            return entry.revealed
        end
    end
    return entry.resting
end

function Visibility:ConditionRole(entry, condition)
    if entry.reveal[condition] then
        return "reveal"
    elseif entry.hide[condition] then
        return "hide"
    end
    return nil
end

local function save(settings)
    return R.Settings:SetOption(Visibility.option, settings)
end

-- reveal and hide are written through SetCondition, so a condition never lands in both.
local EDITABLE = { resting = true, revealed = true, mouseover = true, together = true, fadeIn = true, fadeOut = true }

function Visibility:UpdateBehaviour(id, patch)
    if type(patch) ~= "table" then
        return false
    end
    local settings = self:Settings()
    local entry = find(settings.behaviours, id)
    if not entry then
        return false
    end
    for key, value in pairs(patch) do
        if not EDITABLE[key] then
            return false
        end
        entry[key] = value
    end
    return self:ValidBehaviour(entry) and save(settings)
end

-- role is "reveal", "hide", or nil for neither.
function Visibility:SetCondition(id, condition, role)
    if not CONDITIONS[condition] or (role ~= nil and role ~= "reveal" and role ~= "hide") then
        return false
    end
    local settings = self:Settings()
    local entry = find(settings.behaviours, id)
    if not entry then
        return false
    end
    entry.reveal[condition], entry.hide[condition] = nil, nil
    if role then
        entry[role][condition] = true
    end
    return save(settings)
end

local function nameTaken(list, name, except)
    local wanted = name:lower()
    for _, entry in ipairs(list) do
        if entry.id ~= except and Visibility:Name(entry):lower() == wanted then
            return true
        end
    end
    return false
end

-- Cut at a byte limit without leaving half a character behind.
local function cut(text, limit)
    if #text <= limit then
        return text
    end
    return (text:sub(1, limit):gsub("[\192-\255][\128-\191]*$", ""))
end

function Visibility:RenameBehaviour(id, name)
    if type(name) ~= "string" then
        return false, "invalid_name"
    end
    name = name:match("^%s*(.-)%s*$")
    local settings = self:Settings()
    local entry = find(settings.behaviours, id)
    if not entry then
        return false, "missing"
    elseif not validName(name) then
        return false, "invalid_name"
    elseif nameTaken(settings.behaviours, name, id) then
        return false, "name_taken"
    end
    entry.name = name
    return save(settings), nil
end

-- A copy placed right after its source, or with no source a plain new behaviour at the end.
-- Named "<name> copy", then "<name> copy 2" and so on. Returns the new id.
function Visibility:CopyBehaviour(id)
    local settings = self:Settings()
    if #settings.behaviours >= MAX_BEHAVIOURS then
        return nil, "full"
    end
    local L = R.L or {}
    local source, index = find(settings.behaviours, id)
    local entry = source and copyBehaviour(source) or behaviour(nil, 0, true, {}, {}, false)
    local number = 1
    while find(settings.behaviours, string.format("b%d", number)) do
        number = number + 1
    end
    entry.id = string.format("b%d", number)
    local base = source and L.VIS_COPY_NAME and string.format(L.VIS_COPY_NAME, cut(self:Name(source), MAX_NAME - 8))
        or L.VIS_BEHAVIOUR_NEW
    entry.name = nil
    if base then
        local name, suffix = base, 2
        while nameTaken(settings.behaviours, name) do
            name = string.format(L.VIS_NAME_N, cut(base, MAX_NAME - 4), suffix)
            suffix = suffix + 1
        end
        entry.name = name
    end
    table.insert(settings.behaviours, index and index + 1 or #settings.behaviours + 1, entry)
    if not save(settings) then
        return nil, "invalid"
    end
    return entry.id
end

-- Every element that had it goes back to the game's own look.
function Visibility:DeleteBehaviour(id)
    local settings = self:Settings()
    local _, index = find(settings.behaviours, id)
    if not index then
        return false
    end
    table.remove(settings.behaviours, index)
    for _, setup in pairs(settings.setups) do
        for groupId, behaviourId in pairs(setup) do
            if behaviourId == id then
                setup[groupId] = nil
            end
        end
    end
    return save(settings)
end

-- Gives elements a behaviour in one place's setup, or none with a nil behaviourId. A place
-- without a setup of its own has nothing to write to.
function Visibility:Assign(groupIds, place, behaviourId)
    if type(groupIds) ~= "table" or not PLACES[place] then
        return false
    end
    local settings = self:Settings()
    local setup = settings.setups[place]
    if not setup or (behaviourId ~= nil and not find(settings.behaviours, behaviourId)) then
        return false
    end
    local count = 0
    for _, groupId in ipairs(groupIds) do
        if not GROUP_BY_ID[groupId] then
            return false
        end
        setup[groupId] = behaviourId
        count = count + 1
    end
    return count > 0 and save(settings)
end

-- A place's own setup starts as a copy of World's; giving it up goes back to World's.
function Visibility:SetOwnSetup(place, own)
    if not PLACES[place] or place == self.world then
        return false
    end
    local settings = self:Settings()
    if own then
        if settings.setups[place] then
            return true
        end
        local copy = {}
        for groupId, behaviourId in pairs(settings.setups.world) do
            copy[groupId] = behaviourId
        end
        settings.setups[place] = copy
    else
        if not settings.setups[place] then
            return true
        end
        settings.setups[place] = nil
    end
    return save(settings)
end
