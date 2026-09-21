--- @module interface.mapZoneLevels
--- Purpose: show a zone's level range beside its name when it is hovered on the world map.
--- Requires: WorldMapFrame, hooksecurefunc, C_Map.GetMapInfoAtPosition, C_Map.GetMapLevels, UnitLevel,
---     GetQuestDifficultyColor
--- Events: PLAYER_LEVEL_UP. The text is refreshed from a post-hook on Blizzard's own area label, which
---     the map already evaluates every frame while it is open, so the module has no OnUpdate of its own.
--- Hot: no, the hook returns on an unchanged label after one text read
local _, R = ...
local MapZoneLevels = R:RegisterModule({
    id = "interface.mapZoneLevels", category = "Interface", nameKey = "MAP_LEVELS_NAME",
    descriptionKey = "MAP_LEVELS_DESC", detailKey = "MAP_LEVELS_DETAIL",
    requires = { "WorldMapFrame", "hooksecurefunc", "C_Map.GetMapInfoAtPosition", "C_Map.GetMapLevels",
        "UnitLevel", "GetQuestDifficultyColor" },
    risk = "visible", defaultEnabled = true,
})

-- Level ranges by the zone name the client's own label shows. Forever 1.60.1 returns
-- 0, 0, 0, 0 from C_Map.GetMapLevels for every zone (dump, 20 Sep 2026), so its map draws the
-- name alone and no API has the data. Where the client does answer, the module stands down
-- and this table is never read. Keyed by name rather than map ID because Forever's map IDs
-- have not been probed. The values are the original zones' ranges as listed for the Classic
-- client (warcraft.wiki.gg, Zones by level, read 20 Sep 2026), unverified on Forever, which
-- is set earlier and may have tuned them. Of the new zones, Zephras Isle is Blizzard's own
-- "levels 1 through 12" and Riverglades the wiki's 35-45, matching Blizzard's "mid-30s to
-- mid-40s"; Mount Hyjal and Shen'dralas have no published range anywhere, so they are left
-- out rather than guessed. Static data, never invalidated. Cities have no range and are
-- left out on purpose.
local ZONE_LEVELS = {
    ["Elwynn Forest"] = { 1, 10 },
    ["Dun Morogh"] = { 1, 10 },
    ["Tirisfal Glades"] = { 1, 10 },
    ["Westfall"] = { 10, 20 },
    ["Loch Modan"] = { 10, 20 },
    ["Silverpine Forest"] = { 10, 20 },
    ["Redridge Mountains"] = { 15, 25 },
    ["Duskwood"] = { 18, 30 },
    ["Wetlands"] = { 20, 30 },
    ["Hillsbrad Foothills"] = { 20, 35 },
    ["Alterac Mountains"] = { 30, 40 },
    ["Arathi Highlands"] = { 30, 40 },
    ["Stranglethorn Vale"] = { 30, 45 },
    ["Badlands"] = { 35, 45 },
    ["Swamp of Sorrows"] = { 35, 45 },
    ["The Hinterlands"] = { 40, 50 },
    ["Searing Gorge"] = { 45, 50 },
    ["Blasted Lands"] = { 45, 55 },
    ["Burning Steppes"] = { 50, 58 },
    ["Western Plaguelands"] = { 51, 58 },
    ["Eastern Plaguelands"] = { 53, 60 },
    ["Deadwind Pass"] = { 55, 60 },
    ["Riverglades"] = { 35, 45 },
    ["Durotar"] = { 1, 10 },
    ["Mulgore"] = { 1, 10 },
    ["Teldrassil"] = { 1, 10 },
    ["The Barrens"] = { 10, 25 },
    ["Darkshore"] = { 10, 20 },
    ["Stonetalon Mountains"] = { 15, 27 },
    ["Ashenvale"] = { 18, 30 },
    ["Thousand Needles"] = { 25, 35 },
    ["Desolace"] = { 30, 40 },
    ["Dustwallow Marsh"] = { 35, 45 },
    ["Feralas"] = { 40, 50 },
    ["Tanaris"] = { 40, 50 },
    ["Azshara"] = { 45, 55 },
    ["Felwood"] = { 48, 55 },
    ["Un'Goro Crater"] = { 48, 55 },
    ["Winterspring"] = { 53, 60 },
    ["Moonglade"] = { 55, 60 },
    ["Silithus"] = { 55, 60 },
    ["Zephras Isle"] = { 1, 12 },
}
-- The table is English, like the names it matches, so the article is too.
local ARTICLE = "The "
local GAP = 4

