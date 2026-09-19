local Runtime = require("Tests.mock.runtime")

describe("core capabilities and registry", function()
    local env, R
    before_each(function()
        env = Runtime.new()
        R = env.R
    end)

    it("resolves namespaces without treating a partial path as an API", function()
        env.C_Test = { Present = function() end }
        assert.is_function(R.Capabilities:Resolve("C_Test.Present"))
        assert.is_nil(R.Capabilities:Resolve("C_Test.Absent"))
        assert.is_nil(R.Capabilities:Resolve("C_Test.Present.Nested"))
        assert.is_nil(R.Capabilities:Resolve("C_Test..Present"))
        assert.is_nil(R.Capabilities:Resolve("C_Test."))
        assert.is_nil(R.Capabilities:Resolve("C_Test['Present']"))
    end)

    it("names missing requirements and keeps an unsupported module unavailable", function()
        local module = R:RegisterModule({ id = "test.missing", requires = { "C_Absent.Function" } })
        assert.is_false(R.Registry:Enable(module))
        assert.equal("unavailable", module.state)
        assert.same({ "C_Absent.Function" }, module.missing)
        R.Registry:ReconcileAll()
        assert.equal("unavailable", module.state)
    end)

    it("honors a permanent unavailable reason even when all APIs exist", function()
        R.L = { RESTRICTED = "restricted" }
        local module = R:RegisterModule({ id = "test.restricted", requires = {}, unavailableReasonKey = "RESTRICTED" })
        R.Registry:ReconcileAll()
        assert.equal("unavailable", module.state)
        assert.equal("restricted", module.unavailableReason)
    end)

    it("isolates enable errors and removes partially installed handlers and timers", function()
        local bad = R:RegisterModule({ id = "test.bad", requires = {}, defaultEnabled = true })
        function bad:OnEnable()
            R.Broker:Subscribe("TEST_EVENT", function() error("should be removed") end, self)
            R:After(self, 1, function() error("should be cancelled") end)
            error("broken enable")
        end
        local good = R:RegisterModule({ id = "test.good", requires = {}, defaultEnabled = true })
        R.Registry:ReconcileAll()
        assert.equal("failed", bad.state)
        assert.equal("enabled", good.state)
        assert.is_nil(R.Broker.events.TEST_EVENT)
        assert.equal(0, env:ActiveTimers())
        assert.equal(1, #R.errors)
        assert.matches("broken enable", R.errors[1].message)
        assert.matches("mock trace", R.errors[1].message)
        R.Registry:ReconcileAll()
        assert.equal("failed", bad.state)
    end)

    it("enables disables and re-enables without event or timer residue", function()
        local calls = 0
        local module = R:RegisterModule({ id = "test.cycle", requires = {} })
        function module:OnEnable()
            R.Broker:Subscribe("TEST_EVENT", function() calls = calls + 1 end, self)
            R:After(self, 1, function() calls = calls + 100 end)
        end
        R.Registry:Enable(module)
        env:Fire("TEST_EVENT")
        R.Registry:Disable(module)
        env:Fire("TEST_EVENT")
        env:Advance(1)
        assert.equal(1, calls)
        assert.is_nil(R.Broker.events.TEST_EVENT)
        R.Registry:Enable(module)
        env:Fire("TEST_EVENT")
        assert.equal(2, calls)
        assert.equal(1, #R.Broker.events.TEST_EVENT)
    end)

    it("cleans subscriptions even if OnDisable fails", function()
        local module = R:RegisterModule({ id = "test.disable", requires = {} })
        function module:OnEnable()
            R.Broker:Subscribe("TEST_EVENT", function() end, self)
            R:After(self, 1, function() end)
        end
        function module:OnDisable() error("broken disable") end
        R.Registry:Enable(module)
        assert.is_false(R.Registry:Disable(module))
        assert.equal("failed", module.state)
        assert.is_nil(R.Broker.events.TEST_EVENT)
        assert.equal(0, env:ActiveTimers())
    end)

    it("keeps the diagnostic log bounded", function()
        for i = 1, 40 do R:RecordError({}, tostring(i) .. string.rep("x", 5000), "test") end
        assert.equal(30, #R.errors)
        assert.equal(4096, #R.errors[1].message)
        assert.equal("11", R.errors[1].message:sub(1, 2))
    end)
end)

describe("event broker and timers", function()
    local env, R
    before_each(function()
        env = Runtime.new()
        R = env.R
    end)

    it("registers one game event and dispatches by priority", function()
        local first, second, order = {}, {}, {}
        R.Broker:Subscribe("TEST_EVENT", function(_, event, value)
            assert.equal("TEST_EVENT", event)
            order[#order + 1] = value .. "second"
        end, second, nil, 0)
        R.Broker:Subscribe("TEST_EVENT", function(_, _, value) order[#order + 1] = value .. "first" end, first, nil, 10)
        assert.equal(1, #env.frames)
        env:Fire("TEST_EVENT", "value ")
        assert.same({ "value first", "value second" }, order)
        R.Broker:Unsubscribe("TEST_EVENT", first)
        assert.is_true(R.Broker.frame:IsEventRegistered("TEST_EVENT"))
        R.Broker:UnsubscribeAll(second)
        assert.is_false(R.Broker.frame:IsEventRegistered("TEST_EVENT"))
    end)

    it("never registers internal messages as game events", function()
        local owner, result = {}, nil
        R.Broker:Subscribe("REFACTOR_INTERNAL", function(_, _, value) result = value end, owner)
        assert.is_false(R.Broker.frame:IsEventRegistered("REFACTOR_INTERNAL"))
        R.Broker:Emit("REFACTOR_INTERNAL", 12)
        assert.equal(12, result)
    end)

    it("throttles with the latest trailing payload and cancels on unsubscribe", function()
        local owner, values = {}, {}
        R.Broker:Subscribe("TEST_EVENT", function(_, _, value) values[#values + 1] = value end, owner, 1)
        env:Fire("TEST_EVENT", "first")
        env:Advance(0.1)
        env:Fire("TEST_EVENT", "discard")
        env:Advance(0.1)
        env:Fire("TEST_EVENT", "latest")
        assert.equal(1, env:ActiveTimers())
        env:Advance(0.8)
        assert.same({ "first", "latest" }, values)
        env:Fire("TEST_EVENT", "cancelled")
        R.Broker:UnsubscribeAll(owner)
        env:Advance(2)
        assert.same({ "first", "latest" }, values)
        assert.equal(0, env:ActiveTimers())
        assert.is_nil(R.timers[owner])
    end)

    it("preserves nil arguments in immediate and trailing events", function()
        local owner, counts = {}, {}
        R.Broker:Subscribe("TEST_EVENT", function(_, _, ...)
            counts[#counts + 1] = select("#", ...)
            assert.is_nil((...))
        end, owner, 1)
        env:Fire("TEST_EVENT", nil, "second", nil)
        env:Fire("TEST_EVENT", nil, "second", nil)
        env:Advance(1)
        assert.same({ 3, 3 }, counts)
    end)

    it("isolates failed event handlers without skipping healthy subscribers", function()
        local goodCalls = 0
        local bad = R:RegisterModule({ id = "test.badEvent", requires = {} })
        local good = R:RegisterModule({ id = "test.goodEvent", requires = {} })
        function bad:OnEnable()
            R.Broker:Subscribe("TEST_EVENT", function() error("bad event") end, self, nil, 1)
        end
        function good:OnEnable()
            R.Broker:Subscribe("TEST_EVENT", function() goodCalls = goodCalls + 1 end, self)
        end
        R.Registry:Enable(bad)
        R.Registry:Enable(good)
        env:Fire("TEST_EVENT")
        assert.equal("failed", bad.state)
        assert.equal("enabled", good.state)
        assert.equal(1, goodCalls)
        assert.equal(1, #R.Broker.events.TEST_EVENT)
    end)

    it("isolates timer errors and cancels remaining work for the failed module", function()
        local calls = 0
        local module = R:RegisterModule({ id = "test.timer", requires = {} })
        R.Registry:Enable(module)
        R:After(module, 1, function() error("timer failed") end)
        R:After(module, 2, function() calls = calls + 1 end)
        env:Advance(3)
        assert.equal("failed", module.state)
        assert.equal(0, calls)
        assert.equal(1, #R.errors)
    end)

    it("allows a callback to remove another subscription safely", function()
        local owner, removed, calls = {}, {}, 0
        R.Broker:Subscribe("TEST_EVENT", function() R.Broker:UnsubscribeAll(removed) end, owner, nil, 1)
        R.Broker:Subscribe("TEST_EVENT", function() calls = calls + 1 end, removed)
        env:Fire("TEST_EVENT")
        assert.equal(0, calls)
    end)
end)

describe("settings resolution and profiles", function()
    local env, R, settings
    before_each(function()
        env = Runtime.new()
        R, settings = env.R, env.R.Settings
    end)

    it("resolves all 54 combinations of character profile account and default", function()
        local states = { "inherit", true, false }
        local checked = 0
        for _, default in ipairs({ true, false }) do
            for _, accountValue in ipairs(states) do
                for _, profileValue in ipairs(states) do
                    for _, overrideValue in ipairs(states) do
                        local account = accountValue ~= "inherit" and { ["test.setting"] = accountValue } or {}
                        local profile = profileValue ~= "inherit" and { ["test.setting"] = profileValue } or {}
                        local override = overrideValue ~= "inherit" and { ["test.setting"] = overrideValue } or {}
                        settings:Init({ modules = account, profiles = { Test = profile },
                            assignments = { ["Player-test"] = "Test" } }, { overrides = override }, "Player-test")
                        settings:RegisterDefaults("test.setting", default)
                        local expected = default
                        if accountValue ~= "inherit" then expected = accountValue end
                        if profileValue ~= "inherit" then expected = profileValue end
                        if overrideValue ~= "inherit" then expected = overrideValue end
                        assert.equal(expected, settings:Get("test.setting"))
                        checked = checked + 1
                    end
                end
            end
        end
        assert.equal(54, checked)
    end)

    it("inherits account values on another GUID and supports explicit false", function()
        settings:SetAccount("test.setting", true)
        settings:SetOverride("test.setting", false)
        assert.is_false(settings:Get("test.setting"))
        settings:Init(settings.account, {}, "Player-other")
        assert.is_true(settings:Get("test.setting"))
        settings:SetOverride("test.setting", false)
        settings:SetOverride("test.setting", nil)
        assert.is_nil(settings:GetOverride("test.setting"))
        assert.is_true(settings:Get("test.setting"))
    end)

    it("implements profile CRUD without stale GUID assignments or table aliasing", function()
        local values = { ["test.setting"] = true }
        assert.is_true(settings:CreateProfile("Levelling", values))
        values["test.setting"] = false
        assert.is_true(settings:AssignProfile("Levelling"))
        assert.is_true(settings:Get("test.setting"))
        local read = settings:GetProfile("Levelling")
        read["test.setting"] = false
        assert.is_true(settings:Get("test.setting"))
        settings:UpdateProfile("Levelling", { ["test.setting"] = false })
        assert.is_false(settings:Get("test.setting"))
        settings:AssignProfile("Levelling", "Player-other")
        assert.is_true(settings:DeleteProfile("Levelling"))
        assert.same({}, settings.account.assignments)
        assert.is_false(settings:AssignProfile("Levelling"))
    end)

    it("round trips sorted base64 exports and rejects overwrite by default", function()
        local values = { ["test.one"] = true, ["test.two"] = false }
        settings:CreateProfile("Test profile", values)
        local encoded = settings:ExportProfile("Test profile")
        assert.matches("^[A-Za-z0-9+/=]+$", encoded)
        assert.is_false(settings:ImportProfile(encoded))
        local ok, name = settings:ImportProfile(encoded, "Copy")
        assert.is_true(ok)
        assert.equal("Copy", name)
        assert.same(values, settings:GetProfile("Copy"))
        assert.equal(encoded, settings:ExportProfile("Test profile"))
    end)

    it("rejects malformed oversized and executable imports without invoking code", function()
        local payloads = {
            "", "RF1", "!!!!", "AAAA=AAA", "AB==", "AAB=", string.rep("A", 32772),
            "cmV0dXJuIHt9", -- return {}
            "UkYxClgKdGVzdC5vbmU9dHJ1ZQo=", -- invalid non-boolean line
            "UkYxClgKdGVzdC5vbmU9MQp0ZXN0Lm9uZT0wCg==", -- duplicate setting
            "UkYxClgKX0cub3duZWQ9MQo=", -- invalid setting id
        }
        for _, payload in ipairs(payloads) do
            assert.is_false(settings:ImportProfile(payload))
        end
        assert.same({}, settings.account.profiles)
        assert.is_nil(env.owned)
    end)

    it("validates account options and supplies conservative defaults", function()
        assert.equal(100, settings:GetOption("repairCapGold"))
        assert.equal("CTRL", settings:GetOption("killSwitch"))
        assert.same({}, settings:GetOption("neverSellIDs"))
        assert.is_false(settings:SetOption("repairCapGold", -1))
        assert.is_false(settings:SetOption("repairCapGold", 0 / 0))
        assert.is_false(settings:SetOption("killSwitch", "NOPE"))
        assert.is_false(settings:SetOption("neverSellIDs", { [1.5] = true }))
        assert.is_true(settings:SetOption("neverSellIDs", { [123] = true }))
        assert.is_true(settings:GetOption("neverSellIDs")[123])
        assert.equal("SHIFT", settings:GetOption("gossipLearnModifier"))
        assert.is_false(settings:SetOption("gossipLearnModifier", "NOPE"))
        assert.is_true(settings:SetOption("gossipLearnModifier", "ALT"))
        assert.is_false(settings:SetOption("gossipLearned", { Player = { [1] = 1 } }))
        assert.is_false(settings:SetOption("gossipLearned", { Creature = { [1.5] = 1 } }))
        assert.is_false(settings:SetOption("gossipLearned", { Creature = { [1] = "x" } }))
        assert.is_false(settings:SetOption("gossipLearned", { Creature = 5 }))
        assert.is_true(settings:SetOption("gossipLearned", { Creature = { [38038] = 1002 }, GameObject = {} }))
        assert.equal(1002, settings:GetOption("gossipLearned").Creature[38038])
    end)

    it("notifies about mutations and keeps getters safe before initialization", function()
        local calls, owner = {}, {}
        R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", function(_, _, id) calls[#calls + 1] = id end, owner)
        settings:SetAccount("test.setting", true)
        settings:SetOverride("test.setting", false)
        assert.same({ "test.setting", "test.setting" }, calls)
        settings.account, settings.character = nil, nil
        assert.is_false(settings:Get("test.unknown"))
        assert.is_nil(settings:GetOverride("test.unknown"))
        assert.is_false(settings:SetAccount("test.setting", true))
    end)
end)

describe("pools", function()
    it("resets reused objects and ignores foreign or duplicate release", function()
        local R = Runtime.new().R
        local pool = R.Pools:CreateTablePool()
        local first = pool:Acquire()
        first.value = 12
        assert.is_false(pool:Release({}))
        assert.is_true(pool:Release(first))
        assert.is_false(pool:Release(first))
        local reused = pool:Acquire()
        assert.equal(first, reused)
        assert.is_nil(reused.value)
        pool:Acquire()
        assert.equal(2, pool.count)
        pool:ReleaseAll()
        assert.same({}, pool.active)
        assert.equal(2, #pool.free)
    end)
end)
