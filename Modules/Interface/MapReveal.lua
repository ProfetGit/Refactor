--- @module interface.mapReveal
--- Purpose: draw the unexplored parts of the world map, dimmed, under the client's explored overlays.
--- Requires: WorldMapFrame, hooksecurefunc, C_Map.GetMapArtID, C_Map.GetMapArtLayers, GetBuildInfo
--- Events: none. Redraws ride on post-hooks of Blizzard's own exploration pin, which the map
---     refreshes on every map change and exploration update, so nothing polls.
--- Hot: no
local _, R = ...
local MapReveal = R:RegisterModule({
    id = "interface.mapReveal", category = "Interface", nameKey = "MAP_REVEAL_NAME",
    descriptionKey = "MAP_REVEAL_DESC", detailKey = "MAP_REVEAL_DETAIL",
    requires = { "WorldMapFrame", "hooksecurefunc", "C_Map.GetMapArtID", "C_Map.GetMapArtLayers",
        "GetBuildInfo" },
    risk = "visible", defaultEnabled = false,
})

local PIN_TEMPLATE = "MapExplorationPinTemplate"
local data = R.MapOverlays

-- Data/MapOverlays.lua is generated for one client. Another client's map art IDs would put
-- the wrong art on the wrong map, so the module is unavailable rather than wrong.
if type(data) ~= "table" or type(data.maps) ~= "table" or data.interface ~= select(4, GetBuildInfo()) then
    MapReveal.unavailableReasonKey = "MAP_REVEAL_NO_DATA"
end

-- Blizzard's exploration provider keeps one permanent pin of this template, acquired when
-- the map loads. Ours sits under it and follows its refreshes.
function MapReveal:FindPin()
    for pin in WorldMapFrame:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        if type(pin) == "table" and type(pin.RefreshOverlays) == "function"
            and type(pin.RemoveAllData) == "function" and type(pin.RefreshAlpha) == "function" then
            return pin
        end
    end
    return nil
end

-- Parsed once per map art and kept: the strings are generated data that never changes.
function MapReveal:Overlays(artID)
    local parsed = self.parsed[artID]
    if parsed then
        return parsed
    end
    parsed = {}
    for _, entry in ipairs(data.maps[artID]) do
        local width, height, x, y, ids = entry:match("^(%d+):(%d+):(%d+):(%d+):([%d,]+)$")
        if width then
            local overlay = { width = tonumber(width), height = tonumber(height),
                x = tonumber(x), y = tonumber(y), ids = {} }
            for id in ids:gmatch("%d+") do
                overlay.ids[#overlay.ids + 1] = tonumber(id)
            end
            parsed[#parsed + 1] = overlay
        end
    end
    self.parsed[artID] = parsed
    return parsed
end

function MapReveal:Redraw()
    local layer, pin = self.layer, self.pin
    R.UI:MapRevealClear(layer)
    local mapID = WorldMapFrame:GetMapID()
    local artID = mapID and C_Map.GetMapArtID(mapID)
    if not artID or not data.maps[artID] then
        return
    end
    local layers = C_Map.GetMapArtLayers(mapID)
    local art = type(layers) == "table" and layers[WorldMapFrame:GetCanvasContainer():GetCurrentLayerIndex()]
    if type(art) ~= "table" or not art.tileWidth or not art.tileHeight then
        return
    end
    layer:SetFrameLevel(pin:GetFrameLevel() - 1)
    layer:SetAlpha(pin:GetAlpha())
    R.UI:MapRevealDraw(layer, self:Overlays(artID), art.tileWidth, art.tileHeight)
end

function MapReveal:OnEnable()
    local pin = self.pin or self:FindPin()
    if not pin then
        R:Fail(self, R.L.MAP_REVEAL_NO_PIN, "enable")
        return
    end
    self.pin = pin
    self.parsed = self.parsed or {}
    if not self.layer then
        self.layer = R.UI:MapRevealLayer(WorldMapFrame:GetCanvas())
    end
    if not self.installed then
        self.installed = true
        -- The pin clears itself inside every refresh, then draws; our clear and draw follow
        -- each in turn. Its alpha is zero while its textures load and the map's global alpha
        -- after, and ours copies it so a dim layer never shows before the map does.
        hooksecurefunc(pin, "RefreshOverlays", function()
            if self.state == "enabled" then
                R:SafeCall(self, self.Redraw, "map reveal")
            end
        end)
        hooksecurefunc(pin, "RemoveAllData", function()
            if self.state == "enabled" and self.layer then
                R.UI:MapRevealClear(self.layer)
            end
        end)
        hooksecurefunc(pin, "RefreshAlpha", function(frame)
            if self.state == "enabled" and self.layer then
                self.layer:SetAlpha(frame:GetAlpha())
            end
        end)
    end
    self.layer:Show()
    if WorldMapFrame:IsShown() then
        self:Redraw()
    end
end

function MapReveal:OnDisable()
    R.Broker:UnsubscribeAll(self)
    if self.layer then
        R.UI:MapRevealClear(self.layer)
        self.layer:Hide()
    end
end