-- Blizzard keeps the map's providers as the keys of WorldMapFrame.dataProviders. The area
-- label provider is the one holding a Label frame with a Name font string
-- (AreaLabelDataProvider.lua, AreaLabelFrameTemplate). Found by shape, never by position,
-- so a client that adds providers in another order still resolves it.
function MapZoneLevels:FindLabel()
    local providers = WorldMapFrame.dataProviders
    if type(providers) ~= "table" then
        return nil
    end
    for provider in pairs(providers) do
        local label = type(provider) == "table" and provider.Label
        if type(label) == "table" and type(label.Name) == "table" and type(label.Name.GetText) == "function"
            and type(label.EvaluateLabels) == "function" and type(label.CreateFontString) == "function" then
            return label
        end
    end
    return nil
end

function MapZoneLevels:Lookup(name)
    local range = ZONE_LEVELS[name]
    if range then
        return range
    end
    if name:sub(1, #ARTICLE) == ARTICLE then
        return ZONE_LEVELS[name:sub(#ARTICLE + 1)]
    end
    return ZONE_LEVELS[ARTICLE .. name]
end

function MapZoneLevels:Clear()
    self.text:SetText("")
    self.text:Hide()
end

-- Runs once per change of the label's text, never per frame. Blizzard's label names the
-- hovered child map; a subzone of the open map or a point of interest carries no zone level.
function MapZoneLevels:Refresh(name)
    if type(name) ~= "string" or name == "" then
        return self:Clear()
    end
    local mapID = WorldMapFrame:GetMapID()
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if type(info) ~= "table" or info.mapID == mapID or info.name ~= name then
        return self:Clear()
    end
    local minLevel, maxLevel = C_Map.GetMapLevels(info.mapID)
    if type(minLevel) == "number" and minLevel > 0 and type(maxLevel) == "number" and maxLevel > 0 then
        -- The client knows the range, and Blizzard's label already draws it.
        return self:Clear()
    end
    local range = self:Lookup(info.name)
    if not range then
        return self:Clear()
    end
    minLevel, maxLevel = range[1], range[2]
    -- The same three cases as Blizzard's own label: below the zone, the bottom of the range
    -- sets the colour; above it, two under the top, so a zone only just outgrown reads green
    -- rather than yellow; inside it, the player's own level, which is always yellow.
    local playerLevel = UnitLevel("player")
    local level
    if playerLevel < minLevel then
        level = minLevel
    elseif playerLevel > maxLevel then
        level = maxLevel - 2
    else
        level = playerLevel
    end
    local color = GetQuestDifficultyColor(level)
    local text = self.text
    if minLevel == maxLevel then
        text:SetText(string.format(R.L.MAP_LEVELS_SINGLE, maxLevel))
    else
        text:SetText(string.format(R.L.MAP_LEVELS_RANGE, minLevel, maxLevel))
    end
    text:SetTextColor(color.r, color.g, color.b)
    text:Show()
end

function MapZoneLevels:Invalidate()
    self.lastText = nil
end

function MapZoneLevels:OnEnable()
    local label = self.label or self:FindLabel()
    if not label then
        R:Fail(self, R.L.MAP_LEVELS_NO_LABEL, "enable")
        return
    end
    self.label = label
    if not self.text then
        -- Created once and kept across enables. It sits beside Blizzard's name text in that
        -- text's own font, so the pair reads as one line; the colour is the game's own quest
        -- difficulty colour, set on each refresh.
        local text = R.Theme:Text(label, "", "title")
        local font = label.Name:GetFontObject()
        if font then
            text:SetFontObject(font)
        end
        text:SetPoint("LEFT", label.Name, "RIGHT", GAP, 0)
        self.text = text
    end
    self:Clear()
    self.lastText = nil
    if not self.installed then
        self.installed = true
        -- The label's own OnUpdate calls this every frame while the map is open. The hook
        -- reads one string and returns unless it changed, and only then goes through the
        -- guarded path, so nothing is allocated on the unchanged frames.
        hooksecurefunc(label, "EvaluateLabels", function(frame)
            if self.state ~= "enabled" then
                return
            end
            local text = frame.Name:GetText()
            if text == self.lastText then
                return
            end
            self.lastText = text
            R:SafeCall(self, self.Refresh, "map label", text)
        end)
    end
    R.Broker:Subscribe("PLAYER_LEVEL_UP", self.Invalidate, self)
end

function MapZoneLevels:OnDisable()
    R.Broker:UnsubscribeAll(self)
    self.lastText = nil
    if self.text then
        self:Clear()
    end
end
