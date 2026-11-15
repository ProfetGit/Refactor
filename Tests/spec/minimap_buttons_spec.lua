local Runtime = require("Tests.mock.runtime")
local Widgets = require("Tests.mock.widgets")

local ID = "interface.minimapButtons"
local BLOCKED = { "ClearAllPoints", "SetPoint", "SetAllPoints", "SetParent" }

-- Another addon's minimap button. Its methods live on a shared metatable, as a real widget's
-- do, so a spec can tell whether one was replaced on the instance and whether it came back.
local Button = {}
Button.__index = Button
function Button:GetName() return self.name end
function Button:IsProtected() return self.protected == true end
function Button:GetParent() return self.parent end
function Button:SetParent(parent) self.parent = parent end
function Button:GetNumPoints() return #self.points end
function Button:GetPoint(index)
    local point = self.points[index]
    return point[1], point[2], point[3], point[4], point[5]
end
function Button:ClearAllPoints() self.points = {} end
function Button:SetPoint(point, relativeTo, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
end
function Button:SetAllPoints(relativeTo) self.points = { { "TOPLEFT", relativeTo }, { "BOTTOMRIGHT", relativeTo } } end
-- A fixed strata or level ignores SetFrameStrata and SetFrameLevel, the client's way: ATT
-- unfixes its button before it changes the strata, and Blizzard's talent frame its level.
function Button:GetFrameStrata() return self.strata end
function Button:SetFrameStrata(strata) if not self.fixedStrata then self.strata = strata end end
function Button:GetFrameLevel() return self.level end
function Button:SetFrameLevel(level) if not self.fixedLevel then self.level = level end end
function Button:HasFixedFrameStrata() return self.fixedStrata == true end
function Button:HasFixedFrameLevel() return self.fixedLevel == true end
function Button:SetFixedFrameStrata(fixed) self.fixedStrata = fixed end
function Button:SetFixedFrameLevel(fixed) self.fixedLevel = fixed end
function Button:GetScript(name) return self.scripts[name] end
function Button:SetScript(name, callback) self.scripts[name] = callback end
function Button:HookScript(name, callback)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], callback)
end
function Button:Run(name)
    for _, callback in ipairs(self.hooks[name] or {}) do callback(self) end
end
function Button:IsShown() return self.shown end
function Button:Show() self.shown = true self:Run("OnShow") end
function Button:Hide() self.shown = false self:Run("OnHide") end
function Button:GetWidth() return 31 end
function Button:GetHeight() return 31 end
function Button:GetScale() return 1 end

