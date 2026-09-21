local Runtime = require("Tests.mock.runtime")

local function withModules(env)
    local R = env.R
    R:RegisterModule({ id = "loot.fast", requires = {}, risk = "safe", defaultEnabled = true })
    R:RegisterModule({ id = "nameplates.quest", requires = {}, risk = "visible" })
    R:RegisterModule({ id = "quest.autoAccept", requires = {}, risk = "automation" })
    return R
end

describe("module defaults", function()
    local env, R
    before_each(function()
        env = Runtime.new()
        R = withModules(env)
    end)

    it("uses each module's declared default until the player sets one", function()
        assert.is_true(R.Settings:Get("loot.fast"))
        assert.is_false(R.Settings:Get("nameplates.quest"))
        assert.is_false(R.Settings:Get("quest.autoAccept"))
    end)

    it("lets an account value override the default", function()
        R.Settings:SetAccount("loot.fast", false)
        assert.is_false(R.Settings:Get("loot.fast"))
        assert.is_nil(R.Settings:GetOverride("loot.fast"))
    end)

    it("a second character inherits the account choice with no clicks", function()
        R.Settings:SetAccount("nameplates.quest", true)
        local account = R.Settings.account
        R.Settings:Init(account, {}, "Player-second")
        assert.is_true(R.Settings:Get("nameplates.quest"))
        assert.is_true(R.Settings:Get("loot.fast"))
    end)
end)

describe("automation modules", function()
    local env, R
    before_each(function()
        env = Runtime.new()
        R = withModules(env)
    end)

    it("enables as soon as the setting is on, with no confirmation step", function()
        local module = R.moduleByID["quest.autoAccept"]
        R.Settings:SetAccount("quest.autoAccept", true)
        R.Registry:Reconcile(module)
        assert.equal("enabled", module.state)
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
