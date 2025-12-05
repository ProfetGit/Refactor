-- Refactor Addon - Configuration Helpers
-- Additional config utilities and option definitions

local addonName, addon = ...
local L = addon.L

----------------------------------------------
-- Module Definitions (for settings UI)
----------------------------------------------
addon.ModuleInfo = {
    {
        key = "AutoSellJunk",
        name = L.MODULE_AUTO_SELL,
        description = "Automatically sells all grey (junk) items when opening a vendor.",
        category = "Vendor",
        options = {
            {
                key = "AutoSellJunk_ShowNotify",
                type = "checkbox",
                label = L.SHOW_NOTIFICATIONS,
            },
        },
    },
    {
        key = "AutoRepair",
        name = L.MODULE_AUTO_REPAIR,
        description = "Automatically repairs all gear when opening a repair-capable vendor.",
        category = "Vendor",
        options = {
            {
                key = "AutoRepair_UseGuild",
                type = "checkbox",
                label = L.USE_GUILD_FUNDS,
            },
            {
                key = "AutoRepair_ShowNotify",
                type = "checkbox",
                label = L.SHOW_NOTIFICATIONS,
            },
        },
    },
    {
        key = "AutoQuest",
        name = L.MODULE_AUTO_QUEST,
        description = "Automatically accepts and turns in quests, skipping dialogue.",
        category = "Quests",
        options = {
            {
                key = "AutoQuest_Accept",
                type = "checkbox",
                label = L.AUTO_ACCEPT,
            },
            {
                key = "AutoQuest_TurnIn",
                type = "checkbox",
                label = L.AUTO_TURNIN,
            },
            {
                key = "AutoQuest_SkipGossip",
                type = "checkbox",
                label = L.SKIP_GOSSIP,
            },
            {
                key = "AutoQuest_DailyOnly",
                type = "checkbox",
                label = L.DAILY_QUESTS_ONLY,
            },
            {
                key = "AutoQuest_ModifierKey",
                type = "dropdown",
                label = L.MODIFIER_KEY,
                options = {
                    { value = "SHIFT", label = L.MODIFIER_SHIFT },
                    { value = "CTRL", label = L.MODIFIER_CTRL },
                    { value = "ALT", label = L.MODIFIER_ALT },
                    { value = "NONE", label = L.MODIFIER_NONE },
                },
            },
        },
    },
    {
        key = "SkipCinematics",
        name = L.MODULE_SKIP_CINEMATICS,
        description = "Automatically skips cinematics and in-game movies you've seen before.",
        category = "Cinematics",
        options = {
            {
                key = "SkipCinematics_AlwaysSkip",
                type = "checkbox",
                label = L.ALWAYS_SKIP,
            },
            {
                key = "SkipCinematics_ModifierKey",
                type = "dropdown",
                label = L.MODIFIER_KEY,
                options = {
                    { value = "SHIFT", label = L.MODIFIER_SHIFT },
                    { value = "CTRL", label = L.MODIFIER_CTRL },
                    { value = "ALT", label = L.MODIFIER_ALT },
                    { value = "NONE", label = L.MODIFIER_NONE },
                },
            },
        },
    },
    {
        key = "FastLoot",
        name = L.MODULE_FAST_LOOT,
        description = "Instantly loots all items without showing the loot window.",
        category = "Loot",
        options = {},
    },
    {
        key = "AutoConfirm",
        name = L.MODULE_AUTO_CONFIRM,
        description = "Automatically confirms common dialogs like ready checks and summons.",
        category = "Automation",
        options = {},
    },
    {
        key = "AutoInvite",
        name = L.MODULE_AUTO_INVITE,
        description = "Automatically accepts party invites from friends and guildies.",
        category = "Social",
        options = {},
    },
    {
        key = "AutoRelease",
        name = L.MODULE_AUTO_RELEASE,
        description = "Automatically releases spirit on death in selected content types.",
        category = "Combat",
        options = {},
    },
    {
        key = "TooltipPlus",
        name = L.MODULE_TOOLTIP_PLUS,
        description = "Customize tooltip appearance, position, and information display.",
        category = "Tooltip",
        options = {
            {
                key = "TooltipPlus_Anchor",
                type = "dropdown",
                label = L.TOOLTIP_ANCHOR,
                options = {
                    { value = "DEFAULT", label = L.ANCHOR_DEFAULT },
                    { value = "MOUSE", label = L.ANCHOR_MOUSE },
                    { value = "TOPLEFT", label = L.ANCHOR_TOPLEFT },
                    { value = "TOPRIGHT", label = L.ANCHOR_TOPRIGHT },
                    { value = "BOTTOMLEFT", label = L.ANCHOR_BOTTOMLEFT },
                    { value = "BOTTOMRIGHT", label = L.ANCHOR_BOTTOMRIGHT },
                },
            },
            {
                key = "TooltipPlus_MouseSide",
                type = "dropdown",
                label = L.TOOLTIP_MOUSE_SIDE,
                options = {
                    { value = "RIGHT", label = L.SIDE_RIGHT },
                    { value = "LEFT", label = L.SIDE_LEFT },
                    { value = "TOP", label = L.SIDE_TOP },
                    { value = "BOTTOM", label = L.SIDE_BOTTOM },
                },
            },
            {
                key = "TooltipPlus_HideHealthbar",
                type = "checkbox",
                label = L.TOOLTIP_HIDE_HEALTHBAR,
            },
            {
                key = "TooltipPlus_ClassColors",
                type = "checkbox",
                label = L.TOOLTIP_CLASS_COLORS,
            },
            {
                key = "TooltipPlus_ShowItemID",
                type = "checkbox",
                label = L.TOOLTIP_SHOW_ITEM_ID,
            },
            {
                key = "TooltipPlus_ShowSpellID",
                type = "checkbox",
                label = L.TOOLTIP_SHOW_SPELL_ID,
            },
        },
    },
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
-- Get All Modules in Category
----------------------------------------------
function addon.GetModulesInCategory(category)
    local modules = {}
    for _, info in ipairs(addon.ModuleInfo) do
        if info.category == category then
            table.insert(modules, info)
        end
    end
    return modules
end

----------------------------------------------
-- Module Categories
----------------------------------------------
addon.Categories = {
    { key = "Vendor", name = L.SETTINGS_VENDOR, icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    { key = "Loot", name = L.SETTINGS_LOOT, icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { key = "Quests", name = L.SETTINGS_QUESTS, icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "Cinematics", name = L.SETTINGS_CINEMATICS, icon = "Interface\\Icons\\INV_Misc_Film_01" },
    { key = "Tooltip", name = L.SETTINGS_TOOLTIP, icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

----------------------------------------------
-- Parse Module Key from String
----------------------------------------------
function addon.ParseModuleKey(input)
    input = input:lower():gsub("%s+", "")
    
    local aliases = {
        ["autosell"] = "AutoSellJunk",
        ["selljunk"] = "AutoSellJunk",
        ["junk"] = "AutoSellJunk",
        ["sell"] = "AutoSellJunk",
        
        ["autorepair"] = "AutoRepair",
        ["repair"] = "AutoRepair",
        
        ["autoquest"] = "AutoQuest",
        ["quest"] = "AutoQuest",
        ["quests"] = "AutoQuest",
        
        ["skipcin"] = "SkipCinematics",
        ["cinema"] = "SkipCinematics",
        ["cinematics"] = "SkipCinematics",
        ["movie"] = "SkipCinematics",
        ["movies"] = "SkipCinematics",
        
        ["fastloot"] = "FastLoot",
        ["loot"] = "FastLoot",
        ["quickloot"] = "FastLoot",
        
        ["tooltipplus"] = "TooltipPlus",
        ["tooltip"] = "TooltipPlus",
        ["tip"] = "TooltipPlus",
    }
    
    return aliases[input]
end
