--- @integration Neighbours
--- Purpose: list which installed addons overlap which Refactor modules.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...

R.Integrations = R.Integrations or {}

-- Folder names, because that is what the client can answer for. Each entry names the
-- Refactor modules the neighbour already covers, so the conflict panel can say something
-- concrete instead of "an addon may conflict".
R.Integrations.neighbours = {
    { addon = "Leatrix_Plus", labelKey = "NEIGHBOUR_LEATRIX",
        modules = { "loot.fastLoot", "vendor.autoSell", "vendor.autoRepair", "quest.autoGossip" } },
    { addon = "Questie", labelKey = "NEIGHBOUR_QUESTIE",
        modules = { "nameplates.questProgress" } },
    { addon = "Plater", labelKey = "NEIGHBOUR_PLATER",
        modules = { "nameplates.questProgress" } },
    { addon = "TidyPlates_ThreatPlates", labelKey = "NEIGHBOUR_THREATPLATES",
        modules = { "nameplates.questProgress" } },
    { addon = "NeatPlates", labelKey = "NEIGHBOUR_NEATPLATES",
        modules = { "nameplates.questProgress" } },
    { addon = "Scrap", labelKey = "NEIGHBOUR_SCRAP",
        modules = { "vendor.autoSell" } },
    { addon = "Plumber", labelKey = "NEIGHBOUR_PLUMBER",
        modules = { "vendor.itemCosts" } },
    -- The quest, vendor, camera, map, chat, tooltip and loot addons a Forever player is most
    -- likely to bring along, each against only what it really does too.
    { addon = "AutoTurnIn", labelKey = "NEIGHBOUR_AUTOTURNIN",
        modules = { "quest.autoAccept", "quest.autoTurnIn" } },
    { addon = "Dejunk", labelKey = "NEIGHBOUR_DEJUNK",
        modules = { "vendor.autoSell" } },
    { addon = "Peddler", labelKey = "NEIGHBOUR_PEDDLER",
        modules = { "vendor.autoSell" } },
    { addon = "DynamicCam", labelKey = "NEIGHBOUR_DYNAMICCAM",
        modules = { "interface.actionCam" } },
    { addon = "Leatrix_Maps", labelKey = "NEIGHBOUR_LEATRIX_MAPS",
        modules = { "interface.mapReveal", "interface.mapZoneLevels" } },
    { addon = "Mapster", labelKey = "NEIGHBOUR_MAPSTER",
        modules = { "interface.mapReveal" } },
    { addon = "TipTac", labelKey = "NEIGHBOUR_TIPTAC",
        modules = { "tooltips.anchor", "tooltips.rarityBorder" } },
    { addon = "BasicChatMods", labelKey = "NEIGHBOUR_BASICCHATMODS",
        modules = { "chat.urls", "chat.copy" } },
    { addon = "Prat-3.0", labelKey = "NEIGHBOUR_PRAT",
        modules = { "chat.urls", "chat.copy" } },
    { addon = "XLoot_Monitor", labelKey = "NEIGHBOUR_XLOOT_MONITOR",
        modules = { "toasts.loot" } },
}

function R.Integrations:Conflicts(into)
    local found = into or {}
    for index = #found, 1, -1 do
        found[index] = nil
    end
    for _, neighbour in ipairs(self.neighbours) do
        if self:IsLoaded(neighbour.addon) then
            for _, id in ipairs(neighbour.modules) do
                local module = R.moduleByID[id]
                if module then
                    found[#found + 1] = { addon = neighbour.addon, labelKey = neighbour.labelKey, module = module }
                end
            end
        end
    end
    return found
end
