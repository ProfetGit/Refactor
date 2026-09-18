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
    questAcceptItemsOnly = true,
}
local ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local OPTION_DEFAULTS = {
    neverSellIDs = {}, repairCapGold = 100, killSwitch = "CTRL",
    nameplateSide = "RIGHT", nameplateShowIcon = true, nameplateShowRing = true,
    nameplateReduceAnimation = false, nameplateDimCompleted = true,
    minimapButton = true,
    tooltipAnchor = "cursor", tooltipPoint = "BOTTOMRIGHT", tooltipX = -80, tooltipY = 120,
    tooltipCursorSide = "RIGHT", tooltipCursorX = 16, tooltipCursorY = 0,
    toastMinQuality = 0, toastShowPrice = true, toastGold = true, toastCurrency = true,
    toastShowSource = true, toastAggregate = true,
    toastOpacity = 0.85, toastLifetime = 5, toastMaxRows = 5, toastScale = 1,
    -- Auction providers are opt-in (PRD 5.5): on launch day no realm has auction data.
    priceTSM = false, priceAuctionator = false, tsmPriceString = "dbMarket",
    questAcceptItemsOnly = false,
}
Settings.optionDefaults = OPTION_DEFAULTS

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
    elseif key == "tsmPriceString" then
        return type(value) == "string" and #value > 0 and #value <= 64 and not value:find("[%c]")
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
    character.minimap = type(character.minimap) == "table" and character.minimap or {}
    character.toast = type(character.toast) == "table" and character.toast or {}
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
    -- Confirmations are account wide: an automation feature is explained once, not once
    -- per character (PRD 6.3).
    account.confirmed = sanitizeValues(account.confirmed)
    account.firstRun = type(account.firstRun) == "string" and account.firstRun or nil
    account.options = type(account.options) == "table" and account.options or {}
    for key, default in pairs(OPTION_DEFAULTS) do
        if not validOption(key, account.options[key]) then
            account.options[key] = default
        end
    end
    for _, module in ipairs(R.modules) do
        self:RegisterDefaults(module.id, module.defaultEnabled)
    end
end

function Settings:RegisterDefaults(id, value)
    assert(R.Codec:ValidID(id) and type(value) == "boolean", "invalid module default")
    self.defaults[id] = value
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

function Settings:IsFirstRun()
    return self.account ~= nil and self.account.firstRun == nil
end

function Settings:MarkFirstRunDone(choice)
    if self.account then
        self.account.firstRun = type(choice) == "string" and choice or "none"
    end
end

function Settings:IsConfirmed(id)
    return self.account ~= nil and self.account.confirmed[id] == true
end

function Settings:Confirm(id, confirmed)
    if not self.account or not R.Codec:ValidID(id) then
        return false
    end
    self.account.confirmed[id] = confirmed == true or nil
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
