-- Refactor Addon - Configuration Helpers
-- Module metadata for slash commands

local addonName, addon = ...
local L = addon.L

----------------------------------------------
-- Module Info (for slash commands)
-- Only key and name are needed - settings UI
-- builds its own interface in Settings/Main.lua
----------------------------------------------
addon.ModuleInfo = {
    { key = "AutoSellJunk",    name = L.MODULE_AUTO_SELL },
    { key = "AutoRepair",      name = L.MODULE_AUTO_REPAIR },
    { key = "AutoQuest",       name = L.MODULE_AUTO_QUEST },
    { key = "SkipCinematics",  name = L.MODULE_SKIP_CINEMATICS },
    { key = "FastLoot",        name = L.MODULE_FAST_LOOT },
    { key = "AutoConfirm",     name = L.MODULE_AUTO_CONFIRM },
    { key = "AutoInvite",      name = L.MODULE_AUTO_INVITE },
    { key = "AutoRelease",     name = L.MODULE_AUTO_RELEASE },
    { key = "TooltipPlus",     name = L.MODULE_TOOLTIP_PLUS },
    { key = "QuestNameplates", name = L.MODULE_QUEST_NAMEPLATES },
    { key = "LootToast",       name = L.MODULE_LOOT_TOAST },
    { key = "ChatPlus",        name = L.MODULE_CHAT_PLUS },
    { key = "ActionCam",       name = L.MODULE_ACTIONCAM },
    { key = "CombatFade",      name = L.MODULE_COMBAT_FADE },
    { key = "SpeedDisplay",    name = L.MODULE_SPEED_DISPLAY },
}

----------------------------------------------
-- Get Module Info by Key
----------------------------------------------
function addon.GetModuleInfo(key)
    for _, info in ipairs(addon.ModuleInfo) do
        if info.key == key then
            return info
        end
    end
    return nil
end

----------------------------------------------
-- Parse Module Key from String
-- Aliases for slash command convenience
----------------------------------------------
function addon.ParseModuleKey(input)
    input = input:lower():gsub("%s+", "")

    local aliases = {
        -- AutoSellJunk
        ["autosell"] = "AutoSellJunk",
        ["selljunk"] = "AutoSellJunk",
        ["junk"] = "AutoSellJunk",
        ["sell"] = "AutoSellJunk",

        -- AutoRepair
        ["autorepair"] = "AutoRepair",
        ["repair"] = "AutoRepair",

        -- AutoQuest
        ["autoquest"] = "AutoQuest",
        ["quest"] = "AutoQuest",
        ["quests"] = "AutoQuest",

        -- SkipCinematics
        ["skipcinematics"] = "SkipCinematics",
        ["skipcin"] = "SkipCinematics",
        ["cinema"] = "SkipCinematics",
        ["cinematics"] = "SkipCinematics",
        ["movie"] = "SkipCinematics",
        ["movies"] = "SkipCinematics",

        -- FastLoot
        ["fastloot"] = "FastLoot",
        ["loot"] = "FastLoot",
        ["quickloot"] = "FastLoot",

        -- AutoConfirm
        ["autoconfirm"] = "AutoConfirm",
        ["confirm"] = "AutoConfirm",

        -- AutoInvite
        ["autoinvite"] = "AutoInvite",
        ["invite"] = "AutoInvite",

        -- AutoRelease
        ["autorelease"] = "AutoRelease",
        ["release"] = "AutoRelease",

        -- TooltipPlus
        ["tooltipplus"] = "TooltipPlus",
        ["tooltip"] = "TooltipPlus",
        ["tip"] = "TooltipPlus",

        -- QuestNameplates
        ["questnameplates"] = "QuestNameplates",
        ["nameplates"] = "QuestNameplates",
        ["np"] = "QuestNameplates",

        -- LootToast
        ["loottoast"] = "LootToast",
        ["toast"] = "LootToast",
        ["toasts"] = "LootToast",

        -- ChatPlus
        ["chatplus"] = "ChatPlus",
        ["chat"] = "ChatPlus",

        -- ActionCam
        ["actioncam"] = "ActionCam",
        ["cam"] = "ActionCam",
        ["camera"] = "ActionCam",

        -- CombatFade
        ["combatfade"] = "CombatFade",
        ["fade"] = "CombatFade",

        -- SpeedDisplay
        ["speeddisplay"] = "SpeedDisplay",
        ["speed"] = "SpeedDisplay",
    }

    return aliases[input]
end
