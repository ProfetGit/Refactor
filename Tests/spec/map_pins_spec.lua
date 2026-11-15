local Runtime = require("Tests.mock.runtime")

local function mapEnv()
    local env = Runtime.new()
    for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Commands.enUS.lua",
        "Locales/Features.enUS.lua" }) do
        env:Load(path)
    end
    env.R.Print = function() end
    env.R.UI = env.R.UI or {}
    env.rects = {}
    env.maps = {}
    env.dungeons, env.links, env.pois, env.poiInfo = {}, {}, {}, {}
    env.C_Map = {
        GetMapInfo = function(id) return env.maps[id] end,
        GetMapRectOnMap = function(id)
            local rect = env.rects[id]
            if not rect then return nil end
            return rect[1], rect[2], rect[3], rect[4]
        end,
        GetMapChildrenInfo = function(parent)
            local list = {}
            for _, info in pairs(env.maps) do
                if info.parentMapID == parent then list[#list + 1] = info end
            end
            table.sort(list, function(a, b) return a.mapID < b.mapID end)
            return list
        end,
        GetMapLinksForMap = function() return env.links end,
        GetMapInfoAtPosition = function(_, x, y)
            local id = env.hit and env.hit(x, y)
            return id and { mapID = id } or nil
        end,
        GetBestMapForUnit = function() return 10 end,
    }
    env.C_EncounterJournal = { GetDungeonEntrancesForMap = function() return env.dungeons end }
    env.C_AreaPoiInfo = {
        GetAreaPOIForMap = function() return env.pois end,
        GetAreaPOIInfo = function(_, id) return env.poiInfo[id] end,
    }
    env.taxi, env.faction = {}, "Alliance"
    env.C_TaxiMap = { GetTaxiNodesForMap = function() return env.taxi end }
    env.UnitFactionGroup = function() return env.faction end
    env.C_Texture = { GetAtlasInfo = function() return {} end }
    env.GameTooltip = {}
    env.shift, env.ctrl = false, false
    env.IsShiftKeyDown = function() return env.shift end
    env.IsControlKeyDown = function() return env.ctrl end
    env.CreateFrame = function() return {} end
    env.hooksecurefunc = function() end
    env:Load("Core/MapData.lua")
    env:Load("Data/TravelRoutes.lua")
    return env
end

local function zone(env, id, name, parent, rect)
    env.maps[id] = { mapID = id, name = name, mapType = 3, parentMapID = parent }
    env.rects[id] = rect
end

describe("map data", function()
    it("places an exit arrow on the edge facing a neighbouring zone", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        zone(env, 11, "East", 1, { 0.4, 0.6, 0.2, 0.4 })
        zone(env, 12, "Far", 1, { 0.8, 0.9, 0.8, 0.9 })
        local exits = env.R.MapData:Exits(10)
        assert.equal(1, #exits)
        local exit = exits[1]
        assert.equal(11, exit.mapID)
        assert.equal("Exit to East", exit.title)
        assert.is_true(exit.x > 0.95 and exit.x <= 0.975)
        assert.is_true(math.abs(exit.y - 0.5) < 0.001)
        -- Up is zero, so an arrow that points right is a quarter turn clockwise.
        assert.is_true(math.abs(exit.rotation + math.pi / 2) < 0.001)
    end)

    it("points north, south and west the right way and keeps arrows inside the map", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.4, 0.6, 0.4, 0.6 })
        zone(env, 11, "North", 1, { 0.4, 0.6, 0.2, 0.4 })
        zone(env, 12, "South", 1, { 0.4, 0.6, 0.6, 0.8 })
        zone(env, 13, "West", 1, { 0.2, 0.4, 0.4, 0.6 })
        local byMap = {}
        for _, exit in ipairs(env.R.MapData:Exits(10)) do byMap[exit.mapID] = exit end
        assert.is_true(math.abs(byMap[11].rotation) < 0.001)
        assert.is_true(math.abs(math.abs(byMap[12].rotation) - math.pi) < 0.001)
        assert.is_true(math.abs(byMap[13].rotation - math.pi / 2) < 0.001)
        for _, exit in pairs(byMap) do
            assert.is_true(exit.x >= 0.025 and exit.x <= 0.975 and exit.y >= 0.025 and exit.y <= 0.975)
        end
    end)

    it("draws no exits on a continent, an orphan zone or a map with no rectangle", function()
        local env = mapEnv()
        env.maps[1] = { mapID = 1, name = "World", mapType = 2, parentMapID = 0 }
        zone(env, 10, "Home", 0, { 0.2, 0.4, 0.2, 0.4 })
        zone(env, 11, "Lost", 1, nil)
        assert.same({}, env.R.MapData:Exits(1))
        assert.same({}, env.R.MapData:Exits(10))
        assert.same({}, env.R.MapData:Exits(11))
        assert.same({}, env.R.MapData:Exits(999))
    end)

    it("adds the client's map links to the exits, minus the ones that are travel", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        env.links = {
            { name = "Cave", atlasName = "poi-cave", linkedUiMapID = 50, position = { x = 0.3, y = 0.6 } },
            { name = "Boat to Auberdine", atlasName = "poi-ship", linkedUiMapID = 60, position = { x = 0.1, y = 0.9 } },
            { name = "Broken", position = nil },
        }
        local exits = env.R.MapData:Exits(10)
        assert.equal(1, #exits)
        assert.equal("Cave", exits[1].title)
        assert.equal(50, exits[1].mapID)
        local travel = env.R.MapData:Travel(10)
        assert.equal(1, #travel)
        assert.equal("Boat to Auberdine", travel[1].title)
    end)

    -- A client map that answers which zone lies at a point: the smallest listed rectangle wins.
    local function hitFrom(env, parent)
        env.hit = function(x, y)
            local best, bestArea
            for id, rect in pairs(env.rects) do
                if x >= rect[1] and x <= rect[2] and y >= rect[3] and y <= rect[4] then
                    local area = (rect[2] - rect[1]) * (rect[4] - rect[3])
                    if not bestArea or area < bestArea then best, bestArea = id, area end
                end
            end
            return best or parent
        end
    end

    it("puts the exit where the zones really meet, not on the edge of the map", function()
        local env = mapEnv()
        -- Home is a wide zone whose art box spills over, but the zone itself ends at the East border.
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        zone(env, 11, "East", 1, { 0.3, 0.6, 0.2, 0.4 })
        env.hit = function(x, y)
            if y < 0.2 or y > 0.4 then return 1 end
            if x >= 0.2 and x < 0.3 then return 10 end
            if x >= 0.3 and x <= 0.6 then return 11 end
            return 1
        end
        local exits = env.R.MapData:Exits(10)
        assert.equal(1, #exits)
        assert.equal("Exit to East", exits[1].title)
        -- Half way across Home's box, not on its right edge.
        assert.is_true(exits[1].x > 0.45 and exits[1].x < 0.6, exits[1].x)
        assert.is_true(exits[1].y > 0.4 and exits[1].y < 0.6, exits[1].y)
        assert.is_true(math.abs(exits[1].rotation + math.pi / 2) < 0.001)
    end)

    it("calls a city inside the zone one to enter, and ignores touches too small to be a border", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        zone(env, 12, "City", 1, { 0.28, 0.32, 0.28, 0.32 })
        zone(env, 13, "Speck", 1, { 0.2, 0.2 + 0.0001, 0.2, 0.2 + 0.0001 })
        hitFrom(env, 1)
        local titles = {}
        for _, exit in ipairs(env.R.MapData:Exits(10)) do titles[#titles + 1] = exit.title end
        assert.same({ "Enter City" }, titles)
    end)

    it("keeps an exit arrow where the player moved it, and puts it back", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        zone(env, 11, "East", 1, { 0.4, 0.6, 0.2, 0.4 })
        -- The real settings need a saved-variables account; a plain table stands in for it here.
        local store = { mapExitOverrides = {} }
        env.R.Settings = {
            GetOption = function(_, key) return store[key] end,
            SetOption = function(_, key, value) store[key] = value return true end,
        }
        local before = env.R.MapData:Exits(10)[1]
        assert.same({ from = 10, to = 11 }, before.exit)
        assert.is_true(env.R.MapData:SetExit(10, 11, 0.3, 0.8))
        local moved = env.R.MapData:Exits(10)[1]
        assert.equal(0.3, moved.x)
        assert.equal(0.8, moved.y)
        assert.equal(before.rotation, moved.rotation)
        assert.is_true(env.R.MapData:SetExit(10, 11, nil))
        assert.same({}, store.mapExitOverrides)
        assert.equal(before.x, env.R.MapData:Exits(10)[1].x)
    end)

    it("uses an exit placed by hand in the shipped data until the player moves it", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        zone(env, 11, "East", 1, { 0.4, 0.6, 0.2, 0.4 })
        env.R.ExitDefaults = { [10] = { [11] = { x = 0.9, y = 0.1 } } }
        local store = { mapExitOverrides = {} }
        env.R.Settings = {
            GetOption = function(_, key) return store[key] end,
            SetOption = function(_, key, value) store[key] = value return true end,
        }
        local shipped = env.R.MapData:Exits(10)[1]
        assert.equal(0.9, shipped.x)
        assert.equal(0.1, shipped.y)
        env.R.MapData:SetExit(10, 11, 0.5, 0.5)
        assert.equal(0.5, env.R.MapData:Exits(10)[1].x)
        env.R.MapData:SetExit(10, 11, nil)
        assert.equal(0.9, env.R.MapData:Exits(10)[1].x)
    end)

    it("falls back to the rectangles when the client's map answers nothing", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        zone(env, 11, "East", 1, { 0.4, 0.6, 0.2, 0.4 })
        env.hit = function() return false end
        assert.equal(1, #env.R.MapData:Exits(10))
    end)

    it("takes dungeon entrances from the client first and from the table when it lists none", function()
        local env = mapEnv()
        env.R.DungeonEntrances = { maps = { [10] = {
            { x = 0.4, y = 0.7, raid = false, names = { "Deadmines" } },
            { x = 0.5, y = 0.6, raid = true, names = { "Blackwing Lair", "Molten Core" } },
        } } }
        local entries = env.R.MapData:Dungeons(10)
        assert.equal(2, #entries)
        assert.equal("Deadmines", entries[1].title)
        assert.equal("mapPinDungeon", entries[1].asset)
        assert.equal("Dungeons and raids", entries[2].title)
        assert.equal("Blackwing Lair\nMolten Core", entries[2].subtitle)
        assert.equal("mapPinRaid", entries[2].asset)
        env.dungeons = { { name = "Client", position = { x = 0.1, y = 0.1 } } }
        entries = env.R.MapData:Dungeons(10)
        assert.equal(1, #entries)
        assert.equal("Client", entries[1].title)
        env.dungeons = {}
        assert.same({}, env.R.MapData:Dungeons(99))
    end)

    it("leaves out a city that sits inside the zone around it", function()
        local env = mapEnv()
        zone(env, 10, "Wetlands", 1, { 0.45, 0.55, 0.50, 0.60 })
        zone(env, 11, "Dun Morogh", 1, { 0.35, 0.47, 0.50, 0.65 })
        zone(env, 12, "Ironforge", 1, { 0.40, 0.43, 0.55, 0.58 })
        zone(env, 13, "Inside", 1, { 0.48, 0.50, 0.52, 0.54 })
        local titles = {}
        for _, exit in ipairs(env.R.MapData:Exits(10)) do titles[#titles + 1] = exit.title end
        assert.same({ "Exit to Dun Morogh" }, titles)
    end)

    it("puts each route at its town's flight point and lists where it goes", function()
        local env = mapEnv()
        env.taxi = {
            { name = "Menethil Harbor, Wetlands", position = { x = 0.10, y = 0.60 } },
            { name = "Southshore, Hillsbrad", position = { x = 0.03, y = 0.52 } },
            { name = "Ironforge, Dun Morogh", position = { x = 0.19, y = 0.97 } },
            { name = "Darkshire, Duskwood", position = { x = 0.21, y = 3.04 } },
            { name = "Orgrimmar, Durotar", position = { x = 0.5, y = 0.5 } },
        }
        local entries = env.R.MapData:Routes(10)
        local byTitle = {}
        for _, entry in ipairs(entries) do byTitle[entry.title] = entry end
        assert.equal(2, #entries)
        assert.equal(0.10, byTitle["Menethil Harbor"].x)
        assert.equal("Boat to Southshore (one way)\nBoat to Theramore", byTitle["Menethil Harbor"].subtitle)
        assert.equal("Boat to Auberdine (one way)", byTitle["Southshore"].subtitle)
        env.faction = "Horde"
        entries = env.R.MapData:Routes(10)
        assert.equal(1, #entries)
        assert.equal("Orgrimmar", entries[1].title)
        assert.equal("Zeppelin to Undercity\nZeppelin to Grom'gol", entries[1].subtitle)
    end)

    it("keeps only travel area POIs and falls back to a generic name", function()
        local env = mapEnv()
        env.pois = { 1, 2, 3 }
        env.poiInfo = {
            [1] = { name = "Zeppelin to Orgrimmar", atlasName = "poi-zeppelin", linkedUiMapID = 85,
                position = { x = 0.5, y = 0.5 } },
            [2] = { name = "Inn", atlasName = "poi-inn", position = { x = 0.2, y = 0.2 } },
            [3] = { name = "", atlasName = "Portal-Blue", position = { x = 0.7, y = 0.7 } },
        }
        local travel = env.R.MapData:Travel(10)
        assert.equal(2, #travel)
        assert.equal("Zeppelin to Orgrimmar", travel[1].title)
        assert.equal(85, travel[1].mapID)
        assert.equal("Travel point", travel[2].title)
    end)

    it("lists dungeon entrances and skips ones with no position", function()
        local env = mapEnv()
        env.dungeons = {
            { name = "Deadmines", description = "Level 15", atlasName = "dungeon", position = { x = 0.4, y = 0.3 } },
            { name = "No spot" },
        }
        local entries = env.R.MapData:Dungeons(10)
        assert.equal(1, #entries)
        assert.equal("Deadmines", entries[1].title)
        assert.equal("Level 15", entries[1].subtitle)
    end)

    it("dumps what the client answers, capped per section", function()
        local env = mapEnv()
        zone(env, 10, "Home", 1, { 0.2, 0.4, 0.2, 0.4 })
        for index = 1, 15 do
            env.dungeons[index] = { name = "D" .. index, atlasName = "a", position = { x = 0.1, y = 0.1 } }
        end
        local lines = env.R.MapData:Dump(10)
        local text = table.concat(lines, "\n")
        assert.matches("Map 10 (Home)", text, 1, true)
        assert.matches("dungeon entrances: 15", text, 1, true)
        assert.matches("... and 3 more", text, 1, true)
        assert.matches("exits: 0", text, 1, true)
    end)
end)

describe("map pin modules", function()
    local MODULES = {
        { id = "interface.mapDungeons", path = "Modules/Interface/MapDungeons.lua", kind = "dungeons" },
        { id = "interface.mapTravel", path = "Modules/Interface/MapTravel.lua", kind = "travel" },
    }

    local function pinEnv()
        local env = mapEnv()
        env.attached, env.detached, env.nativePins = {}, {}, {}
        env.WorldMapFrame = {
            EnumeratePinsByTemplate = function(_, template)
                local list = template == "DungeonEntrancePinTemplate" and env.nativePins or {}
                local index = 0
                return function()
                    index = index + 1
                    return list[index]
                end
            end,
        }
        env.R.UI.MapPins = {
            Attach = function(_, module, kind, collect) env.attached[kind] = { module = module, collect = collect } end,
            Detach = function(_, kind) env.detached[kind] = true end,
        }
        return env
    end

    for _, spec in ipairs(MODULES) do
        it(spec.id .. " attaches on enable, detaches on disable and leaves no residue", function()
            local env = pinEnv()
            env:Load(spec.path)
            local module = env.R.moduleByID[spec.id]
            assert.is_true(env.R.Registry:Enable(spec.id), tostring(module.failure))
            assert.equal(module, env.attached[spec.kind].module)
            env.R.Registry:Disable(module)
            assert.is_true(env.detached[spec.kind])
            for _, entries in pairs(env.R.Broker.events) do
                for _, entry in ipairs(entries) do assert.is_not.equal(module, entry.owner) end
            end
            assert.is_true(env.R.Registry:Enable(spec.id))
            env.R.Registry:Disable(module)
        end)

        it(spec.id .. " is off by default", function()
            local env = pinEnv()
            env:Load(spec.path)
            assert.is_false(env.R.moduleByID[spec.id].defaultEnabled)
        end)
    end

    it("dungeon pins stand down while the map's own entrance pins are showing", function()
        local env = pinEnv()
        env:Load("Modules/Interface/MapDungeons.lua")
        local module = env.R.moduleByID["interface.mapDungeons"]
        env.dungeons = { { name = "Deadmines", position = { x = 0.4, y = 0.3 } } }
        assert.equal(1, #module:Collect(10))
        env.nativePins = { {} }
        assert.equal(0, #module:Collect(10))
    end)

    it("is unavailable, not failed, where the client lacks the map data calls", function()
        local env = pinEnv()
        env.C_AreaPoiInfo = nil
        env:Load("Modules/Interface/MapTravel.lua")
        assert.is_false(env.R.Registry:Enable("interface.mapTravel"))
        assert.equal("unavailable", env.R.moduleByID["interface.mapTravel"].state)
    end)
end)

describe("map pin layer", function()
    local function layerEnv()
        local env = mapEnv()
        env.created = 0
        env.R.Pools = nil
        env:Load("Core/Pools.lua")
        env.applied = {}
        env.LibStub = function()
            return { ApplyAsset = function(_, _, key) env.applied[#env.applied + 1] = key end }
        end
        local function frame()
            local f = { shown = false, scripts = {} }
            function f:SetAllPoints() end
            function f:SetFrameLevel(level) self.level = level end
            function f:GetFrameLevel() return 1 end
            function f:SetSize() end
            function f:GetSize() return 1000, 500 end
            function f:SetScale(scale) self.scale = scale end
            function f:ClearAllPoints() self.point = nil end
            function f:SetPoint(...) self.point = { ... } end
            function f:SetScript(name, fn) self.scripts[name] = fn end
            function f:SetMovable() end
            function f:RegisterForDrag() end
            function f:RegisterForClicks() end
            function f:StartMoving() self.moving = true end
            function f:StopMovingOrSizing() self.moving = false end
            function f:GetEffectiveScale() return self.effective or 1 end
            function f:GetLeft() return 100 end
            function f:GetTop() return 900 end
            function f:GetCenter() return unpack(self.center or { 600, 400 }) end
            function f:GetTop() return 900 end
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:CreateTexture()
                return { SetAllPoints = function() end, SetRotation = function(texture, r) texture.rotation = r end,
                    SetAtlas = function(texture, a) texture.atlas = a end }
            end
            return f
        end
        env.CreateFrame = function()
            env.created = env.created + 1
            return frame()
        end
        local canvas = frame()
        env.scale = 2
        env.WorldMapFrame = {
            GetCanvas = function() return canvas end, GetMapID = function() return 10 end,
            GetCanvasScale = function() return env.scale end, IsShown = function() return true end,
            SetMapID = function(_, id) env.opened = id end,
        }
        env.R.UI.Dummy = true
        env:Load("UI/MapPins.lua")
        return env
    end

    it("makes its frames when a layer is created, never while drawing, and drops entries past the cap", function()
        local env = layerEnv()
        local pins = env.R.UI.MapPins
        pins:Layer("exits")
        local made = env.created
        assert.is_true(made > 1)
        local entries = {}
        for index = 1, 40 do entries[index] = { x = 0.5, y = 0.5, title = "T" .. index } end
        pins:Set("exits", entries)
        pins:Set("exits", { { x = 0.1, y = 0.2, rotation = 1, title = "A" } })
        assert.equal(made, env.created)
        assert.equal("mapExitArrow", env.applied[#env.applied])
    end)

    it("keeps its layer above Blizzard's map pins, whose frame levels start at 2000", function()
        local env = layerEnv()
        local layer = env.R.UI.MapPins:Layer("dungeons")
        assert.is_true(layer.frame.level > 2000 and layer.frame.level <= 9000)
    end)

    it("sizes pins against the zoom and clears them", function()
        local env = layerEnv()
        local pins = env.R.UI.MapPins
        pins:Set("travel", { { x = 0.25, y = 0.5, title = "Boat" } })
        local layer = pins:Layer("travel")
        local pin = layer.shown[1]
        assert.equal(0.5, pin.scale)
        assert.equal(500, pin.point[4])
        assert.equal(-500, pin.point[5])
        env.scale = 4
        pins:Rescale()
        assert.equal(0.25, pin.scale)
        pins:Clear("travel")
        assert.is_false(layer.frame.shown)
        assert.is_nil(layer.shown)
    end)

    it("moves an exit arrow with shift and a drag, saves it, and puts it back with ctrl right click", function()
        local env = layerEnv()
        local saved = {}
        env.R.MapData.SetExit = function(_, from, to, x, y) saved[#saved + 1] = { from, to, x, y } end
        env.GameTooltip = { Hide = function() end }
        local pins = env.R.UI.MapPins
        pins:Set("exits", { { x = 0.5, y = 0.5, rotation = 0, title = "Exit", mapID = 77,
            exit = { from = 10, to = 77 } } })
        local pin = pins:Layer("exits").shown[1]
        -- Without shift a drag does nothing.
        pin.scripts.OnDragStart(pin)
        assert.is_nil(pin.moving)
        env.shift = true
        pin.scripts.OnDragStart(pin)
        assert.is_true(pin.moving)
        -- The canvas is 1000 by 500 at scale 1 and starts at 100,900; the pin was dropped at 600,400.
        pin.center = { 350, 650 }
        pin.scripts.OnDragStop(pin)
        assert.is_false(pin.moving)
        assert.same({ { 10, 77, 0.25, 0.5 } }, saved)
        -- The click that ends a drag does not open the map.
        pin.scripts.OnClick(pin, "LeftButton")
        assert.is_nil(env.opened)
        pin.scripts.OnClick(pin, "LeftButton")
        assert.equal(77, env.opened)
        -- Ctrl and a right click puts it back; a plain right click does not.
        pin.scripts.OnClick(pin, "RightButton")
        assert.equal(1, #saved)
        env.ctrl = true
        pin.scripts.OnClick(pin, "RightButton")
        assert.same({ 10, 77, nil, nil }, saved[2])
    end)

    it("opens the linked map on click", function()
        local env = layerEnv()
        local pins = env.R.UI.MapPins
        pins:Set("travel", { { x = 0.1, y = 0.1, title = "Boat", mapID = 77 } })
        local pin = pins:Layer("travel").shown[1]
        pin.scripts.OnClick(pin)
        assert.equal(77, env.opened)
    end)
end)
