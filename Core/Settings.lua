local _, R = ...
local Settings = { defaults = {} }
R.Settings = Settings

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do
        result[key] = value
    end
    return result
end

local function sanitizeValues(values)
    local result, count = {}, 0
    if type(values) == "table" then
        for key, value in pairs(values) do
            if count < 256 and R.Codec:ValidID(key) and type(value) == "boolean" then
                result[key], count = value, count + 1
            end
        end
    end
    return result
end

local BOOLEAN_OPTIONS = {
    nameplateShowIcon = true, nameplateShowRing = true,
    nameplateReduceAnimation = true, nameplateDimCompleted = true,
    minimapButton = true,
    toastShowPrice = true, toastGold = true, toastCurrency = true,
    toastShowSource = true, toastAggregate = true,
    priceTSM = true, priceAuctionator = true,
    farmShowHud = true, farmLocked = true, farmShowMeter = true, farmExpand = true,
    farmShowRates = true,
    questAcceptItemsOnly = true, questAcceptLists = true,
    gossipOpenQuests = true, gossipOpenServices = true, gossipSkipDialogue = true, gossipInInstances = true,
    resurrectPvp = true, resurrectInstance = true, resurrectWorld = true,
    uiVisibilityBlobs = true,
    tooltipClassBorder = true,
}
-- Which layer the window's feature checkboxes write to.
local SCOPES = { account = true, character = true }
local DEFAULT_SCOPE = "account"
local ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local OPTION_DEFAULTS = {
    neverSellIDs = {}, repairCapGold = 100, killSwitch = "CTRL",
    nameplateSide = "RIGHT", nameplateShowIcon = true, nameplateShowRing = true,
    nameplateReduceAnimation = false, nameplateDimCompleted = true,
    minimapButton = true,
    -- On: someone who turned the tooltip border on and hovers a player expects the colour
    -- the rest of the UI uses for that class.
    tooltipClassBorder = true,
    tooltipAnchor = "cursor", tooltipPoint = "BOTTOMRIGHT", tooltipX = -80, tooltipY = 120,
    tooltipCursorSide = "RIGHT", tooltipCursorX = 16, tooltipCursorY = 0,
    toastMinQuality = 0, toastShowPrice = true, toastGold = true, toastCurrency = true,
    toastShowSource = true, toastAggregate = true,
    toastOpacity = 0.85, toastLifetime = 5, toastMaxRows = 5, toastScale = 1,
    -- Auction providers are opt-in (PRD 5.5): on launch day no realm has auction data.
    priceTSM = false, priceAuctionator = false, tsmPriceString = "dbMarket",
    priceSource = "auto",
    -- The farm HUD works with none of these touched: it shows up, starts on the first loot,
    -- and prices with whatever the chain already resolves to.
    farmShowHud = true, farmLocked = false, farmOpacity = 0.9, farmIdleSeconds = 180,
    -- Starts collapsed: the HUD is a glance, and the chevron is one press away when it is not.
    farmGoalGold = 0, farmShowMeter = true, farmExpand = false,
    -- Off by default: items and mobs per hour answer a question nobody asked mid-pull.
    farmShowRates = false,
    questAcceptItemsOnly = false, questAcceptLists = true,
    gossipOpenQuests = true, gossipOpenServices = true, gossipSkipDialogue = false, gossipInInstances = false,
    gossipLearnModifier = "SHIFT", gossipLearned = {},
    -- Alt because Ctrl is the pause modifier's default and Shift is the gossip learn key.
    -- Setting this to the pause modifier leaves the click doing nothing, which is why the
    -- feature's own text says to pick another key.
    inviteModifier = "ALT",
    -- Everywhere by default, which is what the module did before the areas existed. The
    -- three cover every instanceType between them, so turning two off is how a player says
    -- "battlegrounds only".
    resurrectPvp = true, resurrectInstance = true, resurrectWorld = true,
    -- The client's own ceiling for cameraDistanceMaxZoomFactor, which is what the feature
    -- set flat out before the slider existed. Its own default is 1.9.
    cameraMaxZoom = 2.6,
    -- Blizzard's window is two by five. Three by six nearly doubles the page and stays
    -- inside the left panel area at the default UI scale.
    vendorColumns = 3, vendorRows = 6,
    -- The active ActionCam profile: a built-in id or a custom name behind its prefix, and
    -- the custom profiles themselves, name to values. Their shape lives in CameraProfiles.
    cameraProfile = R.CameraProfiles.default, cameraProfiles = {},
    -- UI visibility: the chosen preset and one rule per frame group. Their shape lives in Visibility.
    uiVisibility = { preset = R.Visibility.defaultPreset, groups = {} },
    -- Off: the minimap's quest areas are the client's until the player says otherwise.
    uiVisibilityBlobs = false,
}
Settings.optionDefaults = OPTION_DEFAULTS

