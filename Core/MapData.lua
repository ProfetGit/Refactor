--- @core mapData
--- Purpose: turn the client's map answers (dungeon entrances, links, area POIs, neighbouring zones) into pin entries.
--- Requires: C_Map.GetMapInfo, C_Map.GetMapRectOnMap, C_Map.GetMapChildrenInfo, C_Map.GetMapLinksForMap,
---     C_EncounterJournal.GetDungeonEntrancesForMap, C_AreaPoiInfo.GetAreaPOIForMap, C_AreaPoiInfo.GetAreaPOIInfo,
---     C_TaxiMap.GetTaxiNodesForMap, C_Map.GetBestMapForUnit, C_Map.GetMapInfoAtPosition,
---     WorldMapFrame, UnitFactionGroup
--- Events: none
--- Hot: no
local _, R = ...
local MapData = {}
R.MapData = MapData

local ZONE = 3 -- Enum.UIMapType.Zone
local atan2 = math.atan2
-- Zones count as neighbours when their rectangles on the parent map overlap or sit within this
-- much of each other, as a share of the parent map.
local TOUCH = 0.005
-- Keeps an edge arrow inside the map instead of half off the canvas.
local MARGIN = 0.025
-- Words in an area POI's name or atlas that mean "a way to another place". Matched against
-- lower case text. Tuned from /refactor mapdump output, not from the client's documentation,
-- which does not say which POIs are transport.
local TRAVEL_WORDS = { "boat", "ship", "zeppelin", "airship", "tram", "portal", "ferry", "harbor", "dock" }

local function position(info)
    local point = type(info) == "table" and info.position
    if type(point) == "table" and type(point.x) == "number" and type(point.y) == "number" then
        return point.x, point.y
    end
    return nil
end

-- Forever answers no entrances at all (no Encounter Journal), so when the client lists none the
-- entrances come from Data/DungeonEntrances.lua, which was made from the client's own tables.
function MapData:Dungeons(mapID)
    local entries = {}
    local list = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
    for _, info in ipairs(type(list) == "table" and list or {}) do
        local x, y = position(info)
        if x then
            entries[#entries + 1] = { x = x, y = y, atlas = info.atlasName,
                title = info.name ~= "" and info.name or R.L.MAP_PIN_DUNGEON, subtitle = info.description }
        end
    end
    local data = R.DungeonEntrances
    if #entries == 0 and type(data) == "table" and data.maps[mapID] then
        for _, door in ipairs(data.maps[mapID]) do
            local many = #door.names > 1
            entries[#entries + 1] = { x = door.x, y = door.y, asset = door.raid and "mapPinRaid" or "mapPinDungeon",
                title = many and R.L.MAP_PIN_DUNGEONS_HERE or door.names[1],
                subtitle = many and table.concat(door.names, "\n") or nil }
        end
    end
    return entries
end

-- Map links are the client's own "this spot leads to another map" points.
function MapData:Links(mapID)
    local entries = {}
    local list = C_Map.GetMapLinksForMap(mapID)
    for _, info in ipairs(type(list) == "table" and list or {}) do
        local x, y = position(info)
        if x then
            entries[#entries + 1] = { x = x, y = y, atlas = info.atlasName, mapID = info.linkedUiMapID,
                title = info.name ~= "" and info.name or R.L.MAP_PIN_LINK }
        end
    end
    return entries
end

local function looksLikeTravel(info)
    -- Raw client answers carry name and atlasName; the entries built from them, title and atlas.
    local name, atlas = info.name or info.title, info.atlasName or info.atlas
    local text = (tostring(name or "") .. " " .. tostring(atlas or "")):lower()
    for _, word in ipairs(TRAVEL_WORDS) do
        if text:find(word, 1, true) then
            return true
        end
    end
    return false
end

