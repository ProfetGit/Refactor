-- Refactor Addon - Core Initialization
-- Inspired by Plumber's initialization pattern

local addonName, addon = ...

-- Version info
addon.VERSION = "1.0.0"
addon.ADDON_NAME = addonName

-- Database references (set after ADDON_LOADED)
local DB
local DB_PC

----------------------------------------------
-- Callback Registry (Plumber-style)
----------------------------------------------
local CallbackRegistry = {}
CallbackRegistry.events = {}
addon.CallbackRegistry = CallbackRegistry

function CallbackRegistry:Register(event, func, owner)
    if not self.events[event] then
        self.events[event] = {}
    end
    
    local callbackType = type(func) == "string" and 2 or 1
    table.insert(self.events[event], {callbackType, func, owner})
end

function CallbackRegistry:Trigger(event, ...)
    if self.events[event] then
        for _, cb in ipairs(self.events[event]) do
            if cb[1] == 1 then
                if cb[3] then
                    cb[2](cb[3], ...)
                else
                    cb[2](...)
                end
            else
                cb[3][cb[2]](cb[3], ...)
            end
        end
    end
end

function CallbackRegistry:Unregister(event, func, owner)
    if not self.events[event] then return end
    
    local callbacks = self.events[event]
    for i = #callbacks, 1, -1 do
        local cb = callbacks[i]
        if cb[2] == func and cb[3] == owner then
            table.remove(callbacks, i)
        end
    end
end

----------------------------------------------
-- Database Access Functions
----------------------------------------------
function addon.GetDBValue(key)
    return DB and DB[key]
end

function addon.SetDBValue(key, value, userInput)
    if DB then
        DB[key] = value
        CallbackRegistry:Trigger("SettingChanged." .. key, value, userInput)
        CallbackRegistry:Trigger("SettingChanged", key, value, userInput)
    end
end

function addon.GetDBBool(key)
    return DB and DB[key] == true
end

function addon.FlipDBBool(key)
    addon.SetDBValue(key, not addon.GetDBBool(key), true)
end

function addon.GetCharDBValue(key)
    return DB_PC and DB_PC[key]
end

function addon.SetCharDBValue(key, value)
    if DB_PC then
        DB_PC[key] = value
    end
end

----------------------------------------------
-- Default Settings
----------------------------------------------
local DefaultValues = {
    -- Auto-Sell Junk (Smart Vendor)
    AutoSellJunk = true,
    AutoSellJunk_ShowNotify = true,
    AutoSellJunk_SellLowILvl = false, -- OFF by default - risky feature
    AutoSellJunk_MaxILvl = 400, -- Only sell items BELOW this iLvl (safe default: old expansion gear)
    AutoSellJunk_SellKnownTransmog = false,
    AutoSellJunk_KeepTransmog = true,
    
    -- Auto-Repair
    AutoRepair = true,
    AutoRepair_UseGuild = true,
    AutoRepair_ShowNotify = true,
    
    -- Auto-Quest
    AutoQuest = false, -- Disabled by default - affects gameplay
    AutoQuest_Accept = true,
    AutoQuest_TurnIn = true,
    AutoQuest_SkipGossip = true,
    AutoQuest_DailyOnly = false,
    AutoQuest_ModifierKey = "SHIFT", -- SHIFT, CTRL, ALT, NONE
    
    -- Fast Loot
    FastLoot = true, -- Enabled by default - pure QoL
    
    -- Skip Cinematics
    SkipCinematics = false, -- Disabled by default - first-time experience
    SkipCinematics_AlwaysSkip = false,
    SkipCinematics_ModifierKey = "SHIFT",
    
    -- Auto-Confirm Dialogs
    AutoConfirm = true,
    AutoConfirm_ReadyCheck = true,
    AutoConfirm_Summon = true,
    AutoConfirm_RoleCheck = true,
    AutoConfirm_Resurrect = true,
    AutoConfirm_Binding = false, -- Off by default - risky
    AutoConfirm_DeleteGrey = true,
    
    -- Auto-Invite Accept
    AutoInvite = false, -- Off by default - opt-in
    AutoInvite_Friends = true,
    AutoInvite_BNetFriends = true,
    AutoInvite_Guild = true,
    AutoInvite_GuildInvites = false,
    
    -- Auto-Release Spirit
    AutoRelease = false, -- Off by default - opt-in
    AutoRelease_Mode = "PVP", -- ALWAYS, PVP, PVE, OPENWORLD
    AutoRelease_Delay = 0.5,
    AutoRelease_Notify = true,
    
    -- Tooltip Plus
    TooltipPlus = true, -- Enabled by default
    TooltipPlus_Anchor = "DEFAULT", -- DEFAULT, MOUSE, TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT
    TooltipPlus_MouseSide = "RIGHT", -- RIGHT, LEFT, TOP, BOTTOM
    TooltipPlus_MouseOffset = 20,
    TooltipPlus_Scale = 100,
    TooltipPlus_HideHealthbar = false,
    TooltipPlus_HideGuild = false,
    TooltipPlus_HideFaction = false,
    TooltipPlus_HidePvP = false,
    TooltipPlus_HideRealm = false,
    TooltipPlus_ClassColors = true,
    TooltipPlus_RarityBorder = true, -- Color border by item rarity
    TooltipPlus_Compact = false,
    TooltipPlus_ShowItemID = false,
    TooltipPlus_ShowSpellID = false,
    TooltipPlus_ShowTransmog = true, -- Show transmog collection status in tooltip
    TooltipPlus_TransmogOverlay = true, -- Show transmog icon on item buttons
    TooltipPlus_TransmogCorner = "TOPRIGHT", -- TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT
    
    -- Minimap Button
    MinimapButtonAngle = 220,
    MinimapButtonHidden = false,
}

