--- @module interface.mapTravel
--- Purpose: mark boat and zeppelin points on the world map, listing where each one goes.
--- Requires: WorldMapFrame, GameTooltip, hooksecurefunc, UnitFactionGroup, C_TaxiMap.GetTaxiNodesForMap,
---     C_AreaPoiInfo.GetAreaPOIForMap, C_AreaPoiInfo.GetAreaPOIInfo, C_Map.GetMapLinksForMap, C_Texture.GetAtlasInfo
--- Events: none. Redraws ride on post-hooks of the world map's own refresh, so nothing polls.
--- Hot: no
local _, R = ...
local MapTravel = R:RegisterModule({
    id = "interface.mapTravel", category = "Map", nameKey = "MAP_TRAVEL_NAME",
    descriptionKey = "MAP_TRAVEL_DESC", detailKey = "MAP_TRAVEL_DETAIL",
    requires = { "WorldMapFrame", "GameTooltip", "hooksecurefunc", "UnitFactionGroup",
        "C_TaxiMap.GetTaxiNodesForMap", "C_AreaPoiInfo.GetAreaPOIForMap", "C_AreaPoiInfo.GetAreaPOIInfo",
        "C_Map.GetMapLinksForMap", "C_Texture.GetAtlasInfo" },
    risk = "visible", defaultEnabled = false,
})

local KIND = "travel"

function MapTravel:Collect(mapID)
    return R.MapData:Travel(mapID)
end

function MapTravel:OnEnable()
    R.UI.MapPins:Attach(self, KIND, self.Collect)
end

function MapTravel:OnDisable()
    R.UI.MapPins:Detach(KIND)
end