local LEARNED_KINDS = { Creature = true, GameObject = true, Vehicle = true }
local function positiveInteger(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

-- Remembered gossip choices: unit kind, then NPC ID to gossip option ID.
local function validLearned(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for kind, entries in pairs(value) do
        if not LEARNED_KINDS[kind] or type(entries) ~= "table" then
            return false
        end
        for id, optionID in pairs(entries) do
            count = count + 1
            if count > 2000 or not positiveInteger(id) or not positiveInteger(optionID) then
                return false
            end
        end
    end
    return true
end

local function validOption(key, value)
    if BOOLEAN_OPTIONS[key] then
        return type(value) == "boolean"
    elseif key == "nameplateSide" then
        return value == "LEFT" or value == "RIGHT"
    elseif key == "repairCapGold" then
        return type(value) == "number" and value >= 0 and value <= 10000000
    elseif key == "killSwitch" then
        return value == "CTRL" or value == "SHIFT" or value == "ALT"
    elseif key == "tooltipAnchor" then
        return value == "default" or value == "cursor" or value == "point"
    elseif key == "tooltipPoint" then
        return ANCHOR_POINTS[value] == true
    elseif key == "tooltipCursorSide" then
        return value == "LEFT" or value == "RIGHT" or value == "CENTER"
    elseif key == "tooltipX" or key == "tooltipY" or key == "tooltipCursorX" or key == "tooltipCursorY" then
        return type(value) == "number" and value >= -4000 and value <= 4000
    elseif key == "toastMinQuality" then
        return type(value) == "number" and value >= 0 and value <= 5 and value % 1 == 0
    elseif key == "toastOpacity" then
        return type(value) == "number" and value >= 0.2 and value <= 1
    elseif key == "toastLifetime" then
        return type(value) == "number" and value >= 1 and value <= 60
    elseif key == "toastMaxRows" then
        return type(value) == "number" and value >= 1 and value <= 10 and value % 1 == 0
    elseif key == "toastScale" then
        return type(value) == "number" and value >= 0.7 and value <= 1.5
    elseif key == "priceSource" then
        return value == "auto" or value == "tsm" or value == "auctionator" or value == "vendor"
    elseif key == "farmOpacity" then
        return type(value) == "number" and value >= 0.2 and value <= 1
    elseif key == "farmIdleSeconds" then
        -- Half a minute is the shortest gap that is not just a slow pull; an hour is the
        -- longest that still means "you stopped farming".
        return type(value) == "number" and value >= 30 and value <= 3600 and value % 1 == 0
    elseif key == "farmGoalGold" then
        -- Whole gold, and zero means no goal, which is what hides the meter.
        return type(value) == "number" and value >= 0 and value <= 10000000 and value % 1 == 0
    elseif key == "tsmPriceString" then
        return type(value) == "string" and #value > 0 and #value <= 64 and not value:find("[%c]")
    elseif key == "cameraMaxZoom" then
        -- Below the client's own 1.9 is a closer camera, which is a choice; above 2.6 the
        -- client clamps it anyway.
        return type(value) == "number" and value >= 1 and value <= 2.6
    elseif key == "vendorColumns" then
        -- One column would leave the page buttons and repair row overlapping.
        return type(value) == "number" and value >= 2 and value <= 5 and value % 1 == 0
    elseif key == "vendorRows" then
        return type(value) == "number" and value >= 2 and value <= 8 and value % 1 == 0
    elseif key == "gossipLearnModifier" or key == "inviteModifier" then
        return value == "CTRL" or value == "SHIFT" or value == "ALT"
    elseif key == "gossipLearned" then
        return validLearned(value)
    elseif key == "cameraProfile" then
        return R.CameraProfiles:ValidReference(value)
    elseif key == "cameraProfiles" then
        return R.CameraProfiles:ValidCustom(value)
    elseif key == "uiVisibility" then
        return R.Visibility:ValidSettings(value)
    elseif key == "neverSellIDs" then
        if type(value) ~= "table" then
            return false
        end
        local count = 0
        for id, enabled in pairs(value) do
            count = count + 1
            if count > 1000 or type(id) ~= "number" or id <= 0 or id % 1 ~= 0 or enabled ~= true then
                return false
            end
        end
        return true
    end
    return false
end

function Settings:Init(account, character, guid)
    assert(type(account) == "table" and type(character) == "table", "settings tables required")
    self.account, self.character, self.char, self.guid = account, character, character, guid
    account.version = 1
    account.modules = sanitizeValues(account.modules)
    character.overrides = sanitizeValues(character.overrides)
    character.window = type(character.window) == "table" and character.window or {}
    -- Account by default: the layer a player edits is a choice that should outlive a logout,
    -- and the account value is the one every character inherits.
    character.scope = SCOPES[character.scope] and character.scope or DEFAULT_SCOPE
    character.minimap = type(character.minimap) == "table" and character.minimap or {}
    character.toast = type(character.toast) == "table" and character.toast or {}
    character.farmHud = type(character.farmHud) == "table" and character.farmHud or {}
    -- Left over from the mail modules, which are gone: drop it so saved variables shrink.
    character.lastMailRecipient = nil
    local profiles = {}
    if type(account.profiles) == "table" then
        local count = 0
        for name, values in pairs(account.profiles) do
            if count < 50 and R.Codec:ValidName(name) and R.Codec:ValidateValues(values) then
                profiles[name], count = copy(values), count + 1
            end
        end
    end
    account.profiles = profiles
    account.assignments = type(account.assignments) == "table" and account.assignments or {}
    for identity, name in pairs(account.assignments) do
        if type(identity) ~= "string" or type(name) ~= "string" or not profiles[name] then
            account.assignments[identity] = nil
        end
    end
    account.confirmed = nil
    account.firstRun = nil
    account.options = type(account.options) == "table" and account.options or {}
    for key, default in pairs(OPTION_DEFAULTS) do
        if not validOption(key, account.options[key]) then
            account.options[key] = default
        end
    end
    -- The selection is only a name, and the custom profile behind it may be gone.
    if not R.CameraProfiles:Exists(account.options.cameraProfile, account.options.cameraProfiles) then
        account.options.cameraProfile = OPTION_DEFAULTS.cameraProfile
    end
    for _, module in ipairs(R.modules) do
        self:RegisterDefaults(module.id, module.defaultEnabled)
    end
end

function Settings:RegisterDefaults(id, value)
    assert(R.Codec:ValidID(id) and type(value) == "boolean", "invalid module default")
    self.defaults[id] = value
end

function Settings:GetScope()
    return self.character and self.character.scope or DEFAULT_SCOPE
end

function Settings:SetScope(scope)
    if not self.character or not SCOPES[scope] then
        return false
    end
    self.character.scope = scope
    return true
end

function Settings:GetOverride(id)
    return self.character and self.character.overrides[id]
end

function Settings:Get(id)
    local value = self:GetOverride(id)
    if value ~= nil then
        return value
    end
    return self:GetInherited(id)
end

-- What this character would use with no override of its own: profile, then account, then default.
function Settings:GetInherited(id)
    local account = self.account
    if account then
        local profileName = self.guid and account.assignments[self.guid]
        local profile = profileName and account.profiles[profileName]
        if profile and profile[id] ~= nil then
            return profile[id]
        end
        if account.modules[id] ~= nil then
            return account.modules[id]
        end
    end
    return self.defaults[id] == true
end

function Settings:Changed(id)
    if self.OnChanged then
        R:SafeCall(self, self.OnChanged, "settings changed", id)
    end
    R.Broker:Emit("REFACTOR_SETTINGS_CHANGED", id)
end

function Settings:SetAccount(id, value)
    if not self.account or not R.Codec:ValidID(id) or value ~= nil and type(value) ~= "boolean" then
        return false
    end
    self.account.modules[id] = value
    self:Changed(id)
    return true
end

function Settings:SetOverride(id, value)
    if not self.character or not R.Codec:ValidID(id) or value ~= nil and type(value) ~= "boolean" then
        return false
    end
    self.character.overrides[id] = value
    self:Changed(id)
    return true
end

function Settings:GetOption(key)
    if self.account then
        return self.account.options[key]
    end
    local default = OPTION_DEFAULTS[key]
    if type(default) == "table" then
        return {}
    end
    return default
end

function Settings:SetOption(key, value)
    if not self.account or not validOption(key, value) then
        return false
    end
    self.account.options[key] = type(value) == "table" and copy(value) or value
    self:Changed(key)
    return true
end

function Settings:CreateProfile(name, values)
    values = values or {}
    if not self.account or not R.Codec:ValidName(name) or not R.Codec:ValidateValues(values) then
        return false, "invalid_profile"
    end
    if self.account.profiles[name] then
        return false, "profile_exists"
    end
    local count = 0
    for _ in pairs(self.account.profiles) do
        count = count + 1
    end
    if count >= 50 then
        return false, "profile_limit"
    end
    self.account.profiles[name] = copy(values)
    self:Changed()
    return true
end

function Settings:UpdateProfile(name, values)
    if not self.account or not self.account.profiles[name] or not R.Codec:ValidateValues(values) then
        return false, "invalid_profile"
    end
    self.account.profiles[name] = copy(values)
    self:Changed()
    return true
end

function Settings:GetProfile(name)
    local profile = self.account and self.account.profiles[name]
    return profile and copy(profile)
end

function Settings:DeleteProfile(name)
    if not self.account or not self.account.profiles[name] then
        return false
    end
    self.account.profiles[name] = nil
    for guid, assigned in pairs(self.account.assignments) do
        if assigned == name then
            self.account.assignments[guid] = nil
        end
    end
    self:Changed()
    return true
end

function Settings:AssignProfile(name, guid)
    guid = guid or self.guid
    if not self.account or type(guid) ~= "string" or #guid == 0 then
        return false, "missing_guid"
    end
    if name ~= nil and not self.account.profiles[name] then
        return false, "missing_profile"
    end
    self.account.assignments[guid] = name
    self:Changed()
    return true
end

function Settings:ExportProfile(name)
    local profile = self.account and self.account.profiles[name]
    if not profile then
        return nil, "missing_profile"
    end
    return R.Codec:EncodeProfile(name, profile)
end

function Settings:ImportProfile(encoded, rename)
    local profile, err = R.Codec:DecodeProfile(encoded)
    if not profile then
        return false, err
    end
    local name = rename or profile.name
    local ok, createError = self:CreateProfile(name, profile.values)
    return ok, ok and name or createError
end