local DefaultCharValues = {
    -- Track seen cinematics per character
    SeenCinematics = {},
    SeenMovies = {},
}

----------------------------------------------
-- Database Loading
----------------------------------------------
local function LoadDatabase()
    RefactorDB = RefactorDB or {}
    RefactorCharDB = RefactorCharDB or {}
    
    DB = RefactorDB
    DB_PC = RefactorCharDB
    
    -- Apply defaults
    for key, value in pairs(DefaultValues) do
        if DB[key] == nil then
            DB[key] = value
        end
    end
    
    for key, value in pairs(DefaultCharValues) do
        if DB_PC[key] == nil then
            if type(value) == "table" then
                DB_PC[key] = {}
            else
                DB_PC[key] = value
            end
        end
    end
    
    -- Trigger initial setting events
    for key, value in pairs(DB) do
        CallbackRegistry:Trigger("SettingChanged." .. key, value, false)
    end
    
    CallbackRegistry:Trigger("DatabaseLoaded", DB, DB_PC)
end

----------------------------------------------
-- Print Helper
----------------------------------------------
local CHAT_PREFIX = "|cff00ccff[Refactor]|r "

function addon.Print(msg)
    print(CHAT_PREFIX .. msg)
end

function addon.PrintIfEnabled(settingKey, msg)
    if addon.GetDBBool(settingKey) then
        addon.Print(msg)
    end
end

----------------------------------------------
-- Utility Functions
----------------------------------------------
function addon.FormatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperLeft = copper % 100
    
    local str = ""
    if gold > 0 then
        str = str .. "|cffffd700" .. gold .. "g|r "
    end
    if silver > 0 or gold > 0 then
        str = str .. "|cffc7c7cf" .. silver .. "s|r "
    end
    str = str .. "|cffeda55f" .. copperLeft .. "c|r"
    
    return str
end

function addon.IsModifierKeyDown(modifierKey)
    if modifierKey == "SHIFT" then
        return IsShiftKeyDown()
    elseif modifierKey == "CTRL" then
        return IsControlKeyDown()
    elseif modifierKey == "ALT" then
        return IsAltKeyDown()
    else
        return false
    end
end

----------------------------------------------
-- Event Listener
----------------------------------------------
local EL = CreateFrame("Frame")
addon.EventListener = EL

EL:RegisterEvent("ADDON_LOADED")
EL:RegisterEvent("PLAYER_ENTERING_WORLD")

EL:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            LoadDatabase()
            CallbackRegistry:Trigger("AddonLoaded")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        CallbackRegistry:Trigger("PlayerEnteringWorld", isInitialLogin, isReloadingUi)
    end
end)

-- Module registration helper
addon.Modules = {}

function addon.RegisterModule(name, module)
    addon.Modules[name] = module
    if module.OnInitialize then
        CallbackRegistry:Register("AddonLoaded", module.OnInitialize, module)
    end
end
