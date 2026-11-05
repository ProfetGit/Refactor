local Runtime = require("Tests.mock.runtime")
local Probe = require("Tools.probe-to-json")
local json = require("dkjson")

local BUILD = "70009"

-- The real Tools/Probe file, run against the mock client with just enough of an API to walk.
local function client(saved)
    local env = Runtime.new()
    env.printed = {}
    env.print = function(text) env.printed[#env.printed + 1] = text end
    -- Every reading costs 7 ms, so the walk spends its frame budget every few globals and can
    -- only finish by coming back through C_Timer.After.
    local clock = 0
    env.debugprofilestop = function()
        clock = clock + 7
        return clock
    end
    env.GetServerTime = function() return 1790337600 end
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "1.60.1", BUILD, "Sep 20 2026", 16001 end
    env.Enum = { ConsoleCommandType = { Cvar = 0, Command = 1 }, ItemClass = { Armor = 4, Weapon = 2 } }
    env.ConsoleGetAllCommands = function()
        return { { command = "autoQuestWatch", commandType = 0 }, { command = "reloadui", commandType = 1 } }
    end
    env.C_Texture = { GetAtlasInfo = function(name) if name ~= "RedButton-Exit" then return { width = 1 } end end }
    env.C_Container = { UseContainerItem = function() end }
    env.C_AddOns = {
        GetNumAddOns = function() return 2 end,
        IsAddOnLoaded = function(index) return index == 1 end,
        GetAddOnInfo = function(index) return index == 1 and "Refactor" or "Disabled" end,
        LoadAddOn = function()
            env.APIDocumentation = { systems = { {
                Functions = {
                    { Name = "UseContainerItem", SecretArguments = "AllowedWhenUntainted" }, { Name = "Plain" },
                },
                Events = { { LiteralName = "BAG_UPDATE" } },
            } } }
            return true
        end,
    }
    env.ChatTypeInfo = { SAY = { r = 1 } }
    env.FooMixin = { OnLoad = function() end }
    env.Huge = {}
    for index = 1, 4001 do env.Huge["key" .. index] = index end
    env.BugSack = { Toggle = function() end }
    env.SlashCmdList.BUGSACK = function() end
    env.issecurevariable = function(owner, key)
        if owner == env and key == "BugSack" then return false, "BugSack" end
        if owner == env.SlashCmdList and key == "BUGSACK" then return false, "BugSack" end
        return true
    end
    env.RefactorProbeDB = saved
    env:Load("Tools/Probe/RefactorProbe.lua")
    env:Fire("PLAYER_LOGIN")
    env:Advance(1)
    return env
end

describe("the Forever API probe", function()
    it("walks the client across frames and saves a finished dump", function()
        local env = client()
        local db = env.RefactorProbeDB
        assert.is_true(db.finished)
        assert.same({}, db.errors)
        assert.equal(BUILD, db.client.build)
        assert.matches("^Refactor Probe: ", env.printed[1])
        assert.matches("RegisterEvent", db.widgets.Frame)
    end)

    it("runs once per client build", function()
        local done = { schema = 1, finished = true, client = { build = BUILD } }
        assert.equal(done, client(done).RefactorProbeDB)
        local old = { schema = 1, finished = true, client = { build = "69913" } }
        assert.are_not.equal(old, client(old).RefactorProbeDB)
    end)

    it("converts to an index of the client's own API", function()
        local index = Probe.convert(client().RefactorProbeDB, "forever")
        assert.equal("forever", index.flavor)
        assert.equal(16001, index.interface)
        assert.equal("2026-09-25", index.probedAt)
        local symbols = index.symbols
        assert.equal("function", symbols["C_Container.UseContainerItem"])
        assert.equal("number", symbols["Enum.ItemClass.Armor"])
        assert.equal("function", symbols.GetServerTime)
        -- Data tables and mixins are named but not indexed field by field.
        assert.equal("table", symbols.ChatTypeInfo)
        assert.is_nil(symbols["ChatTypeInfo.SAY"])
        assert.equal("table", symbols.FooMixin)
        assert.is_nil(symbols["FooMixin.OnLoad"])
        assert.same({ "Huge" }, index.oversizedTables)
        -- Whatever an addon wrote is that addon's, not the client's.
        assert.is_nil(symbols.BugSack)
        assert.is_nil(symbols["BugSack.Toggle"])
        assert.is_nil(symbols["SlashCmdList.BUGSACK"])
        assert.equal(1, index.excludedGlobals)
        assert.same({ BugSack = "BugSack" }, index.addonGlobals)
        assert.same({ "autoQuestWatch" }, index.cvars)
        assert.same({ "reloadui" }, index.commands)
        assert.same({ "BAG_UPDATE" }, index.events)
        assert.same({ "Refactor" }, index.addons)
        assert.equal(1, index.documentation.secret.SecretArguments)
        assert.is_false(index.atlases["RedButton-Exit"])
        assert.is_true(index.atlases["128-RedButton-Left"])
    end)

    it("refuses a dump that did not finish", function()
        local unfinished = { schema = 1, finished = false, errors = { "run: boom" } }
        assert.has_error(function() Probe.convert(unfinished, "forever") end)
    end)

    it("reads the saved variables file the client writes", function()
        local db = Probe.load(table.concat({
            "", "RefactorProbeDB = {", '["schema"] = 1,', '["finished"] = true,', '["probedAt"] = 1790337600,',
            '["client"] = {', '["build"] = "70009",', '["version"] = "1.60.1",', '["interface"] = 16001,', "},",
            '["globals"] = {', '["function"] = "GetTime\\nUnitGUID",', "},",
            '["fields"] = {', '["C_Test"] = "Run\\tfunction\\nHooked\\tfunction\\tSomeAddon",', "},", "}",
        }, "\n"))
        local index = Probe.convert(db, "forever")
        assert.equal("function", index.symbols.UnitGUID)
        assert.equal("function", index.symbols["C_Test.Run"])
        assert.is_nil(index.symbols["C_Test.Hooked"])
    end)

    it("renders sorted, stable JSON that decodes back", function()
        local index = Probe.convert(client().RefactorProbeDB, "forever")
        local text = Probe.render(index)
        assert.equal(text, Probe.render(index))
        assert.is_true(text:find('"addons"', 1, true) < text:find('"atlases"', 1, true))
        assert.matches('"cvars": %[\n    "autoQuestWatch"\n  %]', text)
        local decoded = json.decode(text)
        assert.equal("function", decoded.symbols["C_Container.UseContainerItem"])
        assert.same({ "Huge" }, decoded.oversizedTables)
    end)
end)
