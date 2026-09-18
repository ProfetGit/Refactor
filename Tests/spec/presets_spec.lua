local Runtime = require("Tests.mock.runtime")

local function withModules(env)
    local R = env.R
    R:RegisterModule({ id = "loot.fast", requires = {}, tier = "minimal", risk = "safe" })
    R:RegisterModule({ id = "vendor.sell", requires = {}, tier = "standard", risk = "safe" })
    R:RegisterModule({ id = "nameplates.quest", requires = {}, tier = "full", risk = "visible" })
    R:RegisterModule({ id = "quest.autoAccept", requires = {}, tier = "standard", risk = "automation" })
    R:RegisterModule({ id = "misc.manual", requires = {}, tier = "manual", risk = "safe" })
    return R
end

describe("presets", function()
    local env, R
    before_each(function()
        env = Runtime.new()
        R = withModules(env)
    end)

    it("nests the tiers so Full contains Standard contains Minimal", function()
        assert.same({ "loot.fast" }, R.Presets:Members("minimal"))
        assert.same({ "loot.fast", "vendor.sell" }, R.Presets:Members("standard"))
        assert.same({ "loot.fast", "nameplates.quest", "vendor.sell" }, R.Presets:Members("full"))
    end)

    it("never puts automation in a preset, Full included", function()
        for _, preset in ipairs(R.Presets.order) do
            for _, id in ipairs(R.Presets:Members(preset)) do
                assert.is_not.equal("quest.autoAccept", id)
            end
        end
    end)

    it("leaves manual-tier modules out of every preset", function()
        assert.equal(3, R.Presets:Count("full"))
    end)

    it("writes account defaults, not character overrides", function()
        R.Presets:Apply("standard")
        assert.is_true(R.Settings:Get("vendor.sell"))
        assert.is_false(R.Settings:Get("nameplates.quest"))
        assert.is_nil(R.Settings:GetOverride("vendor.sell"))
        assert.is_false(R.Settings:IsFirstRun())
    end)

    it("turns everything off when the player chooses to browse instead", function()
        R.Presets:Apply(nil)
        assert.is_false(R.Settings:Get("loot.fast"))
        assert.is_false(R.Settings:IsFirstRun())
    end)

    it("a second character inherits the account choice with no clicks", function()
        R.Presets:Apply("standard")
        local account = env.RefactorDB or R.Settings.account
        -- A fresh character means a fresh per-character table and the same account table.
        R.Settings:Init(account, {}, "Player-second")
        assert.is_true(R.Settings:Get("vendor.sell"))
        assert.is_false(R.Settings:Get("nameplates.quest"))
        assert.is_false(R.Settings:IsFirstRun())
    end)
end)

describe("automation confirmation", function()
    local env, R
    before_each(function()
        env = Runtime.new()
        R = withModules(env)
    end)

    it("refuses to enable an automation module until it is confirmed once", function()
        local module = R.moduleByID["quest.autoAccept"]
        R.Settings:SetAccount("quest.autoAccept", true)
        R.Registry:Reconcile(module)
        assert.equal("unconfirmed", module.state)

        R.Settings:Confirm("quest.autoAccept", true)
        R.Registry:Reconcile(module)
        assert.equal("enabled", module.state)
    end)

    it("keeps the confirmation once given, and forgets it when withdrawn", function()
        R.Settings:Confirm("quest.autoAccept", true)
        assert.is_true(R.Settings:IsConfirmed("quest.autoAccept"))
        R.Settings:Confirm("quest.autoAccept", false)
        assert.is_false(R.Settings:IsConfirmed("quest.autoAccept"))
    end)

    it("returns an unconfirmed module to disabled when the setting goes off", function()
        local module = R.moduleByID["quest.autoAccept"]
        R.Settings:SetAccount("quest.autoAccept", true)
        R.Registry:Reconcile(module)
        R.Settings:SetAccount("quest.autoAccept", false)
        R.Registry:Reconcile(module)
        assert.equal("disabled", module.state)
    end)
end)

describe("price chain", function()
    local env, Price
    before_each(function()
        env = Runtime.new()
        env:Load("Libs/LibRefactorPrice-1.0/LibRefactorPrice-1.0.lua")
        Price = env.LibStub("LibRefactorPrice-1.0")
        env.C_Item = { GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 120 end }
    end)

    it("uses the vendor price on a fresh install and says so", function()
        local value, source = Price:Get("item:1")
        assert.equal(120, value)
        assert.equal("vendor", source)
    end)

    it("multiplies by quantity", function()
        assert.equal(600, Price:Get("item:1", 5))
    end)

    it("prefers an opted-in provider ahead of the vendor", function()
        Price:RegisterProvider("auctionator", 200, function() return 5000 end)
        assert.equal(120, Price:Get("item:1"))
        Price:SetEnabled("auctionator", true)
        local value, source = Price:Get("item:1")
        assert.equal(5000, value)
        assert.equal("auctionator", source)
    end)

    it("falls through a provider that errors or has no answer", function()
        Price:RegisterProvider("tsm", 100, function() error("no database") end)
        Price:SetEnabled("tsm", true)
        assert.equal(120, Price:Get("item:1"))
    end)

    it("returns nothing rather than zero when no provider answers", function()
        env.C_Item.GetItemInfo = function() return nil end
        assert.is_nil(Price:Get("item:1"))
    end)
end)
