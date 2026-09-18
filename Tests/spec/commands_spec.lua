local Runtime = require("Tests.mock.runtime")

local function base()
    local env = Runtime.new()
    env:Load("Locales/Commands.enUS.lua")
    env:Load("Core/Commands.lua")
    env.control, env.shift, env.alt = false, false, false
    env.IsControlKeyDown = function() return env.control end
    env.IsShiftKeyDown = function() return env.shift end
    env.IsAltKeyDown = function() return env.alt end
    return env
end

describe("pause modifier", function()
    it("follows the configured key rather than a hard-coded one", function()
        local env = base()
        local R = env.R
        env.control, env.shift = true, false
        assert.is_true(R:Paused())
        R.Settings:SetOption("killSwitch", "SHIFT")
        assert.is_false(R:Paused())
        env.shift = true
        assert.is_true(R:Paused())
    end)

    it("reports not paused when the client does not expose the key check", function()
        local env = base()
        env.IsControlKeyDown = nil
        assert.is_false(env.R:Paused())
    end)
end)

describe("slash dispatch", function()
    it("opens the window on a bare command and never prints", function()
        local env = base()
        local toggled = 0
        env.R.UI = { Toggle = function() toggled = toggled + 1 end }
        assert.is_nil(env.R.Commands:Dispatch("  "))
        assert.equal(1, toggled)
    end)

    it("reports recorded errors newest last and then forgets them", function()
        local env = base()
        local R = env.R
        assert.same({ R.L.CMD_NO_ERRORS }, R.Commands:Dispatch("errors"))
        R:RecordError({ id = "vendor.autoSell" }, "boom\nstack line", "OnEnable")
        local lines = R.Commands:Dispatch("ERRORS")
        assert.matches("1 recorded", lines[1])
        assert.matches("vendor.autoSell", lines[2])
        assert.matches("OnEnable", lines[2])
        assert.matches("boom", lines[3])
        assert.matches("stack line", lines[4])
        assert.same({ R.L.CMD_ERRORS_CLEARED }, R.Commands:Dispatch("errors clear"))
        assert.equal(0, #R.errors)
    end)

    it("answers an unknown command with help", function()
        local env = base()
        local lines = env.R.Commands:Dispatch("wat")
        assert.equal(env.R.L.CMD_HELP_HEADER, lines[1])
        assert.equal(6, #lines)
    end)

    it("says so when nothing is listening for the loot feed test", function()
        local env = base()
        assert.same({ env.R.L.CMD_LOOT_TEST_OFF }, env.R.Commands:Dispatch("loottest"))
        local fired = 0
        env.R.Broker:Subscribe("REFACTOR_LOOT_TEST", function() fired = fired + 1 end, {})
        assert.is_nil(env.R.Commands:Dispatch("loottest"))
        assert.equal(1, fired)
    end)
end)

describe("login bootstrap", function()
    local function login(env)
        env:Load("Core/Bootstrap.lua")
        env.R.UI = { Initialize = function() end, Toggle = function() end, ShowFirstRun = function() end }
        env:Fire("PLAYER_LOGIN")
    end

    it("initializes saved variables, modules and slash commands once", function()
        local env = base()
        local R = env.R
        local module = R:RegisterModule({ id = "test.login", requires = {}, defaultEnabled = true })
        login(env)
        assert.equal("enabled", module.state)
        assert.is_table(env.RefactorDB)
        assert.is_table(env.RefactorCharDB)
        assert.equal("Player-test", R.Settings.guid)
        assert.equal(0, #R.errors)
        assert.equal("/refactor", env.SLASH_REFACTOR1)
        assert.equal("/rf", env.SLASH_REFACTOR2)
        assert.is_function(env.SlashCmdList.REFACTOR)
        assert.is_nil(R.Broker.events.PLAYER_LOGIN)
    end)

    it("leaves the short alias alone when another addon answers it", function()
        local env = base()
        env.hash_SlashCmdList = { ["/RF"] = "NEIGHBOUR" }
        login(env)
        assert.is_nil(env.SLASH_REFACTOR2)
    end)

    it("prints dispatch output through the chat frame", function()
        local env = base()
        login(env)
        env.SlashCmdList.REFACTOR("errors")
        assert.equal(1, #env.messages)
        assert.matches("No errors recorded", env.messages[1])
    end)

    it("re-reconciles modules when a setting changes", function()
        local env = base()
        local R = env.R
        local module = R:RegisterModule({ id = "test.reconcile", requires = {} })
        login(env)
        assert.equal("disabled", module.state)
        R.Settings:SetAccount("test.reconcile", true)
        assert.equal("enabled", module.state)
    end)
end)
