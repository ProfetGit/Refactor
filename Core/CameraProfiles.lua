--- @core cameraProfiles
--- Purpose: the shape of an ActionCam profile, the built-in profiles, and their share strings.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Profiles = {}
R.CameraProfiles = Profiles

local MAX_CUSTOM, VERSION, CUSTOM_PREFIX = 20, "RC3", "custom:"
Profiles.customPrefix = CUSTOM_PREFIX

-- One flat record per profile. The base fields hold while nothing special is going on;
-- each situation then says where the camera sits, in yards from the character, and where
-- the shoulder offset is while it lasts. Distances are absolute rather than relative so a
-- profile can never put the camera inside the character: the lowest a slider goes still
-- shows the whole model. A distance may also be LEAVE, which moves nothing: the player's
-- own wheel position stands, and only the shoulder changes. Ranges are what the sliders
-- offer and what an imported string is held to.
local DISTANCE_MINIMUM, DISTANCE_MAXIMUM, LEAVE = 4, 30, 0
Profiles.LEAVE = LEAVE
local FIELDS = {
    { key = "distance", kind = "distance", minimum = DISTANCE_MINIMUM, maximum = DISTANCE_MAXIMUM, step = 1 },
    { key = "shoulder", kind = "number", minimum = -2, maximum = 2, step = 0.1 },
    { key = "headBob", kind = "number", minimum = 0, maximum = 1, step = 0.1 },
    { key = "pitch", kind = "boolean" },
    { key = "focusInteract", kind = "boolean" },
    -- How hard the camera turns toward the target in combat; off at zero.
    { key = "targetPull", kind = "number", minimum = 0, maximum = 1, step = 0.1 },
}
-- Listed in the order the dropdown offers them. Which one wins when several apply is the
-- module's call, not the profile's.
local SITUATIONS = { "indoors", "resting", "mounted", "combat", "npc", "dungeon", "raid", "battleground", "arena" }
for _, situation in ipairs(SITUATIONS) do
    FIELDS[#FIELDS + 1] = { key = situation .. "Distance", kind = "distance",
        minimum = DISTANCE_MINIMUM, maximum = DISTANCE_MAXIMUM, step = 1 }
    FIELDS[#FIELDS + 1] = { key = situation .. "Shoulder", kind = "number", minimum = -2, maximum = 2, step = 0.1 }
end
local FIELD_BY_KEY = {}
for _, field in ipairs(FIELDS) do
    FIELD_BY_KEY[field.key] = field
end
Profiles.fields = FIELDS
Profiles.situations = SITUATIONS

-- base is distance, shoulder, head sway, pitch, interact focus, target pull; each situation
-- is distance and shoulder.
local function record(base, situations)
    local values = {
        distance = base[1], shoulder = base[2], headBob = base[3],
        pitch = base[4], focusInteract = base[5], targetPull = base[6],
    }
    for _, situation in ipairs(SITUATIONS) do
        local pair = situations[situation]
        values[situation .. "Distance"], values[situation .. "Shoulder"] = pair[1], pair[2]
    end
    return values
end

-- Immersive: the camera sits close over the right shoulder, tilts as it comes in, follows
-- the head only faintly, and turns to face an NPC you talk to. Indoors it comes in and
-- centres so walls stay out of frame; talking to an NPC it comes in closest; in a city or
-- inn it backs off to show the place; mounted it backs off and centres; in combat the
-- shoulder offset grows so the target sits off centre. Dungeons sit a little further
-- back, raids and battlegrounds much further for awareness, arenas in between. No target
-- pull: with a mouse the player already steers, and the camera pulling toward a target
-- fights them.
--
-- Controller, in two: a stick has no free hand to keep the target in frame, so the camera
-- pulls toward it, and no head movement, which fights a stick-driven camera. Ranged sits
-- wide and pulls gently, because a hard pull toward a mob forty yards out yanks the view
-- on every tab. Melee sits close and hard over the shoulder and pulls hard, so a target
-- being circled stays in frame.
--
-- Cinematic: further back than Immersive, centred, tilting as it comes in, no sway, and
-- closest of all at an NPC. For the story and the screenshots, not the fight.
--
-- Raider: far back everywhere, nothing that moves on its own, ActionCam on for the turn
-- toward an NPC and nothing else. Indoors a little closer so walls stay out of it; an NPC
-- window leaves the camera where it is.
--
-- Melee: hard over the shoulder, a medium target pull, so a target you circle stays in frame,
-- and the wheel is the player's: nothing moves the camera except a mount and a raid,
-- because a melee player sits exactly as close as they want. A ranged player would hate it.
--
-- Comfort: Immersive's distances with everything that moves on its own switched off: no
-- tilt, no sway, no focus, a mild shoulder, and no move for an NPC window. For the player
-- it makes queasy who still wants the situations.
--
-- Blizzard's three are run through the console command that defines them; the numbers
-- here are only what the sliders show for them, taken from the community documentation
-- of those presets, and what a copy of one starts from. A preset never moves the zoom,
-- so its distances are a middling starting point for a copy and nothing more.
local BLIZZARD_DISTANCE = 15
local function blizzard(shoulder)
    local pair = { BLIZZARD_DISTANCE, shoulder }
    return { indoors = pair, resting = pair, mounted = pair, combat = pair, npc = pair,
        dungeon = pair, raid = pair, battleground = pair, arena = pair }
end
Profiles.builtIn = {
    { id = "immersive", nameKey = "CAMERA_PROFILE_IMMERSIVE", detailKey = "CAMERA_PROFILE_IMMERSIVE_DETAIL",
        values = record({ 9, 0.6, 0.3, true, true, 0 }, {
            indoors = { 6, 0 }, resting = { 12, 0.3 }, mounted = { 16, 0 }, combat = { 9, 0.9 },
            npc = { 5, 0.8 }, dungeon = { 14, 0.3 }, raid = { 24, 0 }, battleground = { 16, 0.3 },
            arena = { 12, 0.5 },
        }) },
    { id = "controllerRanged", nameKey = "CAMERA_PROFILE_CONTROLLER_RANGED",
        detailKey = "CAMERA_PROFILE_CONTROLLER_RANGED_DETAIL",
        values = record({ 13, 0.8, 0, true, true, 0.3 }, {
            indoors = { 8, 0.2 }, resting = { 14, 0.4 }, mounted = { 17, 0 }, combat = { 13, 0.9 },
            npc = { 6, 0.8 }, dungeon = { 15, 0.3 }, raid = { 24, 0 }, battleground = { 16, 0.4 },
            arena = { 14, 0.6 },
        }) },
    { id = "controllerMelee", nameKey = "CAMERA_PROFILE_CONTROLLER_MELEE",
        detailKey = "CAMERA_PROFILE_CONTROLLER_MELEE_DETAIL",
        values = record({ 8, 1, 0, true, true, 0.8 }, {
            indoors = { 6, 0.6 }, resting = { 10, 0.5 }, mounted = { 17, 0 }, combat = { 8, 1 },
            npc = { 5, 0.8 }, dungeon = { 9, 0.8 }, raid = { 20, 0.5 }, battleground = { 10, 0.8 },
            arena = { 9, 0.9 },
        }) },
    { id = "cinematic", nameKey = "CAMERA_PROFILE_CINEMATIC", detailKey = "CAMERA_PROFILE_CINEMATIC_DETAIL",
        values = record({ 12, 0, 0, true, true, 0 }, {
            indoors = { 7, 0 }, resting = { 14, 0 }, mounted = { 18, 0 }, combat = { 12, 0.3 },
            npc = { 4, 0.6 }, dungeon = { 15, 0 }, raid = { 24, 0 }, battleground = { 16, 0 },
            arena = { 13, 0 },
        }) },
    { id = "raider", nameKey = "CAMERA_PROFILE_RAIDER", detailKey = "CAMERA_PROFILE_RAIDER_DETAIL",
        values = record({ 24, 0, 0, false, true, 0 }, {
            indoors = { 20, 0 }, resting = { 24, 0 }, mounted = { 24, 0 }, combat = { 24, 0 },
            npc = { LEAVE, 0 }, dungeon = { 24, 0 }, raid = { 24, 0 }, battleground = { 24, 0 },
            arena = { 24, 0 },
        }) },
    { id = "melee", nameKey = "CAMERA_PROFILE_MELEE", detailKey = "CAMERA_PROFILE_MELEE_DETAIL",
        values = record({ LEAVE, 1, 0.2, true, true, 0.5 }, {
            indoors = { LEAVE, 0.6 }, resting = { LEAVE, 0.5 }, mounted = { 16, 0 }, combat = { LEAVE, 1 },
            npc = { LEAVE, 0.8 }, dungeon = { LEAVE, 0.8 }, raid = { 12, 0.6 }, battleground = { LEAVE, 0.8 },
            arena = { LEAVE, 0.9 },
        }) },
    { id = "comfort", nameKey = "CAMERA_PROFILE_COMFORT", detailKey = "CAMERA_PROFILE_COMFORT_DETAIL",
        values = record({ 9, 0.3, 0, false, false, 0 }, {
            indoors = { 6, 0.3 }, resting = { 12, 0.3 }, mounted = { 16, 0.3 }, combat = { 9, 0.3 },
            npc = { LEAVE, 0.3 }, dungeon = { 14, 0.3 }, raid = { 24, 0.3 }, battleground = { 16, 0.3 },
            arena = { 12, 0.3 },
        }) },
    { id = "blizzardBasic", nameKey = "CAMERA_PROFILE_BLIZZARD_BASIC", detailKey = "CAMERA_PROFILE_BLIZZARD_DETAIL",
        console = "actioncam basic",
        values = record({ BLIZZARD_DISTANCE, 0, 0, true, false, 0 }, blizzard(0)) },
    { id = "blizzardOn", nameKey = "CAMERA_PROFILE_BLIZZARD_ON", detailKey = "CAMERA_PROFILE_BLIZZARD_DETAIL",
        console = "actioncam on",
        values = record({ BLIZZARD_DISTANCE, 1, 1, true, true, 0 }, blizzard(1)) },
    { id = "blizzardFull", nameKey = "CAMERA_PROFILE_BLIZZARD_FULL", detailKey = "CAMERA_PROFILE_BLIZZARD_DETAIL",
        console = "actioncam full",
        values = record({ BLIZZARD_DISTANCE, 1, 1, true, true, 0.5 }, blizzard(1)) },
}
Profiles.default = "immersive"
local BUILT_IN_BY_ID = {}
for _, profile in ipairs(Profiles.builtIn) do
    BUILT_IN_BY_ID[profile.id] = profile
end

local function copy(values)
    local result = {}
    for key, value in pairs(values) do
        result[key] = value
    end
    return result
end

function Profiles:Valid(values)
    if type(values) ~= "table" then
        return false
    end
    local count = 0
    for key, value in pairs(values) do
        count = count + 1
        local field = FIELD_BY_KEY[key]
        if not field then
            return false
        end
        if field.kind == "boolean" then
            if type(value) ~= "boolean" then
                return false
            end
        elseif type(value) ~= "number" or value ~= value then
            return false
        elseif (value < field.minimum or value > field.maximum)
            and not (field.kind == "distance" and value == LEAVE) then
            return false
        end
    end
    return count == #FIELDS
end

-- The saved table of custom profiles: name to values.
function Profiles:ValidCustom(custom)
    if type(custom) ~= "table" then
        return false
    end
    local count = 0
    for name, values in pairs(custom) do
        count = count + 1
        if count > MAX_CUSTOM or not R.Codec:ValidName(name) or not self:Valid(values) then
            return false
        end
    end
    return true
end

-- What the active profile setting may say: a built-in id, or a custom name behind the prefix.
function Profiles:ValidReference(reference)
    if type(reference) ~= "string" then
        return false
    end
    if BUILT_IN_BY_ID[reference] then
        return true
    end
    return reference:sub(1, #CUSTOM_PREFIX) == CUSTOM_PREFIX and R.Codec:ValidName(reference:sub(#CUSTOM_PREFIX + 1))
end

function Profiles:CustomName(reference)
    if type(reference) == "string" and reference:sub(1, #CUSTOM_PREFIX) == CUSTOM_PREFIX then
        return reference:sub(#CUSTOM_PREFIX + 1)
    end
    return nil
end

-- Resolves a reference against a custom table: a fresh record with the values copied, so
-- nothing downstream can edit a built-in or a saved profile by accident.
function Profiles:Resolve(reference, custom)
    local builtIn = BUILT_IN_BY_ID[reference]
    if builtIn then
        return { id = builtIn.id, nameKey = builtIn.nameKey, detailKey = builtIn.detailKey,
            console = builtIn.console, builtIn = true, values = copy(builtIn.values) }
    end
    local name = self:CustomName(reference)
    local values = name and type(custom) == "table" and custom[name]
    if values then
        return { id = reference, name = name, builtIn = false, values = copy(values) }
    end
    return nil
end

function Profiles:Exists(reference, custom)
    return self:Resolve(reference, custom) ~= nil
end

-- Numbers are written with %g so 0.6 stays "0.6" rather than a float's tail, and a whole
-- number carries no decimals. Booleans are 1 and 0.
local function formatValue(field, value)
    if field.kind == "boolean" then
        return value and "1" or "0"
    end
    return string.format("%g", value)
end

function Profiles:Encode(name, values)
    if not R.Codec:ValidName(name) or not self:Valid(values) then
        return nil, "invalid_profile"
    end
    local lines = { VERSION, name }
    for _, field in ipairs(FIELDS) do
        lines[#lines + 1] = field.key .. "=" .. formatValue(field, values[field.key])
    end
    return R.Codec:EncodeText(table.concat(lines, "\n") .. "\n")
end

function Profiles:Decode(data)
    local payload = R.Codec:DecodeText(data)
    if not payload or payload:sub(-1) ~= "\n" then
        return nil, "invalid_encoding"
    end
    local version, name, body = payload:match("^([^\n]*)\n([^\n]*)\n(.*)$")
    if version ~= VERSION or not R.Codec:ValidName(name) then
        return nil, "invalid_profile"
    end
    local values = {}
    for line in body:gmatch("([^\n]*)\n") do
        local key, text = line:match("^([%w_]+)=(.+)$")
        local field = key and FIELD_BY_KEY[key]
        if not field or values[key] ~= nil then
            return nil, "invalid_profile"
        end
        if field.kind == "boolean" then
            if text ~= "1" and text ~= "0" then
                return nil, "invalid_profile"
            end
            values[key] = text == "1"
        else
            values[key] = tonumber(text)
        end
    end
    if not self:Valid(values) then
        return nil, "invalid_profile"
    end
    return { name = name, values = values }
end

-- Everything below goes through Settings, so the account table is the only copy and every
-- write is validated and announced the same way a slider's is.
function Profiles:Active()
    local Settings = R.Settings
    return self:Resolve(Settings:GetOption("cameraProfile"), Settings:GetOption("cameraProfiles"))
end

function Profiles:Select(reference)
    if not self:Exists(reference, R.Settings:GetOption("cameraProfiles")) then
        return false, "missing_profile"
    end
    return R.Settings:SetOption("cameraProfile", reference)
end

-- A new custom profile from a set of values, selected as soon as it exists.
function Profiles:SaveCopy(name, values)
    local Settings = R.Settings
    if not R.Codec:ValidName(name) or not self:Valid(values) then
        return false, "invalid_profile"
    end
    local custom = copy(Settings:GetOption("cameraProfiles") or {})
    if custom[name] then
        return false, "profile_exists"
    end
    local count = 0
    for _ in pairs(custom) do
        count = count + 1
    end
    if count >= MAX_CUSTOM then
        return false, "profile_limit"
    end
    custom[name] = copy(values)
    if not Settings:SetOption("cameraProfiles", custom) then
        return false, "invalid_profile"
    end
    Settings:SetOption("cameraProfile", CUSTOM_PREFIX .. name)
    return true, name
end

-- One field of the active custom profile. A built-in refuses: it is copied first.
function Profiles:SetField(key, value)
    local Settings = R.Settings
    local active = self:Active()
    if not active or active.builtIn or not FIELD_BY_KEY[key] then
        return false
    end
    local custom = copy(Settings:GetOption("cameraProfiles") or {})
    local values = copy(custom[active.name])
    values[key] = value
    if not self:Valid(values) then
        return false
    end
    custom[active.name] = values
    return Settings:SetOption("cameraProfiles", custom)
end

function Profiles:Delete(name)
    local Settings = R.Settings
    local custom = copy(Settings:GetOption("cameraProfiles") or {})
    if not custom[name] then
        return false
    end
    custom[name] = nil
    -- The selection moves first, so no listener ever sees a profile that is not there.
    if Settings:GetOption("cameraProfile") == CUSTOM_PREFIX .. name then
        Settings:SetOption("cameraProfile", self.default)
    end
    return Settings:SetOption("cameraProfiles", custom)
end

function Profiles:Export(reference)
    local profile = self:Resolve(reference, R.Settings:GetOption("cameraProfiles"))
    if not profile then
        return nil, "missing_profile"
    end
    local name = profile.name or (R.L and R.L[profile.nameKey]) or profile.id
    return self:Encode(name, profile.values)
end

function Profiles:Import(encoded)
    local profile, err = self:Decode(encoded)
    if not profile then
        return false, err
    end
    return self:SaveCopy(profile.name, profile.values)
end
