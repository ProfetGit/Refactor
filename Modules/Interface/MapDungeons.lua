--- @module interface.mapDungeons
--- Purpose: mark dungeon and raid entrances on the world map, with a tooltip and a click that opens the entrance's map.
--- Requires: WorldMapFrame, GameTooltip, hooksecurefunc, C_EncounterJournal.GetDungeonEntrancesForMap,
---     C_Texture.GetAtlasInfo
--- Events: none. Redraws ride on post-hooks of the world map's own refresh, so nothing polls.
--- Hot: no
local _, R = ...
local MapDungeons = R:RegisterModule({
    id = "interface.mapDungeons", category = "Map", nameKey = "MAP_DUNGEONS_NAME",
    descriptionKey = "MAP_DUNGEONS_DESC", detailKey = "MAP_DUNGEONS_DETAIL",
    requires = { "WorldMapFrame", "GameTooltip", "hooksecurefunc",
        "C_EncounterJournal.GetDungeonEntrancesForMap", "C_Texture.GetAtlasInfo" },
    risk = "visible", defaultEnabled = false,
})

local KIND, NATIVE_PIN = "dungeons", "DungeonEntrancePinTemplate"

-- When the map's own entrance pins are up the player already sees them, and a second set on
-- top would only double the tooltip.
function MapDungeons:Collect(mapID)
    if WorldMapFrame:EnumeratePinsByTemplate(NATIVE_PIN)() ~= nil then
        return {}
    end
    return R.MapData:Dungeons(mapID)
end

function MapDungeons:OnEnable()
    R.UI.MapPins:Attach(self, KIND, self.Collect)
end

function MapDungeons:OnDisable()
    R.UI.MapPins:Detach(KIND)
end