local function world()
    local env = Runtime.new()
    Widgets.install(env)
    for _, path in ipairs({ "Locales/Modules.enUS.lua", "Locales/UI.enUS.lua", "Locales/Features.enUS.lua",
        "Locales/Panels.enUS.lua" }) do
        env:Load(path)
    end
    env.R.Print = function() end
    env.R.UI = env.R.UI or {}
    env.loaded, env.secure, env.children = {}, {}, {}
    env.C_AddOns = { IsAddOnLoaded = function(name) return env.loaded[name] == true end }
    env.issecurevariable = function(_, name) return env.secure[name] == true end
    env.GameTooltip = { Hide = function() end }
    env.Minimap = env.CreateFrame("Frame", "Minimap", env.UIParent)
    env.Minimap.GetChildren = function() return unpack(env.children) end
    for _, path in ipairs({ "Integrations/Questie.lua", "Integrations/Plater.lua", "Integrations/Neighbours.lua",
        "UI/Minimap.lua", "UI/MinimapButtons.lua", "Modules/Interface/MinimapButtons.lua" }) do
        env:Load(path)
    end
    local library = env.LibStub:NewLibrary("LibDBIcon-1.0", 99)
    library.objects, library.listeners = {}, {}
    function library:GetButtonList()
        local names = {}
        for name in pairs(self.objects) do names[#names + 1] = name end
        table.sort(names)
        return names
    end
    function library:GetMinimapButton(name) return self.objects[name] end
    function library.RegisterCallback(owner, event, method) library.listeners[owner] = { event, method } end
    function library.UnregisterCallback(owner) library.listeners[owner] = nil end
    function library:SetButtonToPosition(button, position)
        button:SetPoint("CENTER", env.Minimap, "CENTER", position, 0)
    end
    env.library = library
    return env
end

local function drag() end
local function drop() end

local function button(env, name, options)
    options = options or {}
    local frame = setmetatable({
        name = name, parent = env.Minimap, points = { { "CENTER", env.Minimap, "CENTER", 52, -40 } },
        strata = "MEDIUM", level = 8, scripts = { OnDragStart = drag, OnDragStop = drop }, hooks = {},
        shown = options.hidden ~= true, protected = options.protected,
    }, Button)
    if options.library then
        frame.db = { minimapPos = options.library }
    else
        env.children[#env.children + 1] = frame
    end
    return frame
end

-- A LibDBIcon button, made the way the library makes one: MEDIUM at level 8, both fixed, and
-- announced to whoever listens.
local function libraryButton(env, name, angle)
    local frame = button(env, "LibDBIcon10_" .. name, { library = angle or 225 })
    frame.fixedStrata, frame.fixedLevel = true, true
    env.library.objects[name] = frame
    for owner, listener in pairs(env.library.listeners) do
        owner[listener[2]](owner, listener[1], frame, name)
    end
    return frame
end

local function enable(env)
    assert.is_true(env.R.Registry:Enable(ID), tostring(env.R.moduleByID[ID].failure))
    return env.R.moduleByID[ID]
end

local function gathered(module)
    local names = {}
    for _, record in ipairs(module.order) do names[#names + 1] = record.name end
    return names
end

describe("minimap button collector", function()
    it("gathers addon buttons and leaves Blizzard's, pins and protected frames on the minimap", function()
        local env = world()
        libraryButton(env, "BugSack")
        button(env, "LueurMinimapButton")
        button(env, "AllTheThings-Minimap")
        button(env, "TomCats-MinimapButton2026")
        local blizzard = button(env, "ExpansionLandingPageMinimapButton")
        env.secure.ExpansionLandingPageMinimapButton = true
        local pin = button(env, "HandyNotesPin12")
        local gatherMate = button(env, "GatherMateMinimapIcon")
        local secured = button(env, "SecureMinimapButton", { protected = true })
        local unnamed = button(env, nil)
        local module = enable(env)
        assert.same({ "AllTheThings-Minimap", "LibDBIcon10_BugSack", "LueurMinimapButton",
            "TomCats-MinimapButton2026" }, gathered(module))
        for _, frame in ipairs({ blizzard, pin, gatherMate, secured, unnamed }) do
            assert.equal(env.Minimap, frame.parent)
        end
    end)

    it("holds a gathered button in the drawer, then hands it back exactly as it was", function()
        local env = world()
        local frame = button(env, "LueurMinimapButton")
        local module = enable(env)
        local content = module.collector.content
        assert.equal(content, frame.parent)
        assert.equal("HIGH", frame.strata)
        assert.is_nil(frame.scripts.OnDragStart)
        assert.is_nil(frame.scripts.OnDragStop)
        -- The addon putting its button back on the rim changes nothing while it is gathered.
        local before = frame.points[1]
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", env.Minimap, "CENTER", 80, 0)
        frame:SetParent(env.Minimap)
        assert.equal(before, frame.points[1])
        assert.equal(content, frame.parent)
        env.R.Registry:Disable(module)
        assert.equal(env.Minimap, frame.parent)
        assert.same({ { "CENTER", env.Minimap, "CENTER", 52, -40 } }, frame.points)
        assert.equal("MEDIUM", frame.strata)
        assert.equal(8, frame.level)
        assert.equal(drag, frame.scripts.OnDragStart)
        assert.equal(drop, frame.scripts.OnDragStop)
        for _, method in ipairs(BLOCKED) do
            assert.is_nil(rawget(frame, method), method)
        end
    end)

    -- Seen in game 11 Nov 2026: BugSack's, Spoken's and Lueur's buttons stayed MEDIUM under the
    -- HIGH drawer and showed dimmed through its panel.
    it("lifts a button its addon fixed to a strata above the drawer, and fixes it again", function()
        local env = world()
        local frame = libraryButton(env, "BugSack")
        local module = enable(env)
        assert.equal("HIGH", frame.strata)
        assert.equal(module.collector.content:GetFrameLevel() + 2, frame.level)
        assert.is_true(frame.fixedStrata)
        assert.is_true(frame.fixedLevel)
        env.R.Registry:Disable(module)
        assert.equal("MEDIUM", frame.strata)
        assert.equal(8, frame.level)
        assert.is_true(frame.fixedStrata)
        assert.is_true(frame.fixedLevel)
    end)

    it("puts a LibDBIcon button back at the angle LibDBIcon has for it", function()
        local env = world()
        local frame = libraryButton(env, "BugSack", 190)
        local module = enable(env)
        frame.db.minimapPos = 140
        env.R.Registry:Disable(module)
        assert.equal(env.Minimap, frame.parent)
        assert.same({ { "CENTER", env.Minimap, "CENTER", 140, 0 } }, frame.points)
    end)

    it("leaves no residue across enable, disable, enable", function()
        local env = world()
        local frame = button(env, "LueurMinimapButton")
        local module = enable(env)
        env.R.Registry:Disable(module)
        assert.equal(0, env:ActiveTimers())
        assert.is_nil(next(env.library.listeners))
        for _, entries in pairs(env.R.Broker.events) do
            for _, entry in ipairs(entries) do assert.is_not.equal(module, entry.owner) end
        end
        assert.is_false(module.collector.button:IsShown())
        enable(env)
        assert.same({ "LueurMinimapButton" }, gathered(module))
        assert.equal(module.collector.content, frame.parent)
        assert.is_true(module.collector.button:IsShown())
        -- Hooked once in its life, however often the feature is switched.
        assert.equal(1, #frame.hooks.OnShow)
    end)

    it("picks up a LibDBIcon button made after login, and stops listening once off", function()
        local env = world()
        local module = enable(env)
        local late = libraryButton(env, "Spoken")
        assert.same({ "LibDBIcon10_Spoken" }, gathered(module))
        assert.equal(module.collector.content, late.parent)
        env.R.Registry:Disable(module)
        local later = libraryButton(env, "Questie")
        assert.equal(env.Minimap, later.parent)
    end)

    it("looks again at the login gathers, so a button made a second late is still found", function()
        local env = world()
        local module = enable(env)
        button(env, "QuestieMinimapButton2")
        button(env, "GearRefactorMinimapButton")
        env:Advance(1)
        assert.same({ "GearRefactorMinimapButton" }, gathered(module))
    end)

    it("lays shown buttons out in rows and skips hidden ones", function()
        local env = world()
        local module = enable(env)
        assert.same({ 171, 66 }, { module:GridSize(7, 5, 31) })
        assert.same({ 0, 0 }, { module:GridSize(0, 5, 31) })
        assert.same({ 15.5, 50.5 }, { module:GridCenter(6, 5, 31) })
        env.R.Settings:SetOption("minimapButtonsColumns", 2)
        local a = button(env, "AMinimapButton")
        local b = button(env, "BMinimapButton", { hidden = true })
        local c = button(env, "CMinimapButton")
        local d = button(env, "DMinimapButton")
        module:Gather()
        assert.equal(3, module.collector.count)
        assert.same({ "CENTER", module.collector.content, "TOPLEFT", 15.5, -15.5 }, a.points[1])
        assert.same({ "CENTER", module.collector.content, "TOPLEFT", 50.5, -15.5 }, c.points[1])
        assert.same({ "CENTER", module.collector.content, "TOPLEFT", 15.5, -50.5 }, d.points[1])
        -- The addon showing its button again while the drawer is open puts it back in line.
        module:Open()
        b:Show()
        assert.equal(4, module.collector.count)
        assert.same({ "CENTER", module.collector.content, "TOPLEFT", 50.5, -15.5 }, b.points[1])
        a:Hide()
        assert.equal(3, module.collector.count)
    end)

    it("opens away from the screen edges it is near", function()
        local env = world()
        local corner = env.R.UI.MinimapDrawerCorner
        assert.same({ "TOPRIGHT", "BOTTOMRIGHT", -2, true }, { corner(900, 700, 1000, 800) })
        assert.same({ "BOTTOMLEFT", "TOPLEFT", 2, false }, { corner(100, 100, 1000, 800) })
        assert.same({ "TOPLEFT", "BOTTOMLEFT", -2, false }, { corner(100, 700, 1000, 800) })
        assert.same({ "TOPRIGHT", "BOTTOMRIGHT", -2, true }, { corner(nil, nil, 1000, 800) })
    end)

    it("moves nothing in combat and gathers when it ends", function()
        local env = world()
        local frame = button(env, "LueurMinimapButton")
        env.combat = true
        env.InCombatLockdown = function() return env.combat end
        local module = enable(env)
        assert.same({}, gathered(module))
        assert.equal(env.Minimap, frame.parent)
        env.combat = false
        env:Fire("PLAYER_REGEN_ENABLED")
        assert.same({ "LueurMinimapButton" }, gathered(module))
    end)

    it("stands down while MinimapButtonButton is loaded", function()
        local env = world()
        env.loaded.MinimapButtonButton = true
        local frame = button(env, "LueurMinimapButton")
        local module = env.R.moduleByID[ID]
        assert.is_false(env.R.Registry:Enable(ID))
        assert.equal("unavailable", module.state)
        assert.matches("MinimapButtonButton", module.unavailableReason, 1, true)
        assert.equal(env.Minimap, frame.parent)
        local conflicts = env.R.Integrations:Conflicts()
        assert.equal(1, #conflicts)
        assert.equal(module, conflicts[1].module)
    end)

    it("closes on a click elsewhere, not on one inside the drawer", function()
        local env = world()
        local module = enable(env)
        local collector = module.collector
        module:Toggle()
        assert.is_true(collector:IsOpen())
        collector.drawer.IsMouseOver = function() return true end
        env:Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
        assert.is_true(collector:IsOpen())
        collector.drawer.IsMouseOver = function() return false end
        env:Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
        assert.is_false(collector:IsOpen())
        env.R.Settings:SetOption("minimapButtonsCloseOnClick", false)
        module:Toggle()
        env:Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
        assert.is_true(collector:IsOpen())
        module:Toggle()
        assert.is_false(collector:IsOpen())
    end)

    it("rides the minimap's rim, or sits anywhere once taken off it", function()
        local env = world()
        local module = enable(env)
        local collector = module.collector
        local store = env.R.Settings.character.minimapButtons
        assert.equal(env.Minimap, collector.button:GetParent())
        env.Minimap.GetCenter = function() return 100, 100 end
        env.GetCursorPosition = function() return 100, 200 end
        collector:StartDrag()
        local orbit = collector.button:GetScript("OnUpdate")
        assert.is_function(orbit)
        orbit(collector.button)
        collector:StopDrag()
        assert.is_nil(collector.button:GetScript("OnUpdate"))
        assert.is_true(math.abs(store.angle - 90) < 1e-9)
        env.R.Settings:SetOption("minimapButtonsAttach", false)
        assert.equal(env.UIParent, collector.button:GetParent())
        collector:StartDrag()
        assert.is_nil(collector.button:GetScript("OnUpdate"))
        collector:StopDrag()
        assert.equal("CENTER", store.point)
        assert.equal(0, store.x)
        env.R.Settings:SetOption("minimapButtonsAttach", true)
        assert.equal(env.Minimap, collector.button:GetParent())
        assert.is_true(math.abs(store.angle - 90) < 1e-9)
    end)
end)
