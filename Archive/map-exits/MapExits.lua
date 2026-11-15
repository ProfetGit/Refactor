--- @module interface.mapExits
--- Purpose: draw an arrow at each edge of a zone where the player can leave it, and mark the map links inside it.
--- Requires: WorldMapFrame, GameTooltip, hooksecurefunc, IsShiftKeyDown, IsControlKeyDown, C_Map.GetMapInfo,
---     C_Map.GetMapRectOnMap,
---     C_Map.GetMapInfoAtPosition, C_Map.GetMapChildrenInfo, C_Map.GetMapLinksForMap, C_Texture.GetAtlasInfo
--- Events: REFACTOR_SETTINGS_CHANGED. Redraws ride on post-hooks of the world map's own refresh, so
---     nothing polls.
--- Hot: no
local _, R = ...
local MapExits = R:RegisterModule({
    id = "interface.mapExits", category = "Interface", nameKey = "MAP_EXITS_NAME",
    descriptionKey = "MAP_EXITS_DESC", detailKey = "MAP_EXITS_DETAIL",
    requires = { "WorldMapFrame", "GameTooltip", "hooksecurefunc", "IsShiftKeyDown", "IsControlKeyDown",
        "C_Map.GetMapInfo",
        "C_Map.GetMapRectOnMap", "C_Map.GetMapChildrenInfo", "C_Map.GetMapInfoAtPosition",
        "C_Map.GetMapLinksForMap", "C_Texture.GetAtlasInfo" },
    risk = "visible", defaultEnabled = false,
})

local KIND = "exits"

function MapExits:Collect(mapID)
    return R.MapData:Exits(mapID)
end

-- An arrow was moved or put back: draw the map again with it where it now belongs.
function MapExits:OnSettingsChanged(_, key)
    if key == "mapExitOverrides" and self.refreshPins then
        self.refreshPins()
    end
end

function MapExits:OnEnable()
    R.UI.MapPins:Attach(self, KIND, self.Collect)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
end

function MapExits:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R.UI.MapPins:Detach(KIND)
end