-- Pins for the guide's routes, one per town on this map that a route leaves from, placed at
-- that town's flight point. The client lists no boats or zeppelins for a map (Wetlands answered
-- none, 7 Nov 2026), so the routes are data/TravelRoutes.lua and the client supplies the place.
function MapData:Routes(mapID)
    local entries, routes = {}, R.TravelRoutes
    if type(routes) ~= "table" then
        return entries
    end
    local towns = {}
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
        local x, y = position(node)
        local town = tostring(node.name):match("^([^,]+)")
        if x and town and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            towns[#towns + 1] = { name = town:lower(), x = x, y = y }
        end
    end
    local faction = UnitFactionGroup("player")
    local byKey, order = {}, {}
    local function add(from, to, kind, oneWay)
        for _, town in ipairs(towns) do
            if town.name:sub(1, #from.key) == from.key then
                local entry = byKey[from.key]
                if not entry then
                    entry = { x = town.x, y = town.y, title = from.name, lines = {},
                        asset = faction == "Horde" and "mapPinTravelHorde" or "mapPinTravelAlliance" }
                    byKey[from.key] = entry
                    order[#order + 1] = entry
                end
                local label = kind == "zeppelin" and R.L.MAP_ROUTE_ZEPPELIN or R.L.MAP_ROUTE_BOAT
                entry.lines[#entry.lines + 1] = string.format(label, to.name)
                    .. (oneWay and R.L.MAP_ROUTE_ONE_WAY or "")
                return
            end
        end
    end
    for _, route in ipairs(routes) do
        if route.faction == nil or route.faction == faction then
            add(route.a, route.b, route.kind, route.oneWay)
            if not route.oneWay then
                add(route.b, route.a, route.kind)
            end
        end
    end
    for _, entry in ipairs(order) do
        entry.subtitle = table.concat(entry.lines, "\n")
        entry.lines = nil
        entries[#entries + 1] = entry
    end
    return entries
end

function MapData:Travel(mapID)
    local entries = self:Routes(mapID)
    local ids = C_AreaPoiInfo.GetAreaPOIForMap(mapID)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
        local x, y = position(info)
        if x and looksLikeTravel(info) then
            entries[#entries + 1] = { x = x, y = y, atlas = info.atlasName, mapID = info.linkedUiMapID,
                title = info.name ~= "" and info.name or R.L.MAP_PIN_TRAVEL, subtitle = info.description }
        end
    end
    for _, entry in ipairs(self:Links(mapID)) do
        if looksLikeTravel(entry) then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

-- Where the ray from the middle of a rectangle towards a point leaves the rectangle.
local function leavePoint(left, right, top, bottom, toX, toY)
    local cx, cy = (left + right) / 2, (top + bottom) / 2
    local dx, dy = toX - cx, toY - cy
    if dx == 0 and dy == 0 then
        return nil
    end
    local halfW, halfH = (right - left) / 2, (bottom - top) / 2
    local scale = math.min(dx ~= 0 and halfW / math.abs(dx) or math.huge, dy ~= 0 and halfH / math.abs(dy) or math.huge)
    return cx + dx * scale, cy + dy * scale, dx, dy
end

local GRID, MIN_BORDER = 48, 3
-- Where a zone meets each neighbour, found once per map and kept: the map's shapes never
-- change, so nothing invalidates it. false means the client could not say.
local borderCache = {}

-- The continent map answers "which zone is here" for any point (it is what draws the highlight
-- under the cursor), so the real border between two zones can be found by asking over a grid
-- laid across this zone's rectangle and one cell beyond it. Each neighbour's exit is the border
-- cell nearest the middle of the border, with the arrow turned along the way out.
local function findBorders(mapID, parent, left, right, top, bottom)
    local ids = {}
    local cw, ch = (right - left) / GRID, (bottom - top) / GRID
    local inside = false
    for iy = 0, GRID + 1 do
        local row = {}
        ids[iy] = row
        for ix = 0, GRID + 1 do
            local px, py = left + (ix - 0.5) * cw, top + (iy - 0.5) * ch
            local found = false
            if px >= 0 and px <= 1 and py >= 0 and py <= 1 then
                local info = C_Map.GetMapInfoAtPosition(parent, px, py)
                found = type(info) == "table" and info.mapID or false
            end
            row[ix] = found
            if found == mapID and ix >= 1 and ix <= GRID and iy >= 1 and iy <= GRID then
                inside = true
            end
        end
    end
    if not inside then
        return false
    end
    local STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local byMap = {}
    for iy = 1, GRID do
        for ix = 1, GRID do
            if ids[iy][ix] == mapID then
                for _, step in ipairs(STEPS) do
                    local other = ids[iy + step[2]][ix + step[1]]
                    if other and other ~= mapID and other ~= parent then
                        local border = byMap[other]
                        if not border then
                            border = { cells = {}, dx = 0, dy = 0, sx = 0, sy = 0 }
                            byMap[other] = border
                        end
                        border.cells[#border.cells + 1] = { ix, iy }
                        border.dx, border.dy = border.dx + step[1], border.dy + step[2]
                        border.sx, border.sy = border.sx + ix, border.sy + iy
                    end
                end
            end
        end
    end
    local result = {}
    for other, border in pairs(byMap) do
        local count = #border.cells
        if count >= MIN_BORDER then
            local mx, my = border.sx / count, border.sy / count
            local best, bestDistance = border.cells[1], math.huge
            for _, cell in ipairs(border.cells) do
                local distance = (cell[1] - mx) ^ 2 + (cell[2] - my) ^ 2
                if distance < bestDistance then
                    best, bestDistance = cell, distance
                end
            end
            result[#result + 1] = { mapID = other, x = (best[1] - 0.5) / GRID, y = (best[2] - 0.5) / GRID,
                rotation = atan2(-border.dx, -border.dy) }
        end
    end
    table.sort(result, function(a, b) return a.mapID < b.mapID end)
    return result
end

local function contains(outer, inner)
    return inner[1] >= outer[1] and inner[2] <= outer[2] and inner[3] >= outer[3] and inner[4] <= outer[4]
end

-- The same exits from the rectangles alone, for a client whose map answers nothing: the arrow
-- sits on the edge facing the neighbour, which is only roughly where the way out is.
function MapData:RectExits(mapID, parent, left, right, top, bottom)
    local entries = {}
    local siblings, rects = {}, {}
    for _, sibling in ipairs(C_Map.GetMapChildrenInfo(parent, ZONE) or {}) do
        local sl, sr, st, sb = C_Map.GetMapRectOnMap(sibling.mapID, parent)
        if sibling.mapID ~= mapID and sl then
            siblings[#siblings + 1] = sibling
            rects[sibling.mapID] = { sl, sr, st, sb }
        end
    end
    for _, sibling in ipairs(siblings) do
        local sl, sr, st, sb = unpack(rects[sibling.mapID])
        -- A city is a zone of its own to the client but sits inside the zone around it, so it
        -- is no way out: skip a neighbour that lies inside this zone or whose middle lies
        -- inside a larger neighbour.
        local nested = contains({ left, right, top, bottom }, rects[sibling.mapID])
        for _, other in ipairs(siblings) do
            local o = rects[other.mapID]
            if other ~= sibling and (o[2] - o[1]) * (o[4] - o[3]) > (sr - sl) * (sb - st)
                and (sl + sr) / 2 >= o[1] and (sl + sr) / 2 <= o[2] and (st + sb) / 2 >= o[3]
                and (st + sb) / 2 <= o[4] then
                nested = true
            end
        end
        if not nested and sl <= right + TOUCH and sr >= left - TOUCH and st <= bottom + TOUCH and sb >= top - TOUCH then
            local px, py, dx, dy = leavePoint(left, right, top, bottom, (sl + sr) / 2, (st + sb) / 2)
            if px then
                local x = math.min(1 - MARGIN, math.max(MARGIN, (px - left) / (right - left)))
                local y = math.min(1 - MARGIN, math.max(MARGIN, (py - top) / (bottom - top)))
                entries[#entries + 1] = { x = x, y = y, rotation = atan2(-dx, -dy), mapID = sibling.mapID,
                    title = string.format(R.L.MAP_PIN_EXIT_TO, sibling.name) }
            end
        end
    end
    return entries
end

-- Arrows the player has moved. Keyed by the map the arrow is on and the map it leads to.
-- then the ones placed by hand and shipped in Data/ExitDefaults.lua.
local function overrideFor(from, to)
    local all = R.Settings and R.Settings:GetOption("mapExitOverrides")
    local moved = type(all) == "table" and all[from] and all[from][to]
    if moved then
        return moved
    end
    local shipped = R.ExitDefaults
    return type(shipped) == "table" and shipped[from] and shipped[from][to] or nil
end

-- Moves one exit arrow, or puts it back where it was worked out when x is nil.
function MapData:SetExit(from, to, x, y)
    local all = {}
    for fromID, targets in pairs(R.Settings:GetOption("mapExitOverrides") or {}) do
        all[fromID] = {}
        for toID, point in pairs(targets) do
            all[fromID][toID] = { x = point.x, y = point.y }
        end
    end
    all[from] = all[from] or {}
    all[from][to] = x and { x = x, y = y } or nil
    if next(all[from]) == nil then
        all[from] = nil
    end
    return R.Settings:SetOption("mapExitOverrides", all)
end

function MapData:Exits(mapID)
    local entries = {}
    local info = C_Map.GetMapInfo(mapID)
    if type(info) ~= "table" or info.mapType ~= ZONE or not info.parentMapID or info.parentMapID == 0 then
        return entries
    end
    local parent = info.parentMapID
    local left, right, top, bottom = C_Map.GetMapRectOnMap(mapID, parent)
    if not left or right <= left or bottom <= top then
        return entries
    end
    if borderCache[mapID] == nil then
        borderCache[mapID] = findBorders(mapID, parent, left, right, top, bottom)
    end
    local borders = borderCache[mapID]
    if borders then
        for _, border in ipairs(borders) do
            local other = C_Map.GetMapInfo(border.mapID)
            if other then
                -- A neighbour that lies wholly inside this zone is a city to walk into, not a
                -- zone to walk out to.
                local sl, sr, st, sb = C_Map.GetMapRectOnMap(border.mapID, parent)
                local within = sl and contains({ left, right, top, bottom }, { sl, sr, st, sb })
                entries[#entries + 1] = { x = border.x, y = border.y, rotation = border.rotation,
                    mapID = border.mapID,
                    title = string.format(within and R.L.MAP_PIN_ENTER_TO or R.L.MAP_PIN_EXIT_TO, other.name) }
            end
        end
    else
        entries = self:RectExits(mapID, parent, left, right, top, bottom)
    end
    for _, entry in ipairs(entries) do
        entry.exit = { from = mapID, to = entry.mapID }
        local moved = overrideFor(mapID, entry.mapID)
        if moved then
            entry.x, entry.y = moved.x, moved.y
        end
    end
    for _, entry in ipairs(self:Links(mapID)) do
        if not looksLikeTravel(entry) then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

local MAX_DUMP = 12

local function dumpList(lines, label, list, describe)
    lines[#lines + 1] = string.format(R.L.MAP_DUMP_SECTION, label, #list)
    for index = 1, math.min(#list, MAX_DUMP) do
        lines[#lines + 1] = "    " .. describe(list[index])
    end
    if #list > MAX_DUMP then
        lines[#lines + 1] = "    " .. string.format(R.L.MAP_DUMP_MORE, #list - MAX_DUMP)
    end
end

local function at(point)
    local x, y = position({ position = point })
    return x and string.format("%.2f,%.2f", x, y) or "?"
end

-- What the client answers for one map, so the filters above can be tuned against Forever
-- rather than against what the Retail documentation promises.
function MapData:Dump(mapID)
    local lines = {}
    local info = C_Map.GetMapInfo(mapID) or {}
    lines[1] = string.format(R.L.MAP_DUMP_HEADER, tostring(mapID), tostring(info.name), tostring(info.mapType),
        tostring(info.parentMapID))
    dumpList(lines, "dungeon entrances", C_EncounterJournal.GetDungeonEntrancesForMap(mapID) or {}, function(entry)
        return string.format("%s [%s] at %s", tostring(entry.name), tostring(entry.atlasName), at(entry.position))
    end)
    dumpList(lines, "map links", C_Map.GetMapLinksForMap(mapID) or {}, function(entry)
        return string.format("%s [%s] to map %s at %s", tostring(entry.name), tostring(entry.atlasName),
            tostring(entry.linkedUiMapID), at(entry.position))
    end)
    local pois = {}
    for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
        pois[#pois + 1] = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id) or { name = "?" }
    end
    dumpList(lines, "area POIs", pois, function(entry)
        return string.format("%s [%s] link %s%s", tostring(entry.name), tostring(entry.atlasName),
            tostring(entry.linkedUiMapID), looksLikeTravel(entry) and " (travel)" or "")
    end)
    dumpList(lines, "taxi nodes", C_TaxiMap.GetTaxiNodesForMap(mapID) or {}, function(entry)
        return string.format("%s [%s] at %s", tostring(entry.name), tostring(entry.atlasName), at(entry.position))
    end)
    dumpList(lines, R.L.MAP_DUMP_ROUTES, self:Routes(mapID), function(entry)
        return string.format("%s at %.2f,%.2f: %s", tostring(entry.title), entry.x, entry.y,
            tostring(entry.subtitle):gsub("\n", "; "))
    end)
    dumpList(lines, "exits", self:Exits(mapID), function(entry)
        return string.format("%s at %.2f,%.2f", tostring(entry.title), entry.x, entry.y)
    end)
    return lines
end

-- The map the player is looking at, or the one they are standing in when the map is closed.
function MapData:DumpOpenMap()
    local mapID = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or C_Map.GetBestMapForUnit("player")
    return mapID and self:Dump(mapID) or nil
end
