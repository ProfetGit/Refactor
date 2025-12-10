-- Refactor Addon - Core Initialization

local addonName, addon = ...

-- Version info
addon.VERSION = "1.0.0"
addon.ADDON_NAME = addonName

-- Database references (set after ADDON_LOADED)
local DB
local DB_PC

----------------------------------------------
-- Callback Registry
----------------------------------------------
local CallbackRegistry = {}
CallbackRegistry.events = {}
addon.CallbackRegistry = CallbackRegistry

function CallbackRegistry:Register(event, func, owner)
    if not self.events[event] then
        self.events[event] = {}
    end

    local callbackType = type(func) == "string" and 2 or 1
    table.insert(self.events[event], { callbackType, func, owner })
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
-- DESIGN PHILOSOPHY:
-- ✅ ON by default: Pure QoL features with no risk (auto repair, fast loot, tooltips)
-- ❌ OFF by default: Features that significantly change gameplay (auto quest, cinematics)
--                   OR have potential for regret (binding confirmation, sell transmog)
--
-- Sub-options: When a module is enabled, its sub-options should reflect what
--              users most commonly want from that feature.
----------------------------------------------

local DefaultValues = {
    ----------------------------------------------
    -- AUTO-SELL JUNK
    -- ON: Everyone hates grey items cluttering bags
    ----------------------------------------------
    AutoSellJunk = true,
    AutoSellJunk_ShowNotify = true,         -- ON: Transparency - show what was sold
    AutoSellJunk_SellKnownTransmog = false, -- OFF: Risky - might regret selling
    AutoSellJunk_KeepTransmog = true,       -- ON: Protect uncollected appearances
    AutoSellJunk_SellLowILvl = false,       -- OFF: Risky - could sell sentimental gear
    AutoSellJunk_MaxILvl = 400,             -- Safe threshold (old expansion gear)

    ----------------------------------------------
    -- AUTO-REPAIR
    -- ON: Universal QoL, nobody wants broken gear
    ----------------------------------------------
    AutoRepair = true,
    AutoRepair_UseGuild = true,   -- ON: Expected behavior, saves gold
    AutoRepair_ShowNotify = true, -- ON: Transparency

    ----------------------------------------------
    -- AUTO-QUEST
    -- OFF: Significantly changes how you interact with NPCs
    --      Let players opt-in to this automation
    ----------------------------------------------
    AutoQuest = false,
    AutoQuest_Accept = true,           -- ON: If enabled, they want full automation
    AutoQuest_TurnIn = true,           -- ON: Core functionality
    AutoQuest_SkipGossip = true,       -- ON: Skip "I have a quest" dialogue
    AutoQuest_SingleOption = true,     -- ON: Auto-select lone dialogue option
    AutoQuest_ContinueDialogue = true, -- ON: Auto-click "Continue" options
    AutoQuest_DailyOnly = false,       -- OFF: Too restrictive
    AutoQuest_ModifierKey = "SHIFT",   -- Standard modifier for overrides

    ----------------------------------------------
    -- SKIP CINEMATICS
    -- OFF: Preserve first-time story experience
    --      Cinematics are content, not annoyance
    ----------------------------------------------
    SkipCinematics = false,
    SkipCinematics_AlwaysSkip = false, -- OFF: Even more important
    SkipCinematics_ModifierKey = "SHIFT",

    ----------------------------------------------
    -- FAST LOOT
    -- ON: Pure QoL, zero downside, everyone wants faster looting
    ----------------------------------------------
    FastLoot = true,

    ----------------------------------------------
    -- AUTO-CONFIRM DIALOGS
    -- OFF: Users should opt-in to auto-confirming
    ----------------------------------------------
    AutoConfirm = false,
    AutoConfirm_ReadyCheck = true, -- ON: No one enjoys clicking this
    AutoConfirm_Summon = true,     -- ON: Safe, expected
    AutoConfirm_RoleCheck = true,  -- ON: Standard convenience
    AutoConfirm_Resurrect = true,  -- ON: Always want to accept rez
    AutoConfirm_Binding = false,   -- OFF: Risky - accidental BoP hurts

    ----------------------------------------------
    -- AUTO-INVITE ACCEPT
    -- OFF: Social preference, opt-in only
    ----------------------------------------------
    AutoInvite = false,
    AutoInvite_Friends = true,       -- ON: If enabled, trusted sources
    AutoInvite_BNetFriends = true,   -- ON: If enabled, trusted sources
    AutoInvite_Guild = true,         -- ON: If enabled, trusted sources
    AutoInvite_GuildInvites = false, -- OFF: Random guild spam, keep manual

    ----------------------------------------------
    -- AUTO-RELEASE SPIRIT
    -- OFF: Some players hate auto-release
    --      Must be explicit opt-in
    ----------------------------------------------
    AutoRelease = false,
    AutoRelease_Mode = "PVP",  -- Safest mode (only in battlegrounds/arenas)
    AutoRelease_Delay = 0.5,
    AutoRelease_Notify = true, -- ON: Always notify on auto-actions

    ----------------------------------------------
    -- TOOLTIP PLUS
    -- ON: Core feature that shows addon value immediately
    ----------------------------------------------
    TooltipPlus = true,
    TooltipPlus_Anchor = "DEFAULT", -- DEFAULT: Don't surprise users
    TooltipPlus_MouseSide = "RIGHT",
    TooltipPlus_MouseOffset = 20,
    TooltipPlus_Scale = 100,
    TooltipPlus_ClassColors = true,     -- ON: Visually nice, expected
    TooltipPlus_RarityBorder = true,    -- ON: Visually nice, expected
    TooltipPlus_ShowTransmog = true,    -- ON: Key useful feature
    TooltipPlus_TransmogOverlay = true, -- ON: Visual QoL for transmog hunters
    TooltipPlus_TransmogCorner = "TOPRIGHT",
    -- Hide options - OFF: Don't remove info by default
    TooltipPlus_HideHealthbar = false,
    TooltipPlus_HideGuild = false,
    TooltipPlus_HideFaction = false,
    TooltipPlus_HidePvP = false,
    TooltipPlus_HideRealm = false,
    -- Developer/Advanced options - OFF
    TooltipPlus_ShowItemID = false,
    TooltipPlus_ShowSpellID = false,
    TooltipPlus_Compact = false,

    ----------------------------------------------
    -- QUEST NAMEPLATES
    -- ON: Visual QoL showing quest progress on mobs
    ----------------------------------------------
    QuestNameplates = true,
    QuestNameplates_ShowKillIcon = true, -- ON: Core visual feature
    QuestNameplates_ShowLootIcon = true, -- ON: Core visual feature

    ----------------------------------------------
    -- LOOT TOAST
    -- ON: Nice visual loot notifications
    ----------------------------------------------
    LootToast = true,
    LootToast_Duration = 4,                 -- Balanced duration
    LootToast_MaxVisible = 6,               -- Reasonable amount
    LootToast_ShowCurrency = true,          -- ON: Users want to see gains
    LootToast_ShowQuantity = true,          -- ON: Context is good
    LootToast_MinQuality = 0,               -- 0 = Show all, 1 = Common+, 2 = Uncommon+, etc.
    LootToast_AlwaysShowUncollected = true, -- ON: Always show uncollected transmog regardless of quality filter

    ----------------------------------------------
    -- ACTION CAM
    -- OFF: Significantly changes core camera feel
    --      Must be explicit opt-in
    ----------------------------------------------
    ActionCam = false,
    ActionCam_Mode = "basic",

    ----------------------------------------------
    -- COMBAT FADE
    -- OFF: Major UI change, must be opt-in
    ----------------------------------------------
    CombatFade = false,
    CombatFade_ActionBars = true,   -- ON: If enabled, this is what they want
    CombatFade_ActionBars_Opacity = 30,
    CombatFade_PlayerFrame = false, -- OFF: More aggressive, separate opt-in
    CombatFade_PlayerFrame_Opacity = 30,

    ----------------------------------------------
    -- SPEED DISPLAY
    -- OFF: Not everyone wants speed shown
    ----------------------------------------------
    SpeedDisplay = false,
    SpeedDisplay_Decimals = false, -- OFF: Show 100% not 100.0%

    ----------------------------------------------
    -- MINIMAP BUTTON
    ----------------------------------------------
    MinimapButtonAngle = 220,
    MinimapButtonHidden = false, -- OFF: Show button for settings access
}

-- Expose for Reset to Defaults functionality
addon.DEFAULT_SETTINGS = DefaultValues

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
