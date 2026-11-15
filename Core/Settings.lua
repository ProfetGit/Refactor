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

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, inner in pairs(value) do
        result[key] = deepCopy(inner)
    end
    return result
end

local function same(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
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
    nameplateShowIcon = true,
    nameplateReduceAnimation = true, nameplateDimCompleted = true, nameplateShowMore = true,
    nameplateShowGroup = true,
    minimapButton = true,
    minimapButtonsAttach = true, minimapButtonsCloseOnClick = true,
    toastShowPrice = true, toastGold = true, toastCurrency = true,
    toastShowSource = true, toastAggregate = true,
    priceTSM = true, priceAuctionator = true,
    farmShowHud = true, farmLocked = true, farmShowMeter = true, farmExpand = true,
    farmShowRates = true,
    questAcceptItemsOnly = true, questAcceptLists = true,
    gossipOpenQuests = true, gossipOpenServices = true, gossipSkipDialogue = true, gossipInInstances = true,
    resurrectPvp = true, resurrectInstance = true, resurrectWorld = true,
    placeSpellsRanks = true,
    uiVisibilityBlobs = true,
    tooltipClassBorder = true,
    cameraLearnZoom = true,
    bagUpgradeRightClick = true, bagUpgradePrompt = true, bagUpgradeCarry = true,
    mailKeepCrafts = true, mailFillRecipient = true,
}
-- Every character uses exactly one profile, and a character with none uses this one. It is a
-- storage key, never shown as typed: the window names it through the locale.
local DEFAULT_PROFILE = "Default"
Settings.DEFAULT_PROFILE = DEFAULT_PROFILE
-- 1 stacked a character override, an assigned profile and an account value over each module
-- default. 2 is one whole profile per character.
local VERSION = 2
local MAX_PROFILES = 50
-- Data about the world and the player's own characters rather than a taste, so it stays one
-- per account whichever profile a character uses: switching profile never loses a list. The
-- pause key is one account setting by PRD 5.6, shared with Gear Refactor.
local ACCOUNT_OPTIONS = {
    neverSellIDs = true, killSwitch = true, gossipLearned = true, cameraProfiles = true,
    mapExitOverrides = true, mailBankAlt = true, mailRoutes = true, mailItemRoutes = true,
    mailLearning = true, mailNeverIDs = true, mailRoster = true,
}
local ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local OPTION_DEFAULTS = {
    neverSellIDs = {}, repairCapGold = 100, killSwitch = "CTRL",
    nameplateSide = "RIGHT", nameplateShowIcon = true,
    nameplateReduceAnimation = false, nameplateDimCompleted = true,
    -- Off: a second number beside the count reads as a party member's progress, not as
    -- more of the player's own objectives on the same mob.
    nameplateShowMore = false,
    -- Off: party members' marks on every quest mob are noise to someone questing alone in a
    -- dungeon group, and the plate reads the player's own progress first.
    nameplateShowGroup = false,
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
    -- Each one starts at the engine's ceiling for its CVar, the way cameraMaxZoom does.
    -- The game's own defaults are 16, 70 and 70.
    groundEffectDensity = 256, groundEffectDist = 500, groundEffectFade = 370,
    -- The collector rides the minimap's rim like the buttons it gathers, and closes the way a
    -- Blizzard menu does. Five across is MinimapButtonButton's default.
    minimapButtonsAttach = true, minimapButtonsCloseOnClick = true, minimapButtonsColumns = 5,
    -- Blizzard's window is two by five. Three by six nearly doubles the page and stays
    -- inside the left panel area at the default UI scale.
    vendorColumns = 3, vendorRows = 6,
    -- The active ActionCam profile: a built-in id or a custom name behind its prefix, and
    -- the custom profiles themselves, name to values. Their shape lives in CameraProfiles.
    cameraProfile = R.CameraProfiles.default, cameraProfiles = {},
    -- On: a wheel turn inside a situation says where the player wants the camera there, and
    -- having to repeat it on every mount is the camera ignoring them. Kept for the session.
    cameraLearnZoom = true,
    -- UI visibility: the behaviours and the setups that hand them to frame groups. Their shape
    -- lives in Visibility.
    uiVisibility = R.Visibility:Default(),
    -- Off: the minimap's quest areas are the client's until the player says otherwise.
    uiVisibilityBlobs = false,
    -- All on: the bag upgrade does nothing until the player right-clicks a bag or presses Equip.
    bagUpgradeRightClick = true, bagUpgradePrompt = true, bagUpgradeCarry = true,
    -- Send to alts: no bank alt until the player picks one, and no gold row until a keep
    -- amount is set. The roster fills itself as each character logs in.
    mapExitOverrides = {},
    mailBankAlt = "", mailRoutes = {}, mailItemRoutes = {}, mailLearning = {}, mailNeverIDs = {},
    mailRoster = {}, mailKeepCrafts = true, mailFillRecipient = true, mailKeepGold = 0,
    -- Crafts: on 4 November there is no auction data anywhere, and gold falls back to crafts without it.
    plannerGoal = "crafts",
    -- On: a rank left on the bar after the trainer taught the next one is the old spell cast by
    -- mistake. A rank kept below it on purpose is never touched either way.
    placeSpellsRanks = true,
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

-- A name as typed in the To field: no control characters and no escape sequences.
local function validRecipient(value)
    return type(value) == "string" and #value > 0 and #value <= 64 and not value:find("[%c|]")
end

-- Item ID to recipient, for the learned and the confirmed item routes.
local function validItemRoutes(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for id, recipient in pairs(value) do
        count = count + 1
        if count > 1000 or not positiveInteger(id) or not validRecipient(recipient) then
            return false
        end
    end
    return true
end

-- Category key to a recipient, or false for a category the player keeps.
-- Where the player dragged a zone exit arrow: map the arrow is on, then the map it leads to,
-- then the spot as a share of the map.
local function validMapExits(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for from, targets in pairs(value) do
        if type(from) ~= "number" or type(targets) ~= "table" then
            return false
        end
        for to, point in pairs(targets) do
            count = count + 1
            if count > 600 or type(to) ~= "number" or type(point) ~= "table" or type(point.x) ~= "number"
                or type(point.y) ~= "number" or point.x < 0 or point.x > 1 or point.y < 0 or point.y > 1 then
                return false
            end
        end
    end
    return true
end

local function validMailRoutes(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for category, recipient in pairs(value) do
        count = count + 1
        if count > 32 or type(category) ~= "string" or not category:match("^%l%a*$") or #category > 24
            or recipient ~= false and not validRecipient(recipient) then
            return false
        end
    end
    return true
end

-- Character GUID to the name the client gave that character, and its realm.
local function validRoster(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for guid, entry in pairs(value) do
        count = count + 1
        if count > 200 or type(guid) ~= "string" or #guid == 0 or #guid > 64 or guid:find("%c")
            or type(entry) ~= "table" or not validRecipient(entry.name)
            or entry.surname ~= nil and not validRecipient(entry.surname)
            or type(entry.realm) ~= "string" or #entry.realm > 64 or entry.realm:find("%c") then
            return false
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
    elseif key == "groundEffectDensity" then
        return type(value) == "number" and value >= 0 and value <= 256 and value % 1 == 0
    elseif key == "groundEffectDist" then
        return type(value) == "number" and value >= 10 and value <= 500 and value % 1 == 0
    elseif key == "groundEffectFade" then
        return type(value) == "number" and value >= 10 and value <= 370 and value % 1 == 0
    elseif key == "minimapButtonsColumns" then
        return type(value) == "number" and value >= 1 and value <= 10 and value % 1 == 0
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
    elseif key == "mailBankAlt" then
        return value == "" or validRecipient(value)
    elseif key == "mapExitOverrides" then
        return validMapExits(value)
    elseif key == "mailRoutes" then
        return validMailRoutes(value)
    elseif key == "mailItemRoutes" or key == "mailLearning" then
        return validItemRoutes(value)
    elseif key == "mailRoster" then
        return validRoster(value)
    elseif key == "plannerGoal" then
        return value == "crafts" or value == "gold"
    elseif key == "mailKeepGold" then
        -- Whole gold, and zero means the gold button is off.
        return type(value) == "number" and value >= 0 and value <= 1000000 and value % 1 == 0
    elseif key == "neverSellIDs" or key == "mailNeverIDs" then
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

local PROFILE_KEYS = {}
for key in pairs(OPTION_DEFAULTS) do
    if not ACCOUNT_OPTIONS[key] then
        PROFILE_KEYS[#PROFILE_KEYS + 1] = key
    end
end
table.sort(PROFILE_KEYS)

local function freeName(profiles, wanted)
    if not profiles[wanted] then
        return wanted
    end
    local index = 2
    while profiles[wanted .. " " .. index] do
        index = index + 1
    end
    return wanted .. " " .. index
end

-- A profile's options are filled from the defaults and stripped of anything that fails
-- validation, so every reader finds a valid value. Account data never lives in a profile.
local function cleanOptions(options, library)
    options = type(options) == "table" and options or {}
    for key in pairs(ACCOUNT_OPTIONS) do
        options[key] = nil
    end
    -- Converted one by one first: the all-or-nothing check below would otherwise reset every
    -- behaviour over a single old or bad record.
    if options.uiVisibility ~= nil then
        options.uiVisibility = R.Visibility:Clean(options.uiVisibility)
    end
    for _, key in ipairs(PROFILE_KEYS) do
        if not validOption(key, options[key]) then
            options[key] = deepCopy(OPTION_DEFAULTS[key])
        end
    end
    -- The selection is only a name, and the custom camera profile behind it may be gone.
    if not R.CameraProfiles:Exists(options.cameraProfile, library) then
        options.cameraProfile = OPTION_DEFAULTS.cameraProfile
    end
    return options
end

local function cleanAccountData(options)
    -- Upgraded and filtered one by one, for the same reason as the behaviours above.
    if options.cameraProfiles ~= nil then
        options.cameraProfiles = R.CameraProfiles:CleanCustom(options.cameraProfiles)
    end
    for key in pairs(ACCOUNT_OPTIONS) do
        if not validOption(key, options[key]) then
            options[key] = deepCopy(OPTION_DEFAULTS[key])
        end
    end
end

-- Version 1 resolved a switch through the character's override, its assigned profile, the
-- account value and the module default. Each named profile becomes a whole one here, its
-- switches over the account's, so every character resolves exactly what it did before.
local function migrateAccount(account)
    local modules = sanitizeValues(account.modules)
    local options, data = {}, {}
    for key, value in pairs(type(account.options) == "table" and account.options or {}) do
        if ACCOUNT_OPTIONS[key] then
            data[key] = value
        else
            options[key] = value
        end
    end
    local profiles = { [DEFAULT_PROFILE] = { modules = modules, options = options } }
    local names, renamed = {}, {}
    for name, values in pairs(type(account.profiles) == "table" and account.profiles or {}) do
        if R.Codec:ValidName(name) and R.Codec:ValidateValues(values) then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local merged = copy(modules)
        for id, value in pairs(account.profiles[name]) do
            merged[id] = value
        end
        local target = freeName(profiles, name)
        renamed[name] = target
        profiles[target] = { modules = merged, options = deepCopy(options) }
    end
    local assignments = {}
    for guid, name in pairs(type(account.assignments) == "table" and account.assignments or {}) do
        if type(guid) == "string" and renamed[name] then
            assignments[guid] = renamed[name]
        end
    end
    account.modules = nil
    account.profiles, account.assignments, account.options = profiles, assignments, data
end

local function cleanProfiles(account)
    local library = account.options.cameraProfiles
    local profiles = {}
    for name, profile in pairs(type(account.profiles) == "table" and account.profiles or {}) do
        if R.Codec:ValidName(name) and type(profile) == "table" then
            profiles[name] = {
                modules = sanitizeValues(profile.modules),
                options = cleanOptions(profile.options, library),
            }
        end
    end
    profiles[DEFAULT_PROFILE] = profiles[DEFAULT_PROFILE] or { modules = {}, options = cleanOptions(nil, library) }
    account.profiles = profiles
    local assignments = type(account.assignments) == "table" and account.assignments or {}
    for guid, name in pairs(assignments) do
        if type(guid) ~= "string" or name == DEFAULT_PROFILE or not profiles[name] then
            assignments[guid] = nil
        end
    end
    account.assignments = assignments
end

-- A character that pinned switches of its own keeps them as a profile named after it. Pins
-- that only repeat what the character already resolved are dropped with nothing created.
function Settings:MigrateCharacter(character, name)
    local overrides = sanitizeValues(character.overrides)
    character.overrides, character.scope = nil, nil
    if not self.guid then
        return
    end
    local base = self:Profile()
    local own, differs = copy(base.modules), false
    for id, value in pairs(overrides) do
        local current = base.modules[id]
        if current == nil then
            current = self.defaults[id] == true
        end
        if value ~= current then
            own[id], differs = value, true
        end
    end
    if not differs then
        return
    end
    local wanted = R.Codec:ValidName(name) and name or R.L and R.L.UI_PROFILE_CHARACTER or self.guid
    local target = freeName(self.account.profiles, wanted)
    self.account.profiles[target] = { modules = own, options = deepCopy(base.options) }
    self.account.assignments[self.guid] = target
end

function Settings:Init(account, character, guid, name)
    assert(type(account) == "table" and type(character) == "table", "settings tables required")
    self.account, self.character, self.char, self.guid = account, character, character, guid
    -- An account table the client handed back empty is a first install on this account.
    self.fresh = account.version == nil
    for _, module in ipairs(R.modules) do
        self:RegisterDefaults(module.id, module.defaultEnabled)
    end
    if (account.version or 1) < VERSION then
        migrateAccount(account)
    end
    account.version = math.max(account.version or VERSION, VERSION)
    account.confirmed = nil
    account.firstRun = nil
    account.options = type(account.options) == "table" and account.options or {}
    cleanAccountData(account.options)
    cleanProfiles(account)
    character.window = type(character.window) == "table" and character.window or {}
    character.minimap = type(character.minimap) == "table" and character.minimap or {}
    character.minimapButtons = type(character.minimapButtons) == "table" and character.minimapButtons or {}
    character.toast = type(character.toast) == "table" and character.toast or {}
    character.farmHud = type(character.farmHud) == "table" and character.farmHud or {}
    -- Left over from the mail modules, which are gone: drop it so saved variables shrink.
    character.lastMailRecipient = nil
    if (character.version or 1) < VERSION then
        self:MigrateCharacter(character, name)
        character.version = VERSION
    end
end

function Settings:RegisterDefaults(id, value)
    assert(R.Codec:ValidID(id) and type(value) == "boolean", "invalid module default")
    self.defaults[id] = value
end

-- The name of the profile this character uses. A character with no assignment uses Default.
function Settings:ActiveProfile()
    local account = self.account
    local name = account and self.guid and account.assignments[self.guid]
    return name and account.profiles[name] and name or DEFAULT_PROFILE
end

function Settings:Profile()
    return self.account and self.account.profiles[self:ActiveProfile()]
end

-- Default first, then the rest by name, the order every list of profiles shows.
function Settings:ProfileNames()
    local names = {}
    for name in pairs(self.account and self.account.profiles or {}) do
        if name ~= DEFAULT_PROFILE then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    table.insert(names, 1, DEFAULT_PROFILE)
    return names
end

function Settings:IsAccountOption(key)
    return ACCOUNT_OPTIONS[key] == true
end

-- What the profile itself stores for a switch, nil where it follows the module default.
function Settings:Stored(id)
    local profile = self:Profile()
    return profile and profile.modules[id]
end

function Settings:Get(id)
    local value = self:Stored(id)
    if value ~= nil then
        return value
    end
    return self.defaults[id] == true
end

function Settings:Changed(id)
    if self.OnChanged then
        R:SafeCall(self, self.OnChanged, "settings changed", id)
    end
    R.Broker:Emit("REFACTOR_SETTINGS_CHANGED", id)
end

-- nil takes the switch out of the profile, so it follows the module default again.
function Settings:Set(id, value)
    local profile = self:Profile()
    if not profile or not R.Codec:ValidID(id) or value ~= nil and type(value) ~= "boolean" then
        return false
    end
    profile.modules[id] = value
    self:Changed(id)
    return true
end

function Settings:GetOption(key)
    if self.account then
        if ACCOUNT_OPTIONS[key] then
            return self.account.options[key]
        end
        return self:Profile().options[key]
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
    local target = ACCOUNT_OPTIONS[key] and self.account.options or self:Profile().options
    target[key] = deepCopy(value)
    self:Changed(key)
    return true
end

-- Every option the two profiles disagree on is announced by its own key, the way a slider
-- announces it, so each feature re-applies what it reads without knowing profiles exist.
-- The nil after them re-reconciles every switch.
function Settings:AnnounceSwitch(before, after)
    for _, key in ipairs(PROFILE_KEYS) do
        if not same(before[key], after[key]) then
            self:Changed(key)
        end
    end
end

-- source is a profile name to copy, a { modules, options } table, or nil for Refactor's own
-- defaults throughout.
function Settings:CreateProfile(name, source)
    local account = self.account
    if not account or not R.Codec:ValidName(name) then
        return false, "invalid_profile"
    end
    if account.profiles[name] then
        return false, "profile_exists"
    end
    if #self:ProfileNames() >= MAX_PROFILES then
        return false, "profile_limit"
    end
    if type(source) == "string" then
        source = account.profiles[source]
        if not source then
            return false, "missing_profile"
        end
    end
    source = source or {}
    local modules = source.modules or {}
    if not R.Codec:ValidateValues(modules) then
        return false, "invalid_profile"
    end
    account.profiles[name] = {
        modules = copy(modules),
        options = cleanOptions(deepCopy(source.options), account.options.cameraProfiles),
    }
    self:Changed()
    return true
end

function Settings:GetProfile(name)
    local profile = self.account and self.account.profiles[name]
    return profile and deepCopy(profile)
end

-- Its characters move to Default, which is never deleted, so nobody is left without one.
function Settings:DeleteProfile(name)
    local account = self.account
    if not account or name == DEFAULT_PROFILE or not account.profiles[name] then
        return false
    end
    local before = self:Profile()
    account.profiles[name] = nil
    for guid, assigned in pairs(account.assignments) do
        if assigned == name then
            account.assignments[guid] = nil
        end
    end
    self:AnnounceSwitch(before.options, self:Profile().options)
    self:Changed()
    return true
end

function Settings:AssignProfile(name, guid)
    guid = guid or self.guid
    local account = self.account
    if not account or type(guid) ~= "string" or #guid == 0 then
        return false, "missing_guid"
    end
    name = name or DEFAULT_PROFILE
    if not account.profiles[name] then
        return false, "missing_profile"
    end
    local mine = guid == self.guid
    local before = self:Profile()
    account.assignments[guid] = name ~= DEFAULT_PROFILE and name or nil
    if mine then
        self:AnnounceSwitch(before.options, self:Profile().options)
    end
    self:Changed()
    return true
end

function Settings:ExportProfile(name)
    local profile = self.account and self.account.profiles[name]
    if not profile then
        return nil, "missing_profile"
    end
    return R.Codec:EncodeProfileData(name, profile)
end

-- A name already taken gets a number, so an import never fails over a name nobody chose
-- on purpose. Settings the importing client does not know, and account data, are dropped.
function Settings:ImportProfile(encoded, rename)
    local decoded, err = R.Codec:DecodeProfile(encoded)
    if not decoded then
        return false, err
    end
    if not self.account then
        return false, "invalid_profile"
    end
    local options = {}
    for key, value in pairs(decoded.options) do
        if OPTION_DEFAULTS[key] ~= nil and not ACCOUNT_OPTIONS[key] then
            options[key] = value
        end
    end
    local name = freeName(self.account.profiles, rename or decoded.name)
    local ok, createError = self:CreateProfile(name, { modules = decoded.modules, options = options })
    return ok, ok and name or createError
end
