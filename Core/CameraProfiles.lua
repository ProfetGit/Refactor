--- @core cameraProfiles
--- Purpose: the shape of an ActionCam profile, the built-in profiles, and their share strings.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Profiles = {}
R.CameraProfiles = Profiles

local MAX_CUSTOM, VERSION, CUSTOM_PREFIX = 20, "RC1", "custom:"
Profiles.customPrefix = CUSTOM_PREFIX

-- One flat record per profile. The base fields hold while nothing special is going on;
-- each situation then says how far the camera moves (positive is closer) and where the
-- shoulder offset sits while it lasts. Ranges are what the sliders offer and what an
-- imported string is held to.
local FIELDS = {
    { key = "zoom", kind = "number", minimum = 0, maximum = 10, step = 1 },
    { key = "shoulder", kind = "number", minimum = -2, maximum = 2, step = 0.1 },
    { key = "headBob", kind = "number", minimum = 0, maximum = 1, step = 0.1 },
    { key = "pitch", kind = "boolean" },
    { key = "focusInteract", kind = "boolean" },
    { key = "focusEnemy", kind = "boolean" },
}
local SITUATIONS = { "indoors", "resting", "mounted", "combat" }
for _, situation in ipairs(SITUATIONS) do
    FIELDS[#FIELDS + 1] = { key = situation .. "Zoom", kind = "number", minimum = -10, maximum = 10, step = 1 }
    FIELDS[#FIELDS + 1] = { key = situation .. "Shoulder", kind = "number", minimum = -2, maximum = 2, step = 0.1 }
end
local FIELD_BY_KEY = {}
for _, field in ipairs(FIELDS) do
    FIELD_BY_KEY[field.key] = field
end
Profiles.fields = FIELDS
Profiles.situations = SITUATIONS

local function record(values)
    return {
        zoom = values[1], shoulder = values[2], headBob = values[3],
        pitch = values[4], focusInteract = values[5], focusEnemy = values[6],
        indoorsZoom = values[7], indoorsShoulder = values[8],
        restingZoom = values[9], restingShoulder = values[10],
        mountedZoom = values[11], mountedShoulder = values[12],
        combatZoom = values[13], combatShoulder = values[14],
    }
end

-- Immersive: the camera comes in and sits a little over the right shoulder, tilts as it
-- zooms, follows the head only faintly, and turns to face an NPC you talk to. Indoors
-- it comes in further and centres so walls stay out of frame; in a city or inn it backs
-- off to show the place; mounted it backs off and centres; in combat the shoulder
-- offset grows so the target sits off centre. Enemy focus stays off: with a mouse the
-- player already steers, and the camera pulling toward a target fights them.
--
-- Controller: enemy and interact focus both on, because a stick has no free hand to keep
-- the target in frame, and no head movement, which fights a stick-driven camera. Closer
-- than Blizzard's presets but not as close as Immersive, so the wider swings a stick
-- makes still leave room to see.
--
-- Blizzard's three are run through the console command that defines them; the numbers
-- here are only what the sliders show for them, taken from the community documentation
-- of those presets, and what a copy of one starts from.
Profiles.builtIn = {
    { id = "immersive", nameKey = "CAMERA_PROFILE_IMMERSIVE", detailKey = "CAMERA_PROFILE_IMMERSIVE_DETAIL",
        values = record({ 4, 0.6, 0.3, true, true, false, 3, 0, -4, 0.3, -6, 0, 0, 0.9 }) },
    { id = "controller", nameKey = "CAMERA_PROFILE_CONTROLLER", detailKey = "CAMERA_PROFILE_CONTROLLER_DETAIL",
        values = record({ 2, 0.8, 0, true, true, true, 2, 0.2, -3, 0.4, -6, 0, 0, 1 }) },
    { id = "blizzardBasic", nameKey = "CAMERA_PROFILE_BLIZZARD_BASIC", detailKey = "CAMERA_PROFILE_BLIZZARD_DETAIL",
        console = "actioncam basic",
        values = record({ 0, 0, 0, true, false, false, 0, 0, 0, 0, 0, 0, 0, 0 }) },
    { id = "blizzardOn", nameKey = "CAMERA_PROFILE_BLIZZARD_ON", detailKey = "CAMERA_PROFILE_BLIZZARD_DETAIL",
        console = "actioncam on",
        values = record({ 0, 1, 1, true, true, false, 0, 1, 0, 1, 0, 1, 0, 1 }) },
    { id = "blizzardFull", nameKey = "CAMERA_PROFILE_BLIZZARD_FULL", detailKey = "CAMERA_PROFILE_BLIZZARD_DETAIL",
        console = "actioncam full",
        values = record({ 0, 1, 1, true, true, true, 0, 1, 0, 1, 0, 1, 0, 1 }) },
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
        elseif type(value) ~= "number" or value ~= value or value < field.minimum or value > field.maximum then
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
